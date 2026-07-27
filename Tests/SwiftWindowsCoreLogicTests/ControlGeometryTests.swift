import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

// Responsive-geometry regression tests for Supported controls. Each control is
// pinned with `.frame(width:height:)` (the same idiom the gallery uses) at
// compact, regular, and expanded widths, then laid out through a real
// `RetainedViewRuntime.renderFrame()` pass. The shared invariants are:
//   - no descendant frame escapes its parent's bounds,
//   - horizontal-row labels keep their intrinsic width where they fit,
//   - track-like children (slider/progress/gauge tracks, segmented options)
//     consume the remaining width instead of overflowing or underfilling.
final class ControlGeometryTests: XCTestCase {
    // MARK: - Button

    func testButtonLabelStaysWithinBoundsAtAllWidths() async {
        await MainActor.run {
            for width in [100.0, 200.0, 320.0] {
                let node = makeRuntimeNode(
                    Button("Tap Me") {}
                        .frame(width: width, height: 40)
                )
                let button = tryUnwrap(node.children.first)
                assertDescendantFramesWithinBounds(node)
                let label = tryUnwrap(firstTextNode(in: node))
                // The button stretches its centered label to the pinned width.
                XCTAssertEqual(label.resolvedFrame.width, width, accuracy: 0.51)
                // The focus/press/activate lifecycle hooks must stay intact.
                XCTAssertTrue(button.isFocusable)
                XCTAssertNotNil(button.onActivate)
                XCTAssertNotNil(button.onPointerDown)
            }
        }
    }

    // MARK: - Toggle

    func testToggleKeepsLabelIntrinsicAndSwitchFixedAcrossWidths() async {
        await MainActor.run {
            var labelWidths: [Double] = []
            var switchWidths: [Double] = []
            for width in [150.0, 200.0, 320.0] {
                let node = makeRuntimeNode(
                    Toggle("Enabled", isOn: .constant(true))
                        .frame(width: width, height: 36)
                )
                assertDescendantFramesWithinBounds(node)
                let row = tryUnwrap(node.children.first)
                let label = tryUnwrap(firstTextNode(in: row))
                let switchNode = tryUnwrap(row.children.last)
                labelWidths.append(label.resolvedFrame.width)
                switchWidths.append(switchNode.resolvedFrame.width)
                XCTAssertEqual(
                    switchNode.resolvedFrame.width,
                    switchNode.preferredSize?.width ?? -1,
                    accuracy: 0.51,
                    "switch should keep its preferred width at \(width)pt"
                )
            }
            XCTAssertEqual(labelWidths[0], labelWidths[1], accuracy: 0.51)
            XCTAssertEqual(labelWidths[1], labelWidths[2], accuracy: 0.51)
            XCTAssertEqual(switchWidths[0], switchWidths[1], accuracy: 0.51)
            XCTAssertEqual(switchWidths[1], switchWidths[2], accuracy: 0.51)
        }
    }

    func testToggleThumbStaysInsideCrushedTrackAtCompactWidth() async {
        await MainActor.run {
            // An 80pt row forces the switch well below its 52pt preference;
            // the thumb must re-resolve into the crushed track instead of
            // overflowing it.
            for isOn in [true, false] {
                let node = makeRuntimeNode(
                    Toggle("Enabled", isOn: .constant(isOn))
                        .frame(width: 80, height: 36)
                )
                assertDescendantFramesWithinBounds(node)
                let row = tryUnwrap(node.children.first)
                let switchNode = tryUnwrap(row.children.last)
                let track = tryUnwrap(switchNode.children.first)
                let thumb = tryUnwrap(track.children.first)
                XCTAssertGreaterThanOrEqual(thumb.resolvedFrame.minX, -0.51)
                XCTAssertLessThanOrEqual(
                    thumb.resolvedFrame.maxX,
                    track.resolvedFrame.width + 0.51
                )
            }
        }
    }

    // MARK: - Stepper

