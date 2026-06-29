import Foundation

struct CanvasCourse: Codable, Identifiable {
    let id: Int
    let name: String?
    let course_code: String?
}

struct CanvasAssignment: Codable, Identifiable {
    let id: Int
    let name: String
    let due_at: String?
    let points_possible: Double?
    let course_id: Int
    let html_url: String?

    var dueDate: Date? {
        guard let due_at else { return nil }
        return ISO8601DateFormatter().date(from: due_at)
    }
}

struct CanvasCourseDetail: Codable {
    let id: Int
    let name: String?
    let syllabus_body: String?
}

/// Source-agnostic assignment/event used by the UI and the chat context builder, so the
/// rest of the app doesn't care whether it came from the REST API (token) or the ICS
/// calendar feed (the TAMU-friendly path that needs no token).
struct CanvasItem: Identifiable {
    let id: String
    let name: String
    let dueDate: Date?
}
