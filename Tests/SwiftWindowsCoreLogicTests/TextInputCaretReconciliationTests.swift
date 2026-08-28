import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
private struct CaretReconciliationFixture {
    let clock: RuntimeTestClock
    let size = IntSize(width: 120, height: 48)
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let field: ViewNode

    init(children: @escaping @MainActor () -> [ViewNode]) throws {
        let bounds = Rect(x: 0, y: 0, width: 120, height: 48)
        let clock = RuntimeTestClock()
        let runtime = RetainedViewRuntime(clearColor: .black, root: ViewNode(frame: bounds))
        runtime.clock = { clock.now }
        let host = ComponentHost(runtime: runtime)
        host.setComponents {
            [
                Component { _ in
                    let field = ViewNode(
                        frame: bounds, preferredSize: bounds.size, isFocusable: true,
                        children: children())
                    field.accessibilityTraits.insert(.isTextInput)
                    return field
                }
            ]
        }
        _ = runtime.renderScene(at: clock.now)
        let field = try XCTUnwrap(runtime.root.children.first)
        runtime.requestFocus(field)
        XCTAssertTrue(runtime.focusedNode === field)
        self.clock = clock
        self.runtime = runtime
        self.host = host
        self.field = field
    }

    func bitmap() -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(runtime.renderScene(at: clock.now), size: size)
    }

    @discardableResult
    func tick(at timestamp: Double) -> Bool {
        clock.now = timestamp
        return runtime.tickAnimations(at: timestamp)
    }
}

/// Source nodes describe the role. Only ComponentHost may transfer that role
/// onto the retained identities; the tests never repair a marker after adoption.
@MainActor
final class TextInputCaretReconciliationTests: XCTestCase {
    private static let blue = Color(red: 0, green: 0, blue: 1)
    private static let red = Color(red: 1, green: 0, blue: 0)
    private static let green = Color(red: 0, green: 1, blue: 0)
    private static let purple = Color(red: 1, green: 0, blue: 1)

    private static func style(color: Color, size: Double) -> PixelTextStyle {
        PixelTextStyle(
            color: color, scale: 1, alignment: .leading, verticalAlignment: .top,
            insets: EdgeInsets(top: 2, leading: 2, bottom: 6, trailing: 2), nativeFontSize: size)
    }

