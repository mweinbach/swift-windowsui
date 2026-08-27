import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class TextSelectionIndexSafetyTests: XCTestCase {
    func testCurrentCharacterBoundariesPreserveUnicodeOffsets() async {
        for text in ["", "ASCII", "A🧑‍🚀e\u{301}你Z", "🇨🇦\r\n🙂"] {
            let boundaries = Array(text.indices) + [text.endIndex]
            for (offset, index) in boundaries.enumerated() {
                let selection = TextSelection(insertionPoint: index)
                XCTAssertEqual(selection.caretOffset(in: text), offset)
                XCTAssertEqual(selection.retainedSelection(in: text).indices, .insertionPoint(offset))
            }
            let selection = TextSelection(range: text.startIndex..<text.endIndex)
            let expected: RetainedTextSelection.Indices =
                text.isEmpty ? .insertionPoint(0) : .range(0..<text.count)
            XCTAssertEqual(selection.retainedSelection(in: text).indices, expected)
        }
    }

    func testStaleLongerStringEndpointClipsToCurrentTextWithoutIndexingIt() async {
        let source = "firstA"
        let selection = TextSelection(insertionPoint: source.endIndex)
        for text in ["first", "A你", ""] {
            XCTAssertEqual(selection.caretOffset(in: text), text.count)
            XCTAssertEqual(selection.retainedSelection(in: text).indices, .insertionPoint(text.count))
        }

        let range = TextSelection(range: source.startIndex..<source.endIndex)
        XCTAssertEqual(range.retainedSelection(in: "first").indices, .range(0..<5))
        XCTAssertEqual(range.editableSelectedOffsetRange(in: "first"), 0..<5)
        XCTAssertEqual(range.retainedSelection(in: "").indices, .range(0..<0))
        XCTAssertNil(range.editableSelectedOffsetRange(in: ""))
    }

    func testStaleCharacterAlignmentCannotSkipReplacementGraphemeBoundaries() async {
        let source = "abcdef"
        let replacement = "e\u{301}X"
        // Each source index claims character alignment in its old string.
        // Its position can now be inside a different extended grapheme.
        let expected = [0, 0, 0, 1, 2, 2, 2]
        for (offset, expectedOffset) in expected.enumerated() {
            let index = source.index(source.startIndex, offsetBy: offset)
            let selection = TextSelection(insertionPoint: index)
            XCTAssertEqual(selection.caretOffset(in: replacement), expectedOffset)
        }
    }

    func testSubscalarAndCombiningPositionsRoundDownToCurrentCharacterBoundary() async {
        let text = "A😀e\u{301}Z"
        let continuation = text.utf8.index(text.utf8.startIndex, offsetBy: 2)
        let trailingSurrogate = text.utf16.index(text.utf16.startIndex, offsetBy: 2)
        let combiningScalar = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: 3)
        let emojiEnd = text.index(text.startIndex, offsetBy: 2)
        // Native UTF16View indices do not prove foreign UTF-16 backing support;
        // these cover transcoding positions within the current native string.
        for (index, expectedOffset) in [
            (continuation, 1), (trailingSurrogate, 1), (combiningScalar, 2), (emojiEnd, 2),
        ] {
            let selection = TextSelection(insertionPoint: index)
            XCTAssertEqual(selection.caretOffset(in: text), expectedOffset)
            XCTAssertEqual(selection.retainedSelection(in: text).indices, .insertionPoint(expectedOffset))
        }
    }

    func testOutOfBoundsUTF16ConstructedIndicesRemainSafe() async {
        let source = "longer source"
        // Swift represents an out-of-bounds UTF-16 request with an invalid
        // position beyond the source end. Do not give it back to String APIs.
        for offset in [-1, 100] {
            let index = String.Index(utf16Offset: offset, in: source)
            let selection = TextSelection(insertionPoint: index)
            XCTAssertEqual(selection.caretOffset(in: "你"), 1)
            XCTAssertEqual(selection.caretOffset(in: ""), 0)
        }
    }

    func testStaleMultipleRangesClipMonotonicallyAndKeepAffinity() async {
        let source = "abcdefgh"
        func index(_ offset: Int) -> String.Index {
            source.index(source.startIndex, offsetBy: offset)
        }
        var selection = TextSelection(ranges: RangeSet([index(1)..<index(3), index(5)..<index(8)]))
        selection.affinity = .upstream
        let retained = selection.retainedSelection(in: "abcd")
        XCTAssertEqual(retained.indices, .ranges([1..<3, 4..<4]))
        XCTAssertEqual(retained.affinity, .upstream)
        XCTAssertEqual(selection.caretOffset(in: "abcd"), 4)
        XCTAssertNil(selection.editableSelectedOffsetRange(in: "abcd"))
    }

    func testMountedTextFieldCanShortenTextBeforeItsSelectionBindingChanges() async throws {
        try assertMountedTextCanShorten(control: .field)
    }

    func testMountedTextEditorCanShortenTextBeforeItsSelectionBindingChanges() async throws {
        try assertMountedTextCanShorten(control: .editor)
    }

    private func assertMountedTextCanShorten(control: SelectionSafetyControl) throws {
        let capture = SelectionSafetyCapture()
        let original = "firstA"
        let originalSelection = TextSelection(insertionPoint: original.endIndex)
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 400, height: 240), scaleFactor: 1)
        let window = Win32Window(title: "Selection index safety", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Selection index safety", size: surface.pixelSize, clearColor: .black,
                content: [
                    AnyView(
                        SelectionSafetyView(
                            capture: capture, control: control, text: original, selection: originalSelection))
                ]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        defer { host.windowWillClose(window) }
        let clock = RuntimeTestClock()
        clock.now = 100
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        func flush() {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
            _ = host.hostedRuntime.renderScene(at: clock.now)
        }
        flush()
        let originalNode = try XCTUnwrap(selectionSafetyEditor(in: host.hostedRuntime.root))
        XCTAssertEqual(originalNode.textInputCaretOffset, 6)
        let text = try XCTUnwrap(capture.text)
        let selection = try XCTUnwrap(capture.selection)

        // The mounted setter synchronously rebuilds the actual host while
        // the independent selection still contains the longer text's index.
        text.wrappedValue = "first"
        flush()
        XCTAssertTrue(selectionSafetyEditor(in: host.hostedRuntime.root) === originalNode)
        XCTAssertEqual(originalNode.textInputCaretOffset, 5)
        XCTAssertEqual(originalNode.textInputSelection?.indices, .insertionPoint(5))
        XCTAssertEqual(selection.wrappedValue, originalSelection, "Conversion must not rewrite authored selection")
        XCTAssertEqual(text.wrappedValue, "first")

        text.wrappedValue = ""
        flush()
        XCTAssertTrue(selectionSafetyEditor(in: host.hostedRuntime.root) === originalNode)
        XCTAssertEqual(originalNode.textInputCaretOffset, 0)
        XCTAssertEqual(originalNode.textInputSelection?.indices, .insertionPoint(0))
        XCTAssertEqual(selection.wrappedValue, originalSelection)
    }
}

