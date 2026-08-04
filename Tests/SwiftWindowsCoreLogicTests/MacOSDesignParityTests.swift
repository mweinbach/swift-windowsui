import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Pins the macOS-equivalent design constants documented in
/// `docs/MacOSDesignParity.md`. Each test corresponds to a row in that
/// doc; changing a constant without updating the doc fails this suite.
@MainActor
final class MacOSDesignParityTests: XCTestCase {

    // MARK: - Font.system text styles
    //
    // The *macOS* ramp (AppKit `NSFont.preferredFont(forTextStyle:)`), not
    // the iOS Dynamic Type table at `.large`. These used to assert body 17
    // / largeTitle 34, which is verbatim iOS, under the name "macOS
    // parity" — so the guardrail was actively locking the wrong ramp in.

    func testLargeTitleSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.largeTitle.size, 26, accuracy: 0.001)
    }

    func testTitleSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.title.size, 22, accuracy: 0.001)
    }

    func testTitle2SizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.title2.size, 17, accuracy: 0.001)
    }

    func testTitle3SizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.title3.size, 15, accuracy: 0.001)
    }

    func testHeadlineSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.headline.size, 13, accuracy: 0.001)
    }

    func testHeadlineUsesSemiboldWeightLikeSwiftUI() async {
        XCTAssertEqual(Font.headline.weight, .semibold)
    }

    func testSubheadlineSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.subheadline.size, 11, accuracy: 0.001)
    }

    func testBodySizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.body.size, 13, accuracy: 0.001)
    }

    func testCalloutSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.callout.size, 12, accuracy: 0.001)
    }

    func testFootnoteSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.footnote.size, 10, accuracy: 0.001)
    }

    func testCaptionSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.caption.size, 10, accuracy: 0.001)
    }

    func testCaption2SizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.caption2.size, 10, accuracy: 0.001)
    }

    /// The ramp and the control geometry are pinned by the same module.
    /// They used to live in two places — literals in `Core.swift` and a
    /// prose table — which is how a 17pt body ended up specified alongside
    /// a 21pt text field.
    func testTypeRampReadsFromTheSameModuleAsControlGeometry() async {
        XCTAssertEqual(Font.body.size, MacOSControlMetrics.Typography.bodySize, accuracy: 0.001)
        XCTAssertEqual(Font.headline.size, MacOSControlMetrics.Typography.headlineSize, accuracy: 0.001)
        XCTAssertEqual(Font.largeTitle.size, MacOSControlMetrics.Typography.largeTitleSize, accuracy: 0.001)
        XCTAssertEqual(Font.caption.size, MacOSControlMetrics.Typography.captionSize, accuracy: 0.001)
    }

    /// A body label has to fit the box the same module specifies for it.
    func testBodyLineBoxFitsTheStandardTextFieldAndListRow() async {
        let lineHeight = Font.body.size + Font.body.resolvedLineSpacing
        XCTAssertLessThanOrEqual(
            lineHeight, MacOSControlMetrics.TextField.regularHeight,
            "A body label must fit inside a standard text field")
        XCTAssertLessThanOrEqual(
            lineHeight, MacOSControlMetrics.List.plainRowHeight,
            "A body label must fit inside a plain list row")
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
        // One focus-ring number across both pinned sources: this used to say
        // 2 while `MacOSControlMetrics.FocusRing.strokeWidth` said 4, with
        // both documented as "the" macOS value.
        XCTAssertEqual(chrome.focusRingWidth, 4, "Focus ring matches macOS stroke width")
        XCTAssertEqual(chrome.focusRingWidth, SurfaceChrome.focusRingStrokeWidth)
    }

    func testElevatedButtonChromeMatchesMacOS() async {
        let chrome = SurfaceChrome.elevatedButton
        XCTAssertEqual(chrome.borderWidth, 1)
        XCTAssertEqual(chrome.focusRingWidth, 4)
        XCTAssertEqual(chrome.focusRingWidth, SurfaceChrome.focusRingStrokeWidth)
    }

    func testControlSurfaceSheenIsBigSurFlat() async {
        // Apple retired the glossy bevel with Yosemite; the 0.82 end stop
        // this used to carry is an 18% luminance drop on every control.
        XCTAssertEqual(Controls.surfaceSheenFactor, 0.96, accuracy: 0.0001)
        XCTAssertEqual(Controls.grooveSheenFactor, 0.90, accuracy: 0.0001)
    }

    func testPushButtonCornerRadiusIsARoundedRect() async {
        XCTAssertEqual(MacOSControlMetrics.Button.regularCornerRadius, 6)
        XCTAssertEqual(MacOSControlMetrics.Button.smallCornerRadius, 4)
        XCTAssertEqual(MacOSControlMetrics.Button.largeCornerRadius, 8)
    }

    func testControlAnimationStyleDefaultsMatchMacOSBigSur() async {
        let style = ControlAnimationStyle.default
        XCTAssertEqual(style.focusDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(style.pressDuration, 0.14, accuracy: 0.001)
        XCTAssertEqual(style.activationDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(ControlAnimationStyle.pressedScale, 0.97, accuracy: 0.001)
    }

    // MARK: - Grouped form and group box

    func testGroupedFormMetricsMatchTheMacOSSettingsPane() async {
        XCTAssertEqual(MacOSControlMetrics.Form.contentMaxWidth, 640, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.contentHorizontalMargin, 20, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.labelColumnGap, 8, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.sectionSpacing, 20, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.headerSpacing, 6, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.headerLeadingInset, 6, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.rowSpacing, 10, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.boxVerticalPadding, 12, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.boxHorizontalPadding, 16, accuracy: 0.001)
        // The content column carries ~600pt boxes, which is the low end of
        // macOS's 600–715pt settings column.
        XCTAssertEqual(
            MacOSControlMetrics.Form.contentMaxWidth - 2 * MacOSControlMetrics.Form.contentHorizontalMargin,
            600,
            accuracy: 0.001
        )
    }

    func testGroupBoxIsARoundedRectWithAContactShadow() async {
        XCTAssertEqual(MacOSControlMetrics.GroupBox.cornerRadius, 10, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.GroupBox.shadowOffsetY, 2, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.GroupBox.shadowSpread, 3, accuracy: 0.001)
        XCTAssertEqual(ControlPalette.lightStandard.groupedContainerShadow, ControlPalette.black(0.04))
        XCTAssertEqual(ControlPalette.darkStandard.groupedContainerShadow, ControlPalette.black(0.22))
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

    // MARK: - System colors

    private func assertColor(
        _ color: Color, red: Float, green: Float, blue: Float,
        accuracy: Float = 0.005, name: String, file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(color.red, red, accuracy: accuracy, "\(name).red", file: file, line: line)
        XCTAssertEqual(
            color.green, green, accuracy: accuracy, "\(name).green", file: file, line: line)
        XCTAssertEqual(color.blue, blue, accuracy: accuracy, "\(name).blue", file: file, line: line)
        XCTAssertEqual(color.alpha, 1.0, accuracy: 0.001, "\(name).alpha", file: file, line: line)
    }

    func testSystemRedMatchesAppleHIG() async {
        assertColor(.red, red: 1.0, green: 0.231, blue: 0.188, name: "red")
    }

    func testSystemOrangeMatchesAppleHIG() async {
        assertColor(.orange, red: 1.0, green: 0.584, blue: 0.0, name: "orange")
    }

    func testSystemYellowMatchesAppleHIG() async {
        assertColor(.yellow, red: 1.0, green: 0.8, blue: 0.0, name: "yellow")
    }

    func testSystemGreenMatchesAppleHIG() async {
        assertColor(.green, red: 0.204, green: 0.78, blue: 0.349, name: "green")
    }

    func testSystemMintMatchesAppleHIG() async {
        assertColor(.mint, red: 0.0, green: 0.78, blue: 0.745, name: "mint")
    }

    func testSystemTealMatchesAppleHIG() async {
        assertColor(.teal, red: 0.188, green: 0.69, blue: 0.78, name: "teal")
    }

    func testSystemCyanMatchesAppleHIG() async {
        assertColor(.cyan, red: 0.196, green: 0.678, blue: 0.902, name: "cyan")
    }

    func testSystemBlueMatchesAppleHIG() async {
        assertColor(.blue, red: 0.0, green: 0.478, blue: 1.0, name: "blue")
    }

    func testSystemIndigoMatchesAppleHIG() async {
        assertColor(.indigo, red: 0.345, green: 0.337, blue: 0.839, name: "indigo")
    }

    func testSystemPurpleMatchesAppleHIG() async {
        assertColor(.purple, red: 0.686, green: 0.322, blue: 0.871, name: "purple")
    }

    func testSystemPinkMatchesAppleHIG() async {
        assertColor(.pink, red: 1.0, green: 0.176, blue: 0.333, name: "pink")
    }

    func testSystemBrownMatchesAppleHIG() async {
        assertColor(.brown, red: 0.635, green: 0.518, blue: 0.369, name: "brown")
    }

    func testSystemGrayMatchesAppleHIG() async {
        assertColor(.gray, red: 0.557, green: 0.557, blue: 0.576, name: "gray")
    }

    func testAccentColorMatchesMacOSDefaultControlAccentBlue() async {
        // macOS controlAccentColor's "Blue" (default) is #007AFF — the
        // same as Color.blue. WinSwiftUI's defaultTint must agree.
        XCTAssertEqual(
            Color.accentColor, Color.blue,
            "Color.accentColor should equal Color.blue (#007AFF) by default")
        XCTAssertEqual(
            Color.accentColor, ViewBuildContext.defaultTint,
            "ViewBuildContext.defaultTint should track Color.accentColor")
    }
}
