import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Guards the two things that made every screen read as one oversized
/// iPad build: a points API that silently meant something else below 8,
/// and semantic colours with no appearance dimension.
@MainActor
final class TypographyAndAppearanceTests: XCTestCase {

    // MARK: - Font.system(size:) is points, monotonically

    /// `resolvedNativeTextSize` used to be
    /// `size >= 8 ? size : max(12, size * 6 + 8)`, so `.system(size: 3)`
    /// rendered at 26px while `.system(size: 8)` rendered at 8px — the
    /// public points API was not monotonic in its own argument.
    func testNativeTextSizeIsMonotonicInPointSize() async {
        var previous = 0.0
        for points in stride(from: 1.0, through: 40.0, by: 0.5) {
            let resolved = Font.system(size: points).resolvedNativeTextSize
            XCTAssertGreaterThanOrEqual(
                resolved, previous,
                "A larger point size must never resolve to a smaller rendered size (at \(points)pt)")
            previous = resolved
        }
    }

    func testNativeTextSizeIsTheRequestedPointSize() async {
        for points in [1.5, 3.0, 7.9, 8.0, 13.0, 26.0] {
            XCTAssertEqual(
                Font.system(size: points).resolvedNativeTextSize, points, accuracy: 0.0001,
                "\(points)pt must render at \(points)pt")
        }
    }

    /// The 5x7 atlas scale conversion is the bitmap fallback's business and
    /// stays proportional to the point size in every range.
    func testBitmapFallbackScaleStaysProportionalToPoints() async {
        XCTAssertEqual(Font.system(size: 13).resolvedScale, 1.3, accuracy: 0.0001)
        XCTAssertEqual(Font.system(size: 26).resolvedScale, 2.6, accuracy: 0.0001)
        XCTAssertGreaterThan(
            Font.system(size: 13).resolvedScale, Font.system(size: 10).resolvedScale,
            "Bitmap scale must rise with point size across the whole range")
    }

    // MARK: - Leading is proportional

    /// A flat 2px at every size gave a 26pt title the same gap as a 10pt
    /// caption. macOS line height is a fraction of the point size.
    func testStandardLeadingIsProportionalToPointSize() async {
        let caption = Font.system(size: 10)
        let title = Font.system(size: 26)
        XCTAssertGreaterThan(
            title.resolvedLineSpacing, caption.resolvedLineSpacing * 2,
            "A 26pt title must lead substantially more than a 10pt caption")
    }

    /// The renderer lays out at `size + lineSpacing`; body must land on
    /// macOS's 16pt line box.
    func testBodyLineHeightMatchesMacOS() async {
        XCTAssertEqual(Font.body.size + Font.body.resolvedLineSpacing, 16, accuracy: 0.15)
    }

    func testLeadingNeverRoundsToNothing() async {
        XCTAssertGreaterThanOrEqual(Font.system(size: 1).resolvedLineSpacing, 1)
    }

    func testTightLeadsLessThanStandardLeadsLessThanLoose() async {
        let base = Font.system(size: 20)
        let tight = Font(size: 20, leading: .tight)
        let loose = Font(size: 20, leading: .loose)
        XCTAssertLessThan(tight.resolvedLineSpacing, base.resolvedLineSpacing)
        XCTAssertLessThan(base.resolvedLineSpacing, loose.resolvedLineSpacing)
    }

    // MARK: - Semantic colours carry an appearance

    /// `Color.primary` was literally `(1, 1, 1)` and
    /// `resolvedForVisualEnvironment` never took a colour scheme, so light
    /// mode was not unwired — it could not be expressed.
    func testPrimaryLabelFlipsWithTheAppearance() async {
        let dark = Color.primary.resolvedForVisualEnvironment(
            colorScheme: .dark, contrast: .standard, backgroundProminence: .standard)
        let light = Color.primary.resolvedForVisualEnvironment(
            colorScheme: .light, contrast: .standard, backgroundProminence: .standard)
        XCTAssertGreaterThan(dark.red, 0.5, "Dark appearance labels are near-white")
        XCTAssertLessThan(light.red, 0.5, "Light appearance labels are near-black")
    }

