import SwiftUI
import Charts

struct ContainerDetailView: View {
    let container: VesselContainer
    var viewModel: ContainerViewModel
    
    // Mock data for charts
    let cpuData: [Double] = [2, 3, 5, 4, 8, 12, 14, 10, 5, 8, 14.2, 10]
    let memData: [Double] = [0.8, 0.8, 0.85, 0.9, 0.95, 1.0, 1.1, 1.15, 1.2, 1.2, 1.2, 1.2]
    
    var body: some View {
        let isRunning = container.status == .running
        let isLoading = viewModel.loadingContainers.contains(container.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // Header Area
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(container.name)
                                .font(.system(size: 32, weight: .bold, design: .serif))
                                .foregroundColor(AppTheme.textPrimary)
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
                    
                    // Actions
                    HStack(spacing: 16) {
                        Button(action: {
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
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(Color.clear)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                        
                        Button(action: {
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
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(Color.clear)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isRunning || isLoading)
                        .opacity(isRunning ? 1.0 : 0.5)
                        
                        Button(action: {
                            Task {
                                await viewModel.toggleShell(for: container.id)
                            }
                        }) {
                            HStack {
                                Image(systemName: "terminal.fill")
                                Text("Exec")
                            }
                            .font(.system(size: 13, weight: .bold))
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
                        resourceChartCard()
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right Column (Metadata)
                    VStack(spacing: 24) {
                        networkCard()
                        metadataCard()
                    }
                    .frame(width: 320)
                }
                
                // Console Logs
                if let inputPipe = viewModel.shellInputPipes[container.id],
                   let outputPipe = viewModel.shellOutputPipes[container.id] {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Console Logs")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Image(systemName: "line.3.horizontal.decrease")
                                .foregroundColor(AppTheme.textSecondary)
                            Image(systemName: "arrow.down.to.line")
                                .foregroundColor(AppTheme.textSecondary)
                                .padding(.leading, 12)
                        }
                        
                        // Console View
                        VStack(alignment: .leading, spacing: 0) {
                            // Mac Window Buttons (mock)
                            HStack(spacing: 8) {
                                Circle().fill(Color(red: 235/255, green: 80/255, blue: 80/255)).frame(width: 10, height: 10)
                                Circle().fill(Color(red: 235/255, green: 180/255, blue: 60/255)).frame(width: 10, height: 10)
                                Circle().fill(Color(red: 60/255, green: 180/255, blue: 80/255)).frame(width: 10, height: 10)
                                Spacer()
                            }
                            .padding(16)
                            
                            VMTerminalView(
                                inputHandle: inputPipe.fileHandleForWriting,
                                outputHandle: outputPipe.fileHandleForReading
                            )
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                        }
                        .frame(height: 350)
                        .background(AppTheme.darkTerminalBackground)
                        .cornerRadius(8)
                        .opacity(isRunning ? 1.0 : 0.5)
                        .disabled(!isRunning)
                    }
                }
                
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
    
    @ViewBuilder
    private func resourceChartCard() -> some View {
        let stats = viewModel.publishedStats[container.id] ?? StatsModel()
        
        VStack(alignment: .leading, spacing: 16) {
            Text("Resource Utilization")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundColor(AppTheme.textPrimary)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 24) {
                    // Left side: CPU and Mem bars
                    VStack(alignment: .leading, spacing: 4) {
                        if stats.cpuUsages.isEmpty {
                            htopBar(label: "1", percentage: 0.0, color: AppTheme.runningGreen, text: "0.0%")
                        } else {
                            ForEach(Array(stats.cpuUsages.enumerated()), id: \.offset) { index, usage in
                                htopBar(label: "\(index + 1)", percentage: usage, color: AppTheme.runningGreen, text: String(format: "%.1f%%", usage * 100))
                            }
                        }
                        
                        let memPct = stats.memTotalBytes > 0 ? Double(stats.memUsedBytes) / Double(stats.memTotalBytes) : 0.0
                        let memText = String(format: "%.1fM/%.1fM", Double(stats.memUsedBytes) / 1024 / 1024, Double(stats.memTotalBytes) / 1024 / 1024)
                        htopBar(label: "Mem", percentage: memPct, color: .cyan, text: memText)
                        
                        let swpPct = stats.swapTotalBytes > 0 ? Double(stats.swapUsedBytes) / Double(stats.swapTotalBytes) : 0.0
                        let swpText = String(format: "%.1fM/%.1fM", Double(stats.swapUsedBytes) / 1024 / 1024, Double(stats.swapTotalBytes) / 1024 / 1024)
                        htopBar(label: "Swp", percentage: swpPct, color: .red, text: swpText)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right side: Stats
                    VStack(alignment: .leading, spacing: 4) {
                        htopStat(label: "Tasks:", value: "\(stats.tasks), \(stats.runningTasks) running")
                        let load = stats.loadAverage
                        htopStat(label: "Load average:", value: String(format: "%.2f %.2f %.2f", load[0], load[1], load[2]))
                        
                        let totalSecs = Int(stats.uptimeSeconds)
                        let hrs = totalSecs / 3600
                        let mins = (totalSecs % 3600) / 60
                        let secs = totalSecs % 60
                        htopStat(label: "Uptime:", value: String(format: "%02d:%02d:%02d", hrs, mins, secs))
                    }
                    .frame(width: 250)
                }
            }
            .padding(16)
            .background(AppTheme.darkTerminalBackground)
            .cornerRadius(8)
        }
        .padding(32)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 5)
    }
    
    private func htopBar(label: String, percentage: Double, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 30, alignment: .trailing)
            
            HStack(spacing: 0) {
                Text("[")
                    .foregroundColor(.white)
                
                GeometryReader { geo in
                    let totalPipes = Int(geo.size.width / 7.2)
                    let activePipes = Int(Double(totalPipes) * percentage)
                    
                    Text(String(repeating: "|", count: activePipes))
                        .foregroundColor(color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Text(text)
                    .foregroundColor(.white)
                    .frame(width: 80, alignment: .trailing)
                
                Text("]")
                    .foregroundColor(.white)
            }
            .font(.system(size: 12, design: .monospaced))
        }
        .frame(height: 16)
    }
    
    private func htopStat(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(.white)
            Text(value)
                .foregroundColor(AppTheme.runningGreen)
        }
        .font(.system(size: 12, design: .monospaced))
    }
    
    @ViewBuilder
    private func networkCard() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Network")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundColor(AppTheme.textPrimary)
            
            VStack(spacing: 16) {
                detailRow(label: "IP Address", value: container.ipAddress ?? "-")
                Divider().background(AppTheme.cardBorder)
                detailRow(label: "Ports", value: container.ports ?? "-")
                Divider().background(AppTheme.cardBorder)
                detailRow(label: "Gateway", value: "-")
            }
        }
        .padding(24)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 5)
    }
    
    @ViewBuilder
    private func metadataCard() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Metadata")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundColor(AppTheme.textPrimary)
            
            VStack(spacing: 16) {
                detailRow(label: "Created", value: "-", isMonospaced: false)
                Divider().background(AppTheme.cardBorder)
                detailRow(label: "Uptime", value: formattedUptime(), isMonospaced: false)
            }

        }
        .padding(24)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 5)
    }
    
    private func detailRow(label: String, value: String, isMonospaced: Bool = true) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(isMonospaced ? .system(size: 13, design: .monospaced) : .system(size: 13))
                .foregroundColor(AppTheme.textPrimary)
        }
    }
    
    private func formattedUptime() -> String {
        guard container.status == .running else { return container.uptime ?? "-" }
        guard let stats = viewModel.publishedStats[container.id], stats.uptimeSeconds > 0 else { return "Starting..." }
        let totalSeconds = Int(stats.uptimeSeconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
