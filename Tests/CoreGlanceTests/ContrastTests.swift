import XCTest
@testable import CoreGlance

final class ContrastTests: XCTestCase {
    // Známé hodnoty z WCAG: černá/bílá = 21:1, shodné barvy = 1:1.
    func testBlackOnWhiteIs21() {
        XCTAssertEqual(contrastRatio(.black, .white), 21, accuracy: 0.001)
        XCTAssertEqual(contrastRatio(.white, .black), 21, accuracy: 0.001)
    }

    func testIdenticalColorsAre1() {
        XCTAssertEqual(contrastRatio(.white, .white), 1, accuracy: 0.0001)
        XCTAssertEqual(contrastRatio(RGB(r: 150, g: 70, b: 0), RGB(r: 150, g: 70, b: 0)), 1, accuracy: 0.0001)
    }

    // Dosavadní systémové barvy ve světlém režimu (oranžová ~2,0:1) WCAG nesplňují – důvod změny.
    func testOldSystemOrangeFailsOnWhite() {
        XCTAssertLessThan(contrastRatio(RGB(r: 255, g: 149, b: 0), .white), 4.5)
    }

    func testLightPaletteMeetsAAOnWhite() {
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.lightWarning, WarningPalette.lightBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.lightCritical, WarningPalette.lightBackground), 4.5)
    }

    // Skutečné světlé pozadí okna bývá šedivější než čistě bílá (~236).
    func testLightPaletteMeetsAAOnLightGray() {
        let gray = RGB(r: 236, g: 236, b: 236)
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.lightWarning, gray), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.lightCritical, gray), 4.5)
    }

    // Pozadí popoveru, které kreslí Snapshotter: Color(white: 0.17) ≈ 43/255 (0,17 × 255 = 43,35).
    // Ruční výpočet WCAG pro původní darkCritical (255,69,58): ≈ 4,15:1 (<4,5).
    func testDarkPaletteMeetsAAOnSnapshotBackground() {
        let snapshot = RGB(r: 43, g: 43, b: 43)
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkWarning, snapshot), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkCritical, snapshot), 4.5)
    }

    // Oba krajní případy tmavého pozadí: 30/255 (odhad windowBackground) i 43/255 (Snapshotter).
    func testDarkPaletteMeetsAAOnBothBackgroundExtremes() {
        for v in [30.0, 43.0] {
            let bg = RGB(r: v, g: v, b: v)
            XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkWarning, bg), 4.5, "warning na \(v)")
            XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkCritical, bg), 4.5, "critical na \(v)")
        }
    }

    // Skutečné windowBackgroundColor pod darkAqua musí být v rozmezí testovaných pozadí (≤ 43/255 + tolerance).
    func testDarkWindowBackgroundIsCovered() throws {
        var rgb: (Double, Double, Double)?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            if let c = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) {
                rgb = (c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255)
            }
        }
        let v = try XCTUnwrap(rgb)
        let bg = RGB(r: v.0, g: v.1, b: v.2)
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkWarning, bg), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkCritical, bg), 4.5)
    }

    private func resolved(_ color: NSColor, _ name: NSAppearance.Name) -> (Double, Double, Double) {
        var out = (0.0, 0.0, 0.0)
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            out = (c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255)
        }
        return out
    }

    private func assertMatches(_ got: (Double, Double, Double), _ want: RGB, _ msg: String) {
        XCTAssertEqual(got.0, want.r, accuracy: 1, msg)
        XCTAssertEqual(got.1, want.g, accuracy: 1, msg)
        XCTAssertEqual(got.2, want.b, accuracy: 1, msg)
    }

    func testAdaptiveColorsFollowAppearance() {
        assertMatches(resolved(WarningPalette.warningNS, .aqua), WarningPalette.lightWarning, "warning aqua")
        assertMatches(resolved(WarningPalette.warningNS, .darkAqua), WarningPalette.darkWarning, "warning darkAqua")
        assertMatches(resolved(WarningPalette.criticalNS, .aqua), WarningPalette.lightCritical, "critical aqua")
        assertMatches(resolved(WarningPalette.criticalNS, .darkAqua), WarningPalette.darkCritical, "critical darkAqua")
    }

    func testDarkPaletteMeetsAAOnDark() {
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkWarning, WarningPalette.darkBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkCritical, WarningPalette.darkBackground), 4.5)
    }
}
