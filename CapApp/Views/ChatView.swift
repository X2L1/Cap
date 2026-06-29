import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var speech = SpeechService()
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if viewModel.messages.isEmpty {
                                emptyState
                            }
                            ForEach(viewModel.messages) { message in
                                messageRow(message).id(message.id)
                            }
                            if viewModel.isThinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Cap is thinking…").foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.messages.count) {
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                Divider()
                inputBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Cap")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.speakReplies.toggle()
                    } label: {
                        Image(systemName: viewModel.speakReplies ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .accessibilityLabel("Read replies aloud")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) { viewModel.clearHistory() }
                        .disabled(viewModel.messages.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Done") { inputFocused = false }
                    Spacer()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40)).foregroundStyle(Theme.accent.opacity(0.7))
            Text("Ask Cap what's on your plate.")
                .font(.headline)
            Text("Try “what's due this week?” or “any birthdays coming up?”")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                toggleListening()
            } label: {
                Image(systemName: speech.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(speech.isListening ? Theme.accent : Color(.secondarySystemBackground))
                    .foregroundStyle(speech.isListening ? .white : Theme.accent)
                    .clipShape(Circle())
            }

            TextField("Ask Cap…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...4)
                .focused($inputFocused)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        if speech.isListening { speech.stop() }
        let text = input
        input = ""
        inputFocused = false
        viewModel.send(text)
    }

    private func toggleListening() {
        if speech.isListening {
            speech.stop()
            input = speech.transcript
        } else {
            Task {
                guard await speech.requestAuthorization() else { return }
                inputFocused = false
                try? speech.start()
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background {
                    if message.role == .user {
                        Theme.userBubble
                    } else {
                        Theme.assistantBubble
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
