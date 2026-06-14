import Foundation
import Containerization
import ContainerizationExtras
import ContainerizationOS
import ContainerizationEXT4
import ContainerizationOCI
import ContainerizationError

public struct SimpleNATNetwork: Network {
    private var nextIP: UInt32 = 200
    
    public init() {}
    
    public mutating func createInterface(_ id: String) throws -> Containerization.Interface? {
        let ip = nextIP
        nextIP += 1
        // Security: Avoid force unwrap to prevent DoS on invalid IP generation.
        guard let prefix = Prefix.ipv4(24) else { throw NSError(domain: "Network", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid IPv4 prefix"]) }
        return NATInterface(
            ipv4Address: try CIDRv4(IPv4Address(UInt32(192<<24 | 168<<16 | 64<<8) | ip), prefix: prefix),
            ipv4Gateway: try IPv4Address("192.168.64.1")
        )
    }

    public mutating func createInterface(_ id: String, mtu: UInt32) throws -> Containerization.Interface? {
        let ip = nextIP
        nextIP += 1
        // Security: Avoid force unwrap to prevent DoS on invalid IP generation.
        guard let prefix = Prefix.ipv4(24) else { throw NSError(domain: "Network", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid IPv4 prefix"]) }
        return NATInterface(
            ipv4Address: try CIDRv4(IPv4Address(UInt32(192<<24 | 168<<16 | 64<<8) | ip), prefix: prefix),
            ipv4Gateway: try IPv4Address("192.168.64.1"),
            mtu: mtu
        )
    }

    public mutating func releaseInterface(_ id: String) throws {
        // No-op
    }
}

public class ContainerDaemon {
    private struct ActiveContainer {
        let vessel: VesselContainer
        var linux: LinuxContainer?
        var logStream: AsyncStream<String>?
    }
    
    private struct ActivePod {
        let pod: VesselPod
        var linuxPod: LinuxPod?
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
            activePods[p.id] = ActivePod(pod: p, linuxPod: nil)
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
        
        let store = ImageStore.default
        let initPath = store.path.appendingPathComponent("initfs.ext4")
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
        
        let vmm = VZVirtualMachineManager(
            kernel: testKernel,
            initialFilesystem: initfs,
            rosetta: true,
            nestedVirtualization: false
        )
        
        let podId = UUID().uuidString
        let pod = try LinuxPod(podId, vmm: vmm) { config in
            config.cpus = 4
            config.memoryInBytes = 4.gib() // For the whole pod
            
            // Shared network
            var network = SimpleNATNetwork()
            if let interface = try? network.createInterface(podId) {
                config.interfaces = [interface]
                if let gateway = interface.ipv4Gateway {
                    config.dns = .init(nameservers: ["8.8.8.8", "1.1.1.1"])
                }
            }
        }
        
        var containers: [VesselContainer] = []
        let platform = Platform(arch: "arm64", os: "linux", variant: "v8")
        let unpacker = EXT4Unpacker(blockSizeInBytes: 8.gib())
        
        for service in project.services {
            let normalizedRef = normalize(reference: service.image)
            let image = try await store.get(reference: normalizedRef, pull: true)
            let fsPath = store.path.appendingPathComponent("containers").appendingPathComponent("\(podId)-\(service.name)-rootfs.ext4")
            
            let rootfs = try await unpacker.unpack(image, for: platform, at: fsPath, progress: nil)
            
            let imageConfig = try await image.config(for: .current).config
            
            try await pod.addContainer(service.name, rootfs: rootfs) { config in
                if let imageConfig {
                    config.process = LinuxProcessConfiguration(from: imageConfig)
                }
                var envs: [String] = []
                for (key, value) in service.environment {
                    envs.append("\(key)=\(value)")
                }
                config.process.environmentVariables.append(contentsOf: envs)
            }
            
            containers.append(VesselContainer(
                id: "\(podId)-\(service.name)",
                name: service.name,
                subtitle: "Compose Service",
                image: service.image,
                status: .starting,
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
        
        try await pod.create()
        for service in project.services {
            try await pod.startContainer(service.name)
        }
        
        let vesselPod = VesselPod(
            id: podId,
            name: projectName,
            status: .running,
            containers: containers.map { VesselContainer(id: $0.id, name: $0.name, subtitle: $0.subtitle, image: $0.image, status: .running, ipAddress: $0.ipAddress, rosettaEnabled: $0.rosettaEnabled, networkingEnabled: $0.networkingEnabled, rootfsSize: $0.rootfsSize, cpus: $0.cpus, memoryGB: $0.memoryGB, envVars: $0.envVars, volumes: $0.volumes) },
            cpus: 4,
            memoryGB: 4.0
        )
        
        activePods[podId] = ActivePod(pod: vesselPod, linuxPod: pod)
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
    
    public func start(containerId: String, imageReference: String, name: String, rootfsSizeGB: Double, rosetta: Bool, networking: Bool, cpus: Int = 2, memoryGB: Double = 2.0, envVars: [String: String] = [:], volumes: [VesselVolume] = [], domain: VesselDomain = .generic) async throws {
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
        
        debugLog("Initializing ContainerManager...")
        var manager = try await ContainerManager(
            kernel: kernel,
            initfsReference: "ghcr.io/apple/containerization/vminit:0.33.4",
            network: network,
            rosetta: rosetta
        )
        debugLog("ContainerManager initialized")
        
        var logContinuation: AsyncStream<String>.Continuation!
        let stream = AsyncStream<String> { cont in
            logContinuation = cont
        }
        
        debugLog("Creating container instance...")
        let container = try await manager.create(
            containerId,
            reference: normalizedRef,
            rootfsSizeInBytes: UInt64(rootfsSizeGB * 1024 * 1024 * 1024),
            readOnly: false,
            networking: networking
        ) { config in
            config.cpus = cpus
            config.memoryInBytes = UInt64(memoryGB * 1024 * 1024 * 1024)
            config.dns = Containerization.DNS(nameservers: ["192.168.64.1"])
            
            var envs: [String] = []
            for (key, value) in envVars {
                envs.append("\(key)=\(value)")
            }
            config.process.environmentVariables = envs
            
            var newMounts = LinuxContainer.defaultMounts()
            for volume in volumes {
                newMounts.append(Mount.share(source: volume.host, destination: volume.container))
            }
            config.mounts = newMounts
            
            let stdoutWriter = LogWriter(prefix: "STDOUT", continuation: logContinuation)
            let stderrWriter = LogWriter(prefix: "STDERR", continuation: logContinuation)
            config.process.stdout = stdoutWriter
            config.process.stderr = stderrWriter
        }
        
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
            volumes: volumes,
            domain: domain
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
            if let linuxPod = activePod.linuxPod {
                try await linuxPod.start()
            } else {
                throw NSError(domain: "Vessel", code: 400, userInfo: [NSLocalizedDescriptionKey: "Pod linux context not available for restart"])
            }
            let pod = activePod.pod
            let updatedPod = VesselPod(id: pod.id, name: pod.name, status: .running, containers: pod.containers, cpus: pod.cpus, memoryGB: pod.memoryGB)
            activePods[containerId] = ActivePod(pod: updatedPod, linuxPod: activePod.linuxPod)
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
            
            var manager = try await ContainerManager(
                kernel: kernel,
                initfsReference: "ghcr.io/apple/containerization/vminit:0.33.4",
                network: network,
                rosetta: vessel.rosettaEnabled
            )
            
            var logContinuation: AsyncStream<String>.Continuation!
            stream = AsyncStream<String> { cont in
                logContinuation = cont
            }
            
            
            let containerRoot = manager.imageStore.path.appendingPathComponent("containers").appendingPathComponent(containerId)
            let rootfsPath = containerRoot.appendingPathComponent("rootfs.ext4")
            
            let container: LinuxContainer
            
            debugLog("Checking rootfs at \(rootfsPath.path)...")
            
            if FileManager.default.fileExists(atPath: rootfsPath.path) {
                debugLog("Rootfs exists, mounting existing ext4 block...")
                let rootfsMount: Containerization.Mount = .block(format: "ext4", source: rootfsPath.path, destination: "/", options: [])
                let image = try await manager.imageStore.get(reference: normalize(reference: vessel.image), pull: true)
                container = try await manager.create(
                    containerId,
                    image: image,
                    rootfs: rootfsMount,
                    writableLayer: nil,
                    networking: vessel.networkingEnabled
                ) { config in
                    config.cpus = vessel.cpus
                    config.memoryInBytes = UInt64(vessel.memoryGB * 1024 * 1024 * 1024)
                    let baseImageName = vessel.image.split(separator: ":").first.map(String.init) ?? "vessel"
                    config.hostname = baseImageName
                    config.dns = Containerization.DNS(nameservers: ["192.168.64.1"])
                    var envs: [String] = []
                    for (key, value) in vessel.envVars { envs.append("\(key)=\(value)") }
                    config.process.environmentVariables = envs
                    if vessel.image.lowercased().contains("alpine") || vessel.image.lowercased().contains("ubuntu") {
                        config.process.arguments = ["tail", "-f", "/dev/null"]
                    }
                    var newMounts = LinuxContainer.defaultMounts()
                    for volume in vessel.volumes {
                        newMounts.append(Mount.share(source: volume.host, destination: volume.container))
                    }
                    config.mounts = newMounts
                    config.process.stdout = LogWriter(prefix: "STDOUT", continuation: logContinuation)
                    config.process.stderr = LogWriter(prefix: "STDERR", continuation: logContinuation)
                }
            } else {
                debugLog("Rootfs missing, creating from scratch...")
                let rootfsSize = Double(vessel.rootfsSize.replacingOccurrences(of: "GB", with: "")) ?? 8.0
                container = try await manager.create(
                    containerId,
                    reference: normalize(reference: vessel.image),
                    rootfsSizeInBytes: UInt64(rootfsSize * 1024 * 1024 * 1024),
                    readOnly: false,
                    networking: vessel.networkingEnabled
                ) { config in
                    config.cpus = vessel.cpus
                    config.memoryInBytes = UInt64(vessel.memoryGB * 1024 * 1024 * 1024)
                    let baseImageName = vessel.image.split(separator: ":").first.map(String.init) ?? "vessel"
                    config.hostname = baseImageName
                    config.dns = Containerization.DNS(nameservers: ["192.168.64.1"])
                    var envs: [String] = []
                    for (key, value) in vessel.envVars { envs.append("\(key)=\(value)") }
                    config.process.environmentVariables = envs
                    if vessel.image.lowercased().contains("alpine") || vessel.image.lowercased().contains("ubuntu") {
                        config.process.arguments = ["tail", "-f", "/dev/null"]
                    }
                    var newMounts = LinuxContainer.defaultMounts()
                    for volume in vessel.volumes {
                        newMounts.append(Mount.share(source: volume.host, destination: volume.container))
                    }
                    config.mounts = newMounts
                    config.process.stdout = LogWriter(prefix: "STDOUT", continuation: logContinuation)
                    config.process.stderr = LogWriter(prefix: "STDERR", continuation: logContinuation)
                }
            }
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
        
        var config = LinuxProcessConfiguration()
        config.arguments = ["/bin/sh", "-l"]
        config.terminal = true
        config.stdin = stdin
        config.stdout = stdout
        config.stderr = nil
        config.environmentVariables = [
            "TERM=xterm-256color",
            "HOME=/root",
            "USER=root"
        ]
        
        let execId = "shell-\(UUID().uuidString)"
        let process = try await linux.exec(execId, configuration: config)
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
        
        var config = Containerization.LinuxProcessConfiguration()
        // Run a lightweight non-interactive background loop to stream stats
        config.arguments = ["sh", "-c", "while true; do cat /proc/stat; echo '---MEM---'; cat /proc/meminfo; echo '---LOAD---'; cat /proc/loadavg; echo '---UPTIME---'; cat /proc/uptime; echo '---END---'; sleep 1; done"]
        config.terminal = false
        
        let readerWriter = StatsProcessReaderWriter(continuation: continuation)
        config.stdout = readerWriter
        config.stderr = nil
        
        let process = try await linux.exec("stats-\(UUID().uuidString)", configuration: config)
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
    public func stop(containerId: String) async throws {
        if let activePod = activePods[containerId] {
            if let linuxPod = activePod.linuxPod {
                try? await linuxPod.stop()
            }
            let pod = activePod.pod
            let updatedPod = VesselPod(id: pod.id, name: pod.name, status: .stopped, containers: pod.containers, cpus: pod.cpus, memoryGB: pod.memoryGB)
            activePods[containerId] = ActivePod(pod: updatedPod, linuxPod: nil)
            savePods()
            return
        }

        guard let active = activeContainers[containerId], let linux = active.linux else { return }
        try await linux.stop()
        let vessel = active.vessel
        let updated = VesselContainer(id: vessel.id, name: vessel.name, subtitle: vessel.subtitle, image: vessel.image, status: .stopped, ipAddress: vessel.ipAddress, dnsName: vessel.dnsName, uptime: vessel.uptime, ports: vessel.ports, memoryUsage: vessel.memoryUsage, volume: vessel.volume, exitStatus: "Stopped by user", rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, rootfsSize: vessel.rootfsSize, cpus: vessel.cpus, memoryGB: vessel.memoryGB, envVars: vessel.envVars, volumes: vessel.volumes)
        activeContainers[containerId] = ActiveContainer(vessel: updated, linux: nil, logStream: nil)
        saveContainers()
    }
    
    public func delete(containerId: String) async throws {
        if let activePod = activePods[containerId] {
            if let linuxPod = activePod.linuxPod {
                try? await linuxPod.stop()
            }
            activePods.removeValue(forKey: containerId)
            savePods()
            return
        }

        if let active = activeContainers[containerId], let linux = active.linux {
            try? await linux.stop()
        }
        
        let kernelPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/vmlinux")
        let kernel = Kernel(path: kernelPath, platform: .linuxArm)
        
        var manager = try await ContainerManager(
            kernel: kernel,
            initfsReference: "ghcr.io/apple/containerization/vminit:0.33.4",
            network: SimpleNATNetwork(),
            rosetta: false
        )
        
        try await manager.delete(containerId)
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
            let store = ImageStore.default
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
            let store = ImageStore.default
            actor ProgressTracker {
                var currentBytes: Int64 = 0
                var totalBytes: Int64 = 0
                func add(size: Int64) { currentBytes += size }
                func addTotal(size: Int64) { totalBytes += size }
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
                    switch event {
                    case .addSize(let size):
                        await tracker.add(size: size)
                    case .addTotalSize(let size):
                        await tracker.addTotal(size: size)
                    default:
                        break
                    }
                }
                let pct = await tracker.getProgress()
                progress(pct)
            })
        }
        public func deleteImage(reference: String) async throws {
            let store = ImageStore.default
            try await store.delete(reference: reference, performCleanup: true)
        }
    }
