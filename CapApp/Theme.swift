import SwiftUI

/// One place for Cap's look. Keep color/spacing decisions here so the views stay calm.
enum Theme {
    static let accent = Color(red: 0.36, green: 0.42, blue: 0.95)   // muted indigo
    static let userBubble = LinearGradient(
        colors: [Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.45, green: 0.36, blue: 0.92)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let assistantBubble = Color(.secondarySystemBackground)
    static let corner: CGFloat = 18
}
