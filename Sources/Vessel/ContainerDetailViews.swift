import SwiftUI
import Charts

struct ContainerConsoleView: View {
    let container: VesselContainer
    var viewModel: ContainerViewModel
    @State private var logSearchText = ""

    var body: some View {
        let isRunning = container.status == .running
        if let inputPipe = viewModel.shellInputPipes[container.id],
           let outputPipe = viewModel.shellOutputPipes[container.id] {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Console Logs")
                        .font(.system(size: 16, weight: .semibold, design: .default))
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
}

struct ContainerResourceChartsView: View {
    let container: VesselContainer
    var viewModel: ContainerViewModel

    var body: some View {
        let statsHistory = viewModel.statsHistory[container.id] ?? []
        let currentStats = statsHistory.last ?? StatsModel()

        VStack(alignment: .leading, spacing: 16) {
            Text("Resource Utilization")
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.textPrimary)

            HStack(spacing: 24) {
                // CPU Chart
                VStack(alignment: .leading) {
                    Text("CPU Usage")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)

                    Chart {
                        ForEach(statsHistory, id: \.timestamp) { stat in
                            let avgCpu = stat.cpuUsages.isEmpty ? 0 : stat.cpuUsages.reduce(0, +) / Double(stat.cpuUsages.count)
                            LineMark(
                                x: .value("Time", stat.timestamp),
                                y: .value("CPU", avgCpu * 100)
                            )
                            .foregroundStyle(AppTheme.runningGreen)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Time", stat.timestamp),
                                y: .value("CPU", avgCpu * 100)
                            )
                            .foregroundStyle(LinearGradient(colors: [AppTheme.runningGreen.opacity(0.3), Color.clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4]))
                            AxisTick()
                            AxisValueLabel {
                                if let intValue = value.as(Int.self) {
                                    Text("\(intValue)%")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                        }
                    }
                    .frame(height: 120)
                }

                // RAM Chart
                VStack(alignment: .leading) {
                    Text("Memory Usage")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)

                    Chart {
                        ForEach(statsHistory, id: \.timestamp) { stat in
                            let memMB = Double(stat.memUsedBytes) / 1024 / 1024
                            LineMark(
                                x: .value("Time", stat.timestamp),
                                y: .value("Memory", memMB)
                            )
                            .foregroundStyle(Color.cyan)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Time", stat.timestamp),
                                y: .value("Memory", memMB)
                            )
                            .foregroundStyle(LinearGradient(colors: [Color.cyan.opacity(0.3), Color.clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYScale(domain: 0...(currentStats.memTotalBytes > 0 ? Double(currentStats.memTotalBytes) / 1024 / 1024 : 1000))
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4]))
                            AxisTick()
                            AxisValueLabel {
                                if let val = value.as(Double.self) {
                                    Text(String(format: "%.0fM", val))
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                        }
                    }
                    .frame(height: 120)
                }

                // Network I/O Chart
                VStack(alignment: .leading) {
                    Text("Network I/O")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)

                    Chart {
                        ForEach(statsHistory, id: \.timestamp) { stat in
                            let rxMB = Double(stat.netRxDelta) / 1024 / 1024
                            let txMB = Double(stat.netTxDelta) / 1024 / 1024

                            LineMark(
                                x: .value("Time", stat.timestamp),
                                y: .value("Traffic", rxMB)
                            )
                            .foregroundStyle(by: .value("Type", "RX"))
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Time", stat.timestamp),
                                y: .value("Traffic", txMB)
                            )
                            .foregroundStyle(by: .value("Type", "TX"))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartForegroundStyleScale([
                        "RX": Color.green,
                        "TX": Color.orange
                    ])
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4]))
                            AxisTick()
                            AxisValueLabel {
                                if let val = value.as(Double.self) {
                                    Text(String(format: "%.1fM/s", val))
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                        }
                    }
                    .chartLegend(position: .bottom, alignment: .leading)
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
}

struct ContainerNetworkCardView: View {
    let container: VesselContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Network")
                .font(.system(size: 16, weight: .semibold, design: .default))
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
}


struct ContainerMetadataCardView: View {
    let container: VesselContainer
    var viewModel: ContainerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Metadata")
                .font(.system(size: 16, weight: .semibold, design: .default))
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
