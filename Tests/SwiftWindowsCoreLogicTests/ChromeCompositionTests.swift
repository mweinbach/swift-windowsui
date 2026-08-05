import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private func makeChromeNode<V: View>(_ view: V) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 800, height: 600) },
        invalidateHandler: {}
    )
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func flattened(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap { flattened($0) }
}

@MainActor
private func firstDescendant(_ node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
    flattened(node).first(where: predicate)
}

/// Chrome-composition assertions for the macOS-parity control surface
/// language: gradient sheens, hairline borders, shadows, and the segmented
/// picker label fix. Geometry is covered elsewhere; these tests pin paint.
final class ChromeCompositionTests: XCTestCase {

    // MARK: - Buttons

    func testButtonHasTopLighterGradientSheenAndHairlineBorder() async throws {
        try await MainActor.run {
            let node = makeChromeNode(Button("Tap Me") {})

            // Pinned chrome constants: 1pt hairline border, 4pt focus ring
            // (MacOSControlMetrics.FocusRing.strokeWidth). The ring's *width*
            // is 0 at rest and grows out of the edge when focus arrives, so
            // the pinned value lives on the interaction surface the runtime
            // resolves — see `docs/AnimationParity.md`.
            XCTAssertEqual(node.borderWidth, 1, accuracy: 0.001)
            XCTAssertEqual(node.outlineWidth, 0, accuracy: 0.001)
            XCTAssertEqual(
                node.interactionSurface?.focusRingWidth ?? -1,
                MacOSControlMetrics.FocusRing.strokeWidth, accuracy: 0.001)

            // Subtle vertical gradient: bottom stop darker than the (idle)
            // top stop. Big Sur+ keeps 96% of the luminance, not the 82%
            // the retired gloss dropped to.
            let background = try XCTUnwrap(node.backgroundColor)
            let sheen = try XCTUnwrap(node.backgroundGradient)
            XCTAssertLessThan(sheen.endColor.red, background.red)
            XCTAssertLessThan(sheen.endColor.blue, background.blue)
            XCTAssertEqual(sheen.endColor.alpha, background.alpha, accuracy: 0.001)

            // Border gradient fades toward the bottom edge (top highlight).
            let borderSheen = try XCTUnwrap(node.borderGradient)
            XCTAssertLessThan(borderSheen.endColor.alpha, node.borderColor.alpha)
        }
    }

    /// A bezel's ring is lightest along its top edge in both appearances,
    /// which is the *opposite* stop order in each: a white ring fades
    /// downward, a black one fades upward. One direction for both put the
    /// shadow edge along the top of every light-mode control.
    @MainActor
    func testBezelRingIsLightestAlongItsTopEdgeInBothAppearances() async throws {
        for palette in [ControlPalette.darkStandard, .lightStandard] {
            let ring = try XCTUnwrap(Controls.borderSheen(for: palette.controlBorder))
            guard case .linear(let gradient) = ring else {
                return XCTFail("a ring sheen is a linear gradient")
            }
            let topWeight = gradient.startColor.alpha
            let bottomWeight = gradient.endColor.alpha
            if palette.isDark {
                XCTAssertGreaterThan(
                    topWeight, bottomWeight,
                    "a white ring is a highlight: full strength on top, fading down")
            } else {
                XCTAssertLessThan(
                    topWeight, bottomWeight,
                    "a black ring is a shadow: withdrawn on top, closing along the bottom")
            }
            XCTAssertEqual(
                min(topWeight, bottomWeight),
                max(topWeight, bottomWeight) * Controls.borderSheenFadeFactor,
                accuracy: 0.0001
            )
        }
    }

    func testBorderedProminentButtonGradientTracksTint() async throws {
        try await MainActor.run {
            let node = makeChromeNode(Button("Go") {}.buttonStyle(.borderedProminent))
            let background = try XCTUnwrap(node.backgroundColor)
            // Default tint is the design accent as an opaque fill, #5B4DE0.
            XCTAssertEqual(background, ControlPalette.darkStandard.accentFill)
            let sheen = try XCTUnwrap(node.backgroundGradient)
            XCTAssertLessThan(sheen.endColor.blue, background.blue)
        }
    }

