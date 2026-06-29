import Foundation

/// A single thing competing for the user's attention, scored for "what to do first."
struct PlanItem: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let courseCode: String?
    let importance: Int    // 1...5 (3 = unknown/default)
    let source: Source

    enum Source: String { case canvas = "Canvas", task = "Task" }

    /// Higher = do it sooner. Combines urgency (how close/overdue the due date is) with the
    /// course's importance. Items without a due date sit low unless marked important.
    var score: Double {
        let urgency: Double
        if let dueDate {
            let days = Double(Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day ?? 0)
            // Overdue or imminent ranks highest; far-off tapers toward zero.
            urgency = max(0, min(20, 14 - days))
        } else {
            urgency = 2
        }
        return urgency + Double(importance) * 3
    }

    var dueDescription: String {
        guard let dueDate else { return "No due date" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
        switch days {
        case ..<0: return "Overdue"
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        default: return "Due in \(days) days"
        }
    }
}

enum Planner {
    /// Pulls a course code like "HIST 105" out of a Canvas title's trailing "[...]".
    static func courseCode(from title: String) -> String? {
        guard let open = title.lastIndex(of: "["), let close = title.lastIndex(of: "]"), open < close else {
            return nil
        }
        let inner = title[title.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
    }

    static func prioritize(canvas: [CanvasItem], tasks: [CapTask], weights: [String: Int]) -> [PlanItem] {
        var items: [PlanItem] = []

        for item in canvas {
            let code = courseCode(from: item.name)
            let importance = code.flatMap { weights[$0] } ?? 3
            items.append(PlanItem(id: "c-\(item.id)", title: item.name, dueDate: item.dueDate,
                                  courseCode: code, importance: importance, source: .canvas))
        }
        for task in tasks where !task.isDone {
            items.append(PlanItem(id: "t-\(task.id.uuidString)", title: task.title, dueDate: task.dueDate,
                                  courseCode: nil, importance: 3, source: .task))
        }

        return items.sorted { $0.score > $1.score }
    }

    /// Distinct course codes seen in the current Canvas items, for the importance editor.
    static func courseCodes(in canvas: [CanvasItem]) -> [String] {
        Array(Set(canvas.compactMap { courseCode(from: $0.name) })).sorted()
    }
}
