import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum UIAValueControl {
    case field
    case editor
    case secure
}

@MainActor
private final class UIAValueModel {
    var text = "abcd"
    var selection: TextSelection?
    var attemptedValues: [String] = []
    var writeVersions: [Int] = []
    var readVersions: [Int] = []
    var selectionWrites = 0
    var transactions: [Transaction] = []
    var scopes: [Transaction?] = []
    var beforeRead: ((Int) -> Void)?
    var beforeSelectionRead: (() -> Void)?
    var setter: ((String) -> Void)?
    var afterWrite: (() -> Void)?
}

@MainActor
private final class UIAValueState {
    let primary = UIAValueModel()
    let alternate = UIAValueModel()
    var usesAlternate = false
    var control: UIAValueControl
    var manager: WinSwiftUI.UndoManager? = WinSwiftUI.UndoManager()
    var bindsSelection = false
    var showsEditor = true
    var isEnabled = true
    var identity = 0
    var version = 0
    var builds = 0
    var configureBinding: ((Binding<String>) -> Binding<String>)?
    var beforeBuild: (() -> Void)?
    var mountedBodyTransactions: [Transaction?] = []

    var model: UIAValueModel { usesAlternate ? alternate : primary }

    init(control: UIAValueControl) { self.control = control }
}

@MainActor
private struct UIAValueRoot: View {
    let state: UIAValueState

    var body: some View {
        state.beforeBuild?()
        state.builds += 1
        let model = state.model
        let version = state.version
        let raw = Binding<String>(
            get: {
                model.readVersions.append(version)
                model.beforeRead?(version)
                return model.text
            },
            set: { value, transaction in
                model.attemptedValues.append(value)
                model.writeVersions.append(version)
                model.transactions.append(transaction)
                model.scopes.append(TransactionContext.current)
                if let setter = model.setter { setter(value) } else { model.text = value }
                model.afterWrite?()
            }
        )
        let text = state.configureBinding?(raw) ?? raw
        let selection = Binding<TextSelection?>(
            get: {
                model.beforeSelectionRead?()
                return model.selection
            },
            set: {
                model.selectionWrites += 1
                model.selection = $0
            }
        )
        let input: AnyView
        switch state.control {
        case .field:
            if state.bindsSelection {
                input = AnyView(TextField("Text", text: text, selection: selection))
            } else {
                input = AnyView(TextField("Text", text: text))
            }
        case .editor:
            input = AnyView(TextEditor(text: text, selection: state.bindsSelection ? selection : nil))
        case .secure:
            input = AnyView(SecureField("Secret", text: text))
        }
        return VStack(alignment: .leading, spacing: 4) {
            if state.showsEditor {
                input
                    .disabled(!state.isEnabled)
                    .accessibilityIdentifier("uia-value-editor")
                    .frame(width: 300, height: 120)
                    .id(state.identity)
            }
            Text("Authored text: \(model.text)")
                .accessibilityIdentifier("uia-value-authored")
        }
        .environment(\.undoManager, state.manager)
    }
}

@MainActor
private struct UIAMountedValueRoot: View {
    @State private var text = "abcd"
    let state: UIAValueState

    var body: some View {
        state.builds += 1
        state.primary.text = text
        state.mountedBodyTransactions.append(TransactionContext.current)
        let binding = $text.animation(.linear(duration: 0.4))
        let input: AnyView
        if state.control == .field {
            input = AnyView(TextField("Mounted text", text: binding))
        } else {
            input = AnyView(TextEditor(text: binding))
        }
        return VStack(alignment: .leading, spacing: 4) {
            input
                .accessibilityIdentifier("uia-value-editor")
                .frame(width: 300, height: 120)
            Text("Authored text: \(text)")
        }
        .environment(\.undoManager, state.manager)
    }
}

@MainActor
private func uiaValueNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children)
    }
    return result
}

