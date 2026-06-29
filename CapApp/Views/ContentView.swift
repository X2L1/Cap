import SwiftUI

struct ContentView: View {
    @StateObject private var eventKitService: EventKitService
    @StateObject private var chatViewModel: ChatViewModel

    init() {
        let eventKit = EventKitService()
        _eventKitService = StateObject(wrappedValue: eventKit)
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(eventKitService: eventKit))
    }

    var body: some View {
        TabView {
            ChatView(viewModel: chatViewModel)
                .tabItem { Label("Cap", systemImage: "message") }

            TodayView(eventKitService: eventKitService)
                .tabItem { Label("Today", systemImage: "calendar") }

            SettingsView(eventKitService: eventKitService)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
