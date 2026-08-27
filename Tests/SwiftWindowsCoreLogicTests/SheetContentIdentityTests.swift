import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum SheetContentIdentityKind {
    case boolean
    case item
}

private struct SheetContentIdentityItem: Identifiable {
    let id: Int
}

@MainActor
private final class SheetContentIdentityModel {
    let kind: SheetContentIdentityKind
    var text = "abcd"
    var isPresented = false
    var item: SheetContentIdentityItem?
    var dismissCount = 0
    var manager: WinSwiftUI.UndoManager?

    init(kind: SheetContentIdentityKind) { self.kind = kind }

    func present() {
        isPresented = true
        item = SheetContentIdentityItem(id: 1)
    }

    func hide() {
        isPresented = false
        item = nil
    }
}

@MainActor
private struct SheetContentIdentityPresentation: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Dismiss") { dismiss() }
            .accessibilityIdentifier("sheet-identity-dismiss")
    }
}

@MainActor
private struct SheetContentIdentityView: View {
    @Environment(\.undoManager) private var manager
    let model: SheetContentIdentityModel

    var body: AnyView {
        model.manager = manager
        let editor = TextField(
            "Editor",
            text: Binding(get: { model.text }, set: { model.text = $0 })
        )
        .accessibilityIdentifier("sheet-identity-editor")
        .frame(width: 240, height: 40)

        switch model.kind {
        case .boolean:
            return AnyView(
                editor.sheet(
                    isPresented: Binding(get: { model.isPresented }, set: { model.isPresented = $0 }),
                    onDismiss: { model.dismissCount += 1 }
                ) {
                    SheetContentIdentityPresentation()
                })
        case .item:
            return AnyView(
                editor.sheet(
                    item: Binding(get: { model.item }, set: { model.item = $0 }),
                    onDismiss: { model.dismissCount += 1 }
                ) { _ in
                    SheetContentIdentityPresentation()
                })
        }
    }
}

@MainActor
private func sheetContentIdentityNode(in root: ViewNode, matching predicate: (ViewNode) -> Bool) -> ViewNode? {
    if predicate(root) { return root }
    for child in root.children {
        if let node = sheetContentIdentityNode(in: child, matching: predicate) { return node }
    }
    return nil
}

/// Plain closure bindings keep these presentation tests independent of mounted
/// State installation. Both raw reconciliation and the real window host must
/// preserve the background editor through an absent/present/absent sheet.
@MainActor
final class SheetContentIdentityTests: XCTestCase {
    func testBooleanSheetKeepsRawBackgroundIdentityAndSelection() async throws {
        try withTextLayout { try assertRawRoundTrip(kind: .boolean) }
    }

    func testItemSheetKeepsRawBackgroundIdentityAndSelection() async throws {
        try withTextLayout { try assertRawRoundTrip(kind: .item) }
    }

    func testBooleanSheetKeepsHostedBackgroundUndoUntilDismissal() async throws {
        try withTextLayout { try assertHostedRoundTrip(kind: .boolean) }
    }

    func testItemSheetKeepsHostedBackgroundUndoUntilDismissal() async throws {
        try withTextLayout { try assertHostedRoundTrip(kind: .item) }
    }

