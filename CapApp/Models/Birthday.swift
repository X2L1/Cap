import Foundation

/// A contact's next upcoming birthday. `age` is the age they'll be turning, when the
/// birth year is known in the contact card (it often isn't).
struct Birthday: Identifiable {
    let id: String
    let name: String
    let date: Date          // the next occurrence (this year or next)
    let age: Int?

    var daysAway: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
}
