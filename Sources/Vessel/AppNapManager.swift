import Foundation

public final class AppNapManager: @unchecked Sendable {
    public static let shared = AppNapManager()

    private var activityToken: NSObjectProtocol?
    private var lastActivityTime: Date = Date()
    private let queue = DispatchQueue(label: "com.vessel.appnap")
    private var timer: DispatchSourceTimer?
    private let timeout: TimeInterval = 5 * 60 // 5 minutes

    private init() {
        startTimer()
    }

    public func recordActivity() {
        queue.async {
            self.lastActivityTime = Date()
            if self.activityToken == nil {
                self.activityToken = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiated, .latencyCritical],
                    reason: "Obsługa przychodzącego żądania HTTP"
                )
            }
        }
    }

    private func startTimer() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + 10, repeating: 10)
        timer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastActivityTime) >= self.timeout {
                if let token = self.activityToken {
                    ProcessInfo.processInfo.endActivity(token)
                    self.activityToken = nil
                }
            }
        }
        timer?.resume()
    }
}
