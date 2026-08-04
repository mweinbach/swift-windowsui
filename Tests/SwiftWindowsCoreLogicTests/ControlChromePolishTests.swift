import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

// Chrome-polish regression tests for the stepper joined pair, segmented
// picker equal-width segments, checkbox/radio glyph centering, and list
// row selection chrome. Geometry invariants go through a real
// `RetainedViewRuntime` layout pass; the render smoke test rasterizes the
// same controls through the CPU rasterizer so the output can be inspected
// as PNGs (written to the OS temp directory).
final class ControlChromePolishTests: XCTestCase {
    // MARK: - Stepper joined pair

    func testStepperJoinedPairButtonsStayIndividuallyPressable() async {
        await MainActor.run {
            var value = 5
            let binding = Binding<Int>(
                get: { value },
                set: { value = $0 }
            )
            let node = makeChromeRuntimeNode(
                Stepper(value: binding, in: 0...10) {
                    Text("Count")
                }
                .frame(width: 200, height: 40)
            )
            assertChromeDescendantFramesWithinBounds(node)
            let row = tryUnwrap(node.children.first)
            // NSStepper is a vertical pair inside one bezel beside the
            // label: [label slot][bezel[increment][rule][decrement]].
            //
            // The rule between the halves is new: two flush buttons each
            // ringed by their own hairline put two adjacent borders at the
            // seam, and those cancelled into a flat smear with no divider in
            // it. The bezel owns the ring now (the painter re-draws a
            // parent's ring after its children) and the seam is a real node.
            XCTAssertEqual(row.children.count, 2)
            let bezel = row.children[1]
            XCTAssertEqual(bezel.children.count, 3)
            let increment = bezel.children[0]
            let divider = bezel.children[1]
            let decrement = bezel.children[2]

            // The halves sit flush against the rule, stacked up-chevron over
            // down-chevron, and keep the per-corner radii that follow the
            // bezel's own rounding.
            XCTAssertEqual(increment.resolvedFrame.maxY, divider.resolvedFrame.minY, accuracy: 0.51)
            XCTAssertEqual(divider.resolvedFrame.maxY, decrement.resolvedFrame.minY, accuracy: 0.51)
            XCTAssertEqual(
                increment.resolvedFrame.minX, decrement.resolvedFrame.minX, accuracy: 0.51)
            XCTAssertNotNil(decrement.cornerRadii)
            XCTAssertNotNil(increment.cornerRadii)

            // One bezel, one ring: the pair is closed by the container, and
            // the seam is a separator-marked hairline inside it.
            XCTAssertEqual(bezel.borderWidth, 1, accuracy: 0.01)
            XCTAssertEqual(bezel.cornerRadius, MacOSControlMetrics.Stepper.cornerRadius, accuracy: 0.01)
            XCTAssertTrue(divider.isSeparatorRule)
            XCTAssertGreaterThan(tryUnwrap(divider.backgroundColor).alpha, 0)
            XCTAssertLessThanOrEqual(divider.resolvedFrame.height, 1.01)

            // Both buttons remain individually focusable/pressable and keep
            // their action names for accessibility.
            for (button, name) in [(decrement, "Decrement"), (increment, "Increment")] {
                XCTAssertTrue(button.isFocusable)
                XCTAssertNotNil(button.onActivate)
                XCTAssertNotNil(button.onPointerDown)
                XCTAssertEqual(button.accessibilityLabel, name)
                // Joined chrome: the ring belongs to the bezel, not to each
                // half, and the elevated shadow is gone either way.
                XCTAssertEqual(button.borderWidth, 0, accuracy: 0.01)
                XCTAssertEqual(button.shadowColor.alpha, 0, accuracy: 0.01)
            }

            decrement.onActivate?()
            XCTAssertEqual(value, 4, "decrement should still fire its action")
            increment.onActivate?()
            XCTAssertEqual(value, 5, "increment should still fire its action")
        }
    }

    func testStepperJoinedPairLabelsHiddenStaysFlush() async {
        await MainActor.run {
            let node = makeChromeRuntimeNode(
                Stepper(value: .constant(5), in: 0...10) {
                    Text("Count")
                }
                .labelsHidden()
                .frame(width: 100, height: 40)
            )
            assertChromeDescendantFramesWithinBounds(node)
            let pair = tryUnwrap(node.children.first)
            // [increment][rule][decrement] inside the one bezel.
            XCTAssertEqual(pair.children.count, 3)
            XCTAssertEqual(
                pair.children[0].resolvedFrame.maxY,
                pair.children[1].resolvedFrame.minY,
                accuracy: 0.51,
                "labelsHidden stepper halves should sit flush, stacked vertically"
            )
            XCTAssertEqual(
                pair.children[1].resolvedFrame.maxY,
                pair.children[2].resolvedFrame.minY,
                accuracy: 0.51,
                "labelsHidden stepper halves should sit flush, stacked vertically"
            )
        }
    }

