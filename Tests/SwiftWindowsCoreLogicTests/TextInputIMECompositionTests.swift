import Foundation

import SwiftWindowsCore
import WinSDK

import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private enum IMECompositionHarness {
    /// Fixed per-character advance used by the synthetic native layout.
    static let advance: Double = 9

    static func installSyntheticNativeLayout() {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let characters = Array(text)
            let glyphs = characters.enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character,
                    origin: Point(x: Double(index) * advance, y: 0),
                    advance: advance,
                    glyphID: UInt32(character.unicodeScalars.first?.value ?? UInt32(index + 1)),
                    fontFamily: style.fontFamily,
                    weight: style.weight,
                    fontSize: style.nativeFontPixelSize,
                    sourceIndex: index
                )
            }
            let width = Double(max(characters.count, 1)) * advance
            let height = max(style.nativeFontPixelSize, 1)
            return NativeTextLayoutResult(
                lines: [
                    NativeTextLineLayout(
                        text: text,
                        width: width,
                        height: height,
                        glyphs: glyphs
                    )
                ],
                contentSize: Size(width: width, height: height),
                measuredSize: Size(width: width, height: height)
            )
        }
    }

    static func reset() {
        NativeTextRenderer.resetTestingOverrides()
    }

    static func makeNode(
        text: Binding<String>,
        kind: Kind = .field
    ) -> (runtime: RetainedViewRuntime, node: ViewNode, label: ViewNode) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 800, height: 600) },
            invalidateHandler: {}
        )
        let node: ViewNode
        switch kind {
        case .field:
            node = TextField("VALUE", text: text).makeComponent(context: context).makeNode(runtime: runtime)
        case .secure:
            node = SecureField("VALUE", text: text).makeComponent(context: context).makeNode(runtime: runtime)
        case .editor:
            node = TextEditor(text: text).makeComponent(context: context).makeNode(runtime: runtime)
        }

        guard let label = node.children.first else {
            fatalError("text input should start with its content label child")
        }
        // Stand in for a layout pass: the label sits at the node's content
        // origin, so content-space geometry maps to root space by translation.
        node.frame = Rect(x: 10, y: 20, width: 200, height: 30)
        label.frame = Rect(x: 4, y: 4, width: 192, height: 22)
        runtime.requestFocus(node)
        return (runtime, node, label)
    }

    enum Kind {
        case field
        case secure
        case editor
    }

    /// All nodes in the subtree, depth-first.
    static func flattened(_ node: ViewNode) -> [ViewNode] {
        var result = [node]
        for child in node.children {
            result += flattened(child)
        }
        return result
    }

    /// The underlined marked-text segment label currently painted by the
    /// editing chrome, if any.
    static func markedSegment(in node: ViewNode) -> ViewNode? {
        flattened(node).first { $0.textStyle.underline && ($0.text?.isEmpty == false) }
    }
}

/// Fake IMM32 seam driving the WM_IME_COMPOSITION translation headlessly.
private final class FakeIMECompositionContextProvider: IMECompositionContextProvider, @unchecked Sendable {
    var composition: String?
    var result: String?
    var positions: [Point] = []

    func compositionString(window hwnd: HWND?) -> String? {
        composition
    }

    func resultString(window hwnd: HWND?) -> String? {
        result
    }

    func setCompositionWindowPosition(_ point: Point, window hwnd: HWND?) {
        positions.append(point)
    }
}

