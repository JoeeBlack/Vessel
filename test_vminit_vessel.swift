import Foundation
import Vessel
import Containerization

Task {
    do {
        let store = ImageStore.default
        print("PULLING VMINIT...")
        let initImage = try await store.getInitImage(reference: "ghcr.io/apple/containerization/vminit:0.33.4")
        print("SUCCESS! Init image fetched.")
    } catch {
        print("ERROR: \(error)")
    }
    exit(0)
}
RunLoop.main.run()
