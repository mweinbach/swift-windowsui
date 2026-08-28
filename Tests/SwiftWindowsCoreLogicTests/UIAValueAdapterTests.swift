import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum UIAAdapterControl: Equatable, Sendable {
    case field
    case editor
    case secure
}

@MainActor
private final class UIAAdapterModel {
    var text = "abcd"
    var selection: TextSelection?
    var attemptedValues: [String] = []
    var writeVersions: [Int] = []
    var readVersions: [Int] = []
    var selectionWrites = 0
    var beforeRead: (@MainActor (Int) -> Void)?
    var setter: (@MainActor (String) -> Void)?
    var afterWrite: (@MainActor () -> Void)?
}

@MainActor
private final class UIAAdapterState {
    let primary = UIAAdapterModel()
    let alternate = UIAAdapterModel()
    var usesAlternate = false
    var control: UIAAdapterControl
    var manager: WinSwiftUI.UndoManager? = WinSwiftUI.UndoManager()
    var showsEditor = true
    var isEnabled = true
    var identity = 0
    var version = 0
    var builds = 0
    var mountedTransactions: [Transaction?] = []

    var model: UIAAdapterModel { usesAlternate ? alternate : primary }

    init(control: UIAAdapterControl) {
        self.control = control
        if control == .secure { primary.text = String(repeating: "s", count: 16) }
    }
}

@MainActor
private struct UIAAdapterRoot: View {
    let state: UIAAdapterState

    var body: some View {
        state.builds += 1
        let model = state.model
        let version = state.version
        let text = Binding<String>(
            get: {
                model.readVersions.append(version)
                model.beforeRead?(version)
                return model.text
            },
            set: { value in
                model.attemptedValues.append(value)
                model.writeVersions.append(version)
                if let setter = model.setter { setter(value) } else { model.text = value }
                model.afterWrite?()
            })
        let selection = Binding<TextSelection?>(
            get: { model.selection },
            set: {
                model.selectionWrites += 1
                model.selection = $0
            })
        let input: AnyView
        switch state.control {
        case .field:
            input = AnyView(TextField("Adapter text", text: text, selection: selection))
        case .editor:
            input = AnyView(TextEditor(text: text, selection: selection))
        case .secure:
            input = AnyView(SecureField("Protected field", text: text))
        }
        let authored = state.control == .secure ? "Protected content" : "Authored text: \(model.text)"
        return VStack(alignment: .leading, spacing: 4) {
            if state.showsEditor {
                input
                    .disabled(!state.isEnabled)
                    .accessibilityIdentifier("uia-adapter-editor")
                    .frame(width: 300, height: 120)
                    .id(state.identity)
            }
            Text(authored)
                .accessibilityIdentifier("uia-adapter-authored")
        }
        .environment(\.undoManager, state.manager)
    }
}

@MainActor
private struct UIAAdapterMountedRoot: View {
    @State private var text = "abcd"
    let state: UIAAdapterState

    var body: some View {
        state.builds += 1
        state.primary.text = text
        state.mountedTransactions.append(TransactionContext.current)
        let binding = $text.animation(.linear(duration: 0.4))
        let input: AnyView
        if state.control == .field {
            input = AnyView(TextField("Mounted adapter text", text: binding))
        } else {
            input = AnyView(TextEditor(text: binding))
        }
        return VStack(alignment: .leading, spacing: 4) {
            input
                .accessibilityIdentifier("uia-adapter-editor")
                .frame(width: 300, height: 120)
            Text("Authored text: \(text)")
        }
        .environment(\.undoManager, state.manager)
    }
}

@MainActor
private func uiaAdapterNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children)
    }
    return result
}

@MainActor
private final class UIAAdapterRawInputProbe {
    var keyEvents = 0
    var imeEvents = 0

    func install(on node: ViewNode) {
        node.onKeyDown = { [weak self] _ in self?.keyEvents += 1 }
        node.onIMEComposition = { [weak self] _ in self?.imeEvents += 1 }
    }

    func assertUnused(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(keyEvents, 0, file: file, line: line)
        XCTAssertEqual(imeEvents, 0, file: file, line: line)
    }
}

@MainActor
private final class UIAAdapterUnsupportedController: RetainedTextInputController {
    func attach(to node: ViewNode) {}
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func detach(from node: ViewNode) {}
}

