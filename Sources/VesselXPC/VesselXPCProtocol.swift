import Foundation

@objc public protocol VesselXPCProtocol {
    func ps(reply: @escaping (String) -> Void)
}
