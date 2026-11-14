import AppKit
import SwiftUI

/// sRGB barva v rozsahu 0...255 (RGB a contrastRatio jsou čistá logika bez AppKitu;
/// AppKit soubor importuje jen kvůli adaptivní NSColor níže).
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
/// Tmavý warning je systemOrange (dark); tmavý critical je světlejší
/// než systemRed (255,69,58), který má na pozadí 43/255 jen ≈4,15:1.
enum WarningPalette {
    static let lightWarning = RGB(r: 150, g: 70, b: 0)
    static let lightCritical = RGB(r: 180, g: 0, b: 0)
    static let darkWarning = RGB(r: 255, g: 159, b: 10)
    static let darkCritical = RGB(r: 255, g: 105, b: 97)

    /// Pozadí popoveru (windowBackground): světlý ≈ bílá, tmavý 43/255 jako kreslí Snapshotter
    /// (Color(white: 0.17)); testy navíc kontrolují starší odhad 30/255.
    static let lightBackground = RGB.white
    static let darkBackground = RGB(r: 43, g: 43, b: 43)

    static let warningNS = adaptive(light: lightWarning, dark: darkWarning)
    static let criticalNS = adaptive(light: lightCritical, dark: darkCritical)
    static let warning = Color(nsColor: warningNS)
    static let critical = Color(nsColor: criticalNS)

    private static func adaptive(light: RGB, dark: RGB) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1)
        }
    }
}
