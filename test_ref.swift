import Foundation
import Containerization

Task {
    do {
        let _ = try Reference.parse("alpine:latest")
        print("Success alpine:latest")
    } catch {
        print("Error alpine:latest: \(error)")
    }
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