    func testStepperKeepsGeometryWithinBoundsAcrossWidths() async {
        await MainActor.run {
            for width in [150.0, 200.0, 320.0] {
                let node = makeRuntimeNode(
                    Stepper(value: .constant(5), in: 0...10) {
                        Text("Count: 5")
                    }
                    .frame(width: width, height: 40)
                )
                assertDescendantFramesWithinBounds(node)
                let row = tryUnwrap(node.children.first)
                // Joined pair: [label slot, decrement, increment] with the
                // buttons flush against each other.
                XCTAssertEqual(row.children.count, 3)
                let decrement = row.children[1]
                let increment = row.children[2]
                XCTAssertEqual(
                    decrement.resolvedFrame.width,
                    increment.resolvedFrame.width,
                    accuracy: 0.51,
                    "stepper buttons should share width equally at \(width)pt"
                )
                XCTAssertEqual(
                    decrement.resolvedFrame.maxX,
                    increment.resolvedFrame.minX,
                    accuracy: 0.51,
                    "stepper buttons should sit flush as a joined pair at \(width)pt"
                )
                // Per-corner radii: rounded outer corners, square joined edge.
                let decrementRadii = tryUnwrap(decrement.cornerRadii)
                XCTAssertGreaterThan(decrementRadii.topLeft, 0)
                XCTAssertGreaterThan(decrementRadii.bottomLeft, 0)
                XCTAssertEqual(decrementRadii.topRight, 0, accuracy: 0.01)
                XCTAssertEqual(decrementRadii.bottomRight, 0, accuracy: 0.01)
                let incrementRadii = tryUnwrap(increment.cornerRadii)
                XCTAssertEqual(incrementRadii.topLeft, 0, accuracy: 0.01)
                XCTAssertEqual(incrementRadii.bottomLeft, 0, accuracy: 0.01)
                XCTAssertGreaterThan(incrementRadii.topRight, 0)
                XCTAssertGreaterThan(incrementRadii.bottomRight, 0)
                XCTAssertGreaterThan(tryUnwrap(firstTextNode(in: row)).resolvedFrame.width, 0)
            }
        }
    }

    func testStepperKeepsLabelAndButtonsIntrinsicWhereTheyFit() async {
        await MainActor.run {
            var labelWidths: [Double] = []
            for width in [200.0, 320.0] {
                let node = makeRuntimeNode(
                    Stepper(value: .constant(5), in: 0...10) {
                        Text("Count: 5")
                    }
                    .frame(width: width, height: 40)
                )
                let row = tryUnwrap(node.children.first)
                labelWidths.append(tryUnwrap(firstTextNode(in: row)).resolvedFrame.width)
                for index in [1, 2] {
                    let button = row.children[index]
                    XCTAssertEqual(
                        button.resolvedFrame.width,
                        button.preferredSize?.width ?? -1,
                        accuracy: 0.51,
                        "stepper button should keep its preferred width at \(width)pt"
                    )
                }
            }
            XCTAssertEqual(labelWidths[0], labelWidths[1], accuracy: 0.51)
        }
    }

    // MARK: - ProgressView

    func testProgressViewUnlabeledTrackReResolvesToPinnedWidth() async {
        await MainActor.run {
            for width in [140.0, 200.0, 320.0] {
                let node = makeRuntimeNode(
                    ProgressView(value: 0.6)
                        .frame(width: width, height: 36)
                )
                assertDescendantFramesWithinBounds(node)
                let bar = tryUnwrap(node.children.first)
                XCTAssertEqual(bar.resolvedFrame.width, width, accuracy: 0.51)
                let track = tryUnwrap(bar.children.first)
                let fill = tryUnwrap(bar.children.last)
                XCTAssertEqual(track.resolvedFrame.width, width, accuracy: 0.51)
                XCTAssertEqual(fill.resolvedFrame.width, width * 0.6, accuracy: 0.6)
                // The bar stays vertically centered inside the pinned slot.
                XCTAssertEqual(
                    track.resolvedFrame.midY,
                    bar.resolvedFrame.height * 0.5,
                    accuracy: 0.51
                )
            }
        }
    }