@MainActor
private final class UIAAdapterFixture {
    let state: UIAAdapterState
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    private var active = true
    private var isClosed = false
    lazy var source = RuntimeUIAElementTreeSource(runtime: runtime)

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init(control: UIAAdapterControl, mountedState: Bool, usesUndoManager: Bool) throws {
        let state = UIAAdapterState(control: control)
        if !usesUndoManager { state.manager = nil }
        self.state = state
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 360, height: 280), scaleFactor: 1)
        let content =
            mountedState ? AnyView(UIAAdapterMountedRoot(state: state)) : AnyView(UIAAdapterRoot(state: state))
        window = Win32Window(title: "Accessibility value adapter fixture", clientSize: surface.pixelSize)
        host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Accessibility value adapter fixture", size: surface.pixelSize,
                clearColor: .black, content: [content]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.windowDidCreate(window)
        runtime.clock = { 0 }
        runtime.requestFocus(try editor())
        render()
    }

    func editor() throws -> ViewNode {
        try XCTUnwrap(
            uiaAdapterNodes(in: runtime.root).first {
                $0.accessibilityIdentifier == "uia-adapter-editor" && $0.accessibilityTraits.contains(.isTextInput)
            })
    }

    func snapshot(using source: RuntimeUIAElementTreeSource? = nil) throws -> UIAElementSnapshot {
        try XCTUnwrap(
            (source ?? self.source).uiaElementSnapshots().first { $0.automationID == "uia-adapter-editor" })
    }

    func render() {
        host.windowNeedsDisplay(window)
        _ = runtime.renderScene()
    }

    func rebuild() {
        state.version += 1
        active.toggle()
        host.windowDidChangeActiveState(window, isActive: active)
        render()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        host.windowWillClose(window)
    }

    @discardableResult
    func appendModal(accessibilityHidden: Bool) -> ViewNode {
        let modal = ViewNode(
            frame: Rect(x: 20, y: 20, width: 180, height: 120),
            accessibilityLabel: "Adapter competing modal", accessibilityTraits: .isModal,
            isAccessibilityHidden: accessibilityHidden)
        modal.paintsInDeferredPhase = true
        runtime.root.addChild(modal)
        return modal
    }
}

/// Hosted retained adapter coverage with fake presentation and deterministic
/// text metrics. These tests never call the editor capability directly, create
/// an HWND, or qualify native COM scheduling and HRESULT behavior.
@MainActor
final class UIAValueAdapterTests: XCTestCase {
    private func withFixture(
        control: UIAAdapterControl = .editor, mountedState: Bool = false, usesUndoManager: Bool = true,
        _ body: @MainActor (UIAAdapterFixture) throws -> Void
    ) throws {
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
        let fixture = try UIAAdapterFixture(
            control: control, mountedState: mountedState, usesUndoManager: usesUndoManager)
        defer { fixture.close() }
        XCTAssertNil(fixture.window.nativeHandle)
        try body(fixture)
    }

