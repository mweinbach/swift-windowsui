import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum UndoTestControl {
    case field
    case editor
    case secure
}

private enum UndoTestSetterPolicy {
    case accept
    case reject
    case uppercase
}

@MainActor
private final class UndoTestReleaseCallback {
    let callback: @MainActor () -> Void

    init(_ callback: @escaping @MainActor () -> Void) { self.callback = callback }

    deinit { MainActor.assumeIsolated { callback() } }
}

@MainActor
private final class UndoTestExpiredTarget {}

@MainActor
private enum UndoTestManagerPolicy {
    case inherited
    case custom(WinSwiftUI.UndoManager?)
}

@MainActor
private final class UndoTestDocument {
    var text: String
    var selection: TextSelection?
    var setterPolicy: UndoTestSetterPolicy = .accept
    var attemptedValues: [String] = []
    var textBindingVersions: [Int] = []
    var selectionBindingVersions: [Int] = []
    var manager: WinSwiftUI.UndoManager?
    var onEditingChanged: (@MainActor (Bool) -> Void)?
    var afterTextWrite: (@MainActor () -> Void)?
    var afterSelectionWrite: (@MainActor () -> Void)?
    var beforeSelectionRead: (@MainActor () -> Void)?

    init(text: String, selection: TextSelection? = nil) {
        self.text = text
        self.selection = selection
    }

    func write(_ value: String, bindingVersion: Int) {
        attemptedValues.append(value)
        textBindingVersions.append(bindingVersion)
        switch setterPolicy {
        case .accept:
            text = value
        case .reject:
            break
        case .uppercase:
            text = value.uppercased()
        }
        afterTextWrite?()
    }
}

@MainActor
private final class UndoTestClipboard: TextInputClipboard {
    var value: String?

    func copyString(_ text: String) { value = text }
    func pasteString() -> String? { value }
}

@MainActor
private final class UndoTestState {
    let control: UndoTestControl
    let primary: UndoTestDocument
    let alternate = UndoTestDocument(text: "")
    let modal = UndoTestDocument(text: "")
    let clipboard = UndoTestClipboard()
    var managerPolicy: UndoTestManagerPolicy
    var hostedManager: WinSwiftUI.UndoManager?
    var bindsSelection: Bool
    var bindingVersion = 0
    var revision = 0
    var editorIdentity = "original-document"
    var usesAlternateDocument = false
    var showsEditor = true
    var isDisabled = false
    var showsModal = false
    var modalControl: UndoTestControl = .editor
    var preventsClosing = false
    var installsUndoCommand = false
    var undoCommandCalls = 0

    var document: UndoTestDocument { usesAlternateDocument ? alternate : primary }

    init(
        control: UndoTestControl,
        text: String,
        bindsSelection: Bool,
        selection: TextSelection?,
        managerPolicy: UndoTestManagerPolicy
    ) {
        self.control = control
        primary = UndoTestDocument(text: text, selection: selection)
        self.bindsSelection = bindsSelection
        self.managerPolicy = managerPolicy
    }
}

@MainActor
private struct UndoTestControlView: View {
    @Environment(\.undoManager) private var manager

    let document: UndoTestDocument
    let control: UndoTestControl
    let bindsSelection: Bool
    let bindingVersion: Int
    let isDisabled: Bool
    let identifier: String
    let undoCommand: (() -> Void)?

    var body: some View {
        document.manager = manager
        // Bind this build to a specific document and version. A controller
        // that keeps an old binding cannot pass the latest-binding checks.
        let text = Binding<String>(
            get: { document.text },
            set: { document.write($0, bindingVersion: bindingVersion) }
        )
        let selection = Binding<TextSelection?>(
            get: {
                document.beforeSelectionRead?()
                return document.selection
            },
            set: {
                document.selection = $0
                document.selectionBindingVersions.append(bindingVersion)
                document.afterSelectionWrite?()
            }
        )
        let input: AnyView
        switch control {
        case .field:
            if bindsSelection {
                input = AnyView(TextField("Text", text: text, selection: selection))
            } else {
                input = AnyView(
                    TextField("Text", text: text, onEditingChanged: { document.onEditingChanged?($0) })
                )
            }
        case .editor:
            input = AnyView(TextEditor(text: text, selection: bindsSelection ? selection : nil))
        case .secure:
            input = AnyView(SecureField("Password", text: text))
        }
        let configured: AnyView
        if let undoCommand {
            configured = AnyView(input.onUndoCommand(perform: undoCommand))
        } else {
            configured = input
        }
        return
            configured
            .disabled(isDisabled)
            .accessibilityIdentifier(identifier)
            .frame(width: 300, height: 120)
    }
}

@MainActor
private struct UndoTestRoot: View {
    @Environment(\.undoManager) private var hostedManager

    let state: UndoTestState

    var body: some View {
        state.hostedManager = hostedManager
        let manager: WinSwiftUI.UndoManager?
        switch state.managerPolicy {
        case .inherited:
            manager = hostedManager
        case .custom(let custom):
            manager = custom
        }
        let document = state.document
        let undoCommand: (() -> Void)? =
            state.installsUndoCommand ? { state.undoCommandCalls += 1 } : nil
        return VStack(alignment: .leading, spacing: 4) {
            if state.showsEditor {
                UndoTestControlView(
                    document: document,
                    control: state.control,
                    bindsSelection: state.bindsSelection,
                    bindingVersion: state.bindingVersion,
                    isDisabled: state.isDisabled,
                    identifier: "undo-primary-editor",
                    undoCommand: undoCommand
                )
                .id(state.editorIdentity)
            }
            Button("Other control") {}
                .accessibilityIdentifier("undo-other-control")
            Text("Revision \(state.revision)")
        }
        .sheet(
            isPresented: Binding(
                get: { state.showsModal },
                set: { state.showsModal = $0 }
            )
        ) {
            UndoTestControlView(
                document: state.modal,
                control: state.modalControl,
                bindsSelection: false,
                bindingVersion: state.bindingVersion,
                isDisabled: false,
                identifier: "undo-modal-editor",
                undoCommand: nil
            )
        }
        .environment(\.undoManager, manager)
        .environment(\.textInputClipboard, state.clipboard)
        .windowDismissBehavior(state.preventsClosing ? .disabled : .automatic)
    }
}

