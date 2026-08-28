import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private struct UIADocumentAdapterDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.utf8PlainText] }
    var text: String

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

/// Value replacement is an in-memory document mutation. These operations are
/// deliberately unavailable so no fixture can silently start a dialog or IO.
@MainActor
private final class UIADocumentAdapterFiles: DocumentFileService {
    private(set) var calls = 0

    func chooseOpenURL(types: [UTType], owner: FileDialogOwner) -> FileDialogOutcome<URL> {
        calls += 1
        XCTFail("UIA value replacement must not open a document dialog")
        return .cancelled
    }

    func chooseSaveURL(
        name: String?, directory: URL?, type: UTType, owner: FileDialogOwner
    ) -> FileDialogOutcome<URL> {
        calls += 1
        XCTFail("UIA value replacement must not open a save dialog")
        return .cancelled
    }

    func readRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
        calls += 1
        XCTFail("UIA value replacement must not read a file")
        throw DocumentFileServiceError.notRegularFile
    }

    func writeRegularFile(
        to url: URL, provideData: @MainActor (URL) throws -> Data,
        validate: @MainActor () throws -> Void
    ) throws -> Data {
        calls += 1
        XCTFail("UIA value replacement must not write a file")
        throw DocumentFileServiceError.notRegularFile
    }
}

private enum UIADocumentAdapterInput {
    case field
    case editor
    case secure
}

private enum UIADocumentAdapterRefusal: Equatable {
    case readOnly
    case expiredOwner
    case disabled
    case secure
}

@MainActor
private final class UIADocumentAdapterState {
    let session: FileDocumentSession<UIADocumentAdapterDocument>
    let input: UIADocumentAdapterInput
    let environmentManager = WinSwiftUI.UndoManager()
    var isEnabled: Bool
    var showsEditor = true
    var selection: TextSelection?
    var buildVersion = 0
    var selectionWriteVersions: [Int] = []
    var staleSelectionWrites = 0

    init(
        session: FileDocumentSession<UIADocumentAdapterDocument>, input: UIADocumentAdapterInput,
        isEnabled: Bool, selection: TextSelection?
    ) {
        self.session = session
        self.input = input
        self.isEnabled = isEnabled
        self.selection = selection
    }
}

@MainActor
private struct UIADocumentAdapterRoot: View {
    typealias Body = Never
    let state: UIADocumentAdapterState

    var body: Never { fatalError("UIADocumentAdapterRoot has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        state.buildVersion += 1
        let version = state.buildVersion
        // Fresh session bindings retain the actual document source and key
        // path. Do not wrap them in a custom setter that loses that ownership.
        let text = state.session.configuration().$document.text
        let selection = Binding<TextSelection?>(
            get: { state.selection },
            set: {
                if version != state.buildVersion { state.staleSelectionWrites += 1 }
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
                        .accessibilityIdentifier("uia.document.adapter")
                        .id(state.session.sessionID)
                        .frame(width: 300, height: 120)
                }
                Text("Build \(version)")
            }, context: context
        )
    }
}

