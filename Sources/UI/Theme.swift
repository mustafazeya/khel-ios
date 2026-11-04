import SwiftUI

enum Theme {
    static let bg = Color(red: 0.055, green: 0.055, blue: 0.09)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.15)
    static let surface2 = Color(red: 0.15, green: 0.15, blue: 0.21)
    static let text2 = Color(white: 0.72)
    static let dim = Color(white: 0.5)
    static let saffron = Color(red: 1.0, green: 0.52, blue: 0.10)
    static let accent = saffron
    static let teal = Color(red: 0.10, green: 0.80, blue: 0.70)
    static let good = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let bad = Color(red: 1.0, green: 0.35, blue: 0.35)

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }

    static func gradient(_ palette: [UInt32]) -> LinearGradient {
        LinearGradient(colors: palette.map(color), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Distinct colour per seat, used for pieces and highlights.
    static let seatColors: [Color] = [
        Color(red: 0.22, green: 0.50, blue: 0.95), Color(red: 0.93, green: 0.27, blue: 0.27),
        Color(red: 0.18, green: 0.72, blue: 0.40), Color(red: 0.98, green: 0.78, blue: 0.15),
    ]
}

extension Font {
    static let khTitle = Font.system(size: 32, weight: .heavy, design: .rounded)
    static let khHeadline = Font.system(size: 18, weight: .bold, design: .rounded)
    static let khLabel = Font.system(size: 12, weight: .bold, design: .rounded)
}

struct Kicker: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.khLabel).tracking(1.6).foregroundStyle(Theme.text2)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
