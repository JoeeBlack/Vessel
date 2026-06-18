import SwiftUI

struct PodDetailView: View {
    @Namespace private var animation
    let pod: VesselPod
    var viewModel: ContainerViewModel
    var onSelectContainer: (String) -> Void

    var isRunning: Bool { pod.status == .running }
    var isLoading: Bool { viewModel.loadingContainers.contains(pod.id) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {

                // Header Area
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(pod.name)
                                .font(.system(size: 32, weight: .bold, design: .serif))
                                .foregroundColor(AppTheme.textPrimary)
                        }

                        HStack(spacing: 4) {
                            Text("Type:")
                                .foregroundColor(AppTheme.textSecondary)
                                .font(.system(size: 14))
                            Text("Compose Pod")
                                .foregroundColor(AppTheme.textPrimary)
                                .font(.system(size: 14, design: .monospaced))
                        }
                    }

                    Spacer()

                    // Actions
                    HStack(spacing: 16) {
                        Button(action: {
                            Task {
                                if isRunning {
                                    await viewModel.stopContainer(id: pod.id)
                                } else {
                                    await viewModel.startContainer(id: pod.id)
                                }
                            }
                        }) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(isRunning ? "Stopping..." : "Starting...")
                                        .foregroundColor(.gray)
                                } else {
                                    Image(systemName: isRunning ? "stop.circle" : "play.circle")
                                        .foregroundColor(isRunning ? .red : .green)
                                    Text(isRunning ? "Stop Pod" : "Start Pod")
                                        .foregroundColor(isRunning ? .red : .green)
                                }
                            }
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(Color.clear)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || pod.status == .creating)

                        Button(action: {
                            Task {
                                await viewModel.deleteContainer(id: pod.id)
                            }
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                Text("Delete")
                                    .foregroundColor(.red)
                            }
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(Color.clear)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning || isLoading)
                        .opacity(isRunning ? 0.5 : 1.0)
                    }
                }

                Divider()
                    .background(AppTheme.cardBorder)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Containers in Pod")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.bottom, 8)

                    ForEach(pod.containers) { container in
                            ContainerCardView(
                                animation: animation,
                                container: container,
                                isLoading: viewModel.loadingContainers.contains(container.id),
                                viewModel: viewModel,
                                onStart: { Task { await viewModel.startContainer(id: container.id) } },
                                onStop: { Task { await viewModel.stopContainer(id: container.id) } },
                                onDelete: { Task { await viewModel.deleteContainer(id: container.id) } }
                            )
                            .onTapGesture {
                                onSelectContainer(container.id)
                            }
                            .cursor(.pointingHand)
                            .drawingGroup()
                        }
                }

            }
            .padding(40)
        }
    }
}
