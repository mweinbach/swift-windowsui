import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// Regression tests for the product-UI-polish leftovers:
/// - labeled Slider/ProgressView/Gauge must keep their label fully above the
///   track, even when a constrained parent squeezes the control vertically
/// - `inspector` presentations must paint in the deferred phase, dismiss on
///   Escape, and restore focus captured at presentation time
@MainActor
private func polishMakeContext(
    size: Size = Size(width: 800, height: 600),
    onInvalidate: @escaping () -> Void = {}
) -> ViewBuildContext {
    ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
}

@MainActor
private func polishMakeRuntime(size: Size = Size(width: 800, height: 600)) -> RetainedViewRuntime {
    let runtime = RetainedViewRuntime(root: ViewNode())
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    return runtime
}

@MainActor
private func polishMakeNode<V: View>(
    _ view: V,
    runtime: RetainedViewRuntime,
    context: ViewBuildContext
) -> ViewNode {
    view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func polishAllTexts(in node: ViewNode) -> [String] {
    var texts: [String] = []
    if let text = node.text {
        texts.append(text)
    }
    for child in node.children {
        texts.append(contentsOf: polishAllTexts(in: child))
    }
    return texts
}

@MainActor
private func polishFocusableNode(containing text: String, in node: ViewNode) -> ViewNode? {
    if node.isFocusable, polishAllTexts(in: node).contains(text) {
        return node
    }
    for child in node.children {
        if let match = polishFocusableNode(containing: text, in: child) {
            return match
        }
    }
    return nil
}

@MainActor
private func polishFirstFocusableNode(in node: ViewNode) -> ViewNode? {
    if node.isFocusable {
        return node
    }
    for child in node.children {
        if let match = polishFirstFocusableNode(in: child) {
            return match
        }
    }
    return nil
}

/// Layouts `view` at `size` and returns the composition's root node.
@MainActor
private func polishLayoutLabeledControl<V: View>(
    _ view: V,
    size: Size,
    runtime: RetainedViewRuntime,
    context: ViewBuildContext
) -> ViewNode {
    let node = polishMakeNode(view, runtime: runtime, context: context)
    node.frame = Rect(origin: .zero, size: size)
    runtime.root.addChild(node)
    _ = runtime.renderFrame()
    node.removeFromParent()
    return node
}

@MainActor
private func polishAssertLabelAboveTrack(
    label: Rect,
    track: Rect,
    spacing: Double,
    naturalLabelHeight: Double,
    _ labelName: String
) {
    XCTAssertEqual(
        label.height, naturalLabelHeight, accuracy: 0.5,
        "\(labelName) label must keep its natural height instead of being squeezed"
    )
    XCTAssertEqual(
        track.minY - label.maxY, spacing, accuracy: 0.5,
        "\(labelName) track must sit exactly \(spacing)pt below the label frame"
    )
    XCTAssertLessThanOrEqual(
        label.maxY, track.minY,
        "\(labelName) label frame must sit fully above the track frame"
    )
}

@MainActor
private func polishRunLabeledControlScenario<V: View>(
    _ labelName: String,
    spacing: Double,
    gallerySize: Size,
    squeezedHeight: Double,
    makeView: @MainActor () -> V
) {
    let runtime = polishMakeRuntime()
    let context = polishMakeContext()

    // Gallery-style canvas: enough room for label + spacing + track.
    let relaxed = polishLayoutLabeledControl(
        makeView(),
        size: gallerySize,
        runtime: runtime,
        context: context
    )
    XCTAssertGreaterThanOrEqual(relaxed.children.count, 2, "\(labelName) must compose label + track")
    let relaxedLabel = relaxed.children[0].resolvedFrame
    let relaxedTrack = relaxed.children[1].resolvedFrame
    polishAssertLabelAboveTrack(
        label: relaxedLabel,
        track: relaxedTrack,
        spacing: spacing,
        naturalLabelHeight: relaxedLabel.height,
        labelName
    )
    let naturalTrackHeight = relaxedTrack.height

    // Constrained canvas: not enough room for everything. The track must
    // absorb the deficit; the label keeps its natural height and stays
    // fully above the track with the same spacing.
    let squeezed = polishLayoutLabeledControl(
        makeView(),
        size: Size(width: gallerySize.width, height: squeezedHeight),
        runtime: runtime,
        context: context
    )
    let squeezedLabel = squeezed.children[0].resolvedFrame
    let squeezedTrack = squeezed.children[1].resolvedFrame
    polishAssertLabelAboveTrack(
        label: squeezedLabel,
        track: squeezedTrack,
        spacing: spacing,
        naturalLabelHeight: relaxedLabel.height,
        labelName
    )
    XCTAssertLessThan(
        squeezedTrack.height, naturalTrackHeight,
        "\(labelName) track should absorb the vertical deficit before the label does"
    )
}

final class PolishWaveTests: XCTestCase {

    // MARK: - Labeled-control label/track arrangement

    func testLabeledSliderKeepsLabelAboveTrack() async {
        await MainActor.run {
            polishRunLabeledControlScenario(
                "Slider",
                spacing: 6,
                gallerySize: Size(width: 230, height: 80),
                squeezedHeight: 34
            ) {
                Slider(value: .constant(0.65), in: 0...1) {
                    Text("Volume")
                }
            }
        }
    }

    func testLabeledSliderWithRangeLabelsKeepsLabelAboveTrack() async {
        await MainActor.run {
            polishRunLabeledControlScenario(
                "Slider(min/max)",
                spacing: 6,
                gallerySize: Size(width: 230, height: 80),
                squeezedHeight: 34
            ) {
                Slider(value: .constant(0.65), in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("100")
                }
            }
        }
    }

    func testLabeledProgressViewKeepsLabelAboveTrack() async {
        await MainActor.run {
            polishRunLabeledControlScenario(
                "ProgressView",
                spacing: 8,
                gallerySize: Size(width: 160, height: 50),
                squeezedHeight: 30
            ) {
                ProgressView("Loading", value: 0.4)
            }
        }
    }

    func testLabeledGaugeKeepsLabelAboveTrack() async {
        await MainActor.run {
            polishRunLabeledControlScenario(
                "Gauge",
                spacing: 8,
                gallerySize: Size(width: 200, height: 60),
                squeezedHeight: 32
            ) {
                Gauge(value: 0.5, in: 0...1) {
                    Text("Storage")
                }
            }
        }
    }

    // MARK: - Inspector presentation

    func testInspectorOverlayPaintsInDeferredPhaseWithoutScrim() async {
        await MainActor.run {
            let runtime = polishMakeRuntime()
            let context = polishMakeContext()
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = Text("BASE").inspector(isPresented: binding) {
                Text("DETAILS")
            }

            let node = polishMakeNode(view, runtime: runtime, context: context)
            node.frame = Rect(x: 0, y: 0, width: 800, height: 600)
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 2)
            let overlayContainer = node.children[1]
            XCTAssertEqual(overlayContainer.nodeTag, "inspector-overlay")
            XCTAssertTrue(
                overlayContainer.paintsInDeferredPhase,
                "Inspector must paint in the deferred phase so it always sits above base content"
            )
            XCTAssertEqual(
                overlayContainer.children.count, 1,
                "An inspector is non-modal: no blocking scrim may be added to the overlay"
            )
            XCTAssertFalse(
                overlayContainer.isHitTestVisible,
                "The overlay container must not intercept hits outside the inspector column"
            )
            node.removeFromParent()
        }
    }

    func testInspectorEscapeDismisses() async {
        await MainActor.run {
            let runtime = polishMakeRuntime()
            let context = polishMakeContext()
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = Text("BASE").inspector(isPresented: binding) {
                Button("CLOSE") {}
            }

            let node = polishMakeNode(view, runtime: runtime, context: context)
            node.frame = Rect(x: 0, y: 0, width: 800, height: 600)
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            guard let closeButton = polishFocusableNode(containing: "CLOSE", in: node) else {
                return XCTFail("Expected a focusable CLOSE button in the inspector")
            }
            runtime.requestFocus(closeButton)
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            XCTAssertFalse(presented, "Escape must dismiss the presented inspector")
            node.removeFromParent()
        }
    }

    func testInspectorDismissalRestoresFocusToPreviouslyFocusedControl() async {
        await MainActor.run {
            let runtime = polishMakeRuntime()
            let context = polishMakeContext()
            var presented = false
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            var name = "ADA"
            let nameBinding = Binding<String>(get: { name }, set: { name = $0 })
            let view = VStack {
                TextField("NAME", text: nameBinding)
            }
            .inspector(isPresented: binding) {
                Button("CLOSE") {}
            }

            let collapsedNode = polishMakeNode(view, runtime: runtime, context: context)
            collapsedNode.frame = Rect(x: 0, y: 0, width: 800, height: 600)
            runtime.root.addChild(collapsedNode)
            _ = runtime.renderFrame()

            guard let textField = polishFirstFocusableNode(in: collapsedNode) else {
                return XCTFail("Expected a focusable text field in the base content")
            }
            runtime.requestFocus(textField)
            XCTAssertTrue(textField.isFocused)

            // Present while the text field is still attached and focused so
            // the presentation captures it as the focus-restoration target.
            presented = true
            let presentedNode = polishMakeNode(view, runtime: runtime, context: context)
            presentedNode.frame = Rect(x: 0, y: 0, width: 800, height: 600)
            runtime.root.addChild(presentedNode)
            _ = runtime.renderFrame()

            guard let closeButton = polishFocusableNode(containing: "CLOSE", in: presentedNode) else {
                return XCTFail("Expected a focusable CLOSE button in the inspector")
            }
            runtime.requestFocus(closeButton)
            XCTAssertFalse(textField.isFocused)

            // Invoke the presentation's Escape handler directly: runtime-level
            // keyDown clears focus after dispatch, which is shared-runtime
            // behavior outside this presentation's control.
            closeButton.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            XCTAssertFalse(presented)
            XCTAssertTrue(
                runtime.focusedNode === textField,
                "Dismissing the inspector should restore focus to the control focused at presentation time"
            )

            collapsedNode.removeFromParent()
            presentedNode.removeFromParent()
        }
    }

    func testInspectorDismissalFallsBackToFirstBaseControlWhenNothingWasFocused() async {
        await MainActor.run {
            let runtime = polishMakeRuntime()
            let context = polishMakeContext()
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = VStack {
                Button("OPEN") {}
            }
            .inspector(isPresented: binding) {
                Button("CLOSE") {}
            }

            let node = polishMakeNode(view, runtime: runtime, context: context)
            node.frame = Rect(x: 0, y: 0, width: 800, height: 600)
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            guard let closeButton = polishFocusableNode(containing: "CLOSE", in: node) else {
                return XCTFail("Expected a focusable CLOSE button in the inspector")
            }
            guard let openButton = polishFocusableNode(containing: "OPEN", in: node) else {
                return XCTFail("Expected a focusable OPEN button in the base content")
            }
            runtime.requestFocus(closeButton)
            closeButton.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            XCTAssertFalse(presented)
            XCTAssertTrue(
                runtime.focusedNode === openButton,
                "With nothing focused at presentation time, dismissal should fall back to the first base control"
            )
            node.removeFromParent()
        }
    }
}