    func testPlainBindingsWriteOnceRefreshOnceAndKeepSingleUndoRedoAction() async throws {
        for control in [UIAAdapterControl.field, .editor] {
            try withFixture(control: control) { fixture in
                let node = try fixture.editor()
                let id = try fixture.snapshot().id
                let manager = try XCTUnwrap(fixture.state.manager)
                let builds = fixture.state.builds
                let reloads = fixture.host.executedReloadCount
                let rawInput = UIAAdapterRawInputProbe()
                rawInput.install(on: node)

                XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "replaced"))
                XCTAssertTrue(fixture.runtime.hasPendingLayout, "Accepted value replacement may leave layout queued")
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["replaced"])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertEqual(fixture.state.builds, builds + 1)
                XCTAssertEqual(fixture.host.executedReloadCount, reloads + 1)
                XCTAssertTrue(try fixture.editor() === node)
                XCTAssertTrue(
                    uiaAdapterNodes(in: fixture.runtime.root).contains { $0.text == "Authored text: replaced" })
                XCTAssertEqual(node.textInputCaretOffset, 8)
                XCTAssertNil(node.textInputSelection)
                rawInput.assertUnused()
                XCTAssertTrue(manager.canUndo)
                manager.undo()
                XCTAssertEqual(fixture.state.primary.text, "abcd")
                XCTAssertFalse(manager.canUndo)
                XCTAssertTrue(manager.canRedo)
                manager.redo()
                XCTAssertEqual(fixture.state.primary.text, "replaced")
                XCTAssertFalse(manager.canRedo)
            }
        }
    }

    func testUnicodeEmptyAndEqualValuesNeverUseRawInputOrWriteSelection() async throws {
        for control in [UIAAdapterControl.field, .editor] {
            for value in ["e\u{301}👩‍👩‍👧‍👧", "", "abcd"] {
                try withFixture(control: control) { fixture in
                    let node = try fixture.editor()
                    let id = try fixture.snapshot().id
                    let manager = try XCTUnwrap(fixture.state.manager)
                    let rawInput = UIAAdapterRawInputProbe()
                    rawInput.install(on: node)

                    XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: value))
                    XCTAssertEqual(fixture.state.primary.attemptedValues, [value])
                    XCTAssertEqual(Array(fixture.state.primary.text.utf8), Array(value.utf8))
                    XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                    XCTAssertEqual(node.textInputCaretOffset, value.count)
                    XCTAssertNil(node.textInputSelection)
                    XCTAssertEqual(manager.canUndo, value != "abcd")
                    rawInput.assertUnused()
                    if value != "abcd" {
                        rawInput.install(on: try fixture.editor())
                        XCTAssertTrue(
                            fixture.source.uiaSetValue(elementID: id, value: value),
                            "Immediate repeat: control=\(control), value=\(String(reflecting: value))")
                        XCTAssertEqual(
                            fixture.state.primary.attemptedValues, [value, value],
                            "Immediate repeat: control=\(control), value=\(String(reflecting: value))")
                        XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                        rawInput.assertUnused()
                        manager.undo()
                        XCTAssertEqual(fixture.state.primary.text, "abcd")
                        XCTAssertFalse(manager.canUndo)
                    }
                }
            }
        }
    }

    func testMountedStateAcceptsCompatibleRefreshAndUndoRedo() async throws {
        for control in [UIAAdapterControl.field, .editor] {
            try withFixture(control: control, mountedState: true) { fixture in
                let node = try fixture.editor()
                let id = try fixture.snapshot().id
                let manager = try XCTUnwrap(fixture.state.manager)
                let builds = fixture.state.builds

                XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "mounted"))
                XCTAssertEqual(fixture.state.primary.text, "mounted")
                XCTAssertEqual(fixture.state.builds, builds + 1)
                XCTAssertTrue(try fixture.editor() === node)
                let transaction = try XCTUnwrap(fixture.state.mountedTransactions.last.flatMap { $0 })
                XCTAssertEqual(transaction.animation?.duration, 0.4)
                XCTAssertEqual(node.textInputCaretOffset, 7)
                XCTAssertTrue(manager.canUndo)
                manager.undo()
                XCTAssertEqual(fixture.state.primary.text, "abcd")
                XCTAssertFalse(manager.canUndo)
                XCTAssertTrue(manager.canRedo)
                manager.redo()
                XCTAssertEqual(fixture.state.primary.text, "mounted")
                XCTAssertFalse(manager.canRedo)
            }
        }
    }

    func testSynchronousSetterRebuildUsesOnlyOriginalGetterAndOneRefresh() async throws {
        for control in [UIAAdapterControl.field, .editor] {
            try withFixture(control: control) { fixture in
                let node = try fixture.editor()
                let original = try XCTUnwrap(node.textInputController)
                let id = try fixture.snapshot().id
                let manager = try XCTUnwrap(fixture.state.manager)
                let builds = fixture.state.builds
                let reloads = fixture.host.executedReloadCount
                var readsAfterSetter: [Int] = []
                fixture.state.primary.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    fixture.rebuild()
                    fixture.state.primary.beforeRead = { readsAfterSetter.append($0) }
                }

                XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "fresh"))
                fixture.state.primary.beforeRead = nil
                fixture.state.primary.afterWrite = nil
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["fresh"])
                XCTAssertEqual(fixture.state.primary.writeVersions, [0])
                XCTAssertEqual(readsAfterSetter, [0])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertEqual(fixture.state.builds, builds + 1)
                XCTAssertEqual(fixture.host.executedReloadCount, reloads + 1)
                XCTAssertTrue(try fixture.editor() === node)
                XCTAssertFalse(node.textInputController === original)
                XCTAssertTrue(manager.canUndo)
                manager.undo()
                XCTAssertEqual(fixture.state.primary.text, "abcd")
                XCTAssertFalse(manager.canUndo)
            }
        }
    }

    func testFocusCallbacksCannotReplaceDisableSecureRemoveOrCloseTheSelectedEditorAndThenWrite() async throws {
        for change in 0..<5 {
            try withFixture { fixture in
                let node = try fixture.editor()
                let original = try XCTUnwrap(node.textInputController)
                fixture.runtime.requestFocus(nil)
                fixture.render()
                let id = try fixture.snapshot().id
                let rawInput = UIAAdapterRawInputProbe()
                rawInput.install(on: node)
                var entries = 0
                node.onFocusEnter = { [weak fixture, weak node] in
                    entries += 1
                    guard let fixture, let node else { return }
                    switch change {
                    case 0:
                        fixture.state.usesAlternate = true
                        fixture.rebuild()
                    case 1: node.accessibilityRespondsToUserInteraction = false
                    case 2: node.accessibilityTraits.insert(.isSecureTextInput)
                    case 3: node.parent?.removeChild(node)
                    default: fixture.close()
                    }
                }

                XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "not dispatched"))
                XCTAssertEqual(entries, 1)
                XCTAssertTrue(fixture.state.primary.attemptedValues.isEmpty)
                XCTAssertTrue(fixture.state.alternate.attemptedValues.isEmpty)
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertEqual(fixture.state.alternate.selectionWrites, 0)
                rawInput.assertUnused()
                if change == 0 {
                    XCTAssertTrue(try fixture.editor() === node)
                    XCTAssertFalse(node.textInputController === original)
                }
            }
        }
    }

    func testOriginalGetterReplacingTheSameNodeControllerCannotWriteEitherBinding() async throws {
        try withFixture { fixture in
            let node = try fixture.editor()
            let original = try XCTUnwrap(node.textInputController)
            let id = try fixture.snapshot().id
            let rawInput = UIAAdapterRawInputProbe()
            rawInput.install(on: node)
            fixture.state.primary.beforeRead = { [weak fixture] _ in
                guard let fixture else { return }
                fixture.state.primary.beforeRead = nil
                fixture.state.usesAlternate = true
                fixture.rebuild()
            }

            XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "not dispatched"))
            XCTAssertTrue(try fixture.editor() === node)
            XCTAssertFalse(node.textInputController === original)
            XCTAssertTrue(fixture.state.primary.attemptedValues.isEmpty)
            XCTAssertTrue(fixture.state.alternate.attemptedValues.isEmpty)
            XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
            XCTAssertEqual(fixture.state.alternate.selectionWrites, 0)
            rawInput.assertUnused()
        }
    }

    func testRejectedOrNormalizedSetterReturnsFalseAfterOneWriteWithoutFallback() async throws {
        for control in [UIAAdapterControl.field, .editor] {
            for normalizes in [false, true] {
                try withFixture(control: control) { fixture in
                    let node = try fixture.editor()
                    let id = try fixture.snapshot().id
                    let manager = try XCTUnwrap(fixture.state.manager)
                    let rawInput = UIAAdapterRawInputProbe()
                    rawInput.install(on: node)
                    fixture.state.primary.setter = { [weak model = fixture.state.primary] value in
                        if normalizes { model?.text = value.uppercased() }
                    }

                    XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "lower"))
                    XCTAssertEqual(fixture.state.primary.attemptedValues, ["lower"])
                    XCTAssertEqual(fixture.state.primary.text, normalizes ? "LOWER" : "abcd")
                    XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                    XCTAssertFalse(manager.canUndo)
                    XCTAssertFalse(manager.canRedo)
                    rawInput.assertUnused()
                }
            }
        }
    }

    func testNilAndDisabledUndoManagersStillAcceptOneCompatibleWrite() async throws {
        for usesManager in [false, true] {
            try withFixture(usesUndoManager: usesManager) { fixture in
                let id = try fixture.snapshot().id
                let manager = fixture.state.manager
                if let manager {
                    XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "recorded"))
                    XCTAssertTrue(manager.canUndo)
                    manager.disableUndoRegistration()
                }
                defer { manager?.enableUndoRegistration() }
                fixture.state.primary.afterWrite = { [weak fixture] in fixture?.rebuild() }
                let builds = fixture.state.builds

                XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "unrecorded"))
                fixture.state.primary.afterWrite = nil
                XCTAssertEqual(
                    fixture.state.primary.attemptedValues,
                    usesManager ? ["recorded", "unrecorded"] : ["unrecorded"])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertEqual(fixture.state.builds, builds + 1)
                XCTAssertEqual(fixture.state.primary.text, "unrecorded")
                if let manager {
                    XCTAssertFalse(manager.canUndo)
                    XCTAssertFalse(manager.canRedo)
                } else {
                    XCTAssertNil(fixture.state.manager)
                }
            }
        }
    }

    func testMissingAndCustomControllersAreReadOnlyWithoutRawHandlerFallback() async throws {
        for installsCustom in [false, true] {
            try withFixture { fixture in
                let node = try fixture.editor()
                node.textInputController = installsCustom ? UIAAdapterUnsupportedController() : nil
                let rawInput = UIAAdapterRawInputProbe()
                rawInput.install(on: node)
                let snapshot = try fixture.snapshot()
                let reads = fixture.state.primary.readVersions.count

                XCTAssertTrue(snapshot.supportsValue)
                XCTAssertTrue(snapshot.isReadOnly)
                XCTAssertFalse(fixture.source.uiaSetValue(elementID: snapshot.id, value: "unsupported"))
                XCTAssertEqual(fixture.state.primary.readVersions.count, reads)
                XCTAssertTrue(fixture.state.primary.attemptedValues.isEmpty)
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                rawInput.assertUnused()
            }
        }
    }

    func testSecureFieldExposesNoValuePatternAndRefusesWithoutReadingOrWritingItsBinding() async throws {
        try withFixture(control: .secure) { fixture in
            let node = try fixture.editor()
            let rawInput = UIAAdapterRawInputProbe()
            rawInput.install(on: node)
            let snapshot = try fixture.snapshot()
            let reads = fixture.state.primary.readVersions.count
            let originalText = fixture.state.primary.text

            XCTAssertTrue(snapshot.isPassword)
            XCTAssertFalse(snapshot.supportsValue)
            XCTAssertTrue(snapshot.isReadOnly)
            XCTAssertTrue(snapshot.value == nil, "Secure content must not enter the accessibility value")
            XCTAssertFalse(
                fixture.source.uiaSetValue(elementID: snapshot.id, value: String(repeating: "r", count: 19)))
            XCTAssertEqual(fixture.state.primary.readVersions.count, reads)
            XCTAssertEqual(fixture.state.primary.attemptedValues.count, 0)
            XCTAssertTrue(fixture.state.primary.text == originalText, "The protected binding must remain unchanged")
            XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
            rawInput.assertUnused()
        }
    }

    func testSetterInstallingVisibleOrAccessibilityHiddenModalReturnsFalseAfterOneEffect() async throws {
        for hidden in [false, true] {
            try withFixture { fixture in
                let node = try fixture.editor()
                let id = try fixture.snapshot().id
                let rawInput = UIAAdapterRawInputProbe()
                rawInput.install(on: node)
                fixture.state.primary.afterWrite = { [weak fixture] in
                    fixture?.appendModal(accessibilityHidden: hidden)
                }

                XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "submitted"))
                fixture.state.primary.afterWrite = nil
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["submitted"])
                XCTAssertEqual(fixture.state.primary.text, "submitted")
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertTrue(fixture.runtime.focusedNode === node)
                XCTAssertFalse(try XCTUnwrap(fixture.state.manager).canUndo)
                rawInput.assertUnused()
            }
        }
    }

    func testEnclosingModalAllowsTheEditButClippedCompetingModalConservativelyRefuses() async throws {
        for addsCompetitor in [false, true] {
            try withFixture { fixture in
                let node = try fixture.editor()
                fixture.runtime.root.accessibilityTraits.insert(.isModal)
                if addsCompetitor {
                    let modal = ViewNode(
                        frame: Rect(x: 100, y: 100, width: 20, height: 20),
                        accessibilityLabel: "Clipped competing modal", accessibilityTraits: .isModal)
                    let clip = ViewNode(
                        frame: Rect(x: 0, y: 0, width: 20, height: 20), clipsToBounds: true, children: [modal])
                    fixture.runtime.root.addChild(clip)
                }
                fixture.render()
                let id = try fixture.snapshot().id
                XCTAssertTrue(fixture.runtime.activeModalPresentationNode === fixture.runtime.root)
                let rawInput = UIAAdapterRawInputProbe()
                rawInput.install(on: node)

                XCTAssertEqual(fixture.source.uiaSetValue(elementID: id, value: "modal edit"), !addsCompetitor)
                XCTAssertEqual(fixture.state.primary.attemptedValues, addsCompetitor ? [] : ["modal edit"])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                rawInput.assertUnused()
            }
        }
    }

    func testNewSameNodeOrRoundTripFocusIntentRevokesGetterAndSetterCompletion() async throws {
        for duringSetter in [false, true] {
            for roundTrip in [false, true] {
                try withFixture { fixture in
                    let node = try fixture.editor()
                    let id = try fixture.snapshot().id
                    let rawInput = UIAAdapterRawInputProbe()
                    rawInput.install(on: node)
                    let issueFocus: @MainActor () -> Void = { [weak runtime = fixture.runtime, weak node] in
                        guard let runtime, let node else { return }
                        if roundTrip { runtime.requestFocus(nil) }
                        runtime.requestFocus(node)
                    }
                    if duringSetter {
                        fixture.state.primary.afterWrite = issueFocus
                    } else {
                        fixture.state.primary.beforeRead = { [weak model = fixture.state.primary] _ in
                            model?.beforeRead = nil
                            issueFocus()
                        }
                    }

                    XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "focus intent"))
                    fixture.state.primary.beforeRead = nil
                    fixture.state.primary.afterWrite = nil
                    XCTAssertEqual(fixture.state.primary.attemptedValues, duringSetter ? ["focus intent"] : [])
                    XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                    XCTAssertTrue(fixture.runtime.focusedNode === node)
                    XCTAssertTrue(node.isFocused)
                    rawInput.assertUnused()
                }
            }
        }
    }

    func testSetterRemovalDisableOrKeyedReplacementCannotRetargetItsCompletedWrite() async throws {
        for change in 0..<3 {
            try withFixture { fixture in
                let node = try fixture.editor()
                let id = try fixture.snapshot().id
                let manager = try XCTUnwrap(fixture.state.manager)
                let rawInput = UIAAdapterRawInputProbe()
                rawInput.install(on: node)
                var lateAlternateReads = 0
                fixture.state.primary.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    switch change {
                    case 0: fixture.state.showsEditor = false
                    case 1: fixture.state.isEnabled = false
                    default:
                        fixture.state.alternate.text = fixture.state.primary.text
                        fixture.state.usesAlternate = true
                        fixture.state.identity += 1
                    }
                    fixture.rebuild()
                    fixture.state.alternate.beforeRead = { _ in lateAlternateReads += 1 }
                }

                XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "one effect"))
                fixture.state.primary.afterWrite = nil
                fixture.state.alternate.beforeRead = nil
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["one effect"])
                XCTAssertTrue(fixture.state.alternate.attemptedValues.isEmpty)
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertEqual(fixture.state.alternate.selectionWrites, 0)
                XCTAssertEqual(lateAlternateReads, 0)
                XCTAssertFalse(manager.canUndo)
                rawInput.assertUnused()
            }
        }
    }

    func testCrossAdapterNestedFocusAndSetterCallsAreDeniedAndAdmissionReopens() async throws {
        for duringSetter in [false, true] {
            try withFixture { fixture in
                let node = try fixture.editor()
                if !duringSetter {
                    fixture.runtime.requestFocus(nil)
                    fixture.render()
                }
                let id = try fixture.snapshot().id
                let other = RuntimeUIAElementTreeSource(runtime: fixture.runtime)
                let otherID = try fixture.snapshot(using: other).id
                var nestedResults: [Bool] = []
                let nested: @MainActor () -> Void = {
                    nestedResults.append(other.uiaSetValue(elementID: otherID, value: "nested"))
                    nestedResults.append(other.uiaSetFocusResult(elementID: otherID))
                }
                if duringSetter {
                    fixture.state.primary.afterWrite = nested
                } else {
                    let originalEnter = node.onFocusEnter
                    node.onFocusEnter = {
                        originalEnter?()
                        nested()
                    }
                }

                XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "outer"))
                fixture.state.primary.afterWrite = nil
                XCTAssertEqual(nestedResults, [false, false])
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["outer"])
                XCTAssertTrue(other.uiaSetValue(elementID: otherID, value: "later"))
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["outer", "later"])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
            }
        }
    }

    func testAuthoredSelectionFromACompatibleSetterRebuildWinsWithoutSyntheticBindingWrites() async throws {
        for control in [UIAAdapterControl.field, .editor] {
            try withFixture(control: control) { fixture in
                let id = try fixture.snapshot().id
                fixture.state.primary.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    let text = fixture.state.primary.text
                    fixture.state.primary.selection = TextSelection(
                        range: text.startIndex..<text.index(after: text.startIndex))
                    fixture.rebuild()
                }

                XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "authored"))
                fixture.state.primary.afterWrite = nil
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["authored"])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(0..<1))
                XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            }
        }
    }
}
