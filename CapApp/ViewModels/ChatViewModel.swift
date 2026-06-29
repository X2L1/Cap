import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var lastError: String?

    /// When on, Cap reads its replies aloud (Phase 1 voice). Persisted locally.
    @Published var speakReplies: Bool = UserDefaults.standard.bool(forKey: "cap.speakReplies") {
        didSet {
            UserDefaults.standard.set(speakReplies, forKey: "cap.speakReplies")
            if !speakReplies { synthesizer.stop() }
        }
    }

    let synthesizer = SpeechSynthesizer()

    private let modelService = FoundationModelsService()
    let eventKitService: EventKitService
    let contactsService: ContactsService
    private let canvasService = CanvasService()
    private var cachedAssignments: [CanvasItem] = []

    /// The on-device model session is empty on a fresh launch. The first message after
    /// launch replays the persisted chat log into the context block so Cap picks up
    /// where it left off; later turns rely on the live session's own transcript.
    private var hasReplayedHistory = false

    init(eventKitService: EventKitService, contactsService: ContactsService) {
        self.eventKitService = eventKitService
        self.contactsService = contactsService
        messages = LocalStore.shared.loadMessages()
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        LocalStore.shared.saveMessages(messages)
        isThinking = true

        Task {
            do {
                let context = await buildContext()
                let reply = try await modelService.send(trimmed, context: context)
                messages.append(ChatMessage(role: .assistant, text: reply))
                if speakReplies { synthesizer.speak(reply) }
            } catch {
                lastError = "\(error)"
                messages.append(ChatMessage(role: .assistant, text: "Couldn't reach the on-device model: \(error.localizedDescription)"))
            }
            LocalStore.shared.saveMessages(messages)
            isThinking = false
        }
    }

    func clearHistory() {
        messages = []
        LocalStore.shared.saveMessages([])
        hasReplayedHistory = true
        Task { await modelService.resetConversation() }
    }

    /// Builds a compact text block of the user's own calendar + assignment data so the
    /// model can answer "what's due" / "what's on my plate" without tool-calling wired
    /// up yet. This is Phase 0's stand-in for real tool use, which comes later.
    private func buildContext() async -> String {
        var lines: [String] = []

        // On the first turn after a relaunch, hand the model a transcript of the recent
        // conversation so it has continuity the empty session would otherwise lack.
        if !hasReplayedHistory {
            hasReplayedHistory = true
            let prior = messages.dropLast() // exclude the message we're about to answer
            if !prior.isEmpty {
                lines.append("Earlier in this conversation:")
                for message in prior.suffix(10) {
                    let speaker = message.role == .user ? "User" : "Cap"
                    lines.append("\(speaker): \(message.text)")
                }
                lines.append("")
            }
        }

        let events = eventKitService.upcomingEvents(daysAhead: 7)
        if !events.isEmpty {
            lines.append("Upcoming calendar events (next 7 days):")
            for event in events.prefix(15) {
                lines.append("- \(event.title) — \(event.start.formatted(date: .abbreviated, time: .shortened))")
            }
        }

        if CanvasService.hasCredentials {
            if cachedAssignments.isEmpty {
                cachedAssignments = (try? await canvasService.fetchAllUpcomingItems()) ?? []
            }
            if !cachedAssignments.isEmpty {
                lines.append("Upcoming Canvas assignments (next 14 days):")
                for assignment in cachedAssignments.prefix(15) {
                    let due = assignment.dueDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "no due date set"
                    lines.append("- \(assignment.name) — due \(due)")
                }
            }
        }

        let birthdays = contactsService.upcomingBirthdays(daysAhead: 14)
        if !birthdays.isEmpty {
            lines.append("Upcoming birthdays (next 14 days):")
            for b in birthdays.prefix(10) {
                let when = b.daysAway == 0 ? "today" : "in \(b.daysAway) day\(b.daysAway == 1 ? "" : "s")"
                let age = b.age.map { " (turning \($0))" } ?? ""
                lines.append("- \(b.name)\(age) — \(when)")
            }
        }

        return lines.joined(separator: "\n")
    }

    func refreshAssignmentsCache() async {
        cachedAssignments = (try? await canvasService.fetchAllUpcomingItems()) ?? []
    }
}
