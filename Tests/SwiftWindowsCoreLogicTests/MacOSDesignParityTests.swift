import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Pins the macOS-equivalent design constants documented in
/// `docs/MacOSDesignParity.md`. Each test corresponds to a row in that
/// doc; changing a constant without updating the doc fails this suite.
@MainActor
final class MacOSDesignParityTests: XCTestCase {

    // MARK: - Font.system text styles

    func testLargeTitleSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.largeTitle.size, 34, accuracy: 0.001)
    }

    func testTitleSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.title.size, 28, accuracy: 0.001)
    }

    func testTitle2SizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.title2.size, 22, accuracy: 0.001)
    }

    func testTitle3SizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.title3.size, 20, accuracy: 0.001)
    }

    func testHeadlineSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.headline.size, 17, accuracy: 0.001)
    }

    func testHeadlineUsesSemiboldWeightLikeSwiftUI() async {
        XCTAssertEqual(Font.headline.weight, .semibold)
    }

    func testSubheadlineSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.subheadline.size, 15, accuracy: 0.001)
    }

    func testBodySizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.body.size, 17, accuracy: 0.001)
    }

    func testCalloutSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.callout.size, 16, accuracy: 0.001)
    }

    func testFootnoteSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.footnote.size, 13, accuracy: 0.001)
    }

    func testCaptionSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.caption.size, 12, accuracy: 0.001)
    }

    func testCaption2SizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.caption2.size, 11, accuracy: 0.001)
    }

    func testNonHeadlineStylesUseRegularWeightLikeSwiftUI() async {
        XCTAssertEqual(Font.body.weight, .regular)
        XCTAssertEqual(Font.title.weight, .regular)
        XCTAssertEqual(Font.callout.weight, .regular)
        XCTAssertEqual(Font.footnote.weight, .regular)
        XCTAssertEqual(Font.caption.weight, .regular)
    }

    // MARK: - Control chrome defaults

    func testDefaultControlChromeMatchesMacOS() async {
        let chrome = SurfaceChrome.default
        XCTAssertEqual(chrome.borderWidth, 1, "Standard controls use a hairline border")
        XCTAssertEqual(chrome.focusRingWidth, 2, "Focus ring matches macOS stroke width")
    }

    func testElevatedButtonChromeMatchesMacOS() async {
        let chrome = SurfaceChrome.elevatedButton
        XCTAssertEqual(chrome.borderWidth, 1)
        XCTAssertEqual(chrome.focusRingWidth, 2)
    }

    func testControlAnimationStyleDefaultsMatchMacOSBigSur() async {
        let style = ControlAnimationStyle.default
        XCTAssertEqual(style.focusDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(style.pressDuration, 0.14, accuracy: 0.001)
        XCTAssertEqual(style.activationDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(ControlAnimationStyle.pressedScale, 0.97, accuracy: 0.001)
    }

    // MARK: - Material backdrop blur

    func testMaterialKindTintAlphasMatchDocumentedTable() async {
        XCTAssertEqual(Material.ultraThin.retainedFallbackColor.alpha, 0.18, accuracy: 0.001)
        XCTAssertEqual(Material.thin.retainedFallbackColor.alpha, 0.28, accuracy: 0.001)
        XCTAssertEqual(Material.regular.retainedFallbackColor.alpha, 0.40, accuracy: 0.001)
        XCTAssertEqual(Material.thick.retainedFallbackColor.alpha, 0.58, accuracy: 0.001)
        XCTAssertEqual(Material.ultraThick.retainedFallbackColor.alpha, 0.72, accuracy: 0.001)
        XCTAssertEqual(Material.bar.retainedFallbackColor.alpha, 0.64, accuracy: 0.001)
    }

    func testMaterialKindBlurRadiiMatchDocumentedTable() async {
        XCTAssertEqual(Material.ultraThin.retainedBlurRadius, 8, accuracy: 0.001)
        XCTAssertEqual(Material.thin.retainedBlurRadius, 14, accuracy: 0.001)
        XCTAssertEqual(Material.regular.retainedBlurRadius, 22, accuracy: 0.001)
        XCTAssertEqual(Material.thick.retainedBlurRadius, 30, accuracy: 0.001)
        XCTAssertEqual(Material.ultraThick.retainedBlurRadius, 40, accuracy: 0.001)
        XCTAssertEqual(Material.bar.retainedBlurRadius, 18, accuracy: 0.001)
    }
}
