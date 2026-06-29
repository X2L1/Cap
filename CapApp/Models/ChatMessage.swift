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
}
