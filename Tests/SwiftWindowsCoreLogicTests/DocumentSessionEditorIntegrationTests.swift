import Foundation
import SwiftWindowsCore
import SwiftWindowsDemo
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class SessionEditorRecorder {
    var configuration: FileDocumentConfiguration<DemoPlainTextDocument>?
    var selection: TextSelection?
}

@MainActor
private struct SessionEditorProbe: View {
    typealias Body = Never
    let configuration: FileDocumentConfiguration<DemoPlainTextDocument>
    let recorder: SessionEditorRecorder

    var body: Never { fatalError("SessionEditorProbe has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        recorder.configuration = configuration
        return makeViewComponent(
            TextEditor(
                text: configuration.$document.text,
                selection: Binding(get: { recorder.selection }, set: { recorder.selection = $0 })
            )
            .font(.system(size: 16))
            .lineSpacing(0)
            .accessibilityIdentifier("session.integration.editor")
            .frame(width: 320, height: 140), context: context
        )
    }
}

@MainActor
private final class SessionEditorFixture {
    let directory: URL
    let url: URL
    let recorder: SessionEditorRecorder
    let coordinator: WinSwiftUIWindowCoordinator
    let host: WinSwiftUIWindowHost
    let context: DocumentWindowContext
    let runtime: RetainedViewRuntime
    let manager: WinSwiftUI.UndoManager

