import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class NativeTextInputValue {
    var text: String
    var submitCount = 0

    init(_ text: String) {
        self.text = text
    }
}

@MainActor
private final class NativeTextInputClipboard: TextInputClipboard {
    var text: String?

    func copyString(_ text: String) {
        self.text = text
    }

    func pasteString() -> String? {
        text
    }
}

@MainActor
private final class NativeTextInputDelegateRecorder: WindowDelegate {
    var keyEvents: [KeyboardEvent] = []
    var textEvents: [String] = []

    func window(_ window: Win32Window, keyDown event: KeyboardEvent) {
        keyEvents.append(event)
    }

    func window(_ window: Win32Window, didInputText text: String) {
        textEvents.append(text)
    }
}

/// Covers the complete distinction between virtual-key commands and the
/// keyboard-layout-translated Unicode text stream delivered by `WM_CHAR`.
@MainActor
final class Win32TextInputTests: XCTestCase {
    private enum ControlKind {
        case field
        case secure
        case editor
    }

    private struct Fixture {
        var value: NativeTextInputValue
        var runtime: RetainedViewRuntime
        var node: ViewNode
    }

    private func makeFixture(
        text: String = "",
        kind: ControlKind = .field,
        autocapitalization: TextInputAutocapitalization? = nil,
        clipboard: NativeTextInputClipboard? = nil
    ) -> Fixture {
        let value = NativeTextInputValue(text)
        let binding = Binding(get: { value.text }, set: { value.text = $0 })
        let runtime = RetainedViewRuntime(root: ViewNode())
        var context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 800, height: 600) },
            invalidateHandler: {}
        )

        if let autocapitalization {
            context = context.withEnvironmentValue(
                \.textInputAutocapitalization,
                autocapitalization as TextInputAutocapitalization?
            )
        }
        if let clipboard {
            context = context.withEnvironmentValue(
                \.textInputClipboard,
                clipboard as (any TextInputClipboard)?
            )
        }

        let node: ViewNode
        switch kind {
        case .field:
            node = TextField("VALUE", text: binding, onCommit: { value.submitCount += 1 })
                .makeComponent(context: context)
                .makeNode(runtime: runtime)
        case .secure:
            node = SecureField("VALUE", text: binding)
                .makeComponent(context: context)
                .makeNode(runtime: runtime)
        case .editor:
            node = TextEditor(text: binding)
                .makeComponent(context: context)
                .makeNode(runtime: runtime)
        }

        runtime.requestFocus(node)
        return Fixture(value: value, runtime: runtime, node: node)
    }

    private func keyboardEvent(
        _ keyCode: UInt32,
        modifiers: KeyboardModifiers = []
    ) -> KeyboardEvent {
        KeyboardEvent(
            keyCode: keyCode,
            modifiers: modifiers,
            textInputDelivery: .systemCharacter
        )
    }

    private func commitKeyboardText(_ text: String, in fixture: Fixture) {
        fixture.runtime.imeComposition(
            IMECompositionEvent(phase: .committed(text), source: .keyboard)
        )
    }

    private func firstTextInput(in node: ViewNode) -> ViewNode? {
        if node.onIMEComposition != nil {
            return node
        }

        for child in node.children {
            if let match = firstTextInput(in: child) {
                return match
            }
        }
        return nil
    }

    func testUTF16DecoderPreservesKeyboardLayoutCharacters() async {
        var decoder = Win32UTF16TextInputDecoder()

        XCTAssertEqual(decoder.append(0x0021), "!")
        XCTAssertEqual(decoder.append(0x0041), "A")
        XCTAssertEqual(decoder.append(0x00E9), "é")
        XCTAssertEqual(decoder.append(0x20AC), "€")
        XCTAssertEqual(decoder.append(0x597D), "好")
    }

    func testUTF16DecoderCombinesSupplementaryPlaneSurrogates() async {
        var decoder = Win32UTF16TextInputDecoder()

        XCTAssertNil(decoder.append(0xD83D))
        XCTAssertEqual(decoder.append(0xDE00), "😀")
        XCTAssertNil(decoder.append(0xD834))
        XCTAssertEqual(decoder.append(0xDD1E), "𝄞")
    }

    func testMalformedSurrogatesDoNotPoisonFollowingInput() async {
        var decoder = Win32UTF16TextInputDecoder()

        XCTAssertNil(decoder.append(0xDE00), "An unmatched low surrogate is not text.")
        XCTAssertNil(decoder.append(0xD83D))
        XCTAssertEqual(decoder.append(0x0078), "x", "An interrupted high surrogate must be discarded.")
        XCTAssertNil(decoder.append(0xDE00))

        XCTAssertNil(decoder.append(0xD800))
        XCTAssertNil(decoder.append(0xD83D), "A later high surrogate replaces the incomplete pair.")
        XCTAssertEqual(decoder.append(0xDE00), "😀")

        XCTAssertNil(decoder.append(0xD83D))
        decoder.reset()
        XCTAssertNil(decoder.append(0xDE00), "A focus change cannot complete the old field's surrogate pair.")
    }

    func testControlCharactersAreCommandsAndReturnBecomesLineFeed() async {
        var decoder = Win32UTF16TextInputDecoder()

        for codeUnit: UInt16 in [0x0000, 0x0001, 0x0003, 0x0008, 0x0009, 0x001B, 0x007F] {
            XCTAssertNil(decoder.append(codeUnit), "Control code \(codeUnit) must not become editable text.")
        }

        XCTAssertEqual(decoder.append(0x000D), "\n")
        XCTAssertEqual(decoder.append(0x0020), " ")
    }

    func testVirtualKeyAndTranslatedCharacterInsertExactlyOnce() async {
        let fixture = makeFixture()

        fixture.runtime.keyDown(keyboardEvent(0x41))
        XCTAssertEqual(fixture.value.text, "", "The virtual key is not the keyboard-layout character.")

        commitKeyboardText("a", in: fixture)
        XCTAssertEqual(fixture.value.text, "a")
        XCTAssertEqual(fixture.node.textInputCaretOffset, 1)
    }

    func testSyntheticVirtualKeyEventsKeepExistingInsertionBehavior() async {
        let fixture = makeFixture()

        fixture.runtime.keyDown(KeyboardEvent(keyCode: 0x41))

        XCTAssertEqual(fixture.value.text, "a")
        XCTAssertEqual(fixture.node.textInputCaretOffset, 1)
    }

    func testShiftedPunctuationCapsLockAndInternationalTextUseTranslatedCharacters() async {
        let fixture = makeFixture()

        fixture.runtime.keyDown(keyboardEvent(0x31, modifiers: [.shift]))
        commitKeyboardText("!", in: fixture)
        fixture.runtime.keyDown(keyboardEvent(0x41))
        commitKeyboardText("A", in: fixture)
        fixture.runtime.keyDown(keyboardEvent(0x45))
        commitKeyboardText("é", in: fixture)
        commitKeyboardText("好", in: fixture)
        commitKeyboardText("😀", in: fixture)

        XCTAssertEqual(fixture.value.text, "!Aé好😀")
        XCTAssertEqual(fixture.node.textInputCaretOffset, 5)
    }

    func testAltGrCharacterSurvivesControlAndAltVirtualKeyModifiers() async {
        let fixture = makeFixture()

        fixture.runtime.keyDown(keyboardEvent(0x45, modifiers: [.control, .alt]))
        XCTAssertEqual(fixture.value.text, "")

        commitKeyboardText("€", in: fixture)
        XCTAssertEqual(fixture.value.text, "€")
    }

    func testKeyboardUnicodeCommitReplacesSelection() async {
        let fixture = makeFixture(text: "hello")
        fixture.node.textInputCaretOffset = 3
        fixture.node.textInputSelection = RetainedTextSelection(
            indices: .range(1..<3),
            affinity: .downstream
        )

        commitKeyboardText("😀", in: fixture)

        XCTAssertEqual(fixture.value.text, "h😀lo")
        XCTAssertEqual(fixture.node.textInputCaretOffset, 2)
        XCTAssertNil(fixture.node.textInputSelection)
    }

    func testSecureFieldsAcceptTranslatedUnicodeWithoutDuplicatingVirtualKeys() async {
        let fixture = makeFixture(text: "abc", kind: .secure)

        fixture.runtime.keyDown(keyboardEvent(0x4D))
        commitKeyboardText("密", in: fixture)

        XCTAssertEqual(fixture.value.text, "abc密")
        XCTAssertEqual(fixture.node.textInputCaretOffset, 4)
    }

    func testSingleLineEnterSubmitsWithoutInsertingNewline() async {
        let fixture = makeFixture(text: "hello")

        fixture.runtime.keyDown(keyboardEvent(KeyboardKey.enter.rawValue))
        commitKeyboardText("\n", in: fixture)

        XCTAssertEqual(fixture.value.submitCount, 1)
        XCTAssertEqual(fixture.value.text, "hello")
    }

    func testTextEditorEnterInsertsExactlyOneNormalizedLineFeed() async {
        let fixture = makeFixture(text: "hello", kind: .editor)
        var decoder = Win32UTF16TextInputDecoder()

        fixture.runtime.keyDown(keyboardEvent(KeyboardKey.enter.rawValue))
        XCTAssertEqual(fixture.value.text, "hello")

        if let text = decoder.append(0x000D) {
            commitKeyboardText(text, in: fixture)
        }

        XCTAssertEqual(fixture.value.text, "hello\n")
        XCTAssertEqual(fixture.node.textInputCaretOffset, 6)
    }

    func testKeyboardTextPreservesAutocapitalizationWithoutChangingIMECommits() async {
        let words = makeFixture(autocapitalization: .words)

        commitKeyboardText("a", in: words)
        commitKeyboardText("b", in: words)
        commitKeyboardText(" ", in: words)
        commitKeyboardText("c", in: words)
        XCTAssertEqual(words.value.text, "Ab C")

        let sentence = makeFixture(text: "hi. ", autocapitalization: .sentences)
        commitKeyboardText("d", in: sentence)
        XCTAssertEqual(sentence.value.text, "hi. D")

        let characters = makeFixture(autocapitalization: .characters)
        characters.runtime.imeComposition(IMECompositionEvent(phase: .committed("é")))
        XCTAssertEqual(characters.value.text, "é", "An actual IME result must retain its composed casing.")
        commitKeyboardText("ß", in: characters)
        XCTAssertEqual(characters.value.text, "éSS")
        XCTAssertEqual(characters.node.textInputCaretOffset, 3)
    }

    func testControlShortcutsAndBackspaceRemainVirtualKeyCommands() async {
        let clipboard = NativeTextInputClipboard()
        let fixture = makeFixture(text: "hello", clipboard: clipboard)

        fixture.runtime.keyDown(keyboardEvent(0x41, modifiers: [.control]))
        fixture.runtime.keyDown(keyboardEvent(0x43, modifiers: [.control]))
        XCTAssertEqual(clipboard.text, "hello")

        fixture.runtime.keyDown(keyboardEvent(0x58, modifiers: [.control]))
        XCTAssertEqual(fixture.value.text, "")

        clipboard.text = "ok"
        fixture.runtime.keyDown(keyboardEvent(0x56, modifiers: [.control]))
        XCTAssertEqual(fixture.value.text, "ok")

        fixture.runtime.keyDown(keyboardEvent(KeyboardKey.backspace.rawValue))
        XCTAssertEqual(fixture.value.text, "o")
    }

    func testWindowProcedureRoutesUnicodeCharactersAndMarksNativeKeyEvents() async throws {
        let window = Win32Window(title: "Text input routing", clientSize: IntSize(width: 120, height: 80))
        window.postsQuitMessageOnDestroy = false
        let recorder = NativeTextInputDelegateRecorder()
        window.delegate = recorder

        do {
            try window.create()
        } catch {
            throw XCTSkip("This environment cannot create a top-level window: \(error)")
        }

        let handle = try XCTUnwrap(window.nativeHandle?.rawPointer)
        let hwnd = HWND(bitPattern: Int(bitPattern: handle))
        defer { DestroyWindow(hwnd) }

        SendMessageW(hwnd, UINT(WM_KEYDOWN), WPARAM(0x41), 0)
        SendMessageW(hwnd, UINT(WM_CHAR), WPARAM(0x0041), 0)
        SendMessageW(hwnd, UINT(WM_CHAR), WPARAM(0x0021), 0)
        SendMessageW(hwnd, UINT(WM_CHAR), WPARAM(0x20AC), 0)
        SendMessageW(hwnd, UINT(WM_CHAR), WPARAM(0xD83D), 0)
        SendMessageW(hwnd, UINT(WM_CHAR), WPARAM(0xDE00), 0)
        SendMessageW(hwnd, UINT(WM_CHAR), WPARAM(0x0003), 0)

        XCTAssertEqual(recorder.keyEvents.count, 1)
        XCTAssertEqual(recorder.keyEvents.first?.textInputDelivery, .systemCharacter)
        XCTAssertEqual(recorder.textEvents, ["A", "!", "€", "😀"])
    }

    func testWindowProcedureDoesNotTreatActiveIMECompositionAsOrdinaryKeyboardText() async throws {
        let window = Win32Window(title: "IME text ownership", clientSize: IntSize(width: 120, height: 80))
        window.postsQuitMessageOnDestroy = false
        let recorder = NativeTextInputDelegateRecorder()
        window.delegate = recorder

        do {
            try window.create()
        } catch {
            throw XCTSkip("This environment cannot create a top-level window: \(error)")
        }

        let handle = try XCTUnwrap(window.nativeHandle?.rawPointer)
        let hwnd = HWND(bitPattern: Int(bitPattern: handle))
        defer { DestroyWindow(hwnd) }

        SendMessageW(hwnd, UINT(WM_IME_STARTCOMPOSITION), 0, 0)
        SendMessageW(hwnd, UINT(WM_CHAR), WPARAM(0x0078), 0)
        SendMessageW(hwnd, UINT(WM_IME_ENDCOMPOSITION), 0, 0)
        SendMessageW(hwnd, UINT(WM_CHAR), WPARAM(0x0079), 0)

        XCTAssertEqual(recorder.textEvents, ["y"])
    }

    func testWindowHostRoutesTranslatedCharactersIntoItsFocusedTextField() async throws {
        let value = NativeTextInputValue("")
        let binding = Binding(get: { value.text }, set: { value.text = $0 })
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 320, height: 200),
            scaleFactor: 1
        )
        let configuration = WindowGroupConfiguration(
            title: "Text input host",
            size: surface.pixelSize,
            clearColor: .black,
            content: [AnyView(TextField("VALUE", text: binding))]
        )
        weak var capturedRuntime: RetainedViewRuntime?
        let host = WinSwiftUIWindowHost(
            configuration: configuration,
            renderer: CPUBatchRenderer(),
            batchRenderer: CPUBatchRenderer(),
            surfaceDescriptorProvider: { _ in surface },
            sceneRenderer: { runtime, timestamp in
                capturedRuntime = runtime
                return runtime.renderScene(at: timestamp)
            }
        )
        let window = Win32Window(title: "Text input host", clientSize: surface.pixelSize)
        host.windowDidCreate(window)

        let runtime = try XCTUnwrap(capturedRuntime)
        let textInput = try XCTUnwrap(firstTextInput(in: runtime.root))
        runtime.requestFocus(textInput)

        var routedEvents: [WindowHostInputEvent] = []
        host.onInputEventRouted = { routedEvents.append($0) }

        host.window(window, keyDown: keyboardEvent(0x31, modifiers: [.shift]))
        XCTAssertEqual(value.text, "")

        host.window(window, didInputText: "!")
        XCTAssertEqual(value.text, "!")

        host.window(window, didInputText: "é")
        XCTAssertEqual(value.text, "!é", "The focused field must keep receiving text after a content reload.")
        XCTAssertEqual(routedEvents.count, 3)
        guard case .textInput(let translated) = routedEvents[1] else {
            return XCTFail("Expected the translated character to be observable as routed text input.")
        }
        XCTAssertEqual(translated, "!")
    }
}
