import Foundation
import SwiftWindowsCore
import SwiftWindowsPlatform
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

private struct UIAReplacementDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.utf8PlainText] }
    var text: String
    var alternate = "alternate"

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else {
            throw DocumentFileServiceError.notRegularFile
        }
        text = String(decoding: bytes, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private enum UIAReplacementInput {
    case field
    case editor
    case secure
}

private enum UIAReplacementTargetChange {
    case document
    case projection
    case removal
}

private enum UIAReplacementRefusal: Equatable {
    case readOnly
    case expiredOwner
    case disabled
    case secure
}

@MainActor
private final class UIADocumentReplacementState {
    var session: FileDocumentSession<UIAReplacementDocument>
    let environmentManager = WinSwiftUI.UndoManager()
    let input: UIAReplacementInput
    var isEnabled = true
    var showsEditor = true
    var alternateProjection = false
    var selection: TextSelection?
    var bindingVersion = 0
    var selectionWriteVersions: [Int] = []
    var staleSelectionWrites = 0

    init(session: FileDocumentSession<UIAReplacementDocument>, input: UIAReplacementInput) {
        self.session = session
        self.input = input
    }
}

@MainActor
private struct UIADocumentReplacementRoot: View {
    typealias Body = Never
    let state: UIADocumentReplacementState

    var body: Never { fatalError("UIADocumentReplacementRoot has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        state.bindingVersion += 1
        let version = state.bindingVersion
        // Every build obtains fresh closures from the actual session, while
        // its document source and generated key-path projection remain stable.
        let document = state.session.configuration().$document
        let text = state.alternateProjection ? document.alternate : document.text
        let selection = Binding<TextSelection?>(
            get: { state.selection },
            set: {
                if version != state.bindingVersion { state.staleSelectionWrites += 1 }
                state.selectionWriteVersions.append(version)
                state.selection = $0
            }
        )
        let input: AnyView
        switch state.input {
        case .field:
            input = AnyView(TextField("Document", text: text, selection: selection))
        case .editor:
            input = AnyView(TextEditor(text: text, selection: selection))
        case .secure:
            input = AnyView(SecureField("Document", text: text))
        }
        return makeViewComponent(
            VStack(alignment: .leading, spacing: 0) {
                if state.showsEditor {
                    input
                        .font(.system(size: 16))
                        .lineSpacing(0)
                        .environment(\.undoManager, Optional(state.environmentManager))
                        .disabled(!state.isEnabled)
                        .accessibilityIdentifier("uia.document.value")
                        .id(state.session.sessionID)
                        .frame(width: 300, height: 120)
                }
                Text("Revision \(version)")
            }, context: context
        )
    }
}

@MainActor
private final class UIADocumentReplacementFixture {
    let state: UIADocumentReplacementState
    let session: FileDocumentSession<UIAReplacementDocument>
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    var owners: [DocumentOwnerLease]
    var beforeDispatch: (() -> Void)?
    private var sessions: [FileDocumentSession<UIAReplacementDocument>]

    init(
        text: String = "abcd", input: UIAReplacementInput = .editor,
        manager: WinSwiftUI.UndoManager? = WinSwiftUI.UndoManager(),
        isEditable: Bool = true, isEnabled: Bool = true, selection: TextSelection? = nil
    ) throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 500, height: 300)))
        let owner = DocumentOwnerLease()
        owner.bind(runtime: runtime, dialogOwner: { .hosted(nil) })
        let session = try FileDocumentSession(
            document: UIAReplacementDocument(text: text), contentType: .utf8PlainText,
            isEditable: isEditable, owner: owner, codec: .editable(UIAReplacementDocument.self),
            files: LiveDocumentFileService(), undoManager: manager)
        let state = UIADocumentReplacementState(session: session, input: input)
        state.selection = selection
        state.isEnabled = isEnabled
        self.state = state
        self.session = session
        self.runtime = runtime
        owners = [owner]
        sessions = [session]
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 500, height: 300) },
            invalidateHandler: { [weak host] in host?.reload() })
        host.setComponents { [UIADocumentReplacementRoot(state: state).makeComponent(context: context)] }
        session.onChange = { [weak self] in self?.reload() }
        runtime.requestFocus(try editor())
        render()
    }

    var currentEditor: ViewNode? {
        var pending = [runtime.root]
        while let node = pending.popLast() {
            if node.accessibilityTraits.contains(.isTextInput) { return node }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    var presentedText: String {
        state.alternateProjection ? state.session.document.alternate : state.session.document.text
    }

    func editor() throws -> ViewNode { try XCTUnwrap(currentEditor) }

    func render() { _ = runtime.renderScene() }

    func reload() {
        host.reload()
        render()
    }

    func replace(_ value: String) throws -> TextInputAccessibilityValueResult {
        let node = try editor()
        let capability = try XCTUnwrap(node.textInputController as? any TextInputAccessibilityValueReplacing)
        let isCurrent: @MainActor () -> Bool = { [weak self, weak node] in
            guard let self, let node else { return false }
            return self.currentEditor === node
        }
        let mayDispatch: @MainActor () -> Bool = { [weak self, weak node] in
            guard let self, let node else { return false }
            let callback = self.beforeDispatch
            self.beforeDispatch = nil
            callback?()
            return self.currentEditor === node
        }
        return capability.replaceValueForAccessibility(
            value,
            validation: TextInputAccessibilityValueValidation(
                mayDispatch: mayDispatch, isRetainedTargetCurrent: isCurrent))
    }

    func addSession(text: String) throws -> FileDocumentSession<UIAReplacementDocument> {
        let owner = DocumentOwnerLease()
        owner.bind(runtime: runtime, dialogOwner: { .hosted(nil) })
        let session = try FileDocumentSession(
            document: UIAReplacementDocument(text: text), contentType: .utf8PlainText,
            owner: owner, codec: .editable(UIAReplacementDocument.self),
            files: LiveDocumentFileService(), undoManager: WinSwiftUI.UndoManager())
        owners.append(owner)
        sessions.append(session)
        session.onChange = { [weak self] in self?.reload() }
        return session
    }

    func changeTarget(
        _ change: UIAReplacementTargetChange, replacement: FileDocumentSession<UIAReplacementDocument>
    ) {
        switch change {
        case .document: state.session = replacement
        case .projection: state.alternateProjection = true
        case .removal: state.showsEditor = false
        }
        state.selection = uiaDocumentSelection(1..<1, in: presentedText)
        reload()
    }

    func boundRange() -> Range<Int>? {
        guard case .selection(let range) = state.selection?.indices else { return nil }
        let boundaries = Array(presentedText.indices) + [presentedText.endIndex]
        guard let lower = boundaries.firstIndex(of: range.lowerBound),
            let upper = boundaries.firstIndex(of: range.upperBound), lower <= upper
        else { return nil }
        return lower..<upper
    }

    func cleanup() {
        beforeDispatch = nil
        for session in sessions { session.invalidate() }
        host.setComponents { [] }
    }
}

private func uiaDocumentSelection(
    _ range: Range<Int>, in text: String, affinity: TextSelectionAffinity = .downstream
) -> TextSelection {
    let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: range.upperBound)
    var selection = TextSelection(range: lower..<upper)
    selection.affinity = affinity
    return selection
}

