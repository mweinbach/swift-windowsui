import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// Chrome fidelity against macOS Big Sur+ control design.
///
/// Every assertion here failed before the FIDELITY-CHROME pass: control
/// chrome could not read `colorScheme` at all, buttons defaulted to a 16pt
/// radius that a 22–30pt control clamps into a capsule, accent surfaces sat
/// at 84% alpha under a tinted glow, the destructive style cast a
/// card-scale shadow 16pt below a 30pt button, disabled controls dimmed
/// only their fill, and the retained list model had no way to express a
/// row separator.
@MainActor
private func buildNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600),
    colorScheme: ColorScheme = .dark
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
        .withEnvironmentValue(\.colorScheme, colorScheme)
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func flatten(_ node: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = [node]
    for child in node.children {
        result.append(contentsOf: flatten(child))
    }
    return result
}

final class ControlAppearanceChromeTests: XCTestCase {

    // MARK: - Finding 1: chrome can read the appearance

    func testViewBuildContextExposesColorScheme() async {
        await MainActor.run {
            let context = ViewBuildContext(canvasSizeProvider: { Size(width: 400, height: 400) }, invalidateHandler: {})
            XCTAssertEqual(
                context.colorScheme, context.environmentValues.colorScheme,
                "EnvironmentValues.colorScheme reaches builders")
            XCTAssertEqual(context.withEnvironmentValue(\.colorScheme, .dark).colorScheme, .dark)
            XCTAssertEqual(context.withEnvironmentValue(\.colorScheme, .light).colorScheme, .light)
            XCTAssertEqual(
                context.withEnvironmentValue(\.colorScheme, .light).controlPalette.colorScheme, .light,
                "and the palette follows it")
        }
    }

    func testControlPaletteFollowsColorScheme() async {
        let dark = ControlPalette.resolve(colorScheme: .dark)
        let light = ControlPalette.resolve(colorScheme: .light)
        XCTAssertTrue(dark.isDark)
        XCTAssertFalse(light.isDark)
        XCTAssertNotEqual(dark.controlBackground, light.controlBackground)
        XCTAssertNotEqual(dark.label, light.label)
        XCTAssertNotEqual(dark.separator, light.separator)
    }

    /// The neutrals are achromatic **within a hair** — at most an 8/255 cool
    /// cast between red and blue, which is enough that a near-black page
    /// reads as ink rather than as brown and far short of the blue-cast navy
    /// (`(0.18, 0.23, 0.31)` fills under `(0.96, 0.98, 1.0)` borders) this
    /// stack started from. That was the single clearest "this is a themed web
    /// app" signal, and the bound below is what keeps it from coming back one
    /// tuned literal at a time.
    func testNeutralRolesAreAchromatic() async {
        let bound: Float = 8.0 / 255
        for palette in [ControlPalette.darkStandard, ControlPalette.lightStandard] {
            for (name, color) in [
                ("base", palette.base),
                ("surface0", palette.surface0),
                ("surface1", palette.surface1),
                ("surface2", palette.surface2),
                ("surface3", palette.surface3),
                ("controlSurface", palette.controlSurface),
                ("controlTrack", palette.controlTrack),
                ("separator", palette.separator),
                ("controlBorder", palette.controlBorder),
                ("label", palette.label),
                ("secondaryLabel", palette.secondaryLabel),
                ("systemFill", palette.systemFill),
            ] {
                XCTAssertLessThanOrEqual(
                    abs(color.red - color.green), bound, "\(name) has a colour cast")
                XCTAssertLessThanOrEqual(
                    abs(color.red - color.blue), bound, "\(name) has a colour cast")
            }
        }
    }

    /// Distance between two neutrals in **levels of 255** — the unit the ramp
    /// is authored in. Green, because the ramp is achromatic within a hair and
    /// green carries 72% of luminance, so it is the channel the eye is reading.
    private func levels(_ a: Color, _ b: Color) -> Int {
        Int((abs(Double(a.green) - Double(b.green)) * 255).rounded())
    }

