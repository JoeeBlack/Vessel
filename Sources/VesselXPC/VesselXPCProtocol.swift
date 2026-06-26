import Foundation

@objc public protocol VesselXPCStreamDelegate {
    func onEvent(payload: Data)
    func onComplete(error: Error?)
}

@objc public protocol VesselXPCProtocol {
    func ps(reply: @escaping (String) -> Void)
    func wakeContainer(containerId: String, reply: @escaping (String?, Error?) -> Void)
    func scanImage(reference: String, reply: @escaping (Data?, Error?) -> Void)

    // Unified command method
    func sendCommand(command: String, payload: Data, reply: @escaping (Data?, Error?) -> Void)

    // Stream method using a delegate object
    func openStream(command: String, payload: Data, delegate: VesselXPCStreamDelegate)
}
