import Foundation
import UserNotifications

/// Schedules the morning/evening briefing notifications. Per the roadmap's honesty about
/// iOS background limits, these are plain fixed-time local notifications scheduled ahead —
/// no background process, no guarantees beyond what `UNCalendarNotificationTrigger` gives.
@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    /// Flipped when the user taps a briefing notification, so the UI can jump to the Plan tab.
    @Published var pendingBriefing = false

    private static let morningID = "cap.briefing.morning"
    private static let eveningID = "cap.briefing.evening"

    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleBriefings(morning: (hour: Int, minute: Int) = (7, 30),
                           evening: (hour: Int, minute: Int) = (20, 0)) {
        cancelBriefings()
        schedule(id: Self.morningID, title: "Morning briefing",
                 body: "Open Cap for today's plan.", hour: morning.hour, minute: morning.minute)
        schedule(id: Self.eveningID, title: "Evening check-in",
                 body: "What's still open and tomorrow's setup.", hour: evening.hour, minute: evening.minute)
    }

    func cancelBriefings() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.morningID, Self.eveningID])
    }

    private func schedule(id: String, title: String, body: String, hour: Int, minute: Int) {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["cap.open": "briefing"]

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.notification.request.content.userInfo["cap.open"] as? String == "briefing" {
            await MainActor.run { NotificationService.shared.pendingBriefing = true }
        }
    }
}
