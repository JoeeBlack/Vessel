import Foundation
import Vessel

let daemon = ContainerDaemon()

Task {
    do {
        print("Starting container...")
        try await daemon.start(
            containerId: "test-id",
            imageReference: "alpine:latest",
            name: "test-name",
            rootfsSizeGB: 8.0,
            rosetta: false,
            networking: true
        )
        print("Container started successfully!")
    } catch {
        print("Error: \(error)")
    }
    exit(0)
}

RunLoop.main.run()
