import SwiftUI

enum FloatTheme {
    static let radius: CGFloat = 28

    static let primaryLight = Color(hex: "#0E7C7B")
    static let primaryContainerLight = Color(hex: "#D7F0EE")
    static let backgroundLight = Color(hex: "#FAFCFC")
    static let surfaceLight = Color(hex: "#FFFFFF")
    static let positiveLight = Color(hex: "#1B8A5A")
    static let cautionLight = Color(hex: "#B4613B")
    static let textPrimaryLight = Color(hex: "#0B1F1F")
    static let textSecondaryLight = Color(hex: "#5A6B6B")

    static let backgroundDark = Color(hex: "#0B1414")
    static let surfaceDark = Color(hex: "#13201F")
    static let primaryDark = Color(hex: "#3FC1BE")
    static let textPrimaryDark = Color(hex: "#E6F2F1")
    static let textSecondaryDark = Color(hex: "#9EB7B5")
    static let positiveDark = Color(hex: "#57C98C")
    static let cautionDark = Color(hex: "#D08A62")
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red: UInt64
        let green: UInt64
        let blue: UInt64
        switch cleaned.count {
        case 6:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        default:
            red = 14
            green = 124
            blue = 123
        }
        self.init(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }
}

extension View {
    func floatBackground() -> some View {
        background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground).opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    func moneyStyle(size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        font(.system(size: size, weight: weight, design: .rounded).monospacedDigit())
    }
}
