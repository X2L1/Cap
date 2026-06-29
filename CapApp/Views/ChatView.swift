import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var input: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            messageRow(message)
                        }
                        if viewModel.isThinking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Cap is thinking…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
                Divider()
                HStack(alignment: .bottom) {
                    TextField("Ask Cap…", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button("Send") {
                        let text = input
                        input = ""
                        viewModel.send(text)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Cap")
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant { Spacer(minLength: 0) }
            Text(message.text)
                .padding(10)
                .background(message.role == .user ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if message.role == .user { Spacer(minLength: 0) }
        }
    }
}