    /// The neutral ramp steps far enough that each rung is a rung.
    ///
    /// **This is the finding the whole tone pass exists for.** The ramp this
    /// replaced stepped 5 to 8 levels: a card at `#17171A` on a `#111113` page
    /// is 6/255, a segmented pill sat 5 levels over its own track, and the
    /// sidebar was 5 levels off the content well beside it. At the dark end of
    /// the curve 6/255 is under a percent of luminance, so every elevation in
    /// the app was in fact carried by its hairline and a screenshot read as one
    /// flat near-black field with rules drawn on it. Linear, Raycast, GitHub
    /// and Vercel all step their dark ramps 9 to 14 levels per rung.
    ///
    /// The floor is `DesignTokens.minimumRampStep`, and it binds in **both**
    /// appearances: the near-white ramp had four surfaces inside 13 levels
    /// (base `#F2F3F5`, well `#F7F8FA`, bar `#FAFBFB`, card `#FFFFFF`), which
    /// is four names for one colour.
    /// The ramp is three chains, not one line, and only in dark do all three
    /// happen to run the same way. Each is walked separately because a near-
    /// white page has 25 levels of headroom above its frame and a near-black
    /// one has 240: light spends its range going *up* to the card and then
    /// back *down* for the recesses inside it, which is the same gesture
    /// mirrored, not a shorter version of the dark ramp.
    func testNeutralRampStepsAreLegible() async {
        for palette in [ControlPalette.darkStandard, ControlPalette.lightStandard] {
            let scheme = palette.colorScheme
            let card = DesignTokens.surface1.resolve(scheme)
            let chains: [(String, [(String, Color)])] = [
                // The shell: frame → paper → card. What a window is made of.
                (
                    "shell",
                    [("base", palette.base), ("surface0", palette.surface0), ("surface1", card)]
                ),
                // The recess inside a card: a field, a chip, a segmented
                // track, then the selected/pressed stop past it.
                (
                    "recess",
                    [("surface1", card), ("surface2", palette.surface2), ("surface3", palette.surface3)]
                ),
                // A bordered control's own three states. In dark it climbs
                // (surface2 → 3 → 4); in light it descends from white, which
                // is why `surface4` sits *between* `surface0` and `surface3`
                // rather than past them.
                (
                    "control",
                    [
                        ("idle", palette.controlSurface),
                        ("hovered", palette.controlSurfaceHovered),
                        ("pressed", palette.controlSurfacePressed),
                    ]
                ),
            ]
            for (chainName, chain) in chains {
                for (lower, upper) in zip(chain, chain.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(
                        levels(lower.1, upper.1), DesignTokens.minimumRampStep,
                        "\(scheme) \(chainName): \(lower.0) → \(upper.0) is not a step you can see")
                }
            }

            // A page item with no surface of its own hovers by a full rung too
            // — the sidebar row that used to lift 5/255 and read as nothing.
            XCTAssertGreaterThanOrEqual(
                levels(palette.base, palette.pageItemHoverFill), DesignTokens.minimumRampStep,
                "\(scheme): a page item's hover is a step you can see")
        }

        // Direction. On near-black every rung of every chain is lighter than
        // the one under it; on near-white the shell rises to the card and both
        // other chains fall away from it.
        let dark = ControlPalette.darkStandard
        XCTAssertLessThan(dark.base.green, dark.surface0.green)
        XCTAssertLessThan(dark.surface0.green, DesignTokens.surface1.dark.green)
        XCTAssertLessThan(DesignTokens.surface1.dark.green, dark.surface2.green)
        XCTAssertLessThan(dark.surface2.green, dark.surface3.green)
        XCTAssertLessThan(dark.base.green, dark.pageItemHoverFill.green)

        let light = ControlPalette.lightStandard
        XCTAssertLessThan(light.base.green, light.surface0.green)
        XCTAssertLessThan(light.surface0.green, DesignTokens.surface1.light.green)
        XCTAssertGreaterThan(DesignTokens.surface1.light.green, light.surface2.green)
        XCTAssertGreaterThan(light.surface2.green, light.surface3.green)
        XCTAssertGreaterThan(light.base.green, light.pageItemHoverFill.green)

        // …and the near-black end keeps its character: the floor is unchanged,
        // and widening the ramp is spending the range *above* it.
        XCTAssertEqual(dark.base, DesignTokens.hex(0x0C_0C_0E))
    }