    // MARK: - Segmented picker equal widths

    func testSegmentedPickerSegmentsEqualWidthWithVariedLabels() async {
        await MainActor.run {
            for width in [200.0, 320.0] {
                let node = makeChromeRuntimeNode(
                    Picker("Mode", selection: .constant(1)) {
                        Text("A").tag(0)
                        Text("Medium").tag(1)
                        Text("Extra Long Option").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: width, height: 40)
                )
                assertChromeDescendantFramesWithinBounds(node)
                let stack = tryUnwrap(node.children.first)
                let shell = tryUnwrap(stack.children.last)
                XCTAssertEqual(shell.children.count, 3)
                let optionWidths = shell.children.map { $0.resolvedFrame.width }
                XCTAssertEqual(
                    optionWidths[0], optionWidths[1], accuracy: 0.51,
                    "segments should be equal width despite varied labels at \(width)pt")
                XCTAssertEqual(
                    optionWidths[1], optionWidths[2], accuracy: 0.51,
                    "segments should be equal width despite varied labels at \(width)pt")
                // Segments still exactly consume the shell interior
                // (4pt padding, 4pt spacing).
                let consumed = optionWidths.reduce(0, +) + (2 * 4) + (2 * 4)
                XCTAssertEqual(consumed, width, accuracy: 0.51)
            }
        }
    }

