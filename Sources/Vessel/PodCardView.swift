import SwiftUI

struct PodCardView: View {
    let pod: VesselPod
    let isLoading: Bool
    var viewModel: ContainerViewModel
    var onStart: () -> Void
    var onStop: () -> Void
    var onForceStop: (() -> Void)? = nil
    
    @State private var isHovering = false
    
    var isRunning: Bool { pod.status == .running }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isRunning ? Color.green.opacity(0.1) : AppTheme.textSecondary.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .foregroundColor(isRunning ? Color.green : AppTheme.textSecondary)
                        .font(.system(size: 24))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(pod.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    Text("Compose Project")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.leading, 8)
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 6) {
                    StatusIndicator(status: pod.status, size: 8)
                    Text(pod.status.rawValue.capitalized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isRunning ? Color.green : (pod.status == .creating ? Color.orange : Color.red))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isRunning ? Color.green.opacity(0.1) : (pod.status == .creating ? Color.orange.opacity(0.1) : Color.red.opacity(0.1)))
                )
            }
            
            Divider()
                .background(AppTheme.cardBorder)
            
            // Stats Grid
            VStack(spacing: 12) {
                // Containers count
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "cube.box")
                            .foregroundColor(AppTheme.textSecondary)
                        Text("Containers")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .font(.system(size: 13))
                    
                    Spacer()
                    
                    Text("\(pod.containers.count)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                // Resources
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .foregroundColor(AppTheme.textSecondary)
                        Text("CPU / RAM")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .font(.system(size: 13))
                    
                    Spacer()
                    
                    Text("\(pod.cpus) Cores / \(String(format: "%.1f", pod.memoryGB)) GB")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button(action: {
                    if isRunning {
                        onStop()
                    } else {
                        onStart()
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(isRunning ? Color.red : Color.green)
                        } else {
                            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        }
                        Text(isRunning ? "Stop" : "Start")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isRunning ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .foregroundColor(isRunning ? Color.red : Color.green)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isLoading || pod.status == .creating)

                if isRunning, let onForceStop = onForceStop {
                    Button(action: onForceStop) {
                        HStack {
                            Image(systemName: "exclamationmark.square.fill")
                            Text("Force Stop")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
            }
        }
        .padding(20)
        .frame(height: 240)
        .background(
            ZStack {
                Material.ultraThin
                AppTheme.cardBackground
                // Domain Color Strip for Pod
                if pod.domain != .generic {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(AppTheme.color(for: pod.domain))
                            .frame(width: 4)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isHovering ? AppTheme.accentBlue.opacity(0.5) : AppTheme.cardBorder, lineWidth: isHovering ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(isHovering ? 0.2 : 0.05), radius: isHovering ? 20 : 10, y: isHovering ? 10 : 5)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