@MainActor
private final class UIAValueFixture {
    let state: UIAValueState
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    private var active = true
    private(set) var isClosed = false

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init(control: UIAValueControl, mountedState: Bool = false) throws {
        let state = UIAValueState(control: control)
        self.state = state
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 360, height: 280), scaleFactor: 1)
        let content = mountedState ? AnyView(UIAMountedValueRoot(state: state)) : AnyView(UIAValueRoot(state: state))
        window = Win32Window(title: "Accessibility value fixture", clientSize: surface.pixelSize)
        host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Accessibility value fixture", size: surface.pixelSize,
                clearColor: .black, content: [content]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.windowDidCreate(window)
        runtime.requestFocus(try editor())
        render()
    }

    func editor() throws -> ViewNode {
        try XCTUnwrap(
            uiaValueNodes(in: runtime.root).first {
                $0.accessibilityIdentifier == "uia-value-editor" && $0.accessibilityTraits.contains(.isTextInput)
            })
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

    func contains(_ node: ViewNode) -> Bool {
        !isClosed && uiaValueNodes(in: runtime.root).contains { $0 === node }
    }

    func replace(
        _ value: String,
        mayDispatch: (() -> Bool)? = nil,
        isRetainedTargetCurrent: (() -> Bool)? = nil
    ) throws -> TextInputAccessibilityValueResult {
        let node = try editor()
        let original = try XCTUnwrap(node.textInputController as? any TextInputAccessibilityValueReplacing)
        return original.replaceValueForAccessibility(
            value,
            validation: TextInputAccessibilityValueValidation(
                mayDispatch: {
                    (mayDispatch?() ?? true) && self.contains(node)
                        && node.textInputController === original && self.runtime.focusedNode === node
                },
                isRetainedTargetCurrent: {
                    (isRetainedTargetCurrent?() ?? true) && self.contains(node)
                        && self.runtime.focusedNode === node
                }))
    }
}

@MainActor
private final class UIAValueValidationLifetime {}

private struct UIAValueEnvelope { var text: String }

@MainActor
private final class UIAValueDeadUndoTarget {}

@MainActor
private final class UIAValueHistoryRelease {
    let body: @MainActor () -> Void
    init(_ body: @escaping @MainActor () -> Void) { self.body = body }
    deinit { MainActor.assumeIsolated { body() } }
}

/// These call the internal capability on real hosted public controls. They do
/// not invoke a UIA COM provider or qualify native accessibility scheduling.
@MainActor
final class UIATextValueReplacementTests: XCTestCase {
    private func selection(_ range: Range<Int>, in text: String) -> TextSelection {
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        return TextSelection(range: lower..<upper)
    }

    private func withFixture(
        control: UIAValueControl = .editor, mountedState: Bool = false, _ body: (UIAValueFixture) throws -> Void
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
        let fixture = try UIAValueFixture(control: control, mountedState: mountedState)
        defer { fixture.close() }
        try body(fixture)
    }

