import Foundation

enum CanvasError: Error {
    case missingCredentials
    case badResponse(Int)
}

/// Talks directly to your school's Canvas REST API using your personal access token.
/// No scraping, no third-party relay — this hits https://<your-domain>/api/v1/... only.
final class CanvasService {
    private static let domainKey = "cap.canvas.baseURL"
    private static let tokenKey = "cap.canvas.token"

    static func saveCredentials(domain: String, token: String) {
        KeychainStore.save("https://\(domain)", for: domainKey)
        KeychainStore.save(token, for: tokenKey)
    }

    static var hasCredentials: Bool {
        KeychainStore.read(domainKey) != nil && KeychainStore.read(tokenKey) != nil
    }

    private var baseURL: String? { KeychainStore.read(Self.domainKey) }
    private var token: String? { KeychainStore.read(Self.tokenKey) }

    private func request(_ path: String) async throws -> Data {
        guard let baseURL, let token else { throw CanvasError.missingCredentials }
        guard let url = URL(string: "\(baseURL)/api/v1\(path)") else { throw CanvasError.badResponse(0) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CanvasError.badResponse(code)
        }
        return data
    }

    func fetchCourses() async throws -> [CanvasCourse] {
        let data = try await request("/courses?enrollment_state=active&per_page=50")
        return try JSONDecoder().decode([CanvasCourse].self, from: data)
    }

    func fetchAssignments(courseId: Int) async throws -> [CanvasAssignment] {
        let data = try await request("/courses/\(courseId)/assignments?per_page=100&order_by=due_at")
        return try JSONDecoder().decode([CanvasAssignment].self, from: data)
    }

    /// Pulls every active course's assignments and filters to a due-date window.
    /// Phase 0 keeps this simple (sequential requests); fine for a handful of courses.
    func fetchAllUpcomingAssignments(daysAhead: Int = 14) async throws -> [CanvasAssignment] {
        let courses = try await fetchCourses()
        var all: [CanvasAssignment] = []
        for course in courses {
            if let assignments = try? await fetchAssignments(courseId: course.id) {
                all.append(contentsOf: assignments)
            }
        }
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
        return all
            .filter { assignment in
                guard let due = assignment.dueDate else { return false }
                return due >= now.addingTimeInterval(-86_400) && due <= cutoff
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func fetchSyllabus(courseId: Int) async throws -> String {
        let data = try await request("/courses/\(courseId)?include[]=syllabus_body")
        let detail = try JSONDecoder().decode(CanvasCourseDetail.self, from: data)
        return detail.syllabus_body ?? "No syllabus posted for this course."
    }
}
