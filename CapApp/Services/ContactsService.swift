import Contacts
import Foundation

/// Reads birthdays out of the on-device Contacts store so Cap can remind you. Nothing
/// leaves the phone — this is a local read of the same address book Contacts.app uses.
/// Requires NSContactsUsageDescription in Info.plist.
@MainActor
final class ContactsService: ObservableObject {
    private let store = CNContactStore()
    @Published var authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        return granted
    }

    private var hasAccess: Bool {
        switch authorizationStatus {
        case .authorized, .limited: return true
        default: return false
        }
    }

    /// Birthdays falling within `daysAhead` days, soonest first.
    func upcomingBirthdays(daysAhead: Int = 30) -> [Birthday] {
        guard hasAccess else { return [] }
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactBirthdayKey
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var results: [Birthday] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        try? store.enumerateContacts(with: request) { contact, _ in
            guard let components = contact.birthday,
                  let month = components.month, let day = components.day else { return }

            guard let next = Self.nextOccurrence(month: month, day: day, from: today, calendar: calendar) else { return }
            let daysAway = calendar.dateComponents([.day], from: today, to: next).day ?? 0
            guard daysAway <= daysAhead else { return }

            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }.joined(separator: " ")
            guard !name.isEmpty else { return }

            var age: Int?
            if let birthYear = components.year {
                age = calendar.component(.year, from: next) - birthYear
            }
            results.append(Birthday(id: contact.identifier, name: name, date: next, age: age))
        }

        return results.sorted { $0.date < $1.date }
    }

    /// The next time month/day comes around — this year if it hasn't passed, else next year.
    /// Feb 29 falls back to Feb 28 in non-leap years.
    private static func nextOccurrence(month: Int, day: Int, from today: Date, calendar: Calendar) -> Date? {
        for yearOffset in 0...1 {
            let year = calendar.component(.year, from: today) + yearOffset
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day
            var date = calendar.date(from: comps)
            if date == nil, month == 2, day == 29 {
                comps.day = 28
                date = calendar.date(from: comps)
            }
            if let date, calendar.startOfDay(for: date) >= today { return calendar.startOfDay(for: date) }
        }
        return nil
    }
}
