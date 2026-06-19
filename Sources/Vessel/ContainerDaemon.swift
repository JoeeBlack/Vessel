import Foundation
import Containerization
import ContainerizationExtras
import ContainerizationOS
import ContainerizationEXT4
import ContainerizationOCI
import ContainerizationError
import Virtualization
import Security
import LocalAuthentication

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

final class SafeNetServiceBox: @unchecked Sendable {
    let svc: NetService
    init(_ svc: NetService) { self.svc = svc }
}

public final class ContainerDaemon: @unchecked Sendable {
    private struct ActiveContainer {
        let vessel: VesselContainer
        var linux: LinuxContainer?
        var logStream: AsyncStream<String>?
        var portForwarders: [PortForwarder] = []
        var netService: NetService?
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
    private var domainRules: [DomainRule] = []
    
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
        loadDomainRules()
    }

    private func fetchFromKeychain(key: String) throws -> String {
        let context = LAContext()
        context.localizedReason = "Vessel requires access to secret '\(key)' to start the container."

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            throw NSError(domain: "VesselKeychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve key '\(key)' from Keychain (status: \(status))"])
        }

        guard var data = item as? Data else {
            throw NSError(domain: "VesselKeychain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data format for key '\(key)' in Keychain"])
        }

        defer {
            data.withUnsafeMutableBytes { ptr in
                ptr.initializeMemory(as: UInt8.self, repeating: 0)
            }
        }

        guard let secret = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "VesselKeychain", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode secret string for key '\(key)'"])
        }

        return secret
    }

    private func resolveEnvironment(_ envVars: [String: String]) throws -> [String] {
        var resolved: [String] = []
        for (key, value) in envVars {
            if value.hasPrefix("keychain://") {
                let keychainKey = String(value.dropFirst("keychain://".count))
                let secret = try fetchFromKeychain(key: keychainKey)
                resolved.append("\(key)=\(secret)")
            } else {
                resolved.append("\(key)=\(value)")
            }
        }
        return resolved
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
            vessel = VesselContainer(id: vessel.id, name: vessel.name, subtitle: vessel.subtitle, image: vessel.image, status: .stopped, ipAddress: vessel.ipAddress, dnsName: vessel.dnsName, uptime: vessel.uptime, ports: vessel.ports, memoryUsage: vessel.memoryUsage, volume: vessel.volume, exitStatus: vessel.exitStatus, rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, isBackground: vessel.isBackground, rootfsSize: vessel.rootfsSize, cpus: vessel.cpus, memoryGB: vessel.memoryGB, envVars: vessel.envVars, volumes: vessel.volumes)
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

    public func getContainerIP(containerId: String) -> String? {
        if let active = activeContainers[containerId], let linux = active.linux {
            return linux.interfaces.first?.address.components(separatedBy: "/").first
        }
        return nil
    }

    public func fetchDomainRules() -> [DomainRule] {
        return domainRules
    }

    public func addDomainRule(_ rule: DomainRule) {
        domainRules.append(rule)
        saveDomainRules()
    }

    public func removeDomainRule(id: UUID) {
        domainRules.removeAll { $0.id == id }
        saveDomainRules()
    }

    private func saveDomainRules() {
        let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/domain_rules.json")
        do {
            let data = try JSONEncoder().encode(domainRules)
            try data.write(to: file, options: [.atomic])
        } catch {
            print("Failed to save domain rules: \(error)")
        }
    }

    private func loadDomainRules() {
        let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/domain_rules.json")
        do {
            let data = try Data(contentsOf: file)
            domainRules = try JSONDecoder().decode([DomainRule].self, from: data)
        } catch {
            print("No saved domain rules found or failed to load.")
            domainRules = []
        }
    }
    
    public func startPod(yamlPath: URL) async throws {
        // Read yaml
        let yamlString = try String(contentsOf: yamlPath, encoding: .utf8)
        let projectName = yamlPath.deletingPathExtension().lastPathComponent
        let project = try ComposeParser.parse(yaml: yamlString, projectName: projectName)
        
        // 🛡️ Sentinel: Ensure App Sandbox access to host paths using Security-Scoped Bookmarks
        for service in project.services {
            for volumeStr in service.volumes {
                let parts = volumeStr.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let hostPath = parts[0]
                    if hostPath.hasPrefix("/") || hostPath.hasPrefix("~") || hostPath.hasPrefix(".") {
                        // It's a path, let's process it
                        var actualHostPath = NSString(string: hostPath).expandingTildeInPath
                        if hostPath.hasPrefix("./") {
                            actualHostPath = yamlPath.deletingLastPathComponent().path + "/" + String(hostPath.dropFirst(2))
                        } else if hostPath.hasPrefix("../") {
                            // Basic support for ../ but resolving symlinks covers this mostly if converted to absolute first
                            let absUrl = URL(fileURLWithPath: hostPath, relativeTo: yamlPath.deletingLastPathComponent())
                            actualHostPath = absUrl.path
                        } else if hostPath == "." {
                            actualHostPath = yamlPath.deletingLastPathComponent().path
                        }

                        let resolvedHostPath = URL(fileURLWithPath: actualHostPath).resolvingSymlinksInPath().path
                        try BookmarkManager.shared.resolveAndAccess(path: resolvedHostPath)
                    }
                }
            }
        }

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
        var testKernelCommandLine = Kernel.CommandLine()
        testKernelCommandLine.kernelArgs.append("ro")
        let testKernel = Kernel(path: kernelPath, platform: .linuxArm, commandline: testKernelCommandLine)
        
        let podId = UUID().uuidString
        var containers: [VesselContainer] = []
        var linuxContainers: [String: LinuxContainer] = [:]
        
        // Pods currently default to arm64, but can be updated later to handle rosetta per service
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
            container.rosetta = false
            
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
                let resolvedServiceEnv = try resolveEnvironment(service.environment)
                allEnvs.append(contentsOf: resolvedServiceEnv)
                container.environment = allEnvs
                container.arguments = args
                
                if let rawString = config.user {
                    container.user = ContainerizationOCI.User(username: rawString)
                }
            } else {
                let resolvedServiceEnv = try resolveEnvironment(service.environment)
                container.environment.append(contentsOf: resolvedServiceEnv)
            }
            
            // 🛡️ Sentinel: Borrow 'hidepid=2' from Kicksecure to harden the container environment.
            // Mounting /proc with hidepid=2 prevents users within the container from seeing processes
            // owned by other users, mitigating information disclosure.
            container.mounts.append(Mount.any(type: "proc", source: "proc", destination: "/proc", options: ["nosuid", "noexec", "nodev", "hidepid=2"]))
            container.mounts.append(Mount.any(type: "tmpfs", source: "tmpfs", destination: "/tmp", options: []))
            container.mounts.append(Mount.any(type: "tmpfs", source: "tmpfs", destination: "/var/run", options: []))

            // Note: we can't manually add VZLinuxRosettaDirectoryShare to container.mounts as a string.
            // The apple/containerization package already automatically mounts VZLinuxRosettaDirectoryShare
            // when container.rosetta = true and sets up binfmt_misc. However, to explicitly fulfill
            // local system setup, we make sure it's enabled here.

            try await container.create()
            try await container.start()
            
            if container.rosetta {
                // Manually run binfmt_misc registration in guest VM
                let binfmtConfig = ContainerizationOCI.Process(
                    args: ["sh", "-c", "mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc; echo ':x86_64:M::\\x7fELF\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\x3e\\x00:\\xff\\xff\\xff\\xff\\xff\\xfe\\xfe\\x00\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xfe\\xff\\xff\\xff:/run/rosetta/rosetta:CF' > /proc/sys/fs/binfmt_misc/register"],
                    terminal: false
                )
                if let proc = try? await container.exec("setup-binfmt", configuration: binfmtConfig) {
                    try? await proc.start()
                }
            }
            
            // Zero out environment to prevent secret leaking
            container.environment = []

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
                isBackground: false,
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
            containers: containers.map { VesselContainer(id: $0.id, name: $0.name, subtitle: $0.subtitle, image: $0.image, status: .running, ipAddress: $0.ipAddress, rosettaEnabled: $0.rosettaEnabled, networkingEnabled: $0.networkingEnabled, isBackground: $0.isBackground, rootfsSize: $0.rootfsSize, cpus: $0.cpus, memoryGB: $0.memoryGB, envVars: $0.envVars, volumes: $0.volumes) },
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
    
    public func start(containerId: String, imageReference: String, name: String, rootfsSizeGB: Double, rosetta: Bool, networking: Bool, isBackground: Bool = false, cpus: Int = 2, memoryGB: Double = 2.0, envVars: [String: String] = [:], volumes: [VesselVolume] = [], portForwards: [VesselPortForward] = [], domain: VesselDomain = .generic) async throws {

        // 🛡️ Sentinel: Validate host file paths BEFORE configuration to prevent container escape
        // We throw an error early instead of silently ignoring invalid mounts which could cause data loss.
        let blockedPrefixes = ["/System", "/etc", "/private", "/var", "/bin", "/sbin", "/usr/bin", "/usr/sbin"]
        for volume in volumes {
            let resolvedHostPath = URL(fileURLWithPath: volume.host).resolvingSymlinksInPath().path
            for blocked in blockedPrefixes {
                if resolvedHostPath == blocked || resolvedHostPath.hasPrefix(blocked + "/") {
                    throw NSError(domain: "Vessel", code: 403, userInfo: [NSLocalizedDescriptionKey: "Security Error: Attempted to mount restricted host path \(volume.host)"])
                }
            }
        }

        // 🛡️ Sentinel: Ensure App Sandbox access to host paths using Security-Scoped Bookmarks
        for volume in volumes {
            try BookmarkManager.shared.resolveAndAccess(path: volume.host)
        }

        @Sendable func debugLog(_ msg: String) {
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
        var kernelCommandLine = Kernel.CommandLine()
        kernelCommandLine.kernelArgs.append("ro")
        let kernel = Kernel(path: kernelPath, platform: .linuxArm, commandline: kernelCommandLine)
        
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
        let platform = rosetta ? Platform(arch: "amd64", os: "linux") : Platform(arch: "arm64", os: "linux", variant: "v8")
        let containerDir = storePath.appendingPathComponent("containers")
        try? FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        
        let fsPath = containerDir.appendingPathComponent("\(containerId)-rootfs.ext4")
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
        
        let imageConfig = try await image.config(for: platform).config
        if let config = imageConfig {
            let cwd = config.workingDir ?? "/"
            let env = config.env ?? []
            let args = (config.entrypoint ?? []) + (config.cmd ?? [])
            
            container.workingDirectory = cwd
            var allEnvs = env
            let resolvedServiceEnv = try resolveEnvironment(envVars)
            allEnvs.append(contentsOf: resolvedServiceEnv)
            container.environment = allEnvs
            container.arguments = args
            
            if let rawString = config.user {
                container.user = ContainerizationOCI.User(username: rawString)
            }
        } else {
            let resolvedServiceEnv = try resolveEnvironment(envVars)
            container.environment.append(contentsOf: resolvedServiceEnv)
        }
        
        // 🛡️ Sentinel: Borrow 'hidepid=2' from Kicksecure to harden the container environment.
        // Mounting /proc with hidepid=2 prevents users within the container from seeing processes
        // owned by other users, mitigating information disclosure.
        container.mounts.append(Mount.any(type: "proc", source: "proc", destination: "/proc", options: ["nosuid", "noexec", "nodev", "hidepid=2"]))
        container.mounts.append(Mount.any(type: "tmpfs", source: "tmpfs", destination: "/tmp", options: []))
        container.mounts.append(Mount.any(type: "tmpfs", source: "tmpfs", destination: "/var/run", options: []))

        for volume in volumes {
            // Check for restricted host paths to prevent container escapes
            let resolvedHostPath = URL(fileURLWithPath: volume.host).resolvingSymlinksInPath().path
            let restrictedPrefixes = ["/System", "/etc", "/private", "/var/run", "/dev"]
            if restrictedPrefixes.contains(where: { resolvedHostPath.hasPrefix($0) }) {
                debugLog("Security Error: Attempt to mount restricted host path \(volume.host)")
                throw NSError(domain: "Vessel", code: 403, userInfo: [NSLocalizedDescriptionKey: "Mounting restricted host path \(volume.host) is not allowed."])
            }
            container.mounts.append(Mount.share(source: volume.host, destination: volume.container, options: ["nosuid", "nodev", "noexec"]))
        }
        
        let stdoutWriter = LogWriter(prefix: "STDOUT", continuation: logContinuation)
        let stderrWriter = LogWriter(prefix: "STDERR", continuation: logContinuation)
        container.stdout = stdoutWriter
        container.stderr = stderrWriter
        
        debugLog("Calling container.create()...")
        let qos: DispatchQoS = isBackground ? .background : .utility
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue(label: "com.vessel.daemon.vm", qos: qos).async {
                Task {
                    do {
                        try await container.create()
                        debugLog("Calling container.start()...")
                        try await container.start()
                        debugLog("Container started successfully!")
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        
        if container.rosetta {
            // Manually run binfmt_misc registration in guest VM
            let binfmtConfig = ContainerizationOCI.Process(
                args: ["sh", "-c", "mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc; echo ':x86_64:M::\\x7fELF\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\x3e\\x00:\\xff\\xff\\xff\\xff\\xff\\xfe\\xfe\\x00\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xfe\\xff\\xff\\xff:/run/rosetta/rosetta:CF' > /proc/sys/fs/binfmt_misc/register"],
                terminal: false
            )
            if let proc = try? await container.exec("setup-binfmt", configuration: binfmtConfig) {
                try? await proc.start()
            }
        }
        
        // Zero out environment to prevent secret leaking
        container.environment = []

        // Start Port Forwarders
        var activeForwarders: [PortForwarder] = []
        if networking {
            // we use the IP configured for the container
            // Currently our simplistic SimpleNATNetwork creates 192.168.64.X
            let targetIP = container.interfaces.first?.address.components(separatedBy: "/").first ?? "127.0.0.1"

            for pf in portForwards {
                guard pf.hostPort >= 1 && pf.hostPort <= 65535,
                      pf.containerPort >= 1 && pf.containerPort <= 65535 else { continue }
                let forwarder = PortForwarder(hostPort: UInt16(pf.hostPort), targetIP: targetIP, targetPort: UInt16(pf.containerPort))
                do {
                    try forwarder.start()
                    activeForwarders.append(forwarder)
                    debugLog("Started port forwarder \(pf.hostPort)->\(targetIP):\(pf.containerPort)")
                } catch {
                    debugLog("Failed to start port forwarder for \(pf.hostPort): \(error)")
                }
            }
        }

        var netService: NetService?
        if networking {
            let safeName = name.replacingOccurrences(of: " ", with: "-").lowercased()
            let svc = NetService(domain: "vessel.test.", type: "_http._tcp.", name: safeName, port: 80)
            netService = svc
            let box = SafeNetServiceBox(svc)
            await MainActor.run {
                box.svc.publish()
            }
        }

        let vessel = VesselContainer(
            id: containerId,
            name: name,
            subtitle: "WORKLOAD",
            image: imageReference,
            status: .running,
            ipAddress: networking ? "127.0.0.1" : nil,
            rosettaEnabled: rosetta,
            networkingEnabled: networking,
            isBackground: isBackground,
            rootfsSize: "\(Int(rootfsSizeGB))GB",
            cpus: cpus,
            memoryGB: memoryGB,
            envVars: envVars,
            volumes: volumes,
            portForwards: portForwards,
            domain: domain
        )
        
        activeContainers[containerId] = ActiveContainer(vessel: vessel, linux: container, logStream: stream, portForwarders: activeForwarders, netService: netService)
        saveContainers()
        debugLog("Container added to activeContainers")
    }
    
    public func start(containerId: String) async throws {
        @Sendable func debugLog(_ msg: String) {
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
        
        // 🛡️ Sentinel: Validate host file paths BEFORE configuration to prevent container escape
        // We throw an error early instead of silently ignoring invalid mounts which could cause data loss.
        let blockedPrefixes = ["/System", "/etc", "/private", "/var", "/bin", "/sbin", "/usr/bin", "/usr/sbin"]
        for volume in vessel.volumes {
            let resolvedHostPath = URL(fileURLWithPath: volume.host).resolvingSymlinksInPath().path
            for blocked in blockedPrefixes {
                if resolvedHostPath == blocked || resolvedHostPath.hasPrefix(blocked + "/") {
                    throw NSError(domain: "Vessel", code: 403, userInfo: [NSLocalizedDescriptionKey: "Security Error: Attempted to mount restricted host path \(volume.host)"])
                }
            }
        }

        // 🛡️ Sentinel: Ensure App Sandbox access to host paths using Security-Scoped Bookmarks
        for volume in vessel.volumes {
            try BookmarkManager.shared.resolveAndAccess(path: volume.host)
        }

        // Recreate linux container if it doesn't exist
        var linux = active.linux
        var stream = active.logStream
        
        if linux == nil {
            let network: SimpleNATNetwork? = vessel.networkingEnabled ? SimpleNATNetwork() : nil
            let kernelPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/vmlinux")
            var kernelCommandLine = Kernel.CommandLine()
            kernelCommandLine.kernelArgs.append("ro")
            let kernel = Kernel(path: kernelPath, platform: .linuxArm, commandline: kernelCommandLine)
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
            let platform = vessel.rosettaEnabled ? Platform(arch: "amd64", os: "linux") : Platform(arch: "arm64", os: "linux", variant: "v8")
            let imageConfig = try await image.config(for: platform).config
            
            if let config = imageConfig {
                let cwd = config.workingDir ?? "/"
                let env = config.env ?? []
                let args = (config.entrypoint ?? []) + (config.cmd ?? [])
                
                container.workingDirectory = cwd
                var allEnvs = env
                let resolvedServiceEnv = try resolveEnvironment(vessel.envVars)
                allEnvs.append(contentsOf: resolvedServiceEnv)
                container.environment = allEnvs
                container.arguments = args
                
                if let rawString = config.user {
                    container.user = ContainerizationOCI.User(username: rawString)
                }
            } else {
                let resolvedServiceEnv = try resolveEnvironment(vessel.envVars)
                container.environment.append(contentsOf: resolvedServiceEnv)
            }
            
            // 🛡️ Sentinel: Borrow 'hidepid=2' from Kicksecure to harden the container environment.
            // Mounting /proc with hidepid=2 prevents users within the container from seeing processes
            // owned by other users, mitigating information disclosure.
            container.mounts.append(Mount.any(type: "proc", source: "proc", destination: "/proc", options: ["nosuid", "noexec", "nodev", "hidepid=2"]))
            container.mounts.append(Mount.any(type: "tmpfs", source: "tmpfs", destination: "/tmp", options: []))
            container.mounts.append(Mount.any(type: "tmpfs", source: "tmpfs", destination: "/var/run", options: []))

            for volume in vessel.volumes {
                container.mounts.append(Mount.share(source: volume.host, destination: volume.container, options: ["nosuid", "nodev", "noexec"]))
            }
            
            let stdoutWriter = LogWriter(prefix: "STDOUT", continuation: logContinuation)
            let stderrWriter = LogWriter(prefix: "STDERR", continuation: logContinuation)
            container.stdout = stdoutWriter
            container.stderr = stderrWriter
            debugLog("Calling container.create()...")
            let qosCreate: DispatchQoS = vessel.isBackground ? .background : .utility
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue(label: "com.vessel.daemon.vm", qos: qosCreate).async {
                    Task {
                        do {
                            try await container.create()
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            linux = container
        }
        
        // Security: Avoid force unwrap to prevent application crash if the container fails to initialize.
        guard let linuxContainer = linux else {
            throw NSError(domain: "Vessel", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Linux container"])
        }

        debugLog("Calling linuxContainer.start()...")
        let qosStart: DispatchQoS = vessel.isBackground ? .background : .utility
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue(label: "com.vessel.daemon.vm", qos: qosStart).async {
                Task {
                    do {
                        try await linuxContainer.start()
                        debugLog("linuxContainer.start() succeeded!")
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        
        if linuxContainer.rosetta {
            // Manually run binfmt_misc registration in guest VM
            let binfmtConfig = ContainerizationOCI.Process(
                args: ["sh", "-c", "mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc; echo ':x86_64:M::\\x7fELF\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\x3e\\x00:\\xff\\xff\\xff\\xff\\xff\\xfe\\xfe\\x00\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xfe\\xff\\xff\\xff:/run/rosetta/rosetta:CF' > /proc/sys/fs/binfmt_misc/register"],
                terminal: false
            )
            if let proc = try? await linuxContainer.exec("setup-binfmt", configuration: binfmtConfig) {
                try? await proc.start()
            }
        }
        
        // Zero out environment to prevent secret leaking
        linuxContainer.environment = []

        var activeForwarders: [PortForwarder] = []
        var netService: NetService?
        if vessel.networkingEnabled {
            let safeName = vessel.name.replacingOccurrences(of: " ", with: "-").lowercased()
            let svc = NetService(domain: "vessel.test.", type: "_http._tcp.", name: safeName, port: 80)
            netService = svc
            let box = SafeNetServiceBox(svc)
            await MainActor.run {
                box.svc.publish()
            }

            let targetIP = linuxContainer.interfaces.first?.address.components(separatedBy: "/").first ?? "127.0.0.1"
            for pf in vessel.portForwards {
                guard pf.hostPort >= 1 && pf.hostPort <= 65535,
                      pf.containerPort >= 1 && pf.containerPort <= 65535 else { continue }
                let forwarder = PortForwarder(hostPort: UInt16(pf.hostPort), targetIP: targetIP, targetPort: UInt16(pf.containerPort))
                do {
                    try forwarder.start()
                    activeForwarders.append(forwarder)
                } catch {
                    debugLog("Failed to start port forwarder for \(pf.hostPort): \(error)")
                }
            }
        }

        let updated = VesselContainer(id: vessel.id, name: vessel.name, subtitle: vessel.subtitle, image: vessel.image, status: .running, ipAddress: vessel.networkingEnabled ? "127.0.0.1" : nil, dnsName: vessel.dnsName, uptime: vessel.uptime, ports: vessel.ports, memoryUsage: vessel.memoryUsage, volume: vessel.volume, exitStatus: nil, rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, isBackground: vessel.isBackground, rootfsSize: vessel.rootfsSize, cpus: vessel.cpus, memoryGB: vessel.memoryGB, envVars: vessel.envVars, volumes: vessel.volumes, portForwards: vessel.portForwards, domain: vessel.domain)
        activeContainers[containerId] = ActiveContainer(vessel: updated, linux: linux, logStream: stream, portForwarders: activeForwarders, netService: netService)
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
            args: ["sh", "-c", "while true; do cat /proc/stat; echo '---MEM---'; cat /proc/meminfo; echo '---LOAD---'; cat /proc/loadavg; echo '---UPTIME---'; cat /proc/uptime; echo '---NET---'; cat /proc/net/dev; echo '---END---'; sleep 1; done"],
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

    public func pauseAll() async throws {
        // Pause all running linux containers
        for (id, active) in activeContainers {
            if let linux = active.linux, active.vessel.status == .running {
                try? await linux.pause()

                let vessel = active.vessel
                let updated = VesselContainer(id: vessel.id, name: vessel.name, subtitle: vessel.subtitle, image: vessel.image, status: .paused, ipAddress: vessel.ipAddress, dnsName: vessel.dnsName, uptime: vessel.uptime, ports: vessel.ports, memoryUsage: vessel.memoryUsage, volume: vessel.volume, exitStatus: vessel.exitStatus, rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, rootfsSize: vessel.rootfsSize, cpus: vessel.cpus, memoryGB: vessel.memoryGB, envVars: vessel.envVars, volumes: vessel.volumes, portForwards: vessel.portForwards, domain: vessel.domain)
                activeContainers[id] = ActiveContainer(vessel: updated, linux: linux, logStream: active.logStream, portForwarders: active.portForwarders)
            }
        }
        for (id, activePod) in activePods {
            if activePod.pod.status == .running {
                for (_, linux) in activePod.linuxContainers {
                    try? await linux.pause()
                }
                let pod = activePod.pod
                let updatedContainers = pod.containers.map {
                    let container = $0
                    let updated = VesselContainer(id: container.id, name: container.name, subtitle: container.subtitle, image: container.image, status: .paused, ipAddress: container.ipAddress, dnsName: container.dnsName, uptime: container.uptime, ports: container.ports, memoryUsage: container.memoryUsage, volume: container.volume, exitStatus: container.exitStatus, rosettaEnabled: container.rosettaEnabled, networkingEnabled: container.networkingEnabled, rootfsSize: container.rootfsSize, cpus: container.cpus, memoryGB: container.memoryGB, envVars: container.envVars, volumes: container.volumes, portForwards: container.portForwards, domain: container.domain)
                    return updated
                }
                let updatedPod = VesselPod(id: pod.id, name: pod.name, status: .paused, containers: updatedContainers, cpus: pod.cpus, memoryGB: pod.memoryGB)
                activePods[id] = ActivePod(pod: updatedPod, linuxContainers: activePod.linuxContainers)
            }
        }
        saveContainers()
        savePods()
    }

    public func resumeAll() async throws {
        // Resume all paused linux containers
        for (id, active) in activeContainers {
            if let linux = active.linux, active.vessel.status == .paused {
                try? await linux.resume()

                let vessel = active.vessel
                let updated = VesselContainer(id: vessel.id, name: vessel.name, subtitle: vessel.subtitle, image: vessel.image, status: .running, ipAddress: vessel.ipAddress, dnsName: vessel.dnsName, uptime: vessel.uptime, ports: vessel.ports, memoryUsage: vessel.memoryUsage, volume: vessel.volume, exitStatus: vessel.exitStatus, rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, rootfsSize: vessel.rootfsSize, cpus: vessel.cpus, memoryGB: vessel.memoryGB, envVars: vessel.envVars, volumes: vessel.volumes, portForwards: vessel.portForwards, domain: vessel.domain)
                activeContainers[id] = ActiveContainer(vessel: updated, linux: linux, logStream: active.logStream, portForwarders: active.portForwarders)
            }
        }
        for (id, activePod) in activePods {
            if activePod.pod.status == .paused {
                for (_, linux) in activePod.linuxContainers {
                    try? await linux.resume()
                }
                let pod = activePod.pod
                let updatedContainers = pod.containers.map {
                    let container = $0
                    let updated = VesselContainer(id: container.id, name: container.name, subtitle: container.subtitle, image: container.image, status: .running, ipAddress: container.ipAddress, dnsName: container.dnsName, uptime: container.uptime, ports: container.ports, memoryUsage: container.memoryUsage, volume: container.volume, exitStatus: container.exitStatus, rosettaEnabled: container.rosettaEnabled, networkingEnabled: container.networkingEnabled, rootfsSize: container.rootfsSize, cpus: container.cpus, memoryGB: container.memoryGB, envVars: container.envVars, volumes: container.volumes, portForwards: container.portForwards, domain: container.domain)
                    return updated
                }
                let updatedPod = VesselPod(id: pod.id, name: pod.name, status: .running, containers: updatedContainers, cpus: pod.cpus, memoryGB: pod.memoryGB)
                activePods[id] = ActivePod(pod: updatedPod, linuxContainers: activePod.linuxContainers)
            }
        }
        saveContainers()
        savePods()
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

        for pf in active.portForwarders {
            pf.stop()
        }

        active.netService?.stop()

        if force {
            // Some containers might be stubborn, stop them forcefully. The api currently provides stop()
            // In a real framework extension, a kill() signal would be sent. Here we call stop and release resources.
            try? await linux.stop()
        } else {
            try await linux.stop()
        }

        let vessel = active.vessel
        let updated = VesselContainer(id: vessel.id, name: vessel.name, subtitle: vessel.subtitle, image: vessel.image, status: .stopped, ipAddress: vessel.ipAddress, dnsName: vessel.dnsName, uptime: vessel.uptime, ports: vessel.ports, memoryUsage: vessel.memoryUsage, volume: vessel.volume, exitStatus: force ? "Force Stopped by user" : "Stopped by user", rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, isBackground: vessel.isBackground, rootfsSize: vessel.rootfsSize, cpus: vessel.cpus, memoryGB: vessel.memoryGB, envVars: vessel.envVars, volumes: vessel.volumes, portForwards: vessel.portForwards, domain: vessel.domain)
        activeContainers[containerId] = ActiveContainer(vessel: updated, linux: nil, logStream: nil, portForwarders: [])
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

        if let active = activeContainers[containerId] {
            for pf in active.portForwarders {
                pf.stop()
            }
            active.netService?.stop()
            if let linux = active.linux {
                try? await linux.stop()
            }
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
            let allImages = try await store.list()
            let images = allImages.filter { !$0.reference.contains("ghcr.io/apple/containerization/vminit") }
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
                    if event.event == "add-size" {
                        if let size = event.value as? Int64 { await tracker.add(size: size) }
                        else if let size = event.value as? Int { await tracker.add(size: Int64(size)) }
                        else if let size = event.value as? UInt64 { await tracker.add(size: Int64(size)) }
                    } else if event.event == "add-total-size" {
                        if let size = event.value as? Int64 { await tracker.addTotal(totalSize: size) }
                        else if let size = event.value as? Int { await tracker.addTotal(totalSize: Int64(size)) }
                        else if let size = event.value as? UInt64 { await tracker.addTotal(totalSize: Int64(size)) }
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
