import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class RetainedTextCaretBoundaryTests: XCTestCase {
    func testEmptyCaretClampsEveryOffsetWithoutRequestingNativeLayout() async {
        let previous = NativeTextRenderer.testingOverrides
        defer { NativeTextRenderer.testingOverrides = previous }
        var layoutCalls = 0
        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in
            layoutCalls += 1
            return nil
        }

        for scale in [0.0, 1.0, 2.0] {
            let style = PixelTextStyle(color: .white, scale: scale, letterSpacing: 3)
            for displayScale in [1.0, 1.25, 2.0] {
                for offset in [Int.min, -1, 0, 1, Int.max] {
                    XCTAssertEqual(
                        RetainedTextMetrics.caretX(
                            atOffset: offset, in: "", style: style, displayScale: displayScale),
                        0)
                }
                for x in [-100.0, 0.0, 100.0] {
                    XCTAssertEqual(
                        RetainedTextMetrics.characterOffset(
                            atX: x, in: "", style: style, displayScale: displayScale),
                        0)
                }
            }
        }
        XCTAssertEqual(layoutCalls, 0, "Empty text has one origin boundary without consulting native layout")
    }

    func testNonemptyPixelBoundariesKeepGraphemeOffsetsAndClamping() async {
        let previous = NativeTextRenderer.testingOverrides
        defer { NativeTextRenderer.testingOverrides = previous }
        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
        let style = PixelTextStyle(color: .white, scale: 2, letterSpacing: 1)
        let text = "A👩🏽‍💻é"
        XCTAssertEqual(text.count, 3)
        let expected = [0.0, 10.0, 22.0, 34.0]
        XCTAssertEqual(PixelFont.glyphWidth, 5)
        for offset in 0...3 {
            XCTAssertEqual(RetainedTextMetrics.caretX(atOffset: offset, in: text, style: style), expected[offset])
            XCTAssertEqual(RetainedTextMetrics.characterOffset(atX: expected[offset], in: text, style: style), offset)
        }
        XCTAssertEqual(RetainedTextMetrics.caretX(atOffset: Int.min, in: text, style: style), 0)
        XCTAssertEqual(RetainedTextMetrics.caretX(atOffset: Int.max, in: text, style: style), 34)
    }

    func testFocusedFieldsReportAnEmptyCaretAfterSelectAllAndBackspace() async throws {
        let previous = NativeTextRenderer.testingOverrides
        defer { NativeTextRenderer.testingOverrides = previous }
        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
        NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in nil }

        for secure in [false, true] {
            for initialText in ["Operator", "👩🏽‍💻"] {
                var value = initialText
                let (runtime, field) = makeField(
                    secure: secure, text: Binding(get: { value }, set: { value = $0 }))
                XCTAssertTrue(runtime.focusedNode === field)
                field.textInputCaretOffset = 0
                let origin = try XCTUnwrap(runtime.focusedTextInputCaretRect).origin

                runtime.keyDown(
                    KeyboardEvent(keyCode: 0x41, modifiers: [.control], textInputDelivery: .systemCharacter))
                XCTAssertEqual(field.textInputSelection?.indices, .range(0..<initialText.count))
                runtime.keyDown(
                    KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue, textInputDelivery: .systemCharacter))

                XCTAssertEqual(value, "")
                XCTAssertEqual(field.textInputCaretOffset, 0)
                XCTAssertNil(field.textInputSelection)
                XCTAssertTrue(runtime.focusedNode === field)
                let caret = try XCTUnwrap(runtime.focusedTextInputCaretRect)
                assertEmptyCaret(caret, at: origin)
                _ = runtime.renderScene()
                assertEmptyCaret(try XCTUnwrap(runtime.focusedTextInputCaretRect), at: origin)
            }
        }
    }

    func testInitiallyEmptyFieldsReportTheirContentOriginCaret() async throws {
        let previous = NativeTextRenderer.testingOverrides
        defer { NativeTextRenderer.testingOverrides = previous }
        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
        NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in nil }

        for secure in [false, true] {
            let (runtime, field) = makeField(secure: secure, text: .constant(""))
            XCTAssertTrue(runtime.focusedNode === field)
            let caret = try XCTUnwrap(runtime.focusedTextInputCaretRect)
            XCTAssertEqual(caret.size.width, 0)
            XCTAssertTrue(caret.origin.x.isFinite && caret.origin.y.isFinite)
            XCTAssertTrue(caret.size.height.isFinite && caret.size.height > 0)
            XCTAssertEqual(field.textInputCaretOffset, 0)
            XCTAssertNil(field.textInputSelection)
        }
    }

    private func makeField(secure: Bool, text: Binding<String>) -> (RetainedViewRuntime, ViewNode) {
        let size = Size(width: 320, height: 100)
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(origin: .zero, size: size)))
        let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
        let field: ViewNode
        if secure {
            field = SecureField("Display name", text: text).makeComponent(context: context).makeNode(runtime: runtime)
        } else {
            field = TextField("Display name", text: text).makeComponent(context: context).makeNode(runtime: runtime)
        }
        field.frame = Rect(x: 20, y: 10, width: 220, height: 32)
        runtime.root.addChild(field)
        _ = runtime.renderScene()
        runtime.requestFocus(field)
        return (runtime, field)
    }

    private func assertEmptyCaret(
        _ caret: Rect, at origin: Point, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(caret.origin, origin, file: file, line: line)
        XCTAssertEqual(caret.size.width, 0, file: file, line: line)
        XCTAssertTrue(caret.origin.x.isFinite && caret.origin.y.isFinite, file: file, line: line)
        XCTAssertTrue(caret.size.height.isFinite && caret.size.height > 0, file: file, line: line)
    }
}
