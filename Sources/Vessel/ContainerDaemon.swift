import Foundation
import Containerization
import ContainerizationExtras
import ContainerizationOS
import ContainerizationEXT4
import ContainerizationOCI
import ContainerizationError

public struct SimpleNATNetwork {
    private var nextIP: UInt32 = 200
    
    public init() {}
    
    public mutating func createInterface(_ id: String) throws -> Containerization.Interface? {
        let ip = nextIP
        nextIP += 1
        return NATInterface(
            address: "192.168.64.\(ip)/24",
            gateway: "192.168.64.1"
        )
    }

    public mutating func createInterface(_ id: String, mtu: UInt32) throws -> Containerization.Interface? {
        let ip = nextIP
        nextIP += 1
        return NATInterface(
            address: "192.168.64.\(ip)/24",
            gateway: "192.168.64.1"
        )
    }

    public mutating func releaseInterface(_ id: String) throws {
        // No-op
    }
}

public final class ContainerDaemon: @unchecked Sendable {
    private struct ActiveContainer {
        let vessel: VesselContainer
        var linux: LinuxContainer?
        var logStream: AsyncStream<String>?
    }
    
    private struct ActivePod {
        let pod: VesselPod
        var linuxContainers: [String: LinuxContainer] = [:]
    }
    
    private final class LogWriter: Writer {
        let prefix: String
        let continuation: AsyncStream<String>.Continuation
        
        // ⚡ Bolt Optimization: Cache DateFormatter. Instantiating it is notoriously slow.
        private let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            return df
        }()

        init(prefix: String, continuation: AsyncStream<String>.Continuation) {
            self.prefix = prefix
            self.continuation = continuation
        }
        
        func write(_ data: Data) throws {
            if let string = String(data: data, encoding: .utf8) {
                let timeStr = dateFormatter.string(from: Date())
                // ⚡ Bolt Optimization: Use .split instead of .components to avoid allocating new Arrays and Strings
                let lines = string.split(whereSeparator: \.isNewline)
                for line in lines {
                    guard !line.isEmpty else { continue }
                    continuation.yield("\(timeStr) \(prefix) \(line)")
                }
            }
        }
        
