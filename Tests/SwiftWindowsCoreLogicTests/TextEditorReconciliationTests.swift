import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class ReconciledEditorDocument {
    var text: String
    var selection: TextSelection?
    var textWrites = 0
    var selectionWrites = 0
    var afterTextWrite: (() -> Void)?

    init(text: String, selection: TextSelection? = nil) {
        self.text = text
        self.selection = selection
    }
}

@MainActor
private final class ReconciledEditorState {
    let primary: ReconciledEditorDocument
    let alternate = ReconciledEditorDocument(text: "WXYZ")
    var bindsSelection: Bool
    var usesAlternateDocument = false
    var showsEditor = true
    var isDisabled = false
    var revision = 0

    init(text: String, bindsSelection: Bool, selection: TextSelection?) {
        primary = ReconciledEditorDocument(text: text, selection: selection)
        self.bindsSelection = bindsSelection
    }
}

@MainActor
private struct ReconciledEditorView: View {
    let state: ReconciledEditorState

    var body: some View {
        // Capture the document selected by this build, so retaining an old
        // binding after reconciliation cannot accidentally pass these tests.
        let document = state.usesAlternateDocument ? state.alternate : state.primary
        let text = Binding<String>(
            get: { document.text },
            set: { value in
                document.text = value
                document.textWrites += 1
                document.afterTextWrite?()
            }
        )
        let selection = Binding<TextSelection?>(
            get: { document.selection },
            set: { value in
                document.selection = value
                document.selectionWrites += 1
            }
        )
        VStack(alignment: .leading, spacing: 4) {
            if state.showsEditor {
                TextEditor(text: text, selection: state.bindsSelection ? selection : nil)
                    .disabled(state.isDisabled)
                    .id("reconciled-editor")
                    .frame(width: 300, height: 120)
            }
            Text("Revision \(state.revision)")
                .id("unrelated-status")
        }
    }
}

@MainActor
private func editorNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private final class ReconciledEditorFixture {
    let state: ReconciledEditorState
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let editor: ViewNode
    let batchRenderer: FakeBatchRenderBackend
    private var isActive = true

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init(text: String, bindsSelection: Bool, selection: TextSelection?) throws {
        let state = ReconciledEditorState(text: text, bindsSelection: bindsSelection, selection: selection)
        self.state = state
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 320, height: 200), scaleFactor: 1)
        window = Win32Window(title: "TextEditor reconciliation", clientSize: surface.pixelSize)
        batchRenderer = FakeBatchRenderBackend()
        host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "TextEditor reconciliation",
                size: surface.pixelSize,
                clearColor: .black,
                content: [AnyView(ReconciledEditorView(state: state))]
            ),
            platformWindow: window,
            renderer: FakeRenderBackend(),
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface },
            startupProbeConfiguration: nil
        )
        host.windowDidCreate(window)
        editor = try XCTUnwrap(
            editorNodes(in: host.hostedRuntime.root).first { $0.accessibilityTraits.contains(.isTextInput) })
        host.hostedRuntime.requestFocus(editor)
        render()
    }

    func render() {
        host.windowNeedsDisplay(window)
        _ = runtime.renderScene()
    }

    func rebuildUnrelatedContent() {
        state.revision += 1
        isActive.toggle()
        // This rebuilds the public view through its actual window host but
        // does not deliver keyboard-focus loss or modify the document.
        host.windowDidChangeActiveState(window, isActive: isActive)
        render()
    }

    func key(_ key: KeyboardKey, modifiers: KeyboardModifiers = []) {
        host.window(
            window,
            keyDown: KeyboardEvent(
                keyCode: key.rawValue,
                modifiers: modifiers,
                textInputDelivery: .systemCharacter
            )
        )
        render()
    }

    func type(_ text: String) {
        host.window(window, didInputText: text)
        render()
    }

    func compose(_ phase: IMECompositionEvent.Phase) {
        host.window(window, imeComposition: IMECompositionEvent(phase: phase))
        render()
    }

    func currentEditor() -> ViewNode? {
        editorNodes(in: runtime.root).first { $0.accessibilityTraits.contains(.isTextInput) }
    }

    func visibleCaretNodes() -> [ViewNode] {
        editorNodes(in: editor).filter { $0.isTextInputCaret && !$0.isHidden }
    }

    func markedTextSegments() -> [ViewNode] {
        editorNodes(in: editor).filter { $0.textStyle.underline && !$0.isHidden && $0.text?.isEmpty == false }
    }
}

