import Foundation
import Security
import os
import VesselXPC
import Containerization

final class XPCShellReader: ReaderStream, @unchecked Sendable {
    private let internalStream: AsyncStream<Data>
    
    init(stream: AsyncStream<Data>) {
        self.internalStream = stream
    }
    
    func stream() -> AsyncStream<Data> {
        return internalStream
    }
}

final class XPCShellWriter: Writer, @unchecked Sendable {
    private let delegate: VesselXPCStreamDelegate
    
    init(delegate: VesselXPCStreamDelegate) {
        self.delegate = delegate
    }
    
    func write(_ data: Data) throws {
        delegate.onEvent(payload: data)
    }
}

class VesselDaemonXPC: NSObject, VesselXPCProtocol, @unchecked Sendable {
    private let daemon: ContainerDaemon
    private var connectionTasks: [ObjectIdentifier: [UUID: Task<Void, Never>]] = [:]
    private var activeShellStreams: [String: AsyncStream<Data>.Continuation] = [:]
    private let lock = NSLock()

    init(daemon: ContainerDaemon) {
        self.daemon = daemon
    }

    func writeToStream(streamId: String, payload: Data) {
        lock.lock()
        let continuation = activeShellStreams[streamId]
        lock.unlock()
        continuation?.yield(payload)
    }

    func cancelTasks(for connectionId: ObjectIdentifier) {
        lock.lock()
        let tasks = connectionTasks.removeValue(forKey: connectionId)
        lock.unlock()

        tasks?.values.forEach { $0.cancel() }
    }

    private func trackTask(_ task: Task<Void, Never>, withId id: UUID, for connectionId: ObjectIdentifier) {
        lock.lock()
        if connectionTasks[connectionId] == nil {
            connectionTasks[connectionId] = [:]
        }
        connectionTasks[connectionId]?[id] = task
        lock.unlock()
    }

    private func removeTask(withId id: UUID, for connectionId: ObjectIdentifier) {
        lock.lock()
        connectionTasks[connectionId]?.removeValue(forKey: id)
        if connectionTasks[connectionId]?.isEmpty == true {
            connectionTasks.removeValue(forKey: connectionId)
        }
        lock.unlock()
    }

    func addShellStream(_ continuation: AsyncStream<Data>.Continuation, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        activeShellStreams[id] = continuation
    }

    func removeShellStream(for id: String) {
        lock.lock()
        defer { lock.unlock() }
        activeShellStreams.removeValue(forKey: id)
    }

    func ps(reply: @escaping (String) -> Void) {
        reply("vesseld is running securely")
    }

    func wakeContainer(containerId: String, reply: @escaping (String?, Error?) -> Void) {
        reply("vesseld cannot wake container: not implemented", nil)
    }

    private static func isPathSafe(_ path: String, userIdentifier: uid_t?) -> Bool {
        // Prevent arbitrary directory mount bypasses and enforce explicit user consent
        // Reject paths targeting root (/), /Users, or outside the current user's home directory.
        let expandedPath = NSString(string: path).expandingTildeInPath
        let standardizedPath = URL(fileURLWithPath: expandedPath).standardized.path

        if standardizedPath == "/" || standardizedPath == "/Users" {
            return false
        }

        if path.contains("..") {
            return false
        }

        let homeDir: String
        if let uid = userIdentifier {
            if let pw = getpwuid(uid), let dir = pw.pointee.pw_dir {
                homeDir = String(cString: dir)
            } else {
                homeDir = NSHomeDirectory()
            }
        } else {
            homeDir = NSHomeDirectory()
        }

        // Ensure path is exactly the home dir or a subdirectory, preventing bypasses like /Users/johnny for /Users/john
        if standardizedPath != homeDir && !standardizedPath.hasPrefix(homeDir + "/") {
            return false
        }

        return true
    }

