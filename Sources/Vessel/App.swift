import SwiftUI

@main
struct VesselApp: App {
    @State private var viewModel = ContainerViewModel()

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