    /// The **light shell is three levels, not four.** `base` (columns and
    /// gutters), `surface0` (the well *and* the chrome bands), `surface1`
    /// (cards) — and nothing between them. The fourth near-white was the bar
    /// material: `.bar` at white 0.64 over `#F2F3F5` landed at `#FAFBFB`,
    /// three levels under the card and three over the well, which is a rung
    /// that costs a token and says nothing.
    func testLightShellIsThreeLevels() async {
        let light = ControlPalette.lightStandard
        let shell = [light.base, light.surface0, DesignTokens.surface1.light]
        for (lower, upper) in zip(shell, shell.dropFirst()) {
            XCTAssertGreaterThanOrEqual(levels(lower, upper), DesignTokens.minimumRampStep)
        }
        XCTAssertEqual(
            light.chromeBand, light.surface0,
            "the light chrome band is the well's rung, not a fourth near-white")
    }

    /// The **columns are a rung off the field they frame.** A sidebar, a rail
    /// and the window gutters take `base`; the content well and the chrome
    /// bands over it take `surface0`. Column structure used to rest entirely
    /// on a 15/255 hairline with a 5/255 tone difference behind it, so
    /// removing the rule removed the columns.
    ///
    /// Direction is the Linear pattern and it is *not* symmetric: in dark the
    /// frame is darker than the field it holds, and in light it is darker
    /// *and* a shade cooler — the frame recedes in both, because a frame that
    /// advances is a frame you read instead of the content.
    func testColumnsAreARungOffTheContentWell() async {
        for palette in [ControlPalette.darkStandard, ControlPalette.lightStandard] {
            XCTAssertGreaterThanOrEqual(
                levels(palette.base, palette.surface0), DesignTokens.minimumRampStep,
                "\(palette.colorScheme): the columns and the well are one tone")
            XCTAssertLessThan(
                palette.base.green, palette.surface0.green,
                "\(palette.colorScheme): the frame is darker than the field")
        }
        let light = ControlPalette.lightStandard
        XCTAssertGreaterThan(
            light.base.blue - light.base.red,
            light.surface0.blue - light.surface0.red,
            "the light frame is the cooler of the two")
    }

