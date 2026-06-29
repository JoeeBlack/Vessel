import Foundation
import VesselXPC
import Containerization

// Since VesselXPCStreamDelegate is @objc, we must subclass NSObject
class StreamDelegateProxy: NSObject, VesselXPCStreamDelegate {
    private let onEventBlock: (Data) -> Void
    private let onCompleteBlock: (Error?) -> Void

    init(onEvent: @escaping (Data) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.onEventBlock = onEvent
        self.onCompleteBlock = onComplete
    }

    func onEvent(payload: Data) {
        onEventBlock(payload)
    }

    func onComplete(error: Error?) {
        onCompleteBlock(error)
    }
}

public final class ContainerDaemon: @unchecked Sendable {
    private let connection: NSXPCConnection

    public init() {
        connection = NSXPCConnection(machServiceName: "com.vessel.daemon.xpc", options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: VesselXPCProtocol.self)

        let expectedClasses = NSSet(objects: NSString.self, NSData.self, NSDictionary.self, NSArray.self, NSNumber.self)
        let streamInterface = NSXPCInterface(with: VesselXPCStreamDelegate.self)

        connection.remoteObjectInterface?.setInterface(streamInterface, for: #selector(VesselXPCProtocol.openStream(command:payload:delegate:)), argumentIndex: 2, ofReply: false)

        connection.resume()
    }

    private var proxy: VesselXPCProtocol {
        connection.remoteObjectProxyWithErrorHandler { error in
            print("XPC Connection error: \(error)")
        } as! VesselXPCProtocol
    }

    private func sendCommand<T: Decodable>(command: String, payload: [String: Any]) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await withCheckedThrowingContinuation { continuation in
            proxy.sendCommand(command: command, payload: data) { responseData, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let responseData = responseData else {
                    continuation.resume(throwing: NSError(domain: "Vessel", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                    return
                }
                do {
                    let decoder = JSONDecoder()
                    let result = try decoder.decode(T.self, from: responseData)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendCommandRaw(command: String, payload: [String: Any]) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await withCheckedThrowingContinuation { continuation in
            proxy.sendCommand(command: command, payload: data) { responseData, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let responseData = responseData else {
                    continuation.resume(throwing: NSError(domain: "Vessel", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                    return
                }
                continuation.resume(returning: responseData)
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
            proxy.sendCommand(command: "getContainerIP", payload: data) { responseData, _ in
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
        proxy.sendCommand(command: "fetchDomainRules", payload: data) { responseData, _ in
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
        _ = try await sendCommandRaw(command: "startPod", payload: ["yamlPath": yamlPath.path])
    }

    public func start(containerId: String, config: ContainerStartConfiguration) async throws {

        let encoder = JSONEncoder()
        let configData = try encoder.encode(config)

        let payload: [String: Any] = [
            "containerId": containerId,
            "config": try JSONSerialization.jsonObject(with: configData)
        ]
        _ = try await sendCommandRaw(command: "startFull", payload: payload)
    }

    public func start(containerId: String) async throws {
        _ = try await sendCommandRaw(command: "start", payload: ["id": containerId])
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
        let (stream, continuation) = AsyncStream<StatsModel>.makeStream()

        let delegate = StreamDelegateProxy(onEvent: { eventData in
            if let stat = try? JSONDecoder().decode(StatsModel.self, from: eventData) {
                continuation.yield(stat)
            }
        }, onComplete: { error in
            continuation.finish()
        })

        proxy.openStream(command: "startStatsStream", payload: data, delegate: delegate)
        return stream
    }

    public func streamLogs(for id: String) -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let data = try! JSONSerialization.data(withJSONObject: ["id": id])

        let delegate = StreamDelegateProxy(onEvent: { eventData in
            if let str = String(data: eventData, encoding: .utf8) {
                continuation.yield(str)
            }
        }, onComplete: { error in
            continuation.finish()
        })

        proxy.openStream(command: "streamLogs", payload: data, delegate: delegate)
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var isFinished = false

            let delegate = StreamDelegateProxy(onEvent: { eventData in
                if let dict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] {
                    if let pct = dict["progress"] as? Double {
                        progress(pct)
                    }
                    if let finished = dict["finished"] as? Bool, finished {
                        if !isFinished {
                            isFinished = true
                            continuation.resume(returning: ())
                        }
                    }
                }
            }, onComplete: { error in
                if let error = error, !isFinished {
                    isFinished = true
                    continuation.resume(throwing: error)
                } else if !isFinished {
                    isFinished = true
                    continuation.resume(returning: ())
                }
            })

            proxy.openStream(command: "pullImage", payload: data, delegate: delegate)
        }
    }

    public func deleteImage(reference: String) async throws {
        _ = try await sendCommandRaw(command: "deleteImage", payload: ["ref": reference])
    }

    public func execShell(containerId: String, stdin: Containerization.ReaderStream, stdout: Containerization.Writer) async throws -> LinuxProcess {
        throw NSError(domain: "Vessel", code: 501, userInfo: [NSLocalizedDescriptionKey: "execShell not supported over XPC directly yet"])
    }
}
