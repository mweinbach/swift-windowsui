import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class TemplateDocumentModel {
    var document: DemoPlainTextDocument
    var fileURL: URL?
    var documentWrites = 0
    var builds = 0

    init(text: String, fileURL: URL? = nil) {
        document = DemoPlainTextDocument(text: text)
        self.fileURL = fileURL
    }
}

@MainActor
private func templateDocumentNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private final class DocumentTemplateFixture {
    let model: TemplateDocumentModel
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let coordinator: StateMountCoordinator

    init(model: TemplateDocumentModel) {
        self.model = model
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 640, height: 480)))
        self.runtime = runtime
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let coordinator = StateMountCoordinator(
            invalidate: { [weak host] in host?.reload() },
            observeObject: { _ in },
            updateObservedObjects: { _, _, _ in })
        self.coordinator = coordinator
        host.buildLifecycle = coordinator
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator,
            canvasSizeProvider: { Size(width: 640, height: 480) },
            invalidateHandler: { [weak host] in host?.reload() })
        host.setComponents {
            model.builds += 1
            let document = Binding<DemoPlainTextDocument>(
                get: { model.document },
                set: {
                    model.document = $0
                    model.documentWrites += 1
                })
            // Recreate the public view for every build. Selection must belong
            // to its mounted State location, not a captured initializer seed.
            return [
                DemoDocumentEditor(document: document, fileURL: model.fileURL)
                    .makeComponent(context: context)
            ]
        }
        render()
    }

    func close() {
        runtime.requestFocus(nil)
        coordinator.close()
    }

    func render() {
        _ = runtime.renderScene()
        XCTAssertNil(coordinator.latestInstallationError)
    }

    func reload() {
        host.reload()
        render()
    }

    func editor() throws -> ViewNode {
        try XCTUnwrap(templateDocumentNodes(in: runtime.root).first { $0.accessibilityTraits.contains(.isTextInput) })
    }

    func focus() throws {
        runtime.requestFocus(try editor())
        render()
    }

    func key(_ key: KeyboardKey, modifiers: KeyboardModifiers = []) {
        runtime.keyDown(KeyboardEvent(keyCode: key.rawValue, modifiers: modifiers, textInputDelivery: .systemCharacter))
        render()
    }

    func type(_ text: String) {
        runtime.imeComposition(IMECompositionEvent(phase: .committed(text), source: .keyboard))
        render()
    }

    func filename() throws -> String {
        let container = try XCTUnwrap(
            templateDocumentNodes(in: runtime.root).first { $0.accessibilityIdentifier == "document.template.filename" }
        )
        return try XCTUnwrap(templateDocumentNodes(in: container).compactMap(\.text).first)
    }
}

/// Codec fixtures use real FileWrapper bytes. View fixtures exercise only the
/// shared editor and retained state ownership, without a native window or I/O.
@MainActor
final class DemoDocumentTemplateTests: XCTestCase {
    private func read(_ data: Data) throws -> DemoPlainTextDocument {
        try DemoPlainTextDocument(
            configuration: .init(file: FileWrapper(regularFileWithContents: data), contentType: .utf8PlainText))
    }

    private func encoded(_ document: DemoPlainTextDocument) throws -> Data {
        let wrapper = try document.fileWrapper(configuration: .init(contentType: .utf8PlainText))
        XCTAssertTrue(wrapper.isRegularFile)
        return try XCTUnwrap(wrapper.regularFileContents)
    }

