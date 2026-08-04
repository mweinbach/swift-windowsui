import SwiftWindowsCore
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
        // The same step stated as a distance: macOS's bezels travel about
        // the same absolute amount in both appearances (#FFFFFF → #F5F5F5
        // light, #545456 → #48484A dark).
        XCTAssertEqual(Controls.surfaceSheenDrop, 0.04, accuracy: 0.0001)
        XCTAssertEqual(Controls.surfaceSheenDrop, 1 - Controls.surfaceSheenFactor, accuracy: 0.0001)
        // …capped relative to the surface, so a dim control does not lose its
        // bottom edge to its own sheen. macOS's dark push bezel travels ~14%.
        XCTAssertEqual(Controls.surfaceSheenRelativeCeiling, 0.16, accuracy: 0.0001)
        XCTAssertEqual(Controls.borderSheenFadeFactor, 0.55, accuracy: 0.0001)
    }

    func testGroupedContainerMaterialIsBarelyThereAndDownward() async {
        for palette in [ControlPalette.darkStandard, .lightStandard] {
            guard case .linear(let fill) = palette.raisedSurfaceFill else {
                return XCTFail("a panel material is a linear gradient")
            }
            XCTAssertEqual(fill.axis, .vertical, "a panel is lit from above")
            XCTAssertEqual(fill.startColor, palette.raisedSurface)
            let travel = Controls.compositeValue(fill.startColor) - Controls.compositeValue(fill.endColor)
            XCTAssertGreaterThan(travel, 0.005)
            XCTAssertLessThanOrEqual(travel, Controls.surfaceSheenDrop + 0.0001)

            guard case .linear(let ring) = palette.raisedSurfaceRing else {
                return XCTFail("a panel ring is a linear gradient")
            }
            XCTAssertEqual(ring.startColor, palette.raisedSurfaceHighlight)
            XCTAssertEqual(ring.endColor, palette.separator)
        }
        XCTAssertEqual(ControlPalette.darkStandard.raisedSurfaceHighlight, ControlPalette.white(0.16))
        XCTAssertEqual(ControlPalette.lightStandard.raisedSurfaceHighlight, ControlPalette.white(0.55))
    }

    func testInsetListBodyMetricsMatchAnInsetNSTableView() async {
        XCTAssertEqual(MacOSControlMetrics.List.insetCornerRadius, 6, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.List.insetVerticalInset, 6, accuracy: 0.001)
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

    func testOverlayScrollerMetricsMatchNSScroller() async {
        XCTAssertEqual(MacOSControlMetrics.Scroller.overlayThumbThickness, 7, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Scroller.overlayInset, 4, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Scroller.minimumThumbLength, 24, accuracy: 0.001)
        // The stock ScrollView chrome is the pinned metric, not a number of
        // its own: a 5pt bar at a 6pt inset was a web scrollbar's geometry.
        XCTAssertEqual(
            ScrollViewStyle.default.indicatorThickness,
            MacOSControlMetrics.Scroller.overlayThumbThickness,
            accuracy: 0.001
        )
    }

    func testOverlayScrollerKnobIsANeutralPillInBothAppearances() async {
        // White on a dark app, black on a light one. The retained default was
        // a blue-tinted near-white in both, which light mode could not show.
        XCTAssertEqual(ControlPalette.darkStandard.scrollerKnob, ControlPalette.white(0.48))
        XCTAssertEqual(ControlPalette.lightStandard.scrollerKnob, ControlPalette.black(0.42))
        XCTAssertGreaterThan(
            ControlPalette.darkStandard.scrollerKnobHovered.alpha,
            ControlPalette.darkStandard.scrollerKnob.alpha
        )
        XCTAssertGreaterThan(
            ControlPalette.darkStandard.scrollerKnobActive.alpha,
            ControlPalette.darkStandard.scrollerKnobHovered.alpha
        )
    }

    func testFloatingPanelsSitOnAnAppearanceResolvedSurface() async {
        // A menu, a popover, a sheet, an alert and a context menu all share
        // one elevation. Every one of them used to be a dark literal, so a
        // light-mode app opened a near-black panel with near-black text.
        XCTAssertGreaterThan(ControlPalette.lightStandard.elevatedSurface.red, 0.9)
        XCTAssertLessThan(ControlPalette.darkStandard.elevatedSurface.red, 0.3)
        // Elevated is *above* the window, so it is lighter than the window
        // backdrop in dark mode rather than a second copy of it.
        XCTAssertGreaterThan(
            ControlPalette.darkStandard.elevatedSurface.red,
            ControlPalette.darkStandard.windowBackground.red
        )
        // The closing hairline follows the appearance too.
        XCTAssertEqual(ControlPalette.darkStandard.elevatedSurfaceBorder, ControlPalette.white(0.16))
        XCTAssertEqual(ControlPalette.lightStandard.elevatedSurfaceBorder, ControlPalette.black(0.14))
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

    /// The statics are the *light* rung of the pair table, so a colour cannot
    /// be given a dark twin while its light value quietly drifts away from the
    /// constant every existing assertion reads.
    func testSystemColorStaticsAreTheLightRungOfTheirPair() async {
        let pairedStatics: [(String, Color, SystemColorPalette.Pair)] = [
            ("red", .red, SystemColorPalette.red),
            ("orange", .orange, SystemColorPalette.orange),
            ("yellow", .yellow, SystemColorPalette.yellow),
            ("green", .green, SystemColorPalette.green),
            ("mint", .mint, SystemColorPalette.mint),
            ("teal", .teal, SystemColorPalette.teal),
            ("cyan", .cyan, SystemColorPalette.cyan),
            ("blue", .blue, SystemColorPalette.blue),
            ("indigo", .indigo, SystemColorPalette.indigo),
            ("purple", .purple, SystemColorPalette.purple),
            ("pink", .pink, SystemColorPalette.pink),
            ("brown", .brown, SystemColorPalette.brown),
            ("gray", .gray, SystemColorPalette.gray),
        ]
        XCTAssertEqual(
            pairedStatics.count, SystemColorPalette.pairs.count,
            "Every pair in the table has a matching static")
        for (name, value, pair) in pairedStatics {
            XCTAssertEqual(value, pair.light, "Color.\(name) is the pair's light value")
            XCTAssertNotEqual(
                pair.light, pair.dark,
                "\(name) publishes two different sRGB values, one per appearance")
            XCTAssertEqual(
                SystemColorPalette.darkVariant(of: value), pair.dark,
                "\(name) resolves to its dark twin")
        }
    }

    func testSystemRedMatchesAppleHIG() async {
        assertColor(.red, red: 1.0, green: 0.231, blue: 0.188, name: "red")
        assertColor(SystemColorPalette.red.dark, red: 1.0, green: 0.271, blue: 0.227, name: "red·dark")
    }

    func testSystemOrangeMatchesAppleHIG() async {
        assertColor(.orange, red: 1.0, green: 0.584, blue: 0.0, name: "orange")
        assertColor(
            SystemColorPalette.orange.dark, red: 1.0, green: 0.624, blue: 0.039, name: "orange·dark")
    }

    func testSystemYellowMatchesAppleHIG() async {
        assertColor(.yellow, red: 1.0, green: 0.8, blue: 0.0, name: "yellow")
        assertColor(
            SystemColorPalette.yellow.dark, red: 1.0, green: 0.839, blue: 0.039, name: "yellow·dark")
    }

    func testSystemGreenMatchesAppleHIG() async {
        assertColor(.green, red: 0.204, green: 0.78, blue: 0.349, name: "green")
        assertColor(
            SystemColorPalette.green.dark, red: 0.188, green: 0.82, blue: 0.345, name: "green·dark")
    }

    func testSystemMintMatchesAppleHIG() async {
        assertColor(.mint, red: 0.0, green: 0.78, blue: 0.745, name: "mint")
        assertColor(
            SystemColorPalette.mint.dark, red: 0.4, green: 0.831, blue: 0.812, name: "mint·dark")
    }

    func testSystemTealMatchesAppleHIG() async {
        assertColor(.teal, red: 0.188, green: 0.69, blue: 0.78, name: "teal")
        assertColor(
            SystemColorPalette.teal.dark, red: 0.251, green: 0.784, blue: 0.878, name: "teal·dark")
    }

    func testSystemCyanMatchesAppleHIG() async {
        assertColor(.cyan, red: 0.196, green: 0.678, blue: 0.902, name: "cyan")
        assertColor(
            SystemColorPalette.cyan.dark, red: 0.392, green: 0.824, blue: 1.0, name: "cyan·dark")
    }

    func testSystemBlueMatchesAppleHIG() async {
        assertColor(.blue, red: 0.0, green: 0.478, blue: 1.0, name: "blue")
        assertColor(
            SystemColorPalette.blue.dark, red: 0.039, green: 0.518, blue: 1.0, name: "blue·dark")
    }

    func testSystemIndigoMatchesAppleHIG() async {
        assertColor(.indigo, red: 0.345, green: 0.337, blue: 0.839, name: "indigo")
        assertColor(
            SystemColorPalette.indigo.dark, red: 0.369, green: 0.361, blue: 0.902, name: "indigo·dark")
    }

    func testSystemPurpleMatchesAppleHIG() async {
        assertColor(.purple, red: 0.686, green: 0.322, blue: 0.871, name: "purple")
        assertColor(
            SystemColorPalette.purple.dark, red: 0.749, green: 0.353, blue: 0.949, name: "purple·dark")
    }

    func testSystemPinkMatchesAppleHIG() async {
        assertColor(.pink, red: 1.0, green: 0.176, blue: 0.333, name: "pink")
        assertColor(
            SystemColorPalette.pink.dark, red: 1.0, green: 0.216, blue: 0.373, name: "pink·dark")
    }

    func testSystemBrownMatchesAppleHIG() async {
        assertColor(.brown, red: 0.635, green: 0.518, blue: 0.369, name: "brown")
        assertColor(
            SystemColorPalette.brown.dark, red: 0.675, green: 0.557, blue: 0.408, name: "brown·dark")
    }

    func testSystemGrayMatchesAppleHIG() async {
        assertColor(.gray, red: 0.557, green: 0.557, blue: 0.576, name: "gray")
        assertColor(
            SystemColorPalette.gray.dark, red: 0.596, green: 0.596, blue: 0.616, name: "gray·dark")
    }

    /// The table is only worth having if the resolver reads it. A dark window
    /// used to paint `Color.orange` at the light `#FF9500`, which is the one
    /// value in the pair that is *not* meant for a dark background.
    func testSystemColorsResolveByAppearance() async {
        let lightOrange = Color.orange.resolvedForVisualEnvironment(
            colorScheme: .light, contrast: .standard, backgroundProminence: .standard)
        let darkOrange = Color.orange.resolvedForVisualEnvironment(
            colorScheme: .dark, contrast: .standard, backgroundProminence: .standard)
        XCTAssertEqual(lightOrange, Color.orange, "The static already is the light value")
        XCTAssertEqual(darkOrange, SystemColorPalette.orange.dark)

        // Alpha is the caller's, not the table's: a faded system colour stays
        // faded through the swap.
        let faded = Color.orange.opacity(0.4).resolvedForVisualEnvironment(
            colorScheme: .dark, contrast: .standard, backgroundProminence: .standard)
        XCTAssertEqual(faded.red, SystemColorPalette.orange.dark.red, accuracy: 0.001)
        XCTAssertEqual(faded.green, SystemColorPalette.orange.dark.green, accuracy: 0.001)
        XCTAssertEqual(faded.alpha, 0.4, accuracy: 0.001)

        // A colour the app mixed itself is nobody's system colour and is
        // returned untouched in either appearance.
        let authored = Color(red: 0.42, green: 0.17, blue: 0.63)
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertEqual(
                authored.resolvedForVisualEnvironment(
                    colorScheme: scheme, contrast: .standard, backgroundProminence: .standard),
                authored, "\(scheme): an authored literal is not a system colour")
        }
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