    init(text: String = "A") throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-windowsui-session-editor-\(UUID().uuidString)", isDirectory: true)
        let recorder = SessionEditorRecorder()
        let configuration = DocumentGroup(newDocument: DemoPlainTextDocument(text: text)) { configuration in
            SessionEditorProbe(configuration: configuration, recorder: recorder)
        }.makeWindowConfiguration()
        let coordinator = WinSwiftUIWindowCoordinator(
            sceneConfigurations: [configuration],
            hooks: WindowCoordinatorHooks(
                startWindow: { host in host.windowDidCreate(host.platformWindow) },
                requestCloseWindow: { host in
                    if host.windowShouldClose(host.platformWindow) { host.windowWillClose(host.platformWindow) }
                },
                runMessageLoop: { 0 }, terminateMessageLoop: {}
            ),
            hostFactory: { configuration, _ in
                WinSwiftUIWindowHost(
                    configuration: configuration, renderer: FakeRenderBackend(), batchRenderer: nil,
                    surfaceDescriptorProvider: { _ in
                        SurfaceDescriptor(
                            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1))!,
                            pixelSize: IntSize(width: 640, height: 480), scaleFactor: 1)
                    },
                    startupProbeConfiguration: nil
                )
            },
            documentServices: .headless(files: LiveDocumentFileService())
        )
        let host = try coordinator.bootPrimaryWindow()
        var createdDirectory = false
        do {
            let context = try XCTUnwrap(host.documentContext)
            let runtime = try XCTUnwrap(context.owner.runtime)
            let manager = try XCTUnwrap(context.undoManager)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            createdDirectory = true
            self.directory = directory
            url = directory.appendingPathComponent("document.txt")
            self.recorder = recorder
            self.coordinator = coordinator
            self.host = host
            self.context = context
            self.runtime = runtime
            self.manager = manager
            runtime.requestFocus(try editor())
            render()
        } catch {
            host.windowWillClose(host.platformWindow)
            if createdDirectory,
                directory.deletingLastPathComponent().standardizedFileURL
                    == FileManager.default.temporaryDirectory.standardizedFileURL
            {
                try? FileManager.default.removeItem(at: directory)
            }
            throw error
        }
    }

    var text: String { recorder.configuration?.document.text ?? "" }

    func editor() throws -> ViewNode {
        var pending = [runtime.root]
        while let node = pending.popLast() {
            if node.accessibilityTraits.contains(.isTextInput) { return node }
            pending.append(contentsOf: node.children.reversed())
        }
        XCTFail("Expected the actual document session's retained editor")
        throw DocumentSessionError.ownerUnavailable
    }

    func render() { _ = runtime.renderScene() }

    func key(_ code: UInt32, modifiers: KeyboardModifiers = []) {
        runtime.keyDown(KeyboardEvent(keyCode: code, modifiers: modifiers, textInputDelivery: .systemCharacter))
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

    func assign(_ text: String) throws {
        try XCTUnwrap(recorder.configuration).$document.text.wrappedValue = text
        render()
    }

    func boundRange() -> Range<Int>? {
        guard case .selection(let range) = recorder.selection?.indices else { return nil }
        let boundaries = Array(text.indices) + [text.endIndex]
        guard let lower = boundaries.firstIndex(of: range.lowerBound),
            let upper = boundaries.firstIndex(of: range.upperBound), lower <= upper
        else { return nil }
        return lower..<upper
    }

    func cleanup() {
        host.windowWillClose(host.platformWindow)
        // Only this fresh direct child of the system temporary directory is owned.
        guard
            directory.deletingLastPathComponent().standardizedFileURL
                == FileManager.default.temporaryDirectory.standardizedFileURL
        else { return XCTFail("Refusing cleanup outside the owned temporary directory") }
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
final class DocumentSessionEditorIntegrationTests: XCTestCase {
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

    func testRealSessionInterleavesEditorAndDirectWritesWithoutDuplicateHistory() async throws {
        try withLayout {
            let fixture = try SessionEditorFixture()
            defer { fixture.cleanup() }
            let editor = try fixture.editor()
            let unicode = "e\u{301}👩🏽‍💻B"
            fixture.key(0x41, modifiers: [.control])
            XCTAssertEqual(fixture.boundRange(), 0..<1)
            fixture.type(unicode)
            XCTAssertEqual(fixture.text, unicode)
            XCTAssertEqual(fixture.boundRange(), 3..<3)
            guard case .saved(let receipt, let isCurrent) = fixture.context.save(to: fixture.url) else {
                return XCTFail("The joined session must commit real bytes")
            }
            XCTAssertTrue(isCurrent)
            XCTAssertEqual(receipt.bytes, Data(unicode.utf8))
            XCTAssertEqual(try Data(contentsOf: fixture.url), receipt.bytes)
            let savedCheckpoint = fixture.context.session.savedCheckpoint
            XCTAssertFalse(fixture.context.session.isDirty)

            try fixture.assign("direct")
            fixture.key(KeyboardKey.end.rawValue, modifiers: [.control])
            fixture.type("!")
            XCTAssertEqual(fixture.text, "direct!")
            XCTAssertEqual(fixture.context.session.mutationRevision, 3)

            fixture.key(0x5A, modifiers: [.control])
            XCTAssertEqual(fixture.text, "direct")
            XCTAssertEqual(fixture.boundRange(), 6..<6)
            XCTAssertTrue(fixture.context.session.isDirty)
            fixture.key(0x5A, modifiers: [.control])
            XCTAssertEqual(fixture.text, unicode)
            XCTAssertFalse(fixture.context.session.isDirty)
            XCTAssertEqual(fixture.context.session.currentCheckpoint, savedCheckpoint)
            fixture.key(0x5A, modifiers: [.control])
            XCTAssertEqual(fixture.text, "A")
            XCTAssertEqual(fixture.boundRange(), 0..<1)
            XCTAssertTrue(fixture.context.session.isDirty)
            XCTAssertFalse(fixture.manager.canUndo)

            fixture.key(0x59, modifiers: [.control])
            XCTAssertEqual(fixture.text, unicode)
            XCTAssertEqual(fixture.boundRange(), 3..<3)
            XCTAssertFalse(fixture.context.session.isDirty)
            fixture.key(0x59, modifiers: [.control])
            XCTAssertEqual(fixture.text, "direct")
            fixture.key(0x59, modifiers: [.control])
            XCTAssertEqual(fixture.text, "direct!")
            XCTAssertEqual(fixture.boundRange(), 7..<7)
            XCTAssertFalse(fixture.manager.canRedo)
            XCTAssertEqual(fixture.context.session.mutationRevision, 9)
            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertEqual(fixture.context.session.savedCheckpoint, savedCheckpoint)
            XCTAssertEqual(try Data(contentsOf: fixture.url), receipt.bytes)
        }
    }

    func testNestedDirectAssignmentCannotClaimTheEditorsAcceptedReceipt() async throws {
        try withLayout {
            let fixture = try SessionEditorFixture(text: "abc")
            defer { fixture.cleanup() }
            let editor = try fixture.editor()
            fixture.key(0x41, modifiers: [.control])
            let refresh = fixture.context.session.onChange
            var performsNestedAssignment = true
            fixture.context.session.onChange = {
                if performsNestedAssignment {
                    performsNestedAssignment = false
                    let replacement = "XYZ"
                    fixture.recorder.selection = TextSelection(insertionPoint: replacement.startIndex)
                    fixture.recorder.configuration?.$document.text.wrappedValue = replacement
                }
                refresh?()
            }
            fixture.type("q")
            XCTAssertEqual(fixture.text, "XYZ")
            XCTAssertEqual(fixture.context.session.mutationRevision, 2)
            XCTAssertEqual(fixture.boundRange(), 0..<0)

            fixture.key(0x5A, modifiers: [.control])
            XCTAssertEqual(fixture.text, "q")
            XCTAssertEqual(fixture.boundRange(), 0..<0)
            fixture.key(0x5A, modifiers: [.control])
            XCTAssertEqual(fixture.text, "abc")
            XCTAssertEqual(fixture.boundRange(), 0..<3)
            XCTAssertFalse(fixture.manager.canUndo)
            XCTAssertTrue(try fixture.editor() === editor)
        }
    }

    func testRealSessionCompositionBlocksBothKeyboardAndDirectReplayUntilEnd() async throws {
        try withLayout {
            let fixture = try SessionEditorFixture()
            defer { fixture.cleanup() }
            fixture.compose(.started)
            fixture.compose(.updated("候補"))
            XCTAssertEqual(fixture.text, "A")
            XCTAssertFalse(fixture.manager.canUndo)
            fixture.compose(.committed("漢"))
            XCTAssertEqual(fixture.text, "A漢")
            XCTAssertEqual(fixture.context.session.mutationRevision, 1)
            fixture.key(0x5A, modifiers: [.control])
            fixture.manager.undo()
            XCTAssertEqual(fixture.text, "A漢")
            XCTAssertEqual(fixture.context.session.mutationRevision, 1)
            XCTAssertTrue(fixture.manager.canUndo)
            fixture.compose(.ended)
            fixture.key(0x5A, modifiers: [.control])
            XCTAssertEqual(fixture.text, "A")
            XCTAssertEqual(fixture.context.session.mutationRevision, 2)
            XCTAssertFalse(fixture.manager.canUndo)
            fixture.key(0x59, modifiers: [.control])
            XCTAssertEqual(fixture.text, "A漢")
            XCTAssertFalse(fixture.manager.canRedo)
        }
    }
}