    /// macOS only *fills* a destructive button when the app also asks for
    /// prominence; otherwise the role reads in the label and the bezel
    /// stays standard.
    func testDestructiveButtonKeepsRedSurfaceWithSheen() async throws {
        try await MainActor.run {
            let bordered = makeChromeNode(Button("Delete", role: .destructive) {})
            let borderedLabel = try XCTUnwrap(flattened(bordered).first { $0.text == "Delete" })
            XCTAssertGreaterThan(borderedLabel.textStyle.color.red, borderedLabel.textStyle.color.green)
            XCTAssertGreaterThan(borderedLabel.textStyle.color.red, borderedLabel.textStyle.color.blue)

            let node = makeChromeNode(
                Button("Delete", role: .destructive) {}.buttonStyle(.borderedProminent))
            let background = try XCTUnwrap(node.backgroundColor)
            XCTAssertGreaterThan(background.red, background.green)
            XCTAssertGreaterThan(background.red, background.blue)
            let sheen = try XCTUnwrap(node.backgroundGradient)
            XCTAssertLessThan(sheen.endColor.red, background.red)
        }
    }

    func testDisabledButtonSheenDerivesFromDisabledSurface() async throws {
        try await MainActor.run {
            let node = makeChromeNode(Button("Nope") {}.disabled(true))
            XCTAssertFalse(node.isHitTestVisible)
            let background = try XCTUnwrap(node.backgroundColor)
            let sheen = try XCTUnwrap(node.backgroundGradient)
            XCTAssertLessThan(sheen.endColor.red, background.red)
        }
    }

    /// The sheen has to move what the *window* shows, not what the surface's
    /// own channels say.
    ///
    /// A dark-appearance control surface is `white(0.10)`: a wash whose
    /// composite is governed by its alpha. Scaling `(1,1,1)` by 0.96 left the
    /// composite 0.4% lower — one level of 255 on a 25/255 button — so every
    /// bordered button in the dark appearance was a flat fill while the light
    /// one, being opaque, carried the gradient the same code asked for.
    func testControlSheenMovesTheCompositeInBothAppearances() async {
        for palette in [ControlPalette.darkStandard, .lightStandard] {
            let surface = palette.controlSurface
            let bottom = Controls.sheenBottom(surface, drop: Controls.surfaceSheenDrop)
            let travel = Controls.compositeValue(surface) - Controls.compositeValue(bottom)
            XCTAssertGreaterThan(
                travel, 0.01,
                "\(palette.colorScheme): a sheen the window cannot see is not a sheen"
            )
            XCTAssertLessThanOrEqual(
                travel, Controls.surfaceSheenDrop + 0.0001,
                "\(palette.colorScheme): and never more than the pinned step"
            )
            // Hue survives: the channels still scale together.
            XCTAssertEqual(bottom.alpha, surface.alpha, accuracy: 0.0001)
        }
    }

    /// The step is capped relative to the surface so a dim control does not
    /// lose its bottom edge to its own sheen. The bordered face is opaque
    /// now, so it takes the full absolute step; the ceiling binds on the
    /// washes that remain — the fill ramp a plain button hovers into.
    func testDarkControlSheenIsCappedRelativeToItsSurface() async {
        let palette = ControlPalette.darkStandard
        let wash = palette.quaternaryFill
        let bottom = Controls.sheenBottom(wash, drop: Controls.surfaceSheenDrop)
        let value = Controls.compositeValue(wash)
        let travel = value - Controls.compositeValue(bottom)
        XCTAssertEqual(
            travel, value * Controls.surfaceSheenRelativeCeiling, accuracy: 0.0005,
            "a 8/255 wash takes the relative ceiling, not the full absolute step"
        )
        // …and the opaque bezel beside it takes the absolute step, which is
        // the whole point of stating the sheen as a distance.
        let surface = palette.controlSurface
        let surfaceValue = Controls.compositeValue(surface)
        let surfaceTravel =
            surfaceValue - Controls.compositeValue(Controls.sheenBottom(surface, drop: Controls.surfaceSheenDrop))
        XCTAssertEqual(surfaceTravel, Controls.surfaceSheenDrop, accuracy: 0.0005)
    }

