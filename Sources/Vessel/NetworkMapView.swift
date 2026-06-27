import VesselXPC
import SwiftUI

public struct NetworkMapView: View {
    @Environment(ContainerViewModel.self) private var viewModel
    @State private var graphModel = NetworkGraphModel()

    // Track canvas size to center the layout
    @State private var canvasSize: CGSize = .zero

    // Dragging state
    @State private var draggedNodeId: String? = nil

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header Area
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Topology")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                    Text("Interactive visualization of container network connections.")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()

                Button(action: refreshGraph) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Refresh Layout")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.cardBorder)
                    .foregroundColor(AppTheme.textPrimary)
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)

            // Map Area
            GeometryReader { geometry in
                ZStack {
                    // Draw Edges using Canvas for performance
                    Canvas { context, size in
                        for edge in graphModel.edges {
                            guard let sourceNode = graphModel.nodes.first(where: { $0.id == edge.source }),
                                  let targetNode = graphModel.nodes.first(where: { $0.id == edge.target }) else { continue }

                            var path = Path()
                            path.move(to: sourceNode.position)
                            path.addLine(to: targetNode.position)

                            context.stroke(path, with: .color(AppTheme.accentBlue.opacity(0.3)), lineWidth: 2)
                        }
                    }

                    // Draw Nodes
                    ForEach($graphModel.nodes) { $node in
                        NodeView(node: node)
                            .position(node.position)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if draggedNodeId == nil {
                                            draggedNodeId = node.id
                                        }
                                        if draggedNodeId == node.id {
                                            node.position = value.location
                                        }
                                    }
                                    .onEnded { _ in
                                        draggedNodeId = nil
                                    }
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.mainBackgroundGradient)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .onAppear {
                    canvasSize = geometry.size
                    refreshGraph()
                }
                .onChange(of: geometry.size) { oldSize, newSize in
                    canvasSize = newSize
                    refreshGraph()
                }
                .onChange(of: viewModel.workloads) { _, _ in
                    refreshGraph()
                }
            }
        }
    }

    private func refreshGraph() {
        // Reset positions to .zero for containers to recalculate layout if they are dragged far away, or just pass existing and let them stay.
        // Let's reset positions when refresh is clicked manually, but for automatic updates, keep positions.

        // Ensure we have a valid center
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        if center.x > 0 && center.y > 0 {
            let containers = viewModel.workloads.compactMap { workload -> VesselContainer? in
                if case .container(let c) = workload {
                    return c
                }
                return nil
            }
            graphModel.update(from: containers, centerPoint: center)
        }
    }
}

struct NodeView: View {
    let node: NetworkGraphModel.Node

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(node.isNetwork ? AppTheme.accentBlue.opacity(0.2) : AppTheme.cardBackground)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle().stroke(node.isNetwork ? AppTheme.accentBlue : AppTheme.cardBorder, lineWidth: 2)
                    )

                Image(systemName: node.isNetwork ? "network" : "cube.box.fill")
                    .font(.system(size: 24))
                    .foregroundColor(node.isNetwork ? AppTheme.accentBlue : AppTheme.textPrimary)
            }

            Text(node.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 100)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Material.ultraThin)
                .cornerRadius(4)
        }
        .cursor(.pointingHand)
    }
}
