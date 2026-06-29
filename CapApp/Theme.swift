import SwiftUI

/// One place for Cap's look. Keep color/spacing decisions here so the views stay calm.
enum Theme {
    static let accent = Color(red: 0.89, green: 0.44, blue: 0.42)    // warm coral (matches the icon)
    static let userBubble = LinearGradient(
        colors: [Color(red: 0.93, green: 0.50, blue: 0.43), Color(red: 0.78, green: 0.42, blue: 0.62)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let assistantBubble = Color(.secondarySystemBackground)
    static let corner: CGFloat = 18

    /// Soft warm wash for cozy card/screen backgrounds (the Dormway-ish mesh-gradient feel).
    static let warmWash = LinearGradient(
        colors: [Color(red: 1.0, green: 0.92, blue: 0.84), Color(red: 0.99, green: 0.86, blue: 0.86)],
        startPoint: .top, endPoint: .bottom
    )
}