    /// The text ladder still lands where it has to on the **widened**
    /// surfaces. Lifting a card 11 levels lifts the floor every string on it
    /// is measured against, so widening the ramp is a change to text contrast
    /// whether or not a single alpha moved — this is the assertion that says
    /// by how much.
    ///
    /// **The rungs that carry sentences clear WCAG AA.** Primary and secondary
    /// are ≥ 4.5:1 on every surface in both appearances, with the worst case
    /// at 5.74:1 (light secondary on `surface3`). Widening cost them margin —
    /// dark primary on `surface3` fell 13.71 → 10.54 — and nothing else.
    ///
    /// **Tertiary is the de-emphasized rung and is held to 3.85:1.** It has
    /// never cleared AA: at the pinned `lightTertiaryAlpha` of 0.54 it is
    /// 4.18:1 on pure *white*, so no light surface has ever reached 4.5 and
    /// the ladder was graded that way deliberately (AppKit's own
    /// `tertiaryLabelColor` is white 0.25 in dark, far below either number).
    /// What widening did was bring the dark rung down to meet the light one:
    /// both appearances now bottom out at 3.89:1 on `surface3`, where before
    /// dark ran 4.49–4.84 and light 3.97–4.18. Tertiary carries captions,
    /// eyebrows and field placeholders — never a sentence, never a control
    /// label — and it now reads the same in both appearances, which is what
    /// the ladder wanted and did not have.
    ///
    /// Quaternary is exempt and always was: chevrons, disabled glyphs and
    /// rule-adjacent marks, never a string you have to read.
    func testTextRungsClearContrastOnEveryRampSurface() async {
        func contrast(_ text: Color, over fill: Color) -> Double {
            func channel(_ v: Double) -> Double {
                v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            func luminance(_ c: Color) -> Double {
                0.2126 * channel(Double(c.red)) + 0.7152 * channel(Double(c.green))
                    + 0.0722 * channel(Double(c.blue))
            }
            let a = Double(text.alpha)
            let composited = Color(
                red: Float(a * Double(text.red) + (1 - a) * Double(fill.red)),
                green: Float(a * Double(text.green) + (1 - a) * Double(fill.green)),
                blue: Float(a * Double(text.blue) + (1 - a) * Double(fill.blue)),
                alpha: 1)
            let x = luminance(composited)
            let y = luminance(fill)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }

        for palette in [ControlPalette.darkStandard, ControlPalette.lightStandard] {
            let surfaces: [(String, Color)] = [
                ("base", palette.base),
                ("surface0", palette.surface0),
                ("chromeBand", palette.chromeBand),
                ("surface1", DesignTokens.surface1.resolve(palette.colorScheme)),
                ("surface2", palette.surface2),
                ("surface3", palette.surface3),
            ]
            for (surfaceName, surface) in surfaces {
                for (rungName, rung, floor) in [
                    ("primary", palette.label, 4.5),
                    ("secondary", palette.secondaryLabel, 4.5),
                    ("tertiary", palette.tertiaryLabel, 3.85),
                ] {
                    XCTAssertGreaterThanOrEqual(
                        contrast(rung, over: surface), floor,
                        "\(palette.colorScheme) \(rungName) on \(surfaceName)")
                }
            }
        }
    }

    func testIncreasedContrastStrengthensHairlinesAndLabels() async {
        let standard = ControlPalette.resolve(colorScheme: .dark, contrast: .standard)
        let increased = ControlPalette.resolve(colorScheme: .dark, contrast: .increased)
        XCTAssertGreaterThan(increased.separator.alpha, standard.separator.alpha)
        XCTAssertGreaterThan(increased.controlBorder.alpha, standard.controlBorder.alpha)
        XCTAssertGreaterThan(increased.label.alpha, standard.label.alpha)
    }

    /// The segmented picker used to paint a near-white pill under a
    /// near-black label in *both* appearances — the light-mode
    /// NSSegmentedControl dropped into a dark app.
    func testSegmentedSelectedPillInvertsWithAppearance() async {
        let dark = ControlPalette.darkStandard
        let light = ControlPalette.lightStandard
        // A selected segment is the one you are meant to read, so its label
        // is the primary rung in both appearances rather than a flat black or
        // white that belongs to neither ladder.
        XCTAssertEqual(dark.segmentedSelectedLabel, dark.label)
        XCTAssertEqual(light.segmentedSelectedLabel, light.label)
        XCTAssertLessThan(
            dark.segmentedSelectedFill.red, light.segmentedSelectedFill.red,
            "The dark-mode pill is a dark surface, not a near-white one")
        // The pill's lift comes from *elevation* (`surface3` plus the `e1`
        // contact shadow), not from lightness: it used to be a mid-grey plate
        // (#636366) six steps above its own track so it could be seen.
        XCTAssertEqual(dark.segmentedSelectedFill, dark.surface3)
        XCTAssertLessThan(
            dark.segmentedTrackFill.red, light.segmentedTrackFill.red,
            "The dark-mode track is darker than the light-mode track")
    }

    func testSegmentedPickerNodeUsesAppearanceLabelColors() async {
        await MainActor.run {
            @MainActor func segmentLabelColors(scheme: ColorScheme) -> [Color] {
                let runtime = RetainedViewRuntime(root: ViewNode())
                let context = ViewBuildContext(
                    canvasSizeProvider: { Size(width: 400, height: 200) },
                    invalidateHandler: {}
                )
                .withEnvironmentValue(\.colorScheme, scheme)
                let node = Picker("Theme", selection: .constant(0)) {
                    Text("One").tag(0)
                    Text("Two").tag(1)
                }
                .pickerStyle(.segmented)
                .makeComponent(context: context)
                .makeNode(runtime: runtime)
                return flatten(node).compactMap { $0.text != nil ? $0.textStyle.color : nil }
            }

            let darkColors = segmentLabelColors(scheme: .dark)
            let lightColors = segmentLabelColors(scheme: .light)
            XCTAssertFalse(darkColors.isEmpty, "Segment labels are painted")
            XCTAssertNotEqual(darkColors, lightColors, "Segment label colours follow the appearance")
        }
    }

    // MARK: - Finding 2: push buttons are a rounded rect, not a capsule

    func testPushButtonDefaultCornerRadiusIsMacOSRoundedRect() async {
        XCTAssertEqual(MacOSControlMetrics.Button.regularCornerRadius, 6)
        XCTAssertEqual(ButtonSurfaceStyle().cornerRadius, MacOSControlMetrics.Button.regularCornerRadius)
        XCTAssertEqual(ButtonSurfaceStyle.default.cornerRadius, MacOSControlMetrics.Button.regularCornerRadius)
        XCTAssertEqual(ButtonSurfaceStyle.destructive.cornerRadius, MacOSControlMetrics.Button.regularCornerRadius)
    }

    func testBuiltButtonIsNotAStadium() async {
        await MainActor.run {
            for style in [ButtonStyle.automatic, .bordered, .borderedProminent] {
                let node = buildNode(Button("Save") {}.buttonStyle(style))
                XCTAssertEqual(
                    node.cornerRadius, MacOSControlMetrics.Button.regularCornerRadius,
                    "\(style) renders a rounded rect, not a capsule clamped to h/2")
            }
        }
    }

    // MARK: - Finding 13: accent surfaces are opaque, with no coloured glow

    func testProminentButtonFillsWithTheFullAccentAtRest() async {
        await MainActor.run {
            let node = buildNode(Button("Prominent") {}.buttonStyle(.borderedProminent))
            let fill = node.backgroundColor ?? .clear
            XCTAssertEqual(fill.alpha, 1, accuracy: 0.001, "A resting accent button is not 84% opaque")
            // …and it is `accent-fill`: the same hex in both appearances,
            // because an opaque fill has no appearance behind it to vary with.
            XCTAssertEqual(fill, ControlPalette.darkStandard.accentFill)
            XCTAssertEqual(fill.red, Color.accentColor.red, accuracy: 0.002)
            XCTAssertEqual(fill.green, Color.accentColor.green, accuracy: 0.002)
            XCTAssertEqual(fill.blue, Color.accentColor.blue, accuracy: 0.002)
        }
    }

    /// A control shadow is neutral, and it follows the same
    /// appearance-conditional rule the cards do: nothing in dark, `e1` in
    /// light. A near-black bezel on a near-black page has no shadow to cast
    /// that is not either invisible or a smear.
    func testControlShadowsAreNeutralAndAmbient() async {
        await MainActor.run {
            for style in [ButtonStyle.automatic, .borderedProminent] {
                for scheme in [ColorScheme.dark, ColorScheme.light] {
                    let node = buildNode(Button("Go") {}.buttonStyle(style), colorScheme: scheme)
                    let shadow = node.shadowColor
                    XCTAssertLessThanOrEqual(
                        abs(shadow.red - shadow.blue), 6.0 / 255, "Control shadows are never tinted")
                    XCTAssertLessThanOrEqual(node.shadowOffset.y, 1, "Contact shadow, not a card drop shadow")
                    XCTAssertLessThanOrEqual(node.shadowSpread, 2)
                    if scheme == .dark {
                        XCTAssertEqual(shadow.alpha, 0, accuracy: 0.001, "a dark control casts nothing")
                    }
                }
            }
        }
    }

    // MARK: - Finding 12: destructive chrome

    func testDestructiveSurfaceUsesSystemRedAndNoDetachedSlab() async {
        let destructive = ButtonSurfaceStyle.destructive
        XCTAssertEqual(destructive.palette.idle.red, Color.red.red, accuracy: 0.002)
        XCTAssertEqual(destructive.palette.idle.green, Color.red.green, accuracy: 0.002)
        XCTAssertEqual(destructive.palette.idle.blue, Color.red.blue, accuracy: 0.002)
        XCTAssertLessThanOrEqual(
            destructive.chrome.shadowOffset.y, 1,
            "A 30pt control does not cast a shadow 16pt below itself")
        XCTAssertLessThanOrEqual(destructive.chrome.shadowSpread, 2)
    }

    /// macOS only fills a destructive button when the app also asks for
    /// prominence; otherwise the role lives in the label.
    func testBorderedDestructiveKeepsStandardBezelAndTintsItsLabel() async {
        await MainActor.run {
            let bordered = buildNode(Button("Delete", role: .destructive) {})
            let borderedFill = bordered.backgroundColor ?? .clear
            XCTAssertEqual(
                borderedFill, ControlPalette.darkStandard.borderedButtonPalette.idle,
                "A non-prominent destructive button keeps the standard bezel")
            let labelColors = flatten(bordered).compactMap { $0.text != nil ? $0.textStyle.color : nil }
            XCTAssertTrue(
                labelColors.contains { $0.red > 0.8 && $0.green < 0.4 },
                "The destructive role reads in the label: \(labelColors)")

            let prominent = buildNode(
                Button("Delete", role: .destructive) {}.buttonStyle(.borderedProminent))
            let prominentFill = prominent.backgroundColor ?? .clear
            XCTAssertEqual(prominentFill.red, Color.red.red, accuracy: 0.002, "Prominent + destructive fills red")
        }
    }

    // MARK: - Finding 14: the gloss is retired

    func testSurfaceSheenIsNearlyFlat() async {
        XCTAssertEqual(Controls.surfaceSheenFactor, 0.98, accuracy: 0.0001)
        XCTAssertGreaterThan(
            Controls.surfaceSheenFactor, 0.9,
            "a surface travels at the edge of perception, not the retired 18% bevel")
        XCTAssertEqual(Controls.grooveSheenFactor, 0.95, accuracy: 0.0001)
    }

    // MARK: - Finding 5: a disabled control dims its content

    func testDisabledButtonDimsItsLabelNotJustItsFill() async {
        await MainActor.run {
            let enabled = buildNode(Button("Unavailable") {})
            let disabled = buildNode(Button("Unavailable") {}.disabled(true))
            let enabledLabel = enabled.children.first
            let disabledLabel = disabled.children.first
            XCTAssertNotNil(enabledLabel)
            XCTAssertNotNil(disabledLabel)
            XCTAssertEqual(enabledLabel?.opacity ?? 1, 1, accuracy: 0.001)
            XCTAssertEqual(
                disabledLabel?.opacity ?? 1, ControlPalette.disabledContentOpacity, accuracy: 0.001,
                "AppKit dims the whole disabled cell, label included")
        }
    }

    // MARK: - Finding 15: no developer-facing text in control chrome

    func testSecureFieldMasksWithBullet() async {
        XCTAssertEqual(secureFieldMaskCharacter, "\u{2022}", "macOS masks with U+2022 BULLET, not an asterisk")
        await MainActor.run {
            let node = buildNode(SecureField("Password", text: .constant("hunter2")))
            let texts = flatten(node).compactMap(\.text)
            XCTAssertFalse(texts.contains { $0.contains("*") }, "No ASCII asterisks reach the scene: \(texts)")
            XCTAssertTrue(texts.contains { $0.contains("\u{2022}") }, "Masked content uses bullets: \(texts)")
        }
    }

    func testColorPickerDoesNotPaintAHexReadout() async {
        await MainActor.run {
            let node = buildNode(ColorPicker("Accent Color", selection: .constant(.blue)))
            let texts = flatten(node).compactMap(\.text)
            XCTAssertFalse(
                texts.contains { $0.hasPrefix("#") },
                "NSColorWell shows the well, never a hex string: \(texts)")
            XCTAssertTrue(texts.contains("Accent Color"), "The row label still renders")
        }
    }

    /// An NSColorWell is a *bordered control* filled with the selection: a
    /// bezel in the control tone with the swatch inset inside it, carrying the
    /// pointer ramp every other bordered control has. It used to be a bare
    /// rectangle of accent colour with a 1pt gutter, which read as an inert
    /// block of paint rather than as something to click.
    func testColorPickerWellIsABezelWithAnInsetSwatch() async {
        await MainActor.run {
            for scheme in [ColorScheme.light, .dark] {
                let palette = ControlPalette.resolve(colorScheme: scheme)
                let node = buildNode(
                    ColorPicker("Accent Color", selection: .constant(.blue)),
                    colorScheme: scheme
                )
                guard
                    let bezel = flatten(node).first(where: {
                        $0.preferredSize == MacOSControlMetrics.ColorWell.regularSize
                    })
                else {
                    return XCTFail("the well states the NSColorWell size")
                }
                XCTAssertEqual(bezel.backgroundColor, palette.controlSurface, "\(scheme): the bezel is a control face")
                XCTAssertEqual(bezel.borderColor, palette.controlBorder, "\(scheme): closed by the control hairline")
                XCTAssertEqual(bezel.borderWidth, 1, accuracy: 0.001)
                XCTAssertEqual(bezel.cornerRadius, MacOSControlMetrics.ColorWell.cornerRadius, accuracy: 0.001)
                // Hover affordance: the bezel carries the bordered-control
                // ramp, which is only expressible on a button surface.
                XCTAssertNotNil(
                    bezel.interactionSurface?.hoveredBackground,
                    "\(scheme): the well lights up under the pointer")
                XCTAssertFalse(bezel.isFocusable, "the row is the focus stop, not the bezel inside it")
                // …and it is the node a click on the swatch lands on:
                // activation does not bubble in the retained runtime, so a
                // chrome-only bezel would swallow every click on the well.
                XCTAssertTrue(bezel.isHitTestVisible)
                XCTAssertNotNil(bezel.onActivate, "\(scheme): clicking the well activates the well")

                let swatch = bezel.children[0]
                XCTAssertEqual(swatch.backgroundColor, .blue)
                XCTAssertEqual(
                    swatch.cornerRadius,
                    MacOSControlMetrics.ColorWell.swatchCornerRadius,
                    accuracy: 0.001
                )
            }
        }
    }

    /// The bezel and the row it sits in do the same thing, because they are
    /// built from the same closure. Clicking the swatch and clicking the row
    /// beside it must not be two different colour pickers.
    func testColorPickerBezelAndRowActivateTheSameWell() async {
        await MainActor.run {
            var selected = Color.blue
            let binding = Binding<Color>(get: { selected }, set: { selected = $0 })
            let node = buildNode(ColorPicker("Accent Color", selection: binding))
            guard
                let bezel = flatten(node).first(where: {
                    $0.preferredSize == MacOSControlMetrics.ColorWell.regularSize
                })
            else {
                return XCTFail("the well states the NSColorWell size")
            }

            bezel.onActivate?()
            let afterBezel = selected
            XCTAssertNotEqual(afterBezel, .blue, "the bezel steps the palette")

            selected = .blue
            node.onActivate?()
            XCTAssertEqual(selected, afterBezel, "…and the row does exactly the same step")
        }
    }

    /// The label used to be forced to `.secondary`, so "Accent Color"
    /// rendered dimmer than every sibling row of an otherwise uniform Form.
    func testColorPickerLabelSharesRowLabelProminence() async {
        await MainActor.run {
            let picker = buildNode(ColorPicker("Accent Color", selection: .constant(.blue)))
            let toggle = buildNode(Toggle("Sound Effects", isOn: .constant(true)))
            let pickerLabel = flatten(picker).first { $0.text == "Accent Color" }
            let toggleLabel = flatten(toggle).first { $0.text == "Sound Effects" }
            XCTAssertNotNil(pickerLabel)
            XCTAssertNotNil(toggleLabel)
            XCTAssertEqual(pickerLabel?.textStyle.color, toggleLabel?.textStyle.color)
        }
    }

    // MARK: - Finding 16: one focus-ring number

    func testFocusRingWidthAgreesAcrossBothPinnedSources() async {
        XCTAssertEqual(
            SurfaceChrome.focusRingStrokeWidth, MacOSControlMetrics.FocusRing.strokeWidth,
            "SurfaceChrome and MacOSControlMetrics both claimed to pin the macOS focus ring, with different numbers")
        XCTAssertEqual(SurfaceChrome.default.focusRingWidth, MacOSControlMetrics.FocusRing.strokeWidth)
        XCTAssertEqual(SurfaceChrome.elevatedButton.focusRingWidth, MacOSControlMetrics.FocusRing.strokeWidth)
    }

    /// A focus ring is a thin accent outline, not a bloom: 2pt at 0.45,
    /// drawn in the accent as **ink** so it is visible against the page it
    /// sits on. `accent-fill` as a ring is 2.7:1 on the near-black page — a
    /// focus ring you cannot see on the control you just tabbed to.
    func testFocusRingIsAVisibleAccentHalo() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let palette = ControlPalette.resolve(colorScheme: scheme)
            let chrome = palette.buttonChrome(focusTint: .accentColor)
            XCTAssertGreaterThanOrEqual(
                chrome.focusRingColor.alpha, 0.4,
                "\(scheme): a keyboard focus ring is clearly visible, not a 0.28 whisper")
            XCTAssertEqual(chrome.focusRingWidth, MacOSControlMetrics.FocusRing.strokeWidth)
            XCTAssertEqual(chrome.focusRingColor, palette.accentRing)
        }
        XCTAssertGreaterThanOrEqual(SurfaceChrome.elevatedButton.focusRingColor.alpha, 0.4)
    }
}
