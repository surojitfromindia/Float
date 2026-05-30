import SwiftUI
import UIKit

enum FloatColorTheme: String, CaseIterable, Identifiable {
    case float
    case ocean
    case forest
    case royal
    case rose
    case ember
    case graphite
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .float: "Float"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .royal: "Royal"
        case .rose: "Rose"
        case .ember: "Ember"
        case .graphite: "Graphite"
        case .system: "System dynamic"
        }
    }
}

struct FloatThemePalette {
    let accent: Color
    let accentSoft: Color
    let positive: Color
    let caution: Color
    let backgroundTop: Color
    let backgroundBottom: Color
    let chartColors: [Color]
}

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

    static func colorTheme(for rawValue: String) -> FloatColorTheme {
        FloatColorTheme(rawValue: rawValue) ?? .float
    }

    static func palette(for rawValue: String) -> FloatThemePalette {
        palette(for: colorTheme(for: rawValue))
    }

    static func palette(for theme: FloatColorTheme) -> FloatThemePalette {
        switch theme {
        case .float:
            FloatThemePalette(
                accent: Color(hex: "#0E7C7B"),
                accentSoft: Color(hex: "#D7F0EE"),
                positive: Color(hex: "#1B8A5A"),
                caution: Color(hex: "#B4613B"),
                backgroundTop: Color(lightHex: "#EEF8F6", darkHex: "#081615"),
                backgroundBottom: Color(lightHex: "#D8EDEA", darkHex: "#102321"),
                chartColors: [
                    Color(hex: "#0E7C7B"),
                    Color(hex: "#1B8A5A"),
                    Color(hex: "#3B82F6"),
                    Color(hex: "#8B5CF6"),
                    Color(hex: "#B4613B"),
                    Color(hex: "#EC4899"),
                ]
            )
        case .ocean:
            FloatThemePalette(
                accent: Color(hex: "#0A6FAE"),
                accentSoft: Color(hex: "#D8ECFA"),
                positive: Color(hex: "#087F5B"),
                caution: Color(hex: "#B7791F"),
                backgroundTop: Color(lightHex: "#EDF7FF", darkHex: "#07131D"),
                backgroundBottom: Color(lightHex: "#D6E9F7", darkHex: "#0E2433"),
                chartColors: [
                    Color(hex: "#0A6FAE"),
                    Color(hex: "#00A6A6"),
                    Color(hex: "#2457C5"),
                    Color(hex: "#6A8DFF"),
                    Color(hex: "#087F5B"),
                    Color(hex: "#B7791F"),
                ]
            )
        case .forest:
            FloatThemePalette(
                accent: Color(hex: "#2F6F3E"),
                accentSoft: Color(hex: "#DCEEDB"),
                positive: Color(hex: "#1B8A5A"),
                caution: Color(hex: "#A65F2B"),
                backgroundTop: Color(lightHex: "#EFF8EB", darkHex: "#0A150C"),
                backgroundBottom: Color(lightHex: "#DDEDD5", darkHex: "#132415"),
                chartColors: [
                    Color(hex: "#2F6F3E"),
                    Color(hex: "#7A9E3D"),
                    Color(hex: "#0F766E"),
                    Color(hex: "#8B5CF6"),
                    Color(hex: "#A65F2B"),
                    Color(hex: "#3B82F6"),
                ]
            )
        case .royal:
            FloatThemePalette(
                accent: Color(hex: "#5B4DDB"),
                accentSoft: Color(hex: "#E7E4FF"),
                positive: Color(hex: "#15803D"),
                caution: Color(hex: "#C2410C"),
                backgroundTop: Color(lightHex: "#F4F1FF", darkHex: "#100D22"),
                backgroundBottom: Color(lightHex: "#E4DFFF", darkHex: "#1B1738"),
                chartColors: [
                    Color(hex: "#5B4DDB"),
                    Color(hex: "#2563EB"),
                    Color(hex: "#A855F7"),
                    Color(hex: "#DB2777"),
                    Color(hex: "#15803D"),
                    Color(hex: "#C2410C"),
                ]
            )
        case .rose:
            FloatThemePalette(
                accent: Color(hex: "#C0265E"),
                accentSoft: Color(hex: "#FCE1EC"),
                positive: Color(hex: "#168A5A"),
                caution: Color(hex: "#B45309"),
                backgroundTop: Color(lightHex: "#FFF0F5", darkHex: "#1D0B12"),
                backgroundBottom: Color(lightHex: "#F8DCE8", darkHex: "#321522"),
                chartColors: [
                    Color(hex: "#C0265E"),
                    Color(hex: "#E11D48"),
                    Color(hex: "#9333EA"),
                    Color(hex: "#0EA5E9"),
                    Color(hex: "#168A5A"),
                    Color(hex: "#B45309"),
                ]
            )
        case .ember:
            FloatThemePalette(
                accent: Color(hex: "#B45309"),
                accentSoft: Color(hex: "#FDE7C7"),
                positive: Color(hex: "#1B8A5A"),
                caution: Color(hex: "#B91C1C"),
                backgroundTop: Color(lightHex: "#FFF3E4", darkHex: "#1B1008"),
                backgroundBottom: Color(lightHex: "#F3DFC2", darkHex: "#302012"),
                chartColors: [
                    Color(hex: "#B45309"),
                    Color(hex: "#DC2626"),
                    Color(hex: "#D97706"),
                    Color(hex: "#0F766E"),
                    Color(hex: "#2563EB"),
                    Color(hex: "#7C3AED"),
                ]
            )
        case .graphite:
            FloatThemePalette(
                accent: Color(hex: "#475569"),
                accentSoft: Color(hex: "#E2E8F0"),
                positive: Color(hex: "#15803D"),
                caution: Color(hex: "#B45309"),
                backgroundTop: Color(lightHex: "#F0F2F5", darkHex: "#0F1115"),
                backgroundBottom: Color(lightHex: "#DDE1E7", darkHex: "#1B1F27"),
                chartColors: [
                    Color(hex: "#475569"),
                    Color(hex: "#0F766E"),
                    Color(hex: "#2563EB"),
                    Color(hex: "#7C3AED"),
                    Color(hex: "#B45309"),
                    Color(hex: "#BE123C"),
                ]
            )
        case .system:
            FloatThemePalette(
                accent: Color.accentColor,
                accentSoft: Color.accentColor.opacity(0.16),
                positive: Color(hex: "#1B8A5A"),
                caution: Color(hex: "#B4613B"),
                backgroundTop: Color(.systemBackground),
                backgroundBottom: Color(.secondarySystemBackground),
                chartColors: [
                    Color.accentColor,
                    Color(hex: "#1B8A5A"),
                    Color(hex: "#3B82F6"),
                    Color(hex: "#8B5CF6"),
                    Color(hex: "#B4613B"),
                    Color(hex: "#EC4899"),
                ]
            )
        }
    }
}