@MainActor
private func undoTestNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private final class UndoTestFixture {
    let state: UndoTestState
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    private var isActive = true

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init(
        control: UndoTestControl = .editor,
        text: String = "abcd",
        bindsSelection: Bool = false,
        selection: TextSelection? = nil,
        managerPolicy: UndoTestManagerPolicy = .inherited
    ) throws {
        let state = UndoTestState(
            control: control,
            text: text,
            bindsSelection: bindsSelection,
            selection: selection,
            managerPolicy: managerPolicy
        )
        self.state = state
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 360, height: 320), scaleFactor: 1)
        window = Win32Window(title: "Text input undo", clientSize: surface.pixelSize)
        host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Text input undo",
                size: surface.pixelSize,
                clearColor: .black,
                content: [AnyView(UndoTestRoot(state: state))]
            ),
            platformWindow: window,
            renderer: FakeRenderBackend(),
            batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface },
            startupProbeConfiguration: nil
        )
        host.windowDidCreate(window)
        try focusEditor()
        render()
    }

    func close() {
        host.windowWillClose(window)
    }

    func render() {
        host.windowNeedsDisplay(window)
        _ = runtime.renderScene()
    }

    func rebuild() {
        state.revision += 1
        isActive.toggle()
        host.windowDidChangeActiveState(window, isActive: isActive)
        render()
    }

    func editor(_ identifier: String = "undo-primary-editor") throws -> ViewNode {
        try XCTUnwrap(
            undoTestNodes(in: runtime.root).first {
                $0.accessibilityTraits.contains(.isTextInput) && $0.accessibilityIdentifier == identifier
            }
        )
    }

    func focusEditor(_ identifier: String = "undo-primary-editor") throws {
        runtime.requestFocus(try editor(identifier))
        render()
    }

    func manager() throws -> WinSwiftUI.UndoManager {
        try XCTUnwrap(state.document.manager)
    }

    func key(code: UInt32, modifiers: KeyboardModifiers = []) {
        host.window(
            window,
            keyDown: KeyboardEvent(keyCode: code, modifiers: modifiers, textInputDelivery: .systemCharacter)
        )
        render()
    }

    func key(_ key: KeyboardKey, modifiers: KeyboardModifiers = []) {
        self.key(code: key.rawValue, modifiers: modifiers)
    }

    func undoKey() { key(code: 0x5A, modifiers: [.control]) }
    func redoKey() { key(code: 0x59, modifiers: [.control]) }
    func shiftedRedoKey() { key(code: 0x5A, modifiers: [.control, .shift]) }

    func type(_ text: String) {
        host.window(window, didInputText: text)
        render()
    }

    func compose(_ phase: IMECompositionEvent.Phase) {
        host.window(window, imeComposition: IMECompositionEvent(phase: phase))
        render()
    }

    func undoUsingManager() throws {
        try manager().undo()
        render()
    }

    func redoUsingManager() throws {
        try manager().redo()
        render()
    }
}

/// Public controls, the actual retained window host, and its environment
/// manager are exercised together. Fakes replace presentation and clipboard
/// access, and deterministic glyph advances avoid native font dependence.
@MainActor
final class TextInputUndoTests: XCTestCase {
    private static let characterAdvance = 9.0

    private func withTextLayout(_ body: () throws -> Void) throws {
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
        try body()
    }

    private func withFixture(
        control: UndoTestControl = .editor,
        text: String = "abcd",
        bindsSelection: Bool = false,
        selection: TextSelection? = nil,
        managerPolicy: UndoTestManagerPolicy = .inherited,
        _ body: (UndoTestFixture) throws -> Void
    ) throws {
        try withTextLayout {
            let fixture = try UndoTestFixture(
                control: control,
                text: text,
                bindsSelection: bindsSelection,
                selection: selection,
                managerPolicy: managerPolicy
            )
            defer { fixture.close() }
            try body(fixture)
        }
    }

    private func selection(_ range: Range<Int>, in text: String) -> TextSelection {
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        return TextSelection(range: lower..<upper)
    }

    private func boundSelectionOffsets(in document: UndoTestDocument) -> Range<Int>? {
        guard case .selection(let range) = document.selection?.indices,
            range.lowerBound >= document.text.startIndex,
            range.upperBound <= document.text.endIndex
        else { return nil }
        let lower = document.text.distance(from: document.text.startIndex, to: range.lowerBound)
        let upper = document.text.distance(from: document.text.startIndex, to: range.upperBound)
        return lower..<upper
    }

    func testPublicControlsRecordAcceptedEditsInTheEnvironmentManager() async throws {
        for control in [UndoTestControl.field, .editor] {
            try withFixture(control: control, text: "ab") { fixture in
                let manager = try fixture.manager()
                let editor = try fixture.editor()
                XCTAssertTrue(manager === fixture.state.hostedManager)
                XCTAssertFalse(manager.canUndo)

                fixture.type("X")

                XCTAssertEqual(fixture.state.primary.text, "abX")
                XCTAssertTrue(manager.canUndo)
                try fixture.undoUsingManager()
                XCTAssertEqual(fixture.state.primary.text, "ab")
                XCTAssertEqual(editor.textInputCaretOffset, 2)
                XCTAssertFalse(manager.canUndo)
                XCTAssertTrue(manager.canRedo)
                try fixture.redoUsingManager()
                XCTAssertEqual(fixture.state.primary.text, "abX")
                XCTAssertEqual(editor.textInputCaretOffset, 3)
                XCTAssertTrue(fixture.runtime.focusedNode === editor)
            }
        }
    }

    func testKeyboardUndoAndBothRedoShortcutsRestoreSeparateEdits() async throws {
        for control in [UndoTestControl.field, .editor] {
            try withFixture(control: control, text: "") { fixture in
                fixture.type("A")
                fixture.type("B")

                fixture.undoKey()
                XCTAssertEqual(fixture.state.primary.text, "A")
                fixture.shiftedRedoKey()
                XCTAssertEqual(fixture.state.primary.text, "AB")
                fixture.undoKey()
                XCTAssertEqual(fixture.state.primary.text, "A")
                fixture.redoKey()
                XCTAssertEqual(fixture.state.primary.text, "AB")
                fixture.undoKey()
                XCTAssertEqual(fixture.state.primary.text, "A")
                fixture.undoKey()
                XCTAssertEqual(fixture.state.primary.text, "")
                XCTAssertFalse(try fixture.manager().canUndo)
            }
        }
    }