    private static func sourceNode(
        frame: Rect, color: Color, text: String?, style: PixelTextStyle, isCaret: Bool
    ) -> ViewNode {
        let node = ViewNode(
            frame: frame, backgroundColor: color, text: text, textStyle: style,
            preferredSize: frame.size, isHitTestVisible: false)
        node.isTextInputCaret = isCaret
        return node
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, color: Color,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let actual = try XCTUnwrap(bitmap.colorAt(x: x, y: y), file: file, line: line)
        XCTAssertEqual(actual.red, color.red, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(actual.green, color.green, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(actual.blue, color.blue, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(actual.alpha, color.alpha, accuracy: 1 / 255, file: file, line: line)
    }

    func testSameSlotCopiesAndClearsCaretMarkerWithoutBlinkingTheRestoredLabel() async throws {
        var isCaret = false
        var latestSource: ViewNode?
        let labelFrame = Rect(x: 4, y: 4, width: 40, height: 32)
        let caretFrame = Rect(x: 4, y: 4, width: 2, height: 18)
        let labelStyle = Self.style(color: .white, size: 10)
        let caretStyle = Self.style(color: Self.red, size: 18)
        let fixture = try CaretReconciliationFixture {
            let source = Self.sourceNode(
                frame: isCaret ? caretFrame : labelFrame,
                color: isCaret ? Self.red : Self.blue, text: isCaret ? nil : "Label",
                style: isCaret ? caretStyle : labelStyle, isCaret: isCaret)
            latestSource = source
            return [source]
        }
        let retained = try XCTUnwrap(fixture.field.children.first)
        XCTAssertTrue(latestSource === retained)
        XCTAssertFalse(retained.isTextInputCaret)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
        fixture.tick(at: 0)
        XCTAssertFalse(fixture.tick(at: 0.7))
        XCTAssertEqual(retained.opacity, 1)
        try assertPixel(fixture.bitmap(), x: 5, y: 32, color: Self.blue)

        isCaret = true
        fixture.host.reload()
        XCTAssertTrue(fixture.runtime.root.children.first === fixture.field)
        XCTAssertEqual(fixture.field.children.count, 1)
        XCTAssertTrue(fixture.field.children.first === retained)
        XCTAssertFalse(latestSource === retained)
        XCTAssertTrue(try XCTUnwrap(latestSource).isTextInputCaret)
        XCTAssertTrue(retained.isTextInputCaret)
        XCTAssertNil(retained.text)
        XCTAssertEqual(retained.frame, caretFrame)
        XCTAssertEqual(retained.preferredSize, caretFrame.size)
        XCTAssertEqual(retained.textStyle, caretStyle)
        XCTAssertEqual(retained.backgroundColor, Self.red)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.field)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)

        fixture.tick(at: 0.7)
        XCTAssertEqual(retained.opacity, 1)
        try assertPixel(fixture.bitmap(), x: 5, y: 8, color: Self.red)
        XCTAssertTrue(fixture.tick(at: 1.4))
        XCTAssertEqual(retained.opacity, 0)
        XCTAssertTrue(fixture.runtime.dirtyFlags.contains(.paint))
        try assertPixel(fixture.bitmap(), x: 5, y: 8, color: .black)

        // Reset the source role while the reused caret is in its off phase.
        // Reconciliation must restore the label's opacity and clear the marker.
        isCaret = false
        fixture.host.reload()
        XCTAssertTrue(fixture.field.children.first === retained)
        XCTAssertFalse(latestSource === retained)
        XCTAssertFalse(try XCTUnwrap(latestSource).isTextInputCaret)
        XCTAssertFalse(retained.isTextInputCaret)
        XCTAssertEqual(retained.text, "Label")
        XCTAssertEqual(retained.frame, labelFrame)
        XCTAssertEqual(retained.preferredSize, labelFrame.size)
        XCTAssertEqual(retained.textStyle, labelStyle)
        XCTAssertEqual(retained.backgroundColor, Self.blue)
        XCTAssertEqual(retained.opacity, 1)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.field)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
        try assertPixel(fixture.bitmap(), x: 5, y: 32, color: Self.blue)

        for timestamp in [1.4, 2.1, 2.6] {
            XCTAssertFalse(fixture.tick(at: timestamp))
            XCTAssertEqual(retained.opacity, 1)
            XCTAssertFalse(fixture.runtime.hasActiveAnimations)
            try assertPixel(fixture.bitmap(), x: 5, y: 32, color: Self.blue)
        }
    }

