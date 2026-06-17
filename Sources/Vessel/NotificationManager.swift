import Foundation
import Cocoa
import UserNotifications
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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

extension Notification.Name {
    static let navigateToContainer = Notification.Name("VesselNavigateToContainer")
    static let restartContainer = Notification.Name("VesselRestartContainer")
}
