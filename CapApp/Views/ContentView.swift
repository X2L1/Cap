import SwiftUI

struct ContentView: View {
    @StateObject private var eventKitService: EventKitService
    @StateObject private var contactsService: ContactsService
    @StateObject private var locationService = LocationService()
    @StateObject private var googleAuth: GoogleAuthService
    @StateObject private var chatViewModel: ChatViewModel
    @ObservedObject private var notifications = NotificationService.shared
    @State private var tab = 0

    init() {
        let eventKit = EventKitService()
        let contacts = ContactsService()
        let google = GoogleAuthService()
        _eventKitService = StateObject(wrappedValue: eventKit)
        _contactsService = StateObject(wrappedValue: contacts)
        _googleAuth = StateObject(wrappedValue: google)
        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(eventKitService: eventKit, contactsService: contacts, googleAuth: google)
        )
    }

    var body: some View {
        TabView(selection: $tab) {
            ChatView(viewModel: chatViewModel)
                .tag(0)
                .tabItem { Label("Cap", systemImage: "bubble.left.and.text.bubble.right") }

            PlanView(chat: chatViewModel, eventKitService: eventKitService, locationService: locationService)
                .tag(1)
                .tabItem { Label("Plan", systemImage: "list.bullet.clipboard") }

            TodayView(eventKitService: eventKitService, contactsService: contactsService)
                .tag(2)
                .tabItem { Label("Today", systemImage: "calendar") }

            MailView(chat: chatViewModel)
                .tag(3)
                .tabItem { Label("Mail", systemImage: "envelope") }

            SettingsView(eventKitService: eventKitService, contactsService: contactsService,
                         chat: chatViewModel, googleAuth: googleAuth)
                .tag(4)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .onChange(of: notifications.pendingBriefing) {
            if notifications.pendingBriefing {
                tab = 1
                notifications.pendingBriefing = false
            }
        }
    }
}
