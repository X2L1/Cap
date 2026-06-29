import EventKit
import Foundation

/// Lightweight, Sendable-friendly mirror of EKCalendar for the picker UI.
struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
}

/// Reads Apple Calendar via EventKit. Requires NSCalendarsFullAccessUsageDescription
/// (and NSCalendarsUsageDescription for older OS compatibility) in Info.plist —
/// see README_SETUP.md.
@MainActor
final class EventKitService: ObservableObject {
    private let store = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    /// Calendars the user has chosen to hide (e.g. shared calendars they don't care about).
    /// Stored as identifiers in UserDefaults — these aren't secrets, just a local preference.
    @Published var hiddenCalendarIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: Self.hiddenKey) }
    }

    private static let hiddenKey = "cap.calendars.hidden"

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
        hiddenCalendarIDs = Set(stored)
    }

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

    private var hasAccess: Bool {
        authorizationStatus == .fullAccess || authorizationStatus == .authorized
    }

    /// All event calendars on the device, for the Settings picker.
    func availableCalendars() -> [CalendarInfo] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func setCalendar(_ id: String, enabled: Bool) {
        if enabled { hiddenCalendarIDs.remove(id) } else { hiddenCalendarIDs.insert(id) }
    }

    /// Write-back: create an event in the user's default calendar. Returns false if access
    /// isn't granted or there's no default calendar to write to.
    @discardableResult
    func createEvent(title: String, start: Date, end: Date, notes: String?) -> Bool {
        guard hasAccess, let calendar = store.defaultCalendarForNewEvents else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }

    /// Synchronous on purpose — EKEventStore's event fetch is local/fast once access
    /// is granted. Honors the user's hidden-calendar choices.
    func upcomingEvents(daysAhead: Int = 7) -> [CalendarEvent] {
        guard hasAccess else { return [] }
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start) else { return [] }

        let visible = store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        // An empty calendars array to the predicate would mean "all" — but if the user has
        // hidden everything we genuinely want nothing, so short-circuit that case.
        if visible.isEmpty && !store.calendars(for: .event).isEmpty { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
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