/// Calls the capability on real retained controls. These tests cover document
/// history and selection ownership, not UIA adapter wiring or native providers.
@MainActor
final class UIADocumentValueReplacementTests: XCTestCase {
    private func withLayout(_ body: () throws -> Void) rethrows {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let characters = Array(text)
            let glyphs = characters.enumerated().map { offset, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(offset) * 9, y: 0), advance: 9,
                    glyphID: UInt32(offset + 1), fontFamily: style.fontFamily,
                    weight: style.weight, fontSize: style.nativeFontPixelSize, sourceIndex: offset)
            }
            let size = Size(width: Double(characters.count) * 9, height: max(1, style.nativeFontPixelSize))
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
                contentSize: size, measuredSize: size)
        }
        defer { NativeTextRenderer.resetTestingOverrides() }
        try body()
    }

    func testWholeValueReplacementUsesOneDocumentActionForTextFieldAndTextEditor() async throws {
        try withLayout {
            let original = "a👩🏽‍💻e\u{301}z"
            let replacement = "e\u{301}🐈B"
            let selection = uiaDocumentSelection(1..<2, in: original, affinity: .upstream)
            for input in [UIAReplacementInput.field, .editor] {
                let fixture = try UIADocumentReplacementFixture(text: original, input: input, selection: selection)
                defer { fixture.cleanup() }
                let manager = try XCTUnwrap(fixture.session.documentUndoManager)
                let initialCaret = try fixture.editor().textInputCaretOffset
                // A bound range initializes the caret at its upper bound;
                // upstream affinity does not change that captured offset.
                XCTAssertEqual(initialCaret, 2)

                let result = try fixture.replace(replacement)
                XCTAssertTrue(result.didDispatch)
                XCTAssertTrue(result.accepted)
                XCTAssertEqual(Array(fixture.session.document.text.utf8), Array(replacement.utf8))
                XCTAssertEqual(fixture.session.mutationRevision, 1)
                XCTAssertTrue(manager.canUndo)
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
                XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
                XCTAssertEqual(fixture.state.selection, selection)
                XCTAssertEqual(try fixture.editor().textInputCaretOffset, replacement.count)
                XCTAssertNil(try fixture.editor().textInputSelection)

                manager.undo()
                fixture.render()
                XCTAssertEqual(Array(fixture.session.document.text.utf8), Array(original.utf8))
                XCTAssertEqual(fixture.boundRange(), 1..<2)
                XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
                XCTAssertEqual(try fixture.editor().textInputCaretOffset, initialCaret)
                XCTAssertFalse(manager.canUndo)
                manager.redo()
                fixture.render()
                XCTAssertEqual(Array(fixture.session.document.text.utf8), Array(replacement.utf8))
                XCTAssertEqual(try fixture.editor().textInputCaretOffset, replacement.count)
                XCTAssertNil(try fixture.editor().textInputSelection)
                XCTAssertNil(fixture.state.selection)
                XCTAssertEqual(fixture.session.mutationRevision, 3)
                XCTAssertFalse(manager.canRedo)
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
                XCTAssertEqual(fixture.state.staleSelectionWrites, 0)
            }
        }
    }

    func testFreshProjectedBindingsPreserveTheDocumentSelectionSidecarAcrossRebuilds() async throws {
        try withLayout {
            let fixture = try UIADocumentReplacementFixture(
                selection: uiaDocumentSelection(1..<3, in: "abcd", affinity: .upstream))
            defer { fixture.cleanup() }
            let node = try fixture.editor()
            XCTAssertEqual(node.textInputCaretOffset, 3)
            let previousController = try XCTUnwrap(node.textInputController)
            let originalBinding = fixture.session.configuration().$document.text
            let source = try XCTUnwrap(originalBinding.mutationSource as? DocumentBindingSource)
            let manager = try XCTUnwrap(fixture.session.documentUndoManager)

            let result = try fixture.replace("changed")
            XCTAssertTrue(result.didDispatch)
            XCTAssertTrue(result.accepted)
            XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
            fixture.reload()
            fixture.reload()
            let freshBinding = fixture.session.configuration().$document.text
            XCTAssertTrue((freshBinding.mutationSource as? DocumentBindingSource) === source)
            XCTAssertEqual(freshBinding.mutationProjection, originalBinding.mutationProjection)
            XCTAssertTrue(try fixture.editor() === node)
            XCTAssertFalse(try XCTUnwrap(node.textInputController) === previousController)

            manager.undo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "abcd")
            XCTAssertEqual(fixture.boundRange(), 1..<3)
            XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 3)
            fixture.reload()
            manager.redo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "changed")
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 7)
            XCTAssertNil(try fixture.editor().textInputSelection)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, 2)
            XCTAssertEqual(fixture.state.staleSelectionWrites, 0)
            XCTAssertEqual(fixture.session.mutationRevision, 3)
            XCTAssertFalse(fixture.state.environmentManager.canUndo)
        }
    }

    func testNestedDirectAssignmentCannotClaimTheAccessibilityEditReceipt() async throws {
        try withLayout {
            let fixture = try UIADocumentReplacementFixture(
                text: "abc", selection: uiaDocumentSelection(1..<2, in: "abc", affinity: .upstream))
            defer { fixture.cleanup() }
            let manager = try XCTUnwrap(fixture.session.documentUndoManager)
            let refresh = fixture.session.onChange
            var assignsDirectly = true
            fixture.session.onChange = { [weak fixture] in
                guard let fixture else { return }
                if assignsDirectly {
                    assignsDirectly = false
                    fixture.state.selection = uiaDocumentSelection(0..<0, in: "XYZ")
                    fixture.session.configuration().$document.text.wrappedValue = "XYZ"
                }
                refresh?()
            }

            let result = try fixture.replace("q")
            XCTAssertTrue(result.didDispatch)
            XCTAssertFalse(result.accepted)
            XCTAssertEqual(fixture.session.document.text, "XYZ")
            XCTAssertEqual(fixture.session.mutationRevision, 2)
            XCTAssertEqual(fixture.boundRange(), 0..<0)
            XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
            manager.undo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "q")
            XCTAssertEqual(fixture.boundRange(), 0..<0)
            XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
            manager.undo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "abc")
            XCTAssertEqual(fixture.boundRange(), 1..<2)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, 1)
            XCTAssertFalse(manager.canUndo)
            manager.redo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "q")
            manager.redo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "XYZ")
            XCTAssertEqual(fixture.session.mutationRevision, 6)
            XCTAssertFalse(manager.canRedo)
            XCTAssertFalse(fixture.state.environmentManager.canUndo)
            XCTAssertEqual(fixture.state.staleSelectionWrites, 0)
        }
    }

    func testDocumentProjectionSwitchOrRemovalRejectsTheUnwrittenReplacement() async throws {
        try withLayout {
            for change in [UIAReplacementTargetChange.document, .projection, .removal] {
                let fixture = try UIADocumentReplacementFixture(selection: uiaDocumentSelection(0..<2, in: "abcd"))
                defer { fixture.cleanup() }
                let replacement = try fixture.addSession(text: "replacement")
                var changedTarget = false
                fixture.beforeDispatch = { [weak fixture] in
                    guard let fixture else { return }
                    changedTarget = true
                    fixture.changeTarget(change, replacement: replacement)
                }

                let result = try fixture.replace("must not commit")
                XCTAssertTrue(changedTarget)
                XCTAssertFalse(result.didDispatch)
                XCTAssertFalse(result.accepted)
                XCTAssertEqual(fixture.session.document.text, "abcd")
                XCTAssertEqual(fixture.session.document.alternate, "alternate")
                XCTAssertEqual(fixture.session.mutationRevision, 0)
                XCTAssertEqual(replacement.document.text, "replacement")
                XCTAssertEqual(replacement.mutationRevision, 0)
                XCTAssertFalse(try XCTUnwrap(fixture.session.documentUndoManager).canUndo)
                XCTAssertFalse(try XCTUnwrap(replacement.documentUndoManager).canUndo)
                XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
                XCTAssertEqual(fixture.boundRange(), 1..<1)
                if case .removal = change {
                    XCTAssertNil(fixture.currentEditor)
                } else {
                    XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
                }
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
            }
        }
    }

    func testNilOrDisabledDocumentManagerNeverFallsBackToLocalHistory() async throws {
        try withLayout {
            for hasDisabledManager in [false, true] {
                let manager = hasDisabledManager ? WinSwiftUI.UndoManager() : nil
                let fixture = try UIADocumentReplacementFixture(manager: manager)
                defer { fixture.cleanup() }
                manager?.disableUndoRegistration()
                let result = try fixture.replace("accepted")
                manager?.enableUndoRegistration()
                XCTAssertTrue(result.didDispatch)
                XCTAssertTrue(result.accepted)
                XCTAssertEqual(fixture.session.document.text, "accepted")
                XCTAssertEqual(fixture.session.mutationRevision, 1)
                XCTAssertFalse(manager?.canUndo ?? false)
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
                XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
                fixture.runtime.keyDown(KeyboardEvent(keyCode: 0x5A, modifiers: [.control]))
                fixture.render()
                XCTAssertEqual(fixture.session.document.text, "accepted")
                XCTAssertEqual(fixture.session.mutationRevision, 1)
                XCTAssertFalse(fixture.state.environmentManager.canRedo)
            }
        }
    }

    func testReadOnlyExpiredDisabledAndSecureDocumentsRefuseReplacement() async throws {
        try withLayout {
            for refusal in [UIAReplacementRefusal.readOnly, .expiredOwner, .disabled, .secure] {
                let fixture = try UIADocumentReplacementFixture(
                    input: refusal == .secure ? .secure : .editor,
                    isEditable: refusal != .readOnly, isEnabled: refusal != .disabled)
                defer { fixture.cleanup() }
                if refusal == .expiredOwner {
                    weak var expiredOwner = fixture.owners.first
                    fixture.owners.removeAll()
                    XCTAssertNil(expiredOwner)
                }
                XCTAssertNotNil(fixture.session.configuration().$document.text.mutationSource as? DocumentBindingSource)
                let result = try fixture.replace("refused")
                XCTAssertFalse(result.didDispatch)
                XCTAssertFalse(result.accepted)
                XCTAssertEqual(fixture.session.document.text, "abcd")
                XCTAssertEqual(fixture.session.mutationRevision, 0)
                XCTAssertFalse(try XCTUnwrap(fixture.session.documentUndoManager).canUndo)
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
                XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
            }
        }
    }

    func testCommittedDocumentHistorySurvivesTargetRetirementWithoutSelectionEffects() async throws {
        try withLayout {
            for change in [UIAReplacementTargetChange.document, .projection, .removal] {
                let fixture = try UIADocumentReplacementFixture(selection: uiaDocumentSelection(0..<2, in: "abcd"))
                defer { fixture.cleanup() }
                let replacement = try fixture.addSession(text: "replacement")
                let manager = try XCTUnwrap(fixture.session.documentUndoManager)
                let refresh = fixture.session.onChange
                var changesTarget = true
                fixture.session.onChange = { [weak fixture] in
                    guard let fixture else { return }
                    if changesTarget {
                        changesTarget = false
                        fixture.changeTarget(change, replacement: replacement)
                    }
                    refresh?()
                }

                let result = try fixture.replace("committed")
                XCTAssertTrue(result.didDispatch)
                XCTAssertFalse(result.accepted)
                XCTAssertEqual(fixture.session.document.text, "committed")
                XCTAssertEqual(fixture.session.mutationRevision, 1)
                XCTAssertTrue(manager.canUndo)
                XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
                manager.undo()
                fixture.render()
                XCTAssertEqual(fixture.session.document.text, "abcd")
                XCTAssertFalse(manager.canUndo)
                XCTAssertTrue(manager.canRedo)
                manager.redo()
                fixture.render()
                XCTAssertEqual(fixture.session.document.text, "committed")
                XCTAssertFalse(manager.canRedo)
                XCTAssertEqual(fixture.session.document.alternate, "alternate")
                XCTAssertEqual(fixture.session.mutationRevision, 3)
                XCTAssertEqual(replacement.document.text, "replacement")
                XCTAssertEqual(replacement.mutationRevision, 0)
                XCTAssertFalse(try XCTUnwrap(replacement.documentUndoManager).canUndo)
                XCTAssertEqual(fixture.boundRange(), 1..<1)
                XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
                if case .removal = change {
                    XCTAssertNil(fixture.currentEditor)
                } else {
                    XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
                }
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
            }
        }
    }

    func testAuthoredSelectionDuringSynchronousRebuildWinsInternalStaging() async throws {
        try withLayout {
            let fixture = try UIADocumentReplacementFixture(
                selection: uiaDocumentSelection(1..<3, in: "abcd", affinity: .upstream))
            defer { fixture.cleanup() }
            let manager = try XCTUnwrap(fixture.session.documentUndoManager)
            let refresh = fixture.session.onChange
            let authored = uiaDocumentSelection(0..<1, in: "wxyz", affinity: .upstream)
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 3)
            var authorsSelection = true
            fixture.session.onChange = { [weak fixture] in
                if authorsSelection {
                    authorsSelection = false
                    fixture?.state.selection = authored
                }
                refresh?()
            }

            let result = try fixture.replace("wxyz")
            XCTAssertTrue(result.didDispatch)
            XCTAssertTrue(result.accepted)
            XCTAssertEqual(fixture.session.document.text, "wxyz")
            XCTAssertEqual(fixture.session.mutationRevision, 1)
            XCTAssertEqual(fixture.state.selection, authored)
            XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(0..<1))
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
            manager.undo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "abcd")
            XCTAssertEqual(fixture.boundRange(), 1..<3)
            XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
            manager.redo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "wxyz")
            XCTAssertEqual(fixture.boundRange(), 0..<1)
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, 2)
            XCTAssertEqual(fixture.state.staleSelectionWrites, 0)
            XCTAssertFalse(fixture.state.environmentManager.canUndo)
        }
    }
}