    func testCustomBindingWritesOnceRefreshesAuthoredContentOnceAndKeepsOneUndoAction() async throws {
        for control in [UIAValueControl.field, .editor] {
            try withFixture(control: control) { fixture in
                let manager = try XCTUnwrap(fixture.state.manager)
                let node = try fixture.editor()
                let builds = fixture.state.builds
                let reloads = fixture.host.executedReloadCount
                let result = try fixture.replace("replaced")

                XCTAssertTrue(result.didDispatch)
                XCTAssertTrue(result.accepted)
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["replaced"])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertEqual(fixture.state.builds, builds + 1)
                XCTAssertEqual(fixture.host.executedReloadCount, reloads + 1)
                XCTAssertTrue(try fixture.editor() === node)
                XCTAssertTrue(uiaValueNodes(in: fixture.runtime.root).contains { $0.text == "Authored text: replaced" })
                XCTAssertEqual(node.textInputCaretOffset, "replaced".count)
                XCTAssertNil(node.textInputSelection)
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

    func testMountedStateProjectionKeepsTheHostTransactionAndRetainedUndoOwner() async throws {
        for control in [UIAValueControl.field, .editor] {
            try withFixture(control: control, mountedState: true) { fixture in
                let node = try fixture.editor()
                let manager = try XCTUnwrap(fixture.state.manager)
                let builds = fixture.state.builds
                let result = try fixture.replace("mounted")

                XCTAssertTrue(result.didDispatch)
                XCTAssertTrue(result.accepted)
                XCTAssertEqual(fixture.state.primary.text, "mounted")
                XCTAssertEqual(fixture.state.builds, builds + 1)
                XCTAssertTrue(try fixture.editor() === node)
                let transaction = try XCTUnwrap(fixture.state.mountedBodyTransactions.last.flatMap { $0 })
                XCTAssertEqual(transaction.animation?.duration, 0.4)
                XCTAssertEqual(node.textInputCaretOffset, 7)
                XCTAssertTrue(manager.canUndo)
                manager.undo()
                XCTAssertEqual(fixture.state.primary.text, "abcd")
                XCTAssertFalse(manager.canUndo)
                XCTAssertTrue(manager.canRedo)
                manager.redo()
                XCTAssertEqual(fixture.state.primary.text, "mounted")
                XCTAssertTrue(try fixture.editor() === node)
            }
        }
    }

    func testSynchronousSetterRebuildPreservesUndoWithoutSecondOldInvalidationOrNewControllerReads() async throws {
        for control in [UIAValueControl.field, .editor] {
            try withFixture(control: control) { fixture in
                let manager = try XCTUnwrap(fixture.state.manager)
                let node = try fixture.editor()
                let builds = fixture.state.builds
                var readsAfterSetter: [Int] = []
                fixture.state.primary.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    fixture.rebuild()
                    fixture.state.primary.beforeRead = { readsAfterSetter.append($0) }
                }
                let result = try fixture.replace("fresh")
                fixture.state.primary.beforeRead = nil

                XCTAssertTrue(result.didDispatch)
                XCTAssertTrue(result.accepted)
                XCTAssertEqual(fixture.state.builds, builds + 1)
                XCTAssertEqual(readsAfterSetter, [0])
                XCTAssertEqual(fixture.state.primary.writeVersions, [0])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertTrue(try fixture.editor() === node)
                manager.undo()
                fixture.state.primary.beforeRead = nil
                XCTAssertEqual(fixture.state.primary.text, "abcd")
                XCTAssertEqual(fixture.state.primary.writeVersions, [0, 1])
                XCTAssertFalse(manager.canUndo)
                fixture.state.primary.afterWrite = nil
            }
        }
    }

    func testAuthoredSelectionWinsWithoutAnySynthesizedSelectionBindingWrite() async throws {
        try withFixture { fixture in
            fixture.state.bindsSelection = true
            fixture.rebuild()
            fixture.state.primary.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                let text = fixture.state.primary.text
                fixture.state.primary.selection = TextSelection(
                    range: text.startIndex..<text.index(after: text.startIndex))
                fixture.rebuild()
            }
            let result = try fixture.replace("new text")
            fixture.state.primary.afterWrite = nil

            XCTAssertTrue(result.accepted)
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["new text"])
            XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
            XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(0..<1))
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
        }
    }

    func testRejectedOrNormalizedSetterDoesNotRegisterTheProposedValue() async throws {
        for acceptsNormalized in [false, true] {
            try withFixture { fixture in
                let manager = try XCTUnwrap(fixture.state.manager)
                fixture.state.primary.setter = { [weak model = fixture.state.primary] value in
                    if acceptsNormalized { model?.text = value.uppercased() }
                }
                let result = try fixture.replace("lower")

                XCTAssertTrue(result.didDispatch)
                XCTAssertFalse(result.accepted)
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["lower"])
                XCTAssertEqual(fixture.state.primary.text, acceptsNormalized ? "LOWER" : "abcd")
                XCTAssertFalse(manager.canUndo)
                XCTAssertFalse(manager.canRedo)
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                if !acceptsNormalized { XCTAssertEqual(try fixture.editor().textInputCaretOffset, 4) }
            }
        }
    }

    func testOriginalGetterDetectsNormalizationAfterACompatibleEqualTextBuild() async throws {
        try withFixture { fixture in
            let manager = try XCTUnwrap(fixture.state.manager)
            fixture.state.primary.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                fixture.rebuild()
                fixture.state.primary.text = "normalized after build"
            }
            let result = try fixture.replace("proposed")
            fixture.state.primary.afterWrite = nil

            XCTAssertTrue(result.didDispatch)
            XCTAssertFalse(result.accepted)
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["proposed"])
            XCTAssertEqual(fixture.state.primary.text, "normalized after build")
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testOriginalGetterReplacementBeforeDispatchDoesNotWriteEitherDocument() async throws {
        try withFixture { fixture in
            fixture.state.primary.beforeRead = { [weak fixture] _ in
                guard let fixture else { return }
                fixture.state.primary.beforeRead = nil
                fixture.state.usesAlternate = true
                fixture.state.identity += 1
                fixture.rebuild()
            }
            let result = try fixture.replace("must not write")

            XCTAssertFalse(result.didDispatch)
            XCTAssertFalse(result.accepted)
            XCTAssertTrue(fixture.state.primary.attemptedValues.isEmpty)
            XCTAssertTrue(fixture.state.alternate.attemptedValues.isEmpty)
            XCTAssertEqual(fixture.state.alternate.selectionWrites, 0)
        }
    }

    func testPostWriteKeyedReplacementNeverReadsOrMutatesTheReplacementAfterSetterReturns() async throws {
        try withFixture { fixture in
            let manager = try XCTUnwrap(fixture.state.manager)
            var lateReplacementReads = 0
            fixture.state.primary.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.alternate.text = fixture.state.primary.text
                fixture.state.usesAlternate = true
                fixture.state.identity += 1
                fixture.rebuild()
                fixture.state.alternate.beforeRead = { _ in lateReplacementReads += 1 }
            }
            let result = try fixture.replace("equal text")
            fixture.state.primary.afterWrite = nil
            fixture.state.alternate.beforeRead = nil

            XCTAssertTrue(result.didDispatch)
            XCTAssertFalse(result.accepted)
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["equal text"])
            XCTAssertEqual(fixture.state.alternate.text, "equal text")
            XCTAssertTrue(fixture.state.alternate.attemptedValues.isEmpty)
            XCTAssertEqual(fixture.state.alternate.selectionWrites, 0)
            XCTAssertEqual(lateReplacementReads, 0)
            XCTAssertFalse(manager.canUndo)
        }
    }

    func testRemovalDisableManagerSecurityAndCloseRevokeAnInFlightAttempt() async throws {
        for change in 0..<5 {
            try withFixture { fixture in
                let manager = try XCTUnwrap(fixture.state.manager)
                fixture.state.primary.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    switch change {
                    case 0: fixture.state.showsEditor = false
                    case 1: fixture.state.isEnabled = false
                    case 2: fixture.state.manager = WinSwiftUI.UndoManager()
                    case 3: fixture.state.control = .secure
                    default:
                        fixture.close()
                        return
                    }
                    fixture.rebuild()
                }
                let result = try fixture.replace("one effect")
                fixture.state.primary.afterWrite = nil

                XCTAssertTrue(result.didDispatch)
                XCTAssertFalse(result.accepted)
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["one effect"])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertFalse(manager.canUndo)
                manager.undo()
                XCTAssertEqual(fixture.state.primary.text, "one effect")
            }
        }
    }

    func testNilManagerCompatibleRebuildWorksButManagerRoundTripDoesNotReviveTheAttempt() async throws {
        for roundTrip in [false, true] {
            try withFixture { fixture in
                fixture.state.manager = nil
                fixture.rebuild()
                fixture.state.primary.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    if roundTrip {
                        fixture.state.manager = WinSwiftUI.UndoManager()
                        fixture.rebuild()
                        fixture.state.manager = nil
                    }
                    fixture.rebuild()
                }
                let result = try fixture.replace("nil history")
                fixture.state.primary.afterWrite = nil

                XCTAssertTrue(result.didDispatch)
                XCTAssertEqual(result.accepted, !roundTrip)
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["nil history"])
                XCTAssertNil(fixture.state.manager)
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
            }
        }
    }

    func testDisabledRegistrationAcceptsOneWriteAndClearsOlderHistory() async throws {
        try withFixture { fixture in
            let manager = try XCTUnwrap(fixture.state.manager)
            XCTAssertTrue(try fixture.replace("first").accepted)
            XCTAssertTrue(manager.canUndo)
            manager.disableUndoRegistration()
            let result = try fixture.replace("unrecorded")
            manager.enableUndoRegistration()

            XCTAssertTrue(result.accepted)
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["first", "unrecorded"])
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testNestedReplacementOwnsItsUndoWithoutAStaleOuterCompletion() async throws {
        try withFixture { fixture in
            let manager = try XCTUnwrap(fixture.state.manager)
            var inner: TextInputAccessibilityValueResult?
            fixture.state.primary.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.primary.afterWrite = nil
                inner = try? fixture.replace("inner")
            }
            let outer = try fixture.replace("outer")

            XCTAssertTrue(outer.didDispatch)
            XCTAssertFalse(outer.accepted)
            XCTAssertTrue(try XCTUnwrap(inner).accepted)
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["outer", "inner"])
            XCTAssertEqual(fixture.state.primary.text, "inner")
            manager.undo()
            XCTAssertEqual(fixture.state.primary.text, "outer")
            XCTAssertFalse(manager.canUndo)
            XCTAssertTrue(manager.canRedo)
        }
    }

    func testBindingTransactionAndExplicitNilAnimationReachTheOriginalSetter() async throws {
        for configuredAnimation in [Animation.linear(duration: 0.7), nil] as [Animation?] {
            try withFixture { fixture in
                fixture.state.configureBinding = { $0.transaction(Transaction(animation: configuredAnimation)) }
                fixture.rebuild()
                let result = try withTransaction(Transaction(animation: .linear(duration: 2))) {
                    try fixture.replace("transaction")
                }

                XCTAssertTrue(result.accepted)
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["transaction"])
                XCTAssertEqual(
                    fixture.state.primary.transactions.first?.animation?.duration, configuredAnimation?.duration)
                let scope = try XCTUnwrap(fixture.state.primary.scopes.first.flatMap { $0 })
                XCTAssertEqual(scope.animation?.duration, configuredAnimation?.duration)
            }
        }
    }

    func testAdmissionAndPostEffectAvailabilityHaveDifferentResultsWithoutRetry() async throws {
        try withFixture { fixture in
            let refused = try fixture.replace("refused", mayDispatch: { false })
            XCTAssertFalse(refused.didDispatch)
            XCTAssertFalse(refused.accepted)
            XCTAssertTrue(fixture.state.primary.attemptedValues.isEmpty)

            let unavailable = try fixture.replace("submitted", isRetainedTargetCurrent: { false })
            XCTAssertTrue(unavailable.didDispatch)
            XCTAssertFalse(unavailable.accepted)
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["submitted"])
            XCTAssertEqual(fixture.state.primary.text, "submitted")
            XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
        }
    }

    func testValidationClosuresAreNotRetainedByTheControllerOrHistory() async throws {
        try withFixture { fixture in
            weak var lifetime: UIAValueValidationLifetime?
            @MainActor
            func invoke() throws -> TextInputAccessibilityValueResult {
                let marker = UIAValueValidationLifetime()
                lifetime = marker
                return try fixture.replace(
                    "temporary validators",
                    mayDispatch: { withExtendedLifetime(marker) { true } },
                    isRetainedTargetCurrent: { withExtendedLifetime(marker) { true } })
            }
            XCTAssertTrue(try invoke().accepted)
            XCTAssertNil(lifetime)
            XCTAssertNotNil(try fixture.editor().textInputController)
            XCTAssertTrue(try XCTUnwrap(fixture.state.manager).canUndo)
        }
    }

    func testOriginalSetterSelectionOverrideWithoutRebuildIsDisplayedAndRecordedForRedo() async throws {
        try withFixture { fixture in
            let manager = try XCTUnwrap(fixture.state.manager)
            fixture.state.bindsSelection = true
            fixture.state.primary.selection = selection(1..<3, in: "abcd")
            fixture.rebuild()
            let builds = fixture.state.builds
            let authored = selection(0..<1, in: "wxyz")
            fixture.state.primary.afterWrite = { [weak model = fixture.state.primary] in
                model?.selection = authored
            }
            let result = try fixture.replace("wxyz")
            fixture.state.primary.afterWrite = nil

            XCTAssertTrue(result.accepted)
            XCTAssertEqual(fixture.state.builds, builds + 1)
            XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
            XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(0..<1))
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
            manager.undo()
            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(1..<3))
            manager.redo()
            XCTAssertEqual(fixture.state.primary.text, "wxyz")
            XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(0..<1))
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 1)
        }
    }

    func testRejectedSetterKeepsAuthoredNilSelectionAndRestoresOnlyUnchangedStaging() async throws {
        for authorsNil in [false, true] {
            for rebuilds in [false, true] {
                try withFixture { fixture in
                    fixture.state.bindsSelection = true
                    fixture.state.primary.selection = selection(1..<3, in: "abcd")
                    fixture.rebuild()
                    fixture.state.primary.setter = { _ in }
                    fixture.state.primary.afterWrite = { [weak fixture] in
                        guard let fixture else { return }
                        if authorsNil { fixture.state.primary.selection = nil }
                        if rebuilds { fixture.rebuild() }
                    }
                    let result = try fixture.replace("wxyz")
                    fixture.state.primary.afterWrite = nil

                    XCTAssertTrue(result.didDispatch)
                    XCTAssertFalse(result.accepted)
                    XCTAssertEqual(fixture.state.primary.text, "abcd")
                    XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                    XCTAssertEqual(try fixture.editor().textInputCaretOffset, authorsNil ? 4 : 3)
                    if authorsNil {
                        XCTAssertNil(try fixture.editor().textInputSelection)
                        XCTAssertNil(fixture.state.primary.selection)
                    } else {
                        XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(1..<3))
                    }
                    XCTAssertFalse(try XCTUnwrap(fixture.state.manager).canUndo)
                }
            }
        }
    }

    func testOriginalSelectionGetterCannotRetireTheTargetAndThenContinueItsUndo() async throws {
        for removes in [false, true] {
            try withFixture { fixture in
                fixture.state.bindsSelection = true
                fixture.rebuild()
                let manager = try XCTUnwrap(fixture.state.manager)
                fixture.state.primary.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    fixture.state.primary.beforeSelectionRead = { [weak fixture] in
                        guard let fixture else { return }
                        fixture.state.primary.beforeSelectionRead = nil
                        if removes {
                            fixture.state.showsEditor = false
                        } else {
                            fixture.state.usesAlternate = true
                            fixture.state.identity += 1
                        }
                        fixture.rebuild()
                    }
                }
                let result = try fixture.replace("accepted before getter")
                fixture.state.primary.afterWrite = nil

                XCTAssertTrue(result.didDispatch)
                XCTAssertFalse(result.accepted)
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["accepted before getter"])
                XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
                XCTAssertTrue(fixture.state.alternate.attemptedValues.isEmpty)
                XCTAssertEqual(fixture.state.alternate.selectionWrites, 0)
                XCTAssertFalse(manager.canUndo)
            }
        }
    }

    func testOriginalSelectionGetterTextMutationCannotRegisterAPhantomAcceptedValue() async throws {
        try withFixture { fixture in
            fixture.state.bindsSelection = true
            fixture.rebuild()
            fixture.state.primary.afterWrite = { [weak model = fixture.state.primary] in
                model?.beforeSelectionRead = { [weak model] in
                    model?.beforeSelectionRead = nil
                    model?.text = "programmatic replacement"
                }
            }
            let result = try fixture.replace("proposed")
            fixture.state.primary.afterWrite = nil

            XCTAssertTrue(result.didDispatch)
            XCTAssertFalse(result.accepted)
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["proposed"])
            XCTAssertEqual(fixture.state.primary.text, "programmatic replacement")
            XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
            XCTAssertFalse(try XCTUnwrap(fixture.state.manager).canUndo)
        }
    }

    func testRegistrationDisabledDuringTheSetterStillRefreshesTheAcceptedCustomBinding() async throws {
        for rebuilds in [false, true] {
            try withFixture { fixture in
                let manager = try XCTUnwrap(fixture.state.manager)
                let builds = fixture.state.builds
                fixture.state.primary.afterWrite = { [weak fixture] in
                    manager.disableUndoRegistration()
                    if rebuilds { fixture?.rebuild() }
                }
                let result = try fixture.replace("accepted without history")
                fixture.state.primary.afterWrite = nil
                manager.enableUndoRegistration()

                XCTAssertTrue(result.accepted)
                XCTAssertEqual(fixture.state.builds, builds + 1)
                XCTAssertEqual(fixture.state.primary.attemptedValues, ["accepted without history"])
                XCTAssertTrue(
                    uiaValueNodes(in: fixture.runtime.root).contains {
                        $0.text == "Authored text: accepted without history"
                    })
                XCTAssertFalse(manager.canUndo)
                XCTAssertFalse(manager.canRedo)
            }
        }
    }

    func testRegistrationDisabledBeforeASynchronousRebuildUsesOnlyItsOwnCheckpointReset() async throws {
        try withFixture { fixture in
            let manager = try XCTUnwrap(fixture.state.manager)
            XCTAssertTrue(try fixture.replace("recorded").accepted)
            manager.disableUndoRegistration()
            fixture.state.primary.afterWrite = { [weak fixture] in fixture?.rebuild() }
            let builds = fixture.state.builds
            let result = try fixture.replace("not recorded")
            fixture.state.primary.afterWrite = nil
            manager.enableUndoRegistration()

            XCTAssertTrue(result.accepted)
            XCTAssertEqual(fixture.state.builds, builds + 1)
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["recorded", "not recorded"])
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testFinalRefreshCannotUseAnEarlierGenerationAllowanceForANewerProgrammaticValue() async throws {
        try withFixture { fixture in
            fixture.state.beforeBuild = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.beforeBuild = nil
                fixture.state.primary.text = "newer during refresh"
            }
            let builds = fixture.state.builds
            let result = try fixture.replace("abcd")

            XCTAssertTrue(result.didDispatch)
            XCTAssertFalse(result.accepted)
            XCTAssertEqual(fixture.state.primary.attemptedValues, ["abcd"])
            XCTAssertEqual(fixture.state.primary.text, "newer during refresh")
            XCTAssertEqual(fixture.state.builds, builds + 1)
            XCTAssertTrue(
                uiaValueNodes(in: fixture.runtime.root).contains { $0.text == "Authored text: newer during refresh" })
            XCTAssertFalse(try XCTUnwrap(fixture.state.manager).canUndo)
        }
    }

    func testGeneratedProjectionReentryCannotReachTheOriginalRootSetter() async throws {
        try withFixture { fixture in
            var armed = false
            var reads = 0
            fixture.state.configureBinding = { binding in
                Binding<UIAValueEnvelope>(
                    get: { [weak fixture] in
                        let text = binding.wrappedValue
                        if armed {
                            reads += 1
                            if reads == 3 {
                                armed = false
                                fixture?.state.identity += 1
                                fixture?.rebuild()
                            }
                        }
                        return UIAValueEnvelope(text: text)
                    },
                    set: { binding.wrappedValue = $0.text }
                ).text
            }
            fixture.rebuild()
            armed = true
            let result = try fixture.replace("must not reach root")

            XCTAssertTrue(result.didDispatch)
            XCTAssertFalse(result.accepted)
            XCTAssertEqual(reads, 3)
            XCTAssertTrue(fixture.state.primary.attemptedValues.isEmpty)
            XCTAssertEqual(fixture.state.primary.text, "abcd")
            XCTAssertEqual(fixture.state.primary.selectionWrites, 0)
        }
    }

    func testHistoryReleaseKeyboardEditsCannotBecomeTheOuterMissingMutation() async throws {
        try withFixture { fixture in
            let manager = try XCTUnwrap(fixture.state.manager)
            XCTAssertTrue(try fixture.replace("first").accepted)
            fixture.state.primary.text = "external"
            var releaseCalls = 0
            @MainActor
            func installDeadTarget() {
                let target = UIAValueDeadUndoTarget()
                let release = UIAValueHistoryRelease { [weak fixture] in
                    guard let fixture else { return }
                    releaseCalls += 1
                    fixture.host.window(fixture.window, didInputText: "X")
                    fixture.host.window(
                        fixture.window,
                        keyDown: KeyboardEvent(
                            keyCode: KeyboardKey.backspace.rawValue, textInputDelivery: .systemCharacter))
                }
                manager.registerUndo(withTarget: target) { _ in withExtendedLifetime(release) {} }
            }
            installDeadTarget()
            let result = try fixture.replace("outer must not write")

            XCTAssertFalse(result.didDispatch)
            XCTAssertFalse(result.accepted)
            XCTAssertEqual(releaseCalls, 1)
            XCTAssertEqual(fixture.state.primary.text, "external")
            XCTAssertFalse(fixture.state.primary.attemptedValues.contains("outer must not write"))
            XCTAssertTrue(manager.canUndo)
            manager.undo()
            XCTAssertTrue(fixture.state.primary.text.contains("X"))
        }
    }
}