extension Color {
    init(lightHex: String, darkHex: String) {
        self.init(
            UIColor { traits in
                UIColor(
                    hex: traits.userInterfaceStyle == .dark
                        ? darkHex : lightHex
                )
            }
        )
    }

    init(hex: String) {
        self.init(UIColor(hex: hex))
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let components = Self.rgbComponents(from: hex)
        self.init(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )
    }

    static func rgbComponents(from hex: String)
        -> (red: CGFloat, green: CGFloat, blue: CGFloat)
    {
        let cleaned = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        guard cleaned.count == 6 else {
            return (
                CGFloat(14) / 255,
                CGFloat(124) / 255,
                CGFloat(123) / 255
            )
        }

        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }
}

extension View {
    func floatBackground() -> some View {
        modifier(FloatBackgroundModifier())
    }

    func moneyStyle(size: CGFloat, weight: Font.Weight = .semibold) -> some View
    {
        font(
            .system(size: size, weight: weight, design: .rounded)
                .monospacedDigit()
        )
    }
}

private struct FloatBackgroundModifier: ViewModifier {
    @AppStorage("selectedThemeMode") private var selectedThemeMode = "float"

    func body(content: Content) -> some View {
        let palette = FloatTheme.palette(for: selectedThemeMode)
        content.background(
            LinearGradient(
                colors: [
                    palette.backgroundTop,
                    palette.backgroundBottom.opacity(0.78),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}
