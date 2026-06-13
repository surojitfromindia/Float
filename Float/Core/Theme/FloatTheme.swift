import SwiftUI
import UIKit

enum FloatColorTheme: String, CaseIterable, Identifiable {
    case float
    case ocean
    case forest
    case sage
    case mint
    case willow
    case graphite
    case aurora
    case sunset
    case ember
    case plum
    case midnight
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .float: "Float"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .sage: "Sage"
        case .mint: "Mint"
        case .willow: "Willow"
        case .graphite: "Graphite"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .ember: "Ember"
        case .plum: "Plum"
        case .midnight: "Midnight"
        case .system: "System dynamic"
        }
    }

    var subtitle: String {
        switch self {
        case .float: "Balanced teal"
        case .ocean: "Bright blue water"
        case .forest: "Deep green canopy"
        case .sage: "Soft modern neutral"
        case .mint: "Fresh mint glass"
        case .willow: "Warm leafy tones"
        case .graphite: "Slate and steel"
        case .aurora: "Electric sky glow"
        case .sunset: "Warm coral dusk"
        case .ember: "Deep red ember"
        case .plum: "Violet and berry"
        case .midnight: "Moody midnight blue"
        case .system: "Matches the device"
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
    let hero: FloatHeroPalette
}

struct FloatHeroPalette {
    let accent: Color
    let positive: Color
    let caution: Color
    let backgroundTop: Color
    let backgroundBottom: Color
    let glow: Color
    let railTrack: Color
}

enum FloatTheme {
    static let cardRadius: CGFloat = 28
    static let tileRadius: CGFloat = 16
    static let controlRadius: CGFloat = 18
    static let radius: CGFloat = cardRadius

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
        switch rawValue {
        case "royal":
            return .sage
        case "rose":
            return .mint
        default:
            break
        }
        return FloatColorTheme(rawValue: rawValue) ?? .float
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
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#2B8F7F", darkHex: "#59D0AE"),
                    positive: Color(lightHex: "#2C9B68", darkHex: "#65D497"),
                    caution: Color(lightHex: "#B86F39", darkHex: "#D9A15D"),
                    backgroundTop: Color(lightHex: "#F1F9F7", darkHex: "#0A1111"),
                    backgroundBottom: Color(lightHex: "#DCEDEA", darkHex: "#12211E"),
                    glow: Color(lightHex: "#8EDCC4", darkHex: "#2CB783"),
                    railTrack: Color(lightHex: "#CBD8D4", darkHex: "#2A3A37")
                )
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
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#256FB3", darkHex: "#72B6FF"),
                    positive: Color(lightHex: "#218E68", darkHex: "#61D2A0"),
                    caution: Color(lightHex: "#B8792A", darkHex: "#E0B060"),
                    backgroundTop: Color(lightHex: "#EEF7FF", darkHex: "#07111D"),
                    backgroundBottom: Color(lightHex: "#D9ECFA", darkHex: "#0F2637"),
                    glow: Color(lightHex: "#8CC4FF", darkHex: "#2F95FF"),
                    railTrack: Color(lightHex: "#D0DCE7", darkHex: "#223244")
                )
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
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#2E7A46", darkHex: "#6ED78A"),
                    positive: Color(lightHex: "#257F5F", darkHex: "#60CB91"),
                    caution: Color(lightHex: "#A96A33", darkHex: "#D8A35D"),
                    backgroundTop: Color(lightHex: "#EFF8ED", darkHex: "#08130B"),
                    backgroundBottom: Color(lightHex: "#DDEBD6", darkHex: "#122116"),
                    glow: Color(lightHex: "#92D59B", darkHex: "#3CA86E"),
                    railTrack: Color(lightHex: "#D0DDCF", darkHex: "#24342A")
                )
            )
        case .sage:
            FloatThemePalette(
                accent: Color(hex: "#5C8C69"),
                accentSoft: Color(hex: "#E2F0E4"),
                positive: Color(hex: "#2F8C63"),
                caution: Color(hex: "#A67C55"),
                backgroundTop: Color(lightHex: "#F2FAF4", darkHex: "#091410"),
                backgroundBottom: Color(lightHex: "#DDE9E0", darkHex: "#13211B"),
                chartColors: [
                    Color(hex: "#5C8C69"),
                    Color(hex: "#8AB58B"),
                    Color(hex: "#2F8C63"),
                    Color(hex: "#4C9D8B"),
                    Color(hex: "#A67C55"),
                    Color(hex: "#99B56B"),
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#55846A", darkHex: "#7BC39A"),
                    positive: Color(lightHex: "#328562", darkHex: "#67C096"),
                    caution: Color(lightHex: "#AA825C", darkHex: "#D2A36E"),
                    backgroundTop: Color(lightHex: "#F1F9F3", darkHex: "#09120F"),
                    backgroundBottom: Color(lightHex: "#DEEADF", darkHex: "#13211B"),
                    glow: Color(lightHex: "#A8D8B1", darkHex: "#4BAF86"),
                    railTrack: Color(lightHex: "#D5DED6", darkHex: "#24342D")
                )
            )
        case .mint:
            FloatThemePalette(
                accent: Color(hex: "#4B9A8A"),
                accentSoft: Color(hex: "#DCF4EE"),
                positive: Color(hex: "#3F8B64"),
                caution: Color(hex: "#A47E57"),
                backgroundTop: Color(lightHex: "#F1FBF8", darkHex: "#081512"),
                backgroundBottom: Color(lightHex: "#D5ECE5", darkHex: "#10211C"),
                chartColors: [
                    Color(hex: "#4B9A8A"),
                    Color(hex: "#72C3A6"),
                    Color(hex: "#3F8B64"),
                    Color(hex: "#69A3B8"),
                    Color(hex: "#A47E57"),
                    Color(hex: "#8DB88B"),
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#458F86", darkHex: "#67D0C2"),
                    positive: Color(lightHex: "#2F8C68", darkHex: "#61CFA1"),
                    caution: Color(lightHex: "#A47F5C", darkHex: "#D0A475"),
                    backgroundTop: Color(lightHex: "#F0FBF8", darkHex: "#081412"),
                    backgroundBottom: Color(lightHex: "#D8ECE7", darkHex: "#11211C"),
                    glow: Color(lightHex: "#8DE1CF", darkHex: "#36B89B"),
                    railTrack: Color(lightHex: "#D2E0DC", darkHex: "#223430")
                )
            )
        case .willow:
            FloatThemePalette(
                accent: Color(hex: "#6B8E5A"),
                accentSoft: Color(hex: "#E4F1D8"),
                positive: Color(hex: "#4A8F6D"),
                caution: Color(hex: "#A58B57"),
                backgroundTop: Color(lightHex: "#F5FAF1", darkHex: "#0D150B"),
                backgroundBottom: Color(lightHex: "#E1E9D5", darkHex: "#172317"),
                chartColors: [
                    Color(hex: "#6B8E5A"),
                    Color(hex: "#9AB56C"),
                    Color(hex: "#4A8F6D"),
                    Color(hex: "#6AA9A1"),
                    Color(hex: "#A58B57"),
                    Color(hex: "#8696C8"),
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#6B9156", darkHex: "#A0D06E"),
                    positive: Color(lightHex: "#3F8E66", darkHex: "#69C88E"),
                    caution: Color(lightHex: "#A78752", darkHex: "#D0A86A"),
                    backgroundTop: Color(lightHex: "#F4FAEE", darkHex: "#0B1208"),
                    backgroundBottom: Color(lightHex: "#E3ECD6", darkHex: "#182316"),
                    glow: Color(lightHex: "#B3D783", darkHex: "#5BB66C"),
                    railTrack: Color(lightHex: "#D7E0CF", darkHex: "#253225")
                )
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
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#52657A", darkHex: "#8FA2B8"),
                    positive: Color(lightHex: "#2E8A5C", darkHex: "#73C792"),
                    caution: Color(lightHex: "#A56F2E", darkHex: "#D6A35F"),
                    backgroundTop: Color(lightHex: "#F2F5F8", darkHex: "#0D1014"),
                    backgroundBottom: Color(lightHex: "#E2E7EC", darkHex: "#171C23"),
                    glow: Color(lightHex: "#B9C5D0", darkHex: "#5D748B"),
                    railTrack: Color(lightHex: "#D5DCE3", darkHex: "#27313D")
                )
            )
        case .aurora:
            FloatThemePalette(
                accent: Color(hex: "#4D86F7"),
                accentSoft: Color(hex: "#DCE8FF"),
                positive: Color(hex: "#2FB57D"),
                caution: Color(hex: "#D9963D"),
                backgroundTop: Color(lightHex: "#EEF6FF", darkHex: "#071320"),
                backgroundBottom: Color(lightHex: "#DCEEFF", darkHex: "#0E2238"),
                chartColors: [
                    Color(hex: "#4D86F7"),
                    Color(hex: "#33C3B2"),
                    Color(hex: "#67B7FF"),
                    Color(hex: "#8C6CF7"),
                    Color(hex: "#D9963D"),
                    Color(hex: "#EF5DA8"),
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#5281FF", darkHex: "#8AB5FF"),
                    positive: Color(lightHex: "#2FAF7E", darkHex: "#65D6A1"),
                    caution: Color(lightHex: "#D2903C", darkHex: "#E6B164"),
                    backgroundTop: Color(lightHex: "#EEF6FF", darkHex: "#07101E"),
                    backgroundBottom: Color(lightHex: "#DDEAFF", darkHex: "#10243E"),
                    glow: Color(lightHex: "#9BC0FF", darkHex: "#4A9FFF"),
                    railTrack: Color(lightHex: "#D4E0F0", darkHex: "#23344A")
                )
            )
        case .sunset:
            FloatThemePalette(
                accent: Color(hex: "#E06B4E"),
                accentSoft: Color(hex: "#FFE1D8"),
                positive: Color(hex: "#2E9E77"),
                caution: Color(hex: "#C98B2E"),
                backgroundTop: Color(lightHex: "#FFF4EE", darkHex: "#1B1115"),
                backgroundBottom: Color(lightHex: "#FFE1D7", darkHex: "#352029"),
                chartColors: [
                    Color(hex: "#E06B4E"),
                    Color(hex: "#F59E3D"),
                    Color(hex: "#EC4899"),
                    Color(hex: "#8B5CF6"),
                    Color(hex: "#2E9E77"),
                    Color(hex: "#C2410C"),
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#D96A4D", darkHex: "#FF9A74"),
                    positive: Color(lightHex: "#2E986E", darkHex: "#63D29A"),
                    caution: Color(lightHex: "#C98A32", darkHex: "#E4B05C"),
                    backgroundTop: Color(lightHex: "#FFF4EE", darkHex: "#1A1113"),
                    backgroundBottom: Color(lightHex: "#FFE0D8", darkHex: "#331F26"),
                    glow: Color(lightHex: "#F2A07D", darkHex: "#E86E7A"),
                    railTrack: Color(lightHex: "#EED6CC", darkHex: "#3A2730")
                )
            )
        case .ember:
            FloatThemePalette(
                accent: Color(hex: "#C2412D"),
                accentSoft: Color(hex: "#F8DDD6"),
                positive: Color(hex: "#2F9E7C"),
                caution: Color(hex: "#D28B2E"),
                backgroundTop: Color(lightHex: "#FFF2EE", darkHex: "#1D0E10"),
                backgroundBottom: Color(lightHex: "#FFE0DA", darkHex: "#35191D"),
                chartColors: [
                    Color(hex: "#C2412D"),
                    Color(hex: "#E06B4E"),
                    Color(hex: "#F59E3D"),
                    Color(hex: "#8D5CF6"),
                    Color(hex: "#2F9E7C"),
                    Color(hex: "#BE123C"),
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#C94A35", darkHex: "#FF8E74"),
                    positive: Color(lightHex: "#2F986F", darkHex: "#64D19A"),
                    caution: Color(lightHex: "#D38C34", darkHex: "#E6B05E"),
                    backgroundTop: Color(lightHex: "#FFF2EE", darkHex: "#1B0D10"),
                    backgroundBottom: Color(lightHex: "#FFE0D9", darkHex: "#35181D"),
                    glow: Color(lightHex: "#F2A08F", darkHex: "#F16D64"),
                    railTrack: Color(lightHex: "#EFD5D0", darkHex: "#3A2327")
                )
            )
        case .plum:
            FloatThemePalette(
                accent: Color(hex: "#8D5CF6"),
                accentSoft: Color(hex: "#E9DDFF"),
                positive: Color(hex: "#2E9E8A"),
                caution: Color(hex: "#D07A45"),
                backgroundTop: Color(lightHex: "#F6F0FF", darkHex: "#110C1D"),
                backgroundBottom: Color(lightHex: "#E9DEFF", darkHex: "#201033"),
                chartColors: [
                    Color(hex: "#8D5CF6"),
                    Color(hex: "#C65CF0"),
                    Color(hex: "#5D87FF"),
                    Color(hex: "#2E9E8A"),
                    Color(hex: "#D07A45"),
                    Color(hex: "#F472B6"),
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#8B62E8", darkHex: "#B08EFF"),
                    positive: Color(lightHex: "#2E9B84", darkHex: "#69D0B7"),
                    caution: Color(lightHex: "#CB8240", darkHex: "#E1AA67"),
                    backgroundTop: Color(lightHex: "#F6F0FF", darkHex: "#120C1C"),
                    backgroundBottom: Color(lightHex: "#E9DEFF", darkHex: "#211133"),
                    glow: Color(lightHex: "#D3BAFF", darkHex: "#8E69FF"),
                    railTrack: Color(lightHex: "#DDD5EE", darkHex: "#2D243F")
                )
            )
        case .midnight:
            FloatThemePalette(
                accent: Color(hex: "#6AA9FF"),
                accentSoft: Color(hex: "#DCE9FF"),
                positive: Color(hex: "#4CBF88"),
                caution: Color(hex: "#D79A49"),
                backgroundTop: Color(lightHex: "#EDF2FF", darkHex: "#07111F"),
                backgroundBottom: Color(lightHex: "#D9E6F7", darkHex: "#101C31"),
                chartColors: [
                    Color(hex: "#6AA9FF"),
                    Color(hex: "#5B8DEF"),
                    Color(hex: "#22D3EE"),
                    Color(hex: "#4CBF88"),
                    Color(hex: "#D79A49"),
                    Color(hex: "#F472B6"),
                ],
                hero: FloatHeroPalette(
                    accent: Color(lightHex: "#5F99F1", darkHex: "#82BAFF"),
                    positive: Color(lightHex: "#3EAE78", darkHex: "#71D69A"),
                    caution: Color(lightHex: "#CD9545", darkHex: "#E3B264"),
                    backgroundTop: Color(lightHex: "#EDF2FF", darkHex: "#07111F"),
                    backgroundBottom: Color(lightHex: "#D9E6F7", darkHex: "#101C31"),
                    glow: Color(lightHex: "#9BBCFF", darkHex: "#3A8DFF"),
                    railTrack: Color(lightHex: "#D5E0EF", darkHex: "#223046")
                )
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
                ],
                hero: FloatHeroPalette(
                    accent: Color.accentColor,
                    positive: Color(hex: "#1B8A5A"),
                    caution: Color(hex: "#B4613B"),
                    backgroundTop: Color(.systemBackground),
                    backgroundBottom: Color(.secondarySystemBackground),
                    glow: Color.accentColor.opacity(0.28),
                    railTrack: Color(.quaternaryLabel).opacity(0.25)
                )
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
    func body(content: Content) -> some View {
        content.background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
    }
}
