import Foundation
import VesselXPC

class VesselDaemonXPC: NSObject, VesselXPCProtocol {
    func ps(reply: @escaping (String) -> Void) {
        reply("vesseld is running securely")
    }
}

class VesselDaemonDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: VesselXPCProtocol.self)
        newConnection.exportedObject = VesselDaemonXPC()
        newConnection.resume()
        return true
    }
}

let delegate = VesselDaemonDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
