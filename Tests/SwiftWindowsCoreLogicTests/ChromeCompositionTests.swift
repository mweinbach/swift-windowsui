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

            // Pinned chrome constants: 1pt hairline border, 2pt focus ring.
            XCTAssertEqual(node.borderWidth, 1, accuracy: 0.001)
            XCTAssertEqual(node.outlineWidth, 2, accuracy: 0.001)

            // Subtle vertical gradient: bottom stop darker than the (idle)
            // top stop.
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

    func testBorderedProminentButtonGradientTracksTint() async throws {
        try await MainActor.run {
            let node = makeChromeNode(Button("Go") {}.buttonStyle(.borderedProminent))
            let background = try XCTUnwrap(node.backgroundColor)
            // Default tint is Color.blue (#007AFF).
            XCTAssertEqual(background.blue, 1.0, accuracy: 0.02)
            let sheen = try XCTUnwrap(node.backgroundGradient)
            XCTAssertLessThan(sheen.endColor.blue, background.blue)
        }
    }

    func testDestructiveButtonKeepsRedSurfaceWithSheen() async throws {
        try await MainActor.run {
            let node = makeChromeNode(Button("Delete", role: .destructive) {})
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
            // Dark label on the raised light pill.
            XCTAssertLessThan(selected.textStyle.color.red, 0.2)

            let unselected = try XCTUnwrap(nodes.first { $0.text == "Red" })
            XCTAssertLessThanOrEqual(unselected.textStyle.scale, 1.3)
            // Light label on the recessed track.
            XCTAssertGreaterThan(unselected.textStyle.color.red, 0.8)

            // Segment chrome is compact enough to leave room for the label.
            let segmentButton = try XCTUnwrap(
                nodes.first { $0.children.contains(where: { $0 === selected }) })
            guard case .stack(let layout) = segmentButton.layoutMode else {
                XCTFail("segment button should use stack layout")
                return
            }
            XCTAssertLessThanOrEqual(layout.padding.top, 2)
            XCTAssertLessThanOrEqual(layout.padding.bottom, 2)

            // Selected segment is a raised pill: light fill + soft shadow.
            let selectedBackground = try XCTUnwrap(segmentButton.backgroundColor)
            XCTAssertGreaterThan(selectedBackground.red, 0.85)
            XCTAssertGreaterThan(segmentButton.shadowColor.alpha, 0.1)
        }
    }

    // MARK: - Toggle switch

    func testToggleSwitchHasRecessedTrackAndShadowedThumb() async throws {
        try await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())

            let onNode = Controls.toggle(runtime: runtime, isOn: true)
            let onTrack = try XCTUnwrap(
                firstDescendant(onNode) { $0.preferredSize?.width == 44 && $0.preferredSize?.height == 24 })
            XCTAssertNotNil(onTrack.backgroundGradient)
            XCTAssertEqual(onTrack.borderWidth, 1, accuracy: 0.001)
            let onThumb = try XCTUnwrap(onTrack.children.first)
            XCTAssertEqual(onThumb.borderWidth, 1, accuracy: 0.001)
            XCTAssertGreaterThan(onThumb.shadowColor.alpha, 0.1)
            XCTAssertNotNil(onThumb.backgroundGradient)

            // Off state: recessed track — top stop darker than bottom stop.
            let offNode = Controls.toggle(runtime: runtime, isOn: false)
            let offTrack = try XCTUnwrap(
                firstDescendant(offNode) { $0.preferredSize?.width == 44 && $0.preferredSize?.height == 24 })
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
            XCTAssertEqual(node.cornerRadius, 8, accuracy: 0.001)

            // Recessed well: bottom stop lighter than the top stop.
            let background = try XCTUnwrap(node.backgroundColor)
            let gradient = try XCTUnwrap(node.backgroundGradient)
            XCTAssertGreaterThan(gradient.endColor.red, background.red)

            // Placeholder at secondary-label prominence.
            let placeholder = try XCTUnwrap(flattened(node).first { $0.text == "Name" })
            XCTAssertLessThan(placeholder.textStyle.color.alpha, 0.7)

            // Accent focus ring at the pinned 2pt width.
            node.onFocusEnter?()
            XCTAssertEqual(node.outlineWidth, 2, accuracy: 0.001)
            node.onFocusExit?()
            XCTAssertEqual(node.outlineWidth, 0, accuracy: 0.001)
        }
    }

    func testSecureFieldSharesFieldChrome() async throws {
        try await MainActor.run {
            let node = makeChromeNode(SecureField("Password", text: .constant("secret")))
            XCTAssertNotNil(node.backgroundGradient)
            XCTAssertEqual(node.cornerRadius, 8, accuracy: 0.001)
            XCTAssertTrue(flattened(node).contains { $0.text == "******" })
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
            // Pinned structure: [label, decrement, increment].
            XCTAssertEqual(node.children.count, 3)
            let decrement = node.children[1]
            let increment = node.children[2]

            for button in [decrement, increment] {
                // Elevated-button chrome: hairline border, gradient sheen.
                XCTAssertEqual(button.borderWidth, 1, accuracy: 0.001)
                let background = try XCTUnwrap(button.backgroundColor)
                let sheen = try XCTUnwrap(button.backgroundGradient)
                XCTAssertLessThan(sheen.endColor.red, background.red)
            }
            XCTAssertEqual(decrement.accessibilityLabel, "Decrement")
            XCTAssertEqual(increment.accessibilityLabel, "Increment")
        }
    }
}
