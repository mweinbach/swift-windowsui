import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum UIAFieldChromeHistory: CaseIterable, Equatable {
    case enabled
    case disabled
    case absent
}

private enum UIAFieldChromeExtraLocation: CaseIterable, Equatable {
    case none
    case sibling
    case insideLabel
}

@MainActor
private final class UIAFieldChromeCleanup {
    var created = 0
    var released = 0
    var activated = 0
}

@MainActor
private final class UIAFieldChromeAuthoredPayload {
    let cleanup: UIAFieldChromeCleanup

    init(cleanup: UIAFieldChromeCleanup) {
        self.cleanup = cleanup
        cleanup.created += 1
    }

    isolated deinit { cleanup.released += 1 }
}

@MainActor
private final class UIAFieldChromeState {
    var text = "abcd"
    var selection: TextSelection?
    var placeholder = "Field placeholder"
    var fontSize = 14.0
    var foreground = Color.white
    var isSecure = false
    var showsField = true
    var manager: WinSwiftUI.UndoManager? = WinSwiftUI.UndoManager()
    var version = 0
    var builds = 0
    var values: [String] = []
    var writeVersions: [Int] = []
    var readVersions: [Int] = []
    var selectionWrites = 0
    var beforeRead: (@MainActor (Int) -> Void)?
    var afterWrite: (@MainActor () -> Void)?
    var extraLocation = UIAFieldChromeExtraLocation.none
    weak var authoredChild: ViewNode?
    let cleanup: UIAFieldChromeCleanup

    init(cleanup: UIAFieldChromeCleanup) { self.cleanup = cleanup }
}

@MainActor
private func uiaFieldChromeNodes(in root: ViewNode) -> [ViewNode] {
    var nodes: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        nodes.append(node)
        pending.append(contentsOf: node.children)
    }
    return nodes
}

/// The ordinary input is always a real public control. This test-only wrapper
/// can add an authored node to its constructed source before reconciliation.
@MainActor
private struct UIAFieldChromeInput: View {
    let content: AnyView
    let state: UIAFieldChromeState

    var body: Never { fatalError("UIAFieldChromeInput builds its public input directly") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let input = makeViewComponent(content, context: context)
        let location = state.extraLocation
        return Component { runtime in
            let root = input.makeNode(runtime: runtime)
            guard location != .none else { return root }
            guard
                let field = uiaFieldChromeNodes(in: root).first(where: {
                    $0.accessibilityTraits.contains(.isTextInput)
                }), let label = field.children.first
            else {
                XCTFail("Expected the public field's constructed label")
                return root
            }
            let payload = UIAFieldChromeAuthoredPayload(cleanup: state.cleanup)
            let authored = ViewNode(
                frame: Rect(x: 0, y: 0, width: 8, height: 8),
                accessibilityLabel: "Authored field child", accessibilityIdentifier: "uia-field-authored-child")
            authored.onActivate = { payload.cleanup.activated += 1 }
            state.authoredChild = authored
            if location == .insideLabel {
                label.addChild(authored)
            } else {
                field.addChild(authored)
            }
            return root
        }
    }
}

@MainActor
private struct UIAFieldChromeRoot: View {
    let state: UIAFieldChromeState

    var body: some View {
        state.builds += 1
        let version = state.version
        let text = Binding<String>(
            get: {
                state.readVersions.append(version)
                state.beforeRead?(version)
                return state.text
            },
            set: {
                state.values.append($0)
                state.writeVersions.append(version)
                state.text = $0
                state.afterWrite?()
            })
        let selection = Binding<TextSelection?>(
            get: { state.selection },
            set: {
                state.selectionWrites += 1
                state.selection = $0
            })
        let content: AnyView
        if state.isSecure {
            content = AnyView(SecureField(state.placeholder, text: text))
        } else {
            content = AnyView(TextField(state.placeholder, text: text, selection: selection))
        }
        return VStack(alignment: .leading, spacing: 4) {
            if state.showsField {
                UIAFieldChromeInput(content: content, state: state)
                    .font(.system(size: state.fontSize, weight: .semibold))
                    .foregroundColor(state.foreground)
                    .accessibilityIdentifier("uia-field-chrome")
                    .frame(width: 300, height: 80)
                    .id(0)
            }
            Text(state.isSecure ? "Protected content" : "Authored text: \(state.text)")
        }
        .environment(\.undoManager, state.manager)
    }
}

