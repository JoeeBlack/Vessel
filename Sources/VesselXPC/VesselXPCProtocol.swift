import Foundation

@objc public protocol VesselXPCProtocol {
    func ps(reply: @escaping (String) -> Void)
    func wakeContainer(containerId: String, reply: @escaping (String?, Error?) -> Void)
}
