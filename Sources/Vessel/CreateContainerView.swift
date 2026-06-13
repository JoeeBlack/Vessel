import SwiftUI

struct CreateContainerView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var containerName: String = ""
    @State private var selectedImage: String = ""
    @State private var rootfsSize: Double = 8.0 // GB
    @State private var enableRosetta: Bool = false
    @State private var enableNetworking: Bool = true
    
    @State private var cpuCount: Double = 2.0 // CPU Cores
    @State private var memoryGB: Double = 2.0 // GB
    
    struct EnvVar: Identifiable {
        let id = UUID()
        var key: String = ""
        var value: String = ""
    }
    @State private var envVars: [EnvVar] = []
    
    struct VolumeMount: Identifiable {
        let id = UUID()
        var hostPath: String = ""
        var containerPath: String = ""
    }
    @State private var volumes: [VolumeMount] = []
    
    @State private var availableImages: [VesselImage] = []
    
    var onCreate: (_ name: String, _ image: String, _ rootfs: Double, _ rosetta: Bool, _ networking: Bool, _ cpus: Int, _ memoryGB: Double, _ envVars: [String: String], _ volumes: [(host: String, container: String)]) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Deploy New Workload")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Close")



            }
            .padding(24)
            .background(AppTheme.mainBackgroundTop)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Basic Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Basic Configuration")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Container Name")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            TextField("e.g. my-web-server", text: $containerName)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(AppTheme.mainBackgroundTop)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.cardBorder, lineWidth: 1))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Base Image (OCI)")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            
                            Picker("", selection: $selectedImage) {
                                ForEach(availableImages, id: \.id) { img in
                                    Text("\(img.repository):\(img.tag)").tag("\(img.repository):\(img.tag)")
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppTheme.textPrimary)
                        }
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    
                    // Hardware & Emulation
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Virtualization & Storage")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        Toggle(isOn: $enableRosetta) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Rosetta 2")
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Run x86_64 linux workloads on Apple Silicon.")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(AppTheme.accentBlue)
                        
                        Toggle(isOn: $enableNetworking) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Networking")
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Attach a dedicated Netlink interface.")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(AppTheme.accentBlue)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Root Filesystem (ext4) Size")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                Text("\(Int(rootfsSize)) GB")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppTheme.accentBlue)
                            }
                            
                            Slider(value: $rootfsSize, in: 1...100, step: 1)
                                .tint(AppTheme.accentBlue)
                        }
                        .padding(.top, 12)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("CPU Cores")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                Text("\(Int(cpuCount))")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppTheme.accentBlue)
                            }
                            
                            Slider(value: $cpuCount, in: 1...Double(ProcessInfo.processInfo.processorCount), step: 1)
                                .tint(AppTheme.accentBlue)
                        }
                        .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Memory (RAM)")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                Text("\(Int(memoryGB)) GB")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppTheme.accentBlue)
                            }
                            
                            let maxMem = Double(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
                            Slider(value: $memoryGB, in: 1...maxMem, step: 1)
                                .tint(AppTheme.accentBlue)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    
                    // Advanced Configuration
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Advanced Settings")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        // Environment Variables
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Environment Variables")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                Button(action: {
                                    envVars.append(EnvVar())
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(AppTheme.accentBlue)
                                }
                                .buttonStyle(.plain)

                                .help("Add environment variable")

                                .help("Add environment variable")

                            }
                            
                            ForEach($envVars) { $envVar in
                                HStack {
                                    TextField("Key (e.g. NODE_ENV)", text: $envVar.key)
                                        .textFieldStyle(.plain)
                                        .padding(8)
                                        .background(AppTheme.mainBackgroundTop)
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.cardBorder, lineWidth: 1))
                                        .foregroundColor(AppTheme.textPrimary)
                                    
                                    Text("=")
                                        .foregroundColor(AppTheme.textSecondary)
                                    
                                    TextField("Value", text: $envVar.value)
                                        .textFieldStyle(.plain)
                                        .padding(8)
                                        .background(AppTheme.mainBackgroundTop)
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.cardBorder, lineWidth: 1))
                                        .foregroundColor(AppTheme.textPrimary)
                                    
                                    Button(action: {
                                        envVars.removeAll(where: { $0.id == envVar.id })
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)

                                    .help("Remove environment variable")

                                    .help("Remove environment variable")

                                }
                            }
                        }
                        
                        Divider().background(AppTheme.cardBorder).padding(.vertical, 8)
                        
                        // Volumes
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Volume Mounts")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                Button(action: {
                                    volumes.append(VolumeMount())
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(AppTheme.accentBlue)
                                }
                                .buttonStyle(.plain)

                                .help("Add volume mount")

                                .help("Add volume mount")

                            }
                            
                            ForEach($volumes) { $volume in
                                HStack {
                                    TextField("Host Path (/Users/...)", text: $volume.hostPath)
                                        .textFieldStyle(.plain)
                                        .padding(8)
                                        .background(AppTheme.mainBackgroundTop)
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.cardBorder, lineWidth: 1))
                                        .foregroundColor(AppTheme.textPrimary)
                                    
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(AppTheme.textSecondary)
                                    
                                    TextField("Container Path", text: $volume.containerPath)
                                        .textFieldStyle(.plain)
                                        .padding(8)
                                        .background(AppTheme.mainBackgroundTop)
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.cardBorder, lineWidth: 1))
                                        .foregroundColor(AppTheme.textPrimary)
                                    
                                    Button(action: {
                                        volumes.removeAll(where: { $0.id == volume.id })
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)

                                    .help("Remove volume mount")

                                    .help("Remove volume mount")

                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    
                }
                .padding(24)
            }
            
            // Footer
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundColor(AppTheme.textPrimary)
                        .background(AppTheme.cardBorder)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: create) {
                    Text("Deploy Container")
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundColor(.white)
                        .background(containerName.trimmingCharacters(in: .whitespaces).isEmpty ? AppTheme.textSecondary.opacity(0.5) : AppTheme.accentBlue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(containerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(24)
            .background(AppTheme.mainBackgroundTop)
        }
        .frame(width: 500, height: 600)
        .background(AppTheme.mainBackgroundTop)
        .task {
            do {
                let images = try await ContainerDaemon().fetchImages()
                await MainActor.run {
                    self.availableImages = images
                    if let first = images.first {
                        self.selectedImage = "\(first.repository):\(first.tag)"
                    }
                }
            } catch {
                print("Failed to load images for CreateContainerView: \(error)")
            }
        }
    }
    
    private func create() {
        var envMap: [String: String] = [:]
        for ev in envVars where !ev.key.isEmpty {
            envMap[ev.key] = ev.value
        }
        
        var vMap: [(host: String, container: String)] = []
        for v in volumes where !v.hostPath.isEmpty && !v.containerPath.isEmpty {
            vMap.append((host: v.hostPath, container: v.containerPath))
        }
        
        onCreate(containerName, selectedImage, rootfsSize, enableRosetta, enableNetworking, Int(cpuCount), memoryGB, envMap, vMap)
        dismiss()
    }
}
