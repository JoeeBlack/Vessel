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
        let isRunning = container.status == .running
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
                                .font(.system(size: 32, weight: .bold, design: .serif))
                                .foregroundColor(AppTheme.textPrimary)

                            if container.domain != .generic {
                                Text(container.domain.rawValue.uppercased())
                                    .font(.system(size: 12, weight: .bold))
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
                                .font(.system(size: 10, weight: .bold))
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
                                .font(.system(size: 10, weight: .bold))
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
                            .font(.system(size: 13, weight: .bold))
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
                            .font(.system(size: 13, weight: .bold))
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

                            // Log Search
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(AppTheme.textSecondary)
                                TextField("Filter logs...", text: $logSearchText)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .frame(width: 150)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Material.ultraThin)
                            .background(AppTheme.cardBackground)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.cardBorder, lineWidth: 1))

                            Image(systemName: "line.3.horizontal.decrease")
                                .foregroundColor(AppTheme.textSecondary)
                                .padding(.leading, 8)
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
                                outputHandle: outputPipe.fileHandleForReading,
                                filterText: logSearchText
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
        let statsHistory = viewModel.statsHistory[container.id] ?? []
        let currentStats = statsHistory.last ?? StatsModel()
        
        VStack(alignment: .leading, spacing: 16) {
            Text("Resource Utilization")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundColor(AppTheme.textPrimary)
            
            HStack(spacing: 24) {
                // CPU Chart
                VStack(alignment: .leading) {
                    Text("CPU Usage")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)

                    let cpuData = statsHistory.map { stat -> Double in
                        stat.cpuUsages.isEmpty ? 0 : stat.cpuUsages.reduce(0, +) / Double(stat.cpuUsages.count) * 100
                    }

                    HStack {
                        VStack(alignment: .trailing) {
                            Text("100%").font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text("50%").font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text("0%").font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(width: 30)

                        CanvasLineChart(
                            dataSets: [cpuData],
                            colors: [AppTheme.runningGreen],
                            yMax: 100
                        )
                    }
                    .frame(height: 120)
                }

                // RAM Chart
                VStack(alignment: .leading) {
                    Text("Memory Usage")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    let memData = statsHistory.map { Double($0.memUsedBytes) / 1024 / 1024 }
                    let memMax = currentStats.memTotalBytes > 0 ? Double(currentStats.memTotalBytes) / 1024 / 1024 : 1000.0

                    HStack {
                        VStack(alignment: .trailing) {
                            Text(String(format: "%.0fM", memMax)).font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text(String(format: "%.0fM", memMax / 2)).font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text("0M").font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(width: 40)

                        CanvasLineChart(
                            dataSets: [memData],
                            colors: [Color.cyan],
                            yMax: memMax
                        )
                    }
                    .frame(height: 120)
                }

                // Network I/O Chart
                VStack(alignment: .leading) {
                    Text("Network I/O")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)

                    let rxData = statsHistory.map { Double($0.netRxDelta) / 1024 / 1024 }
                    let txData = statsHistory.map { Double($0.netTxDelta) / 1024 / 1024 }
                    let maxNet = max((rxData + txData).max() ?? 1.0, 1.0)

                    HStack {
                        VStack(alignment: .trailing) {
                            Text(String(format: "%.1fM/s", maxNet)).font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text(String(format: "%.1fM/s", maxNet / 2)).font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text("0M/s").font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(width: 40)

                        VStack {
                            CanvasLineChart(
                                dataSets: [rxData, txData],
                                colors: [Color.green, Color.orange],
                                yMax: maxNet
                            )

                            // Legend
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.green).frame(width: 8, height: 8)
                                    Text("RX").font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                                }
                                HStack(spacing: 4) {
                                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                                    Text("TX").font(.system(size: 10)).foregroundColor(AppTheme.textSecondary)
                                }
                            }
                        }
                    }
                    .frame(height: 120)
                }
            }
            .padding(16)
            .background(AppTheme.darkTerminalBackground)
            .cornerRadius(8)
            
            // Stats Row
            HStack(spacing: 24) {
                htopStat(label: "Tasks:", value: "\(currentStats.tasks) total, \(currentStats.runningTasks) running")
                
                let load = currentStats.loadAverage
                htopStat(label: "Load average:", value: String(format: "%.2f %.2f %.2f", load[0], load[1], load[2]))
                
                let totalSecs = Int(currentStats.uptimeSeconds)
                let hrs = totalSecs / 3600
                let mins = (totalSecs % 3600) / 60
                let secs = totalSecs % 60
                htopStat(label: "Uptime:", value: String(format: "%02d:%02d:%02d", hrs, mins, secs))
            }
            .padding(.top, 8)
        }
        .padding(32)
        .background(Material.ultraThin)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
    }
    
    private func htopStat(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(AppTheme.textSecondary)
            Text(value)
                .foregroundColor(AppTheme.textPrimary)
        }
        .font(.system(size: 12))
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

                let forwards = container.portForwards
                if !forwards.isEmpty {
                    HStack {
                        Text("Ports")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(forwards, id: \.hostPort) { pf in
                                if let url = URL(string: "http://localhost:\(pf.hostPort)") {
                                    Link("\(pf.hostPort):\(pf.containerPort)", destination: url)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(AppTheme.accentBlue)
                                        .underline()
                                        .help("Open in Browser")
                                        .accessibilityLabel("Open localhost:\(pf.hostPort) in Browser")
                                } else {
                                    Text("\(pf.hostPort):\(pf.containerPort)")
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(AppTheme.accentBlue)
                                }
                            }
                        }
                    }
                } else {
                    detailRow(label: "Ports", value: container.ports ?? "-")
                }

                Divider().background(AppTheme.cardBorder)
                detailRow(label: "Gateway", value: "-")
            }
        }
        .padding(24)
        .background(Material.ultraThin)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
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
        .background(Material.ultraThin)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
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