    func testSegmentedPickerSegmentsEqualWidthAtIntrinsicSize() async {
        await MainActor.run {
            let node = makeChromeRuntimeNode(
                Picker("Mode", selection: .constant(0)) {
                    Text("Off").tag(0)
                    Text("Automatic").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
            )
            assertChromeDescendantFramesWithinBounds(node)
            // Unpinned: the component node is the vertical label+picker
            // stack itself; find the recessed track by its chrome.
            let shell = tryUnwrap(
                firstNode(in: node) {
                    $0.cornerRadius == MacOSControlMetrics.Button.regularCornerRadius && $0.clipsToBounds
                        && $0.children.count == 2
                },
                message: "segmented track not found"
            )
            XCTAssertEqual(
                shell.children[0].resolvedFrame.width,
                shell.children[1].resolvedFrame.width,
                accuracy: 0.51,
                "unpinned segments should size to the widest label"
            )
        }
    }

    /// A segment's title cell is the segment, not the string.
    ///
    /// The title used to be centred by the segment's own stack, which sized
    /// the text node to the string's advance — a box with no tolerance at
    /// all. A pressed control is drawn at `ControlAnimationStyle.pressedScale`
    /// and its label is re-fitted to that scaled box, so every segment title
    /// ellipsized for as long as the pointer was down ("Three" → "Thr…"), and
    /// the gallery's pressed-picker entry certified it. The cell now spans the
    /// segment interior, which is both what NSSegmentedControl does and enough
    /// headroom that a 3% squeeze cannot reach the string.
    func testSegmentTitleCellSpansTheSegmentSoAPressCannotTruncateIt() async {
        await MainActor.run {
            let node = makeChromeRuntimeNode(
                Picker("Mode", selection: .constant(0)) {
                    Text("One").tag(0)
                    Text("Two").tag(1)
                    Text("Three").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
                .frame(width: 240, height: 30)
            )
            let shell = tryUnwrap(
                firstNode(in: node) {
                    $0.cornerRadius == MacOSControlMetrics.Button.regularCornerRadius && $0.clipsToBounds
                        && $0.children.count == 3
                },
                message: "segmented track not found"
            )
            // The segment's own horizontal padding, from `segmentedPickerNode`.
            let segmentHorizontalPadding: Double = 10
            for segment in shell.children {
                let label = tryUnwrap(segment.children.first, message: "segment title")
                XCTAssertNotNil(label.text, "a segment's only child is its title")
                XCTAssertEqual(
                    label.resolvedFrame.width,
                    segment.resolvedFrame.width - 2 * segmentHorizontalPadding,
                    accuracy: 0.51,
                    "the title cell is the segment interior, not the string's advance")
                XCTAssertEqual(
                    label.textStyle.alignment, .center,
                    "…and the string is centred inside that cell")
            }
        }
    }

    // MARK: - Checkbox / radio glyph centering

    func testCheckboxGlyphCentersInBoxAtDisplayScales() async {
        await MainActor.run {
            for displayScale in [1.0, 2.0] {
                for isOn in [true, false] {
                    let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                        of:
                            Toggle("Receive updates", isOn: .constant(isOn))
                            .toggleStyle(.checkbox)
                            .frame(width: 200, height: 36),
                        size: IntSize(width: 220, height: 60),
                        displayScale: displayScale
                    )
                    let box = tryUnwrap(
                        firstNode(in: snapshot.runtime.root) {
                            $0.preferredSize?.width == 20 && $0.preferredSize?.height == 20
                                && $0.cornerRadius == 4
                        },
                        message: "checkbox box not found"
                    )
                    let glyph = tryUnwrap(
                        box.children.first, message: "checkbox glyph slot not found")
                    // Child frames are relative to the box; the box must not
                    // be crushed, and the glyph must sit dead center inside it.
                    XCTAssertEqual(box.resolvedFrame.width, 20, accuracy: 0.51)
                    XCTAssertEqual(box.resolvedFrame.height, 20, accuracy: 0.51)
                    XCTAssertEqual(
                        glyph.resolvedFrame.midX, box.resolvedFrame.width * 0.5, accuracy: 0.51,
                        "checkbox glyph should be horizontally centered at \(displayScale)x")
                    XCTAssertEqual(
                        glyph.resolvedFrame.midY, box.resolvedFrame.height * 0.5, accuracy: 0.51,
                        "checkbox glyph should be vertically centered at \(displayScale)x")
                    if isOn {
                        // Checked state renders a real check glyph (native
                        // icon-font bitmap or drawn-vector fallback), not a
                        // blank placeholder.
                        XCTAssertTrue(
                            glyph.bitmapSurface != nil || glyph.canvasDraw != nil,
                            "checked checkbox should paint a check glyph")
                    }
                }
            }
        }
    }

    func testRadioDotCentersInCircleAtDisplayScales() async {
        await MainActor.run {
            for displayScale in [1.0, 2.0] {
                let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                    of:
                        Picker("Mode", selection: .constant(1)) {
                            Text("One").tag(0)
                            Text("Two").tag(1)
                        }
                        .pickerStyle(RadioGroupPickerStyle())
                        .frame(width: 200),
                    size: IntSize(width: 220, height: 140),
                    displayScale: displayScale
                )
                let circles = allNodes(in: snapshot.runtime.root) {
                    $0.preferredSize?.width == 20 && $0.preferredSize?.height == 20
                        && $0.cornerRadius == 10
                }
                XCTAssertEqual(circles.count, 2, "expected two radio circles")
                let selectedCircle = tryUnwrap(
                    circles.first(where: { !$0.children.isEmpty }),
                    message: "selected radio circle should contain a dot"
                )
                // The circle must not be crushed, and the dot must sit dead
                // center inside it (child frames are relative to the circle).
                XCTAssertEqual(selectedCircle.resolvedFrame.width, 20, accuracy: 0.51)
                XCTAssertEqual(selectedCircle.resolvedFrame.height, 20, accuracy: 0.51)
                let dot = selectedCircle.children[0]
                XCTAssertEqual(
                    dot.resolvedFrame.midX, selectedCircle.resolvedFrame.width * 0.5, accuracy: 0.51,
                    "radio dot should be horizontally centered at \(displayScale)x")
                XCTAssertEqual(
                    dot.resolvedFrame.midY, selectedCircle.resolvedFrame.height * 0.5, accuracy: 0.51,
                    "radio dot should be vertically centered at \(displayScale)x")
            }
        }
    }

    // MARK: - List row chrome