    func testUnicodeSelectionAndCaretRoundTripAfterUnrelatedRebuild() async throws {
        let original = "A👩🏽‍💻e\u{301}Z"
        for control in [UndoTestControl.field, .editor] {
            try withFixture(
                control: control,
                text: original,
                bindsSelection: true,
                selection: selection(1..<3, in: original)
            ) { fixture in
                let editor = try fixture.editor()
                fixture.type("🧑‍🚀")
                XCTAssertEqual(fixture.state.primary.text, "A🧑‍🚀Z")
                XCTAssertEqual(editor.textInputCaretOffset, 2)
                fixture.rebuild()

                fixture.undoKey()

                XCTAssertEqual(fixture.state.primary.text, original)
                XCTAssertTrue(try fixture.editor() === editor)
                XCTAssertEqual(editor.textInputSelection?.indices, .range(1..<3))
                XCTAssertEqual(editor.textInputCaretOffset, 3)
                XCTAssertEqual(boundSelectionOffsets(in: fixture.state.primary), 1..<3)
                fixture.redoKey()
                XCTAssertEqual(fixture.state.primary.text, "A🧑‍🚀Z")
                XCTAssertEqual(editor.textInputCaretOffset, 2)
                XCTAssertEqual(boundSelectionOffsets(in: fixture.state.primary), 2..<2)
                XCTAssertTrue(fixture.runtime.focusedNode === editor)
            }
        }
    }

