import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

private struct DocumentUndoTestRow: Equatable {
    var text: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text.utf8.elementsEqual(rhs.text.utf8)
    }
}

private struct DocumentUndoGateValue {
    var storage = "before"
    var onAssignment: (() -> Void)?

    var text: String {
        get { storage }
        set {
            storage = newValue
            onAssignment?()
        }
    }
}

/// A small value-shaped document, deliberately compared by bytes so the
/// fixture does not hide canonically equivalent but different UTF-8 edits.
private struct DocumentUndoTestValue: Equatable {
    var text: String
    var alternate = "alternate"
    var optionalText: String? = "optional"
    var rows = [DocumentUndoTestRow(text: "row")]
    var computedTextWrites = 0

    var countedText: String {
        get { text }
        set {
            text = newValue
            computedTextWrites += 1
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        let sameOptional: Bool
        switch (lhs.optionalText, rhs.optionalText) {
        case (.none, .none): sameOptional = true
        case (.some(let left), .some(let right)): sameOptional = left.utf8.elementsEqual(right.utf8)
        default: sameOptional = false
        }
        return lhs.text.utf8.elementsEqual(rhs.text.utf8)
            && lhs.alternate.utf8.elementsEqual(rhs.alternate.utf8)
            && sameOptional && lhs.rows == rhs.rows && lhs.computedTextWrites == rhs.computedTextWrites
    }
}

/// Tests the editor/session ownership handshake, not FileDocument I/O or a
/// production document-history implementation. Only this fake registers
/// document actions; the public editor supplies its optional selection ticket.
@MainActor
private final class DocumentUndoTestOwner: DocumentTextUndoOwner {
    private struct Edit {
        let before: DocumentUndoTestValue
        let after: DocumentUndoTestValue
        let receipt: DocumentTextUndoReceipt?
    }

    var documentUndoManager: WinSwiftUI.UndoManager?
    var documentUndoGeneration: UInt64 = 0
    var documentMutationRevision: UInt64 = 0
    var documentUndoIsValid = true
    var documentAllowsTextMutation = true
    weak var runtime: RetainedViewRuntime?
    lazy var source = DocumentBindingSource(owner: self)
    private(set) var value: DocumentUndoTestValue
    private(set) var contexts: [(any BindingMutationContext)?] = []
    private(set) var receipts: [DocumentTextUndoReceipt?] = []
    private(set) var committedValues: [DocumentUndoTestValue] = []
    private(set) var bindingVersions: [Int] = []
    private(set) var replayCount = 0
    private(set) var rejectedWrites = 0
    private(set) var savedUTF8: [UInt8]
    var beforeCommit: (() -> Void)?
    var afterValueCommit: (() -> Void)?
    var afterCommit: (() -> Void)?
    var afterReplay: (() -> Void)?
    var didChange: (() -> Void)?

    init(text: String = "a", manager: WinSwiftUI.UndoManager? = WinSwiftUI.UndoManager()) {
        value = DocumentUndoTestValue(text: text)
        documentUndoManager = manager
        savedUTF8 = Array(text.utf8)
    }

    var isDirty: Bool { !value.text.utf8.elementsEqual(savedUTF8) }

    func documentUndoBelongs(to runtime: RetainedViewRuntime) -> Bool {
        self.runtime === runtime
    }

    func prepareForUndoReplay() -> Bool {
        documentUndoIsValid && documentAllowsTextMutation && source.permitsReplay
    }

    func binding(version: Int = 0) -> Binding<DocumentUndoTestValue> {
        let fallback = value
        return Binding(
            get: { [weak self] in self?.value ?? fallback },
            set: { [weak self] value, _, mutation in
                self?.accept(value, mutation: mutation, bindingVersion: version)
            },
            isValidForWrite: { [weak self] in
                self?.documentUndoIsValid == true && self?.documentAllowsTextMutation == true
            },
            mutationSource: source
        )
    }

    func assignText(_ text: String) {
        var next = value
        next.text = text
        binding().wrappedValue = next
    }

    func markSaved() { savedUTF8 = Array(value.text.utf8) }

    private func accept(
        _ next: DocumentUndoTestValue, mutation: (any BindingMutationContext)?, bindingVersion: Int
    ) {
        guard documentUndoIsValid, documentAllowsTextMutation else { return }
        let generation = documentUndoGeneration
        let revision = documentMutationRevision
        let ticket: DocumentTextEditTicket?
        if let mutation {
            guard let candidate = mutation as? DocumentTextEditTicket, candidate.consume(for: self) else {
                rejectedWrites += 1
                return
            }
            ticket = candidate
        } else {
            ticket = nil
        }
        beforeCommit?()
        guard documentUndoIsValid, documentAllowsTextMutation,
            documentUndoGeneration == generation, documentMutationRevision == revision
        else {
            rejectedWrites += 1
            return
        }
        guard next != value else { return }
        let before = value
        value = next
        documentMutationRevision &+= 1
        afterValueCommit?()
        let receipt = ticket?.didCommit(for: self, revision: documentMutationRevision)
        contexts.append(mutation)
        receipts.append(receipt)
        committedValues.append(next)
        bindingVersions.append(bindingVersion)
        register(Edit(before: before, after: next, receipt: receipt), undoing: true)
        // The accepted action already has its own identity before callbacks
        // can synchronously write another value through the root binding.
        afterCommit?()
        didChange?()
    }

    private func register(_ edit: Edit, undoing: Bool) {
        guard documentUndoIsValid, let manager = documentUndoManager else { return }
        manager.registerUndo(withTarget: self, actionName: "Edit Document") { owner in
            owner.replay(edit, undoing: undoing)
        }
    }

    private func replay(_ edit: Edit, undoing: Bool) {
        guard prepareForUndoReplay(), value == (undoing ? edit.after : edit.before) else { return }
        let generation = documentUndoGeneration
        let selectionReplay = edit.receipt?.prepareSelectionReplay(for: self, undoing: undoing)
        guard documentUndoIsValid, documentUndoGeneration == generation else { return }
        value = undoing ? edit.before : edit.after
        documentMutationRevision &+= 1
        let revision = documentMutationRevision
        replayCount += 1
        register(edit, undoing: !undoing)
        afterReplay?()
        didChange?()
        // Removing the editor here only removes optional selection behavior;
        // it cannot erase the reciprocal document action above.
        selectionReplay?.restore(for: self, revision: revision)
    }
}

@MainActor
private final class DocumentUndoTestState {
    var owner: DocumentUndoTestOwner?
    let retainedBinding: Binding<DocumentUndoTestValue>
    let environmentManager: WinSwiftUI.UndoManager
    var usesDocumentBinding = true
    var alternateProjection = false
    var countedProjection = false
    var usesSecureField = false
    var localText = "local"
    var showsEditor = true
    var bindsSelection = false
    var selection: TextSelection?
    var selectionWriteVersions: [Int] = []
    var beforeSelectionRead: (() -> Void)?
    var selectionReadOverride: (() -> TextSelection?)?
    var afterSelectionWrite: (() -> Void)?
    var bindingVersion = 0
    var revision = 0

