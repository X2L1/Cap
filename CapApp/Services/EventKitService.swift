import EventKit
import Foundation

/// Reads Apple Calendar via EventKit. Requires NSCalendarsFullAccessUsageDescription
/// (and NSCalendarsUsageDescription for older OS compatibility) in Info.plist —
/// see README_SETUP.md.
@MainActor
final class EventKitService: ObservableObject {
    private let store = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return false
        }
    }

    /// Synchronous on purpose — EKEventStore's event fetch is local/fast once access
    /// is granted, no need to hop threads for this in Phase 0.
    func upcomingEvents(daysAhead: Int = 7) -> [CalendarEvent] {
        guard authorizationStatus == .fullAccess || authorizationStatus == .authorized else { return [] }
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .map {
                CalendarEvent(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "Untitled",
                    start: $0.startDate,
                    end: $0.endDate,
                    location: $0.location
                )
            }
            .sorted { $0.start < $1.start }
    }
}
