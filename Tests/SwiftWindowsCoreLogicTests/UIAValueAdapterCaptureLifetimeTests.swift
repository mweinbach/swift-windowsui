import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class UIAAdapterRetiredBindingPayload {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

@MainActor
private final class UIAAdapterCaptureState {
    var text = "before"
    var attempts: [String] = []
    var retainsPayload = true
    weak var payload: UIAAdapterRetiredBindingPayload?
    var releases = 0
    var releaseAction: (() -> Void)?
    var afterWrite: (() -> Void)?
    let manager = WinSwiftUI.UndoManager()
}

private enum UIAAdapterManualRetirement {
    case revoke
    case detach
}

@MainActor
private struct UIAAdapterCaptureRoot: View {
    let state: UIAAdapterCaptureState

    var body: some View {
        let payload: UIAAdapterRetiredBindingPayload?
        if state.retainsPayload {
            let created = UIAAdapterRetiredBindingPayload { [weak state] in
                guard let state else { return }
                state.releases += 1
                state.releaseAction?()
            }
            state.payload = created
            payload = created
        } else {
            payload = nil
        }
        let text = Binding<String>(
            get: {
                withExtendedLifetime(payload) {}
                return state.text
            },
            set: { value in
                withExtendedLifetime(payload) {}
                state.attempts.append(value)
                state.text = value
                state.afterWrite?()
            })
        return VStack {
            TextField("Value", text: text)
                .accessibilityIdentifier("capture-editor")
                .frame(width: 220, height: 34)
            Button("Other") {}
                .accessibilityIdentifier("capture-other")
            Text(state.text)
        }
        .environment(\.undoManager, Optional(state.manager))
    }
}

@MainActor
private final class UIAAdapterCaptureFixture {
    let state: UIAAdapterCaptureState
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let source: RuntimeUIAElementTreeSource
    let otherSource: RuntimeUIAElementTreeSource
    let id: UInt64
    let otherID: UInt64
    private var active = true
    private(set) var isClosed = false

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init() throws {
        let state = UIAAdapterCaptureState()
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 320, height: 220), scaleFactor: 1)
        let window = Win32Window(title: "Value capture lifetime", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Value capture lifetime", size: surface.pixelSize,
                clearColor: .black, content: [AnyView(UIAAdapterCaptureRoot(state: state))]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.windowDidCreate(window)
        let runtime = host.hostedRuntime
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let otherSource = RuntimeUIAElementTreeSource(runtime: runtime)
        _ = runtime.renderScene()
        let id = try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == "capture-editor" }?.id)
        let otherID = try XCTUnwrap(otherSource.uiaElementSnapshots().first { $0.automationID == "capture-editor" }?.id)
        let editor = try XCTUnwrap(Self.node(in: runtime.root, identifier: "capture-editor"))
        runtime.requestFocus(editor)
        _ = runtime.renderScene()
        state.releases = 0
        self.state = state
        self.window = window
        self.host = host
        self.source = source
        self.otherSource = otherSource
        self.id = id
        self.otherID = otherID
    }

    func node(_ identifier: String) throws -> ViewNode {
        try XCTUnwrap(Self.node(in: runtime.root, identifier: identifier))
    }

    func rebuild() {
        active.toggle()
        host.windowDidChangeActiveState(window, isActive: active)
        _ = runtime.renderScene()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        host.windowWillClose(window)
    }

    private static func node(in root: ViewNode, identifier: String) -> ViewNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if node.accessibilityIdentifier == identifier { return node }
            pending.append(contentsOf: node.children)
        }
        return nil
    }
}

