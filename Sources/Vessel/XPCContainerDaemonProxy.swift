import Foundation
import VesselXPC
import Containerization

// Since VesselXPCStreamDelegate is @objc, we must subclass NSObject
final class StreamDelegateProxy: NSObject, VesselXPCStreamDelegate, @unchecked Sendable {
    private let onEventBlock: @Sendable (Data) -> Void
    private let onCompleteBlock: @Sendable (Error?) -> Void

    private func writeLog(_ msg: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/ui.log")
        let data = "[\(Date())] \(msg)\n".data(using: .utf8)!
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }

    init(onEvent: @escaping @Sendable (Data) -> Void, onComplete: @escaping @Sendable (Error?) -> Void) {
        self.onEventBlock = onEvent
        self.onCompleteBlock = onComplete
        super.init()
    }

    func onEvent(payload: Data) {
        writeLog("StreamDelegateProxy received onEvent: \(payload.count) bytes")
        onEventBlock(payload)
    }

    func onComplete(error: Error?) {
        writeLog("StreamDelegateProxy received onComplete: \(String(describing: error))")
        onCompleteBlock(error)
    }
}

final class ContinuationWrapper<T: Sendable>: @unchecked Sendable {
    var continuation: CheckedContinuation<T, Error>?
    let lock = NSLock()
    var retainedObjects: [Any] = []
    
    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }
    
    func retain(_ object: Any) {
        lock.lock()
        defer { lock.unlock() }
        retainedObjects.append(object)
    }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.resume(returning: value)
        continuation = nil
        retainedObjects.removeAll()
    }
    
    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.resume(throwing: error)
        continuation = nil
        retainedObjects.removeAll()
    }
}

public final class ContainerDaemon: @unchecked Sendable {
    private let connection: NSXPCConnection
    private let connectionLock = NSLock()
    private var activeStreamDelegates: [StreamDelegateProxy] = []