@MainActor
private final class UIADocumentAdapterFixture {
    let state: UIADocumentAdapterState
    let session: FileDocumentSession<UIADocumentAdapterDocument>
    let files: UIADocumentAdapterFiles
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let source: RuntimeUIAElementTreeSource
    var owner: DocumentOwnerLease?
    var afterDocumentChange: (() -> Void)?
    private(set) var changes = 0
    private var active = true

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init(
        text: String = "abcd", input: UIADocumentAdapterInput = .editor,
        manager: WinSwiftUI.UndoManager? = WinSwiftUI.UndoManager(),
        isEditable: Bool = true, isEnabled: Bool = true, selection: TextSelection? = nil
    ) throws {
        let owner = DocumentOwnerLease()
        let files = UIADocumentAdapterFiles()
        let session = try FileDocumentSession(
            document: UIADocumentAdapterDocument(text: text), contentType: .utf8PlainText,
            isEditable: isEditable, owner: owner, codec: .editable(UIADocumentAdapterDocument.self),
            files: files, undoManager: manager)
        let state = UIADocumentAdapterState(
            session: session, input: input, isEnabled: isEnabled, selection: selection)
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 400, height: 280), scaleFactor: 1)
        let window = Win32Window(title: "UIA document adapter fixture", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "UIA document adapter fixture", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(UIADocumentAdapterRoot(state: state))]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.owner = owner
        self.files = files
        self.session = session
        self.state = state
        self.window = window
        self.host = host
        source = RuntimeUIAElementTreeSource(runtime: host.hostedRuntime)
        owner.bind(runtime: host.hostedRuntime, dialogOwner: { .hosted(nil) })
        session.onChange = { [weak self] in
            guard let self else { return }
            changes += 1
            afterDocumentChange?()
            rebuild()
        }
        host.windowDidCreate(window)
        do {
            runtime.requestFocus(try editor())
            render()
        } catch {
            cleanup()
            throw error
        }
    }

    var currentEditor: ViewNode? {
        var pending = [runtime.root]
        while let node = pending.popLast() {
            if node.accessibilityIdentifier == "uia.document.adapter",
                node.accessibilityTraits.contains(.isTextInput)
            {
                return node
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    func editor() throws -> ViewNode { try XCTUnwrap(currentEditor) }

    func snapshot() throws -> UIAElementSnapshot {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == "uia.document.adapter" })
    }

    func replace(_ value: String) throws -> Bool {
        source.uiaSetValue(elementID: try snapshot().id, value: value)
    }

    func render() {
        host.windowNeedsDisplay(window)
        _ = runtime.renderScene()
    }

    func rebuild() {
        active.toggle()
        host.windowDidChangeActiveState(window, isActive: active)
        render()
    }

    func boundRange() -> Range<Int>? {
        guard case .selection(let range) = state.selection?.indices else { return nil }
        let text = session.document.text
        let boundaries = Array(text.indices) + [text.endIndex]
        guard let lower = boundaries.firstIndex(of: range.lowerBound),
            let upper = boundaries.firstIndex(of: range.upperBound), lower <= upper
        else { return nil }
        return lower..<upper
    }

    func cleanup() {
        afterDocumentChange = nil
        // This fixture attaches its own session to an ordinary headless host,
        // so explicitly retire that session rather than claiming DocumentGroup
        // close routing was exercised by the host teardown below.
        owner?.revoke()
        session.invalidate()
        host.windowWillClose(window)
        owner = nil
        XCTAssertNil(window.nativeHandle)
        XCTAssertEqual(files.calls, 0)
    }
}

private func uiaDocumentAdapterSelection(
    _ range: Range<Int>, in text: String, affinity: TextSelectionAffinity = .downstream
) -> TextSelection {
    let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: range.upperBound)
    var selection = TextSelection(range: lower..<upper)
    selection.affinity = affinity
    return selection
}

