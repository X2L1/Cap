import SwiftUI
import UserNotifications

@main
struct CapApp: App {
    init() {
        // Set the delegate at launch so taps on briefing notifications are routed even
        // when the app was cold-launched by the tap.
        UNUserNotificationCenter.current().delegate = NotificationService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
