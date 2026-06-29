import Foundation

/// Lightweight, Sendable-friendly mirror of EKEvent so views and the chat context
/// builder don't need to touch EventKit types directly.
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String?
}
