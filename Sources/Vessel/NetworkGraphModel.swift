import VesselXPC
import SwiftUI

@Observable
public final class NetworkGraphModel: @unchecked Sendable {
    public struct Node: Identifiable, Equatable, Sendable {
        public let id: String
        public var name: String
        public let isNetwork: Bool
        public var position: CGPoint

        public init(id: String, name: String, isNetwork: Bool, position: CGPoint = .zero) {
            self.id = id
            self.name = name
            self.isNetwork = isNetwork
            self.position = position
        }
    }

    public struct Edge: Identifiable, Equatable, Sendable {
        public let id: String
        public let source: String
        public let target: String

        public init(source: String, target: String) {
            self.id = "\(source)-\(target)"
            self.source = source
            self.target = target
        }
    }

    public var nodes: [Node] = []
    public var edges: [Edge] = []

    public init() {}

    @MainActor
    public func update(from containers: [VesselContainer], centerPoint: CGPoint) {
        var newNodes: [Node] = []
        var newEdges: [Edge] = []
        var networks = Set<String>()

        // Find all unique networks
        for container in containers {
            networks.insert(container.networkName)
        }

        // Optionally add default network if missing
        if networks.isEmpty {
            networks.insert("vessel-default")
        }

        // Add network nodes
        for network in networks {
            if let existing = nodes.first(where: { $0.id == "net-\(network)" }) {
                newNodes.append(existing)
            } else {
                newNodes.append(Node(id: "net-\(network)", name: network, isNetwork: true))
            }
        }

        // Add container nodes and edges
        for container in containers {
            if let existing = nodes.first(where: { $0.id == container.id }) {
                var updated = existing
                updated.name = container.name
                newNodes.append(updated)
            } else {
                newNodes.append(Node(id: container.id, name: container.name, isNetwork: false))
            }

            newEdges.append(Edge(source: container.id, target: "net-\(container.networkName)"))
        }

        self.nodes = newNodes
        self.edges = newEdges

        // Run layout algorithm in background
        Task.detached {
            let layoutNodes = await self.calculateLayout(nodes: newNodes, edges: newEdges, centerPoint: centerPoint)
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.nodes = layoutNodes
                }
            }
        }
    }

    private func calculateLayout(nodes: [Node], edges: [Edge], centerPoint: CGPoint) async -> [Node] {
        var layoutNodes = nodes
        let networks = layoutNodes.filter { $0.isNetwork }
        let containers = layoutNodes.filter { !$0.isNetwork }

        // Simple radial layout logic
        // Place networks centrally
        let networkRadius: CGFloat = networks.count > 1 ? 100 : 0
        for (i, network) in networks.enumerated() {
            let angle = (2 * .pi / CGFloat(max(1, networks.count))) * CGFloat(i)
            let x = centerPoint.x + networkRadius * cos(angle)
            let y = centerPoint.y + networkRadius * sin(angle)

            if let index = layoutNodes.firstIndex(where: { $0.id == network.id }) {
                // Only set position if it's currently .zero to avoid snapping back user-moved nodes
                if layoutNodes[index].position == .zero {
                    layoutNodes[index].position = CGPoint(x: x, y: y)
                }
            }
        }

        // Place containers circularly around their connected network
        var containerGroups: [String: [Node]] = [:]
        for container in containers {
            if let edge = edges.first(where: { $0.source == container.id }),
               let networkNode = layoutNodes.first(where: { $0.id == edge.target }) {
                containerGroups[networkNode.id, default: []].append(container)
            } else {
                containerGroups["unconnected", default: []].append(container)
            }
        }

        let containerRadius: CGFloat = 180
        for (networkId, connectedContainers) in containerGroups {
            let center = layoutNodes.first(where: { $0.id == networkId })?.position ?? centerPoint
            for (i, container) in connectedContainers.enumerated() {
                let angle = (2 * .pi / CGFloat(max(1, connectedContainers.count))) * CGFloat(i)
                let x = center.x + containerRadius * cos(angle)
                let y = center.y + containerRadius * sin(angle)

                if let index = layoutNodes.firstIndex(where: { $0.id == container.id }) {
                    if layoutNodes[index].position == .zero {
                        layoutNodes[index].position = CGPoint(x: x, y: y)
                    }
                }
            }
        }

        return layoutNodes
    }
}
