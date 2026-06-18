
import AppKit
import SwiftUI
import UserNotifications

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var viewModel: ContainerViewModel?
    private var pausedForSleep = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleepListener(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wakeListener(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let showLogsAction = UNNotificationAction(
            identifier: "SHOW_LOGS",
            title: "Pokaż Logi",
            options: .foreground
        )

        let restartAction = UNNotificationAction(
            identifier: "RESTART_CONTAINER",
            title: "Restartuj",
            options: .destructive
        )

        let crashCategory = UNNotificationCategory(
            identifier: "CRASH_CATEGORY",
            actions: [restartAction, showLogsAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        center.setNotificationCategories([crashCategory])
    }

    @objc func sleepListener(_ notification: Notification) {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            print("Eco Mode: System screen slept in Low Power Mode. Pausing workloads...")
            pausedForSleep = true
            if let vm = viewModel {
                Task { await vm.pauseAllWorkloads() }
            }
        }
    }

    @objc func wakeListener(_ notification: Notification) {
        if pausedForSleep {
            print("Eco Mode: System screen woke up. Resuming workloads...")
            pausedForSleep = false
            if let vm = viewModel {
                Task { await vm.resumeAllWorkloads() }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        guard let containerId = userInfo["containerId"] as? String else {
            completionHandler()
            return
        }

        if response.actionIdentifier == "SHOW_LOGS" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            NotificationCenter.default.post(name: .navigateToContainer, object: containerId)
        } else if response.actionIdentifier == "RESTART_CONTAINER" {
            NotificationCenter.default.post(name: .restartContainer, object: containerId)
        }

        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
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

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environment(viewModel)
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
