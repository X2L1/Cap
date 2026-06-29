import SwiftUI
import UIKit

/// Gmail triage: recent inbox, with an on-device "draft a reply" that never sends.
struct MailView: View {
    @ObservedObject var chat: ChatViewModel

    @State private var messages: [GmailMessageMeta] = []
    @State private var loading = false
    @State private var draftFor: GmailMessageMeta?
    @State private var draftText = ""
    @State private var drafting = false

    private let gmail = GmailService()

    var body: some View {
        NavigationStack {
            Group {
                if !chat.googleAuth.isConnected {
                    ContentUnavailableView(
                        "Connect Google",
                        systemImage: "envelope",
                        description: Text("Connect your Google account in Settings to triage your inbox here.")
                    )
                } else {
                    List {
                        if messages.isEmpty && !loading {
                            Text("Inbox empty, or still loading.")
                                .foregroundStyle(.secondary).font(.callout)
                        }
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sender(message.from)).font(.subheadline).bold()
                                Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                                    .lineLimit(1)
                                Text(message.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Button {
                                    Task { await draft(message) }
                                } label: {
                                    Label("Draft a reply", systemImage: "arrowshape.turn.up.left")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .padding(.top, 2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .overlay { if loading { ProgressView() } }
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("Mail")
            .task { if chat.googleAuth.isConnected && messages.isEmpty { await reload() } }
            .sheet(item: $draftFor) { message in
                draftSheet(for: message)
            }
        }
    }

    private func draftSheet(for message: GmailMessageMeta) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Re: \(message.subject)").font(.headline)
                    if drafting {
                        HStack { ProgressView(); Text("Drafting…").foregroundStyle(.secondary) }
                    } else {
                        Text(draftText).textSelection(.enabled)
                    }
                    Text("Cap never sends mail. Copy this into Gmail yourself if you want to use it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Draft reply")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { UIPasteboard.general.string = draftText }
                        .disabled(drafting || draftText.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { draftFor = nil }
                }
            }
        }
    }

    private func reload() async {
        loading = true
        messages = await gmail.recentMessages(auth: chat.googleAuth)
        loading = false
    }

    private func draft(_ message: GmailMessageMeta) async {
        draftFor = message
        drafting = true
        draftText = ""
        draftText = await chat.draftReply(to: message)
        drafting = false
    }

    /// "Jane Doe <jane@x.com>" → "Jane Doe".
    private func sender(_ raw: String) -> String {
        if let angle = raw.firstIndex(of: "<") {
            let name = raw[raw.startIndex..<angle].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name.replacingOccurrences(of: "\"", with: "") }
        }
        return raw
    }
}
