import Foundation
import Containerization

Task {
    do {
        let kernelPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/vmlinux")
        let kernel = Kernel(path: kernelPath, platform: .linuxArm)
        
        print("1. Creating network...")
        let network = try? VmnetNetwork()
        print("Network created: \(network != nil)")

        print("2. Creating manager...")
        var manager = try await ContainerManager(
            kernel: kernel,
            initfsReference: "ghcr.io/apple/containerization/vminit:0.33.4",
            network: network,
            rosetta: true
        )
        print("Manager created")

        print("3. Creating container instance...")
        let container = try await manager.create(
            "test_hang",
            reference: "alpine:latest",
            rootfsSizeInBytes: 2 * 1024 * 1024 * 1024,
            readOnly: false,
            networking: true
        ) { config in
            config.cpus = 2
            config.memoryInBytes = 2 * 1024 * 1024 * 1024
        }
        print("Container instance created")

        print("4. Calling container.create()...")
        try await container.create()
        print("container.create() succeeded")

        print("5. Calling container.start()...")
        try await container.start()
        print("container.start() succeeded")

    } catch {
        print("ERROR: \(error)")
    }
    exit(0)
}
RunLoop.main.run()
