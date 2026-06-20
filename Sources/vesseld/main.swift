import Foundation
import VesselXPC

class VesselDaemonXPC: NSObject, VesselXPCProtocol {
    func ps(reply: @escaping (String) -> Void) {
        reply("vesseld is running securely")
    }

    func wakeContainer(containerId: String, reply: @escaping (String?, Error?) -> Void) {
        reply("vesseld cannot wake container: not implemented", nil)
    }

    func scanImage(reference: String, reply: @escaping (Data?, Error?) -> Void) {
        reply(nil, NSError(domain: "VesselDaemonXPC", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented in daemon"]))
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