@MainActor
private final class UIAFieldChromeRawInput {
    var keys = 0
    var compositions = 0

    func install(on node: ViewNode) {
        node.onKeyDown = { [weak self] _ in self?.keys += 1 }
        node.onIMEComposition = { [weak self] _ in self?.compositions += 1 }
    }

    func assertUnused(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(keys, 0, file: file, line: line)
        XCTAssertEqual(compositions, 0, file: file, line: line)
    }
}

@MainActor
private final class UIAFieldChromeFixture {
    let state: UIAFieldChromeState
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    private var active = true
    private var closed = false
    lazy var source = RuntimeUIAElementTreeSource(runtime: runtime)

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init(history: UIAFieldChromeHistory, secure: Bool, cleanup: UIAFieldChromeCleanup) throws {
        let state = UIAFieldChromeState(cleanup: cleanup)
        state.isSecure = secure
        if secure { state.text = String(repeating: "s", count: 17) }
        if history == .absent { state.manager = nil }
        if history == .disabled { state.manager?.disableUndoRegistration() }
        self.state = state
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 360, height: 220), scaleFactor: 1)
        window = Win32Window(title: "Field chrome adoption fixture", clientSize: surface.pixelSize)
        host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Field chrome adoption fixture", size: surface.pixelSize,
                clearColor: .black, content: [AnyView(UIAFieldChromeRoot(state: state))]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.windowDidCreate(window)
        runtime.clock = { 0 }
        runtime.requestFocus(try field())
        render()
    }

    func field() throws -> ViewNode {
        try XCTUnwrap(
            uiaFieldChromeNodes(in: runtime.root).first {
                $0.accessibilityIdentifier == "uia-field-chrome" && $0.accessibilityTraits.contains(.isTextInput)
            })
    }

    func snapshot() throws -> UIAElementSnapshot {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == "uia-field-chrome" })
    }

    func rebuildWithoutRender() {
        state.version += 1
        active.toggle()
        host.windowDidChangeActiveState(window, isActive: active)
    }

    func render() {
        host.windowNeedsDisplay(window)
        _ = runtime.renderScene()
    }

    func close() {
        guard !closed else { return }
        closed = true
        host.windowWillClose(window)
    }
}

/// Headless retained hosts qualify source behavior, not native COM scheduling.
/// Consecutive value calls deliberately have no render or query inserted
/// between them; the regular admission query is the only layout opportunity.
@MainActor
final class UIAFieldChromeAdoptionTests: XCTestCase {
    private func withFixture(
        history: UIAFieldChromeHistory = .enabled, secure: Bool = false,
        cleanup: UIAFieldChromeCleanup? = nil,
        _ body: @MainActor (UIAFieldChromeFixture) throws -> Void
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
        let fixture = try UIAFieldChromeFixture(
            history: history, secure: secure, cleanup: cleanup ?? UIAFieldChromeCleanup())
        defer {
            if history == .disabled { fixture.state.manager?.enableUndoRegistration() }
            fixture.close()
        }
        XCTAssertNil(fixture.window.nativeHandle)
        try body(fixture)
    }

    private func selection(_ range: Range<Int>, in text: String) -> TextSelection {
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        return TextSelection(range: lower..<upper)
    }

    private func assertAuthoredChildIsPresent(
        in fixture: UIAFieldChromeFixture, location: UIAFieldChromeExtraLocation
    ) throws {
        let field = try fixture.field()
        let authored = try XCTUnwrap(fixture.state.authoredChild)
        let expectedParent: ViewNode
        if location == .insideLabel {
            expectedParent = try XCTUnwrap(field.children.first)
        } else {
            expectedParent = field
        }
        XCTAssertTrue(authored.parent === expectedParent)
        XCTAssertTrue(expectedParent.children.contains { $0 === authored })
        XCTAssertEqual(fixture.state.cleanup.created, 1)
        XCTAssertEqual(fixture.state.cleanup.released, 0)
        XCTAssertEqual(fixture.state.cleanup.activated, 0)
    }