    /// Every opaque full-value surface is where the two formulations meet:
    /// a white bezel, an accent fill, a destructive red, a slider's filled
    /// bar. That is the reason nothing already correct moves — only the
    /// translucent dark washes, which had no sheen at all, do.
    func testOpaqueFullValueSurfaceSheenStillEqualsTheHistoricalFactor() async {
        let surfaces: [Color] = [
            Color(red: 1, green: 1, blue: 1, alpha: 1),
            ControlPalette.opaque(.accentColor),
            ControlPalette.opaque(.red),
            ControlPalette.darkStandard.segmentedSelectedFill,
        ]
        for surface in surfaces where Controls.compositeValue(surface) >= 0.999 {
            XCTAssertEqual(
                Controls.sheenBottom(surface, drop: Controls.surfaceSheenDrop),
                Controls.shaded(surface, by: Controls.surfaceSheenFactor),
                "\(surface) is at full value and takes the historical proportional shade"
            )
        }
    }

    // MARK: - Segmented picker

    func testSegmentedPickerLabelsArePresentCompactAndLegible() async throws {
        try await MainActor.run {
            let node = makeChromeNode(
                Picker("Color", selection: .constant(1)) {
                    Text("Red").tag(0)
                    Text("Green").tag(1)
                    Text("Blue").tag(2)
                }
            )
            let nodes = flattened(node)

            // The invisible-label regression: segment text must exist in the
            // tree with compact, single-line metrics that cannot be
            // height-starved by the segment chrome.
            for title in ["Red", "Green", "Blue"] {
                XCTAssertTrue(
                    nodes.contains { $0.text == title },
                    "segment label \(title) missing from picker node tree")
            }

            let selected = try XCTUnwrap(nodes.first { $0.text == "Green" })
            XCTAssertLessThanOrEqual(selected.textStyle.scale, 1.3)
            XCTAssertEqual(selected.textStyle.maximumNumberOfLines, 1)
            // Dark mode raises a grey pill under a WHITE label. The
            // near-black label on a near-white pill this used to pin is the
            // light-mode NSSegmentedControl.
            XCTAssertEqual(selected.textStyle.color, ControlPalette.darkStandard.segmentedSelectedLabel)

            let unselected = try XCTUnwrap(nodes.first { $0.text == "Red" })
            XCTAssertLessThanOrEqual(unselected.textStyle.scale, 1.3)
            // Label colour on the recessed track.
            XCTAssertEqual(unselected.textStyle.color, ControlPalette.darkStandard.label)

            // Segment chrome is compact enough to leave room for the label.
            let segmentButton = try XCTUnwrap(
                nodes.first { $0.children.contains(where: { $0 === selected }) })
            guard case .stack(let layout) = segmentButton.layoutMode else {
                XCTFail("segment button should use stack layout")
                return
            }
            XCTAssertLessThanOrEqual(layout.padding.top, 4)
            XCTAssertLessThanOrEqual(layout.padding.bottom, 4)

            // Selected segment is a raised pill lifted off the groove by a
            // neutral ambient shadow.
            let selectedBackground = try XCTUnwrap(segmentButton.backgroundColor)
            XCTAssertEqual(selectedBackground, ControlPalette.darkStandard.segmentedSelectedFill)
            XCTAssertGreaterThan(
                selectedBackground.red, ControlPalette.darkStandard.segmentedTrackFill.red,
                "the pill is raised out of the track")
            // The lift is `e1`: one quiet tonal step plus a contact shadow,
            // rather than the six-step mid-grey plate the pill used to be.
            XCTAssertGreaterThan(segmentButton.shadowColor.alpha, 0.05)
        }
    }

    // MARK: - Toggle switch

    func testToggleSwitchHasRecessedTrackAndShadowedThumb() async throws {
        try await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())

            let onNode = Controls.toggle(runtime: runtime, isOn: true)
            let onTrack = try XCTUnwrap(
                firstDescendant(onNode) { $0.preferredSize?.width == 40 && $0.preferredSize?.height == 22 })
            XCTAssertNotNil(onTrack.backgroundGradient)
            XCTAssertEqual(onTrack.borderWidth, 1, accuracy: 0.001)
            // The knob is a flat white disc lifted by `e1`. It used to carry
            // a gradient *and* a hairline edge *and* a 0.32 shadow — three
            // depth cues stacked on an 18pt circle.
            let onThumb = try XCTUnwrap(onTrack.children.first)
            XCTAssertEqual(onThumb.borderWidth, 0, accuracy: 0.001)
            XCTAssertGreaterThan(onThumb.shadowColor.alpha, 0.1)
            XCTAssertNil(onThumb.backgroundGradient)
            XCTAssertEqual(onThumb.frame.width, 18, accuracy: 0.001)

