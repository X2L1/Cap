import Foundation

struct ChatMessage: Identifiable, Codable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    var id = UUID()
    let role: Role
    let text: String
    var timestamp = Date()
    /// Which brain produced an assistant message, when it wasn't the on-device default
    /// (e.g. "home server"). Surfaced in the UI so it's clear what left the phone.
    var via: String? = nil
}
