import re

with open("Sources/Vessel/ContainerDaemon.swift", "r") as f:
    content = f.read()

# 1. SimpleNATNetwork
nat_old = """    public mutating func createInterface(_ id: String) throws -> Containerization.Interface? {
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
    }"""
nat_new = """    public mutating func createInterface(_ id: String) throws -> Containerization.Interface? {
        let ip = nextIP
        nextIP += 1
        return NATInterface(
            address: "192.168.64.\\(ip)/24",
            gateway: "192.168.64.1"
        )
    }

    public mutating func createInterface(_ id: String, mtu: UInt32) throws -> Containerization.Interface? {
        let ip = nextIP
        nextIP += 1
        return NATInterface(
            address: "192.168.64.\\(ip)/24",
            gateway: "192.168.64.1"
        )
    }"""
content = content.replace(nat_old, nat_new)

# 2. kernelPath redeclaration
kernel_old = """        }()
        
        let kernelPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/vmlinux")
        let testKernel = Kernel(path: kernelPath, platform: .linuxArm)
        
        let kernelPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/vmlinux")
        let testKernel = Kernel(path: kernelPath, platform: .linuxArm)"""
kernel_new = """        }()
        
        let kernelPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/vmlinux")
        let testKernel = Kernel(path: kernelPath, platform: .linuxArm)"""
content = content.replace(kernel_old, kernel_new)

# 3. get(pull: true)
content = content.replace("store.get(reference: normalizedRef, pull: true)", "store.get(reference: normalizedRef)")

# 4. pod unpacker unpack
unpack_old = """        let platform = Platform(arch: "arm64", os: "linux", variant: "v8")
        let unpacker = EXT4Unpacker(blockSizeInBytes: 8.gib())
        
        for service in project.services {
            let normalizedRef = normalize(reference: service.image)
            let image = try await store.get(reference: normalizedRef)
            let fsPath = storePath.appendingPathComponent("containers").appendingPathComponent("\\(podId)-\\(service.name)-rootfs.ext4")
            
            let rootfs = try await unpacker.unpack(image, for: platform, at: fsPath, progress: nil)"""
unpack_new = """        let platform = Platform(arch: "arm64", os: "linux", variant: "v8")
        
        for service in project.services {
            let normalizedRef = normalize(reference: service.image)
            let image = try await store.get(reference: normalizedRef)
            let fsPath = storePath.appendingPathComponent("containers").appendingPathComponent("\\(podId)-\\(service.name)-rootfs.ext4")
            
            let rootfs = try await image.unpack(for: platform, at: fsPath, blockSizeInBytes: 8.gib(), progress: nil)"""
content = content.replace(unpack_old, unpack_new)

# 5. LinuxProcessConfiguration inside streamStats
stats_old = """        let (stream, continuation) = AsyncStream<StatsModel>.makeStream()
        
        var config = Containerization.LinuxProcessConfiguration()
        // Run a lightweight non-interactive background loop to stream stats
        config.arguments = ["sh", "-c", "while true; do cat /proc/stat; echo '---MEM---'; cat /proc/meminfo; echo '---LOAD---'; cat /proc/loadavg; echo '---UPTIME---'; cat /proc/uptime; echo '---END---'; sleep 1; done"]
        config.terminal = false
        
        let readerWriter = StatsProcessReaderWriter(continuation: continuation)
        config.stdout = readerWriter
        
        let execId = "stats-\\(UUID().uuidString)"
        let process = try await linux.exec(execId, configuration: config)"""
stats_new = """        let (stream, continuation) = AsyncStream<StatsModel>.makeStream()
        
        let readerWriter = StatsProcessReaderWriter(continuation: continuation)
        let config = ContainerizationOCI.Process(
            args: ["sh", "-c", "while true; do cat /proc/stat; echo '---MEM---'; cat /proc/meminfo; echo '---LOAD---'; cat /proc/loadavg; echo '---UPTIME---'; cat /proc/uptime; echo '---END---'; sleep 1; done"],
            terminal: false
        )
        let execId = "stats-\\(UUID().uuidString)"
        let process = try await linux.exec(execId, configuration: config, stdout: readerWriter)"""
content = content.replace(stats_old, stats_new)

# 6. .stop() on dictionary
stop_old = """        if let activePod = activePods[containerId] {
            if let linuxPod = activePod.linuxContainers {
                try? await linuxPod.stop()
            }
            let pod = activePod.pod"""
stop_new = """        if let activePod = activePods[containerId] {
            for (_, container) in activePod.linuxContainers {
                try? await container.stop()
            }
            let pod = activePod.pod"""
content = content.replace(stop_old, stop_new)

delete_old = """        if let activePod = activePods[containerId] {
            if let linuxPod = activePod.linuxContainers {
                try? await linuxPod.stop()
            }
            activePods.removeValue(forKey: containerId)"""
delete_new = """        if let activePod = activePods[containerId] {
            for (_, container) in activePod.linuxContainers {
                try? await container.stop()
            }
            activePods.removeValue(forKey: containerId)"""
content = content.replace(delete_old, delete_new)

# 7. ProgressEvent .addSize -> .add
content = content.replace("case .add(let size):", "case .add(let size):")

with open("Sources/Vessel/ContainerDaemon.swift", "w") as f:
    f.write(content)
