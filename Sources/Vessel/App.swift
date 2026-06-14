import SwiftUI

@main
struct VesselApp: App {
    // 🎨 Palette: Menu bar integration to allow quick access, matching State of the Art UX
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Vessel", systemImage: "cube.box.fill") {
            VStack {
                Text("Vessel Engine")
                    .font(.headline)
                Divider()
                Button("Open Dashboard") {
                    if let window = NSApp.windows.first {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
        }
        .menuBarExtraStyle(.menu)
    }
}