    func testSecondaryAndTertiaryStayBelowPrimaryInBothAppearances() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let primary = Color.primary.resolvedForVisualEnvironment(
                colorScheme: scheme, contrast: .standard, backgroundProminence: .standard)
            let secondary = Color.secondary.resolvedForVisualEnvironment(
                colorScheme: scheme, contrast: .standard, backgroundProminence: .standard)
            let tertiary = Color.tertiary.resolvedForVisualEnvironment(
                colorScheme: scheme, contrast: .standard, backgroundProminence: .standard)
            XCTAssertGreaterThan(primary.alpha, secondary.alpha, "\(scheme) primary outranks secondary")
            XCTAssertGreaterThan(secondary.alpha, tertiary.alpha, "\(scheme) secondary outranks tertiary")
        }
    }

    /// The semantic label colours and the control chrome palette must be
    /// the same colours, not two independent roundings.
    func testSemanticLabelsAndControlPaletteAgree() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let palette = ControlPalette.resolve(colorScheme: scheme)
            XCTAssertEqual(
                Color.primary.resolvedForVisualEnvironment(
                    colorScheme: scheme, contrast: .standard, backgroundProminence: .standard),
                palette.label)
            XCTAssertEqual(
                Color.secondary.resolvedForVisualEnvironment(
                    colorScheme: scheme, contrast: .standard, backgroundProminence: .standard),
                palette.secondaryLabel)
        }
    }

    /// A colour the app wrote itself is not a semantic role and must pass
    /// through untouched in both appearances.
    func testAppAuthoredColorsAreNotReinterpreted() async {
        let brand = Color(red: 0.2, green: 0.6, blue: 0.4, alpha: 1)
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            XCTAssertEqual(
                brand.resolvedForVisualEnvironment(
                    colorScheme: scheme, contrast: .standard, backgroundProminence: .standard),
                brand)
        }
        XCTAssertEqual(
            Color.accentColor.resolvedForVisualEnvironment(
                colorScheme: .light, contrast: .standard, backgroundProminence: .standard),
            Color.accentColor,
            "The accent is the one chromatic element and never desaturates")
    }

    func testIncreasedContrastLiftsSecondaryInBothAppearances() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let standard = Color.secondary.resolvedForVisualEnvironment(
                colorScheme: scheme, contrast: .standard, backgroundProminence: .standard)
            let increased = Color.secondary.resolvedForVisualEnvironment(
                colorScheme: scheme, contrast: .increased, backgroundProminence: .standard)
            XCTAssertGreaterThan(increased.alpha, standard.alpha, "\(scheme) high contrast lifts secondary")
        }
    }

    /// Content drawn over a filled selection stops being secondary.
    func testIncreasedBackgroundProminencePromotesSecondaryToPrimary() async {
        let promoted = Color.secondary.resolvedForVisualEnvironment(
            colorScheme: .dark, contrast: .standard, backgroundProminence: .increased)
        XCTAssertEqual(promoted, ControlPalette.darkStandard.label)
    }

    // MARK: - The chrome neutrals are achromatic

    /// The whole chrome ramp used to sit on a navy axis where blue was
    /// roughly twice red. macOS dark is hueless except for the accent.
    func testHierarchicalFallbackColorsAreAchromatic() async {
        let levels: [HierarchicalShapeStyle] = [.primary, .secondary, .tertiary, .quaternary, .quinary]
        for level in levels {
            let color = level.retainedFallbackColor
            XCTAssertEqual(color.red, color.green, accuracy: 0.001)
            XCTAssertEqual(color.green, color.blue, accuracy: 0.001)
        }
    }

    // MARK: - Uppercase tracking

    /// `.textCase(.uppercase)` sets capitals with sidebearings tuned for
    /// mixed case; without extra tracking they read as a solid block.
    func testUppercaseRunsGetPositiveTracking() async {
        let context = Self.buildContext()
        let plain = Text("Workspace").makeComponent(context: context).makeNode(runtime: RetainedViewRuntime())
        let caps = Text("Workspace")
            .textCase(.uppercase)
            .makeComponent(context: context)
            .makeNode(runtime: RetainedViewRuntime())
        XCTAssertNil(plain.textStyle.nativeLetterSpacing, "Mixed-case text keeps the face's own metrics")
        XCTAssertEqual(caps.textStyle.nativeLetterSpacing ?? 0, Font.body.size * 0.06, accuracy: 0.001)
    }

    /// An explicit `.tracking()` still wins over the uppercase default.
    func testExplicitTrackingOverridesTheUppercaseDefault() async {
        let node = Text("Workspace")
            .textCase(.uppercase)
            .tracking(3)
            .makeComponent(context: Self.buildContext())
            .makeNode(runtime: RetainedViewRuntime())
        XCTAssertEqual(node.textStyle.nativeLetterSpacing ?? 0, 3, accuracy: 0.001)
    }

    // MARK: - Label inherits

    /// `Label` hardcoded 17.6px semibold and applied it with `withFont`,
    /// so it *overrode* the ambient font instead of inheriting it, and it
    /// forced `lineLimit(1)`, which SwiftUI does not.
    func testLabelInheritsTheAmbientFont() async {
        let context = Self.buildContext().withFont(.system(size: 22))
        let node = Label("Render host", systemImage: "bolt")
            .makeComponent(context: context)
            .makeNode(runtime: RetainedViewRuntime())
        let title = Self.firstTextNode(in: node) { $0.text == "Render host" }
        XCTAssertNotNil(title)
        XCTAssertEqual(title?.textStyle.nativeFontSize ?? 0, 22, accuracy: 0.001)
    }

    func testLabelIsRegularWeightLikeAMacOSListRow() async {
        let node = Label("Render host", systemImage: "bolt")
            .makeComponent(context: Self.buildContext())
            .makeNode(runtime: RetainedViewRuntime())
        let title = Self.firstTextNode(in: node) { $0.text == "Render host" }
        XCTAssertEqual(title?.textStyle.weight, .regular)
    }

    func testLabelDoesNotForceASingleLine() async {
        let node = Label("Render host", systemImage: "bolt")
            .makeComponent(context: Self.buildContext())
            .makeNode(runtime: RetainedViewRuntime())
        let title = Self.firstTextNode(in: node)
        XCTAssertNotEqual(title?.textStyle.maximumNumberOfLines, 1, "SwiftUI's Label does not clamp to one line")
    }

    // MARK: - Segmented picker participates in the ramp

    /// The segment used to clamp its label to <= 13px, a workaround for an
    /// ambient body of 17 starving the 22pt track. A picker has to be able
    /// to take part in the app's type scale.
    func testSegmentedPickerLabelInheritsTheAmbientFont() async {
        let context = Self.buildContext().withFont(.system(size: 18))
        let node = Picker("Theme", selection: .constant(0)) {
            Text("System").tag(0)
            Text("Light").tag(1)
        }
        .pickerStyle(.segmented)
        .makeComponent(context: context)
        .makeNode(runtime: RetainedViewRuntime())
        let label = Self.firstTextNode(in: node) { $0.text == "System" }
        XCTAssertNotNil(label)
        XCTAssertEqual(label?.textStyle.nativeFontSize ?? 0, 18, accuracy: 0.001)
    }

    // MARK: - Helpers

    private static func buildContext() -> ViewBuildContext {
        ViewBuildContext(canvasSizeProvider: { Size(width: 800, height: 600) }, invalidateHandler: {})
    }

    private static func firstTextNode(
        in node: ViewNode,
        matching predicate: (ViewNode) -> Bool = { $0.text != nil }
    ) -> ViewNode? {
        if node.text != nil, predicate(node) {
            return node
        }
        for child in node.children {
            if let found = firstTextNode(in: child, matching: predicate) {
                return found
            }
        }
        return nil
    }
}
