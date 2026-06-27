import Foundation
import Network

/// A proxy that forwards TCP traffic from a local host port to a target IP and port.
public final class PortForwarder: @unchecked Sendable {
    public let hostPort: UInt16
    public let targetIP: String
    public let targetPort: UInt16

    private var listener: NWListener?
    private var connections: [UUID: ForwardedConnection] = [:]
    private let queue = DispatchQueue(label: "com.vessel.portforwarder")

    public init(hostPort: UInt16, targetIP: String, targetPort: UInt16) {
        self.hostPort = hostPort
        self.targetIP = targetIP
        self.targetPort = targetPort
    }

    public func start() throws {
        let params = NWParameters.tcp
        guard let port = NWEndpoint.Port(rawValue: hostPort) else {
            throw NSError(domain: "PortForwarder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid host port \(hostPort)"])
        }

        listener = try NWListener(using: params, on: port)

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("PortForwarder listening on port \(self.hostPort) forwarding to \(self.targetIP):\(self.targetPort)")
            case .failed(let error):
                print("PortForwarder listener failed on port \(self.hostPort): \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            self.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        queue.async {
            for (_, forwardedConnection) in self.connections {
                forwardedConnection.stop()
            }
            self.connections.removeAll()
        }
    }

    private func handleNewConnection(_ inbound: NWConnection) {
        guard let port = NWEndpoint.Port(rawValue: targetPort) else { return }
        let id = UUID()
        let outbound = NWConnection(host: NWEndpoint.Host(targetIP), port: port, using: .tcp)

        let forwardedConnection = ForwardedConnection(inbound: inbound, outbound: outbound)

        queue.async {
            self.connections[id] = forwardedConnection
        }

        forwardedConnection.start()

        forwardedConnection.onClose = { [weak self] in
            self?.queue.async {
                self?.connections.removeValue(forKey: id)
            }
        }
    }
}

private final class ForwardedConnection: @unchecked Sendable {
    let inbound: NWConnection
    let outbound: NWConnection
    var onClose: (() -> Void)?

    init(inbound: NWConnection, outbound: NWConnection) {
        self.inbound = inbound
        self.outbound = outbound
    }

    func start() {
        inbound.stateUpdateHandler = { [weak self] state in
            self?.stateChanged(connection: self?.inbound, state: state)
        }
        outbound.stateUpdateHandler = { [weak self] state in
            self?.stateChanged(connection: self?.outbound, state: state)
        }

        inbound.start(queue: .global())
        outbound.start(queue: .global())

        forward(from: inbound, to: outbound)
        forward(from: outbound, to: inbound)
    }

    func stop() {
        inbound.cancel()
        outbound.cancel()
        onClose?()
    }

    private func stateChanged(connection: NWConnection?, state: NWConnection.State) {
        switch state {
        case .failed, .cancelled:
            stop()
        default:
            break
        }
    }

    private func forward(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] content, _, isComplete, error in
            if let content = content, !content.isEmpty {
                destination.send(content: content, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        self?.stop()
                    }
                })
            }

            if isComplete || error != nil {
                self?.stop()
            } else {
                self?.forward(from: source, to: destination)
            }
        }
    }
}
