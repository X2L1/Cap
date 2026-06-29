import SwiftUI

struct ContentView: View {
    @StateObject private var eventKitService: EventKitService
    @StateObject private var contactsService: ContactsService
    @StateObject private var chatViewModel: ChatViewModel
    @ObservedObject private var notifications = NotificationService.shared
    @State private var tab = 0

    init() {
        let eventKit = EventKitService()
        let contacts = ContactsService()
        _eventKitService = StateObject(wrappedValue: eventKit)
        _contactsService = StateObject(wrappedValue: contacts)
        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(eventKitService: eventKit, contactsService: contacts)
        )
    }

    var body: some View {
        TabView(selection: $tab) {
            ChatView(viewModel: chatViewModel)
                .tag(0)
                .tabItem { Label("Cap", systemImage: "bubble.left.and.text.bubble.right") }

            PlanView(chat: chatViewModel, eventKitService: eventKitService)
                .tag(1)
                .tabItem { Label("Plan", systemImage: "list.bullet.clipboard") }

            TodayView(eventKitService: eventKitService, contactsService: contactsService)
                .tag(2)
                .tabItem { Label("Today", systemImage: "calendar") }

            SettingsView(eventKitService: eventKitService, contactsService: contactsService, chat: chatViewModel)
                .tag(3)
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
