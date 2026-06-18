
import AppKit

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: ContainerViewModel?
    private var pausedForSleep = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleepListener(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wakeListener(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc func sleepListener(_ notification: Notification) {
        // As per requirements: "Gdy użytkownik pracujący na baterii odejdzie od komputera i system wygasi ekran"
        // and "Rejestrujemy też stan trybu niskiego zużycia energii w macOS (Low Power Mode) przy użyciu obiektu ProcessInfo.processInfo.isLowPowerModeEnabled."
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            print("Eco Mode: System screen slept in Low Power Mode. Pausing workloads...")
            pausedForSleep = true
            Task {
                await viewModel?.pauseAllWorkloads()
            }
        }
    }

    @objc func wakeListener(_ notification: Notification) {
        if pausedForSleep {
            print("Eco Mode: System screen woke up. Resuming workloads...")
            pausedForSleep = false
            Task {
                await viewModel?.resumeAllWorkloads()
            }
        }
    }
}
import SwiftUI
#endif


@main
struct VesselApp: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif

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
                .onAppear {
#if os(macOS)
                    appDelegate.viewModel = viewModel
#endif
                }
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Vessel", systemImage: "cube.box.fill") {
            MenuBarView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