    private static func securelyOpenFileForReading(path: String, userIdentifier: uid_t?) throws -> FileHandle {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            throw NSError(domain: "VesselDaemonXPC", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to open file safely (it may not exist, or it is a symlink)"])
        }

        var statInfo = stat()
        if fstat(fd, &statInfo) < 0 {
            close(fd)
            throw NSError(domain: "VesselDaemonXPC", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to stat opened file descriptor"])
        }

        if (statInfo.st_mode & S_IFMT) != S_IFREG {
            close(fd)
            throw NSError(domain: "VesselDaemonXPC", code: 403, userInfo: [NSLocalizedDescriptionKey: "File is not a regular file"])
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if fcntl(fd, F_GETPATH, &pathBuffer) < 0 {
            close(fd)
            throw NSError(domain: "VesselDaemonXPC", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve final path"])
        }

        let resolvedPath = String(cString: pathBuffer)
        if !isPathSafe(resolvedPath, userIdentifier: userIdentifier) {
            close(fd)
            throw NSError(domain: "VesselDaemonXPC", code: 403, userInfo: [NSLocalizedDescriptionKey: "Resolved file path is outside allowed boundaries"])
        }

        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private static func securelyOpenFileForWriting(path: String, userIdentifier: uid_t?) throws -> FileHandle {
        if !isPathSafe(path, userIdentifier: userIdentifier) {
            throw NSError(domain: "VesselDaemonXPC", code: 403, userInfo: [NSLocalizedDescriptionKey: "Resolved file path is outside allowed boundaries"])
        }
        let fd = open(path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if fd < 0 {
            throw NSError(domain: "VesselDaemonXPC", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to create or open file safely (it may be a symlink)"])
        }

        var statInfo = stat()
        if fstat(fd, &statInfo) < 0 {
            close(fd)
            throw NSError(domain: "VesselDaemonXPC", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to stat opened file descriptor"])
        }

        if (statInfo.st_mode & S_IFMT) != S_IFREG {
            close(fd)
            throw NSError(domain: "VesselDaemonXPC", code: 403, userInfo: [NSLocalizedDescriptionKey: "Target is not a regular file"])
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if fcntl(fd, F_GETPATH, &pathBuffer) < 0 {
            close(fd)
            throw NSError(domain: "VesselDaemonXPC", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve final path"])
        }

        let resolvedPath = String(cString: pathBuffer)
        if !isPathSafe(resolvedPath, userIdentifier: userIdentifier) {
            close(fd)
            throw NSError(domain: "VesselDaemonXPC", code: 403, userInfo: [NSLocalizedDescriptionKey: "Resolved file path is outside allowed boundaries"])
        }

        if ftruncate(fd, 0) < 0 {
            close(fd)
            throw NSError(domain: "VesselDaemonXPC", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to truncate file securely"])
        }

        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private func resolveBookmarks(from payload: [String: Any]?) {
        guard let bookmarksDict = payload?["bookmarks"] as? [String: String] else { return }

        for (path, base64String) in bookmarksDict {
            if let data = Data(base64Encoded: base64String) {
                var isStale = false
                do {
                    let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                    if url.startAccessingSecurityScopedResource() {
                        print("vesseld: Successfully accessed bookmark for \(path)")
                    } else {
                        print("vesseld: Failed to access bookmark for \(path)")
                    }
                } catch {
                    print("vesseld: Error resolving bookmark for \(path): \(error)")
                }
            }
        }
    }

    func sendCommand(command: String, payload: Data, reply: @escaping (Data?, Error?) -> Void) {
        
        struct ReplyWrapper: @unchecked Sendable {
            let reply: (Data?, Error?) -> Void
        }
        let replyWrapper = ReplyWrapper(reply: reply)
        let daemon = self.daemon

        guard let connection = NSXPCConnection.current() else {
            replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "No active XPC connection found"]))
            return
        }
        let connectionId = ObjectIdentifier(connection)
        let taskId = UUID()
        let uid = connection.effectiveUserIdentifier

        // Ensure trackTask is called before Task starts execution to avoid race condition
        // Unfortunately Swift doesn't allow calling it before initialization on local var, but we can do it like this:
        // Or we can just let it be, the task dictionary purge on disconnect handles any edge case.
        // Let's explicitly track it immediately.
        var localTask: Task<Void, Never>!
        localTask = Task { [weak self, daemon, command, payload, replyWrapper, connectionId, taskId, uid] in
            defer {
                self?.removeTask(withId: taskId, for: connectionId)
            }
            do {
                let dict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]

                switch command {
                case "fetchActiveContainers":
                    let containers = try await daemon.fetchActiveContainers()
                    replyWrapper.reply(try JSONEncoder().encode(containers), nil)
                case "fetchActiveWorkloads":
                    let workloads = try await daemon.fetchActiveWorkloads()
                    replyWrapper.reply(try JSONEncoder().encode(workloads), nil)
                case "getContainerIP":
                    guard let id = dict?["id"] as? String else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing container id"]))
                        return
                    }
                    if let ip = daemon.getContainerIP(containerId: id) {
                        replyWrapper.reply(try JSONSerialization.data(withJSONObject: ["ip": ip]), nil)
                    } else {
                        replyWrapper.reply(Data(), nil)
                    }
                case "fetchDomainRules":
                    let rules = daemon.fetchDomainRules()
                    replyWrapper.reply(try JSONEncoder().encode(rules), nil)
                case "addDomainRule":
                    guard let d = dict,
                          let jsonData = try? JSONSerialization.data(withJSONObject: d),
                          let rule = try? JSONDecoder().decode(DomainRule.self, from: jsonData) else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid domain rule payload"]))
                        return
                    }
                    daemon.addDomainRule(rule)
                    replyWrapper.reply(Data(), nil)
                case "removeDomainRule":
                    guard let idStr = dict?["id"] as? String, let uuid = UUID(uuidString: idStr) else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid id"]))
                        return
                    }
                    daemon.removeDomainRule(id: uuid)
                    replyWrapper.reply(Data(), nil)
                case "startPod":
                    self?.resolveBookmarks(from: dict)
                    guard let path = dict?["yamlPath"] as? String else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing yamlPath"]))
                        return
                    }
                    guard Self.isPathSafe(path, userIdentifier: uid) else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 403, userInfo: [NSLocalizedDescriptionKey: "Invalid or unauthorized path"]))
                        return
                    }
                    let handle = try Self.securelyOpenFileForReading(path: path, userIdentifier: uid)
                    guard let yamlData = try? handle.readToEnd(), let yamlString = String(data: yamlData, encoding: .utf8) else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to read yaml configuration securely"]))
                        return
                    }
                    try await daemon.startPod(yamlPath: URL(fileURLWithPath: path), yamlString: yamlString)
                    replyWrapper.reply(Data(), nil)
                case "startFull":
                    self?.resolveBookmarks(from: dict)
                    guard let d = dict,
                          let id = d["containerId"] as? String,
                          let configDict = d["config"] else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing containerId or config"]))
                        return
                    }
                    let configData = try JSONSerialization.data(withJSONObject: configDict)
                    let config = try JSONDecoder().decode(ContainerStartConfiguration.self, from: configData)
                    try await daemon.start(containerId: id, config: config)
                    replyWrapper.reply(Data(), nil)
                case "start":
                    self?.resolveBookmarks(from: dict)
                    guard let id = dict?["id"] as? String else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing id"]))
                        return
                    }
                    try await daemon.start(containerId: id)
                    replyWrapper.reply(Data(), nil)
                case "listFiles":
                    guard let id = dict?["id"] as? String, let path = dict?["path"] as? String else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing id or path"]))
                        return
                    }
                    let files = try await daemon.listFiles(in: path, containerId: id)
                    replyWrapper.reply(try JSONSerialization.data(withJSONObject: ["files": files]), nil)
                case "downloadFile":
                    guard let id = dict?["id"] as? String, let path = dict?["path"] as? String, let dest = dict?["dest"] as? String else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing id, path, or dest"]))
                        return
                    }
                    guard Self.isPathSafe(dest, userIdentifier: uid) else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 403, userInfo: [NSLocalizedDescriptionKey: "Invalid or unauthorized destination path"]))
                        return
                    }
                    let handle = try Self.securelyOpenFileForWriting(path: dest, userIdentifier: uid)
                    try await daemon.downloadFile(containerId: id, path: path, to: handle)
                    replyWrapper.reply(Data(), nil)
                case "uploadFile":
                    guard let id = dict?["id"] as? String, let source = dict?["source"] as? String, let dest = dict?["dest"] as? String else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing id, source, or dest"]))
                        return
                    }
                    guard Self.isPathSafe(source, userIdentifier: uid) else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 403, userInfo: [NSLocalizedDescriptionKey: "Invalid or unauthorized source path"]))
                        return
                    }
                    let handle = try Self.securelyOpenFileForReading(path: source, userIdentifier: uid)
                    try await daemon.uploadFile(containerId: id, from: handle, to: dest)
                    replyWrapper.reply(Data(), nil)
                case "pauseAll":
                    try await daemon.pauseAll()
                    replyWrapper.reply(Data(), nil)
                case "resumeAll":
                    try await daemon.resumeAll()
                    replyWrapper.reply(Data(), nil)
                case "stop":
                    guard let id = dict?["id"] as? String, let force = dict?["force"] as? Bool else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing id or force"]))
                        return
                    }
                    try await daemon.stop(containerId: id, force: force)
                    replyWrapper.reply(Data(), nil)
                case "delete":
                    guard let id = dict?["id"] as? String else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing id"]))
                        return
                    }
                    try await daemon.delete(containerId: id)
                    replyWrapper.reply(Data(), nil)
                case "fetchImages":
                    let images = try await daemon.fetchImages()
                    replyWrapper.reply(try JSONEncoder().encode(images), nil)
                case "deleteImage":
                    guard let ref = dict?["ref"] as? String else {
                        replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing ref"]))
                        return
                    }
                    try await daemon.deleteImage(reference: ref)
                    replyWrapper.reply(Data(), nil)
                default:
                    replyWrapper.reply(nil, NSError(domain: "VesselDaemonXPC", code: 404, userInfo: [NSLocalizedDescriptionKey: "Command not found: \(command)"]))
                }
            } catch {
                replyWrapper.reply(nil, error)
            }
        }
        trackTask(localTask, withId: taskId, for: connectionId)
    }

    func openStream(command: String, payload: Data, delegate: VesselXPCStreamDelegate) {
        struct DelegateWrapper: @unchecked Sendable {
            let delegate: VesselXPCStreamDelegate
        }
        let wrapper = DelegateWrapper(delegate: delegate)
        
        let daemon = self.daemon
        guard let connection = NSXPCConnection.current() else {
            wrapper.delegate.onComplete(error: NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "No active XPC connection found"]))
            return
        }
        let connectionId = ObjectIdentifier(connection)
        let taskId = UUID()

        var localTask: Task<Void, Never>!
        localTask = Task { [weak self, daemon, command, payload, wrapper, connectionId, taskId] in
            defer {
                self?.removeTask(withId: taskId, for: connectionId)
            }
            do {
                let dict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]

                switch command {
                case "startStatsStream":
                    guard let id = dict?["id"] as? String else {
                        wrapper.delegate.onComplete(error: NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing container id"]))
                        return
                    }
                    let stream = try await daemon.startStatsStream(containerId: id)
                    for await stat in stream {
                        if Task.isCancelled { break }
                        if let data = try? JSONEncoder().encode(stat) {
                            wrapper.delegate.onEvent(payload: data)
                        }
                    }
                    wrapper.delegate.onComplete(error: nil)
                case "streamLogs":
                    guard let id = dict?["id"] as? String else {
                        wrapper.delegate.onComplete(error: NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing container id"]))
                        return
                    }
                    let stream = daemon.streamLogs(for: id)
                    for await log in stream {
                        if Task.isCancelled { break }
                        if let data = log.data(using: .utf8) {
                            wrapper.delegate.onEvent(payload: data)
                        }
                    }
                    wrapper.delegate.onComplete(error: nil)
                case "pullImage":
                    guard let ref = dict?["ref"] as? String else {
                        wrapper.delegate.onComplete(error: NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing ref"]))
                        return
                    }
                    try await daemon.pullImage(reference: ref) { progress in
                        if let data = try? JSONSerialization.data(withJSONObject: ["progress": progress, "finished": false]) {
                            wrapper.delegate.onEvent(payload: data)
                        }
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: ["progress": 1.0, "finished": true]) {
                        wrapper.delegate.onEvent(payload: data)
                        wrapper.delegate.onComplete(error: nil)
                    }
                case "execShell":
                    guard let id = dict?["id"] as? String, let streamId = dict?["streamId"] as? String else {
                        wrapper.delegate.onComplete(error: NSError(domain: "VesselDaemonXPC", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing id or streamId"]))
                        return
                    }
                    
                    let (stream, continuation) = AsyncStream<Data>.makeStream()
                    self?.addShellStream(continuation, for: streamId)
                    
                    defer {
                        self?.removeShellStream(for: streamId)
                        continuation.finish()
                    }
                    
                    let reader = XPCShellReader(stream: stream)
                    let writer = XPCShellWriter(delegate: wrapper.delegate)
                    
                    let process = try await daemon.execShell(containerId: id, stdin: reader, stdout: writer)
                    let exitCode = try await process.wait(timeoutInSeconds: nil)
                    if exitCode != 0 {
                        wrapper.delegate.onComplete(error: NSError(domain: "VesselDaemonXPC", code: Int(exitCode), userInfo: [NSLocalizedDescriptionKey: "Process exited with code \(exitCode)"]))
                    } else {
                        wrapper.delegate.onComplete(error: nil)
                    }
                default:
                    wrapper.delegate.onComplete(error: NSError(domain: "VesselDaemonXPC", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stream command not found: \(command)"]))
                }
            } catch {
                if Task.isCancelled {
                    wrapper.delegate.onComplete(error: NSError(domain: "VesselDaemonXPC", code: -999, userInfo: [NSLocalizedDescriptionKey: "Task cancelled"]))
                } else {
                    wrapper.delegate.onComplete(error: error)
                }
            }
        }

        trackTask(localTask, withId: taskId, for: connectionId)
    }
}

class VesselDaemonDelegate: NSObject, NSXPCListenerDelegate {
    private let sharedXPC: VesselDaemonXPC

    init(sharedXPC: VesselDaemonXPC) {
        self.sharedXPC = sharedXPC
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

        let interface = NSXPCInterface(with: VesselXPCProtocol.self)
        let delegateInterface = NSXPCInterface(with: VesselXPCStreamDelegate.self)

        interface.setInterface(delegateInterface, for: #selector(VesselXPCProtocol.openStream(command:payload:delegate:)), argumentIndex: 2, ofReply: false)

        newConnection.exportedInterface = interface
        newConnection.exportedObject = sharedXPC

        let connectionId = ObjectIdentifier(newConnection)

        newConnection.interruptionHandler = { [weak sharedXPC = self.sharedXPC, connectionId] in
            sharedXPC?.cancelTasks(for: connectionId)
        }

        newConnection.invalidationHandler = { [weak sharedXPC = self.sharedXPC, connectionId] in
            sharedXPC?.cancelTasks(for: connectionId)
        }

        newConnection.resume()
        return true
    }
}

let sharedDaemon = ContainerDaemon()
let sharedXPC = VesselDaemonXPC(daemon: sharedDaemon)
let delegate = VesselDaemonDelegate(sharedXPC: sharedXPC)
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