    func testListSelectedRowChromeComposesAtCompactWidth() async {
        await MainActor.run {
            let node = makeChromeRuntimeNode(
                List(selection: .constant(2 as Int?)) {
                    Text("Alpha").tag(1)
                    Text("Beta").tag(2)
                    Text("Gamma").tag(3)
                }
                .frame(width: 160, height: 120)
            )
            assertChromeDescendantFramesWithinBounds(node)
            let selectedRow = tryUnwrap(
                firstNode(in: node) { $0.nodeTag == "selection:2" },
                message: "selected row not found"
            )
            // A selected row is a solid accent fill with no border, as
            // macOS draws it — the 16% wash under a 52% outline it used to
            // paint read as an outlined chip rather than a selected row.
            XCTAssertEqual(selectedRow.borderWidth, 0)
            XCTAssertEqual(selectedRow.backgroundColor?.alpha ?? 0, 1, accuracy: 0.01)
            XCTAssertEqual(
                selectedRow.cornerRadius, MacOSControlMetrics.Button.regularCornerRadius, accuracy: 0.01)
            // 28pt minimum row height survives the compact width.
            XCTAssertGreaterThanOrEqual(selectedRow.resolvedFrame.height, 28 - 0.51)
            // Hover highlight stays installed.
            XCTAssertEqual(selectedRow.hoverEffect, .highlight)

            let unselectedRow = tryUnwrap(
                firstNode(in: node) { $0.nodeTag == "selection:1" },
                message: "unselected row not found"
            )
            // Unselected rows keep the same extents (constant border width)
            // with a fully transparent border.
            XCTAssertEqual(unselectedRow.borderColor.alpha, 0, accuracy: 0.01)
            XCTAssertEqual(unselectedRow.borderWidth, selectedRow.borderWidth, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(unselectedRow.resolvedFrame.height, 28 - 0.51)
        }
    }

    // MARK: - Render smoke test (inspectable PNGs)

    func testChromeReferenceRendersWritePNGs() async {
        await MainActor.run {
            for displayScale in [1.0, 2.0] {
                let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                    of: makeChromePolishScene(),
                    size: IntSize(width: 380, height: 560),
                    displayScale: displayScale
                )
                let bitmap = GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
                XCTAssertGreaterThan(bitmap.width, 0)
                XCTAssertGreaterThan(bitmap.height, 0)
                // The scene must not be a flat clear color.
                XCTAssertGreaterThan(distinctBitmapByteCount(in: bitmap.pixels), 16)

                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("swift-windowsui-chrome", isDirectory: true)
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("chrome-polish-\(Int(displayScale))x.png")
                try? bitmap.writePNG(to: url)
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                print("chrome polish reference render: \(url.path)")
            }
        }
    }

}

@MainActor
private func distinctBitmapByteCount(in pixels: Data) -> Int {
    var seen = Set<UInt8>()
    for byte in pixels {
        seen.insert(byte)
        if seen.count > 16 {
            return seen.count
        }
    }
    return seen.count
}

@MainActor
private func makeChromePolishScene() -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Toggle("Checked option", isOn: .constant(true))
            .toggleStyle(.checkbox)
        Toggle("Unchecked option", isOn: .constant(false))
            .toggleStyle(.checkbox)
        Picker("Mode", selection: .constant(1)) {
            Text("One").tag(0)
            Text("Two").tag(1)
        }
        .pickerStyle(RadioGroupPickerStyle())
        .frame(height: 80)
        Stepper(value: .constant(5), in: 0...10) {
            Text("Count: 5")
        }
        Picker("Color", selection: .constant(1)) {
            Text("Red").tag(0)
            Text("Green").tag(1)
            Text("Blue").tag(2)
        }
        .pickerStyle(SegmentedPickerStyle())
        List(selection: .constant(2 as Int?)) {
            Text("Alpha").tag(1)
            Text("Beta").tag(2)
            Text("Gamma").tag(3)
        }
        .frame(height: 120)
    }
    .padding(12)
    .frame(width: 356)
}

@MainActor
private func makeChromeRuntimeNode<V: View>(
    _ view: V,
    canvas: Size = Size(width: 480, height: 360)
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { canvas }, invalidateHandler: {})
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(canvas.width), height: Int32(canvas.height)))
    _ = runtime.renderFrame()
    return node
}

@MainActor
private func firstNode(in node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
    if predicate(node) {
        return node
    }
    for child in node.children {
        if let match = firstNode(in: child, where: predicate) {
            return match
        }
    }
    return nil
}

@MainActor
private func allNodes(in node: ViewNode, where predicate: (ViewNode) -> Bool) -> [ViewNode] {
    var matches: [ViewNode] = predicate(node) ? [node] : []
    for child in node.children {
        matches.append(contentsOf: allNodes(in: child, where: predicate))
    }
    return matches
}

@MainActor
private func assertChromeDescendantFramesWithinBounds(
    _ node: ViewNode,
    tolerance: Double = 0.51,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let parentSize = node.resolvedFrame.size
    for child in node.children {
        let frame = child.resolvedFrame
        XCTAssertGreaterThanOrEqual(
            frame.minX, -tolerance, "child overflows the leading edge", file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            frame.minY, -tolerance, "child overflows the top edge", file: file, line: line)
        XCTAssertLessThanOrEqual(
            frame.maxX, parentSize.width + tolerance, "child overflows the trailing edge", file: file, line: line)
        XCTAssertLessThanOrEqual(
            frame.maxY, parentSize.height + tolerance, "child overflows the bottom edge", file: file, line: line)
        assertChromeDescendantFramesWithinBounds(child, tolerance: tolerance, file: file, line: line)
    }
}

private func tryUnwrap<T>(_ value: T?, message: String? = nil, file: StaticString = #filePath, line: UInt = #line) -> T
{
    guard let value else {
        XCTFail(message ?? "expected a non-nil value", file: file, line: line)
        fatalError("unwrapped nil")
    }
    return value
}