    func testPositionalSwapKeepsOneCaretAndBlinksItsNewSlotInsteadOfThePlaceholder() async throws {
        var showsPlaceholder = false
        var latestSources: [ViewNode] = []
        let segmentFrame = Rect(x: 4, y: 4, width: 28, height: 32)
        let oldCaretFrame = Rect(x: 40, y: 4, width: 2, height: 16)
        let newCaretFrame = Rect(x: 4, y: 4, width: 4, height: 24)
        let placeholderFrame = Rect(x: 12, y: 4, width: 48, height: 32)
        let segmentStyle = Self.style(color: .white, size: 10)
        let oldCaretStyle = Self.style(color: Self.green, size: 16)
        let newCaretStyle = Self.style(color: Self.red, size: 24)
        let placeholderStyle = Self.style(color: Self.green, size: 14)
        let fixture = try CaretReconciliationFixture {
            let sources: [ViewNode]
            if showsPlaceholder {
                sources = [
                    Self.sourceNode(
                        frame: newCaretFrame, color: Self.red, text: nil,
                        style: newCaretStyle, isCaret: true),
                    Self.sourceNode(
                        frame: placeholderFrame, color: Self.purple, text: "Hint",
                        style: placeholderStyle, isCaret: false),
                ]
            } else {
                sources = [
                    Self.sourceNode(
                        frame: segmentFrame, color: Self.blue, text: "A",
                        style: segmentStyle, isCaret: false),
                    Self.sourceNode(
                        frame: oldCaretFrame, color: Self.green, text: nil,
                        style: oldCaretStyle, isCaret: true),
                ]
            }
            latestSources = sources
            return sources
        }
        XCTAssertEqual(fixture.field.children.count, 2)
        let firstSlot = try XCTUnwrap(fixture.field.children.first)
        let secondSlot = try XCTUnwrap(fixture.field.children.last)
        XCTAssertFalse(firstSlot === secondSlot)
        XCTAssertFalse(firstSlot.isTextInputCaret)
        XCTAssertTrue(secondSlot.isTextInputCaret)
        XCTAssertEqual(fixture.field.children.filter(\.isTextInputCaret).count, 1)
        fixture.tick(at: 0)
        try assertPixel(fixture.bitmap(), x: 41, y: 8, color: Self.green)
        XCTAssertTrue(fixture.tick(at: 0.7))
        XCTAssertEqual(firstSlot.opacity, 1)
        XCTAssertEqual(secondSlot.opacity, 0)
        let beforeSwap = fixture.bitmap()
        try assertPixel(beforeSwap, x: 5, y: 32, color: Self.blue)
        try assertPixel(beforeSwap, x: 41, y: 8, color: .black)

        showsPlaceholder = true
        fixture.host.reload()
        XCTAssertTrue(fixture.runtime.root.children.first === fixture.field)
        XCTAssertEqual(fixture.field.children.count, 2)
        XCTAssertTrue(fixture.field.children.first === firstSlot)
        XCTAssertTrue(fixture.field.children.last === secondSlot)
        XCTAssertFalse(latestSources.first === firstSlot)
        XCTAssertFalse(latestSources.last === secondSlot)
        XCTAssertEqual(latestSources.map(\.isTextInputCaret), [true, false])
        XCTAssertEqual(fixture.field.children.map(\.isTextInputCaret), [true, false])
        XCTAssertEqual(fixture.field.children.filter(\.isTextInputCaret).count, 1)
        XCTAssertNil(firstSlot.text)
        XCTAssertEqual(firstSlot.frame, newCaretFrame)
        XCTAssertEqual(firstSlot.preferredSize, newCaretFrame.size)
        XCTAssertEqual(firstSlot.textStyle, newCaretStyle)
        XCTAssertEqual(firstSlot.backgroundColor, Self.red)
        XCTAssertEqual(secondSlot.text, "Hint")
        XCTAssertEqual(secondSlot.frame, placeholderFrame)
        XCTAssertEqual(secondSlot.preferredSize, placeholderFrame.size)
        XCTAssertEqual(secondSlot.textStyle, placeholderStyle)
        XCTAssertEqual(secondSlot.backgroundColor, Self.purple)
        XCTAssertEqual(firstSlot.opacity, 1)
        XCTAssertEqual(secondSlot.opacity, 1)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.field)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)

        fixture.tick(at: 1.2)
        let on = fixture.bitmap()
        try assertPixel(on, x: 5, y: 8, color: Self.red)
        try assertPixel(on, x: 13, y: 32, color: Self.purple)
        XCTAssertTrue(fixture.tick(at: 1.7))
        XCTAssertEqual(firstSlot.opacity, 0)
        XCTAssertEqual(secondSlot.opacity, 1)
        XCTAssertTrue(fixture.runtime.dirtyFlags.contains(.paint))
        let off = fixture.bitmap()
        try assertPixel(off, x: 5, y: 8, color: .black)
        try assertPixel(off, x: 13, y: 32, color: Self.purple)
        XCTAssertTrue(fixture.tick(at: 2.2))
        XCTAssertEqual(firstSlot.opacity, 1)
        XCTAssertEqual(secondSlot.opacity, 1)
        let onAgain = fixture.bitmap()
        try assertPixel(onAgain, x: 5, y: 8, color: Self.red)
        try assertPixel(onAgain, x: 13, y: 32, color: Self.purple)
    }
}