final class TextInputIMECompositionTests: XCTestCase {
    func testCompositionUpdateShowsUnderlinedMarkedTextAtCaret() async {
        await MainActor.run {
            IMECompositionHarness.installSyntheticNativeLayout()
            defer { IMECompositionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = IMECompositionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            runtime.imeComposition(IMECompositionEvent(phase: .started))
            runtime.imeComposition(IMECompositionEvent(phase: .updated("ni")))

            XCTAssertEqual(node.textInputMarkedText, "ni")
            XCTAssertEqual(value, "hello", "marked text must not touch the binding")

            let marked = IMECompositionHarness.markedSegment(in: node)
            XCTAssertEqual(marked?.text, "ni")
            XCTAssertEqual(marked?.textStyle.underline, true)
        }
    }

    func testCommitInsertsResultStringAtCaret() async {
        await MainActor.run {
            IMECompositionHarness.installSyntheticNativeLayout()
            defer { IMECompositionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = IMECompositionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            runtime.imeComposition(IMECompositionEvent(phase: .started))
            runtime.imeComposition(IMECompositionEvent(phase: .updated("ni")))
            runtime.imeComposition(IMECompositionEvent(phase: .committed("你")))
            runtime.imeComposition(IMECompositionEvent(phase: .ended))

            XCTAssertEqual(value, "hello你")
            XCTAssertEqual(node.textInputCaretOffset, 6)
            XCTAssertNil(node.textInputMarkedText)
            XCTAssertNil(IMECompositionHarness.markedSegment(in: node))
        }
    }

    func testCommitReplacesCurrentSelection() async {
        await MainActor.run {
            IMECompositionHarness.installSyntheticNativeLayout()
            defer { IMECompositionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = IMECompositionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )
            node.textInputCaretOffset = 3
            node.textInputSelection = RetainedTextSelection(indices: .range(1..<3), affinity: .downstream)

            runtime.imeComposition(IMECompositionEvent(phase: .started))
            runtime.imeComposition(IMECompositionEvent(phase: .updated("hao")))

            // While composing, the marked text visually replaces the selection.
            XCTAssertEqual(IMECompositionHarness.markedSegment(in: node)?.text, "hao")

            runtime.imeComposition(IMECompositionEvent(phase: .committed("好")))

            XCTAssertEqual(value, "h好lo")
            XCTAssertEqual(node.textInputCaretOffset, 2)
            XCTAssertNil(node.textInputMarkedText)
        }
    }

    func testEndWithoutCommitDiscardsMarkedText() async {
        await MainActor.run {
            IMECompositionHarness.installSyntheticNativeLayout()
            defer { IMECompositionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = IMECompositionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            runtime.imeComposition(IMECompositionEvent(phase: .started))
            runtime.imeComposition(IMECompositionEvent(phase: .updated("ni")))
            runtime.imeComposition(IMECompositionEvent(phase: .ended))

            XCTAssertEqual(value, "hello")
            XCTAssertNil(node.textInputMarkedText)
            XCTAssertNil(IMECompositionHarness.markedSegment(in: node))
        }
    }

    func testEscapeCancelsCompositionWithoutCommitting() async {
        await MainActor.run {
            IMECompositionHarness.installSyntheticNativeLayout()
            defer { IMECompositionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = IMECompositionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            runtime.imeComposition(IMECompositionEvent(phase: .started))
            runtime.imeComposition(IMECompositionEvent(phase: .updated("ni")))
            XCTAssertEqual(node.textInputMarkedText, "ni")

            runtime.keyDown(KeyboardEvent(keyCode: 0x1B))  // VK_ESCAPE

            XCTAssertEqual(value, "hello")
            XCTAssertNil(node.textInputMarkedText)
        }
    }

    func testSecureFieldMasksMarkedTextAndCommitsRealText() async {
        await MainActor.run {
            IMECompositionHarness.installSyntheticNativeLayout()
            defer { IMECompositionHarness.reset() }

            var value = "abc"
            let (runtime, node, _) = IMECompositionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 }),
                kind: .secure
            )

            runtime.imeComposition(IMECompositionEvent(phase: .updated("xy")))

            // macOS parity: IME is allowed in secure fields, but the marked
            // text is masked like the committed text.
            XCTAssertEqual(node.textInputMarkedText, "xy")
            XCTAssertEqual(IMECompositionHarness.markedSegment(in: node)?.text, "**")

            runtime.imeComposition(IMECompositionEvent(phase: .committed("密")))
            XCTAssertEqual(value, "abc密")
        }
    }

    func testSingleLineFieldStripsNewlinesFromMarkedAndCommittedText() async {
        await MainActor.run {
            IMECompositionHarness.installSyntheticNativeLayout()
            defer { IMECompositionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = IMECompositionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            runtime.imeComposition(IMECompositionEvent(phase: .updated("ab\ncd")))
            XCTAssertEqual(node.textInputMarkedText, "ab")

            runtime.imeComposition(IMECompositionEvent(phase: .committed("x\ny")))
            XCTAssertEqual(value, "hellox")
        }
    }

    func testCaretRectTracksEndOfMarkedTextForCandidateWindow() async {
        await MainActor.run {
            IMECompositionHarness.installSyntheticNativeLayout()
            defer { IMECompositionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = IMECompositionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            // Caret defaults to the end of "hello" (offset 5): node origin
            // (10, 20) + label origin (4, 4) + 5 * advance.
            let plainCaret = runtime.focusedTextInputCaretRect
            XCTAssertEqual(plainCaret?.origin.x, 14 + 5 * IMECompositionHarness.advance)
            XCTAssertEqual(plainCaret?.origin.y, 24)
            XCTAssertGreaterThan(plainCaret?.size.height ?? 0, 0)

            // While composing "ni" at the caret, the candidate window anchor
            // moves to the end of the marked text (display offset 7).
            runtime.imeComposition(IMECompositionEvent(phase: .updated("ni")))
            let composingCaret = runtime.focusedTextInputCaretRect
            XCTAssertEqual(composingCaret?.origin.x, 14 + 7 * IMECompositionHarness.advance)
        }
    }

    func testIMEEventsIgnoredWithoutFocusedTextInput() async {
        await MainActor.run {
            IMECompositionHarness.installSyntheticNativeLayout()
            defer { IMECompositionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = IMECompositionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )
            runtime.requestFocus(nil)

            runtime.imeComposition(IMECompositionEvent(phase: .updated("ni")))
            XCTAssertNil(node.textInputMarkedText)
            XCTAssertNil(runtime.focusedTextInputCaretRect)
        }
    }

    // MARK: - WM_IME_COMPOSITION translation (headless, fake IMM32 seam)

    func testCompositionMessageTranslatesCompositionString() async {
        await MainActor.run {
            let provider = FakeIMECompositionContextProvider()
            provider.composition = "あ"

            // GCS_COMPSTR = 0x0008
            let events = Win32Window.imeCompositionEvents(lParam: 0x0008, provider: provider, hwnd: nil)

            XCTAssertEqual(events, [IMECompositionEvent(phase: .updated("あ"))])
        }
    }

    func testCompositionMessageTranslatesResultString() async {
        await MainActor.run {
            let provider = FakeIMECompositionContextProvider()
            provider.result = "亜"

            // GCS_RESULTSTR = 0x0800
            let events = Win32Window.imeCompositionEvents(lParam: 0x0800, provider: provider, hwnd: nil)

            XCTAssertEqual(events, [IMECompositionEvent(phase: .committed("亜"))])
        }
    }

    func testCompositionMessageDeliversUpdateBeforeCommit() async {
        await MainActor.run {
            let provider = FakeIMECompositionContextProvider()
            provider.composition = "a"
            provider.result = "あ"

            // GCS_COMPSTR | GCS_RESULTSTR
            let events = Win32Window.imeCompositionEvents(lParam: 0x0008 | 0x0800, provider: provider, hwnd: nil)

            XCTAssertEqual(
                events,
                [
                    IMECompositionEvent(phase: .updated("a")),
                    IMECompositionEvent(phase: .committed("あ")),
                ]
            )
        }
    }

    func testCompositionMessageWithoutStringFlagsProducesNoEvents() async {
        await MainActor.run {
            let provider = FakeIMECompositionContextProvider()
            provider.composition = "a"
            provider.result = "b"

            // GCS_CURSORPOS only = 0x0080: caret moved, no string change.
            let events = Win32Window.imeCompositionEvents(lParam: 0x0080, provider: provider, hwnd: nil)

            XCTAssertEqual(events, [])
        }
    }

    func testSetContextAdjustmentHidesOSCompositionWindowOnly() async {
        await MainActor.run {
            // ISC_SHOWUICOMPOSITIONWINDOW = 0x80000000; every other flag must
            // survive so the candidate window keeps showing.
            let all = LPARAM(bitPattern: UInt64(0xC000_000F))
            let adjusted = Win32Window.imeSetContextAdjustedLParam(all)
            XCTAssertEqual(adjusted, LPARAM(bitPattern: UInt64(0x4000_000F)))
        }
    }
}