@MainActor
final class UIAValueAdapterCaptureLifetimeTests: XCTestCase {
    private func withFixture(_ body: (UIAAdapterCaptureFixture) throws -> Void) throws {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let glyphs = Array(text).enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 8, y: 0), advance: 8,
                    glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                    fontSize: style.nativeFontPixelSize, sourceIndex: index)
            }
            let size = Size(width: Double(max(text.count, 1)) * 8, height: max(style.nativeFontPixelSize, 1))
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
                contentSize: size, measuredSize: size)
        }
        defer { NativeTextRenderer.resetTestingOverrides() }
        let fixture = try UIAAdapterCaptureFixture()
        defer {
            fixture.state.releaseAction = nil
            fixture.state.afterWrite = nil
            fixture.close()
        }
        try body(fixture)
    }

    func testRetiredOriginalBindingReleaseClosesHostBeforeFinalValueAvailability() async throws {
        try withFixture { fixture in
            XCTAssertNotNil(fixture.state.payload)
            var aliveAfterRebuild: [Bool] = []
            fixture.state.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.retainsPayload = false
                fixture.rebuild()
                aliveAfterRebuild.append(fixture.state.payload != nil)
                XCTAssertEqual(fixture.state.releases, 0)
            }
            fixture.state.releaseAction = { [weak fixture] in fixture?.close() }

            XCTAssertFalse(fixture.source.uiaSetValue(elementID: fixture.id, value: "committed"))
            XCTAssertEqual(fixture.state.attempts, ["committed"])
            XCTAssertEqual(fixture.state.text, "committed")
            XCTAssertEqual(aliveAfterRebuild, [true])
            XCTAssertNil(fixture.state.payload)
            XCTAssertEqual(fixture.state.releases, 1)
            XCTAssertTrue(fixture.isClosed)
            XCTAssertNil(fixture.runtime.focusedNode)
            XCTAssertFalse(fixture.state.manager.canUndo)
            XCTAssertFalse(fixture.source.uiaSetValue(elementID: fixture.id, value: "after-close"))
            XCTAssertEqual(fixture.state.attempts, ["committed"])
        }
    }

    func testRetiredOriginalBindingReleaseCannotHideANewerAwayAndBackFocusIntent() async throws {
        try withFixture { fixture in
            let editor = try fixture.node("capture-editor")
            let other = try fixture.node("capture-other")
            fixture.state.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.retainsPayload = false
                fixture.rebuild()
                XCTAssertNotNil(fixture.state.payload)
            }
            fixture.state.releaseAction = { [weak fixture, weak editor, weak other] in
                guard let fixture, let editor, let other else { return }
                fixture.runtime.requestFocus(other)
                fixture.runtime.requestFocus(editor)
            }

            XCTAssertFalse(fixture.source.uiaSetValue(elementID: fixture.id, value: "committed"))
            XCTAssertEqual(fixture.state.attempts, ["committed"])
            XCTAssertEqual(fixture.state.text, "committed")
            XCTAssertNil(fixture.state.payload)
            XCTAssertEqual(fixture.state.releases, 1)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
            XCTAssertFalse(fixture.isClosed)
            XCTAssertTrue(fixture.state.manager.canUndo, "A false final availability result does not undo the effect")
        }
    }

    func testRetiredOriginalBindingReleaseCannotEnterAnotherAdapterUntilTheOuterCallEnds() async throws {
        try withFixture { fixture in
            var nested: [Bool] = []
            fixture.state.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                fixture.state.retainsPayload = false
                fixture.rebuild()
                XCTAssertNotNil(fixture.state.payload)
            }
            fixture.state.releaseAction = { [weak fixture] in
                guard let fixture else { return }
                nested.append(fixture.otherSource.uiaSetValue(elementID: fixture.otherID, value: "nested"))
                nested.append(fixture.otherSource.uiaSetFocusResult(elementID: fixture.otherID))
            }

            XCTAssertTrue(fixture.source.uiaSetValue(elementID: fixture.id, value: "committed"))
            XCTAssertEqual(nested, [false, false])
            XCTAssertEqual(fixture.state.attempts, ["committed"])
            XCTAssertNil(fixture.state.payload)
            XCTAssertEqual(fixture.state.releases, 1)
            fixture.state.afterWrite = nil
            fixture.state.releaseAction = nil
            XCTAssertTrue(fixture.otherSource.uiaSetValue(elementID: fixture.otherID, value: "independent"))
            XCTAssertEqual(fixture.state.attempts, ["committed", "independent"])
        }
    }

    func testRetiredBindingReleaseCannotHideManualControllerRevocationWithUnchangedNodeAndFocus() async throws {
        for retirement in [UIAAdapterManualRetirement.revoke, .detach] {
            try withFixture { fixture in
                let editor = try fixture.node("capture-editor")
                var preservedSlotAndFocus: [Bool] = []
                fixture.state.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    fixture.state.retainsPayload = false
                    fixture.rebuild()
                    XCTAssertNotNil(fixture.state.payload)
                }
                fixture.state.releaseAction = { [weak fixture, weak editor] in
                    guard let fixture, let editor, let controller = editor.textInputController else {
                        XCTFail("The accepted editor must still occupy its retained slot before manual retirement")
                        return
                    }
                    switch retirement {
                    case .revoke: controller.revokeOwnership(from: editor)
                    case .detach: controller.detach(from: editor)
                    }
                    preservedSlotAndFocus.append(
                        editor.textInputController === controller && fixture.runtime.focusedNode === editor
                            && editor.isFocused)
                }

                XCTAssertFalse(fixture.source.uiaSetValue(elementID: fixture.id, value: "committed"))
                XCTAssertEqual(fixture.state.attempts, ["committed"])
                XCTAssertEqual(fixture.state.text, "committed")
                XCTAssertEqual(preservedSlotAndFocus, [true])
                XCTAssertNil(fixture.state.payload)
                XCTAssertEqual(fixture.state.releases, 1)
                XCTAssertTrue(fixture.runtime.focusedNode === editor)
                XCTAssertNotNil(fixture.runtime.accessibilityTarget(for: editor))
                let snapshot = try XCTUnwrap(
                    fixture.source.uiaElementSnapshots().first { $0.automationID == "capture-editor" })
                XCTAssertTrue(snapshot.supportsValue)
                XCTAssertTrue(snapshot.isReadOnly)
                XCTAssertFalse(fixture.source.uiaSetValue(elementID: fixture.id, value: "after-retirement"))
                fixture.state.manager.undo()
                XCTAssertEqual(fixture.state.text, "committed")
                XCTAssertEqual(fixture.state.attempts, ["committed"], "Local history cannot write a retired editor")
            }
        }
    }
}
