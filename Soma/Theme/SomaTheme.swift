import SwiftUI

// MARK: - Soma design tokens (mirrors the Soma web app: src/index.css)

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: UInt64
        if h.count == 6 {
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        } else {
            (r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

enum SomaTheme {
    // hsl(240, 10%, 3.9%) — app background (dark only)
    static let background = Color(red: 0.039, green: 0.039, blue: 0.059)
    // hsl(240, 10%, 6%) — cards
    static let card = Color(red: 0.060, green: 0.060, blue: 0.078)
    // hsl(240, 3.7%, 15.9%) — borders
    static let border = Color(red: 0.159, green: 0.159, blue: 0.172)
    // hsl(347, 77%, 50%) — BP accent
    static let rose = Color(red: 0.882, green: 0.114, blue: 0.282)

    // Chart colors (match web BP charts)
    static let systolic = Color(hex: "f43f5e")
    static let diastolic = Color(hex: "3b82f6")
    static let slate = Color(hex: "94a3b8")

    static let text = Color(hex: "fafafa")
    static let muted = Color(hex: "9c9ca6")

    // BP category colors — HTN Canada 2025 guideline (dark mode), matches web
    static let categoryNormalBG = Color(red: 0.078, green: 0.325, blue: 0.176).opacity(0.30)
    static let categoryNormalText = Color(hex: "4ade80")
    static let categoryHypertensionBG = Color(red: 0.471, green: 0.208, blue: 0.059).opacity(0.30)
    static let categoryHypertensionText = Color(hex: "fbbf24")
    static let categoryTreatBG = Color(red: 0.498, green: 0.114, blue: 0.114).opacity(0.30)
    static let categoryTreatText = Color(hex: "f87171")

    static let cardRadius: CGFloat = 12
}

// MARK: - Typography (LINE Seed JP, bundled; falls back to system)

enum SomaFont {
    static func regular(_ size: CGFloat) -> Font {
        .custom("LINESeedJP-Regular", size: size)
    }
    static func bold(_ size: CGFloat) -> Font {
        .custom("LINESeedJP-Bold", size: size)
    }
    static func medium(_ size: CGFloat) -> Font {
        // No medium weight bundled — use regular; SwiftUI synthesizes weight poorly,
        // so prefer bold for emphasis.
        .custom("LINESeedJP-Regular", size: size)
    }
}