    public init() {
        connection = NSXPCConnection(serviceName: "com.vessel.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: VesselXPCProtocol.self)

        connection.remoteObjectInterface = NSXPCInterface(with: VesselXPCProtocol.self)
        let streamInterface = NSXPCInterface(with: VesselXPCStreamDelegate.self)

        connection.remoteObjectInterface?.setInterface(streamInterface, for: #selector(VesselXPCProtocol.openStream(command:payload:delegate:)), argumentIndex: 2, ofReply: false)

        connection.interruptionHandler = { [weak self] in
            self?.handleConnectionDrop()
        }

        connection.invalidationHandler = { [weak self] in
            self?.handleConnectionDrop()
        }

        connection.resume()
    }

    private func handleConnectionDrop() {
        connectionLock.lock()
        let delegates = activeStreamDelegates
        activeStreamDelegates.removeAll()
        connectionLock.unlock()

        let error = NSError(domain: "Vessel", code: 503, userInfo: [NSLocalizedDescriptionKey: "XPC Connection lost"])
        for delegate in delegates {
            delegate.onComplete(error: error)
        }
    }

    private func trackDelegate(_ delegate: StreamDelegateProxy) {
        connectionLock.lock()
        activeStreamDelegates.append(delegate)
        connectionLock.unlock()
    }

    private func untrackDelegate(_ delegate: StreamDelegateProxy) {
        connectionLock.lock()
        activeStreamDelegates.removeAll { $0 === delegate }
        connectionLock.unlock()
    }

    private var proxy: VesselXPCProtocol {
        connection.remoteObjectProxyWithErrorHandler { error in
            print("XPC Connection error: \(error)")
        } as! VesselXPCProtocol
    }

    private func sendCommand<T: Decodable & Sendable>(command: String, payload: [String: Any]) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await withCheckedThrowingContinuation { continuation in
            let wrapper = ContinuationWrapper(continuation)
            
            let localProxy = connection.remoteObjectProxyWithErrorHandler { error in
                wrapper.resume(throwing: error)
            } as! VesselXPCProtocol

            localProxy.sendCommand(command: command, payload: data) { responseData, error in
                if let error = error {
                    wrapper.resume(throwing: error)
                    return
                }
                guard let responseData = responseData else {
                    wrapper.resume(throwing: NSError(domain: "Vessel", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                    return
                }
                do {
                    let decoder = JSONDecoder()
                    let result = try decoder.decode(T.self, from: responseData)
                    wrapper.resume(returning: result)
                } catch {
                    wrapper.resume(throwing: error)
                }
            }
        }
    }

    private func sendCommandRaw(command: String, payload: [String: Any]) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await withCheckedThrowingContinuation { continuation in
            let wrapper = ContinuationWrapper(continuation)
            
            let localProxy = connection.remoteObjectProxyWithErrorHandler { error in
                wrapper.resume(throwing: error)
            } as! VesselXPCProtocol

            localProxy.sendCommand(command: command, payload: data) { responseData, error in
                if let error = error {
                    wrapper.resume(throwing: error)
                    return
                }
                guard let responseData = responseData else {
                    wrapper.resume(throwing: NSError(domain: "Vessel", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                    return
                }
                wrapper.resume(returning: responseData)
            }
        }
    }

    private func sendCommandNoWait(command: String, payload: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            proxy.sendCommand(command: command, payload: data) { _, _ in }
        }
    }

    public func fetchActiveContainers() async throws -> [VesselContainer] {
        return try await sendCommand(command: "fetchActiveContainers", payload: [:])
    }

    public func fetchActiveWorkloads() async throws -> [VesselWorkload] {
        return try await sendCommand(command: "fetchActiveWorkloads", payload: [:])
    }

    public func getContainerIP(containerId: String) -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String? = nil
        if let data = try? JSONSerialization.data(withJSONObject: ["id": containerId]) {
            let localProxy = connection.remoteObjectProxyWithErrorHandler { _ in
                semaphore.signal()
            } as! VesselXPCProtocol
            localProxy.sendCommand(command: "getContainerIP", payload: data) { responseData, _ in
                if let data = responseData,
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    result = dict["ip"]
                }
                semaphore.signal()
            }
        } else {
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    public func fetchDomainRules() -> [DomainRule] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [DomainRule] = []
        let data = try! JSONSerialization.data(withJSONObject: [:])
        let localProxy = connection.remoteObjectProxyWithErrorHandler { _ in
            semaphore.signal()
        } as! VesselXPCProtocol
        localProxy.sendCommand(command: "fetchDomainRules", payload: data) { responseData, _ in
            if let data = responseData,
               let rules = try? JSONDecoder().decode([DomainRule].self, from: data) {
                result = rules
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    public func addDomainRule(_ rule: DomainRule) {
        if let encoded = try? JSONEncoder().encode(rule),
           let dict = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
            sendCommandNoWait(command: "addDomainRule", payload: dict)
        }
    }

    public func removeDomainRule(id: UUID) {
        sendCommandNoWait(command: "removeDomainRule", payload: ["id": id.uuidString])
    }

    public func startPod(yamlPath: URL) async throws {
        // Read yaml to parse volumes and resolve bookmarks
        var bookmarks: [String: Data] = [:]
        do {
            let yamlString = try String(contentsOf: yamlPath, encoding: .utf8)
            let projectName = yamlPath.deletingPathExtension().lastPathComponent
            let project = try ComposeParser.parse(yaml: yamlString, projectName: projectName)

            for service in project.services {
                for volumeStr in service.volumes {
                    let parts = volumeStr.split(separator: ":", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        let hostPath = parts[0]
                        if hostPath.hasPrefix("/") || hostPath.hasPrefix("~") || hostPath.hasPrefix(".") {
                            var actualHostPath = NSString(string: hostPath).expandingTildeInPath
                            if hostPath.hasPrefix("./") {
                                actualHostPath = yamlPath.deletingLastPathComponent().path + "/" + String(hostPath.dropFirst(2))
                            } else if hostPath.hasPrefix("../") {
                                let absUrl = URL(fileURLWithPath: hostPath, relativeTo: yamlPath.deletingLastPathComponent())
                                actualHostPath = absUrl.path
                            } else if hostPath == "." {
                                actualHostPath = yamlPath.deletingLastPathComponent().path
                            }
                            let resolvedHostPath = URL(fileURLWithPath: actualHostPath).resolvingSymlinksInPath().path
                            try await BookmarkManager.shared.resolveAndAccess(path: resolvedHostPath)
                            if let data = BookmarkManager.shared.getBookmarkData(for: resolvedHostPath) {
                                bookmarks[resolvedHostPath] = data
                            }
                        }
                    }
                }
            }
        } catch {
            print("Failed to parse Compose for volumes: \(error)")
        }

        let bookmarksDict = bookmarks.mapValues { $0.base64EncodedString() }
        _ = try await sendCommandRaw(command: "startPod", payload: ["yamlPath": yamlPath.path, "bookmarks": bookmarksDict])
    }

    public func start(containerId: String, config: ContainerStartConfiguration) async throws {
        // 🛡️ Sentinel: Ensure App Sandbox access to host paths using Security-Scoped Bookmarks
        var bookmarks: [String: Data] = [:]
        for volume in config.volumes {
            try await BookmarkManager.shared.resolveAndAccess(path: volume.host)
            if let data = BookmarkManager.shared.getBookmarkData(for: volume.host) {
                bookmarks[volume.host] = data
            }
        }
        let bookmarksDict = bookmarks.mapValues { $0.base64EncodedString() }

        let encoder = JSONEncoder()
        let configData = try encoder.encode(config)

        let payload: [String: Any] = [
            "containerId": containerId,
            "config": try JSONSerialization.jsonObject(with: configData),
            "bookmarks": bookmarksDict
        ]
        _ = try await sendCommandRaw(command: "startFull", payload: payload)
    }

    public func start(containerId: String) async throws {
        var bookmarks: [String: Data] = [:]
        if let workloads = try? await fetchActiveWorkloads() {
            for workload in workloads {
                if case .container(let vesselContainer) = workload, vesselContainer.id == containerId {
                    for volume in vesselContainer.volumes {
                        try await BookmarkManager.shared.resolveAndAccess(path: volume.host)
                        if let data = BookmarkManager.shared.getBookmarkData(for: volume.host) {
                            bookmarks[volume.host] = data
                        }
                    }
                    break
                }
            }
        }
        let bookmarksDict = bookmarks.mapValues { $0.base64EncodedString() }

        _ = try await sendCommandRaw(command: "start", payload: ["id": containerId, "bookmarks": bookmarksDict])
    }

    public func listFiles(in path: String, containerId: String) async throws -> String {
        let resp: [String: String] = try await sendCommand(command: "listFiles", payload: ["path": path, "id": containerId])
        return resp["files"] ?? ""
    }

    public func downloadFile(containerId: String, path: String, to destinationURL: URL) async throws {
        _ = try await sendCommandRaw(command: "downloadFile", payload: ["id": containerId, "path": path, "dest": destinationURL.path])
    }

    public func uploadFile(containerId: String, from sourceURL: URL, to destinationPath: String) async throws {
        _ = try await sendCommandRaw(command: "uploadFile", payload: ["id": containerId, "source": sourceURL.path, "dest": destinationPath])
    }

    public func startStatsStream(containerId: String) async throws -> AsyncStream<StatsModel> {
        let data = try JSONSerialization.data(withJSONObject: ["id": containerId])
        var streamContinuation: AsyncStream<StatsModel>.Continuation?
        let stream = AsyncStream<StatsModel> { cont in
            streamContinuation = cont
        }
        guard let continuation = streamContinuation else { return stream }

        let delegate = StreamDelegateProxy(onEvent: { eventData in
            if let stat = try? JSONDecoder().decode(StatsModel.self, from: eventData) {
                continuation.yield(stat)
            }
        }, onComplete: { error in
            continuation.finish()
        })

        continuation.onTermination = { [weak self, weak delegate] _ in
            if let delegate = delegate {
                self?.untrackDelegate(delegate)
            }
        }

        self.trackDelegate(delegate)

        let localProxy = connection.remoteObjectProxyWithErrorHandler { [weak self, weak delegate] _ in
            if let delegate = delegate {
                self?.untrackDelegate(delegate)
            }
            continuation.finish()
        } as! VesselXPCProtocol

        localProxy.openStream(command: "startStatsStream", payload: data, delegate: delegate)
        return stream
    }

    public func streamLogs(for id: String) -> AsyncStream<String> {
        var streamContinuation: AsyncStream<String>.Continuation?
        let stream = AsyncStream<String> { cont in
            streamContinuation = cont
        }
        let data = try! JSONSerialization.data(withJSONObject: ["id": id])
        guard let continuation = streamContinuation else { return stream }

        let delegate = StreamDelegateProxy(onEvent: { eventData in
            if let str = String(data: eventData, encoding: .utf8) {
                continuation.yield(str)
            }
        }, onComplete: { error in
            continuation.finish()
        })

        continuation.onTermination = { [weak self, weak delegate] _ in
            if let delegate = delegate {
                self?.untrackDelegate(delegate)
            }
        }

        self.trackDelegate(delegate)

        let localProxy = connection.remoteObjectProxyWithErrorHandler { [weak self, weak delegate] _ in
            if let delegate = delegate {
                self?.untrackDelegate(delegate)
            }
            continuation.finish()
        } as! VesselXPCProtocol

        localProxy.openStream(command: "streamLogs", payload: data, delegate: delegate)
        return stream
    }

    public func pauseAll() async throws {
        _ = try await sendCommandRaw(command: "pauseAll", payload: [:])
    }

    public func resumeAll() async throws {
        _ = try await sendCommandRaw(command: "resumeAll", payload: [:])
    }

    public func stop(containerId: String, force: Bool = false) async throws {
        _ = try await sendCommandRaw(command: "stop", payload: ["id": containerId, "force": force])
    }

    public func delete(containerId: String) async throws {
        _ = try await sendCommandRaw(command: "delete", payload: ["id": containerId])
    }

    public func fetchImages() async throws -> [VesselImage] {
        return try await sendCommand(command: "fetchImages", payload: [:])
    }

    public func pullImage(reference: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["ref": reference])
        var trackedDelegate: StreamDelegateProxy? = nil
        
        defer {
            if let delegate = trackedDelegate {
                self.untrackDelegate(delegate)
            }
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let wrapper = ContinuationWrapper(continuation)

            let delegate = StreamDelegateProxy(onEvent: { eventData in
                if let dict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] {
                    if let pct = dict["progress"] as? Double {
                        progress(pct)
                    }
                }
            }, onComplete: { error in
                if let error = error {
                    wrapper.resume(throwing: error)
                } else {
                    wrapper.resume(returning: ())
                }
            })
            
            trackedDelegate = delegate
            wrapper.retain(delegate)
            self.trackDelegate(delegate)

            let localProxy = connection.remoteObjectProxyWithErrorHandler { error in
                wrapper.resume(throwing: error)
            } as! VesselXPCProtocol

            localProxy.openStream(command: "pullImage", payload: data, delegate: delegate)
        }
    }

    public func deleteImage(reference: String) async throws {
        _ = try await sendCommandRaw(command: "deleteImage", payload: ["ref": reference])
    }

    public func execShell(containerId: String, stdin: Containerization.ReaderStream, stdout: Containerization.Writer) async throws -> String {
        let streamId = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["id": containerId, "streamId": streamId])

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let wrapper = ContinuationWrapper(continuation)

            final class DelegateHolder: @unchecked Sendable {
                weak var delegate: StreamDelegateProxy?
            }
            let holder = DelegateHolder()

            let delegate = StreamDelegateProxy(onEvent: { eventData in
                try? stdout.write(eventData)
            }, onComplete: { [weak self] error in
                if let error = error {
                    // Try to resume if it hasn't started yet
                    wrapper.resume(throwing: error)
                }
                if let d = holder.delegate {
                    self?.untrackDelegate(d)
                }
            })
            holder.delegate = delegate

            wrapper.retain(delegate)
            self.trackDelegate(delegate)

            let localProxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                self?.untrackDelegate(delegate)
                wrapper.resume(throwing: error)
            } as! VesselXPCProtocol
            
            // Start the reading task to consume stdin and send to XPC
            let conn = connection
            Task {
                let streamProxy = conn.remoteObjectProxyWithErrorHandler { _ in } as! VesselXPCProtocol
                for await chunk in stdin.stream() {
                    streamProxy.writeToStream(streamId: streamId, payload: chunk)
                }
            }

            localProxy.openStream(command: "execShell", payload: data, delegate: delegate)
            
            // Return streamId immediately so UI considers shell started
            wrapper.resume(returning: streamId)
        }
    }
}
