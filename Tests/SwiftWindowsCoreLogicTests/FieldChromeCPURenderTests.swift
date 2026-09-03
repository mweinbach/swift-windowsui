import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum FieldChromeCPUPath: CaseIterable {
    case direct
    case nested
}

@MainActor
private final class FieldChromeCPUState {
    var text = "old"
    var selection: TextSelection?
    var version = 0
    var fontSize = 12.0
    var family = "Field Chrome CPU Original"
    var foreground = Color(red: 0, green: 0, blue: 1)
    var reads: [Int] = []
    var writes: [String] = []
    var selectionWrites = 0
    var layouts = 0
    var afterWrite: (@MainActor () -> Void)?
}

@MainActor
private func fieldChromeCPUNodes(_ root: ViewNode) -> [ViewNode] {
    var nodes: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        nodes.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return nodes
}

@MainActor
private func fieldChromeCPUVisible(_ node: ViewNode, within root: ViewNode) -> Bool {
    var candidate: ViewNode? = node
    while let current = candidate {
        if current.isHidden { return false }
        if current === root { return true }
        candidate = current.parent
    }
    return false
}

@MainActor
private final class FieldChromeCPULifetime {
    weak var runtime: RetainedViewRuntime?
    weak var field: ViewNode?
    weak var incoming: ViewNode?
    weak var chrome: ViewNode?
}

/// The fixture owns its runtime, mounted nodes, source, and incoming source for
/// the complete edit/render operation. The binding callback captures it weakly.
/// There is no native window, fake input controller, or synthetic chrome tree.
@MainActor
private final class FieldChromeCPUFixture {
    let state: FieldChromeCPUState
    let runtime: RetainedViewRuntime
    let context: ViewBuildContext
    let container: ViewNode
    let row: ViewNode
    let field: ViewNode
    let path: FieldChromeCPUPath
    lazy var source = RuntimeUIAElementTreeSource(runtime: runtime)
    var incoming: ViewNode?
    var result: RetainedLazyListAdoptionResult?
    var layoutPassAtWrite: UInt64?
    var adoptionReads: [Int] = []
    var adoptionLayouts = 0

    init(path: FieldChromeCPUPath) {
        let state = FieldChromeCPUState()
        let runtime = RetainedViewRuntime(
            clearColor: .black,
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 80), isHitTestVisible: false))
        runtime.clock = { 0 }
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 160, height: 80) }, invalidateHandler: {})
        XCTAssertNil(context.environmentValues.undoManager)
        let field = Self.makeField(state: state, context: context, runtime: runtime)
        let row = Self.makeRow(field: field, path: path)
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 80))
        container.addChild(row)
        runtime.root.addChild(container)
        self.state = state
        self.runtime = runtime
        self.context = context
        self.container = container
        self.row = row
        self.field = field
        self.path = path
        runtime.requestFocus(field)
        _ = runtime.renderScene(at: 0)
    }

    private static func makeField(
        state: FieldChromeCPUState, context: ViewBuildContext, runtime: RetainedViewRuntime
    ) -> ViewNode {
        let version = state.version
        let text = Binding<String>(
            get: {
                state.reads.append(version)
                return state.text
            },
            set: {
                state.writes.append($0)
                state.text = $0
                state.afterWrite?()
            })
        let selection = Binding<TextSelection?>(
            get: { state.selection },
            set: {
                state.selectionWrites += 1
                state.selection = $0
            })
        let field = TextField("CPU field", text: text, selection: selection)
            .textFieldStyle(PlainTextFieldStyle())
            .font(.custom(state.family, size: state.fontSize).weight(.semibold))
            .foregroundColor(state.foreground)
            .tint(Color(red: 0, green: 1, blue: 0))
            .makeComponent(context: context).makeNode(runtime: runtime)
        field.accessibilityIdentifier = "field-chrome-cpu"
        field.nodeTag = "field-chrome-cpu"
        field.frame = Rect(x: 12, y: 12, width: 120, height: 40)
        field.preferredSize = Size(width: 120, height: 40)
        let nativeLayout = field.onLayout
        field.onLayout = { bounds in
            state.layouts += 1
            nativeLayout?(bounds)
        }
        return field
    }

    private static func makeRow(field: ViewNode, path: FieldChromeCPUPath) -> ViewNode {
        if path == .direct { return field }
        return ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 80), children: [field])
    }

    func edit(_ value: String, selectionRange: Range<Int>?) throws {
        let originalController = try XCTUnwrap(field.textInputController)
        let id = try XCTUnwrap(
            source.uiaElementSnapshots().first { $0.automationID == "field-chrome-cpu" }
        ).id
        state.afterWrite = { [weak self] in
            guard let self else { return }
            self.layoutPassAtWrite = self.runtime.layoutPassID
            self.state.version += 1
            self.state.fontSize = 20
            self.state.family = "Field Chrome CPU Incoming"
            self.state.foreground = Color(red: 1, green: 0, blue: 0)
            if let selectionRange {
                let lower = value.index(value.startIndex, offsetBy: selectionRange.lowerBound)
                let upper = value.index(value.startIndex, offsetBy: selectionRange.upperBound)
                self.state.selection = TextSelection(range: lower..<upper)
            }
            let incomingField = Self.makeField(state: self.state, context: self.context, runtime: self.runtime)
            let incoming = Self.makeRow(field: incomingField, path: self.path)
            self.incoming = incoming
            XCTAssertNil(incoming.parent)
            XCTAssertEqual(incomingField.children.count, 1)
            XCTAssertEqual(incomingField.children.first?.isHidden, false)
            let reads = self.state.reads.count
            let layouts = self.state.layouts
            if self.path == .direct {
                self.result = ComponentHost.adopt(source: incoming, into: self.row)
            } else {
                self.result = ComponentHost.reconcileChildren(
                    of: self.container, oldChildren: self.container.children, newNodes: [incoming])
            }
            self.adoptionReads = Array(self.state.reads.dropFirst(reads))
            self.adoptionLayouts = self.state.layouts - layouts
        }
        defer { state.afterWrite = nil }
        XCTAssertTrue(source.uiaSetValue(elementID: id, value: value))
        XCTAssertTrue(try XCTUnwrap(result).completed)
        XCTAssertNil(result?.completion, "This small fixture uses ordinary, unchecked adoption")
        XCTAssertFalse(field.textInputController === originalController)
        XCTAssertTrue(runtime.focusedNode === field)
        XCTAssertTrue(field.isFocused)
        XCTAssertTrue(fieldChromeCPUNodes(runtime.root).contains { $0 === field })
        XCTAssertEqual(state.writes, [value])
        XCTAssertEqual(state.selectionWrites, 0)
        XCTAssertEqual(adoptionReads, [])
        XCTAssertEqual(adoptionLayouts, 0)
        XCTAssertEqual(runtime.layoutPassID, try XCTUnwrap(layoutPassAtWrite))
    }

    func close() {
        state.afterWrite = nil
        runtime.requestFocus(nil)
        runtime.root.removeChild(container)
        incoming = nil
        result = nil
    }
}