    func testConsecutiveUnicodeEmptyAndEqualValuesPrepareFocusedChromeWithoutRendering() async throws {
        for history in UIAFieldChromeHistory.allCases {
            for value in ["e\u{301}👩‍👩‍👧‍👧", "", "abcd"] {
                try withFixture(history: history) { fixture in
                    let node = try fixture.field()
                    let id = try fixture.snapshot().id
                    let rawInput = UIAFieldChromeRawInput()
                    var passAtWrite: UInt64?
                    fixture.state.afterWrite = { [weak runtime = fixture.runtime] in
                        passAtWrite = runtime?.layoutPassID
                    }
                    for attempt in 1...2 {
                        rawInput.install(on: node)
                        let builds = fixture.state.builds
                        let pass = fixture.runtime.layoutPassID

                        XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: value), "\(history), \(attempt)")
                        XCTAssertEqual(fixture.state.values, Array(repeating: value, count: attempt))
                        XCTAssertEqual(Array(fixture.state.text.utf8), Array(value.utf8))
                        XCTAssertEqual(fixture.state.selectionWrites, 0)
                        XCTAssertEqual(fixture.state.builds, builds + 1)
                        XCTAssertEqual(fixture.runtime.layoutPassID, pass + 1)
                        XCTAssertEqual(fixture.runtime.layoutPassID, try XCTUnwrap(passAtWrite))
                        XCTAssertTrue(try fixture.field() === node)
                        XCTAssertTrue(node.isFocused)
                        XCTAssertEqual(node.textInputCaretOffset, value.count)
                        XCTAssertNil(node.textInputSelection)
                        XCTAssertTrue(try XCTUnwrap(node.children.first).isHidden)
                        XCTAssertEqual(uiaFieldChromeNodes(in: node).filter(\.isTextInputCaret).count, 1)
                        rawInput.assertUnused()
                    }
                    fixture.state.afterWrite = nil
                    if history == .enabled, value != "abcd" {
                        let manager = try XCTUnwrap(fixture.state.manager)
                        XCTAssertTrue(manager.canUndo)
                        manager.undo()
                        XCTAssertEqual(fixture.state.text, "abcd")
                        XCTAssertFalse(manager.canUndo)
                    } else {
                        XCTAssertFalse(fixture.state.manager?.canUndo ?? false)
                    }
                }
            }
        }
    }

    func testSynchronousSetterAdoptionReadsOnlyTheOriginalGetterAfterTheSetterReturns() async throws {
        try withFixture { fixture in
            let node = try fixture.field()
            let original = try XCTUnwrap(node.textInputController)
            let id = try fixture.snapshot().id
            let builds = fixture.state.builds
            var readsDuringRebuild: [Int] = []
            var readsAfterSetter: [Int] = []
            var passAtWrite: UInt64?
            fixture.state.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                passAtWrite = fixture.runtime.layoutPassID
                let readsBeforeRebuild = fixture.state.readVersions.count
                fixture.rebuildWithoutRender()
                readsDuringRebuild = Array(fixture.state.readVersions.dropFirst(readsBeforeRebuild))
                fixture.state.beforeRead = { readsAfterSetter.append($0) }
            }

            XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "adopted"))
            fixture.state.beforeRead = nil
            fixture.state.afterWrite = nil
            // Construction and its two undo-configuration steps read the
            // incoming binding. Preparing chrome must not add another read.
            XCTAssertEqual(readsDuringRebuild, [1, 1, 1])
            XCTAssertEqual(readsAfterSetter, [0])
            XCTAssertEqual(fixture.state.writeVersions, [0])
            XCTAssertEqual(fixture.state.values, ["adopted"])
            XCTAssertEqual(fixture.state.selectionWrites, 0)
            XCTAssertEqual(fixture.state.builds, builds + 1)
            XCTAssertEqual(fixture.runtime.layoutPassID, try XCTUnwrap(passAtWrite))
            XCTAssertTrue(try fixture.field() === node)
            XCTAssertFalse(node.textInputController === original)
            XCTAssertEqual(uiaFieldChromeNodes(in: node).filter(\.isTextInputCaret).count, 1)

            XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "adopted"))
            XCTAssertEqual(fixture.state.writeVersions, [0, 1])
            XCTAssertEqual(fixture.state.values, ["adopted", "adopted"])
            let manager = try XCTUnwrap(fixture.state.manager)
            manager.undo()
            XCTAssertEqual(fixture.state.text, "abcd")
            XCTAssertFalse(manager.canUndo)
        }
    }

    func testAuthoredUnicodeSelectionAndCaretProduceMatchingChromeWithoutSelectionWrites() async throws {
        try withFixture { fixture in
            let node = try fixture.field()
            let id = try fixture.snapshot().id
            let value = "A👩‍👩‍👧‍👧e\u{301}Z"
            var written = 0
            fixture.state.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                written += 1
                let range = written == 1 ? 1..<3 : 0..<1
                fixture.state.selection = self.selection(range, in: fixture.state.text)
                fixture.rebuildWithoutRender()
            }
            for attempt in 1...2 {
                let range = attempt == 1 ? 1..<3 : 0..<1
                let selected = attempt == 1 ? "👩‍👩‍👧‍👧e\u{301}" : "A"
                XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: value))
                XCTAssertEqual(fixture.state.values, Array(repeating: value, count: attempt))
                XCTAssertEqual(fixture.state.selectionWrites, 0)
                XCTAssertTrue(try fixture.field() === node)
                XCTAssertEqual(node.textInputSelection?.indices, .range(range))
                XCTAssertEqual(node.textInputCaretOffset, range.upperBound)
                XCTAssertEqual(uiaFieldChromeNodes(in: node).filter(\.isTextInputCaret).count, 0)
                XCTAssertEqual(
                    uiaFieldChromeNodes(in: node).filter { $0.text == selected && $0.backgroundColor != nil }.count, 1)
            }
            fixture.state.afterWrite = nil
        }
    }

    func testIncomingFontColorAndPlaceholderStyleAreUsedBeforeAnotherFrame() async throws {
        try withFixture { fixture in
            let node = try fixture.field()
            let id = try fixture.snapshot().id
            let incomingColor = Color(red: 0.7, green: 0.2, blue: 0.4)
            let placeholderForeground = Color(red: 0.2, green: 0.6, blue: 0.3)
            fixture.state.afterWrite = { [weak state = fixture.state] in
                guard let state else { return }
                state.fontSize = state.text.isEmpty ? 26 : 21
                state.foreground = state.text.isEmpty ? placeholderForeground : incomingColor
                state.placeholder = "Incoming placeholder"
            }
            for value in ["styled", ""] {
                XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: value))
                let label = try XCTUnwrap(node.children.first)
                let caret = try XCTUnwrap(uiaFieldChromeNodes(in: node).first { $0.isTextInputCaret })
                let renderedText = uiaFieldChromeNodes(in: node).filter { $0 !== label && $0.text != nil }
                XCTAssertTrue(label.isHidden)
                XCTAssertEqual(label.text, value.isEmpty ? "Incoming placeholder" : value)
                XCTAssertEqual(label.textStyle.nativeFontPixelSize, value.isEmpty ? 26 : 21)
                XCTAssertFalse(renderedText.isEmpty)
                for segment in renderedText {
                    XCTAssertEqual(segment.textStyle.nativeFontPixelSize, label.textStyle.nativeFontPixelSize)
                    XCTAssertEqual(segment.textStyle.color, label.textStyle.color)
                    XCTAssertEqual(segment.textStyle.fontFamily, label.textStyle.fontFamily)
                }
                XCTAssertEqual(caret.backgroundColor, label.textStyle.color)
                XCTAssertEqual(try XCTUnwrap(caret.preferredSize).height, label.textStyle.nativeFontPixelSize)
                if !value.isEmpty { XCTAssertEqual(label.textStyle.color, incomingColor) }
                XCTAssertEqual(fixture.state.selectionWrites, 0)
            }
            fixture.state.afterWrite = nil
            XCTAssertEqual(fixture.state.values, ["styled", ""])
        }
    }

    func testActiveCompositionRefusesValueReplacementWithoutClearingMarkedText() async throws {
        try withFixture { fixture in
            let node = try fixture.field()
            let id = try fixture.snapshot().id
            let compose = try XCTUnwrap(node.onIMEComposition)
            compose(IMECompositionEvent(phase: .started))
            compose(IMECompositionEvent(phase: .updated("ni")))
            let caret = node.textInputCaretOffset
            let selected = node.textInputSelection
            let rawInput = UIAFieldChromeRawInput()
            rawInput.install(on: node)

            XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "must not commit"))
            XCTAssertTrue(fixture.state.values.isEmpty)
            XCTAssertEqual(fixture.state.text, "abcd")
            XCTAssertEqual(node.textInputMarkedText, "ni")
            XCTAssertEqual(node.textInputCaretOffset, caret)
            XCTAssertEqual(node.textInputSelection, selected)
            XCTAssertEqual(fixture.state.selectionWrites, 0)
            rawInput.assertUnused()
        }
    }

    func testCompositionStartedBySetterSurvivesAdoptionWithoutASecondValueEffect() async throws {
        try withFixture { fixture in
            let node = try fixture.field()
            let id = try fixture.snapshot().id
            let compose = try XCTUnwrap(node.onIMEComposition)
            let rawInput = UIAFieldChromeRawInput()
            rawInput.install(on: node)
            fixture.state.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                compose(IMECompositionEvent(phase: .started))
                compose(IMECompositionEvent(phase: .updated("ni")))
                fixture.rebuildWithoutRender()
            }

            XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "accepted"))
            fixture.state.afterWrite = nil
            XCTAssertEqual(fixture.state.values, ["accepted"])
            XCTAssertEqual(fixture.state.writeVersions, [0])
            XCTAssertEqual(fixture.state.text, "accepted")
            XCTAssertTrue(try fixture.field() === node)
            XCTAssertEqual(node.textInputMarkedText, "ni")
            XCTAssertEqual(fixture.state.selectionWrites, 0)
            XCTAssertFalse(try XCTUnwrap(fixture.state.manager).canUndo)
            rawInput.assertUnused()

            XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "must still refuse"))
            XCTAssertEqual(fixture.state.values, ["accepted"])
            XCTAssertEqual(node.textInputMarkedText, "ni")
            let endComposition = try XCTUnwrap(node.onIMEComposition)
            endComposition(IMECompositionEvent(phase: .ended))
            XCTAssertNil(node.textInputMarkedText)
            XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "after composition"))
            XCTAssertEqual(fixture.state.values, ["accepted", "after composition"])
            XCTAssertEqual(fixture.state.selectionWrites, 0)
        }
    }

    func testSecureFieldsExposeNoValueOrUnmaskedChromeAcrossRebuilds() async throws {
        try withFixture(secure: true) { fixture in
            let node = try fixture.field()
            let snapshot = try fixture.snapshot()
            let originalText = fixture.state.text
            XCTAssertTrue(snapshot.isPassword)
            XCTAssertFalse(snapshot.supportsValue)
            XCTAssertTrue(snapshot.value == nil, "Protected text must not appear in the accessibility value")
            for rebuilds in [false, true] {
                if rebuilds { fixture.rebuildWithoutRender() }
                let reads = fixture.state.readVersions.count
                XCTAssertFalse(
                    fixture.source.uiaSetValue(
                        elementID: snapshot.id, value: String(repeating: "r", count: 19)))
                XCTAssertEqual(fixture.state.readVersions.count, reads)
                XCTAssertEqual(fixture.state.values.count, 0)
                XCTAssertTrue(fixture.state.text == originalText, "The protected binding must remain unchanged")
                XCTAssertTrue(try fixture.field() === node)
                XCTAssertTrue(
                    uiaFieldChromeNodes(in: node).allSatisfy { $0.text?.contains(originalText) != true },
                    "Protected text must not appear in retained display labels")
            }
        }
    }

    func testUnexpectedSourceChildrenSurvivePreparationAndCleanUpOnlyOnNormalRemoval() async throws {
        for location in [UIAFieldChromeExtraLocation.sibling, .insideLabel] {
            let cleanup = UIAFieldChromeCleanup()
            try withFixture(cleanup: cleanup) { fixture in
                let identity = ObjectIdentifier(try fixture.field())
                let id = try fixture.snapshot().id
                fixture.state.afterWrite = { [weak state = fixture.state] in state?.extraLocation = location }

                XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "one effect"))
                fixture.state.afterWrite = nil
                XCTAssertEqual(fixture.state.values, ["one effect"])
                XCTAssertEqual(fixture.state.selectionWrites, 0)
                XCTAssertEqual(ObjectIdentifier(try fixture.field()), identity)
                // Do not render or project here: this witnesses preparation,
                // before ordinary layout may normalize a field's child tree.
                try assertAuthoredChildIsPresent(in: fixture, location: location)

                fixture.state.showsField = false
                fixture.rebuildWithoutRender()
                fixture.render()
                XCTAssertNil(fixture.state.authoredChild)
                XCTAssertEqual(cleanup.released, 1)
                XCTAssertEqual(cleanup.activated, 0)
            }
            XCTAssertEqual(cleanup.created, 1)
            XCTAssertEqual(cleanup.released, 1)
        }
    }
}