/// Calls the real UIA source on hosted public controls backed by a real
/// FileDocumentSession. Fake presenters and text metrics keep these tests
/// headless; they do not qualify COM scheduling, native UIA, or document IO.
@MainActor
final class UIADocumentValueAdapterTests: XCTestCase {
    private func withLayout(_ body: () throws -> Void) rethrows {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let glyphs = Array(text).enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 9, y: 0), advance: 9,
                    glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                    fontSize: style.nativeFontPixelSize, sourceIndex: index)
            }
            let size = Size(width: Double(max(text.count, 1)) * 9, height: max(style.nativeFontPixelSize, 1))
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
                contentSize: size, measuredSize: size)
        }
        defer { NativeTextRenderer.resetTestingOverrides() }
        try body()
    }

    func testWholeValueUsesOneDocumentActionAndSelectionSidecarForFieldAndEditor() async throws {
        try withLayout {
            let original = "a👩🏽‍💻e\u{301}z"
            let replacement = "e\u{301}🐈B"
            let selection = uiaDocumentAdapterSelection(1..<2, in: original, affinity: .upstream)
            for input in [UIADocumentAdapterInput.field, .editor] {
                let fixture = try UIADocumentAdapterFixture(text: original, input: input, selection: selection)
                defer { fixture.cleanup() }
                let manager = try XCTUnwrap(fixture.session.documentUndoManager)
                let node = try fixture.editor()
                // A bound range starts at its upper caret offset regardless
                // of affinity; no synthetic backward selection is assumed.
                XCTAssertEqual(node.textInputCaretOffset, 2)

                XCTAssertTrue(try fixture.replace(replacement))
                XCTAssertEqual(Array(fixture.session.document.text.utf8), Array(replacement.utf8))
                XCTAssertEqual(fixture.session.mutationRevision, 1)
                XCTAssertEqual(fixture.changes, 1)
                XCTAssertTrue(manager.canUndo)
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
                XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
                XCTAssertEqual(fixture.state.selection, selection)
                XCTAssertEqual(node.textInputCaretOffset, replacement.count)
                XCTAssertNil(node.textInputSelection)
                XCTAssertEqual(try fixture.snapshot().value, replacement)

                manager.undo()
                fixture.render()
                XCTAssertEqual(Array(fixture.session.document.text.utf8), Array(original.utf8))
                XCTAssertEqual(fixture.boundRange(), 1..<2)
                XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
                XCTAssertEqual(try fixture.editor().textInputCaretOffset, 2)
                XCTAssertFalse(manager.canUndo)
                XCTAssertTrue(manager.canRedo)

                manager.redo()
                fixture.render()
                XCTAssertEqual(Array(fixture.session.document.text.utf8), Array(replacement.utf8))
                XCTAssertEqual(try fixture.editor().textInputCaretOffset, replacement.count)
                XCTAssertNil(try fixture.editor().textInputSelection)
                XCTAssertNil(fixture.state.selection)
                XCTAssertEqual(fixture.session.mutationRevision, 3)
                XCTAssertEqual(fixture.changes, 3)
                XCTAssertFalse(manager.canRedo)
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
                XCTAssertEqual(fixture.state.staleSelectionWrites, 0)
            }
        }
    }

    func testSynchronousHostedRebuildKeepsTheOriginalDocumentProjectionAndUndoOwner() async throws {
        try withLayout {
            let fixture = try UIADocumentAdapterFixture(
                selection: uiaDocumentAdapterSelection(1..<3, in: "abcd", affinity: .upstream))
            defer { fixture.cleanup() }
            let node = try fixture.editor()
            let previousController = try XCTUnwrap(node.textInputController)
            let originalBinding = fixture.session.configuration().$document.text
            let originalSource = try XCTUnwrap(originalBinding.mutationSource as? DocumentBindingSource)
            let manager = try XCTUnwrap(fixture.session.documentUndoManager)
            let version = fixture.state.buildVersion
            let reloads = fixture.host.executedReloadCount

            XCTAssertTrue(try fixture.replace("changed"))
            XCTAssertTrue(try fixture.editor() === node)
            XCTAssertFalse(try XCTUnwrap(node.textInputController) === previousController)
            XCTAssertEqual(fixture.state.buildVersion, version + 1)
            XCTAssertEqual(fixture.host.executedReloadCount, reloads + 1)
            XCTAssertEqual(fixture.session.mutationRevision, 1)
            XCTAssertEqual(fixture.changes, 1)
            XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
            let freshBinding = fixture.session.configuration().$document.text
            XCTAssertTrue((freshBinding.mutationSource as? DocumentBindingSource) === originalSource)
            XCTAssertEqual(freshBinding.mutationProjection, originalBinding.mutationProjection)

            fixture.rebuild()
            fixture.rebuild()
            manager.undo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "abcd")
            XCTAssertEqual(fixture.boundRange(), 1..<3)
            XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 3)
            XCTAssertFalse(manager.canUndo)
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

    func testNilOrDisabledDocumentManagerWritesOnceWithoutLocalHistoryFallback() async throws {
        try withLayout {
            for hasDisabledManager in [false, true] {
                let manager = hasDisabledManager ? WinSwiftUI.UndoManager() : nil
                let fixture = try UIADocumentAdapterFixture(manager: manager)
                defer { fixture.cleanup() }
                manager?.disableUndoRegistration()
                let accepted = try fixture.replace("accepted")
                manager?.enableUndoRegistration()

                XCTAssertTrue(accepted)
                XCTAssertEqual(fixture.session.document.text, "accepted")
                XCTAssertEqual(fixture.session.mutationRevision, 1)
                XCTAssertEqual(fixture.changes, 1)
                XCTAssertFalse(manager?.canUndo ?? false)
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
                XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
                fixture.runtime.keyDown(KeyboardEvent(keyCode: 0x5A, modifiers: [.control]))
                fixture.render()
                XCTAssertEqual(fixture.session.document.text, "accepted")
                XCTAssertEqual(fixture.session.mutationRevision, 1)
                XCTAssertEqual(fixture.changes, 1)
                XCTAssertFalse(fixture.state.environmentManager.canRedo)
            }
        }
    }

    func testCommittedDocumentHistorySurvivesEditorRemovalAfterUIAReportsFalse() async throws {
        try withLayout {
            let fixture = try UIADocumentAdapterFixture(selection: uiaDocumentAdapterSelection(0..<2, in: "abcd"))
            defer { fixture.cleanup() }
            let manager = try XCTUnwrap(fixture.session.documentUndoManager)
            let elementID = try fixture.snapshot().id
            let retiredEditor = try fixture.editor()
            fixture.afterDocumentChange = { [weak fixture] in
                guard let fixture, fixture.state.showsEditor else { return }
                fixture.state.showsEditor = false
                fixture.state.selection = uiaDocumentAdapterSelection(1..<1, in: "committed")
            }

            XCTAssertFalse(fixture.source.uiaSetValue(elementID: elementID, value: "committed"))
            XCTAssertEqual(fixture.session.document.text, "committed")
            XCTAssertEqual(fixture.session.mutationRevision, 1)
            XCTAssertEqual(fixture.changes, 1)
            XCTAssertNil(fixture.currentEditor)
            XCTAssertNil(fixture.runtime.accessibilityTarget(for: retiredEditor))
            XCTAssertTrue(manager.canUndo)
            XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
            XCTAssertFalse(fixture.source.uiaSetValue(elementID: elementID, value: "stale request"))
            XCTAssertEqual(fixture.session.mutationRevision, 1)

            manager.undo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "abcd")
            XCTAssertFalse(manager.canUndo)
            XCTAssertTrue(manager.canRedo)
            manager.redo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "committed")
            XCTAssertEqual(fixture.session.mutationRevision, 3)
            XCTAssertEqual(fixture.changes, 3)
            XCTAssertFalse(manager.canRedo)
            XCTAssertNil(fixture.currentEditor)
            XCTAssertEqual(fixture.boundRange(), 1..<1)
            XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
            XCTAssertFalse(fixture.state.environmentManager.canUndo)
        }
    }

    func testNestedOrdinaryDocumentAssignmentSupersedesTheUIAReceiptWithoutRetry() async throws {
        try withLayout {
            let fixture = try UIADocumentAdapterFixture(
                text: "abc", selection: uiaDocumentAdapterSelection(1..<2, in: "abc", affinity: .upstream))
            defer { fixture.cleanup() }
            let manager = try XCTUnwrap(fixture.session.documentUndoManager)
            var assignsDirectly = true
            fixture.afterDocumentChange = { [weak fixture] in
                guard let fixture, assignsDirectly else { return }
                assignsDirectly = false
                fixture.state.selection = uiaDocumentAdapterSelection(0..<0, in: "XYZ")
                fixture.session.configuration().$document.text.wrappedValue = "XYZ"
            }

            XCTAssertFalse(try fixture.replace("q"))
            XCTAssertEqual(fixture.session.document.text, "XYZ")
            XCTAssertEqual(fixture.session.mutationRevision, 2)
            XCTAssertEqual(fixture.changes, 2)
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
            XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, 1)
            XCTAssertFalse(manager.canUndo)

            manager.redo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "q")
            manager.redo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "XYZ")
            XCTAssertEqual(fixture.session.mutationRevision, 6)
            XCTAssertEqual(fixture.changes, 6)
            XCTAssertFalse(manager.canRedo)
            XCTAssertFalse(fixture.state.environmentManager.canUndo)
            XCTAssertEqual(fixture.state.staleSelectionWrites, 0)
        }
    }

    func testReadOnlyExpiredDisabledAndSecureDocumentTargetsRefuseWithoutHistoryOrDisclosure() async throws {
        try withLayout {
            for refusal in [UIADocumentAdapterRefusal.readOnly, .expiredOwner, .disabled, .secure] {
                let original = "private document 👩🏽‍💻"
                let fixture = try UIADocumentAdapterFixture(
                    text: original, input: refusal == .secure ? .secure : .editor,
                    isEditable: refusal != .readOnly, isEnabled: refusal != .disabled)
                defer { fixture.cleanup() }
                let snapshot = try fixture.snapshot()
                if refusal == .expiredOwner {
                    weak var expiredOwner = fixture.owner
                    fixture.owner = nil
                    XCTAssertNil(expiredOwner)
                }
                XCTAssertNotNil(fixture.session.configuration().$document.text.mutationSource as? DocumentBindingSource)

                XCTAssertFalse(fixture.source.uiaSetValue(elementID: snapshot.id, value: "refused replacement"))
                XCTAssertTrue(
                    fixture.session.document.text.utf8.elementsEqual(original.utf8),
                    "Refused value must remain unchanged")
                XCTAssertEqual(fixture.session.mutationRevision, 0)
                XCTAssertEqual(fixture.changes, 0)
                XCTAssertFalse(try XCTUnwrap(fixture.session.documentUndoManager).canUndo)
                XCTAssertFalse(fixture.state.environmentManager.canUndo)
                XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)
                if refusal == .secure {
                    XCTAssertTrue(snapshot.isPassword)
                    XCTAssertFalse(snapshot.supportsValue)
                    XCTAssertNil(snapshot.value)
                    for exposed in fixture.source.uiaElementSnapshots() {
                        XCTAssertFalse(exposed.name.contains(original))
                        XCTAssertFalse(exposed.value?.contains(original) ?? false)
                        XCTAssertFalse(exposed.helpText?.contains(original) ?? false)
                    }
                }
            }
        }
    }

    func testAuthoredSelectionDuringSynchronousDocumentRebuildWinsUIAStaging() async throws {
        try withLayout {
            let fixture = try UIADocumentAdapterFixture(
                selection: uiaDocumentAdapterSelection(1..<3, in: "abcd", affinity: .upstream))
            defer { fixture.cleanup() }
            let manager = try XCTUnwrap(fixture.session.documentUndoManager)
            let authored = uiaDocumentAdapterSelection(0..<1, in: "wxyz", affinity: .upstream)
            var authorsSelection = true
            fixture.afterDocumentChange = { [weak fixture] in
                guard let fixture, authorsSelection else { return }
                authorsSelection = false
                fixture.state.selection = authored
            }

            XCTAssertTrue(try fixture.replace("wxyz"))
            XCTAssertEqual(fixture.session.document.text, "wxyz")
            XCTAssertEqual(fixture.session.mutationRevision, 1)
            XCTAssertEqual(fixture.changes, 1)
            XCTAssertEqual(fixture.state.selection, authored)
            XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(0..<1))
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            XCTAssertTrue(fixture.state.selectionWriteVersions.isEmpty)

            manager.undo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "abcd")
            XCTAssertEqual(fixture.boundRange(), 1..<3)
            XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
            XCTAssertFalse(manager.canUndo)
            manager.redo()
            fixture.render()
            XCTAssertEqual(fixture.session.document.text, "wxyz")
            XCTAssertEqual(fixture.boundRange(), 0..<1)
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            XCTAssertEqual(fixture.state.selection?.affinity, .upstream)
            XCTAssertEqual(fixture.state.selectionWriteVersions.count, 2)
            XCTAssertEqual(fixture.state.staleSelectionWrites, 0)
            XCTAssertEqual(fixture.session.mutationRevision, 3)
            XCTAssertFalse(manager.canRedo)
            XCTAssertFalse(fixture.state.environmentManager.canUndo)
        }
    }
}
