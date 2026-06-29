import Foundation

/// A saved place Cap watches for arrival/departure (dorm, library, gym, key buildings).
/// iOS caps an app at 20 monitored regions total, so the UI enforces that.
struct Place: Codable, Identifiable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double      // meters

    init(name: String, latitude: Double, longitude: Double, radius: Double = 150) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }
}