    private func assertRawRoundTrip(kind: SheetContentIdentityKind) throws {
        let model = SheetContentIdentityModel(kind: kind)
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 360, height: 320)))
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 360, height: 320) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        let unpresented = SheetContentIdentityView(model: model).makeComponent(context: context)
            .makeNode(runtime: runtime)
        XCTAssertEqual(unpresented.intrinsicContentSize(), Size(width: 240, height: 40))
        host.setComponents {
            [composeComponent(from: [AnyView(SheetContentIdentityView(model: model))], context: context)]
        }
        _ = runtime.renderFrame()
        let shell = try XCTUnwrap(runtime.root.children.first)
        let base = try XCTUnwrap(shell.children.first)
        let editor = try editor(in: runtime)
        let identity = editor.retainedViewIdentity
        XCTAssertNotNil(identity)
        editor.textInputCaretOffset = 1
        editor.textInputSelection = RetainedTextSelection(indices: .range(1..<3), affinity: .upstream)

        for isPresented in [true, false, true, false] {
            if isPresented { model.present() } else { model.hide() }
            host.reload()
            _ = runtime.renderFrame()

            XCTAssertTrue(runtime.root.children.first === shell)
            XCTAssertTrue(shell.children.first === base)
            XCTAssertTrue(try self.editor(in: runtime) === editor)
            XCTAssertEqual(editor.retainedViewIdentity, identity)
            XCTAssertEqual(editor.textInputCaretOffset, 1)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(1..<3))
            XCTAssertEqual(editor.textInputSelection?.affinity, .upstream)
            XCTAssertEqual(shell.children.count, isPresented ? 2 : 1)
            let overlay = sheetContentIdentityNode(in: shell) { $0.nodeTag == "sheet-overlay" }
            XCTAssertEqual(overlay != nil, isPresented)
        }
    }

    private func assertHostedRoundTrip(kind: SheetContentIdentityKind) throws {
        let model = SheetContentIdentityModel(kind: kind)
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 360, height: 320), scaleFactor: 1)
        let window = Win32Window(title: "Sheet content identity", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Sheet content identity",
                size: surface.pixelSize,
                clearColor: .black,
                content: [AnyView(SheetContentIdentityView(model: model))]
            ),
            platformWindow: window,
            renderer: FakeRenderBackend(),
            batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface },
            startupProbeConfiguration: nil
        )
        host.windowDidCreate(window)
        defer { host.windowWillClose(window) }
        let runtime = host.hostedRuntime
        func render() {
            host.windowNeedsDisplay(window)
            _ = runtime.renderScene()
        }
        func key(_ code: UInt32, modifiers: KeyboardModifiers = []) {
            host.window(
                window,
                keyDown: KeyboardEvent(keyCode: code, modifiers: modifiers, textInputDelivery: .systemCharacter)
            )
            render()
        }
        let editor = try editor(in: runtime)
        runtime.requestFocus(editor)
        key(KeyboardKey.home.rawValue)
        key(KeyboardKey.rightArrow.rawValue)
        key(KeyboardKey.rightArrow.rawValue)
        host.window(window, didInputText: "X")
        render()
        let manager = try XCTUnwrap(model.manager)
        XCTAssertEqual(model.text, "abXcd")
        XCTAssertEqual(editor.textInputCaretOffset, 3)
        XCTAssertTrue(manager.canUndo)

        model.present()
        host.windowDidChangeActiveState(window, isActive: false)
        render()
        XCTAssertTrue(try self.editor(in: runtime) === editor)
        XCTAssertEqual(editor.textInputCaretOffset, 3)
        XCTAssertTrue(manager.canUndo, "Presenting a sheet must not detach the background editor")
        let dismissButton = try XCTUnwrap(
            sheetContentIdentityNode(in: runtime.root) { $0.accessibilityIdentifier == "sheet-identity-dismiss" }
        )
        runtime.requestFocus(dismissButton)
        manager.undo()
        render()
        XCTAssertEqual(model.text, "abXcd", "The retained history stays blocked by the modal scope")
        XCTAssertTrue(manager.canUndo)
        XCTAssertFalse(manager.canRedo)

        key(KeyboardKey.enter.rawValue)
        XCTAssertEqual(model.dismissCount, 1)
        XCTAssertNil(sheetContentIdentityNode(in: runtime.root) { $0.nodeTag == "sheet-overlay" })
        XCTAssertTrue(try self.editor(in: runtime) === editor)
        XCTAssertEqual(editor.textInputCaretOffset, 3)
        XCTAssertTrue(manager.canUndo)
        runtime.requestFocus(editor)
        key(0x5A, modifiers: [.control])
        XCTAssertEqual(model.text, "abcd")
        XCTAssertEqual(editor.textInputCaretOffset, 2)
        XCTAssertFalse(manager.canUndo)
        XCTAssertTrue(manager.canRedo)
        key(0x59, modifiers: [.control])
        XCTAssertEqual(model.text, "abXcd")
        XCTAssertEqual(editor.textInputCaretOffset, 3)
    }

    private func editor(in runtime: RetainedViewRuntime) throws -> ViewNode {
        try XCTUnwrap(
            sheetContentIdentityNode(in: runtime.root) {
                $0.accessibilityIdentifier == "sheet-identity-editor" && $0.accessibilityTraits.contains(.isTextInput)
            }
        )
    }

    private func withTextLayout(_ body: () throws -> Void) rethrows {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let characters = Array(text)
            let glyphs = characters.enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character,
                    origin: Point(x: Double(index) * 10, y: 0),
                    advance: 10,
                    glyphID: UInt32(index + 1),
                    fontFamily: style.fontFamily,
                    weight: style.weight,
                    fontSize: style.nativeFontPixelSize,
                    sourceIndex: index
                )
            }
            let width = Double(max(characters.count, 1)) * 10
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
}