    func testProgressViewLabeledBarConsumesFullWidth() async {
        await MainActor.run {
            for width in [160.0, 240.0, 320.0] {
                let node = makeRuntimeNode(
                    ProgressView("Loading", value: 0.4)
                        .frame(width: width, height: 50)
                )
                assertDescendantFramesWithinBounds(node)
                let stack = tryUnwrap(node.children.first)
                let bar = tryUnwrap(stack.children.last)
                XCTAssertEqual(bar.resolvedFrame.width, width, accuracy: 0.51)
                let track = tryUnwrap(bar.children.first)
                let fill = tryUnwrap(bar.children.last)
                XCTAssertEqual(track.resolvedFrame.width, width, accuracy: 0.51)
                XCTAssertEqual(fill.resolvedFrame.width, width * 0.4, accuracy: 0.6)
            }
        }
    }

    func testProgressViewCircularDotsStayContainedAtCompactSizes() async {
        await MainActor.run {
            for side in [80.0, 28.0, 16.0] {
                let node = makeRuntimeNode(
                    ProgressView(value: 0.5)
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: side, height: side)
                )
                assertDescendantFramesWithinBounds(node)
            }
        }
    }

    // MARK: - Gauge

    func testGaugeLinearBarConsumesFullWidthAndBoundsLabelsPinEdges() async {
        await MainActor.run {
            for width in [200.0, 320.0] {
                let node = makeRuntimeNode(
                    Gauge(value: 0.5, in: 0...1) {
                        Text("CPU")
                    } currentValueLabel: {
                        Text("50%")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("100")
                    }
                    .frame(width: width, height: 80)
                )
                assertDescendantFramesWithinBounds(node)
                let stack = tryUnwrap(node.children.first)
                XCTAssertEqual(stack.children.count, 3)
                let bar = stack.children[1]
                let track = tryUnwrap(bar.children.first)
                let fill = tryUnwrap(bar.children.last)
                XCTAssertEqual(track.resolvedFrame.width, width, accuracy: 0.51)
                XCTAssertEqual(fill.resolvedFrame.width, width * 0.5, accuracy: 0.6)

                let boundsRow = stack.children[2]
                XCTAssertEqual(boundsRow.children.count, 3)
                let minimumLabel = boundsRow.children[0]
                let spacer = boundsRow.children[1]
                let maximumLabel = boundsRow.children[2]
                XCTAssertEqual(minimumLabel.resolvedFrame.minX, 0, accuracy: 0.51)
                XCTAssertEqual(
                    maximumLabel.resolvedFrame.maxX,
                    width,
                    accuracy: 0.51,
                    "maximum label should pin to the trailing edge at \(width)pt"
                )
                XCTAssertGreaterThan(
                    spacer.resolvedFrame.width,
                    0,
                    "spacer should consume the remaining row width at \(width)pt"
                )
            }
        }
    }

    // MARK: - Picker (segmented)

    func testPickerSegmentedOptionsConsumeRemainingWidth() async {
        await MainActor.run {
            for width in [160.0, 240.0, 320.0] {
                let node = makeRuntimeNode(
                    Picker("Color", selection: .constant(1)) {
                        Text("Red").tag(0)
                        Text("Green").tag(1)
                        Text("Blue").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: width, height: 40)
                )
                assertDescendantFramesWithinBounds(node)
                let stack = tryUnwrap(node.children.first)
                let shell = tryUnwrap(stack.children.last)
                XCTAssertEqual(shell.resolvedFrame.width, width, accuracy: 0.51)
                XCTAssertEqual(shell.children.count, 3)
                let optionWidths = shell.children.map { $0.resolvedFrame.width }
                for optionWidth in optionWidths {
                    XCTAssertGreaterThan(optionWidth, 0)
                }
                // macOS segmented controls give every segment the same width.
                XCTAssertEqual(
                    optionWidths[0], optionWidths[1], accuracy: 0.51,
                    "segments should be equal width at \(width)pt")
                XCTAssertEqual(
                    optionWidths[1], optionWidths[2], accuracy: 0.51,
                    "segments should be equal width at \(width)pt")
                // Options consume the full shell interior (4pt padding, 4pt spacing).
                let consumed = optionWidths.reduce(0, +) + (2 * 4) + (2 * 4)
                XCTAssertEqual(consumed, width, accuracy: 0.51)
                XCTAssertEqual(shell.children[0].resolvedFrame.minX, 4, accuracy: 0.51)
                XCTAssertEqual(
                    shell.children[2].resolvedFrame.maxX,
                    width - 4,
                    accuracy: 0.51
                )
            }
        }
    }

    // MARK: - ColorPicker

    func testColorPickerKeepsSwatchIntrinsicAndRowContained() async {
        await MainActor.run {
            for width in [200.0, 260.0, 320.0] {
                let node = makeRuntimeNode(
                    ColorPicker("Accent", selection: .constant(.red))
                        .frame(width: width, height: 40)
                )
                assertDescendantFramesWithinBounds(node)
                let row = tryUnwrap(node.children.first)
                let control = tryUnwrap(row.children.last)
                let swatch = tryUnwrap(control.children.first)
                if width >= 260 {
                    XCTAssertEqual(
                        swatch.resolvedFrame.width,
                        swatch.preferredSize?.width ?? -1,
                        accuracy: 0.51,
                        "swatch should keep its preferred width at \(width)pt"
                    )
                    XCTAssertEqual(
                        swatch.resolvedFrame.height,
                        swatch.preferredSize?.height ?? -1,
                        accuracy: 0.51
                    )
                }
            }
        }
    }

    // MARK: - DatePicker

    func testDatePickerKeepsLabelAndValueWithinBoundsAcrossWidths() async {
        await MainActor.run {
            let date = Date(timeIntervalSince1970: 1_768_454_400)
            for width in [200.0, 320.0] {
                let node = makeRuntimeNode(
                    DatePicker("Date", selection: .constant(date))
                        .frame(width: width, height: 40)
                )
                assertDescendantFramesWithinBounds(node)
                let row = tryUnwrap(node.children.first)
                XCTAssertEqual(row.children.count, 2)
                let label = row.children[0]
                let value = row.children[1]
                XCTAssertGreaterThan(label.resolvedFrame.width, 0)
                XCTAssertGreaterThan(value.resolvedFrame.width, 0)
                XCTAssertNotNil(value.text ?? firstTextNode(in: value)?.text)
            }
        }
    }

    // MARK: - Slider (regression anchor for the labeled-slider pattern)

    func testLabeledSliderTrackMatchesResolvedWidthAtGalleryCanvas() async {
        await MainActor.run {
            let node = makeRuntimeNode(
                Slider(value: .constant(0.5), in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("1")
                }
                .frame(width: 244, height: 108)
            )
            assertDescendantFramesWithinBounds(node)
            let stack = tryUnwrap(node.children.first)
            let row = tryUnwrap(stack.children.last)
            XCTAssertEqual(row.children.count, 3)
            let slider = row.children[1]
            let track = tryUnwrap(slider.children.first)
            XCTAssertEqual(
                track.resolvedFrame.width,
                slider.resolvedFrame.width,
                accuracy: 0.51
            )
            // Range labels keep their intrinsic width while the track flexes.
            let minimumLabel = row.children[0]
            let maximumLabel = row.children[2]
            XCTAssertEqual(
                minimumLabel.resolvedFrame.width,
                minimumLabel.preferredSize?.width ?? minimumLabel.resolvedFrame.width,
                accuracy: 0.51
            )
            XCTAssertGreaterThan(maximumLabel.resolvedFrame.width, 0)
        }
    }
}

@MainActor
private func makeRuntimeNode<V: View>(
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
private func firstTextNode(in node: ViewNode) -> ViewNode? {
    if node.text != nil {
        return node
    }
    for child in node.children {
        if let match = firstTextNode(in: child) {
            return match
        }
    }
    return nil
}

@MainActor
private func assertDescendantFramesWithinBounds(
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
        assertDescendantFramesWithinBounds(child, tolerance: tolerance, file: file, line: line)
    }
}

private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
    guard let value else {
        XCTFail("expected a non-nil value", file: file, line: line)
        fatalError("unwrapped nil")
    }
    return value
}
