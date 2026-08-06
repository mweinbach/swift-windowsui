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

    /// The `caption` role is 11, not 10: a caption is the smallest string in
    /// the app a reader is actually expected to read, and at 10pt in the
    /// third rung it was a texture. 10 survives as `caption2`, the axis-label
    /// role — a number you glance at beside a mark that already answered you.
    func testCaptionSizeMatchesSwiftUIDefault() async {
        XCTAssertEqual(Font.caption.size, 11, accuracy: 0.001)
        XCTAssertGreaterThan(Font.caption.size, Font.caption2.size)
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
        // One focus-ring number across both pinned sources. A 2pt halo
        // outside a 1px accent border: 4pt of ring around a 6pt corner
        // swallows the corner, so a focused control loses the shape that
        // identifies it at the moment you need to find it.
        XCTAssertEqual(chrome.focusRingWidth, 2, "Focus ring is a thin outline, not a bloom")
        XCTAssertEqual(chrome.focusRingWidth, SurfaceChrome.focusRingStrokeWidth)
    }

    func testElevatedButtonChromeMatchesMacOS() async {
        let chrome = SurfaceChrome.elevatedButton
        XCTAssertEqual(chrome.borderWidth, 1)
        XCTAssertEqual(chrome.focusRingWidth, 2)
        XCTAssertEqual(chrome.focusRingWidth, SurfaceChrome.focusRingStrokeWidth)
    }

    func testControlSurfaceSheenIsBigSurFlat() async {
        // A surface's travel is at the *edge of perception* — a couple of
        // levels of 255 — and that slight amount is the whole difference
        // between a surface and a rectangle of paint. 0.82 was an 18% drop
        // that made every control a styled div; 0.96 was still visible on a
        // card the size of a settings box. The system specifies -0.02.
        XCTAssertEqual(Controls.surfaceSheenFactor, 0.98, accuracy: 0.0001)
        // A groove is genuinely shaded rather than lit, so it travels
        // further than a surface — still near-flat.
        XCTAssertEqual(Controls.grooveSheenFactor, 0.95, accuracy: 0.0001)
        // The same step stated as a distance rather than a ratio, so a
        // translucent surface falls by what the *window* shows.
        XCTAssertEqual(Controls.surfaceSheenDrop, 0.02, accuracy: 0.0001)
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
        // `edge-highlight`: the top stop of every ring. A dark ring is
        // brightest at the top; a light ring withdraws at the top and closes
        // at the bottom, which is the identical lighting read the other way
        // round.
        XCTAssertEqual(ControlPalette.darkStandard.raisedSurfaceHighlight, ControlPalette.white(0.10))
        XCTAssertEqual(ControlPalette.lightStandard.raisedSurfaceHighlight, ControlPalette.white(0.75))
    }

    func testInsetListBodyMetricsMatchAnInsetNSTableView() async {
        XCTAssertEqual(MacOSControlMetrics.List.insetCornerRadius, 6, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.List.insetVerticalInset, 6, accuracy: 0.001)
    }

    /// Every button radius is a step of the scale: `sm` for the standard
    /// bezel *and* the segmented pill (they are the same shape at different
    /// sizes), `xs` for `.mini`, `md` for `.large`. The 4 that `.small` used
    /// to carry is not a member of the scale.
    func testPushButtonCornerRadiusIsARoundedRect() async {
        XCTAssertEqual(MacOSControlMetrics.Button.regularCornerRadius, MacOSControlMetrics.Radius.sm)
        XCTAssertEqual(MacOSControlMetrics.Button.smallCornerRadius, MacOSControlMetrics.Radius.sm)
        XCTAssertEqual(MacOSControlMetrics.Button.miniCornerRadius, MacOSControlMetrics.Radius.xs)
        XCTAssertEqual(MacOSControlMetrics.Button.largeCornerRadius, MacOSControlMetrics.Radius.md)
    }

    func testControlAnimationStyleDefaultsMatchMacOSBigSur() async {
        let style = ControlAnimationStyle.default
        XCTAssertEqual(style.focusDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(style.pressDuration, 0.14, accuracy: 0.001)
    }

    /// A macOS control's press feedback is a *fill* change with identical
    /// geometry: `NSButtonCell` highlights, `NSSegmentedControl` darkens the
    /// pressed segment, `NSSwitch` darkens its track. None of them shrinks.
    /// The 0.97 this table used to pin as a "Big Sur feel" was an iOS idiom
    /// that reached the gallery's pressed entries and read as intentional.
    ///
    /// The borderless styles are the exception that proves it: they have no
    /// bezel to move, so AppKit darkens their *contents* instead
    /// (`contentsCellMask`), which is `SurfacePalette.pressedContentOpacity`.
    func testPressedStateIsAFillChangeNotAShrink() async {
        XCTAssertEqual(ControlAnimationStyle.default.pressedScale, 1.0, accuracy: 0.0001)
        XCTAssertEqual(ControlAnimationStyle.tactilePressedScale, 0.97, accuracy: 0.001)

        // Every ramp with a bezel answers a press with its fill and leaves the
        // content alone.
        for palette in [ControlPalette.darkStandard, .lightStandard] {
            XCTAssertEqual(palette.borderedButtonPalette.pressedContentOpacity, 1.0, accuracy: 0.0001)
            XCTAssertEqual(palette.prominentPalette(tint: .accentColor).pressedContentOpacity, 1.0, accuracy: 0.0001)
            XCTAssertNotEqual(
                palette.borderedButtonPalette.pressed, palette.borderedButtonPalette.idle,
                "the pressed rung has to differ from idle — it is the whole affordance now")
        }

        // The borderless ramp is transparent in every state, so it is the one
        // that dims.
        XCTAssertEqual(ButtonSurfaceStyle.plain.palette.pressed, .clear)
        XCTAssertEqual(
            ButtonSurfaceStyle.plain.palette.pressedContentOpacity,
            ControlPalette.pressedContentOpacity,
            accuracy: 0.0001)
        XCTAssertLessThan(ControlPalette.pressedContentOpacity, 1.0)
    }

    /// The type roles. **The weight axis is the hierarchy tool, not size** —
    /// a 14/600 card title and the 13/400 body under it differ by one point
    /// and read as clearly different roles because weight *and* rung move.
    ///
    /// The two section-header sizes are one call site serving two roles: a
    /// settings section names a group you are about to read (a heading), a
    /// list group names rows you are already reading past (a label).
    func testTypeRolesArePinned() async {
        XCTAssertEqual(MacOSControlMetrics.Typography.controlLabelSize, 12, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Typography.cardTitleSize, 14, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Typography.eyebrowSize, 11, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Typography.sectionHeaderSize, 11, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Typography.formSectionHeaderSize, 15, accuracy: 0.001)
        XCTAssertGreaterThan(
            MacOSControlMetrics.Typography.formSectionHeaderSize,
            MacOSControlMetrics.Typography.sectionHeaderSize)
        XCTAssertEqual(MacOSControlMetrics.Typography.uppercaseTrackingRatio, 0.06, accuracy: 0.0001)
        XCTAssertEqual(MacOSControlMetrics.Typography.symbolBoxRatio, 1.25, accuracy: 0.0001)
    }

    /// The weight axis has three rungs — 400 / 500 / 600 — and 500 is one of
    /// them. It used to fold into 400, which deleted the whole difference
    /// between `body` (13/400) and `body-strong` (13/500): they are one point
    /// apart in size, so the weight is all there is. Every 500-weight role in
    /// the app rendered as its own resting state.
    func testTheWeightAxisCarriesFiveHundred() async {
        XCTAssertEqual(Font.Weight.regular.textWeight.gdiWeight, 400)
        XCTAssertEqual(Font.Weight.medium.textWeight.gdiWeight, 500)
        XCTAssertEqual(Font.Weight.semibold.textWeight.gdiWeight, 600)
        XCTAssertEqual(Font.Weight.bold.textWeight.gdiWeight, 700)
        // Nothing in the system is heavier than 600, so the roles that carry
        // hierarchy sit strictly between regular and bold.
        XCTAssertLessThan(
            Font.Weight.medium.textWeight.gdiWeight, Font.Weight.semibold.textWeight.gdiWeight)
    }

    // MARK: - Grouped form and group box

    func testGroupedFormMetricsMatchTheMacOSSettingsPane() async {
        // A 640pt column centred in a 1280 window leaves ~340pt of dead
        // space on each side and reads as a pane borrowed from another app.
        XCTAssertEqual(MacOSControlMetrics.Form.contentMaxWidth, 720, accuracy: 0.001)
        // Still a *centred* column with a margin: leading-anchoring it inside
        // the page margin is a decision the settings pane makes, not a chrome
        // default — moving it here would re-anchor every grouped Form.
        //
        // Interim: the design system's end state is 0 vertical box padding,
        // which is only correct once a row carries its own `rowMinHeight`.
        // Until then a zero-padded box sits its first row flush against its
        // own corner, so the box keeps one scale step.
        XCTAssertEqual(MacOSControlMetrics.Form.contentHorizontalMargin, 20, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.labelColumnGap, 12, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.sectionSpacing, 24, accuracy: 0.001)
        // 8 below against 24 above — the 3:1 ratio that keeps a header
        // attached to what is under it rather than floating between groups.
        XCTAssertEqual(MacOSControlMetrics.Form.headerSpacing, 8, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.headerLeadingInset, 0, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.rowSpacing, 12, accuracy: 0.001)
        // A row states its own height, so box padding would only double the
        // first and last gaps.
        XCTAssertEqual(MacOSControlMetrics.Form.boxVerticalPadding, 8, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.boxHorizontalPadding, 16, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.rowMinHeight, 36, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Form.descriptiveRowMinHeight, 52, accuracy: 0.001)
        for gap in [
            MacOSControlMetrics.Form.labelColumnGap,
            MacOSControlMetrics.Form.sectionSpacing,
            MacOSControlMetrics.Form.headerSpacing,
            MacOSControlMetrics.Form.rowSpacing,
            MacOSControlMetrics.Form.boxHorizontalPadding,
            MacOSControlMetrics.Form.boxVerticalPadding,
            MacOSControlMetrics.Form.contentHorizontalMargin,
        ] {
            XCTAssertTrue(
                MacOSControlMetrics.Spacing.scale.contains(gap), "a form gap is not a step of the 4/8 grid")
        }
    }

    /// The spacing scale is a 4/8 grid and nothing else is legal. Half a
    /// dozen near-miss values (6, 10, 14, 18, 26, 30) do not read as a
    /// rhythm; they read as the absence of one.
    func testSpacingScaleIsAFourEightGrid() async {
        XCTAssertEqual(MacOSControlMetrics.Spacing.scale, [4, 8, 12, 16, 20, 24, 32, 40, 48, 64])
        XCTAssertEqual(MacOSControlMetrics.Layout.defaultStackSpacing, MacOSControlMetrics.Spacing.s2)
        XCTAssertEqual(MacOSControlMetrics.Layout.labelIconSpacing, MacOSControlMetrics.Spacing.s2)
        XCTAssertEqual(MacOSControlMetrics.Layout.defaultPadding, MacOSControlMetrics.Spacing.s4)
    }

    /// **Nothing in the app exceeds 12.** The 16 / 20 / 22 / 24 / 26 / 30 the
    /// app used to carry is what made it read as bubbly: a 20pt radius on a
    /// 28pt row is a stadium, and a window full of stadiums is a consumer toy
    /// however correct its tones are.
    func testRadiusScaleTopsOutAtTwelve() async {
        XCTAssertEqual(MacOSControlMetrics.Radius.xs, 3, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Radius.sm, 6, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Radius.md, 8, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Radius.lg, 10, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Radius.xl, 12, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Radius.maximum, MacOSControlMetrics.Radius.xl, accuracy: 0.001)
        for radius in [
            MacOSControlMetrics.Button.regularCornerRadius,
            MacOSControlMetrics.Button.smallCornerRadius,
            MacOSControlMetrics.Button.largeCornerRadius,
            MacOSControlMetrics.GroupBox.cornerRadius,
            MacOSControlMetrics.List.insetCornerRadius,
            MacOSControlMetrics.Window.cornerRadius,
            MacOSControlMetrics.Window.sheetCornerRadius,
        ] {
            XCTAssertLessThanOrEqual(radius, MacOSControlMetrics.Radius.maximum, "a radius rounds past the scale")
        }
    }

    /// The elevation ramp. Structure is carried by the hairline; a shadow
    /// only ever says "this floats". The retired ramp offset **14** under a
    /// 12pt gutter, so every gutter in the window was filled with a shadow
    /// smear rather than page tone.
    func testElevationRampNeverOffsetsPastTwelve() async {
        for level in [Elevation.e0, Elevation.e1, Elevation.e2, Elevation.e3, Elevation.e4] {
            for scheme in [ColorScheme.dark, ColorScheme.light] {
                XCTAssertLessThanOrEqual(level.offsetY(for: scheme), 12, "a rung offsets past the ramp")
            }
        }
        XCTAssertEqual(Elevation.e0.dark.color, .clear)
        XCTAssertEqual(Elevation.e0.light.color, .clear)
        XCTAssertEqual(Elevation.e1.light.radius, 3, accuracy: 0.001)
        XCTAssertEqual(Elevation.e1.light.offsetY, 1, accuracy: 0.001)
        // `e4` is the one tinted shadow in the app, and it belongs to the
        // hero card alone; every other rung is neutral.
        XCTAssertNotEqual(Elevation.e4.dark.color.red, Elevation.e4.dark.color.green)
        for level in [Elevation.e1, Elevation.e2, Elevation.e3] {
            XCTAssertEqual(level.dark.color.red, level.dark.color.blue, accuracy: 0.001)
        }
    }

    /// The accent split: ink varies with the appearance behind it, an opaque
    /// fill does not.
    func testAccentIsOneAccentInTwoRoles() async {
        let dark = ControlPalette.darkStandard
        let light = ControlPalette.lightStandard
        XCTAssertEqual(dark.accentFill, light.accentFill, "an opaque fill has no appearance to vary with")
        XCTAssertEqual(dark.accentFill, Color.accentColor)
        XCTAssertNotEqual(dark.accentForeground, light.accentForeground, "ink always varies")
        XCTAssertEqual(light.accentForeground, light.accentFill, "the light ink and the fill are the same hex")
        // The tint an app hands chrome resolves to ink through the palette;
        // a tint the app chose itself passes through untouched.
        XCTAssertEqual(dark.accentInk(for: .accentColor), dark.accentForeground)
        let authored = Color(red: 0.42, green: 0.17, blue: 0.63)
        XCTAssertEqual(dark.accentInk(for: authored), authored)
        XCTAssertEqual(ControlPalette.focusRingAlpha, 0.45, accuracy: 0.0001)
    }

    /// **The appearance-conditional card rule.** In dark a card is
    /// `surface1` closed by a hairline and casts *nothing* — a shadow under a
    /// near-black card on a near-black page is invisible work, and at any
    /// alpha you can see it fills the gutter beside the card with a smear. In
    /// light a white card takes `e1`, a 3pt blur at y 1 that reads as a paper
    /// lift. One rule, resolved twice.
    func testGroupBoxIsARoundedRectWithAContactShadow() async {
        XCTAssertEqual(MacOSControlMetrics.GroupBox.cornerRadius, MacOSControlMetrics.Radius.lg, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.GroupBox.shadowOffsetY, Elevation.e1.light.offsetY, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.GroupBox.shadowSpread, Elevation.e1.light.radius, accuracy: 0.001)
        XCTAssertEqual(ControlPalette.lightStandard.groupedContainerShadow, Elevation.e1.light.color)
        XCTAssertEqual(ControlPalette.darkStandard.groupedContainerShadow, .clear)
    }

    func testOverlayScrollerMetricsMatchNSScroller() async {
        XCTAssertEqual(MacOSControlMetrics.Scroller.overlayThumbThickness, 6, accuracy: 0.001)
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
        // White on a dark app, ink on a light one, and **nearly invisible at
        // rest**: the 0.48 / 0.42 this used to draw made the scrollbar the
        // brightest object in whatever column it floated over, which is the
        // one thing a scrollbar must never be.
        XCTAssertEqual(ControlPalette.darkStandard.scrollerKnob, ControlPalette.white(0.22))
        XCTAssertEqual(ControlPalette.lightStandard.scrollerKnob, ControlPalette.ink(0.18))
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
        // backdrop in **both** appearances rather than a second copy of it.
        // The rungs differ because the pages do: `surface3` is a lift on
        // near-black and a recess on near-white, and resolving both from it
        // opened a light-mode menu darker than the window under it.
        for palette in [ControlPalette.darkStandard, ControlPalette.lightStandard] {
            XCTAssertGreaterThan(
                palette.elevatedSurface.red, palette.windowBackground.red,
                "\(palette.colorScheme): a floating panel is lighter than the window")
        }
        // A floating panel is closed with the *structural* hairline: it has
        // no page around it to borrow an edge from.
        XCTAssertEqual(
            ControlPalette.darkStandard.elevatedSurfaceBorder, ControlPalette.darkStandard.controlBorderStrong)
        XCTAssertEqual(
            ControlPalette.lightStandard.elevatedSurfaceBorder, ControlPalette.lightStandard.controlBorderStrong)
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

    /// **A `.bar` lands on the chrome rung, and it is still a material.**
    ///
    /// The tint used to be `base` in dark, and a translucent film of the page
    /// tone over the page tone is the page tone at every alpha: the toolbar
    /// band and the selector bar above it sampled byte-identical to the window
    /// backdrop, so the top 88pt of every dark screen was one flat black field
    /// with a hairline in it. The fix is not an opaque band — that throws the
    /// material away — it is solving the tint so the *composite* is the design
    /// value: `a·tint + (1 − a)·base == chromeBand`.
    ///
    /// Both halves matter, so both are asserted: the band lands on the rung,
    /// and 36% of whatever is scrolled under it still comes through.
    func testBarMaterialCompositesOntoTheChromeRung() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let tint = Material.bar.retainedTint(for: scheme)
            let backdrop = DesignTokens.base.resolve(scheme)
            let alpha = tint.alpha

            XCTAssertEqual(
                alpha, Material.bar.retainedFallbackColor.alpha, accuracy: 0.001,
                "\(scheme): the published alpha is the pinned part and does not move")
            XCTAssertLessThan(alpha, 1, "\(scheme): a bar is translucent, not an opaque plate")

            func composite(_ tintChannel: Float, _ backdropChannel: Float) -> Float {
                alpha * tintChannel + (1 - alpha) * backdropChannel
            }
            let band = Color(
                red: composite(tint.red, backdrop.red),
                green: composite(tint.green, backdrop.green),
                blue: composite(tint.blue, backdrop.blue),
                alpha: 1)
            let chrome = DesignTokens.chromeBand.resolve(scheme)
            XCTAssertEqual(band.red, chrome.red, accuracy: 0.002, "\(scheme) band red")
            XCTAssertEqual(band.green, chrome.green, accuracy: 0.002, "\(scheme) band green")
            XCTAssertEqual(band.blue, chrome.blue, accuracy: 0.002, "\(scheme) band blue")

            // …and the band is a band: a full ramp rung off the columns and
            // gutters it runs across, rather than the 0/255 it used to be.
            XCTAssertGreaterThanOrEqual(
                Int((abs(Double(band.green) - Double(backdrop.green)) * 255).rounded()),
                DesignTokens.minimumRampStep,
                "\(scheme): the chrome band is invisible against the window backdrop")
        }
    }

    /// The selector bar and the toolbar band are **one chrome unit**: the
    /// opaque bar the runtime paints and the material the app paints resolve
    /// to the same tone, so the two stacked bands read as one region closed by
    /// one hairline rather than as two slabs.
    func testSelectorBarAndBarMaterialAgreeOnTheChromeTone() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let palette = ControlPalette.resolve(colorScheme: scheme)
            XCTAssertEqual(
                palette.chromeBand, DesignTokens.chromeBand.resolve(scheme),
                "\(scheme): the role resolves its own token")
            let tint = Material.bar.retainedTint(for: scheme)
            let backdrop = DesignTokens.base.resolve(scheme)
            let bandGreen = tint.alpha * tint.green + (1 - tint.alpha) * backdrop.green
            XCTAssertEqual(
                bandGreen, palette.chromeBand.green, accuracy: 0.002,
                "\(scheme): the material lands where the opaque bar is painted")
        }
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

    // MARK: - Background rungs

    private func relativeLuminance(of color: Color) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(Double(color.red)) + 0.7152 * channel(Double(color.green))
            + 0.0722 * channel(Double(color.blue))
    }

    /// WCAG contrast of `text` drawn at its own alpha over an *opaque* fill.
    private func contrastRatio(text: Color, over fill: Color) -> Double {
        let alpha = Double(text.alpha)
        let composited = Color(
            red: Float(alpha * Double(text.red) + (1 - alpha) * Double(fill.red)),
            green: Float(alpha * Double(text.green) + (1 - alpha) * Double(fill.green)),
            blue: Float(alpha * Double(text.blue) + (1 - alpha) * Double(fill.blue)),
            alpha: 1)
        let a = relativeLuminance(of: composited)
        let b = relativeLuminance(of: fill)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// `.background(.quaternary)` is a *bar* — the scrim that closes a list
    /// with an inspector or status strip.
    ///
    /// **A bar is never brighter than the list it closes in dark, or darker
    /// than it in light.** Drawn as a wash the rung fails that in whichever
    /// appearance it is not tuned for: the light black wash landed the bar at
    /// #D5D5D5 on a #ECECEC window — below the page it closed, which no
    /// bottom bar is — and once the dark rung moved to 0.30 for legibility
    /// the same maths lifted a dark footer well above the table over it,
    /// which reads as a second window pinned to the bottom.
    ///
    /// It is the page tone in **both** appearances now, with the hairline
    /// above it carrying the edge. The *label* resolution of the rung is
    /// untouched.
    func testQuaternaryBackgroundIsABarNotAShadeInLight() async {
        let lightBar = Color.quaternary.resolvedForBackgroundVisualEnvironment(
            colorScheme: .light, contrast: .standard, backgroundProminence: .standard)
        XCTAssertEqual(
            lightBar, ControlPalette.lightStandard.windowBackground,
            "a light quaternary background sits at the window tone, never below it")
        XCTAssertGreaterThanOrEqual(
            contrastRatio(text: ControlPalette.lightStandard.secondaryLabel, over: lightBar), 4.5,
            "secondary strings on the light bar clear WCAG AA")

        // Dark follows the same rule, which is what makes it one rule.
        let darkBar = Color.quaternary.resolvedForBackgroundVisualEnvironment(
            colorScheme: .dark, contrast: .standard, backgroundProminence: .standard)
        XCTAssertEqual(darkBar, ControlPalette.darkStandard.windowBackground)
        XCTAssertGreaterThanOrEqual(
            contrastRatio(text: ControlPalette.darkStandard.secondaryLabel, over: darkBar), 4.5,
            "secondary strings on the dark bar clear WCAG AA")
        // …and the bar is never brighter than the content it closes.
        XCTAssertLessThanOrEqual(
            darkBar.red, ControlPalette.darkStandard.controlBackground.red,
            "a dark bar does not outshine the list above it")

        // The label rung itself is not what moved: quaternary *text* keeps
        // AppKit's published alpha in both appearances.
        XCTAssertEqual(
            Color.quaternary.resolvedForVisualEnvironment(
                colorScheme: .light, contrast: .standard, backgroundProminence: .standard),
            ControlPalette.lightStandard.quaternaryLabel)
        XCTAssertEqual(
            Color.quaternary.resolvedForVisualEnvironment(
                colorScheme: .dark, contrast: .standard, backgroundProminence: .standard),
            ControlPalette.darkStandard.quaternaryLabel)
    }

    /// The accent is the design system's own `#5B4DE0`, not the OS blue.
    /// `#007AFF` is the right answer for an app cloning macOS and the wrong
    /// one for an app with a signature: it arrived in every render as a
    /// fourth unrelated hue beside the module tints.
    func testAccentColorIsTheDesignSystemAccentFill() async {
        assertColor(.accentColor, red: 91 / 255, green: 77 / 255, blue: 224 / 255, name: "accentColor")
        XCTAssertNotEqual(Color.accentColor, Color.blue, "the accent is not the OS blue any more")
        XCTAssertEqual(
            Color.accentColor, ViewBuildContext.defaultTint,
            "ViewBuildContext.defaultTint should track Color.accentColor")
        XCTAssertEqual(Color.accentColor, ControlPalette.darkStandard.accentFill)
        XCTAssertEqual(Color.accentColor, ControlPalette.lightStandard.accentFill)
    }
}
