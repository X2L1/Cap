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
    let googleAuth: GoogleAuthService
    private let canvasService = CanvasService()
    private let googleCalendar = GoogleCalendarService()
    private let homeServer = HomeServerService()
    private var cachedGoogleEvents: [CalendarEvent] = []
    private var cachedAssignments: [CanvasItem] = []

    /// Read-only view of the cached Canvas items for the Plan tab.
    var canvasItems: [CanvasItem] { cachedAssignments }

    /// The on-device model session is empty on a fresh launch. The first message after
    /// launch replays the persisted chat log into the context block so Cap picks up
    /// where it left off; later turns rely on the live session's own transcript.
    private var hasReplayedHistory = false

    init(eventKitService: EventKitService, contactsService: ContactsService, googleAuth: GoogleAuthService) {
        self.eventKitService = eventKitService
        self.contactsService = contactsService
        self.googleAuth = googleAuth
        messages = LocalStore.shared.loadMessages()
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        LocalStore.shared.saveMessages(messages)
        isThinking = true

        Task {
            // Route to the user's home server when it's enabled and actually reachable;
            // otherwise use the on-device model. The server gets real message history, so
            // it doesn't need the conversation replayed into the context block.
            var useServer = false
            if HomeServerConfig.isEnabled {
                useServer = await homeServer.isReachable()
            }
            let context = await buildContext(includeHistory: !useServer)

            do {
                let reply: String
                var via: String?
                if useServer {
                    reply = try await homeServer.send(buildServerMessages(context: context))
                    via = "home server"
                } else {
                    reply = try await modelService.send(trimmed, context: context)
                }
                messages.append(ChatMessage(role: .assistant, text: reply, via: via))
                if speakReplies { synthesizer.speak(reply) }
            } catch {
                // If the server was the problem, fall back to the on-device model once.
                if useServer, let fallback = try? await modelService.send(trimmed, context: context) {
                    messages.append(ChatMessage(role: .assistant, text: fallback))
                } else {
                    lastError = "\(error)"
                    messages.append(ChatMessage(role: .assistant, text: "Couldn't reach the model: \(error.localizedDescription)"))
                }
            }
            LocalStore.shared.saveMessages(messages)
            isThinking = false
        }
    }

    /// Build the OpenAI-style message array for the home server: persona + data context as
    /// system messages, then recent turns (the current user message is already the last one).
    private func buildServerMessages(context: String) -> [HomeServerService.Message] {
        var msgs: [HomeServerService.Message] = [.init(role: "system", content: Persona.systemInstructions)]
        if !context.isEmpty { msgs.append(.init(role: "system", content: context)) }
        for message in messages.suffix(12) {
            msgs.append(.init(role: message.role == .user ? "user" : "assistant", content: message.text))
        }
        return msgs
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
    private func buildContext(includeHistory: Bool = true) async -> String {
        var lines: [String] = []

        // Compute any arithmetic in the latest user message exactly, so the model doesn't
        // have to (small models are unreliable at it).
        if let lastUser = messages.last(where: { $0.role == .user }),
           let hint = ArithmeticHelper.computedHint(for: lastUser.text) {
            lines.append("Arithmetic (computed exactly — state this answer): \(hint)")
        }

        // On the first turn after a relaunch, hand the model a transcript of the recent
        // conversation so it has continuity the empty session would otherwise lack.
        if includeHistory && !hasReplayedHistory {
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
            lines.append("Upcoming Apple Calendar events (next 7 days):")
            for event in events.prefix(15) {
                lines.append("- \(event.title) — \(event.start.formatted(date: .abbreviated, time: .shortened))")
            }
        }

        if googleAuth.isConnected {
            if cachedGoogleEvents.isEmpty {
                cachedGoogleEvents = await googleCalendar.upcomingEvents(auth: googleAuth, daysAhead: 7)
            }
            if !cachedGoogleEvents.isEmpty {
                lines.append("Upcoming Google Calendar events (next 7 days):")
                for event in cachedGoogleEvents.prefix(15) {
                    lines.append("- \(event.title) — \(event.start.formatted(date: .abbreviated, time: .shortened))")
                }
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

                // Grade-impact signal the user set per course, so triage isn't blind to weight.
                let weights = LocalStore.shared.loadCourseWeights()
                if !weights.isEmpty {
                    let labels = ["1": "low", "2": "low", "3": "medium", "4": "high", "5": "very high"]
                    let described = weights.sorted { $0.key < $1.key }
                        .map { "\($0.key) = \(labels[String($0.value)] ?? "medium")" }
                    lines.append("Course importance the user set (weight these in triage): " + described.joined(separator: ", "))
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

    func refreshGoogleEventsCache() async {
        cachedGoogleEvents = googleAuth.isConnected
            ? await googleCalendar.upcomingEvents(auth: googleAuth, daysAhead: 7)
            : []
    }

    /// Draft a reply suggestion for an email. Read-only by design — this returns text for
    /// the user to copy/send themselves; Cap never sends anything.
    func draftReply(to email: GmailMessageMeta) async -> String {
        let context = """
        Draft a brief, friendly reply to this email. Return only the reply body — no preamble.
        From: \(email.from)
        Subject: \(email.subject)
        Preview: \(email.snippet)
        """
        return (try? await modelService.oneShot("Write the reply.", context: context))
            ?? "Couldn't reach the on-device model."
    }

    /// One-shot triage briefing from the on-device model, using the same context block as
    /// chat. Runs on a throwaway session so it doesn't show up in the conversation.
    func generateBriefing() async -> String {
        if cachedAssignments.isEmpty { await refreshAssignmentsCache() }
        let context = await buildContext(includeHistory: false)
        let prompt = "Give me a short, friendly briefing of what matters today and what to tackle first. " +
            "Lead with the most time-sensitive thing. Keep it to a few sentences."
        return (try? await modelService.oneShot(prompt, context: context))
            ?? "Couldn't reach the on-device model for a briefing."
    }
}
