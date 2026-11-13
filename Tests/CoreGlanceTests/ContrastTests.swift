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

    func testDarkPaletteMeetsAAOnDark() {
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkWarning, WarningPalette.darkBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(WarningPalette.darkCritical, WarningPalette.darkBackground), 4.5)
    }
}
