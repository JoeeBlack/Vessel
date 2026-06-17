import SwiftUI

@main
struct VesselApp: App {
    @State private var viewModel = ContainerViewModel()

    private let xpcDelegate = VesselXPCListenerDelegate()
    private let xpcListener: NSXPCListener

    init() {
        xpcListener = NSXPCListener(machServiceName: "com.vessel.cctl.xpc")
        xpcListener.delegate = xpcDelegate
        xpcListener.resume()
    }

    // 🎨 Palette: Menu bar integration to allow quick access, matching State of the Art UX
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Vessel", systemImage: "cube.box.fill") {
            MenuBarView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