    private func withSyntheticLayout(_ body: () throws -> Void) rethrows {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let glyphs = text.enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 9, y: 0), advance: 9,
                    glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                    fontSize: style.nativeFontPixelSize, sourceIndex: index)
            }
            let size = Size(width: Double(text.count) * 9, height: 20)
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
                lineSpacing: style.lineSpacing, contentSize: size, measuredSize: size)
        }
        defer { NativeTextRenderer.resetTestingOverrides() }
        try body()
    }

    func testNewDocumentIsEmptyAndDeclaresOnlyUTF8PlainText() async throws {
        let document = DemoPlainTextDocument()
        XCTAssertTrue(document.text.isEmpty)
        XCTAssertEqual(DemoPlainTextDocument.readableContentTypes, [.utf8PlainText])
        XCTAssertEqual(DemoPlainTextDocument.writableContentTypes, [.utf8PlainText])
        XCTAssertEqual(try encoded(document), Data())
        XCTAssertTrue(try read(Data()).text.isEmpty)
    }

    func testValidUTF8RoundTripsEverySourceByte() async throws {
        let fixtures: [(String, Data)] = [
            ("empty", Data()),
            ("ASCII", Data("plain text".utf8)),
            ("whitespace", Data(" \t\n\r\n\r\t  ".utf8)),
            ("BOM only", Data([0xEF, 0xBB, 0xBF])),
            ("BOM and mixed endings", Data("\u{FEFF}first\r\nsecond\nthird\rfourth".utf8)),
            ("decomposed text", Data("e\u{301} A\u{30A}\r\n".utf8)),
            ("Unicode and emoji", Data("Résumé 文書 👩🏽‍💻\n".utf8)),
            ("embedded NUL", Data("before\u{0000}after".utf8)),
            ("literal replacement character", Data([0xEF, 0xBF, 0xBD])),
            (
                "scalar boundaries",
                Data("\u{7F}\u{80}\u{7FF}\u{800}\u{D7FF}\u{E000}\u{FFFF}\u{10000}\u{10FFFF}".utf8)
            ),
        ]
        for (name, bytes) in fixtures {
            let document = try read(bytes)
            XCTAssertEqual(Data(document.text.utf8), bytes, name)
            XCTAssertEqual(try encoded(document), bytes, name)
        }
    }

    func testBOMDecompositionAndLineEndingsAreNotNormalized() async throws {
        let original = Data("\u{FEFF}e\u{301}\r\n \tA\u{30A}\r".utf8)
        let document = try read(original)
        XCTAssertEqual(document.text.unicodeScalars.first?.value, 0xFEFF)
        XCTAssertEqual(try encoded(document), original)
        XCTAssertNotEqual(try encoded(document), Data("\u{FEFF}é\r\n \tÅ\r".utf8))
        XCTAssertNotEqual(try encoded(document), Data("e\u{301}\n \tA\u{30A}\n".utf8))
    }

    func testMalformedUTF8IsRejectedInsteadOfBeingRepaired() async {
        let malformed: [(String, [UInt8])] = [
            ("isolated continuation", [0x80]),
            ("continuation after text", [0x61, 0xBF, 0x62]),
            ("overlong two-byte form", [0xC0, 0xAF]),
            ("overlong three-byte form", [0xE0, 0x80, 0xAF]),
            ("overlong four-byte form", [0xF0, 0x80, 0x80, 0xAF]),
            ("truncated two-byte form", [0xC2]),
            ("truncated three-byte form", [0xE2, 0x82]),
            ("truncated four-byte form", [0xF0, 0x9F, 0x92]),
            ("invalid continuation", [0xE2, 0x28, 0xA1]),
            ("surrogate", [0xED, 0xA0, 0x80]),
            ("above Unicode maximum", [0xF4, 0x90, 0x80, 0x80]),
            ("invalid leading byte", [0xF5, 0x80, 0x80, 0x80]),
            ("UTF-16 little endian BOM", [0xFF, 0xFE, 0x41, 0x00]),
            ("UTF-16 big endian BOM", [0xFE, 0xFF, 0x00, 0x41]),
        ]
        for (name, bytes) in malformed {
            XCTAssertThrowsError(try read(Data(bytes)), name) { error in
                XCTAssertEqual(error as? DemoPlainTextDocument.ReadError, .invalidUTF8, name)
            }
        }
    }

    func testMissingDirectoryAndHybridWrappersHaveAnExplicitReadError() async {
        let hybrid = FileWrapper(regularFileWithContents: Data("not a regular wrapper".utf8))
        hybrid.fileWrappers = [:]
        let wrappers = [
            FileWrapper(),
            FileWrapper(directoryWithFileWrappers: [:]),
            FileWrapper(directoryWithFileWrappers: ["child.txt": FileWrapper(regularFileWithContents: Data())]),
            hybrid,
        ]
        for wrapper in wrappers {
            XCTAssertFalse(wrapper.isRegularFile)
            XCTAssertThrowsError(
                try DemoPlainTextDocument(configuration: .init(file: wrapper, contentType: .utf8PlainText))
            ) { error in
                XCTAssertEqual(error as? DemoPlainTextDocument.ReadError, .expectedRegularFile)
            }
        }
    }

    func testEncodingCreatesAFreshRegularWrapperWithoutChangingTheExistingFile() async throws {
        let previousBytes = Data("previous contents".utf8)
        let existing = FileWrapper(regularFileWithContents: previousBytes)
        existing.filename = "previous.txt"
        let document = DemoPlainTextDocument(text: "\u{FEFF}e\u{301}\r\nnew contents\t")

        let result = try document.fileWrapper(configuration: .init(existingFile: existing, contentType: .utf8PlainText))

        XCTAssertFalse(result === existing)
        XCTAssertTrue(result.isRegularFile)
        XCTAssertEqual(result.regularFileContents, Data(document.text.utf8))
        XCTAssertNil(result.fileWrappers)
        XCTAssertEqual(existing.regularFileContents, previousBytes)
        XCTAssertEqual(existing.filename, "previous.txt")
    }

    func testDocumentCopiesKeepIndependentStringValues() async throws {
        let original = DemoPlainTextDocument(text: "e\u{301}\r\n")
        var copy = original
        copy.text += "changed"

        XCTAssertEqual(try encoded(original), Data("e\u{301}\r\n".utf8))
        XCTAssertEqual(try encoded(copy), Data("e\u{301}\r\nchanged".utf8))
        XCTAssertEqual(try encoded(read(encoded(copy))), Data(copy.text.utf8))
    }

    func testTemplateShowsFilenameAndOneRetainedEditorWithoutWritingTheDocument() async throws {
        try withSyntheticLayout {
            let model = TemplateDocumentModel(text: "draft")
            let fixture = DocumentTemplateFixture(model: model)
            defer { fixture.close() }
            let inputs = templateDocumentNodes(in: fixture.runtime.root).filter {
                $0.accessibilityTraits.contains(.isTextInput)
            }
            XCTAssertEqual(inputs.count, 1)
            let editor = try XCTUnwrap(inputs.first)
            XCTAssertEqual(editor.accessibilityIdentifier, "document.template.editor")
            XCTAssertEqual(editor.accessibilityLabel, "Document text")
            XCTAssertTrue(editor.isFocusable)
            XCTAssertTrue(templateDocumentNodes(in: fixture.runtime.root).contains { $0.text == "Plain text document" })
            XCTAssertEqual(try fixture.filename(), "Untitled")
            let viewport = try XCTUnwrap(editor.children.first { $0.scrollAxis == .vertical })
            XCTAssertTrue(viewport.clipsToBounds)
            let frame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: viewport))
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)

            model.fileURL = URL(fileURLWithPath: "C:/Documents/Notes — 文書.txt")
            fixture.reload()

            XCTAssertEqual(try fixture.filename(), "Notes — 文書.txt")
            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertEqual(model.documentWrites, 0)
            XCTAssertEqual(Data(model.document.text.utf8), Data("draft".utf8))
        }
    }

    func testEditingAGraphemeSelectionWritesTheParentDocumentValueExactlyOnce() async throws {
        try withSyntheticLayout {
            let model = TemplateDocumentModel(text: "A👩🏽‍💻e\u{301}Z")
            let fixture = DocumentTemplateFixture(model: model)
            defer { fixture.close() }
            try fixture.focus()
            fixture.key(.home, modifiers: [.control])
            fixture.key(.rightArrow)
            fixture.key(.rightArrow, modifiers: [.shift])
            fixture.key(.rightArrow, modifiers: [.shift])
            XCTAssertEqual(try fixture.editor().textInputSelection?.indices, .range(1..<3))
            XCTAssertEqual(model.documentWrites, 0)

            fixture.type("Q")

            XCTAssertEqual(Data(model.document.text.utf8), Data("AQZ".utf8))
            XCTAssertEqual(model.documentWrites, 1)
            XCTAssertEqual(try fixture.editor().textInputCaretOffset, 2)
            XCTAssertEqual(try encoded(model.document), Data("AQZ".utf8))
        }
    }

    func testSelectionAndFocusSurviveFreshViewBuildsWithoutDocumentWrites() async throws {
        try withSyntheticLayout {
            let model = TemplateDocumentModel(text: "ABCDE")
            let fixture = DocumentTemplateFixture(model: model)
            defer { fixture.close() }
            try fixture.focus()
            fixture.key(.home, modifiers: [.control])
            fixture.key(.rightArrow)
            fixture.key(.rightArrow, modifiers: [.shift])
            fixture.key(.rightArrow, modifiers: [.shift])
            let editor = try fixture.editor()
            let builds = model.builds
            XCTAssertEqual(editor.textInputSelection?.indices, .range(1..<3))

            model.fileURL = URL(fileURLWithPath: "C:/Documents/Renamed.txt")
            fixture.reload()

            XCTAssertGreaterThan(model.builds, builds)
            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
            XCTAssertEqual(editor.textInputCaretOffset, 3)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(1..<3))
            XCTAssertEqual(try fixture.filename(), "Renamed.txt")
            XCTAssertEqual(model.documentWrites, 0)
            XCTAssertEqual(Data(model.document.text.utf8), Data("ABCDE".utf8))
        }
    }

    func testSeparateEditorMountsKeepIndependentSelectionsForTheSameDocumentBinding() async throws {
        try withSyntheticLayout {
            let model = TemplateDocumentModel(text: "ABCDE")
            let first = DocumentTemplateFixture(model: model)
            let second = DocumentTemplateFixture(model: model)
            defer {
                second.close()
                first.close()
            }
            try first.focus()
            first.key(.home, modifiers: [.control])
            first.key(.rightArrow)
            first.key(.rightArrow, modifiers: [.shift])
            try second.focus()
            second.key(.home, modifiers: [.control])
            for _ in 0..<3 { second.key(.rightArrow, modifiers: [.shift]) }

            first.reload()
            second.reload()

            XCTAssertEqual(try first.editor().textInputSelection?.indices, .range(1..<2))
            XCTAssertEqual(try first.editor().textInputCaretOffset, 2)
            XCTAssertEqual(try second.editor().textInputSelection?.indices, .range(0..<3))
            XCTAssertEqual(try second.editor().textInputCaretOffset, 3)
            XCTAssertEqual(model.documentWrites, 0)
            XCTAssertEqual(Data(model.document.text.utf8), Data("ABCDE".utf8))
        }
    }

    func testSharedSceneDeclaresOneDocumentConfigurationWithoutOpeningAWindow() async throws {
        let configurations = DemoDocumentScene().makeWindowConfigurations()
        XCTAssertEqual(configurations.count, 1)
        XCTAssertTrue(try XCTUnwrap(configurations.first).isDocumentGroup)
    }
}