    func testUnboundCaretSnapshotSurvivesNavigationAndRebuildBeforeUndo() async throws {
        try withFixture { fixture in
            let editor = try fixture.editor()
            fixture.key(.home)
            fixture.key(.rightArrow)
            fixture.key(.rightArrow)
            fixture.type("X")
            fixture.key(.home)
            fixture.rebuild()

            try fixture.undoUsingManager()

            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertEqual(editor.textInputCaretOffset, 2)
            XCTAssertNil(editor.textInputSelection)
            try fixture.redoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "abXcd")
            XCTAssertEqual(editor.textInputCaretOffset, 3)
        }
    }

    func testPasteAndBackspaceEachCreateOneUndoableEdit() async throws {
        let original = "A👩🏽‍💻e\u{301}Z"
        for control in [UndoTestControl.field, .editor] {
            try withFixture(
                control: control,
                text: original,
                bindsSelection: true,
                selection: selection(1..<3, in: original)
            ) { fixture in
                fixture.state.clipboard.value = "Q"
                fixture.key(code: 0x56, modifiers: [.control])
                XCTAssertEqual(fixture.state.primary.text, "AQZ")
                fixture.key(.backspace)
                XCTAssertEqual(fixture.state.primary.text, "AZ")

                fixture.undoKey()
                XCTAssertEqual(fixture.state.primary.text, "AQZ")
                XCTAssertEqual(try fixture.editor().textInputCaretOffset, 2)
                fixture.undoKey()
                XCTAssertEqual(fixture.state.primary.text, original)
                XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(1..<3))
                XCTAssertFalse(try fixture.manager().canUndo)
                fixture.redoKey()
                XCTAssertEqual(fixture.state.primary.text, "AQZ")
                fixture.redoKey()
                XCTAssertEqual(fixture.state.primary.text, "AZ")
            }
        }
    }

    func testCutUsesTheInjectedClipboardAndUndoRestoresTheSelection() async throws {
        try withFixture(text: "abcd", bindsSelection: true, selection: selection(1..<3, in: "abcd")) { fixture in
            fixture.key(code: 0x58, modifiers: [.control])
            XCTAssertEqual(fixture.state.clipboard.value, "bc")
            XCTAssertEqual(fixture.state.primary.text, "ad")

            fixture.undoKey()

            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(1..<3))
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 3)
            XCTAssertFalse(try fixture.manager().canUndo)
            fixture.redoKey()
            XCTAssertEqual(fixture.state.primary.text, "ad")
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
        }
    }

    func testNewAcceptedEditInvalidatesRedo() async throws {
        try withFixture(text: "") { fixture in
            fixture.type("A")
            fixture.type("B")
            fixture.undoKey()
            XCTAssertTrue(try fixture.manager().canRedo)

            fixture.type("C")

            XCTAssertEqual(fixture.state.primary.text, "AC")
            XCTAssertFalse(try fixture.manager().canRedo)
            fixture.redoKey()
            XCTAssertEqual(fixture.state.primary.text, "AC")
            fixture.undoKey()
            XCTAssertEqual(fixture.state.primary.text, "A")
            fixture.undoKey()
            XCTAssertEqual(fixture.state.primary.text, "")
        }
    }

    func testSelectionChangesAndNoOpReplacementDoNotAddOrEraseHistory() async throws {
        try withFixture(text: "a") { fixture in
            fixture.type("B")
            fixture.key(code: 0x41, modifiers: [.control])
            fixture.type("aB")
            XCTAssertEqual(fixture.state.primary.text, "aB")

            fixture.undoKey()

            XCTAssertEqual(fixture.state.primary.text, "a")
            XCTAssertFalse(try fixture.manager().canUndo)
            fixture.redoKey()
            XCTAssertEqual(fixture.state.primary.text, "aB")
        }
    }

    func testIMEUpdatesAndCancellationDoNotRecordHistory() async throws {
        try withFixture(text: "ab") { fixture in
            fixture.compose(.started)
            fixture.compose(.updated("n"))
            fixture.compose(.updated("ni"))
            fixture.rebuild()
            XCTAssertEqual(try fixture.editor().textInputMarkedText, "ni")
            XCTAssertFalse(try fixture.manager().canUndo)
            fixture.compose(.ended)

            fixture.compose(.started)
            fixture.compose(.updated("cancel"))
            fixture.key(.escape)
            fixture.compose(.ended)

            XCTAssertEqual(fixture.state.primary.text, "ab")
            XCTAssertTrue(fixture.state.primary.attemptedValues.isEmpty)
            XCTAssertNil(try fixture.editor().textInputMarkedText)
            XCTAssertFalse(try fixture.manager().canUndo)
            XCTAssertFalse(try fixture.manager().canRedo)
        }
    }

    func testIMECommitCreatesOneUndoableReplacement() async throws {
        for control in [UndoTestControl.field, .editor] {
            try withFixture(
                control: control,
                text: "ab",
                bindsSelection: true,
                selection: selection(1..<2, in: "ab")
            ) { fixture in
                fixture.compose(.started)
                fixture.compose(.updated("n"))
                fixture.compose(.updated("ni"))
                fixture.compose(.committed("你"))
                fixture.compose(.ended)
                XCTAssertEqual(fixture.state.primary.text, "a你")
                XCTAssertEqual(fixture.state.primary.attemptedValues.count, 1)

                fixture.undoKey()

                XCTAssertEqual(fixture.state.primary.text, "ab")
                XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(1..<2))
                XCTAssertEqual(try fixture.editor().textInputCaretOffset, 2)
                XCTAssertFalse(try fixture.manager().canUndo)
                fixture.redoKey()
                XCTAssertEqual(fixture.state.primary.text, "a你")
                XCTAssertNil(try fixture.editor().textInputMarkedText)
            }
        }
    }

    func testIMECommitDoesNotPermitReplayUntilTheActiveSessionEnds() async throws {
        try withFixture(text: "ab") { fixture in
            fixture.compose(.started)
            fixture.compose(.updated("ni"))
            fixture.compose(.committed("你"))
            fixture.undoKey()
            try fixture.undoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "ab你")
            XCTAssertTrue(try fixture.manager().canUndo)
            fixture.compose(.ended)
            fixture.undoKey()
            XCTAssertEqual(fixture.state.primary.text, "ab")
            XCTAssertFalse(try fixture.manager().canUndo)
        }
    }

    func testFocusExitCancelsMarkedTextBeforeUnfocusedReplay() async throws {
        try withFixture(text: "ab") { fixture in
            fixture.type("X")
            fixture.compose(.started)
            fixture.compose(.updated("uncommitted"))
            let other = try XCTUnwrap(
                undoTestNodes(in: fixture.runtime.root).first { $0.accessibilityIdentifier == "undo-other-control" })
            fixture.runtime.requestFocus(other)
            XCTAssertNil(try fixture.editor().textInputMarkedText)
            try fixture.undoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "ab")
            XCTAssertNil(try fixture.editor().textInputMarkedText)
        }
    }

    func testSecureFieldDoesNotRecordOrReplaySecretText() async throws {
        try withFixture(control: .secure, text: "start") { fixture in
            fixture.type("secret")
            fixture.rebuild()
            fixture.undoKey()
            fixture.shiftedRedoKey()
            fixture.redoKey()
            try fixture.undoUsingManager()
            try fixture.redoUsingManager()

            XCTAssertEqual(fixture.state.primary.text, "startsecret")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["startsecret"])
            XCTAssertFalse(try fixture.manager().canUndo)
            XCTAssertFalse(try fixture.manager().canRedo)
        }
    }

    func testRejectedSetterClearsEarlierHistoryWithoutRecordingTheProposal() async throws {
        try withFixture(text: "a") { fixture in
            fixture.type("B")
            XCTAssertTrue(try fixture.manager().canUndo)
            fixture.state.primary.setterPolicy = .reject

            fixture.type("C")

            XCTAssertEqual(fixture.state.primary.text, "aB")
            XCTAssertFalse(try fixture.manager().canUndo)
            XCTAssertFalse(try fixture.manager().canRedo)
            let writes = fixture.state.primary.attemptedValues.count
            try fixture.undoUsingManager()
            try fixture.redoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "aB")
            XCTAssertEqual(fixture.state.primary.attemptedValues.count, writes)
        }
    }

    func testNormalizedSetterClearsHistoryInsteadOfRecordingStaleProposedText() async throws {
        try withFixture(text: "a") { fixture in
            fixture.type("B")
            fixture.state.primary.setterPolicy = .uppercase

            fixture.type("c")

            XCTAssertEqual(fixture.state.primary.attemptedValues.last, "aBc")
            XCTAssertEqual(fixture.state.primary.text, "ABC")
            XCTAssertFalse(try fixture.manager().canUndo)
            XCTAssertFalse(try fixture.manager().canRedo)
            let writes = fixture.state.primary.attemptedValues.count
            try fixture.undoUsingManager()
            try fixture.redoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "ABC")
            XCTAssertEqual(fixture.state.primary.attemptedValues.count, writes)
        }
    }

    func testRejectedUndoDoesNotLeaveAReciprocalRedoAction() async throws {
        try withFixture(text: "a") { fixture in
            fixture.type("B")
            fixture.state.primary.setterPolicy = .reject

            try fixture.undoUsingManager()

            XCTAssertEqual(fixture.state.primary.text, "aB")
            XCTAssertFalse(try fixture.manager().canUndo)
            XCTAssertFalse(try fixture.manager().canRedo)
            fixture.state.primary.setterPolicy = .accept
            try fixture.redoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "aB")
        }
    }

    func testReplayUsesLatestTextAndSelectionBindingClosuresAfterRebuild() async throws {
        try withFixture(text: "ab", bindsSelection: true, selection: selection(2..<2, in: "ab")) { fixture in
            fixture.type("X")
            let selectionWritesBefore = fixture.state.primary.selectionBindingVersions.count
            fixture.state.bindingVersion = 1
            fixture.rebuild()

            try fixture.undoUsingManager()
            try fixture.redoUsingManager()

            XCTAssertEqual(fixture.state.primary.text, "abX")
            XCTAssertEqual(fixture.state.primary.textBindingVersions, [0, 1, 1])
            let replaySelectionVersions = fixture.state.primary.selectionBindingVersions.dropFirst(
                selectionWritesBefore)
            XCTAssertFalse(replaySelectionVersions.isEmpty)
            XCTAssertTrue(replaySelectionVersions.allSatisfy { $0 == 1 })
            XCTAssertEqual(boundSelectionOffsets(in: fixture.state.primary), 3..<3)
        }
    }

    func testExternalTextReplacementBeforeAFrameInvalidatesStaleUndoAndRedo() async throws {
        for replaysRedo in [false, true] {
            try withFixture(text: "ab") { fixture in
                fixture.type("X")
                if replaysRedo { try fixture.undoUsingManager() }
                let manager = try fixture.manager()
                let writesBefore = fixture.state.primary.attemptedValues.count
                fixture.state.primary.text = "external replacement"

                // Deliberately do not rebuild, render, or query availability
                // between the external replacement and the replay request.
                if replaysRedo {
                    manager.redo()
                } else {
                    manager.undo()
                }

                XCTAssertEqual(fixture.state.primary.text, "external replacement")
                XCTAssertEqual(fixture.state.primary.attemptedValues.count, writesBefore)
                XCTAssertFalse(manager.canUndo)
                XCTAssertFalse(manager.canRedo)
                fixture.render()
            }
        }
    }

    func testFirstEditAfterExternalReplacementStartsFreshHistory() async throws {
        try withFixture(text: "ab") { fixture in
            fixture.type("X")
            fixture.state.primary.text = "NEW"

            fixture.type("Y")

            XCTAssertEqual(fixture.state.primary.text, "NEWY")
            fixture.undoKey()
            XCTAssertEqual(fixture.state.primary.text, "NEW")
            XCTAssertFalse(try fixture.manager().canUndo)
            fixture.redoKey()
            XCTAssertEqual(fixture.state.primary.text, "NEWY")
        }
    }

    func testExplicitIdentityChangeClearsHistoryForAnEqualTextModelSwitch() async throws {
        try withFixture(text: "ab") { fixture in
            fixture.type("X")
            let previousEditor = try fixture.editor()
            let manager = try fixture.manager()
            fixture.state.alternate.text = "abX"
            fixture.state.usesAlternateDocument = true
            fixture.state.editorIdentity = "different-document"
            fixture.rebuild()
            try fixture.focusEditor()

            XCTAssertFalse(try fixture.editor() === previousEditor)
            XCTAssertFalse(manager.canUndo)
            manager.undo()
            XCTAssertEqual(fixture.state.primary.text, "abX")
            XCTAssertEqual(fixture.state.alternate.text, "abX")
            fixture.type("Y")
            fixture.undoKey()
            XCTAssertEqual(fixture.state.alternate.text, "abX")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["abX"])
            XCTAssertEqual(fixture.state.alternate.attemptedValues, ["abXY", "abX"])
        }
    }

    func testDisabledEditorDoesNotConsumeItsBlockedUndoAction() async throws {
        try withFixture(text: "ab") { fixture in
            fixture.type("X")
            let manager = try fixture.manager()
            fixture.state.isDisabled = true
            fixture.rebuild()
            XCTAssertFalse(try fixture.editor().isFocusable)

            manager.undo()
            fixture.render()
            fixture.undoKey()

            XCTAssertEqual(fixture.state.primary.text, "abX")
            XCTAssertTrue(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            fixture.state.isDisabled = false
            fixture.rebuild()
            try fixture.focusEditor()
            fixture.undoKey()
            XCTAssertEqual(fixture.state.primary.text, "ab")
            XCTAssertTrue(manager.canRedo)
        }
    }

    func testModalEditorCannotConsumeBackgroundHistory() async throws {
        try withFixture(text: "ab") { fixture in
            fixture.type("X")
            let manager = try fixture.manager()
            fixture.state.showsModal = true
            fixture.rebuild()
            try fixture.focusEditor("undo-modal-editor")
            XCTAssertTrue(fixture.state.modal.manager === manager)

            fixture.undoKey()
            manager.undo()
            fixture.render()

            XCTAssertEqual(fixture.state.primary.text, "abX")
            XCTAssertEqual(fixture.state.modal.text, "")
            XCTAssertTrue(manager.canUndo)
            fixture.type("M")
            fixture.undoKey()
            XCTAssertEqual(fixture.state.modal.text, "")
            fixture.undoKey()
            XCTAssertEqual(fixture.state.primary.text, "abX")
            fixture.state.showsModal = false
            fixture.rebuild()
            try fixture.focusEditor()
            fixture.undoKey()
            XCTAssertEqual(fixture.state.primary.text, "ab")
        }
    }

    func testNilEnvironmentManagerDisablesAutomaticHistory() async throws {
        try withFixture(text: "ab", managerPolicy: .custom(nil)) { fixture in
            XCTAssertNil(fixture.state.primary.manager)
            let defaultManager = try XCTUnwrap(fixture.state.hostedManager)
            fixture.type("X")
            fixture.undoKey()
            fixture.shiftedRedoKey()
            fixture.redoKey()

            XCTAssertEqual(fixture.state.primary.text, "abX")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["abX"])
            XCTAssertFalse(defaultManager.canUndo)
            XCTAssertFalse(defaultManager.canRedo)
        }
    }

    func testEnvironmentOverrideUsesOnlyTheSuppliedManager() async throws {
        let override = WinSwiftUI.UndoManager()
        try withFixture(text: "ab", managerPolicy: .custom(override)) { fixture in
            XCTAssertTrue(try fixture.manager() === override)
            let defaultManager = try XCTUnwrap(fixture.state.hostedManager)
            XCTAssertFalse(defaultManager === override)
            fixture.type("X")

            XCTAssertTrue(override.canUndo)
            XCTAssertFalse(defaultManager.canUndo)
            override.undo()
            fixture.render()
            XCTAssertEqual(fixture.state.primary.text, "ab")
        }
    }

    func testHostedDefaultManagersKeepWindowHistoriesSeparate() async throws {
        try withTextLayout {
            let first = try UndoTestFixture(control: .field, text: "ab")
            defer { first.close() }
            let second = try UndoTestFixture(control: .editor, text: "cd")
            defer { second.close() }
            let firstManager = try first.manager()
            let secondManager = try second.manager()
            XCTAssertFalse(firstManager === secondManager)
            first.type("X")
            second.type("Y")

            try first.undoUsingManager()

            XCTAssertEqual(first.state.primary.text, "ab")
            XCTAssertEqual(second.state.primary.text, "cdY")
            XCTAssertFalse(firstManager.canUndo)
            XCTAssertTrue(secondManager.canUndo)
            try second.undoUsingManager()
            XCTAssertEqual(second.state.primary.text, "cd")
        }
    }

    func testRemovingOneEditorPreservesOtherHistoryInASharedManager() async throws {
        try withTextLayout {
            let manager = WinSwiftUI.UndoManager()
            let first = try UndoTestFixture(control: .field, text: "ab", managerPolicy: .custom(manager))
            defer { first.close() }
            let second = try UndoTestFixture(control: .editor, text: "cd", managerPolicy: .custom(manager))
            defer { second.close() }
            first.type("X")
            second.type("Y")

            first.state.showsEditor = false
            first.rebuild()
            manager.undo()
            second.render()

            XCTAssertEqual(first.state.primary.text, "abX")
            XCTAssertEqual(second.state.primary.text, "cd")
            XCTAssertFalse(manager.canUndo)
            manager.redo()
            second.render()
            XCTAssertEqual(second.state.primary.text, "cdY")
        }
    }

    func testKeyboardOriginFilterDoesNotRefreshOrPurgeAnotherWindowsHistory() async throws {
        try withTextLayout {
            let manager = WinSwiftUI.UndoManager()
            let first = try UndoTestFixture(control: .field, text: "ab", managerPolicy: .custom(manager))
            defer { first.close() }
            let second = try UndoTestFixture(control: .editor, text: "cd", managerPolicy: .custom(manager))
            defer { second.close() }
            first.type("X")
            second.type("Y")
            second.state.primary.text = "external replacement"

            first.undoKey()
            // The cross-window keyboard request must not have preflighted
            // and purged the second window's stale entry. This first direct
            // replay therefore invalidates it without undoing the first.
            manager.undo()

            XCTAssertEqual(first.state.primary.text, "abX")
            XCTAssertEqual(second.state.primary.text, "external replacement")
            manager.undo()
            XCTAssertEqual(first.state.primary.text, "ab")
        }
    }

    func testRefusedWindowClosePreservesUndoHistory() async throws {
        try withFixture(control: .field, text: "ab") { fixture in
            fixture.type("X")
            fixture.state.preventsClosing = true
            fixture.rebuild()
            let manager = try fixture.manager()

            XCTAssertFalse(fixture.host.windowShouldClose(fixture.window))

            XCTAssertTrue(manager.canUndo)
            XCTAssertEqual(fixture.state.primary.text, "abX")
            try fixture.undoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "ab")
            XCTAssertTrue(manager.canRedo)
            fixture.state.preventsClosing = false
            fixture.rebuild()
            XCTAssertTrue(fixture.host.windowShouldClose(fixture.window))
        }
    }

    func testClosingInvalidatesHistoryBeforeDeliveringFocusExit() async throws {
        for closesWithSheet in [false, true] {
            try withFixture(control: .field, text: "ab") { fixture in
                fixture.type("X")
                let manager = try fixture.manager()
                let focusedDocument: UndoTestDocument
                if closesWithSheet {
                    fixture.state.modalControl = .field
                    fixture.state.modal.text = "sheet"
                    fixture.state.showsModal = true
                    fixture.rebuild()
                    try fixture.focusEditor("undo-modal-editor")
                    fixture.type("Y")
                    focusedDocument = fixture.state.modal
                } else {
                    focusedDocument = fixture.state.primary
                }
                var undoAvailabilityAtFocusExit: [Bool] = []
                focusedDocument.onEditingChanged = { isEditing in
                    guard !isEditing else { return }
                    undoAvailabilityAtFocusExit.append(manager.canUndo)
                    manager.undo()
                }

                fixture.close()

                XCTAssertEqual(
                    undoAvailabilityAtFocusExit, [false],
                    "The normal focus-exit notification must fire after every closing editor's history is invalidated"
                )
                XCTAssertEqual(fixture.state.primary.text, "abX")
                if closesWithSheet { XCTAssertEqual(fixture.state.modal.text, "sheetY") }
                XCTAssertFalse(manager.canUndo)
                XCTAssertFalse(manager.canRedo)
                fixture.host.window(fixture.window, didInputText: "ignored after close")
                manager.undo()
                XCTAssertEqual(fixture.state.primary.text, "abX")
                if closesWithSheet { XCTAssertEqual(fixture.state.modal.text, "sheetY") }
                focusedDocument.onEditingChanged = nil
            }
        }
    }

    func testClosingOneWindowPreservesOtherHistoryInASharedManager() async throws {
        try withTextLayout {
            let manager = WinSwiftUI.UndoManager()
            let first = try UndoTestFixture(control: .field, text: "ab", managerPolicy: .custom(manager))
            defer { first.close() }
            let second = try UndoTestFixture(control: .editor, text: "cd", managerPolicy: .custom(manager))
            defer { second.close() }
            first.type("X")
            second.type("Y")

            first.close()
            XCTAssertTrue(manager.canUndo)
            manager.undo()
            second.render()

            XCTAssertEqual(first.state.primary.text, "abX")
            XCTAssertEqual(second.state.primary.text, "cd")
            XCTAssertFalse(manager.canUndo)
            XCTAssertTrue(manager.canRedo)
            manager.redo()
            second.render()
            XCTAssertEqual(second.state.primary.text, "cdY")
        }
    }

    func testNonEditorFocusAndAltModifiedShortcutsDoNotReplayHistory() async throws {
        try withFixture(text: "ab") { fixture in
            fixture.type("X")
            let otherControl = try XCTUnwrap(
                undoTestNodes(in: fixture.runtime.root).first { $0.accessibilityIdentifier == "undo-other-control" }
            )
            fixture.runtime.requestFocus(otherControl)
            fixture.undoKey()
            XCTAssertEqual(fixture.state.primary.text, "abX")

            try fixture.focusEditor()
            fixture.key(code: 0x5A, modifiers: [.control, .alt])
            fixture.key(code: 0x5A, modifiers: [.control, .shift, .alt])
            fixture.key(code: 0x59, modifiers: [.control, .alt])
            XCTAssertEqual(fixture.state.primary.text, "abX")
            XCTAssertTrue(try fixture.manager().canUndo)
            fixture.undoKey()
            XCTAssertEqual(fixture.state.primary.text, "ab")
        }
    }

    func testClosingDefaultManagerOwnerPreservesHistoryFromAnotherWindowUsingItsManager() async throws {
        try withTextLayout {
            let first = try UndoTestFixture(control: .field, text: "ab")
            defer { first.close() }
            let sharedManager = try first.manager()
            let second = try UndoTestFixture(control: .editor, text: "cd", managerPolicy: .custom(sharedManager))
            defer { second.close() }
            first.type("X")
            second.type("Y")

            first.close()
            sharedManager.undo()
            second.render()

            XCTAssertEqual(first.state.primary.text, "abX")
            XCTAssertEqual(second.state.primary.text, "cd")
            XCTAssertFalse(sharedManager.canUndo)
            XCTAssertTrue(sharedManager.canRedo)
            sharedManager.redo()
            second.render()
            XCTAssertEqual(second.state.primary.text, "cdY")
        }
    }

    func testExplicitUndoCommandTakesPrecedenceOverAutomaticEditorUndo() async throws {
        try withFixture(text: "ab") { fixture in
            fixture.state.installsUndoCommand = true
            fixture.rebuild()
            try fixture.focusEditor()
            fixture.type("X")

            fixture.undoKey()

            XCTAssertEqual(fixture.state.undoCommandCalls, 1)
            XCTAssertEqual(fixture.state.primary.text, "abX")
            XCTAssertTrue(try fixture.manager().canUndo)
            try fixture.undoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "ab")
        }
    }

    func testEditUndoAndRedoSurviveSynchronousSetterRebuildsWithFreshBindings() async throws {
        for control in [UndoTestControl.field, .editor] {
            try withFixture(control: control) { fixture in
                let editor = try fixture.editor()
                fixture.key(.home)
                fixture.key(.rightArrow)
                let reloadsBefore = fixture.host.executedReloadCount
                var callbackCount = 0
                fixture.state.primary.afterTextWrite = { [weak fixture] in
                    guard let fixture else { return }
                    callbackCount += 1
                    fixture.state.bindingVersion += 1
                    fixture.rebuild()
                }
                defer { fixture.state.primary.afterTextWrite = nil }

                fixture.type("X")
                XCTAssertEqual(fixture.state.primary.text, "aXbcd")
                XCTAssertEqual(editor.textInputCaretOffset, 2)
                fixture.undoKey()
                XCTAssertEqual(fixture.state.primary.text, "abcd")
                XCTAssertEqual(editor.textInputCaretOffset, 1)
                fixture.redoKey()

                XCTAssertEqual(fixture.state.primary.text, "aXbcd")
                XCTAssertEqual(editor.textInputCaretOffset, 2)
                XCTAssertEqual(callbackCount, 3)
                XCTAssertEqual(fixture.state.bindingVersion, 3)
                XCTAssertEqual(fixture.state.primary.textBindingVersions, [0, 1, 2])
                XCTAssertGreaterThanOrEqual(fixture.host.executedReloadCount, reloadsBefore + 3)
                XCTAssertTrue(try fixture.editor() === editor)
                XCTAssertTrue(fixture.runtime.focusedNode === editor)
                XCTAssertTrue(try fixture.manager().canUndo)
                XCTAssertFalse(try fixture.manager().canRedo)
            }
        }
    }

    func testUndoTextSetterCanRemoveTheEditorWithoutRegisteringRedo() async throws {
        try withFixture { fixture in
            fixture.type("X")
            let manager = try fixture.manager()
            let removedEditor = try fixture.editor()
            fixture.state.primary.afterTextWrite = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.showsEditor = false
                fixture.rebuild()
            }
            defer { fixture.state.primary.afterTextWrite = nil }

            try fixture.undoUsingManager()

            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertFalse(
                undoTestNodes(in: fixture.runtime.root).contains { $0.accessibilityTraits.contains(.isTextInput) }
            )
            XCTAssertFalse(fixture.runtime.focusedNode === removedEditor)
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            fixture.type("ignored")
            manager.redo()
            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["abcdX", "abcd"])
        }
    }

    func testUndoTextSetterCanCloseTheHostWithoutLeavingRedoOrAcceptingLaterInput() async throws {
        try withFixture { fixture in
            fixture.type("X")
            let manager = try fixture.manager()
            fixture.state.primary.afterTextWrite = { [weak fixture] in
                fixture?.close()
            }
            defer { fixture.state.primary.afterTextWrite = nil }

            manager.undo()

            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertNil(fixture.host.windowTextInputCaretRect(fixture.window))
            XCTAssertNil(fixture.runtime.focusedNode)
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            fixture.host.window(fixture.window, didInputText: "ignored after close")
            fixture.host.window(
                fixture.window,
                keyDown: KeyboardEvent(keyCode: 0x59, modifiers: [.control], textInputDelivery: .systemCharacter)
            )
            manager.redo()
            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["abcdX", "abcd"])
        }
    }

    func testUndoTextSetterSelectionOverrideWinsAfterSynchronousRebuild() async throws {
        try withFixture(text: "abcd", bindsSelection: true, selection: selection(2..<2, in: "abcd")) { fixture in
            fixture.type("X")
            let editor = try fixture.editor()
            fixture.state.primary.afterTextWrite = { [weak fixture] in
                guard let fixture else { return }
                let text = fixture.state.primary.text
                let upper = text.index(after: text.startIndex)
                fixture.state.primary.selection = TextSelection(range: text.startIndex..<upper)
                fixture.state.bindingVersion += 1
                fixture.rebuild()
            }
            defer { fixture.state.primary.afterTextWrite = nil }

            try fixture.undoUsingManager()

            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(0..<1))
            XCTAssertEqual(editor.textInputCaretOffset, 1)
            XCTAssertEqual(boundSelectionOffsets(in: fixture.state.primary), 0..<1)
            fixture.state.primary.afterTextWrite = nil
            fixture.type("Q")
            XCTAssertEqual(fixture.state.primary.text, "Qbcd")
            XCTAssertEqual(editor.textInputCaretOffset, 1)
        }
    }

    func testUndoSelectionSetterCanRemoveTheEditorWithoutRegisteringAnInverse() async throws {
        try withFixture(text: "abcd", bindsSelection: true, selection: selection(2..<2, in: "abcd")) { fixture in
            fixture.type("X")
            let manager = try fixture.manager()
            var selectionCallbackCount = 0
            fixture.state.primary.afterSelectionWrite = { [weak fixture] in
                guard let fixture else { return }
                selectionCallbackCount += 1
                fixture.state.showsEditor = false
                fixture.rebuild()
            }
            defer { fixture.state.primary.afterSelectionWrite = nil }

            try fixture.undoUsingManager()

            XCTAssertEqual(selectionCallbackCount, 1)
            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertFalse(
                undoTestNodes(in: fixture.runtime.root).contains { $0.accessibilityTraits.contains(.isTextInput) }
            )
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            fixture.type("ignored")
            manager.redo()
            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["abXcd", "abcd"])
        }
    }

    func testHistoryResetBeforeAnEditCannotWriteAfterClosingTheHost() async throws {
        try withFixture(text: "a") { fixture in
            fixture.type("b")
            let manager = try fixture.manager()
            var releaseCount = 0
            do {
                let target = UndoTestExpiredTarget()
                let payload = UndoTestReleaseCallback { [weak fixture] in
                    releaseCount += 1
                    fixture?.close()
                }
                manager.registerUndo(withTarget: target) { _ in withExtendedLifetime(payload) {} }
            }
            fixture.state.primary.text = "XY"

            fixture.type("Z")

            XCTAssertEqual(releaseCount, 1)
            XCTAssertEqual(fixture.state.primary.text, "XY")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["ab"])
            XCTAssertNil(fixture.runtime.focusedNode)
            XCTAssertNil(fixture.host.windowTextInputCaretRect(fixture.window))
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testHistoryResetRebuildAbortsTheOldWriteAndNextEditUsesTheFreshBinding() async throws {
        try withFixture(text: "a") { fixture in
            fixture.type("b")
            let originalEditor = try fixture.editor()
            let manager = try fixture.manager()
            var releaseCount = 0
            do {
                let target = UndoTestExpiredTarget()
                let payload = UndoTestReleaseCallback { [weak fixture] in
                    guard let fixture else { return }
                    releaseCount += 1
                    fixture.state.bindingVersion += 1
                    fixture.rebuild()
                }
                manager.registerUndo(withTarget: target) { _ in withExtendedLifetime(payload) {} }
            }
            fixture.state.primary.text = "XY"

            fixture.type("Z")

            XCTAssertEqual(releaseCount, 1)
            XCTAssertTrue(try fixture.editor() === originalEditor)
            XCTAssertEqual(fixture.state.primary.text, "XY")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["ab"])
            XCTAssertFalse(manager.canUndo)
            fixture.type("Z")
            XCTAssertEqual(fixture.state.primary.text, "XYZ")
            XCTAssertEqual(fixture.state.primary.textBindingVersions, [0, 1])
            try fixture.undoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "XY")
            XCTAssertEqual(fixture.state.primary.textBindingVersions, [0, 1, 1])
            XCTAssertTrue(manager.canRedo)
        }
    }

    func testSelectionGetterCannotWriteAfterClosingTheHost() async throws {
        try withFixture(text: "a", bindsSelection: true) { fixture in
            fixture.type("b")
            let manager = try fixture.manager()
            var getterCallbacks = 0
            fixture.state.primary.beforeSelectionRead = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.primary.beforeSelectionRead = nil
                getterCallbacks += 1
                fixture.close()
            }
            defer { fixture.state.primary.beforeSelectionRead = nil }

            fixture.type("c")

            XCTAssertEqual(getterCallbacks, 1)
            XCTAssertEqual(fixture.state.primary.text, "ab")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["ab"])
            XCTAssertNil(fixture.runtime.focusedNode)
            XCTAssertNil(fixture.host.windowTextInputCaretRect(fixture.window))
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testSelectionGetterRebuildCancelsTheUnwrittenEditWithoutBlockingEarlierUndo() async throws {
        try withFixture(text: "a", bindsSelection: true) { fixture in
            fixture.type("b")
            let originalEditor = try fixture.editor()
            let manager = try fixture.manager()
            fixture.state.primary.beforeSelectionRead = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.primary.beforeSelectionRead = nil
                fixture.state.bindingVersion += 1
                fixture.rebuild()
            }
            defer { fixture.state.primary.beforeSelectionRead = nil }

            fixture.type("c")

            XCTAssertTrue(try fixture.editor() === originalEditor)
            XCTAssertEqual(fixture.state.primary.text, "ab")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["ab"])
            XCTAssertTrue(manager.canUndo)
            try fixture.undoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "a")
            XCTAssertEqual(fixture.state.primary.textBindingVersions, [0, 1])
            XCTAssertTrue(manager.canRedo)
        }
    }

    func testUndoSelectionGetterCannotWriteAfterClosingTheHost() async throws {
        try withFixture(text: "a", bindsSelection: true) { fixture in
            fixture.type("b")
            let manager = try fixture.manager()
            var getterCallbacks = 0
            fixture.state.primary.beforeSelectionRead = { [weak fixture] in
                guard let fixture, manager.isUndoing else { return }
                fixture.state.primary.beforeSelectionRead = nil
                getterCallbacks += 1
                fixture.close()
            }
            defer { fixture.state.primary.beforeSelectionRead = nil }

            manager.undo()

            XCTAssertEqual(getterCallbacks, 1)
            XCTAssertEqual(fixture.state.primary.text, "ab")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["ab"])
            XCTAssertNil(fixture.runtime.focusedNode)
            XCTAssertNil(fixture.host.windowTextInputCaretRect(fixture.window))
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testDisablingUndoRegistrationStillAcceptsAnOrdinaryEditWithoutATicket() async throws {
        try withFixture(text: "a") { fixture in
            fixture.type("b")
            let manager = try fixture.manager()
            manager.disableUndoRegistration()

            fixture.type("c")

            XCTAssertEqual(fixture.state.primary.text, "abc")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["ab", "abc"])
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            manager.enableUndoRegistration()
            fixture.type("d")
            try fixture.undoUsingManager()
            XCTAssertEqual(fixture.state.primary.text, "abc")
            XCTAssertTrue(manager.canRedo)
        }
    }

    func testHistoryCleanupCannotOverwriteANewerProgrammaticReplacement() async throws {
        try withFixture(text: "a") { fixture in
            fixture.type("b")
            let manager = try fixture.manager()
            var releaseCount = 0
            do {
                let target = UndoTestExpiredTarget()
                let payload = UndoTestReleaseCallback { [weak fixture] in
                    releaseCount += 1
                    fixture?.state.primary.text = "newer model text"
                }
                manager.registerUndo(withTarget: target) { _ in withExtendedLifetime(payload) {} }
            }
            fixture.state.primary.text = "XY"

            fixture.type("Z")

            XCTAssertEqual(releaseCount, 1)
            XCTAssertEqual(fixture.state.primary.text, "newer model text")
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["ab"])
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testSelectionGetterProgrammaticReplacementWinsOverOrdinaryAndUndoWrites() async throws {
        for replaying in [false, true] {
            try withFixture(text: "a", bindsSelection: true) { fixture in
                fixture.type("b")
                let manager = try fixture.manager()
                var getterCallbacks = 0
                fixture.state.primary.beforeSelectionRead = { [weak fixture] in
                    guard let fixture, !replaying || manager.isUndoing else { return }
                    fixture.state.primary.beforeSelectionRead = nil
                    getterCallbacks += 1
                    fixture.state.primary.text = "XY"
                }
                defer { fixture.state.primary.beforeSelectionRead = nil }

                if replaying { manager.undo() } else { fixture.type("c") }

                XCTAssertEqual(getterCallbacks, 1)
                XCTAssertEqual(fixture.state.primary.text, "XY")
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["ab"])
                XCTAssertFalse(manager.canUndo)
                XCTAssertFalse(manager.canRedo)
            }
        }
    }
}
