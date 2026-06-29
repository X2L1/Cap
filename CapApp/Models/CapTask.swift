import Foundation

/// Locally-owned tasks/reminders captured through the Today tab's quick-capture field.
/// This is intentionally separate from Calendar/Canvas data — it's Cap's own scratch list.
struct CapTask: Codable, Identifiable {
    let id: UUID
    var title: String
    var notes: String?
    var dueDate: Date?
    let createdAt: Date
    var isDone: Bool

    init(title: String, notes: String? = nil, dueDate: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.createdAt = Date()
        self.isDone = false
    }
}