/// Exercises the public TextEditor through the real retained window host.
/// Render backends are headless fakes; no HWND, desktop capture, or real input
/// is needed. Synthetic advances make caret/drag assertions font-independent.
@MainActor
final class TextEditorReconciliationTests: XCTestCase {
    private static let characterAdvance = 9.0

    private func withFixture(
        text: String = "abcd",
        bindsSelection: Bool = false,
        selection: TextSelection? = nil,
        _ body: (ReconciledEditorFixture) throws -> Void
    ) throws {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let characters = Array(text)
            let glyphs = characters.enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character,
                    origin: Point(x: Double(index) * Self.characterAdvance, y: 0),
                    advance: Self.characterAdvance,
                    glyphID: UInt32(index + 1),
                    fontFamily: style.fontFamily,
                    weight: style.weight,
                    fontSize: style.nativeFontPixelSize,
                    sourceIndex: index
                )
            }
            let width = Double(max(characters.count, 1)) * Self.characterAdvance
            let height = max(style.nativeFontPixelSize, 1)
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: width, height: height, glyphs: glyphs)],
                contentSize: Size(width: width, height: height),
                measuredSize: Size(width: width, height: height)
            )
        }
        defer { NativeTextRenderer.resetTestingOverrides() }
        let fixture = try ReconciledEditorFixture(text: text, bindsSelection: bindsSelection, selection: selection)
        defer { fixture.host.windowWillClose(fixture.window) }
        try body(fixture)
    }

    private func textSelection(_ range: Range<Int>, in text: String) -> TextSelection {
        let lowerBound = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upperBound = text.index(text.startIndex, offsetBy: range.upperBound)
        return TextSelection(range: lowerBound..<upperBound)
    }

    private func insertionOffset(_ selection: TextSelection?, in text: String) -> Int? {
        guard case .selection(let range) = selection?.indices, range.isEmpty else { return nil }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    func testMidStringCaretAndInsertionSurviveUnrelatedHostedRebuilds() async throws {
        try withFixture { fixture in
            fixture.key(.home)
            fixture.key(.rightArrow)
            fixture.key(.rightArrow)
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 2)
            let reloadsBefore = fixture.host.executedReloadCount

            fixture.rebuildUnrelatedContent()

            XCTAssertGreaterThan(fixture.host.executedReloadCount, reloadsBefore)
            XCTAssertTrue(fixture.currentEditor() === fixture.editor)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.editor)
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 2)
            XCTAssertFalse(fixture.visibleCaretNodes().isEmpty)

            fixture.type("X")
            XCTAssertEqual(fixture.state.primary.text, "abXcd")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 3)
            fixture.rebuildUnrelatedContent()
            fixture.type("Y")
            XCTAssertEqual(fixture.state.primary.text, "abXYcd")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 4)
            XCTAssertEqual(fixture.state.primary.textWrites, 2)
        }
    }

    func testUnboundSelectionSurvivesRebuildAndIsReplacedAtItsRetainedRange() async throws {
        try withFixture(text: "abcdef") { fixture in
            fixture.key(.home)
            fixture.key(.rightArrow)
            fixture.key(.rightArrow, modifiers: [.shift])
            fixture.key(.rightArrow, modifiers: [.shift])
            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(1..<3))

            fixture.rebuildUnrelatedContent()

            XCTAssertEqual(fixture.editor.textInputCaretOffset, 3)
            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(1..<3))
            XCTAssertTrue(editorNodes(in: fixture.editor).contains { $0.text == "bc" && $0.backgroundColor != nil })

            fixture.type("Q")
            XCTAssertEqual(fixture.state.primary.text, "aQdef")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 2)
            XCTAssertNil(fixture.editor.textInputSelection)
            fixture.key(.backspace)
            XCTAssertEqual(fixture.state.primary.text, "adef")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 1)
        }
    }

    func testUnicodeSelectionReplacementAfterRebuildKeepsGraphemesWhole() async throws {
        let text = "A👩🏽‍💻e\u{301}Z"
        XCTAssertEqual(text.count, 4)
        try withFixture(text: text) { fixture in
            fixture.key(.home)
            fixture.key(.rightArrow)
            fixture.key(.rightArrow, modifiers: [.shift])
            fixture.key(.rightArrow, modifiers: [.shift])
            fixture.rebuildUnrelatedContent()

            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(1..<3))
            fixture.type("🧑‍🚀")
            XCTAssertEqual(fixture.state.primary.text, "A🧑‍🚀Z")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 2)
            fixture.rebuildUnrelatedContent()
            fixture.type("!")
            XCTAssertEqual(fixture.state.primary.text, "A🧑‍🚀!Z")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 3)
        }
    }

    func testUnboundCaretAndSelectionClampWhenTextShrinksExternally() async throws {
        try withFixture(text: "abcdef") { fixture in
            fixture.key(.home)
            for _ in 0..<5 {
                fixture.key(.rightArrow)
            }
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 5)

            fixture.state.primary.text = "ab"
            fixture.rebuildUnrelatedContent()

            XCTAssertTrue(fixture.currentEditor() === fixture.editor)
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 2)
            XCTAssertNil(fixture.editor.textInputSelection)
            XCTAssertEqual(fixture.state.primary.textWrites, 0)
            fixture.type("X")
            XCTAssertEqual(fixture.state.primary.text, "abX")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 3)
        }

        for replacement in ["abc", "a", ""] {
            try withFixture(text: "abcdef") { fixture in
                fixture.key(.home)
                fixture.key(.rightArrow)
                fixture.key(.rightArrow)
                for _ in 0..<3 {
                    fixture.key(.rightArrow, modifiers: [.shift])
                }
                XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(2..<5))

                fixture.state.primary.text = replacement
                fixture.rebuildUnrelatedContent()

                XCTAssertEqual(fixture.editor.textInputCaretOffset, replacement.count)
                XCTAssertEqual(fixture.state.primary.textWrites, 0)
                if replacement.count > 2 {
                    XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(2..<replacement.count))
                } else if case .range(let range) = fixture.editor.textInputSelection?.indices {
                    // A collapsed unbound selection can be represented by an
                    // empty range or no selection, but never by stale offsets.
                    XCTAssertEqual(range, replacement.count..<replacement.count)
                }
                fixture.type("X")
                XCTAssertEqual(fixture.state.primary.text, String(replacement.prefix(2)) + "X")
                XCTAssertEqual(fixture.editor.textInputCaretOffset, min(2, replacement.count) + 1)
            }
        }
    }

    func testDisabledEditorRetainsSelectionForEditingAfterReenable() async throws {
        try withFixture(text: "abcdef") { fixture in
            fixture.key(.home)
            fixture.key(.rightArrow)
            fixture.key(.rightArrow)
            fixture.key(.rightArrow, modifiers: [.shift])
            fixture.key(.rightArrow, modifiers: [.shift])
            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(2..<4))

            fixture.state.isDisabled = true
            fixture.rebuildUnrelatedContent()

            XCTAssertTrue(fixture.currentEditor() === fixture.editor)
            XCTAssertFalse(fixture.editor.isFocusable)
            XCTAssertFalse(fixture.runtime.focusedNode === fixture.editor)
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 4)
            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(2..<4))
            fixture.type("ignored")
            XCTAssertEqual(fixture.state.primary.text, "abcdef")
            XCTAssertEqual(fixture.state.primary.textWrites, 0)

            fixture.state.isDisabled = false
            fixture.rebuildUnrelatedContent()
            fixture.runtime.requestFocus(fixture.editor)
            fixture.render()

            XCTAssertTrue(fixture.editor.isFocusable)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.editor)
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 4)
            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(2..<4))
            fixture.type("X")
            XCTAssertEqual(fixture.state.primary.text, "abXef")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 3)
        }
    }

    func testExplicitSelectionBindingOverridesRetainedSelectionOnRebuild() async throws {
        let text = "abcdef"
        try withFixture(text: text, bindsSelection: true, selection: textSelection(2..<2, in: text)) { fixture in
            fixture.key(.rightArrow)
            XCTAssertEqual(insertionOffset(fixture.state.primary.selection, in: text), 3)

            fixture.state.primary.selection = textSelection(0..<2, in: text)
            fixture.rebuildUnrelatedContent()

            XCTAssertTrue(fixture.currentEditor() === fixture.editor)
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 2)
            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(0..<2))

            fixture.type("Q")
            XCTAssertEqual(fixture.state.primary.text, "Qcdef")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 1)
            XCTAssertEqual(insertionOffset(fixture.state.primary.selection, in: fixture.state.primary.text), 1)
        }
    }

    func testRebuiltEditorUsesTheLatestTextAndSelectionBindings() async throws {
        let text = "abcd"
        try withFixture(text: text, bindsSelection: true, selection: textSelection(2..<2, in: text)) { fixture in
            fixture.state.alternate.selection = textSelection(1..<3, in: fixture.state.alternate.text)
            fixture.state.usesAlternateDocument = true
            fixture.rebuildUnrelatedContent()

            XCTAssertTrue(fixture.currentEditor() === fixture.editor)
            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(1..<3))
            fixture.type("é")

            XCTAssertEqual(fixture.state.alternate.text, "WéZ")
            XCTAssertEqual(fixture.state.alternate.textWrites, 1)
            XCTAssertEqual(insertionOffset(fixture.state.alternate.selection, in: fixture.state.alternate.text), 2)
            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertEqual(fixture.state.primary.textWrites, 0)
            XCTAssertEqual(insertionOffset(fixture.state.primary.selection, in: fixture.state.primary.text), 2)
        }
    }

    func testIMECompositionAndCandidateGeometrySurviveHostedRebuild() async throws {
        try withFixture { fixture in
            fixture.key(.home)
            fixture.key(.rightArrow)
            fixture.key(.rightArrow)
            let plainCaret = try XCTUnwrap(fixture.host.windowTextInputCaretRect(fixture.window))

            fixture.compose(.started)
            fixture.compose(.updated("ni"))
            let composingCaret = try XCTUnwrap(fixture.host.windowTextInputCaretRect(fixture.window))
            XCTAssertEqual(composingCaret.origin.x, plainCaret.origin.x + 2 * Self.characterAdvance, accuracy: 0.001)
            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertEqual(fixture.editor.textInputMarkedText, "ni")
            XCTAssertEqual(fixture.markedTextSegments().map(\.text), ["ni"])

            fixture.rebuildUnrelatedContent()

            XCTAssertTrue(fixture.runtime.focusedNode === fixture.editor)
            XCTAssertEqual(fixture.editor.textInputMarkedText, "ni")
            XCTAssertEqual(fixture.markedTextSegments().map(\.text), ["ni"])
            XCTAssertEqual(fixture.host.windowTextInputCaretRect(fixture.window), composingCaret)
            XCTAssertEqual(fixture.state.primary.textWrites, 0)

            fixture.compose(.committed("你"))
            fixture.compose(.ended)
            XCTAssertEqual(fixture.state.primary.text, "ab你cd")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 3)
            XCTAssertNil(fixture.editor.textInputMarkedText)
            XCTAssertTrue(fixture.markedTextSegments().isEmpty)
            let committedCaret = try XCTUnwrap(fixture.host.windowTextInputCaretRect(fixture.window))
            XCTAssertEqual(committedCaret.origin.x, plainCaret.origin.x + Self.characterAdvance, accuracy: 0.001)
            fixture.rebuildUnrelatedContent()
            XCTAssertEqual(fixture.host.windowTextInputCaretRect(fixture.window), committedCaret)
        }
    }

    func testPointerDragKeepsTheLiveFocusAndOriginalAnchorAcrossRebuild() async throws {
        try withFixture(text: "abcdef") { fixture in
            fixture.key(.home)
            let startCaret = try XCTUnwrap(fixture.host.windowTextInputCaretRect(fixture.window))
            let firstPoint = Point(
                x: startCaret.origin.x + Self.characterAdvance + 1,
                y: startCaret.origin.y + max(1, startCaret.size.height / 2)
            )
            let lastPoint = Point(x: firstPoint.x + 3 * Self.characterAdvance, y: firstPoint.y)
            fixture.rebuildUnrelatedContent()
            fixture.runtime.requestFocus(nil)
            fixture.render()

            fixture.host.window(fixture.window, leftMouseDownAt: firstPoint)
            fixture.render()
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.editor)
            XCTAssertTrue(fixture.editor.isFocused)
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 1)
            XCTAssertFalse(fixture.visibleCaretNodes().isEmpty)

            fixture.rebuildUnrelatedContent()
            fixture.host.window(fixture.window, pointerMovedTo: lastPoint)
            fixture.host.window(fixture.window, leftMouseUpAt: lastPoint)
            fixture.render()

            XCTAssertTrue(fixture.runtime.focusedNode === fixture.editor)
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 4)
            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(1..<4))
            XCTAssertTrue(editorNodes(in: fixture.editor).contains { $0.text == "bcd" && $0.backgroundColor != nil })
            fixture.type("X")
            XCTAssertEqual(fixture.state.primary.text, "aXef")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 2)
        }
    }

    func testTextBindingCallbackCanSynchronouslyRebuildWithoutLosingTheInsertionPoint() async throws {
        try withFixture { fixture in
            fixture.key(.home)
            fixture.key(.rightArrow)
            var callbackCount = 0
            fixture.state.primary.afterTextWrite = { [weak fixture] in
                callbackCount += 1
                fixture?.rebuildUnrelatedContent()
            }
            let reloadsBefore = fixture.host.executedReloadCount

            fixture.type("X")
            fixture.type("Y")

            XCTAssertEqual(callbackCount, 2)
            XCTAssertGreaterThan(fixture.host.executedReloadCount, reloadsBefore + 1)
            XCTAssertEqual(fixture.state.primary.text, "aXYbcd")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 3)
            XCTAssertTrue(fixture.currentEditor() === fixture.editor)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.editor)
            XCTAssertFalse(fixture.visibleCaretNodes().isEmpty)
        }
    }

    func testTextBindingCallbackSelectionOverrideSurvivesSynchronousRebuild() async throws {
        let text = "abcd"
        try withFixture(text: text, bindsSelection: true, selection: textSelection(1..<1, in: text)) { fixture in
            fixture.state.primary.afterTextWrite = { [weak fixture] in
                guard let fixture else { return }
                let updatedText = fixture.state.primary.text
                let selectionStart = updatedText.index(updatedText.startIndex, offsetBy: 3)
                fixture.state.primary.selection = TextSelection(range: selectionStart..<updatedText.endIndex)
                fixture.rebuildUnrelatedContent()
            }
            let reloadsBefore = fixture.host.executedReloadCount

            fixture.type("X")
            fixture.state.primary.afterTextWrite = nil

            XCTAssertGreaterThan(fixture.host.executedReloadCount, reloadsBefore)
            XCTAssertEqual(fixture.state.primary.text, "aXbcd")
            XCTAssertTrue(fixture.currentEditor() === fixture.editor)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.editor)
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 5)
            XCTAssertEqual(fixture.editor.textInputSelection?.indices, .range(3..<5))
            if case .selection(let range) = fixture.state.primary.selection?.indices {
                XCTAssertEqual(String(fixture.state.primary.text[range]), "cd")
            } else {
                XCTFail("The application's selection override must remain in the binding")
            }

            fixture.type("Y")

            XCTAssertEqual(fixture.state.primary.text, "aXbY")
            XCTAssertEqual(fixture.editor.textInputCaretOffset, 4)
            XCTAssertEqual(insertionOffset(fixture.state.primary.selection, in: fixture.state.primary.text), 4)
            XCTAssertEqual(fixture.state.primary.textWrites, 2)
        }
    }

    func testBindingCallbackRemovalDoesNotRestoreDetachedEditorFocusOrChrome() async throws {
        try withFixture { fixture in
            fixture.key(.home)
            fixture.key(.rightArrow)
            fixture.state.primary.afterTextWrite = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.showsEditor = false
                fixture.rebuildUnrelatedContent()
            }

            fixture.type("X")

            XCTAssertEqual(fixture.state.primary.text, "aXbcd")
            XCTAssertEqual(fixture.state.primary.textWrites, 1)
            XCTAssertNil(fixture.currentEditor())
            XCTAssertFalse(fixture.runtime.focusedNode === fixture.editor)
            XCTAssertFalse(editorNodes(in: fixture.runtime.root).contains(where: \.isTextInputCaret))
            XCTAssertNil(fixture.host.windowTextInputCaretRect(fixture.window))

            fixture.type("Y")
            fixture.compose(.updated("ni"))
            fixture.compose(.committed("你"))
            XCTAssertEqual(fixture.state.primary.text, "aXbcd", "Later host input must not reach the removed editor")
            XCTAssertEqual(fixture.state.primary.textWrites, 1)
            XCTAssertNil(fixture.currentEditor())
        }
    }

    func testReconciledEditorAndRuntimeReleaseWhenTheHostCloses() async throws {
        weak var releasedHost: WinSwiftUIWindowHost?
        weak var releasedRuntime: RetainedViewRuntime?
        weak var releasedEditor: ViewNode?

        try withFixture { fixture in
            releasedHost = fixture.host
            releasedRuntime = fixture.runtime
            releasedEditor = fixture.editor
            fixture.key(.home)
            fixture.key(.rightArrow)
            fixture.rebuildUnrelatedContent()
            fixture.compose(.updated("ni"))
            XCTAssertNotNil(fixture.host.windowTextInputCaretRect(fixture.window))
        }

        XCTAssertNil(releasedHost)
        XCTAssertNil(releasedRuntime, "Editor callbacks must not retain the runtime that owns their node")
        XCTAssertNil(releasedEditor, "Editor controllers and chrome must not retain a detached node")
    }
}
