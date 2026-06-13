import SwiftUI

struct ContainersListView: View {
    let workloads: [VesselWorkload]
    let loadingContainers: Set<String>
    var viewModel: ContainerViewModel
    var onSelect: (String) -> Void
    var onStart: (String) -> Void
    var onStop: (String) -> Void
    var onDelete: (String) -> Void
    var onNewContainer: () -> Void
    
    let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 24)
    ]
    
    var runningCount: Int { 
        workloads.filter { 
            switch $0 {
            case .container(let c): return c.status == .running
            case .pod(let p): return p.status == .running
            }
        }.count 
    }
    
    var stoppedCount: Int { 
        workloads.filter { 
            switch $0 {
            case .container(let c): return c.status == .stopped
            case .pod(let p): return p.status == .stopped
            }
        }.count 
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Area
                HStack {
                    Spacer()
                    
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease")
                            Text("Filter")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.cardBackground)
                        .foregroundColor(AppTheme.textPrimary)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.cardBorder, lineWidth: 1))
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onNewContainer) {
                        HStack {
                            Image(systemName: "plus")
                            Text("New Container")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.accentBlue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)
                
                // Cards Grid
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(workloads) { workload in
                        switch workload {
                        case .container(let container):
                            ContainerCardView(
                                container: container,
                                isLoading: loadingContainers.contains(container.id),
                                viewModel: viewModel,
                                onStart: { onStart(container.id) },
                                onStop: { onStop(container.id) },
                                onDelete: { onDelete(container.id) }
                            )
                            .onTapGesture {
                                onSelect(container.id)
                            }
                            .cursor(.pointingHand)
                            
                        case .pod(let pod):
                            PodCardView(
                                pod: pod,
                                isLoading: loadingContainers.contains(pod.id),
                                viewModel: viewModel,
                                onStart: { onStart(pod.id) },
                                onStop: { onStop(pod.id) }
                            )
                            .onTapGesture {
                                onSelect(pod.id)
                            }
                            .cursor(.pointingHand)
                        }
                    }
                    
                    // Deploy Container Placeholder
                    Button(action: onNewContainer) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.accentBlue.opacity(0.1))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "plus")
                                    .foregroundColor(AppTheme.accentBlue)
                                    .font(.system(size: 20, weight: .medium))
                            }
                            
                            VStack(spacing: 4) {
                                Text("Deploy Container")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppTheme.accentBlue)
                                Text("From image or compose file")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 40)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .foregroundColor(AppTheme.textSecondary.opacity(0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
            }
            .padding(32)
        }
    }
}

struct ContainerCardView: View {
    let container: VesselContainer
    let isLoading: Bool
    var viewModel: ContainerViewModel
    let onStart: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void
    
    @State private var isAnimatingOverlay: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card Header
            HStack(alignment: .top) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.mainBackgroundTop)
                        .frame(width: 40, height: 40)
                    
                    if container.image.contains("nginx") {
                        Image(systemName: "server.rack")
                            .foregroundColor(AppTheme.textPrimary)
                    } else if container.image.contains("redis") {
                        Image(systemName: "cylinder.split.1x2")
                            .foregroundColor(.red)
                    } else if container.image.contains("postgres") {
                        Image(systemName: "cylinder.split.1x2")
                            .foregroundColor(AppTheme.accentBlue)
                    } else {
                        Image(systemName: "cube.box")
                            .foregroundColor(AppTheme.accentBlue)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(container.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        
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
                        }
                    }
                    
                    Text(container.image)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                        
                    if container.status == .running {
                        let stats = viewModel.publishedStats[container.id] ?? StatsModel()
                        let cpuPct = stats.cpuUsages.isEmpty ? 0.0 : stats.cpuUsages.reduce(0, +) / Double(max(1, stats.cpuUsages.count))
                        let memMb = Double(stats.memUsedBytes) / 1024 / 1024
                        
                        HStack(spacing: 8) {
                            HStack(spacing: 2) {
                                Image(systemName: "cpu")
                                Text(String(format: "%.0f%%", cpuPct * 100))
                            }
                            HStack(spacing: 2) {
                                Image(systemName: "memorychip")
                                Text(String(format: "%.0f MB", memMb))
                            }
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.top, 2)
                    }
                }
            }
            
            // Details Section (IP & Ports)
            VStack(spacing: 8) {
                detailRow(label: "IP Address", value: container.ipAddress ?? "-")
                detailRow(label: "Ports", value: container.ports ?? "-")
            }
            .padding(12)
            .background(AppTheme.mainBackgroundTop)
            .cornerRadius(8)
            
            // Actions
            HStack(spacing: 12) {
                if container.status == .running {
                    Button(action: onStop) {
                        HStack {
                            Image(systemName: "square.fill")
                                .font(.system(size: 10))
                            Text("Stop")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppTheme.mainBackgroundTop)
                        .foregroundColor(AppTheme.textPrimary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                } else {
                    Button(action: onStart) {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Start")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppTheme.mainBackgroundTop)
                        .foregroundColor(AppTheme.textPrimary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
                
                Button(action: onDelete) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 10))
                        Text("Delete")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppTheme.mainBackgroundTop)
                    .foregroundColor(AppTheme.stoppedRed)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
        .padding(20)
        .background(
            ZStack {
                AppTheme.cardBackground
                if container.status == .creating || container.status == .starting || isLoading {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.clear, AppTheme.accentBlue.opacity(0.08), Color.clear]), startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width)
                            .offset(x: isAnimatingOverlay ? geometry.size.width : -geometry.size.width)
                            .onAppear {
                                withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                    isAnimatingOverlay = true
                                }
                            }
                    }
                }
            }
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        .task(id: container.status) {
            if container.status == .running {
                await viewModel.subscribeToStats(for: container.id)
            }
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.accentBlue)
        }
    }
}
