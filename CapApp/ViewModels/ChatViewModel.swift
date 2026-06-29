import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var lastError: String?

    private let modelService = FoundationModelsService()
    let eventKitService: EventKitService
    private let canvasService = CanvasService()
    private var cachedAssignments: [CanvasAssignment] = []

    init(eventKitService: EventKitService) {
        self.eventKitService = eventKitService
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        isThinking = true

        Task {
            do {
                let context = await buildContext()
                let reply = try await modelService.send(trimmed, context: context)
                messages.append(ChatMessage(role: .assistant, text: reply))
            } catch {
                lastError = "\(error)"
                messages.append(ChatMessage(role: .assistant, text: "Couldn't reach the on-device model: \(error.localizedDescription)"))
            }
            isThinking = false
        }
    }

    /// Builds a compact text block of the user's own calendar + assignment data so the
    /// model can answer "what's due" / "what's on my plate" without tool-calling wired
    /// up yet. This is Phase 0's stand-in for real tool use, which comes later.
    private func buildContext() async -> String {
        var lines: [String] = []

        let events = eventKitService.upcomingEvents(daysAhead: 7)
        if !events.isEmpty {
            lines.append("Upcoming calendar events (next 7 days):")
            for event in events.prefix(15) {
                lines.append("- \(event.title) — \(event.start.formatted(date: .abbreviated, time: .shortened))")
            }
        }

        if CanvasService.hasCredentials {
            if cachedAssignments.isEmpty {
                cachedAssignments = (try? await canvasService.fetchAllUpcomingAssignments()) ?? []
            }
            if !cachedAssignments.isEmpty {
                lines.append("Upcoming Canvas assignments (next 14 days):")
                for assignment in cachedAssignments.prefix(15) {
                    let due = assignment.dueDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "no due date set"
                    lines.append("- \(assignment.name) — due \(due)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    func refreshAssignmentsCache() async {
        cachedAssignments = (try? await canvasService.fetchAllUpcomingAssignments()) ?? []
    }
}