        func close() throws {
            continuation.finish()
        }
    }
    
    private var activeContainers: [String: ActiveContainer] = [:]
    private var activePods: [String: ActivePod] = [:]
    
    private let containersFilePath: URL = {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("containers.json")
    }()
    
    private let podsFilePath: URL = {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pods.json")
    }()
    
    public init() {
        loadContainers()
        loadPods()
    }
    
    private func saveContainers() {
        let vessels = activeContainers.values.map { $0.vessel }
        if let data = try? JSONEncoder().encode(vessels) {
            // Security Enhancement: Write with atomic to prevent race conditions or reads before completely written. (completeFileProtection removed for daemon access during lock)
            try? data.write(to: containersFilePath, options: [.atomic])
            // Security Enhancement: Restrict file permissions to owner-only to prevent unauthorized reading of sensitive config like env vars
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: containersFilePath.path)
        }
    }
    
    private func loadContainers() {
        guard let data = try? Data(contentsOf: containersFilePath),
              let vessels = try? JSONDecoder().decode([VesselContainer].self, from: data) else {
            return
        }
        for var vessel in vessels {
            // Mark as stopped initially
            vessel = VesselContainer(id: vessel.id, name: vessel.name, subtitle: vessel.subtitle, image: vessel.image, status: .stopped, ipAddress: vessel.ipAddress, dnsName: vessel.dnsName, uptime: vessel.uptime, ports: vessel.ports, memoryUsage: vessel.memoryUsage, volume: vessel.volume, exitStatus: vessel.exitStatus, rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, rootfsSize: vessel.rootfsSize, cpus: vessel.cpus, memoryGB: vessel.memoryGB, envVars: vessel.envVars, volumes: vessel.volumes)
            activeContainers[vessel.id] = ActiveContainer(vessel: vessel, linux: nil, logStream: nil)
        }
    }
    
    private func savePods() {
        let vesselPods = activePods.values.map { $0.pod }
        if let data = try? JSONEncoder().encode(vesselPods) {
            // Security Enhancement: Write with atomic to prevent race conditions or reads before completely written. (completeFileProtection removed for daemon access during lock)
            try? data.write(to: podsFilePath, options: [.atomic])
            // Security Enhancement: Restrict file permissions to owner-only to prevent unauthorized reading of sensitive config like env vars
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: podsFilePath.path)
        }
    }
    
    private func loadPods() {
        guard let data = try? Data(contentsOf: podsFilePath),
              let vesselPods = try? JSONDecoder().decode([VesselPod].self, from: data) else {
            return
        }
        for var p in vesselPods {
            p = VesselPod(id: p.id, name: p.name, status: .stopped, containers: p.containers, cpus: p.cpus, memoryGB: p.memoryGB)
            activePods[p.id] = ActivePod(pod: p, linuxContainers: [:])
        }
    }
    
    public func fetchActiveContainers() async throws -> [VesselContainer] {
        return activeContainers.values.map { $0.vessel }
    }
    
    public func fetchActiveWorkloads() async throws -> [VesselWorkload] {
        let containers = activeContainers.values.map { VesselWorkload.container($0.vessel) }
        let pods = activePods.values.map { VesselWorkload.pod($0.pod) }
        return containers + pods
    }
    
    public func startPod(yamlPath: URL) async throws {
        // Read yaml
        let yamlString = try String(contentsOf: yamlPath, encoding: .utf8)
        let projectName = yamlPath.deletingPathExtension().lastPathComponent
        let project = try ComposeParser.parse(yaml: yamlString, projectName: projectName)
        
        let storePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/images")
        let contentPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/content")
        let contentStore = try LocalContentStore(path: contentPath)
        let store = try ImageStore(path: storePath, contentStore: contentStore)
        let initPath = storePath.appendingPathComponent("initfs.ext4")
        let initImage = try await store.getInitImage(reference: "ghcr.io/apple/containerization/vminit:0.33.4")
        
        let initfs = try await {
            do {
                return try await initImage.initBlock(at: initPath, for: .linuxArm)
            } catch let err as ContainerizationError {
                guard err.code == .exists else { throw err }
                return Containerization.Mount.block(
                    format: "ext4",
                    source: initPath.absolutePath(),
                    destination: "/",
                    options: ["ro"]
                )
            }
        }()
        
        let kernelPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/vmlinux")
        let testKernel = Kernel(path: kernelPath, platform: .linuxArm)
        
        let podId = UUID().uuidString
        var containers: [VesselContainer] = []
        var linuxContainers: [String: LinuxContainer] = [:]
        
        let platform = Platform(arch: "arm64", os: "linux", variant: "v8")
        
        for service in project.services {
            let normalizedRef = normalize(reference: service.image)
            let image = try await store.get(reference: normalizedRef)
            let fsPath = storePath.appendingPathComponent("containers").appendingPathComponent("\(podId)-\(service.name)-rootfs.ext4")
            
            let rootfs = try await image.unpack(for: platform, at: fsPath, blockSizeInBytes: 8.gib(), progress: nil)
            
            let vmm = VZVirtualMachineManager(
                kernel: testKernel,
                initialFilesystem: initfs,
                bootlog: nil
            )
            
            let container = LinuxContainer("\(podId)-\(service.name)", rootfs: rootfs, vmm: vmm)
            container.cpus = 1
            container.memoryInBytes = 1.gib()
            container.rosetta = true
            
            var network = SimpleNATNetwork()
            if let interface = try? network.createInterface(container.id) {
                container.interfaces = [interface]
                if !interface.gateway.isEmpty {
                    container.dns = Containerization.DNS(nameservers: ["8.8.8.8", "1.1.1.1"])
                }
            }
            
            let imageConfig = try await image.config(for: platform).config
            
            if let config = imageConfig {
                let cwd = config.workingDir ?? "/"
                let env = config.env ?? []
                let args = (config.entrypoint ?? []) + (config.cmd ?? [])
                
                container.workingDirectory = cwd
                var allEnvs = env
                for (key, value) in service.environment {
                    allEnvs.append("\(key)=\(value)")
                }
                container.environment = allEnvs
                container.arguments = args
                
                if let rawString = config.user {
                    container.user = ContainerizationOCI.User(username: rawString)
                }
            } else {
                var envs: [String] = []
                for (key, value) in service.environment {
                    envs.append("\(key)=\(value)")
                }
                container.environment.append(contentsOf: envs)
            }
            
            try await container.create()
            try await container.start()
            
            linuxContainers[service.name] = container
            
            containers.append(VesselContainer(
                id: "\(podId)-\(service.name)",
                name: service.name,
                subtitle: "Compose Service",
                image: service.image,
                status: .running,
                ipAddress: "127.0.0.1",
                rosettaEnabled: true,
                networkingEnabled: true,
                rootfsSize: "8GB",
                cpus: 1,
                memoryGB: 1,
                envVars: service.environment,
                volumes: []
            ))
        }
        
        let vesselPod = VesselPod(
            id: podId,
            name: projectName,
            status: .running,
            containers: containers.map { VesselContainer(id: $0.id, name: $0.name, subtitle: $0.subtitle, image: $0.image, status: .running, ipAddress: $0.ipAddress, rosettaEnabled: $0.rosettaEnabled, networkingEnabled: $0.networkingEnabled, rootfsSize: $0.rootfsSize, cpus: $0.cpus, memoryGB: $0.memoryGB, envVars: $0.envVars, volumes: $0.volumes) },
            cpus: 4,
            memoryGB: 4.0
        )
        
        activePods[podId] = ActivePod(pod: vesselPod, linuxContainers: linuxContainers)
        savePods()
    }
    
    private func normalize(reference: String) -> String {
        var ref = reference
        let parts = ref.split(separator: "/")
        if parts.isEmpty { return ref }
        
        let firstPart = String(parts[0])
        if !firstPart.contains(".") && firstPart != "localhost" {
            if parts.count == 1 {
                ref = "docker.io/library/\(ref)"
            } else {
                ref = "docker.io/\(ref)"
            }
        }
        
        if !ref.contains(":") {
            ref += ":latest"
        }
        return ref
    }
    
    public func start(containerId: String, imageReference: String, name: String, rootfsSizeGB: Double, rosetta: Bool, networking: Bool, cpus: Int = 2, memoryGB: Double = 2.0, envVars: [String: String] = [:], volumes: [VesselVolume] = []) async throws {
        func debugLog(_ msg: String) {
            let logFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/daemon.log")
            let text = "[\(Date())] \(msg)\n"
            if let data = text.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    // Security Enhancement: Use atomic writes and restrict permissions for log files
                    try? data.write(to: logFile, options: [.atomic])
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logFile.path)
                }
            }
        }
        
        debugLog("start() called for \(containerId) with \(imageReference)")
        let normalizedRef = normalize(reference: imageReference)
        
        // 1. kernel
        let network: SimpleNATNetwork?
        if networking {
            debugLog("Initializing network...")
            network = SimpleNATNetwork()
            debugLog("Network initialized: \(network != nil)")
        } else {
            network = nil
        }
        
        let kernelPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/vmlinux")
        let kernel = Kernel(path: kernelPath, platform: .linuxArm)
        
        let storePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/images")
        let contentPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/content")
        let contentStore = try LocalContentStore(path: contentPath)
        let store = try ImageStore(path: storePath, contentStore: contentStore)
        let initPath = storePath.appendingPathComponent("initfs.ext4")
        let initImage = try await store.getInitImage(reference: "ghcr.io/apple/containerization/vminit:0.33.4")
        
        let initfs = try await {
            do {
                return try await initImage.initBlock(at: initPath, for: .linuxArm)
            } catch let err as ContainerizationError {
                guard err.code == .exists else { throw err }
                return Containerization.Mount.block(
                    format: "ext4",
                    source: initPath.absolutePath(),
                    destination: "/",
                    options: ["ro"]
                )
            }
        }()

        let vmm = VZVirtualMachineManager(
            kernel: kernel,
            initialFilesystem: initfs,
            bootlog: nil
        )
        debugLog("VZVirtualMachineManager initialized")
        
        var logContinuation: AsyncStream<String>.Continuation!
        let stream = AsyncStream<String> { cont in
            logContinuation = cont
        }
        
        debugLog("Creating container instance...")
        let image = try await store.get(reference: normalizedRef)
        let platform = Platform(arch: "arm64", os: "linux", variant: "v8")
        let fsPath = storePath.appendingPathComponent("containers").appendingPathComponent("\(containerId)-rootfs.ext4")
        let rootfs = try await image.unpack(for: platform, at: fsPath, blockSizeInBytes: UInt64(rootfsSizeGB * 1024 * 1024 * 1024), progress: nil)

        let container = LinuxContainer(containerId, rootfs: rootfs, vmm: vmm)
        container.cpus = cpus
        container.memoryInBytes = UInt64(memoryGB * 1024 * 1024 * 1024)
        container.rosetta = rosetta
        
        if var network = network {
            if let interface = try? network.createInterface(containerId) {
                container.interfaces = [interface]
                container.dns = Containerization.DNS(nameservers: ["192.168.64.1"])
            }
        }
        
        let imageConfig = try await image.config(for: Platform(arch: "arm64", os: "linux", variant: "v8")).config
        if let config = imageConfig {
            let cwd = config.workingDir ?? "/"
            let env = config.env ?? []
            let args = (config.entrypoint ?? []) + (config.cmd ?? [])
            
            container.workingDirectory = cwd
            var allEnvs = env
            for (key, value) in envVars {
                allEnvs.append("\(key)=\(value)")
            }
            container.environment = allEnvs
            container.arguments = args
            
            if let rawString = config.user {
                container.user = ContainerizationOCI.User(username: rawString)
            }
        } else {
            var envs: [String] = []
            for (key, value) in envVars {
                envs.append("\(key)=\(value)")
            }
            container.environment.append(contentsOf: envs)
        }
        
        for volume in volumes {
            container.mounts.append(Mount.share(source: volume.host, destination: volume.container))
        }
        
        let stdoutWriter = LogWriter(prefix: "STDOUT", continuation: logContinuation)
        let stderrWriter = LogWriter(prefix: "STDERR", continuation: logContinuation)
        container.stdout = stdoutWriter
        container.stderr = stderrWriter
        
        debugLog("Calling container.create()...")
        try await container.create()
        debugLog("Calling container.start()...")
        try await container.start()
        debugLog("Container started successfully!")
        
        let vessel = VesselContainer(
            id: containerId,
            name: name,
            subtitle: "WORKLOAD",
            image: imageReference,
            status: .running,
            ipAddress: networking ? "127.0.0.1" : nil,
            rosettaEnabled: rosetta,
            networkingEnabled: networking,
            rootfsSize: "\(Int(rootfsSizeGB))GB",
            cpus: cpus,
            memoryGB: memoryGB,
            envVars: envVars,
            volumes: volumes
        )
        
        activeContainers[containerId] = ActiveContainer(vessel: vessel, linux: container, logStream: stream)
        saveContainers()
        debugLog("Container added to activeContainers")
    }
    
    public func start(containerId: String) async throws {
        func debugLog(_ msg: String) {
            let logFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/daemon.log")
            let text = "[\(Date())] \(msg)\n"
            if let data = text.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    // Security Enhancement: Use atomic writes and restrict permissions for log files
                    try? data.write(to: logFile, options: [.atomic])
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logFile.path)
                }
            }
        }
        
        debugLog("start(containerId:) called for \(containerId)")
        
        if let activePod = activePods[containerId] {
            for (_, container) in activePod.linuxContainers {
                try await container.start()
            }
            let pod = activePod.pod
            let updatedPod = VesselPod(id: pod.id, name: pod.name, status: .running, containers: pod.containers, cpus: pod.cpus, memoryGB: pod.memoryGB)
            activePods[containerId] = ActivePod(pod: updatedPod, linuxContainers: activePod.linuxContainers)
            savePods()
            return
        }

        guard let active = activeContainers[containerId] else { throw NSError(domain: "Vessel", code: 404, userInfo: [NSLocalizedDescriptionKey: "Container not found"]) }
        
        let vessel = active.vessel
        
        // Recreate linux container if it doesn't exist
        var linux = active.linux
        var stream = active.logStream
        
        if linux == nil {
            let network: SimpleNATNetwork? = vessel.networkingEnabled ? SimpleNATNetwork() : nil
            let kernelPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/vmlinux")
            let kernel = Kernel(path: kernelPath, platform: .linuxArm)
                     let storePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/images")
            let contentPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/content")
            let contentStore = try LocalContentStore(path: contentPath)
            let store = try ImageStore(path: storePath, contentStore: contentStore)
            let initPath = storePath.appendingPathComponent("initfs.ext4")
            let initImage = try await store.getInitImage(reference: "ghcr.io/apple/containerization/vminit:0.33.4")
            
            let initfs = try await {
                do {
                    return try await initImage.initBlock(at: initPath, for: .linuxArm)
                } catch let err as ContainerizationError {
                    guard err.code == .exists else { throw err }
                    return Containerization.Mount.block(
                        format: "ext4",
                        source: initPath.absolutePath(),
                        destination: "/",
                        options: ["ro"]
                    )
                }
            }()
            
            let vmm = VZVirtualMachineManager(
                kernel: kernel,
                initialFilesystem: initfs,
                bootlog: nil
            )
            
            var logContinuation: AsyncStream<String>.Continuation!
            stream = AsyncStream<String> { cont in
                logContinuation = cont
            }
            
            let containerRoot = storePath.appendingPathComponent("containers").appendingPathComponent(containerId)
            let fsPath = containerRoot.appendingPathComponent("rootfs.ext4")
            let rootfs = Containerization.Mount.block(format: "ext4", source: fsPath.path, destination: "/", options: [])
            
            let container = LinuxContainer(containerId, rootfs: rootfs, vmm: vmm)
            container.cpus = vessel.cpus
            container.memoryInBytes = UInt64(vessel.memoryGB * 1024 * 1024 * 1024)
            container.rosetta = vessel.rosettaEnabled
            
            if var network = network {
                if let interface = try? network.createInterface(containerId) {
                    container.interfaces = [interface]
                    container.dns = Containerization.DNS(nameservers: ["192.168.64.1"])
                }
            }
            
            let image = try await store.get(reference: normalize(reference: vessel.image))
            let platform = Platform(arch: "arm64", os: "linux", variant: "v8")
            let imageConfig = try await image.config(for: platform).config
            
            if let config = imageConfig {
                let cwd = config.workingDir ?? "/"
                let env = config.env ?? []
                let args = (config.entrypoint ?? []) + (config.cmd ?? [])
                
                container.workingDirectory = cwd
                var allEnvs = env
                for (key, value) in vessel.envVars {
                    allEnvs.append("\(key)=\(value)")
                }
                container.environment = allEnvs
                container.arguments = args
                
                if let rawString = config.user {
                    container.user = ContainerizationOCI.User(username: rawString)
                }
            } else {
                var envs: [String] = []
                for (key, value) in vessel.envVars {
                    envs.append("\(key)=\(value)")
                }
                container.environment.append(contentsOf: envs)
            }
            
            for volume in vessel.volumes {
                container.mounts.append(Mount.share(source: volume.host, destination: volume.container))
            }
            
            let stdoutWriter = LogWriter(prefix: "STDOUT", continuation: logContinuation)
            let stderrWriter = LogWriter(prefix: "STDERR", continuation: logContinuation)
            container.stdout = stdoutWriter
            container.stderr = stderrWriter
            debugLog("Calling container.create()...")
            try await container.create()
            linux = container
        }
        
        // Security: Avoid force unwrap to prevent application crash if the container fails to initialize.
        guard let linuxContainer = linux else {
            throw NSError(domain: "Vessel", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Linux container"])
        }

        debugLog("Calling linuxContainer.start()...")
        try await linuxContainer.start()
        debugLog("linuxContainer.start() succeeded!")
        
        let updated = VesselContainer(id: vessel.id, name: vessel.name, subtitle: vessel.subtitle, image: vessel.image, status: .running, ipAddress: vessel.networkingEnabled ? "127.0.0.1" : nil, dnsName: vessel.dnsName, uptime: vessel.uptime, ports: vessel.ports, memoryUsage: vessel.memoryUsage, volume: vessel.volume, exitStatus: nil, rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, rootfsSize: vessel.rootfsSize, cpus: vessel.cpus, memoryGB: vessel.memoryGB, envVars: vessel.envVars, volumes: vessel.volumes)
        activeContainers[containerId] = ActiveContainer(vessel: updated, linux: linux, logStream: stream)
        saveContainers()
    }
    
    public func execShell(containerId: String, stdin: Containerization.ReaderStream, stdout: Containerization.Writer) async throws -> LinuxProcess {
        guard let active = activeContainers[containerId] else { throw NSError(domain: "Vessel", code: 404, userInfo: [NSLocalizedDescriptionKey: "Container not found"]) }
        
        guard let linux = active.linux else { throw NSError(domain: "Vessel", code: 400, userInfo: [NSLocalizedDescriptionKey: "Container not running"]) }
        
        let config = ContainerizationOCI.Process(
            args: ["/bin/sh", "-l"],
            env: [
                "TERM=xterm-256color",
                "HOME=/root",
                "USER=root"
            ],
            terminal: true
        )
        let execId = "shell-\(UUID().uuidString)"
        let process = try await linux.exec(execId, configuration: config, stdin: stdin, stdout: stdout, stderr: nil)
        try await process.start()
        return process
    }
    
    public func startStatsStream(containerId: String) async throws -> AsyncStream<StatsModel> {
        guard let active = activeContainers[containerId] else {
            throw NSError(domain: "Vessel", code: 404, userInfo: [NSLocalizedDescriptionKey: "Container not active"])
        }
        guard let linux = active.linux else {
            throw NSError(domain: "Vessel", code: 400, userInfo: [NSLocalizedDescriptionKey: "Container not running"])
        }
        
        let (stream, continuation) = AsyncStream<StatsModel>.makeStream()
        
        let config = ContainerizationOCI.Process(
            args: ["sh", "-c", "while true; do cat /proc/stat; echo '---MEM---'; cat /proc/meminfo; echo '---LOAD---'; cat /proc/loadavg; echo '---UPTIME---'; cat /proc/uptime; echo '---END---'; sleep 1; done"],
            terminal: false
        )
        
        let readerWriter = StatsProcessReaderWriter(continuation: continuation)
        
        let execId = "stats-\(UUID().uuidString)"
        let process = try await linux.exec(execId, configuration: config, stdout: readerWriter)
        try await process.start()
        return stream
    }

