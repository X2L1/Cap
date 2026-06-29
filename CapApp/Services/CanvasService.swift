import Foundation

enum CanvasError: Error {
    case missingCredentials
    case badResponse(Int)
    case badURL
}

/// Talks to Canvas one of two ways, both direct-to-your-school, no third-party relay:
///
/// 1. **Calendar Feed (.ics)** — a personal feed URL with an embedded secret, found in
///    Canvas under Calendar → "Calendar Feed". This is the path for schools (like TAMU)
///    that disable personal access tokens. Read-only; carries titles + due dates only.
/// 2. **REST API (token)** — richer (courses, points, syllabus) but needs a personal
///    access token your institution may not let you create.
///
/// If a feed URL is set, it wins (it's the one that works for the user). The token path
/// stays here so it's a drop-in if they ever get a token.
final class CanvasService {
    private static let domainKey = "cap.canvas.baseURL"
    private static let tokenKey = "cap.canvas.token"
    private static let feedKey = "cap.canvas.feedURL"

    // MARK: - Credentials

    static func saveCredentials(domain: String, token: String) {
        KeychainStore.save("https://\(domain)", for: domainKey)
        KeychainStore.save(token, for: tokenKey)
    }

    static func saveFeedURL(_ url: String) {
        KeychainStore.save(url, for: feedKey)
    }

    static func clearFeedURL() {
        KeychainStore.delete(feedKey)
    }

    static var hasFeed: Bool { KeychainStore.read(feedKey) != nil }
    static var hasToken: Bool {
        KeychainStore.read(domainKey) != nil && KeychainStore.read(tokenKey) != nil
    }
    static var hasCredentials: Bool { hasFeed || hasToken }

    private var baseURL: String? { KeychainStore.read(Self.domainKey) }
    private var token: String? { KeychainStore.read(Self.tokenKey) }
    private var feedURL: String? { KeychainStore.read(Self.feedKey) }

    // MARK: - Unified entry point

    /// Returns upcoming assignments from whichever source is configured, mapped to the
    /// source-agnostic `CanvasItem`. Feed takes priority.
    func fetchAllUpcomingItems(daysAhead: Int = 14) async throws -> [CanvasItem] {
        if Self.hasFeed {
            return try await fetchFeedItems(daysAhead: daysAhead)
        } else if Self.hasToken {
            return try await fetchRESTItems(daysAhead: daysAhead)
        }
        throw CanvasError.missingCredentials
    }

    // MARK: - Feed path

    private func fetchFeedItems(daysAhead: Int) async throws -> [CanvasItem] {
        guard let feedURL, var url = URL(string: feedURL) else { throw CanvasError.badURL }
        // Canvas feed URLs use the webcal:// scheme when copied; normalize to https.
        if url.scheme == "webcal" {
            url = URL(string: feedURL.replacingOccurrences(of: "webcal://", with: "https://")) ?? url
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CanvasError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let raw = String(decoding: data, as: UTF8.self)
        return filterWindow(ICSParser.parse(raw), daysAhead: daysAhead)
    }

    // MARK: - REST path

    private func request(_ path: String) async throws -> Data {
        guard let baseURL, let token else { throw CanvasError.missingCredentials }
        guard let url = URL(string: "\(baseURL)/api/v1\(path)") else { throw CanvasError.badURL }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CanvasError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
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

    func fetchSyllabus(courseId: Int) async throws -> String {
        let data = try await request("/courses/\(courseId)?include[]=syllabus_body")
        let detail = try JSONDecoder().decode(CanvasCourseDetail.self, from: data)
        return detail.syllabus_body ?? "No syllabus posted for this course."
    }

    private func fetchRESTItems(daysAhead: Int) async throws -> [CanvasItem] {
        let courses = try await fetchCourses()
        var all: [CanvasAssignment] = []
        for course in courses {
            if let assignments = try? await fetchAssignments(courseId: course.id) {
                all.append(contentsOf: assignments)
            }
        }
        let items = all.map { CanvasItem(id: String($0.id), name: $0.name, dueDate: $0.dueDate) }
        return filterWindow(items, daysAhead: daysAhead)
    }

    // MARK: - Shared filtering

    private func filterWindow(_ items: [CanvasItem], daysAhead: Int) -> [CanvasItem] {
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
        return items
            .filter { item in
                guard let due = item.dueDate else { return false }
                return due >= now.addingTimeInterval(-86_400) && due <= cutoff
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
}
