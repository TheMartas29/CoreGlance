import AppKit
import SwiftUI

/// sRGB barva v rozsahu 0...255 (bez AppKitu, aby šla použít v testech kontrastu).
struct RGB: Equatable {
    let r: Double, g: Double, b: Double

    /// WCAG 2.x relativní luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double {
            let s = c / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static let white = RGB(r: 255, g: 255, b: 255)
    static let black = RGB(r: 0, g: 0, b: 0)
}

/// WCAG 1.4.3 poměr kontrastu (1...21); symetrický.
func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
    let la = a.luminance, lb = b.luminance
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// Barvy hodnot ve stavu warning/critical v popoveru. Systémové `.orange`/`.red` mají na světlém pozadí
/// kontrast jen ~2,0:1 a ~3,3:1 (pod WCAG 4,5:1), proto má světlý režim tmavší odstíny.
/// Tmavý režim zůstává u hodnot systémových barev (systemOrange/systemRed v dark).
enum WarningPalette {
    static let lightWarning = RGB(r: 150, g: 70, b: 0)
    static let lightCritical = RGB(r: 180, g: 0, b: 0)
    static let darkWarning = RGB(r: 255, g: 159, b: 10)
    static let darkCritical = RGB(r: 255, g: 69, b: 58)

    /// Pozadí popoveru (windowBackground): světlý ≈ bílá, tmavý ≈ 30/255.
    static let lightBackground = RGB.white
    static let darkBackground = RGB(r: 30, g: 30, b: 30)

    static let warning = adaptive(light: lightWarning, dark: darkWarning)
    static let critical = adaptive(light: lightCritical, dark: darkCritical)

    private static func adaptive(light: RGB, dark: RGB) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1)
        })
    }
}