class StatsProcessReaderWriter: Containerization.Writer, @unchecked Sendable {
    let continuation: AsyncStream<StatsModel>.Continuation
    var buffer: String = ""
    var currentModel = StatsModel()
    let parser = StatsParser()
    
    init(continuation: AsyncStream<StatsModel>.Continuation) {
        self.continuation = continuation
    }
    
    func write(_ data: Data) throws {
        let str = String(decoding: data, as: UTF8.self)
        buffer += str
        
        while let endRange = buffer.range(of: "---END---\n") {
            let chunk = String(buffer[..<endRange.lowerBound])
            buffer.removeSubrange(..<endRange.upperBound)
            
            parser.parse(output: chunk, currentModel: &currentModel)
            continuation.yield(currentModel)
        }
    }
    
    func close() throws {
        continuation.finish()
    }
}    
    public func stop(containerId: String, force: Bool = false) async throws {
        if let activePod = activePods[containerId] {
            for (_, container) in activePod.linuxContainers {
                try? await container.stop()
            }
            let pod = activePod.pod
            let updatedPod = VesselPod(id: pod.id, name: pod.name, status: .stopped, containers: pod.containers, cpus: pod.cpus, memoryGB: pod.memoryGB)
            activePods[containerId] = ActivePod(pod: updatedPod, linuxContainers: [:])
            savePods()
            return
        }

        guard let active = activeContainers[containerId], let linux = active.linux else { return }

        if force {
            // Some containers might be stubborn, stop them forcefully. The api currently provides stop()
            // In a real framework extension, a kill() signal would be sent. Here we call stop and release resources.
            try? await linux.stop()
        } else {
            try await linux.stop()
        }

        let vessel = active.vessel
        let updated = VesselContainer(id: vessel.id, name: vessel.name, subtitle: vessel.subtitle, image: vessel.image, status: .stopped, ipAddress: vessel.ipAddress, dnsName: vessel.dnsName, uptime: vessel.uptime, ports: vessel.ports, memoryUsage: vessel.memoryUsage, volume: vessel.volume, exitStatus: force ? "Force Stopped by user" : "Stopped by user", rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, rootfsSize: vessel.rootfsSize, cpus: vessel.cpus, memoryGB: vessel.memoryGB, envVars: vessel.envVars, volumes: vessel.volumes)
        activeContainers[containerId] = ActiveContainer(vessel: updated, linux: nil, logStream: nil)
        saveContainers()
    }
    
    public func delete(containerId: String) async throws {
        if let activePod = activePods[containerId] {
            for (_, container) in activePod.linuxContainers {
                try? await container.stop()
            }
            activePods.removeValue(forKey: containerId)
            savePods()
            return
        }

        if let active = activeContainers[containerId], let linux = active.linux {
            try? await linux.stop()
        }
        
        let storePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/images")
        let containerRoot = storePath.appendingPathComponent("containers").appendingPathComponent(containerId)
        try? FileManager.default.removeItem(at: containerRoot)
        activeContainers.removeValue(forKey: containerId)
        saveContainers()
    }
    
    public func streamLogs(for id: String) -> AsyncStream<String> {
        if let active = activeContainers[id], let stream = active.logStream {
            return stream
        }
        
        return AsyncStream { continuation in
            continuation.yield("No active stream found for container \(id)")
            continuation.finish()
        }
    }
        
        public func fetchImages() async throws -> [VesselImage] {
            let storePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/images")
        let contentPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/content")
        let contentStore = try LocalContentStore(path: contentPath)
        let store = try ImageStore(path: storePath, contentStore: contentStore)
            let images = try await store.list()
            return images.map { img in
                let ref = img.reference
                let parts = ref.split(separator: ":")
                var repo = String(parts.first ?? "unknown")
                if repo.hasPrefix("docker.io/library/") {
                    repo = String(repo.dropFirst("docker.io/library/".count))
                } else if repo.hasPrefix("docker.io/") {
                    repo = String(repo.dropFirst("docker.io/".count))
                }
                
                let tag = parts.count > 1 ? String(parts[1]) : "latest"
                let rawDigest = img.descriptor.digest
                let lastPart = rawDigest.split(separator: ":").last
                // Security: Avoid force unwrap to prevent a crash if digest format is malformed
                let shortDigest: String
                if let lp = lastPart {
                    shortDigest = String(lp.prefix(12))
                } else {
                    shortDigest = "unknown"
                }
                
                return VesselImage(id: shortDigest, repository: repo, tag: tag, size: "N/A MB")
            }
        }
        
        public func pullImage(reference: String, progress: @escaping @Sendable (Double) -> Void) async throws {
            let storePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/images")
        let contentPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/content")
        let contentStore = try LocalContentStore(path: contentPath)
        let store = try ImageStore(path: storePath, contentStore: contentStore)
            actor ProgressTracker {
                var currentBytes: Int64 = 0
                var totalBytes: Int64 = 0
                func add(size: Int64) { currentBytes += size }
                func addTotal(totalSize: Int64) { totalBytes = totalSize }
                func getProgress() -> Double {
                    // Ignorujemy pierwszą fazę pobierania manifestu (zazwyczaj parę KB),
                    // żeby pasek nie skakał sztucznie do 100% i potem z powrotem do 0%.
                    if totalBytes < 1_000_000 {
                        return 0.01
                    }
                    return Double(currentBytes) / Double(totalBytes)
                }
            }
            let tracker = ProgressTracker()
            
            _ = try await store.pull(reference: reference, progress: { events in
                for event in events {
                    if event.event == "add-items", let size = event.value as? UInt64 {
                        await tracker.add(size: Int64(size))
                    } else if event.event == "add-total-items", let size = event.value as? UInt64 {
                        await tracker.addTotal(totalSize: Int64(size))
                    }
                }
                let pct = await tracker.getProgress()
                progress(pct)
            })
        }
        public func deleteImage(reference: String) async throws {
            let storePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/images")
        let contentPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/content")
        let contentStore = try LocalContentStore(path: contentPath)
        let store = try ImageStore(path: storePath, contentStore: contentStore)
            try await store.delete(reference: reference, performCleanup: true)
        }
    }
