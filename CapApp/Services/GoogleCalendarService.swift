import Foundation

/// Reads upcoming Google Calendar events via the Calendar v3 API. Read-only.
final class GoogleCalendarService {
    func upcomingEvents(auth: GoogleAuthService, daysAhead: Int = 7) async -> [CalendarEvent] {
        guard let token = await auth.validAccessToken() else { return [] }

        let formatter = ISO8601DateFormatter()
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start) else { return [] }

        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        comps.queryItems = [
            .init(name: "timeMin", value: formatter.string(from: start)),
            .init(name: "timeMax", value: formatter.string(from: end)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "50")
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode(GCalList.self, from: data) else {
            return []
        }
        return list.items.compactMap { $0.toCalendarEvent() }.sorted { $0.start < $1.start }
    }
}

private struct GCalList: Decodable {
    let items: [GCalEvent]
}

private struct GCalEvent: Decodable {
    let id: String?
    let summary: String?
    let location: String?
    let start: GCalTime?
    let end: GCalTime?

    func toCalendarEvent() -> CalendarEvent? {
        guard let startDate = start?.resolved else { return nil }
        return CalendarEvent(
            id: id ?? UUID().uuidString,
            title: summary ?? "Untitled",
            start: startDate,
            end: end?.resolved ?? startDate,
            location: location
        )
    }
}

private struct GCalTime: Decodable {
    let dateTime: String?
    let date: String?

    var resolved: Date? {
        if let dateTime { return ISO8601DateFormatter().date(from: dateTime) }
        if let date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            return formatter.date(from: date)
        }
        return nil
    }
}