private enum SelectionSafetyControl {
    case field
    case editor
}

@MainActor
private final class SelectionSafetyCapture {
    var text: Binding<String>?
    var selection: Binding<TextSelection?>?
}

private struct SelectionSafetyView: View {
    @State private var text: String
    @State private var selection: TextSelection?
    let capture: SelectionSafetyCapture
    let control: SelectionSafetyControl

    init(capture: SelectionSafetyCapture, control: SelectionSafetyControl, text: String, selection: TextSelection?) {
        self.capture = capture
        self.control = control
        _text = State(initialValue: text)
        _selection = State(initialValue: selection)
    }

    var body: some View {
        capture.text = $text
        capture.selection = $selection
        let input: AnyView
        switch control {
        case .field:
            input = AnyView(TextField("Text", text: $text, selection: $selection))
        case .editor:
            input = AnyView(TextEditor(text: $text, selection: $selection))
        }
        return input.accessibilityIdentifier("selection.safety.editor").frame(width: 260, height: 96)
    }
}

@MainActor
private func selectionSafetyEditor(in node: ViewNode) -> ViewNode? {
    if node.accessibilityIdentifier == "selection.safety.editor", node.accessibilityTraits.contains(.isTextInput) {
        return node
    }
    for child in node.children {
        if let match = selectionSafetyEditor(in: child) { return match }
    }
    return nil
}
