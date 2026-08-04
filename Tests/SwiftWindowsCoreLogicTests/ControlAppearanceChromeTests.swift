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

    /// macOS neutrals are grey. The retired palette was blue-cast navy
    /// (`(0.18, 0.23, 0.31)` bordered fill, `(0.96, 0.98, 1.0)` borders),
    /// which is the single clearest "this is a themed web app" signal.
    func testNeutralRolesAreAchromatic() async {
        for palette in [ControlPalette.darkStandard, ControlPalette.lightStandard] {
            for (name, color) in [
                ("controlSurface", palette.controlSurface),
                ("separator", palette.separator),
                ("controlBorder", palette.controlBorder),
                ("label", palette.label),
                ("secondaryLabel", palette.secondaryLabel),
                ("systemFill", palette.systemFill),
            ] {
                XCTAssertEqual(color.red, color.green, accuracy: 0.001, "\(name) has a colour cast")
                XCTAssertEqual(color.green, color.blue, accuracy: 0.001, "\(name) has a colour cast")
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
        XCTAssertEqual(dark.segmentedSelectedLabel, .white, "Dark mode raises a grey pill under a white label")
        XCTAssertEqual(light.segmentedSelectedLabel, .black)
        XCTAssertLessThan(
            dark.segmentedSelectedFill.red, light.segmentedSelectedFill.red,
            "The dark-mode pill is grey (#636366), not near-white")
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
            XCTAssertEqual(fill.red, Color.accentColor.red, accuracy: 0.002)
            XCTAssertEqual(fill.green, Color.accentColor.green, accuracy: 0.002)
            XCTAssertEqual(fill.blue, Color.accentColor.blue, accuracy: 0.002)
        }
    }

    func testControlShadowsAreNeutralAndAmbient() async {
        await MainActor.run {
            for style in [ButtonStyle.automatic, .borderedProminent] {
                let node = buildNode(Button("Go") {}.buttonStyle(style))
                let shadow = node.shadowColor
                XCTAssertEqual(shadow.red, shadow.green, accuracy: 0.001, "Control shadows are never tinted")
                XCTAssertEqual(shadow.green, shadow.blue, accuracy: 0.001)
                XCTAssertLessThanOrEqual(node.shadowOffset.y, 1, "Ambient shadow, not a card drop shadow")
                XCTAssertLessThanOrEqual(node.shadowSpread, 2)
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
        XCTAssertEqual(Controls.surfaceSheenFactor, 0.96, accuracy: 0.0001)
        XCTAssertGreaterThan(
            Controls.surfaceSheenFactor, 0.9,
            "Big Sur+ controls carry a 3–5% sheen, not the retired 18% bevel")
        XCTAssertEqual(Controls.grooveSheenFactor, 0.90, accuracy: 0.0001)
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
                XCTAssertNotNil(bezel.onPointerEnter, "\(scheme): the well lights up under the pointer")
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

    func testFocusRingIsAVisibleAccentHalo() async {
        let chrome = ControlPalette.darkStandard.buttonChrome(focusTint: .accentColor)
        XCTAssertGreaterThanOrEqual(
            chrome.focusRingColor.alpha, 0.5,
            "A keyboard focus ring is a clearly visible accent halo, not a 0.28 whisper")
        XCTAssertEqual(chrome.focusRingWidth, MacOSControlMetrics.FocusRing.strokeWidth)
        XCTAssertGreaterThanOrEqual(SurfaceChrome.elevatedButton.focusRingColor.alpha, 0.5)
    }
}
