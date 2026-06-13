import Foundation
import Containerization

Task {
    do {
        let network = try VmnetNetwork()
        print("SUCCESS! network created: \(network.subnet)")
    } catch {
        print("ERROR: \(error)")
    }
    exit(0)
}
RunLoop.main.run()