/// CPU scene/raster integration only. Synthetic character metrics and tiny
/// opaque glyph masks deliberately exclude native-font shaping/ink fidelity.
/// The public field, controller transfer, accepted chrome, layout, scene
/// lowering, glyph atlas, compositing, and CPU rasterizer remain production.
@MainActor
final class FieldChromeCPURenderTests: XCTestCase {
    private let value = "A👩‍👩‍👧‍👧e\u{301}Z"

    private func withFixture(
        path: FieldChromeCPUPath, _ body: (FieldChromeCPUFixture, FieldChromeCPULifetime) throws -> Void
    ) throws -> FieldChromeCPULifetime {
        NativeGlyphAtlas.installForTesting(NativeGlyphAtlas(atlasWidth: 256, atlasHeight: 256))
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let glyphs = Array(text).enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 10, y: 0), advance: 10,
                    glyphID: character.unicodeScalars.first?.value ?? 0,
                    fontFamily: style.fontFamily, weight: style.weight,
                    fontSize: style.nativeFontPixelSize, sourceIndex: index)
            }
            let size = Size(width: Double(text.count) * 10, height: style.nativeFontPixelSize)
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
                contentSize: size, measuredSize: size)
        }
        NativeTextRenderer.testingOverrides.rasterizeGlyphForLayout = { glyph, _, _ in
            let width: Int32
            switch glyph.character {
            case "A": width = 2
            case "👩‍👩‍👧‍👧": width = 3
            case "e\u{301}": width = 4
            case "Z": width = 5
            default: width = 6
            }
            return NativeGlyphBitmap(
                surface: BitmapSurface(
                    width: width, height: 3, bytesPerRow: width * 4,
                    pixels: Data(repeating: 255, count: Int(width) * 3 * 4)),
                bearingX: 1, bearingY: 2, advance: 10)
        }
        defer {
            NativeTextRenderer.resetTestingOverrides()
            NativeGlyphAtlas.restoreSharedForTesting()
        }
        let fixture = FieldChromeCPUFixture(path: path)
        defer { fixture.close() }
        let lifetime = FieldChromeCPULifetime()
        lifetime.runtime = fixture.runtime
        lifetime.field = fixture.field
        try body(fixture, lifetime)
        return lifetime
    }

    private func assertReleased(_ lifetime: FieldChromeCPULifetime) {
        XCTAssertNil(lifetime.runtime)
        XCTAssertNil(lifetime.field)
        XCTAssertNil(lifetime.incoming)
        XCTAssertNil(lifetime.chrome)
    }

    private func assertPreparedChrome(
        _ fixture: FieldChromeCPUFixture, selected: Bool
    ) throws -> ViewNode {
        let field = fixture.field
        XCTAssertEqual(field.children.count, 2)
        XCTAssertTrue(try XCTUnwrap(field.children.first).isHidden)
        let chrome = try XCTUnwrap(field.children.last)
        XCTAssertFalse(chrome.isHidden)
        XCTAssertTrue(chrome.parent === field)
        let visible = fieldChromeCPUNodes(chrome).filter { fieldChromeCPUVisible($0, within: field) }
        let labels = visible.filter { $0.text != nil }
        // These strings are authored expectations, not derived from the actual
        // child tree or from TextInputEditingChromePresentation.
        let expected = selected ? ["A", "👩‍👩‍👧‍👧e\u{301}", "Z"] : [value]
        XCTAssertEqual(labels.compactMap(\.text), expected)
        XCTAssertEqual(labels.compactMap(\.text).joined().utf8.map { $0 }, value.utf8.map { $0 })
        for label in labels {
            XCTAssertEqual(label.textStyle.nativeFontPixelSize, 20)
            XCTAssertEqual(label.textStyle.fontFamily, "Field Chrome CPU Incoming")
            XCTAssertEqual(label.textStyle.weight, .semibold)
            XCTAssertEqual(label.textStyle.color, Color(red: 1, green: 0, blue: 0))
        }
        let carets = visible.filter(\.isTextInputCaret)
        if selected {
            XCTAssertEqual(field.textInputSelection?.indices, .range(1..<3))
            XCTAssertEqual(field.textInputCaretOffset, 3)
            XCTAssertTrue(carets.isEmpty)
            XCTAssertEqual(labels.filter { $0.backgroundColor != nil }.count, 1)
            let selectedLabel = try XCTUnwrap(labels.dropFirst().first)
            XCTAssertEqual(selectedLabel.backgroundColor, Color(red: 0, green: 1, blue: 0, alpha: 0.35))
        } else {
            XCTAssertNil(field.textInputSelection)
            XCTAssertEqual(field.textInputCaretOffset, 4)
            XCTAssertEqual(carets.count, 1)
            let caret = try XCTUnwrap(carets.first)
            XCTAssertEqual(caret.preferredSize, Size(width: 1.5, height: 20))
            XCTAssertEqual(caret.backgroundColor, Color(red: 1, green: 0, blue: 0))
            XCTAssertTrue(labels.allSatisfy { $0.backgroundColor == nil })
        }
        return chrome
    }

    private func renderAndAssertIdentity(
        _ fixture: FieldChromeCPUFixture, chrome: ViewNode, selected: Bool
    ) throws -> BitmapSurface {
        let identities = fieldChromeCPUNodes(chrome).map(ObjectIdentifier.init)
        _ = fixture.runtime.tickAnimations(at: 0)
        let scene = fixture.runtime.renderScene(at: 0)
        XCTAssertTrue(fixture.field.children.last === chrome, "Layout must not repair adoption by replacing the chrome")
        XCTAssertEqual(fieldChromeCPUNodes(chrome).map(ObjectIdentifier.init), identities)
        XCTAssertFalse(chrome.isHidden)
        XCTAssertTrue(try XCTUnwrap(fixture.field.children.first).isHidden)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.field)
        XCTAssertEqual(
            try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: fixture.field)),
            Rect(x: 12, y: 12, width: 120, height: 40))
        let placed = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: chrome))
        // Public plain-field padding is 7pt vertically. Four synthetic
        // graphemes each advance 10pt, independent of their UTF-16 length.
        XCTAssertEqual(placed.origin, Point(x: 12, y: 19))
        XCTAssertEqual(placed.height, 20, accuracy: 0.001)
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertNotNil(scene.glyphAtlas)
        let glyphs = scene.layers.flatMap(\.glyphs)
        XCTAssertEqual(glyphs.count, 4, "The hidden original label must contribute no duplicate glyphs")
        XCTAssertEqual(glyphs.map(\.screenX), [13, 23, 33, 43])
        XCTAssertEqual(glyphs.map(\.screenY), [21, 21, 21, 21])
        XCTAssertEqual(glyphs.map(\.screenW), [2, 3, 4, 5])
        XCTAssertEqual(glyphs.map(\.screenH), [3, 3, 3, 3])
        let fillNode = try XCTUnwrap(
            fieldChromeCPUNodes(chrome).first {
                selected ? $0.text == "👩‍👩‍👧‍👧e\u{301}" : $0.isTextInputCaret
            })
        let fillFrame =
            selected ? Rect(x: 22, y: 19, width: 20, height: 20) : Rect(x: 52, y: 19, width: 1.5, height: 20)
        XCTAssertEqual(try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: fillNode)), fillFrame)
        let fills = scene.layers.flatMap(\.quads).filter {
            $0.x == Float(fillFrame.minX) && $0.y == Float(fillFrame.minY)
                && $0.width == Float(fillFrame.width) && $0.height == Float(fillFrame.height)
        }
        XCTAssertEqual(fills.count, 1, "The exact caret/selection geometry must reach the scene")
        return GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 160, height: 80))
    }

    private func assertPixels(_ bitmap: BitmapSurface, selected: Bool, caretOn: Bool = true) throws {
        // Independent fixed oracle for the 60x20 content region. Black is the
        // opaque canvas, selection is green at alpha .35, and known synthetic
        // glyph masks and the fully covered caret column are opaque red.
        // The fractional caret edge column x=41 and horizontal edge rows
        // y=0/19 are excluded. The finite-derivative coverage kernel can
        // partially cover corners even at otherwise integral geometry;
        // exact node/scene extents are asserted separately, not its AA.
        let inkColumns = [1..<3, 11..<14, 21..<25, 31..<36]
        for y in 1..<19 {
            for x in 0..<60 {
                if !selected && x == 41 { continue }
                let glyph = (2..<5).contains(y) && inkColumns.contains { $0.contains(x) }
                let caret = !selected && caretOn && x == 40
                let expected: Color
                if glyph || caret {
                    expected = Color(red: 1, green: 0, blue: 0)
                } else if selected && (10..<30).contains(x) {
                    expected = Color(red: 0, green: 0.35, blue: 0)
                } else {
                    expected = .black
                }
                let actual = try XCTUnwrap(bitmap.colorAt(x: x + 12, y: y + 19))
                let at = "content pixel (\(x), \(y)), selected=\(selected), caretOn=\(caretOn)"
                XCTAssertEqual(actual.red, expected.red, accuracy: 1 / 255, at)
                XCTAssertEqual(actual.green, expected.green, accuracy: 1 / 255, at)
                XCTAssertEqual(actual.blue, expected.blue, accuracy: 1 / 255, at)
                XCTAssertEqual(actual.alpha, 1, accuracy: 1 / 255, at)
            }
        }
    }

    func testAcceptedUnicodeCaretAndIncomingStyleReachTheCPURasterWithoutChromeRepair() async throws {
        XCTAssertEqual(value.count, 4)
        for path in FieldChromeCPUPath.allCases {
            let lifetime = try withFixture(path: path) { fixture, lifetime in
                try fixture.edit(value, selectionRange: nil)
                let chrome = try assertPreparedChrome(fixture, selected: false)
                lifetime.incoming = fixture.incoming
                lifetime.chrome = chrome
                let bitmap = try renderAndAssertIdentity(fixture, chrome: chrome, selected: false)
                try assertPixels(bitmap, selected: false)
                let identities = fieldChromeCPUNodes(chrome).map(ObjectIdentifier.init)
                _ = fixture.runtime.tickAnimations(at: 0.7)
                let off = GPUIRawSceneRasterizer.rasterize(
                    fixture.runtime.renderScene(at: 0.7), size: IntSize(width: 160, height: 80))
                XCTAssertTrue(fixture.field.children.last === chrome)
                XCTAssertTrue(chrome.parent === fixture.field)
                XCTAssertEqual(fieldChromeCPUNodes(chrome).map(ObjectIdentifier.init), identities)
                try assertPixels(off, selected: false, caretOn: false)
                XCTAssertEqual(fixture.state.writes, [value])
                XCTAssertEqual(fixture.state.selectionWrites, 0)
            }
            assertReleased(lifetime)
        }
    }

    func testAcceptedUnicodeSelectionAndIncomingStyleReachTheCPURasterWithoutChromeRepair() async throws {
        XCTAssertEqual(value.count, 4)
        for path in FieldChromeCPUPath.allCases {
            let lifetime = try withFixture(path: path) { fixture, lifetime in
                try fixture.edit(value, selectionRange: 1..<3)
                let chrome = try assertPreparedChrome(fixture, selected: true)
                lifetime.incoming = fixture.incoming
                lifetime.chrome = chrome
                let bitmap = try renderAndAssertIdentity(fixture, chrome: chrome, selected: true)
                try assertPixels(bitmap, selected: true)
                XCTAssertEqual(fixture.state.writes, [value])
                XCTAssertEqual(fixture.state.selectionWrites, 0)
            }
            assertReleased(lifetime)
        }
    }
}
