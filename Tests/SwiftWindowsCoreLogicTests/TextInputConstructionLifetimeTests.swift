import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class TextInputConstructionLifetimeTests: XCTestCase {
    func testMovingUnattachedEditorFromConstructionParentPreservesFirstEditAndUndo() async throws {
        try withTextLayout {
            for control in ConstructionLifetimeControl.allCases {
                let fixture = ConstructionLifetimeRuntime(control: control)
                defer { fixture.runtime.root.removeAllChildren() }
                let constructionParent = ViewNode()
                constructionParent.addChild(fixture.subtree)
                XCTAssertTrue(fixture.runtime.root.children.isEmpty)
                XCTAssertTrue(fixture.subtree.parent === constructionParent)

                fixture.runtime.root.addChild(fixture.subtree)
                XCTAssertTrue(constructionParent.children.isEmpty)
                try fixture.focus()
                fixture.type("X")

                XCTAssertEqual(fixture.document.text, "aX")
                XCTAssertEqual(fixture.document.writes, ["aX"])
                XCTAssertTrue(fixture.manager.canUndo)
                fixture.manager.undo()
                XCTAssertEqual(fixture.document.text, "a")
                XCTAssertTrue(fixture.manager.canRedo)
            }
        }
    }

    func testReattachingRetiredEditorDoesNotReviveItsSessionOrAcceptAnotherEdit() async throws {
        try withTextLayout {
            for control in ConstructionLifetimeControl.allCases {
                let fixture = ConstructionLifetimeRuntime(control: control)
                defer { fixture.runtime.root.removeAllChildren() }
                fixture.runtime.root.addChild(fixture.subtree)
                let editor = try fixture.focus()
                let controller = try XCTUnwrap(editor.textInputController)
                fixture.type("X")
                XCTAssertTrue(fixture.manager.canUndo)

                fixture.runtime.root.removeChild(fixture.subtree)
                XCTAssertFalse(fixture.manager.canUndo)
                fixture.runtime.root.addChild(fixture.subtree)
                XCTAssertTrue(try fixture.focus() === editor)
                XCTAssertTrue(editor.textInputController === controller)
                fixture.type("Y")
                fixture.manager.undo()

                XCTAssertEqual(fixture.document.text, "aX")
                XCTAssertEqual(fixture.document.writes, ["aX"])
                XCTAssertFalse(fixture.manager.canUndo)
                XCTAssertFalse(fixture.manager.canRedo)
            }
        }
    }

    func testHostedConditionalInsertionAcceptsItsFirstInput() async throws {
        try withTextLayout {
            for control in ConstructionLifetimeControl.allCases {
                let state = ConstructionLifetimeState(control: control)
                state.showsEditor = false
                let fixture = ConstructionLifetimeHost(state: state)
                defer { fixture.close() }
                XCTAssertNil(constructionLifetimeEditor(in: fixture.runtime.root, identifier: "construction.primary"))
                state.showsEditor = true
                fixture.rebuild()
                try fixture.focus("construction.primary")
                fixture.type("X")

                XCTAssertEqual(state.primary.text, "aX")
                XCTAssertEqual(state.primary.writes, ["aX"])
                let manager = try XCTUnwrap(state.primary.manager)
                XCTAssertTrue(manager.canUndo)
                manager.undo()
                fixture.render()
                XCTAssertEqual(state.primary.text, "a")
            }
        }
    }

    func testHostedIdentityReplacementStartsFreshHistoryAndAcceptsFirstInput() async throws {
        try withTextLayout {
            for control in ConstructionLifetimeControl.allCases {
                let state = ConstructionLifetimeState(control: control)
                let fixture = ConstructionLifetimeHost(state: state)
                defer { fixture.close() }
                let oldEditor = try fixture.focus("construction.primary")
                fixture.type("X")
                let manager = try XCTUnwrap(state.primary.manager)
                XCTAssertTrue(manager.canUndo)
                state.alternate.text = "aX"
                state.usesAlternate = true
                state.identity = "replacement"
                fixture.rebuild()
                XCTAssertFalse(try fixture.focus("construction.primary") === oldEditor)
                XCTAssertFalse(manager.canUndo)
                fixture.type("Y")
                XCTAssertEqual(state.alternate.text, "aXY")
                manager.undo()
                fixture.render()

                XCTAssertEqual(state.primary.text, "aX")
                XCTAssertEqual(state.primary.writes, ["aX"])
                XCTAssertEqual(state.alternate.text, "aX")
                XCTAssertEqual(state.alternate.writes, ["aXY", "aX"])
            }
        }
    }

    func testNewlyPresentedSheetEditorAcceptsFirstInputAndRecordsItsOwnEdit() async throws {
        try withTextLayout {
            for control in ConstructionLifetimeControl.allCases {
                let state = ConstructionLifetimeState(control: control)
                let fixture = ConstructionLifetimeHost(state: state)
                defer { fixture.close() }
                try fixture.focus("construction.primary")
                fixture.type("X")
                state.showsSheet = true
                fixture.rebuild()
                try fixture.focus("construction.sheet")
                fixture.type("Y")

                XCTAssertEqual(state.sheet.text, "sheetY")
                XCTAssertEqual(state.sheet.writes, ["sheetY"])
                XCTAssertEqual(state.primary.text, "aX")
                let manager = try XCTUnwrap(state.sheet.manager)
                XCTAssertTrue(manager.canUndo)
                manager.undo()
                fixture.render()
                XCTAssertEqual(state.sheet.text, "sheet")
                XCTAssertEqual(state.primary.text, "aX")
            }
        }
    }

    private func withTextLayout(_ body: () throws -> Void) rethrows {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let glyphs = text.enumerated().map { index, character in
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
}

private enum ConstructionLifetimeControl: CaseIterable {
    case field
    case editor
}

@MainActor
private final class ConstructionLifetimeDocument {
    var text: String
    var writes: [String] = []
    weak var manager: WinSwiftUI.UndoManager?

    init(_ text: String) { self.text = text }

    var binding: Binding<String> {
        Binding(
            get: { self.text },
            set: {
                self.writes.append($0)
                self.text = $0
            })
    }
}

private struct ConstructionLifetimeInput: View {
    @Environment(\.undoManager) private var manager
    let document: ConstructionLifetimeDocument
    let control: ConstructionLifetimeControl
    let identifier: String

    var body: some View {
        document.manager = manager
        let input: AnyView
        switch control {
        case .field: input = AnyView(TextField("Text", text: document.binding))
        case .editor: input = AnyView(TextEditor(text: document.binding))
        }
        return input.accessibilityIdentifier(identifier).frame(width: 260, height: 96)
    }
}

@MainActor
private final class ConstructionLifetimeRuntime {
    let document = ConstructionLifetimeDocument("a")
    let manager = WinSwiftUI.UndoManager()
    let runtime = RetainedViewRuntime(root: ViewNode())
    let subtree: ViewNode

    init(control: ConstructionLifetimeControl) {
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) }, invalidateHandler: {})
        subtree = ConstructionLifetimeInput(document: document, control: control, identifier: "construction.raw")
            .environment(\.undoManager, manager)
            .makeComponent(context: context).makeNode(runtime: runtime)
        runtime.root.frame = Rect(x: 0, y: 0, width: 400, height: 300)
    }

    @discardableResult
    func focus() throws -> ViewNode {
        let node = try XCTUnwrap(constructionLifetimeEditor(in: subtree, identifier: "construction.raw"))
        runtime.requestFocus(node)
        XCTAssertTrue(runtime.focusedNode === node)
        return node
    }

    func type(_ text: String) {
        runtime.imeComposition(IMECompositionEvent(phase: .committed(text), source: .keyboard))
    }
}

