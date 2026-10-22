import SwiftUI

/// The few colors used by the demo. Fonts are all system fonts.
enum DemoStyle {
    static let backgroundBottom = Color(white: 19.0 / 255)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.75)
    static let primary400 = Color(red: 188.0 / 255, green: 164.0 / 255, blue: 244.0 / 255)
    static let cardFill = Color(white: 229.0 / 255).opacity(0.10)
    static let cardStroke = Color.white.opacity(0.14)
    static let white008 = Color.white.opacity(0.08)
    static let cardBorderGradient = LinearGradient(
        colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom
    )
}