    init(owner: DocumentUndoTestOwner, environmentManager: WinSwiftUI.UndoManager) {
        self.owner = owner
        retainedBinding = owner.binding()
        self.environmentManager = environmentManager
    }

    var presentedText: String {
        guard usesDocumentBinding else { return localText }
        let value = owner?.value ?? retainedBinding.wrappedValue
        return alternateProjection ? value.alternate : value.text
    }
}

@MainActor
private struct DocumentUndoTestRoot: View {
    let state: DocumentUndoTestState

    var body: some View {
        let document = state.owner?.binding(version: state.bindingVersion) ?? state.retainedBinding
        let text: Binding<String>
        if state.usesDocumentBinding {
            if state.countedProjection {
                text = document.countedText
            } else {
                text = state.alternateProjection ? document.alternate : document.text
            }
        } else {
            text = Binding(get: { state.localText }, set: { state.localText = $0 })
        }
        let version = state.bindingVersion
        let selection = Binding<TextSelection?>(
            get: {
                if let selectionReadOverride = state.selectionReadOverride { return selectionReadOverride() }
                state.beforeSelectionRead?()
                return state.selection
            },
            set: {
                state.selection = $0
                state.selectionWriteVersions.append(version)
                state.afterSelectionWrite?()
            }
        )
        let input: AnyView
        if state.usesSecureField {
            input = AnyView(SecureField("Secret", text: text))
        } else {
            input = AnyView(TextEditor(text: text, selection: state.bindsSelection ? selection : nil))
        }
        return VStack(alignment: .leading, spacing: 0) {
            if state.showsEditor {
                input
                    .font(.system(size: 16))
                    .lineSpacing(0)
                    .environment(\.undoManager, Optional(state.environmentManager))
                    .accessibilityIdentifier("document-undo-editor")
                    .id("document-undo-editor")
                    .frame(width: 300, height: 120)
            }
            Text("Revision \(state.revision)")
        }
    }
}

@MainActor
private func documentUndoNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private final class DocumentUndoTestFixture {
    let state: DocumentUndoTestState
    let runtime: RetainedViewRuntime
    let host: ComponentHost

    init(
        owner: DocumentUndoTestOwner = DocumentUndoTestOwner(),
        environmentManager: WinSwiftUI.UndoManager? = nil,
        usesDocumentBinding: Bool = true,
        selection: TextSelection? = nil,
        bindsSelection: Bool = false
    ) throws {
        let state = DocumentUndoTestState(
            owner: owner,
            environmentManager: environmentManager ?? owner.documentUndoManager ?? WinSwiftUI.UndoManager())
        state.usesDocumentBinding = usesDocumentBinding
        state.selection = selection
        state.bindsSelection = bindsSelection
        self.state = state
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 500, height: 300)))
        self.runtime = runtime
        owner.runtime = runtime
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 500, height: 300) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents { [DocumentUndoTestRoot(state: state).makeComponent(context: context)] }
        owner.didChange = { [weak host] in host?.reload() }
        runtime.requestFocus(try editor())
        render()
    }

    func editor() throws -> ViewNode {
        try XCTUnwrap(documentUndoNodes(in: runtime.root).first { $0.accessibilityTraits.contains(.isTextInput) })
    }

    func render() { _ = runtime.renderScene() }

    func reload() {
        state.revision += 1
        host.reload()
        render()
    }

    func type(_ text: String) {
        runtime.imeComposition(IMECompositionEvent(phase: .committed(text), source: .keyboard))
        render()
    }

    func compose(_ phase: IMECompositionEvent.Phase) {
        runtime.imeComposition(IMECompositionEvent(phase: phase))
        render()
    }

    func key(_ key: KeyboardKey, modifiers: KeyboardModifiers = []) {
        runtime.keyDown(KeyboardEvent(keyCode: key.rawValue, modifiers: modifiers, textInputDelivery: .systemCharacter))
        render()
    }

    func undoKey() {
        runtime.keyDown(KeyboardEvent(keyCode: 0x5A, modifiers: [.control]))
        render()
    }

    func redoKey() {
        runtime.keyDown(KeyboardEvent(keyCode: 0x59, modifiers: [.control]))
        render()
    }

    func boundRange() -> Range<Int>? {
        guard case .selection(let range) = state.selection?.indices else { return nil }
        let text = state.presentedText
        let boundaries = Array(text.indices) + [text.endIndex]
        guard let lower = boundaries.firstIndex(of: range.lowerBound),
            let upper = boundaries.firstIndex(of: range.upperBound), lower <= upper
        else { return nil }
        return lower..<upper
    }
}

@MainActor
private final class DocumentUndoOtherTarget {
    var calls = 0
}

@MainActor
private final class DocumentUndoBindingSource: BindingMutationSource {}

@MainActor
private final class DocumentUndoBindingContext: BindingMutationContext {}

