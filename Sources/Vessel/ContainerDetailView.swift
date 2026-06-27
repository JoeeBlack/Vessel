import VesselXPC
import SwiftUI


struct ContainerDetailView: View {
    let container: VesselContainer
    var viewModel: ContainerViewModel
    var animation: Namespace.ID
    
    @State private var logSearchText = ""
    @AppStorage("enableHaptics") private var enableHaptics: Bool = true
    @State private var hapticTrigger: Int = 0
    // Mock data for charts
    let cpuData: [Double] = [2, 3, 5, 4, 8, 12, 14, 10, 5, 8, 14.2, 10]
    let memData: [Double] = [0.8, 0.8, 0.85, 0.9, 0.95, 1.0, 1.1, 1.15, 1.2, 1.2, 1.2, 1.2]
    
    var body: some View {
        let isRunning = container.status == .running || container.status == .paused
        let isLoading = viewModel.loadingContainers.contains(container.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // Header Area
                HStack(alignment: .center) {
                    if container.domain != .generic {
                        Rectangle()
                            .fill(AppTheme.color(for: container.domain))
                            .frame(width: 6, height: 48)
                            .cornerRadius(3)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(container.name)
                                .font(.system(size: 32, weight: .semibold, design: .default))
                                .foregroundColor(AppTheme.textPrimary)

                            if container.domain != .generic {
                                Text(container.domain.rawValue.uppercased())
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.color(for: container.domain).opacity(0.1))
                                    .foregroundColor(AppTheme.color(for: container.domain))
                                    .cornerRadius(6)
                                    .matchedGeometryEffect(id: "domain-\(container.id)", in: animation)
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Text("Image:")
                                .foregroundColor(AppTheme.textSecondary)
                                .font(.system(size: 14))
                            Text(container.image)
                                .foregroundColor(AppTheme.textPrimary)
                                .font(.system(size: 14, design: .monospaced))
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    if container.status == .creating || container.status == .starting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)

                            Text(container.status.rawValue.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                        .matchedGeometryEffect(id: "status-\(container.id)", in: animation)
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(container.status == .running ? AppTheme.runningGreen : AppTheme.stoppedRed)
                                .frame(width: 6, height: 6)

                            Text(container.status.rawValue.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(container.status == .running ? AppTheme.runningGreen : AppTheme.stoppedRed)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(container.status == .running ? AppTheme.runningGreen.opacity(0.1) : AppTheme.stoppedRed.opacity(0.1))
                        .cornerRadius(12)
                        .matchedGeometryEffect(id: "status-\(container.id)", in: animation)
                    }

                    // Actions
                    HStack(spacing: 16) {
                        Button(action: {
                            hapticTrigger += 1
                            Task {
                                if isRunning {
                                    await viewModel.stopContainer(id: container.id)
                                } else {
                                    await viewModel.startContainer(id: container.id)
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
                                    Text(isRunning ? "Stop" : "Start")
                                        .foregroundColor(isRunning ? .red : .green)
                                }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(Color.clear)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                        .sensoryFeedback(.impact, trigger: hapticTrigger) { _, _ in enableHaptics }
                        
                        Button(action: {
                            hapticTrigger += 1
                            Task {
                                await viewModel.stopContainer(id: container.id)
                                await viewModel.startContainer(id: container.id)
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Restart")
                                    .foregroundColor(AppTheme.textPrimary)
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(Color.clear)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isRunning || isLoading)
                        .opacity(isRunning ? 1.0 : 0.5)
                        .sensoryFeedback(.impact, trigger: hapticTrigger) { _, _ in enableHaptics }
                        
                        Button(action: {
                            Task {
                                await viewModel.toggleShell(for: container.id)
                            }
                        }) {
                            HStack {
                                Image(systemName: "terminal.fill")
                                Text("Exec")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(isRunning ? AppTheme.accentBlue : Color.gray)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isRunning)
                    }
                }
                
                // Main Layout: Chart on Left, Cards on Right
                HStack(alignment: .top, spacing: 24) {
                    // Left Column (Chart)
                    VStack(alignment: .leading, spacing: 16) {
                        ContainerResourceChartsView(container: container, viewModel: viewModel)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right Column (Metadata)
                    VStack(spacing: 24) {
                        ContainerNetworkCardView(container: container)
                        ContainerMetadataCardView(container: container, viewModel: viewModel)
                    }
                    .frame(width: 320)
                }
                
                // Console Logs
                ContainerConsoleView(container: container, viewModel: viewModel)
                
            }
            .padding(40)
        }
        .task(id: container.id) {
            await viewModel.streamLogs(for: container.id)
        }
        .task(id: container.id) {
            await viewModel.subscribeToStats(for: container.id)
        }
    }
}
