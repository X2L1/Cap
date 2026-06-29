import SwiftUI

struct ContentView: View {
    @StateObject private var eventKitService: EventKitService
    @StateObject private var contactsService: ContactsService
    @StateObject private var chatViewModel: ChatViewModel

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
        TabView {
            ChatView(viewModel: chatViewModel)
                .tabItem { Label("Cap", systemImage: "bubble.left.and.text.bubble.right") }

            TodayView(eventKitService: eventKitService, contactsService: contactsService)
                .tabItem { Label("Today", systemImage: "calendar") }

            SettingsView(eventKitService: eventKitService, contactsService: contactsService, chat: chatViewModel)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}