@MainActor
private final class ConstructionLifetimeState {
    let control: ConstructionLifetimeControl
    let primary = ConstructionLifetimeDocument("a")
    let alternate = ConstructionLifetimeDocument("")
    let sheet = ConstructionLifetimeDocument("sheet")
    var showsEditor = true
    var usesAlternate = false
    var showsSheet = false
    var identity = "original"

    init(control: ConstructionLifetimeControl) { self.control = control }
}

private struct ConstructionLifetimeRoot: View {
    let state: ConstructionLifetimeState

    var body: some View {
        VStack {
            if state.showsEditor {
                ConstructionLifetimeInput(
                    document: state.usesAlternate ? state.alternate : state.primary,
                    control: state.control, identifier: "construction.primary"
                )
                .id(state.identity)
            }
            Text("Surviving sibling")
        }
        .sheet(isPresented: Binding(get: { state.showsSheet }, set: { state.showsSheet = $0 })) {
            ConstructionLifetimeInput(document: state.sheet, control: state.control, identifier: "construction.sheet")
        }
    }
}

@MainActor
private final class ConstructionLifetimeHost {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock = RuntimeTestClock()
    private var isActive = true
    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init(state: ConstructionLifetimeState) {
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 400, height: 360), scaleFactor: 1)
        window = Win32Window(title: "Editor construction", clientSize: surface.pixelSize)
        host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Editor construction", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(ConstructionLifetimeRoot(state: state))]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        clock.now = 100
        host.frameClock = { [clock] in clock.now }
        runtime.clock = { [clock] in clock.now }
        host.windowDidCreate(window)
        render()
    }

    func close() { host.windowWillClose(window) }

    func render() {
        clock.now += 0.02
        host.windowNeedsDisplay(window)
        _ = runtime.renderScene(at: clock.now)
    }

    func rebuild() {
        isActive.toggle()
        host.windowDidChangeActiveState(window, isActive: isActive)
        render()
    }

    @discardableResult
    func focus(_ identifier: String) throws -> ViewNode {
        let node = try XCTUnwrap(constructionLifetimeEditor(in: runtime.root, identifier: identifier))
        runtime.requestFocus(node)
        render()
        XCTAssertTrue(runtime.focusedNode === node)
        return node
    }

    func type(_ text: String) {
        host.window(window, didInputText: text)
        render()
    }
}

@MainActor
private func constructionLifetimeEditor(in node: ViewNode, identifier: String) -> ViewNode? {
    if node.accessibilityIdentifier == identifier, node.accessibilityTraits.contains(.isTextInput) { return node }
    for child in node.children {
        if let match = constructionLifetimeEditor(in: child, identifier: identifier) { return match }
    }
    return nil
}
