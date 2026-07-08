import SwiftUI

struct SettingsView: View {
    @AppStorage("enableHaptics") private var enableHaptics: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header Area
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text("Manage containerization framework.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    
                    // UI Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Appearance & Feedback")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        Toggle(isOn: $enableHaptics) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sensory Feedback")
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Provide haptic feedback on trackpad when performing actions like starting/stopping containers.")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(AppTheme.accentBlue)
                    }
                    .padding(20)
                    .background(Material.ultraThin)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)

                    // CLI Tool Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Command Line Interface")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text("Install the 'container' command to /usr/local/bin to use from your terminal.")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        Button(action: installCLI) {
                            Text("Install CLI Tool")
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(AppTheme.accentBlue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .background(Material.ultraThin)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    
                    // Uninstallation Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Uninstallation")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text("Remove the containerization framework from your system.")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                runUninstall(arguments: ["-d"])
                            }) {
                                Text("Prune and Remove (Delete Data)")
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.stoppedRed)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                runUninstall(arguments: ["-k"])
                            }) {
                                Text("Remove (Keep Data)")
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.cardBorder)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .background(Material.ultraThin)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }
    
    private func runUninstall(arguments: [String]) {
        Task.detached {
            do {
                if arguments.contains("-d") {
                    let vesselDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel")
                    try? FileManager.default.removeItem(at: vesselDir)
                }
                
                // Assuming we also try to call the original apple uninstaller if it exists
                let scriptPath = "/usr/local/bin/uninstall-container.sh"
                if FileManager.default.fileExists(atPath: scriptPath) {
                    let appleScript = """
                    on run argv
                        if count of argv is 0 then return
                        set cmd to quoted form of item 1 of argv
                        repeat with i from 2 to count of argv
                            set cmd to cmd & " " & quoted form of item i of argv
                        end repeat
                        do shell script cmd with administrator privileges
                    end run
                    """

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    process.arguments = ["-e", appleScript, "--", scriptPath] + arguments
                    try process.run()
                    process.waitUntilExit()
                }
                
                await MainActor.run {
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                print("Failed to run uninstaller: \(error)")
                await MainActor.run {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
    
    private func installCLI() {
        guard let cliUrl = Bundle.main.url(forResource: "container", withExtension: nil) else {
            print("CLI tool not found in bundle.")
            return
        }
        
        let targetPath = "/usr/local/bin/container"
        
        Task.detached {
            let appleScript = """
            on run argv
                set sourcePath to item 1 of argv
                set targetPath to item 2 of argv
                set cmd to "mkdir -p /usr/local/bin && cp " & quoted form of sourcePath & " " & quoted form of targetPath & " && chmod +x " & quoted form of targetPath
                do shell script cmd with administrator privileges
            end run
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript, "--", cliUrl.path, targetPath]
            try? process.run()
            process.waitUntilExit()
        }
    }
}
