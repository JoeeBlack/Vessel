import Foundation
import Vessel

let daemon = ContainerDaemon()

Task {
    do {
        print("Starting container daemon...")
        let newId = UUID().uuidString.uppercased()
        try await daemon.start(
            containerId: newId,
            imageReference: "alpine:latest",
            name: "TestAlpine",
            rootfsSizeGB: 1.0,
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