@MainActor
final class DocumentTextUndoTests: XCTestCase {
    private func withLayout(_ body: () throws -> Void) rethrows {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let characters = Array(text)
            let glyphs = characters.enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character,
                    origin: Point(x: Double(index) * 9, y: 0),
                    advance: 9,
                    glyphID: UInt32(index + 1),
                    fontFamily: style.fontFamily,
                    weight: style.weight,
                    fontSize: style.nativeFontPixelSize,
                    sourceIndex: index)
            }
            let width = Double(characters.count) * 9
            let height = max(1, style.nativeFontPixelSize)
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: width, height: height, glyphs: glyphs)],
                contentSize: Size(width: width, height: height), measuredSize: Size(width: width, height: height))
        }
        defer { NativeTextRenderer.resetTestingOverrides() }
        try body()
    }

    private func selection(
        _ range: Range<Int>, in text: String, affinity: TextSelectionAffinity = .downstream
    ) -> TextSelection {
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        var selection = TextSelection(range: lower..<upper)
        selection.affinity = affinity
        return selection
    }

    func testOrdinaryBindingStillUsesItsLocalTextHistory() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fixture = try DocumentUndoTestFixture(owner: owner, usesDocumentBinding: false)
            fixture.type("X")
            XCTAssertEqual(fixture.state.localText, "localX")
            XCTAssertTrue(fixture.state.environmentManager.canUndo)
            XCTAssertTrue(owner.committedValues.isEmpty)
            fixture.undoKey()
            XCTAssertEqual(fixture.state.localText, "local")
            XCTAssertFalse(fixture.state.environmentManager.canUndo)
            fixture.redoKey()
            XCTAssertEqual(fixture.state.localText, "localX")
        }
    }

    func testTextDirectAssignmentAndTextAreExactlyThreeInterleavableActions() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let manager = try XCTUnwrap(owner.documentUndoManager)
            let fixture = try DocumentUndoTestFixture(owner: owner)
            fixture.type("b")
            owner.assignText("direct")
            fixture.key(.end, modifiers: [.control])
            fixture.type("!")
            XCTAssertEqual(owner.value.text, "direct!")
            XCTAssertEqual(owner.committedValues.map(\.text), ["ab", "direct", "direct!"])
            XCTAssertEqual(owner.receipts.map { $0 != nil }, [true, false, true])
            for expected in ["direct", "ab", "a"] {
                fixture.undoKey()
                XCTAssertEqual(owner.value.text, expected)
            }
            XCTAssertFalse(manager.canUndo)
            for expected in ["ab", "direct", "direct!"] {
                fixture.redoKey()
                XCTAssertEqual(owner.value.text, expected)
            }
            XCTAssertFalse(manager.canRedo)
            XCTAssertEqual(owner.committedValues.count, 3)
        }
    }

    func testSaveCheckpointMetadataAddsNoActionAndUndoReturnsToSavedBytes() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fixture = try DocumentUndoTestFixture(owner: owner)
            fixture.type("b")
            let revision = owner.documentMutationRevision
            owner.markSaved()
            XCTAssertFalse(owner.isDirty)
            XCTAssertEqual(owner.documentMutationRevision, revision)
            fixture.type("c")
            XCTAssertTrue(owner.isDirty)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "ab")
            XCTAssertFalse(owner.isDirty)
            XCTAssertEqual(owner.committedValues.count, 2)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertTrue(owner.isDirty)
            XCTAssertFalse(try XCTUnwrap(owner.documentUndoManager).canUndo)
        }
    }

    func testDocumentOwnerManagerWinsOverAnEnvironmentOverride() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let environment = WinSwiftUI.UndoManager()
            let fixture = try DocumentUndoTestFixture(owner: owner, environmentManager: environment)
            fixture.type("b")
            XCTAssertFalse(environment.canUndo)
            XCTAssertTrue(try XCTUnwrap(owner.documentUndoManager).canUndo)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertFalse(environment.canRedo)
        }
    }

    func testNilDocumentManagerNeverFallsBackToLocalEnvironmentHistory() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner(manager: nil)
            let fallback = WinSwiftUI.UndoManager()
            let fixture = try DocumentUndoTestFixture(owner: owner, environmentManager: fallback)
            fixture.type("b")
            XCTAssertEqual(owner.value.text, "ab")
            XCTAssertFalse(fallback.canUndo)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "ab")
            XCTAssertFalse(fallback.canRedo)
        }
    }

    func testDisabledDocumentRegistrationDoesNotCreateALocalTextAction() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let manager = try XCTUnwrap(owner.documentUndoManager)
            let fallback = WinSwiftUI.UndoManager()
            let fixture = try DocumentUndoTestFixture(owner: owner, environmentManager: fallback)
            manager.disableUndoRegistration()
            fixture.type("b")
            manager.enableUndoRegistration()
            XCTAssertEqual(owner.value.text, "ab")
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(fallback.canUndo)
        }
    }

    func testExpiredOwnerKeepsTheBindingMarkedAndCannotCreateFallbackHistory() async throws {
        try withLayout {
            var owner: DocumentUndoTestOwner? = DocumentUndoTestOwner()
            weak var weakOwner = owner
            let fallback = WinSwiftUI.UndoManager()
            let fixture = try DocumentUndoTestFixture(owner: try XCTUnwrap(owner), environmentManager: fallback)
            let oldBinding = fixture.state.retainedBinding.text
            fixture.state.owner = nil
            owner = nil
            XCTAssertNil(weakOwner)
            XCTAssertNotNil(oldBinding.mutationSource)
            oldBinding.wrappedValue = "late"
            fixture.reload()
            fixture.type("late")
            XCTAssertEqual(oldBinding.wrappedValue, "a")
            XCTAssertFalse(fallback.canUndo)
        }
    }

    func testReadOnlyDocumentRejectsEditingWithoutCreatingFallbackHistory() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fallback = WinSwiftUI.UndoManager()
            let fixture = try DocumentUndoTestFixture(owner: owner, environmentManager: fallback)
            owner.documentAllowsTextMutation = false
            fixture.reload()
            fixture.type("blocked")
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertTrue(owner.committedValues.isEmpty)
            XCTAssertFalse(fallback.canUndo)
            XCTAssertFalse(try XCTUnwrap(owner.documentUndoManager).canUndo)
        }
    }

    func testManagedSecureFieldCannotWriteSecretsIntoDocumentHistory() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fallback = WinSwiftUI.UndoManager()
            let fixture = try DocumentUndoTestFixture(owner: owner, environmentManager: fallback)
            fixture.state.usesSecureField = true
            fixture.reload()
            fixture.runtime.requestFocus(try fixture.editor())
            fixture.type("secret")
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertTrue(owner.committedValues.isEmpty)
            XCTAssertFalse(fallback.canUndo)
            XCTAssertFalse(try XCTUnwrap(owner.documentUndoManager).canUndo)
        }
    }

    func testRemovingTheEditorPreservesTheDocumentUndoAndRedoActions() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let manager = try XCTUnwrap(owner.documentUndoManager)
            let fixture = try DocumentUndoTestFixture(owner: owner, bindsSelection: true)
            fixture.type("b")
            fixture.state.showsEditor = false
            fixture.reload()
            let selectionWrites = fixture.state.selectionWriteVersions.count
            XCTAssertTrue(manager.canUndo)
            manager.undo()
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertTrue(manager.canRedo)
            manager.redo()
            XCTAssertEqual(owner.value.text, "ab")
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, selectionWrites)
        }
    }

    func testSynchronousRebuildTransfersTheSelectionSidecarToFreshBindings() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner(text: "abcd")
            let fixture = try DocumentUndoTestFixture(
                owner: owner, selection: selection(2..<2, in: "abcd"), bindsSelection: true)
            let editor = try fixture.editor()
            owner.afterCommit = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.bindingVersion += 1
                fixture.reload()
            }
            owner.afterReplay = owner.afterCommit
            fixture.type("X")
            XCTAssertEqual(owner.value.text, "abXcd")
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "abcd")
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 2)
            fixture.redoKey()
            XCTAssertEqual(owner.value.text, "abXcd")
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 3)
            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertEqual(owner.bindingVersions, [0])
            XCTAssertEqual(fixture.state.selectionWriteVersions.last, 3)
        }
    }

    func testDirectionalUnicodeSelectionAndCaretRoundTripWithDocumentReplay() async throws {
        try withLayout {
            let original = "a👩🏽‍💻b"
            let owner = DocumentUndoTestOwner(text: original)
            let fixture = try DocumentUndoTestFixture(
                owner: owner, selection: selection(2..<2, in: original), bindsSelection: true)
            fixture.key(.leftArrow, modifiers: [.shift])
            XCTAssertEqual(fixture.boundRange(), 1..<2)
            XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            fixture.type("漢")
            XCTAssertEqual(owner.value.text, "a漢b")
            fixture.undoKey()
            XCTAssertEqual(Array(owner.value.text.utf8), Array(original.utf8))
            XCTAssertEqual(fixture.boundRange(), 1..<2)
            XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            fixture.redoKey()
            XCTAssertEqual(owner.value.text, "a漢b")
            XCTAssertEqual(fixture.boundRange(), 2..<2)
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 2)
        }
    }

    func testSelectionExplicitlyChangedByReplayCallbacksWinsOverTheSidecar() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner(text: "abcd")
            let fixture = try DocumentUndoTestFixture(
                owner: owner, selection: selection(2..<2, in: "abcd"), bindsSelection: true)
            fixture.type("X")
            owner.afterReplay = { [weak fixture, weak owner] in
                guard let fixture, let owner else { return }
                fixture.state.selection = self.selection(0..<1, in: owner.value.text)
                fixture.reload()
            }
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "abcd")
            XCTAssertEqual(fixture.boundRange(), 0..<1)
            XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(0..<1))
        }
    }

    func testPreparingSelectionReplayDoesNotReadApplicationSelectionBindings() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fixture = try DocumentUndoTestFixture(owner: owner, bindsSelection: true)
            fixture.type("b")
            let receipt = try XCTUnwrap(owner.receipts.last ?? nil)
            let revision = owner.documentMutationRevision
            var getterCalls = 0
            fixture.state.beforeSelectionRead = { [weak state = fixture.state, weak owner] in
                getterCalls += 1
                // A regression remains a bounded assertion failure: do not
                // recursively reenter this getter during the nested rebuild.
                state?.beforeSelectionRead = nil
                owner?.assignText("selection getter reentered")
            }
            let replay = receipt.prepareSelectionReplay(for: owner, undoing: true)
            XCTAssertNotNil(replay)
            XCTAssertEqual(getterCalls, 0)
            XCTAssertEqual(owner.value.text, "ab")
            XCTAssertEqual(owner.documentMutationRevision, revision)
            XCTAssertEqual(owner.committedValues.count, 1)
            fixture.state.beforeSelectionRead = nil
        }
    }

    func testSelectionRestorationDoesNotDrainOrOverwriteALateApplicationOverride() async throws {
        try withLayout {
            let text = "abcd"
            let owner = DocumentUndoTestOwner(text: text)
            let fixture = try DocumentUndoTestFixture(
                owner: owner, selection: selection(2..<2, in: text), bindsSelection: true)
            fixture.render()
            let editor = try fixture.editor()
            let client = try XCTUnwrap(editor.textInputController as? any DocumentTextUndoClient)
            let expectedSelection = fixture.state.selection
            let initialCaret = editor.textInputCaretOffset
            let selectionWrites = fixture.state.selectionWriteVersions.count
            let explicitSelection = selection(3..<4, in: text)
            let snapshot = TextInputUndoSelection(
                caret: 1,
                selection: RetainedTextSelection(indices: .range(0..<1), affinity: .downstream),
                affinity: .downstream)
            var getterCalls = 0
            var lateCallbacks = 0
            fixture.state.beforeSelectionRead = { [weak state = fixture.state, weak runtime = fixture.runtime] in
                getterCalls += 1
                state?.beforeSelectionRead = nil
                runtime?.scheduleAfterLayout(key: "document-undo-explicit-selection") { [weak state] in
                    lateCallbacks += 1
                    // Deliberately no rebuild: the restoration must not rely
                    // on controller replacement to notice newer selection.
                    state?.selection = explicitSelection
                }
            }
            client.restoreDocumentSelection(
                snapshot, expectedText: text, expectedBoundSelection: expectedSelection,
                validate: { owner.documentUndoIsValid })
            XCTAssertEqual(getterCalls, 1)
            XCTAssertEqual(lateCallbacks, 0)
            XCTAssertEqual(fixture.state.selection, expectedSelection)
            XCTAssertEqual(editor.textInputCaretOffset, initialCaret)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, selectionWrites)

            fixture.render()

            XCTAssertEqual(lateCallbacks, 1)
            XCTAssertEqual(fixture.state.selection, explicitSelection)
            XCTAssertEqual(fixture.boundRange(), 3..<4)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, selectionWrites)
            XCTAssertEqual(owner.value.text, text)
        }
    }

    func testGetterNestedLayoutCannotOverwriteASelectionChangedByAPrequeuedCallback() async throws {
        try withLayout {
            let text = "abcd"
            let owner = DocumentUndoTestOwner(text: text)
            let fixture = try DocumentUndoTestFixture(
                owner: owner, selection: selection(2..<2, in: text), bindsSelection: true)
            fixture.render()
            let editor = try fixture.editor()
            let client = try XCTUnwrap(editor.textInputController as? any DocumentTextUndoClient)
            let expectedSelection = fixture.state.selection
            let initialCaret = editor.textInputCaretOffset
            let selectionWrites = fixture.state.selectionWriteVersions.count
            let explicitSelection = selection(3..<4, in: text)
            let snapshot = TextInputUndoSelection(
                caret: 1,
                selection: RetainedTextSelection(indices: .range(0..<1), affinity: .downstream),
                affinity: .downstream)
            var firstCallbacks = 0
            var secondCallbacks = 0
            var getterCalls = 0
            var nestedFrame: Rect?
            var revisionBeforeNestedLayout: UInt64?
            var revisionAfterNestedLayout: UInt64?
            fixture.runtime.scheduleAfterLayout(key: "document-selection-first") {
                [weak runtime = fixture.runtime, weak state = fixture.state] in
                firstCallbacks += 1
                runtime?.scheduleAfterLayout(key: "document-selection-second") { [weak state] in
                    secondCallbacks += 1
                    // This callback only changes application selection. It
                    // neither invalidates the runtime nor rebuilds the editor.
                    state?.selection = explicitSelection
                }
            }
            fixture.state.selectionReadOverride = {
                [weak state = fixture.state, weak runtime = fixture.runtime, weak editor] in
                guard let state, let runtime, let editor else { return nil }
                getterCalls += 1
                let observed = state.selection
                state.selectionReadOverride = nil
                revisionBeforeNestedLayout = runtime.textInputReplayScopeRevision
                nestedFrame = runtime.resolvedLayoutFrame(of: editor)
                revisionAfterNestedLayout = runtime.textInputReplayScopeRevision
                // Returning the value read before reentry prevents the plain
                // bound-selection comparison from masking the missing stamp.
                return observed
            }
            client.restoreDocumentSelection(
                snapshot, expectedText: text, expectedBoundSelection: expectedSelection,
                validate: { owner.documentUndoIsValid })
            XCTAssertEqual(firstCallbacks, 1)
            XCTAssertEqual(secondCallbacks, 1)
            XCTAssertEqual(getterCalls, 1)
            XCTAssertNotNil(nestedFrame)
            XCTAssertNotNil(revisionBeforeNestedLayout)
            XCTAssertNotEqual(revisionAfterNestedLayout, revisionBeforeNestedLayout)
            XCTAssertEqual(fixture.state.selection, explicitSelection)
            XCTAssertEqual(editor.textInputCaretOffset, initialCaret)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, selectionWrites)
            XCTAssertEqual(owner.documentMutationRevision, 0)

            fixture.render()

            XCTAssertEqual(fixture.boundRange(), 3..<4)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, selectionWrites)
            XCTAssertEqual(owner.value.text, text)
        }
    }

    func testTextInputReplayScopeRevisionAdvancesNormally() async {
        var revision: UInt64? = 0
        advanceTextInputReplayScopeRevision(&revision)
        XCTAssertEqual(revision, 1)
        advanceTextInputReplayScopeRevision(&revision)
        XCTAssertEqual(revision, 2)
    }

    func testTextInputReplayScopeRevisionExhaustionNeverWraps() async {
        var revision: UInt64? = UInt64.max - 1
        advanceTextInputReplayScopeRevision(&revision)
        XCTAssertEqual(revision, UInt64.max)
        advanceTextInputReplayScopeRevision(&revision)
        XCTAssertNil(revision)
        advanceTextInputReplayScopeRevision(&revision)
        XCTAssertNil(revision)
    }

    func testNilTextInputReplayScopeRevisionRemainsInvalid() async {
        var revision: UInt64?
        for _ in 0..<3 { advanceTextInputReplayScopeRevision(&revision) }
        XCTAssertNil(revision)
    }

    func testChangingTheProjectionDoesNotRestoreSelectionIntoAnotherField() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner(text: "abcd")
            let fixture = try DocumentUndoTestFixture(
                owner: owner, selection: selection(2..<2, in: "abcd"), bindsSelection: true)
            fixture.type("X")
            fixture.state.alternateProjection = true
            fixture.state.selection = selection(1..<1, in: owner.value.alternate)
            fixture.reload()
            let writes = fixture.state.selectionWriteVersions.count
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "abcd")
            XCTAssertEqual(owner.value.alternate, "alternate")
            XCTAssertEqual(fixture.boundRange(), 1..<1)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, writes)
        }
    }

    func testSelectionCallbackRemovalCannotEraseTheReciprocalDocumentAction() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let manager = try XCTUnwrap(owner.documentUndoManager)
            let fixture = try DocumentUndoTestFixture(owner: owner, bindsSelection: true)
            fixture.type("b")
            fixture.state.afterSelectionWrite = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.showsEditor = false
                fixture.reload()
            }
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertFalse(fixture.state.showsEditor)
            XCTAssertTrue(manager.canRedo)
            manager.redo()
            XCTAssertEqual(owner.value.text, "ab")
        }
    }

    func testSelectionGetterRemovalCancelsTheUnwrittenDocumentEdit() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fixture = try DocumentUndoTestFixture(owner: owner, bindsSelection: true)
            fixture.state.beforeSelectionRead = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.beforeSelectionRead = nil
                fixture.state.showsEditor = false
                fixture.reload()
            }
            fixture.type("b")
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertTrue(owner.committedValues.isEmpty)
            XCTAssertFalse(try XCTUnwrap(owner.documentUndoManager).canUndo)
        }
    }

    func testNestedAssignmentBeforeCommitInvalidatesTheUnwrittenTicket() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fixture = try DocumentUndoTestFixture(owner: owner)
            owner.beforeCommit = { [weak owner] in
                guard let owner else { return }
                owner.beforeCommit = nil
                owner.assignText("nested")
            }
            fixture.type("b")
            XCTAssertEqual(owner.value.text, "nested")
            XCTAssertEqual(owner.committedValues.map(\.text), ["nested"])
            XCTAssertEqual(owner.receipts.map { $0 != nil }, [false])
            XCTAssertEqual(owner.rejectedWrites, 1)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertFalse(try XCTUnwrap(owner.documentUndoManager).canUndo)
        }
    }

    func testNestedAssignmentAfterCommitGetsItsOwnActionWithoutTheEditorTicket() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fixture = try DocumentUndoTestFixture(owner: owner, bindsSelection: true)
            owner.afterCommit = { [weak owner] in
                guard let owner else { return }
                owner.afterCommit = nil
                owner.assignText("nested")
            }
            fixture.type("b")
            XCTAssertEqual(owner.value.text, "nested")
            XCTAssertEqual(owner.committedValues.map(\.text), ["ab", "nested"])
            XCTAssertEqual(owner.receipts.map { $0 != nil }, [true, false])
            XCTAssertNotNil(owner.contexts.first ?? nil)
            XCTAssertNil(owner.contexts.last ?? nil)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "ab")
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertFalse(try XCTUnwrap(owner.documentUndoManager).canUndo)
        }
    }

    func testCanonicallyEquivalentEditorReplacementPreservesExactUTF8History() async throws {
        try withLayout {
            let decomposed = "e\u{301}"
            let composed = "\u{E9}"
            let owner = DocumentUndoTestOwner(text: decomposed)
            let fixture = try DocumentUndoTestFixture(
                owner: owner, selection: selection(0..<1, in: decomposed), bindsSelection: true)
            fixture.type(composed)
            XCTAssertEqual(Array(owner.value.text.utf8), Array(composed.utf8))
            XCTAssertEqual(owner.committedValues.count, 1)
            XCTAssertNotNil(owner.receipts.first ?? nil)
            fixture.undoKey()
            XCTAssertEqual(Array(owner.value.text.utf8), Array(decomposed.utf8))
            fixture.redoKey()
            XCTAssertEqual(Array(owner.value.text.utf8), Array(composed.utf8))
        }
    }

    func testIdenticalTextStillInvokesAComputedProjectionThatChangesTheDocument() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fixture = try DocumentUndoTestFixture(
                owner: owner, selection: selection(0..<1, in: "a"), bindsSelection: true)
            fixture.state.countedProjection = true
            fixture.reload()
            fixture.type("a")
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertEqual(owner.value.computedTextWrites, 1)
            XCTAssertEqual(owner.committedValues.count, 1)
            XCTAssertNotNil(owner.receipts.first ?? nil)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertEqual(owner.value.computedTextWrites, 0)
            fixture.redoKey()
            XCTAssertEqual(owner.value.computedTextWrites, 1)
            XCTAssertEqual(owner.committedValues.count, 1)
        }
    }

    func testCombiningInsertionRestoresOnlyWholeGraphemeSelectionOffsets() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fixture = try DocumentUndoTestFixture(
                owner: owner, selection: selection(1..<1, in: "a"), bindsSelection: true)
            fixture.type("\u{301}")
            XCTAssertEqual(Array(owner.value.text.utf8), Array("a\u{301}".utf8))
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertEqual(fixture.boundRange(), 1..<1)
            fixture.redoKey()
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            XCTAssertEqual(fixture.boundRange(), 1..<1)
        }
    }

    func testIMEPreeditAndCancellationDoNotRegisterAndCommitBlocksReplayUntilEnd() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let fixture = try DocumentUndoTestFixture(owner: owner)
            fixture.compose(.started)
            fixture.compose(.updated("候補"))
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertTrue(owner.committedValues.isEmpty)
            fixture.compose(.ended)
            XCTAssertTrue(owner.committedValues.isEmpty)
            fixture.compose(.started)
            fixture.compose(.updated("漢"))
            fixture.compose(.committed("漢"))
            XCTAssertEqual(owner.value.text, "a漢")
            XCTAssertEqual(owner.committedValues.count, 1)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a漢")
            XCTAssertTrue(try XCTUnwrap(owner.documentUndoManager).canUndo)
            try XCTUnwrap(owner.documentUndoManager).undo()
            XCTAssertEqual(owner.value.text, "a漢")
            fixture.compose(.ended)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a")
        }
    }

    func testDocumentKeyboardUndoDoesNotConsumeAnUnrelatedTopTarget() async throws {
        try withLayout {
            let owner = DocumentUndoTestOwner()
            let manager = try XCTUnwrap(owner.documentUndoManager)
            let fixture = try DocumentUndoTestFixture(owner: owner)
            fixture.type("b")
            let other = DocumentUndoOtherTarget()
            manager.registerUndo(withTarget: other) { $0.calls += 1 }
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "ab")
            XCTAssertEqual(other.calls, 0)
            XCTAssertTrue(manager.canUndo)
            manager.undo()
            XCTAssertEqual(other.calls, 1)
            fixture.undoKey()
            XCTAssertEqual(owner.value.text, "a")
            XCTAssertFalse(manager.canUndo)
        }
    }

    func testSharedManagerKeyboardUndoCannotConsumeAnotherWindowsDocument() async throws {
        try withLayout {
            let manager = WinSwiftUI.UndoManager()
            let first = DocumentUndoTestOwner(text: "first", manager: manager)
            let second = DocumentUndoTestOwner(text: "second", manager: manager)
            let firstFixture = try DocumentUndoTestFixture(owner: first)
            let secondFixture = try DocumentUndoTestFixture(owner: second)
            firstFixture.type("1")
            secondFixture.type("2")
            firstFixture.undoKey()
            XCTAssertEqual(first.value.text, "first1")
            XCTAssertEqual(second.value.text, "second2")
            secondFixture.undoKey()
            XCTAssertEqual(second.value.text, "second")
            firstFixture.undoKey()
            XCTAssertEqual(first.value.text, "first")
            XCTAssertFalse(manager.canUndo)
        }
    }

    func testDynamicMemberKeepsSourceProjectionTransactionAndTheExactMutationObject() async {
        let source = DocumentUndoBindingSource()
        let token = DocumentUndoBindingContext()
        var value = DocumentUndoTestValue(text: "before")
        var mutations: [(any BindingMutationContext)?] = []
        var transactions: [Transaction] = []
        let binding = Binding(
            get: { value },
            set: { next, transaction, mutation in
                value = next
                transactions.append(transaction)
                mutations.append(mutation)
            },
            isValidForWrite: { true },
            mutationSource: source
        )
        var transaction = Transaction(animation: .linear(duration: 0.3))
        transaction.isContinuous = true
        let projected = binding.transaction(transaction).text.animation(.easeIn(duration: 0.7)).projectedValue
        XCTAssertTrue(projected.mutationSource === source)
        XCTAssertEqual(binding.mutationProjection, [])
        XCTAssertEqual(projected.mutationProjection, [\DocumentUndoTestValue.text] as [AnyKeyPath])
        projected.write("after", mutation: token)
        XCTAssertEqual(value.text, "after")
        XCTAssertTrue((mutations.first ?? nil) === token)
        XCTAssertEqual(transactions.first?.animation?.duration, 0.7)
        XCTAssertTrue(transactions.first?.isContinuous == true)
        projected.wrappedValue = "ordinary"
        XCTAssertEqual(mutations.count, 2)
        XCTAssertNil(mutations.last ?? nil)
    }

    func testOptionalAdaptersKeepTheMutationSourceAndTokenWithoutClaimingProjectionIdentity() async throws {
        let source = DocumentUndoBindingSource()
        let token = DocumentUndoBindingContext()
        var value = DocumentUndoTestValue(text: "before")
        var mutations: [(any BindingMutationContext)?] = []
        let binding = Binding(
            get: { value },
            set: { next, _, mutation in
                value = next
                mutations.append(mutation)
            },
            isValidForWrite: { true },
            mutationSource: source
        )
        let lifted = Binding<String?>(binding.text)
        XCTAssertTrue(lifted.mutationSource === source)
        XCTAssertNil(lifted.mutationProjection)
        lifted.write("lifted", mutation: token)
        XCTAssertEqual(value.text, "lifted")
        XCTAssertTrue((mutations.last ?? nil) === token)
        lifted.write(nil, mutation: token)
        XCTAssertEqual(mutations.count, 1)

        let unwrapped = try XCTUnwrap(Binding<String>(binding.optionalText))
        XCTAssertTrue(unwrapped.mutationSource === source)
        XCTAssertNil(unwrapped.mutationProjection)
        unwrapped.write("unwrapped", mutation: token)
        XCTAssertEqual(value.optionalText, "unwrapped")
        XCTAssertTrue((mutations.last ?? nil) === token)
        XCTAssertEqual(mutations.count, 2)
    }

    func testCollectionAndNestedMemberKeepTokenButDoNotClaimAStableSelectionProjection() async {
        let source = DocumentUndoBindingSource()
        let token = DocumentUndoBindingContext()
        var value = DocumentUndoTestValue(text: "before")
        var received: (any BindingMutationContext)?
        var duration: Double?
        let binding = Binding(
            get: { value },
            set: { next, transaction, mutation in
                value = next
                received = mutation
                duration = transaction.animation?.duration
            },
            isValidForWrite: { true },
            mutationSource: source
        )
        let element = binding.rows[0].text.animation(.linear(duration: 0.4))
        XCTAssertTrue(element.mutationSource === source)
        XCTAssertNil(element.mutationProjection)
        element.write("changed", mutation: token)
        XCTAssertEqual(value.rows[0].text, "changed")
        XCTAssertTrue(received === token)
        XCTAssertEqual(duration, 0.4)
    }

    func testLimitingWritesKeepsOwnershipAndComposesWithTheOriginalGate() async {
        let source = DocumentUndoBindingSource()
        let token = DocumentUndoBindingContext()
        var value = DocumentUndoTestValue(text: "before")
        var baseAllows = true
        var wrapperAllows = false
        var writes = 0
        var received: (any BindingMutationContext)?
        let binding = Binding(
            get: { value },
            set: { next, _, mutation in
                value = next
                writes += 1
                received = mutation
            },
            isValidForWrite: { baseAllows },
            mutationSource: source
        )
        let projected = binding.limitingWrites { wrapperAllows }.text
        XCTAssertTrue(projected.mutationSource === source)
        XCTAssertEqual(projected.mutationProjection, [\DocumentUndoTestValue.text] as [AnyKeyPath])
        projected.write("blocked", mutation: token)
        XCTAssertEqual(writes, 0)
        wrapperAllows = true
        baseAllows = false
        projected.wrappedValue = "also blocked"
        XCTAssertEqual(writes, 0)
        baseAllows = true
        projected.write("accepted", mutation: token)
        XCTAssertEqual(value.text, "accepted")
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(received === token)
    }

    func testProjectedGetterCanRevokeTheWriteGateBeforeTheRootSetterRuns() async {
        let source = DocumentUndoBindingSource()
        let token = DocumentUndoBindingContext()
        var allows = true
        var reads = 0
        var writes = 0
        let binding = Binding(
            get: {
                reads += 1
                allows = false
                return DocumentUndoTestValue(text: "before")
            },
            set: { _, _, _ in writes += 1 },
            isValidForWrite: { true },
            mutationSource: source
        ).limitingWrites { allows }
        binding.text.write("blocked", mutation: token)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(writes, 0)
    }

    func testGateAddedAfterProjectionStillRechecksAfterTheProjectionGetter() async {
        let source = DocumentUndoBindingSource()
        let token = DocumentUndoBindingContext()
        var allows = true
        var reads = 0
        var writes = 0
        let binding = Binding(
            get: {
                reads += 1
                allows = false
                return DocumentUndoTestValue(text: "before")
            },
            set: { _, _, _ in writes += 1 },
            isValidForWrite: { true },
            mutationSource: source
        )
        let projected = binding.text.limitingWrites { allows }
        XCTAssertTrue(projected.mutationSource === source)
        projected.write("blocked", mutation: token)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(writes, 0)
    }

    func testComputedProjectionSetterCanRevokeTheFinalGateBeforeRootCommit() async {
        let source = DocumentUndoBindingSource()
        let token = DocumentUndoBindingContext()
        var allows = true
        var projectionSetterCalls = 0
        var rootWrites = 0
        var value = DocumentUndoGateValue()
        value.onAssignment = {
            projectionSetterCalls += 1
            allows = false
        }
        let binding = Binding(
            get: { value },
            set: { next, _, _ in
                rootWrites += 1
                value = next
            },
            isValidForWrite: { true },
            mutationSource: source
        )
        binding.text.limitingWrites { allows }.write("blocked", mutation: token)
        XCTAssertEqual(projectionSetterCalls, 1)
        XCTAssertEqual(rootWrites, 0)
        XCTAssertEqual(value.storage, "before")
    }

    func testTicketsAreSingleUseAndCannotBeConsumedByAnotherOwner() async throws {
        let owner = DocumentUndoTestOwner()
        let other = DocumentUndoTestOwner()
        let wrongOwnerTicket = try XCTUnwrap(
            owner.source.beginEdit(
                before: "a", proposed: "ab", selection: TextInputUndoSelection(caret: 1), endpoint: nil))
        XCTAssertFalse(wrongOwnerTicket.consume(for: other))
        XCTAssertFalse(wrongOwnerTicket.consume(for: owner))
        let accepted = try XCTUnwrap(
            owner.source.beginEdit(
                before: "a", proposed: "ab", selection: TextInputUndoSelection(caret: 1), endpoint: nil))
        owner.binding().text.write("ab", mutation: accepted)
        XCTAssertEqual(owner.value.text, "ab")
        XCTAssertNotNil(accepted.receipt)
        XCTAssertFalse(accepted.consume(for: owner))
        XCTAssertNil(accepted.didCommit(for: owner, revision: owner.documentMutationRevision))
        XCTAssertNil(accepted.receipt?.prepareSelectionReplay(for: other, undoing: true))
        owner.binding().text.write("duplicate", mutation: accepted)
        XCTAssertEqual(owner.value.text, "ab")
        XCTAssertEqual(owner.committedValues.count, 1)
    }

    func testReservedEditorTicketCannotCommitAfterItsEndpointOrEditorRetires() async throws {
        try withLayout {
            for removesEditor in [false, true] {
                let owner = DocumentUndoTestOwner()
                let fixture = try DocumentUndoTestFixture(owner: owner)
                let client = try XCTUnwrap(try fixture.editor().textInputController as? any DocumentTextUndoClient)
                let endpoint = owner.source.endpoint(
                    for: client, projection: [\DocumentUndoTestValue.text], previous: nil)
                let ticket = try XCTUnwrap(
                    owner.source.beginEdit(
                        before: "a", proposed: "ab", selection: TextInputUndoSelection(caret: 1), endpoint: endpoint))
                XCTAssertTrue(ticket.permitsWrite)
                if removesEditor {
                    fixture.state.showsEditor = false
                    fixture.reload()
                } else {
                    endpoint.invalidate()
                }
                XCTAssertFalse(ticket.permitsWrite)
                owner.binding().text.write("ab", mutation: ticket)
                XCTAssertEqual(owner.value.text, "a")
                XCTAssertEqual(owner.value.computedTextWrites, 0)
                XCTAssertEqual(owner.documentMutationRevision, 0)
                XCTAssertTrue(owner.committedValues.isEmpty)
                XCTAssertTrue(owner.receipts.isEmpty)
                XCTAssertNil(ticket.receipt)
                XCTAssertFalse(try XCTUnwrap(owner.documentUndoManager).canUndo)
            }
        }
    }

    func testOptionalAndIndexedTicketsCommitWithoutAStableSelectionProjection() async throws {
        try withLayout {
            for usesCollection in [false, true] {
                for removesEditorAfterCommit in [false, true] {
                    let owner = DocumentUndoTestOwner()
                    let fixture = try DocumentUndoTestFixture(owner: owner, bindsSelection: true)
                    let manager = try XCTUnwrap(owner.documentUndoManager)
                    let client = try XCTUnwrap(try fixture.editor().textInputController as? any DocumentTextUndoClient)
                    let binding: Binding<String>
                    if usesCollection {
                        binding = owner.binding().rows[0].text
                    } else {
                        binding = try XCTUnwrap(Binding<String>(owner.binding().optionalText))
                    }
                    XCTAssertTrue(binding.mutationSource === owner.source)
                    XCTAssertNil(binding.mutationProjection)
                    let endpoint = owner.source.endpoint(
                        for: client, projection: binding.mutationProjection, previous: nil)
                    let before = binding.wrappedValue
                    let after = before + "!"
                    let ticket = try XCTUnwrap(
                        owner.source.beginEdit(
                            before: before, proposed: after,
                            selection: TextInputUndoSelection(caret: before.count), endpoint: endpoint))
                    XCTAssertTrue(ticket.permitsWrite)
                    // Keep the explicitly supplied live client current unless
                    // this case retires it between model commit and receipt.
                    owner.didChange = nil
                    if removesEditorAfterCommit {
                        owner.afterValueCommit = { [weak owner, weak fixture] in
                            owner?.afterValueCommit = nil
                            guard let fixture else { return }
                            fixture.state.showsEditor = false
                            fixture.reload()
                        }
                    }
                    binding.write(after, mutation: ticket)
                    XCTAssertEqual(binding.wrappedValue, after)
                    XCTAssertEqual(owner.documentMutationRevision, 1)
                    XCTAssertEqual(owner.committedValues.count, 1)
                    let receipt = try XCTUnwrap(ticket.receipt)
                    ticket.finish(text: after, selection: TextInputUndoSelection(caret: after.count))
                    XCTAssertNil(receipt.prepareSelectionReplay(for: owner, undoing: true))
                    XCTAssertNil(receipt.prepareSelectionReplay(for: owner, undoing: false))
                    manager.undo()
                    XCTAssertEqual(binding.wrappedValue, before)
                    XCTAssertTrue(manager.canRedo)
                    manager.redo()
                    XCTAssertEqual(binding.wrappedValue, after)
                    XCTAssertEqual(owner.committedValues.count, 1)
                }
            }
        }
    }

    func testCancelledAndRevisionStaleTicketsCannotCommitAProposedTextValue() async throws {
        let owner = DocumentUndoTestOwner()
        let cancelled = try XCTUnwrap(
            owner.source.beginEdit(
                before: "a", proposed: "ab", selection: TextInputUndoSelection(caret: 1), endpoint: nil))
        cancelled.cancel()
        owner.binding().text.write("ab", mutation: cancelled)
        XCTAssertEqual(owner.value.text, "a")
        let stale = try XCTUnwrap(
            owner.source.beginEdit(
                before: "a", proposed: "ac", selection: TextInputUndoSelection(caret: 1), endpoint: nil))
        owner.assignText("direct")
        owner.binding().text.write("ac", mutation: stale)
        XCTAssertEqual(owner.value.text, "direct")
        XCTAssertEqual(owner.committedValues.map(\.text), ["direct"])
        XCTAssertEqual(owner.rejectedWrites, 2)
    }

    func testCommitReceiptCannotClaimARevisionSkippedByANestedAssignment() async throws {
        let owner = DocumentUndoTestOwner()
        let ticket = try XCTUnwrap(
            owner.source.beginEdit(
                before: "a", proposed: "ab", selection: TextInputUndoSelection(caret: 1), endpoint: nil))
        XCTAssertTrue(ticket.consume(for: owner))
        owner.assignText("ab")
        let proposedRevision = owner.documentMutationRevision
        owner.assignText("nested")
        XCTAssertNil(ticket.didCommit(for: owner, revision: proposedRevision))
        XCTAssertNil(ticket.didCommit(for: owner, revision: owner.documentMutationRevision))
        XCTAssertNil(ticket.receipt)
        XCTAssertEqual(owner.value.text, "nested")
        XCTAssertEqual(owner.receipts.map { $0 != nil }, [false, false])
    }
}
