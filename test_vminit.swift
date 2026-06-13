import Foundation
import Containerization
import ContainerizationOS

let store = ImageStore.default

Task {
    do {
        print("Pulling vminit...")
        let initImage = try await store.getInitImage(reference: "ghcr.io/apple/vminit:main")
        print("Successfully pulled vminit!")
    } catch {
        print("Failed to pull vminit: \(error)")
    }
    exit(0)
}

RunLoop.main.run()
