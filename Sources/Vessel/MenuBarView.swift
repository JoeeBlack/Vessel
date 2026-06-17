import SwiftUI

struct MenuBarView: View {
    @Bindable var viewModel: ContainerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Vessel Engine")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button(action: {
                    if let window = NSApp.windows.first {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }) {
                    Image(systemName: "macwindow")
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Open Dashboard")
                .accessibilityLabel("Open Dashboard")

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Quit Vessel")
                .accessibilityLabel("Quit Vessel")
                .padding(.leading, 8)
            }
            .padding()
            .background(AppTheme.mainBackgroundTop)

            Divider().background(AppTheme.cardBorder)

            // Workloads List
            if viewModel.workloads.isEmpty {
                VStack {
                    Spacer()
                    Text("No workloads running.")
                        .foregroundColor(AppTheme.textSecondary)
                        .font(.subheadline)
                    Spacer()
                }
                .frame(height: 150)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.workloads) { workload in
                            MenuBarWorkloadRow(workload: workload, viewModel: viewModel)
                            if workload.id != viewModel.workloads.last?.id {
                                Divider().background(AppTheme.cardBorder.opacity(0.5))
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 300)
        .background(AppTheme.sidebarBackground)
    }
}

struct MenuBarWorkloadRow: View {
    let workload: VesselWorkload
    var viewModel: ContainerViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(workload.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                if isRunning {
                    let stats = viewModel.publishedStats[workload.id] ?? StatsModel()
                    let cpuPct = stats.cpuUsages.isEmpty ? 0.0 : stats.cpuUsages.reduce(0, +) / Double(max(1, stats.cpuUsages.count))
                    let memMb = Double(stats.memUsedBytes) / 1024 / 1024

                    HStack(spacing: 8) {
                        Text(String(format: "CPU: %.0f%%", cpuPct * 100))
                        Text(String(format: "RAM: %.0f MB", memMb))
                    }
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary)
                } else {
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            Spacer()

            // Actions
            if isRunning {
                Button(action: {
                    Task {
                        switch workload {
                        case .container(let c):
                            await viewModel.stopContainer(id: c.id)
                        case .pod(let p):
                            await viewModel.stopContainer(id: p.id)
                        }
                    }
                }) {
                    Image(systemName: "stop.fill")
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(6)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Stop")
                .accessibilityLabel("Stop")
                .disabled(viewModel.loadingContainers.contains(workload.id))
            } else {
                Button(action: {
                    Task {
                        switch workload {
                        case .container(let c):
                            await viewModel.startContainer(id: c.id)
                        case .pod(let p):
                            await viewModel.startContainer(id: p.id)
                        }
                    }
                }) {
                    Image(systemName: "play.fill")
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(6)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Start")
                .accessibilityLabel("Start")
                .disabled(viewModel.loadingContainers.contains(workload.id))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(viewModel.loadingContainers.contains(workload.id) ? AppTheme.accentBlue.opacity(0.1) : Color.clear)
        .task(id: isRunning) {
            if isRunning {
                await viewModel.subscribeToStats(for: workload.id)
            }
        }
    }

    private var isRunning: Bool {
        switch workload {
        case .container(let c): return c.status == .running
        case .pod(let p): return p.status == .running
        }
    }

    private var statusText: String {
        switch workload {
        case .container(let c): return c.status.rawValue.capitalized
        case .pod(let p): return p.status.rawValue.capitalized
        }
    }

    private var statusColor: Color {
        switch workload {
        case .container(let c):
            if c.status == .running { return AppTheme.runningGreen }
            if c.status == .creating || c.status == .starting { return .orange }
            return AppTheme.stoppedRed
        case .pod(let p):
            if p.status == .running { return AppTheme.runningGreen }
            return AppTheme.stoppedRed
        }
    }
}