struct CanvasLineChart: View {
    let dataSets: [[Double]]
    let colors: [Color]
    let yMax: Double
    let yMin: Double
    let showGrid: Bool

    init(dataSets: [[Double]], colors: [Color], yMax: Double, yMin: Double = 0, showGrid: Bool = true) {
        self.dataSets = dataSets
        self.colors = colors
        self.yMax = yMax == 0 ? 1 : yMax // Prevent division by zero
        self.yMin = yMin
        self.showGrid = showGrid
    }

    var body: some View {
        Canvas { context, size in
            // Draw Grid
            if showGrid {
                let gridPath = Path { p in
                    for i in 0...2 {
                        let y = size.height - (size.height * CGFloat(i) / 2.0)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                context.stroke(gridPath, with: .color(Color.gray.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [4]))
            }

            // Draw Lines
            for (index, dataSet) in dataSets.enumerated() {
                guard dataSet.count > 1 else { continue }
                let color = colors[index % colors.count]

                let stepX = size.width / CGFloat(dataSet.count - 1)

                var path = Path()
                var areaPath = Path()

                let firstY = size.height - CGFloat((dataSet[0] - yMin) / (yMax - yMin)) * size.height
                path.move(to: CGPoint(x: 0, y: firstY))
                areaPath.move(to: CGPoint(x: 0, y: size.height))
                areaPath.addLine(to: CGPoint(x: 0, y: firstY))

                for i in 1..<dataSet.count {
                    let x = CGFloat(i) * stepX
                    let y = size.height - CGFloat((dataSet[i] - yMin) / (yMax - yMin)) * size.height

                    // Simple Catmull-Rom like curve approximation (using quad curves for simplicity in canvas)
                    // For performance, we can just use lines, but the user wants curves.
                    // Let's use simple lines first, as curve generation manually is complex, or use addCurve.
                    // To keep it simple and fast, we just draw lines. The original used .catmullRom interpolation.
                    // Let's implement a smooth curve using addCurve if needed, but standard lines are very fast.
                    // The prompt specifically mentions "performance curves (lines, gradients, and gridlines)",
                    // Let's use lines. "Canvas. Rysuje on krzywe użycia pamięci".

                    let prevX = CGFloat(i - 1) * stepX
                    let prevY = size.height - CGFloat((dataSet[i-1] - yMin) / (yMax - yMin)) * size.height

                    let midX = (prevX + x) / 2

                    // Bezier curve for smoothness
                    path.addCurve(to: CGPoint(x: x, y: y),
                                  control1: CGPoint(x: midX, y: prevY),
                                  control2: CGPoint(x: midX, y: y))

                    areaPath.addCurve(to: CGPoint(x: x, y: y),
                                  control1: CGPoint(x: midX, y: prevY),
                                  control2: CGPoint(x: midX, y: y))
                }

                areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
                areaPath.closeSubpath()

                // Area Gradient
                context.fill(areaPath, with: .linearGradient(Gradient(colors: [color.opacity(0.3), Color.clear]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))

                // Line
                context.stroke(path, with: .color(color), lineWidth: 2)
            }
        }
    }
}