            // Off state: recessed track — top stop darker than bottom stop.
            let offNode = Controls.toggle(runtime: runtime, isOn: false)
            let offTrack = try XCTUnwrap(
                firstDescendant(offNode) { $0.preferredSize?.width == 40 && $0.preferredSize?.height == 22 })
            let offBackground = try XCTUnwrap(offTrack.backgroundColor)
            let offGradient = try XCTUnwrap(offTrack.backgroundGradient)
            XCTAssertLessThan(offBackground.red, offGradient.endColor.red)
        }
    }

    // MARK: - Slider

    func testSliderHasInsetTrackGradientFillAndShadowedThumb() async throws {
        try await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = Controls.slider(runtime: runtime, value: 0.5)
            XCTAssertEqual(node.children.count, 3)

            let track = node.children[0]
            let trackBackground = try XCTUnwrap(track.backgroundColor)
            let trackGradient = try XCTUnwrap(track.backgroundGradient)
            // Recessed groove: top stop darker than bottom stop.
            XCTAssertLessThan(trackBackground.red, trackGradient.endColor.red)

            let filled = node.children[1]
            let filledBackground = try XCTUnwrap(filled.backgroundColor)
            let filledGradient = try XCTUnwrap(filled.backgroundGradient)
            // Accent fill: top-lighter sheen.
            XCTAssertLessThan(filledGradient.endColor.blue, filledBackground.blue)

            let thumb = node.children[2]
            XCTAssertEqual(thumb.borderWidth, 1, accuracy: 0.001)
            XCTAssertGreaterThan(thumb.shadowColor.alpha, 0.1)
            XCTAssertNotNil(thumb.backgroundGradient)
        }
    }

    // MARK: - Progress bar

    func testProgressBarHasRoundedRecessedTrackAndGradientFill() async throws {
        try await MainActor.run {
            let node = Controls.progressBar(value: 0.5)
            XCTAssertEqual(node.children.count, 2)

            let track = node.children[0]
            let trackBackground = try XCTUnwrap(track.backgroundColor)
            let trackGradient = try XCTUnwrap(track.backgroundGradient)
            XCTAssertLessThan(trackBackground.red, trackGradient.endColor.red)

            let filled = node.children[1]
            XCTAssertNotNil(filled.backgroundGradient)

            // Fully rounded ends (radius == half the bar height).
            let barHeight = try XCTUnwrap(node.preferredSize?.height)
            XCTAssertEqual(track.cornerRadius, barHeight * 0.5, accuracy: 0.001)
            XCTAssertEqual(filled.cornerRadius, barHeight * 0.5, accuracy: 0.001)
        }
    }

    // MARK: - Checkbox / radio

    func testCheckedCheckboxUsesAccentFillWithCheckmark() async throws {
        try await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())

            let checked = Controls.checkbox(runtime: runtime, label: "Option", isChecked: true)
            let checkedBox = try XCTUnwrap(
                firstDescendant(checked) { $0.preferredSize?.width == 20 && $0.preferredSize?.height == 20 })
            let fill = try XCTUnwrap(checkedBox.backgroundColor)
            // Default checked color is the accent blue.
            XCTAssertEqual(fill.blue, 1.0, accuracy: 0.02)
            XCTAssertNotNil(checkedBox.backgroundGradient)
            XCTAssertTrue(flattened(checkedBox).contains { $0.text == "\u{E73E}" })

            let unchecked = Controls.checkbox(runtime: runtime, label: "Option", isChecked: false)
            let uncheckedBox = try XCTUnwrap(
                firstDescendant(unchecked) { $0.preferredSize?.width == 20 && $0.preferredSize?.height == 20 })
            let idleFill = try XCTUnwrap(uncheckedBox.backgroundColor)
            XCTAssertLessThan(idleFill.blue, 0.5)
            XCTAssertFalse(flattened(uncheckedBox).contains { $0.text == "\u{E73E}" })
        }
    }

    func testSelectedRadioShowsAccentRingWithWhiteDot() async throws {
        try await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())

            let selected = Controls.radioButton(runtime: runtime, label: "A", isSelected: true)
            let ring = try XCTUnwrap(
                firstDescendant(selected) { $0.preferredSize?.width == 20 && $0.preferredSize?.height == 20 })
            let fill = try XCTUnwrap(ring.backgroundColor)
            XCTAssertEqual(fill.blue, 1.0, accuracy: 0.02)
            XCTAssertNotNil(ring.backgroundGradient)
            let dot = try XCTUnwrap(ring.children.first)
            XCTAssertEqual(dot.backgroundColor?.red ?? 0, 1.0, accuracy: 0.02)

            let unselected = Controls.radioButton(runtime: runtime, label: "A", isSelected: false)
            let unselectedRing = try XCTUnwrap(
                firstDescendant(unselected) { $0.preferredSize?.width == 20 && $0.preferredSize?.height == 20 })
            XCTAssertTrue(unselectedRing.children.isEmpty)
        }
    }

    // MARK: - Text fields

    func testTextFieldHasInsetGradientHairlineAndSecondaryPlaceholder() async throws {
        try await MainActor.run {
            let node = makeChromeNode(TextField("Name", text: .constant("")))

            XCTAssertEqual(node.borderWidth, 1, accuracy: 0.001)
            XCTAssertEqual(
                node.cornerRadius, MacOSControlMetrics.Button.regularCornerRadius, accuracy: 0.001)

            // Recessed well: bottom stop lighter than the top stop.
            let background = try XCTUnwrap(node.backgroundColor)
            let gradient = try XCTUnwrap(node.backgroundGradient)
            XCTAssertGreaterThan(gradient.endColor.red, background.red)

            // Placeholder at secondary-label prominence.
            let placeholder = try XCTUnwrap(flattened(node).first { $0.text == "Name" })
            XCTAssertLessThan(placeholder.textStyle.color.alpha, 0.7)

            // Accent focus ring at the pinned macOS stroke width. The ramp
            // is data the runtime resolves against its own focus target, not
            // something the field's own closure paints: see
            // `ControlInteractionContinuityTests` for the timeline, and the
            // rebuild that used to strip a focused field's ring.
            let surface = try XCTUnwrap(node.interactionSurface)
            XCTAssertEqual(surface.focusRingWidth, MacOSControlMetrics.FocusRing.strokeWidth, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(surface.focusRingColor).alpha, 0.4)
            XCTAssertEqual(node.outlineWidth, 0, accuracy: 0.001, "no ring until focus arrives")
        }
    }

    func testSecureFieldSharesFieldChrome() async throws {
        try await MainActor.run {
            let node = makeChromeNode(SecureField("Password", text: .constant("secret")))
            XCTAssertNotNil(node.backgroundGradient)
            XCTAssertEqual(
                node.cornerRadius, MacOSControlMetrics.Button.regularCornerRadius, accuracy: 0.001)
            // macOS masks with U+2022 BULLET, not the ASCII asterisk.
            XCTAssertTrue(flattened(node).contains { $0.text == "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}" })
        }
    }

    // MARK: - Stepper

    func testStepperButtonsUseElevatedChromeWithSheen() async throws {
        try await MainActor.run {
            let node = makeChromeNode(
                Stepper(value: .constant(5), in: 0...10) {
                    Text("Count: 5")
                }
            )
            // Pinned structure: [label, bezel[increment, rule, decrement]] —
            // the vertical NSStepper, not the side-by-side UIStepper pair,
            // and one bezel rather than two chained buttons.
            XCTAssertEqual(node.children.count, 2)
            let bezel = node.children[1]
            XCTAssertEqual(bezel.children.count, 3)
            let increment = bezel.children[0]
            let decrement = bezel.children[2]

            // The hairline ring is the bezel's, drawn once around the pair.
            XCTAssertEqual(bezel.borderWidth, 1, accuracy: 0.001)
            XCTAssertTrue(bezel.children[1].isSeparatorRule)

            for button in [decrement, increment] {
                // Half chrome: no ring of its own, but the surface fill and
                // its gradient sheen stay — that is what makes a pressed half
                // read as pressed.
                XCTAssertEqual(button.borderWidth, 0, accuracy: 0.001)
                let background = try XCTUnwrap(button.backgroundColor)
                let sheen = try XCTUnwrap(button.backgroundGradient)
                XCTAssertLessThan(sheen.endColor.red, background.red)
            }
            XCTAssertEqual(decrement.accessibilityLabel, "Decrement")
            XCTAssertEqual(increment.accessibilityLabel, "Increment")
        }
    }
}
