import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private enum DragSelectionHarness {
    /// Fixed per-character advance used by the synthetic native layout.
    static let advance: Double = 9

    static func installSyntheticNativeLayout() {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let characters = Array(text)
            let glyphs = characters.enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character,
                    origin: Point(x: Double(index) * advance, y: 0),
                    advance: advance,
                    glyphID: UInt32(character.unicodeScalars.first?.value ?? UInt32(index + 1)),
                    fontFamily: style.fontFamily,
                    weight: style.weight,
                    fontSize: style.nativeFontPixelSize,
                    sourceIndex: index
                )
            }
            let width = Double(max(characters.count, 1)) * advance
            let height = max(style.nativeFontPixelSize, 1)
            return NativeTextLayoutResult(
                lines: [
                    NativeTextLineLayout(
                        text: text,
                        width: width,
                        height: height,
                        glyphs: glyphs
                    )
                ],
                contentSize: Size(width: width, height: height),
                measuredSize: Size(width: width, height: height)
            )
        }
    }

    static func reset() {
        NativeTextRenderer.resetTestingOverrides()
    }

    static func makeNode(
        text: Binding<String>,
        kind: Kind = .field
    ) -> (runtime: RetainedViewRuntime, node: ViewNode, label: ViewNode) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 800, height: 600) },
            invalidateHandler: {}
        )
        let node: ViewNode
        switch kind {
        case .field:
            node = TextField("VALUE", text: text).makeComponent(context: context).makeNode(runtime: runtime)
        case .secure:
            node = SecureField("VALUE", text: text).makeComponent(context: context).makeNode(runtime: runtime)
        case .editor:
            node = TextEditor(text: text).makeComponent(context: context).makeNode(runtime: runtime)
        }

        guard let label = node.children.first else {
            fatalError("text input should start with its content label child")
        }
        // Stand in for a layout pass: the label sits at the node's content
        // origin, so a root-space point maps to text-space by translation.
        node.frame = Rect(x: 10, y: 20, width: 200, height: 30)
        label.frame = Rect(x: 4, y: 4, width: 192, height: 22)
        // Component.makeNode leaves ownership of its runtime with the
        // caller. The editor deliberately captures that runtime weakly.
        return (runtime, node, label)
    }

    enum Kind {
        case field
        case secure
        case editor
    }

    /// Root-space point whose text-space coordinates are (x, y): the node
    /// sits at (10, 20) and its label at (4, 4) within it.
    static func rootPoint(textX: Double, textY: Double = 0) -> Point {
        Point(x: 14 + textX, y: 24 + textY)
    }

    /// X of the caret boundary at `offset` under the synthetic layout.
    static func x(atOffset offset: Int) -> Double {
        Double(offset) * advance
    }
}

final class TextInputDragSelectionTests: XCTestCase {
    func testPointerDownPlacesCaretAtHitOffsetAndFocuses() async {
        await MainActor.run {
            DragSelectionHarness.installSyntheticNativeLayout()
            defer { DragSelectionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = DragSelectionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )
            defer { withExtendedLifetime(runtime) {} }

            XCTAssertFalse(node.isFocused)

            // Just past the boundary at offset 2.
            node.onDragStart?(DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 2) + 1))

            XCTAssertTrue(node.isFocused)
            XCTAssertEqual(node.textInputCaretOffset, 2)
            XCTAssertNil(node.textInputSelection)
        }
    }

    func testDragSelectsForwardFromDownAnchor() async {
        await MainActor.run {
            DragSelectionHarness.installSyntheticNativeLayout()
            defer { DragSelectionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = DragSelectionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )
            defer { withExtendedLifetime(runtime) {} }

            node.onDragStart?(DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 1)))
            node.onDragChange?(
                DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 3) + 1),
                Point(x: 20, y: 0)
            )

            XCTAssertEqual(node.textInputCaretOffset, 3)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(1..<3), affinity: .downstream)
            )
        }
    }

    func testDragSelectsBackwardAndKeepsAnchorAcrossCollapse() async {
        await MainActor.run {
            DragSelectionHarness.installSyntheticNativeLayout()
            defer { DragSelectionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = DragSelectionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )
            defer { withExtendedLifetime(runtime) {} }

            node.onDragStart?(DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 2)))
            node.onDragChange?(
                DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 4)),
                Point(x: 18, y: 0)
            )
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(2..<4), affinity: .downstream)
            )

            // Collapsing back onto the anchor clears the selection...
            node.onDragChange?(
                DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 2)),
                Point(x: 0, y: 0)
            )
            XCTAssertEqual(node.textInputCaretOffset, 2)
            XCTAssertNil(node.textInputSelection)

            // ...but the down anchor stays sticky when the drag continues.
            node.onDragChange?(
                DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 0)),
                Point(x: -18, y: 0)
            )
            XCTAssertEqual(node.textInputCaretOffset, 0)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(0..<2), affinity: .upstream)
            )
        }
    }

    func testDragPastLineEndClampsToText() async {
        await MainActor.run {
            DragSelectionHarness.installSyntheticNativeLayout()
            defer { DragSelectionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = DragSelectionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )
            defer { withExtendedLifetime(runtime) {} }

            node.onDragStart?(DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 1)))
            node.onDragChange?(DragSelectionHarness.rootPoint(textX: 1000), Point(x: 990, y: 0))

            XCTAssertEqual(node.textInputCaretOffset, 5)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(1..<5), affinity: .downstream)
            )
        }
    }

    func testSecureFieldDragMapsMaskedTextToRealCharacterOffsets() async {
        await MainActor.run {
            DragSelectionHarness.installSyntheticNativeLayout()
            defer { DragSelectionHarness.reset() }

            var value = "secret"
            let (runtime, node, _) = DragSelectionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 }),
                kind: .secure
            )
            defer { withExtendedLifetime(runtime) {} }

            node.onDragStart?(DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 1)))
            node.onDragChange?(
                DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 4)),
                Point(x: 27, y: 0)
            )

            XCTAssertEqual(value, "secret")
            XCTAssertEqual(node.textInputCaretOffset, 4)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(1..<4), affinity: .downstream)
            )
        }
    }

    func testSingleLineFieldClampsPointerYToFirstLine() async {
        await MainActor.run {
            DragSelectionHarness.installSyntheticNativeLayout()
            defer { DragSelectionHarness.reset() }

            var value = "hello"
            let (runtime, node, _) = DragSelectionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 })
            )
            defer { withExtendedLifetime(runtime) {} }

            // A click far below the field still resolves to the single line.
            node.onDragStart?(
                DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 3), textY: 500)
            )

            XCTAssertEqual(node.textInputCaretOffset, 3)
        }
    }

    func testTextEditorMapsPointerYToHardLineRows() async {
        await MainActor.run {
            DragSelectionHarness.installSyntheticNativeLayout()
            defer { DragSelectionHarness.reset() }

            var value = "ab\ncd"
            let (runtime, node, label) = DragSelectionHarness.makeNode(
                text: Binding(get: { value }, set: { value = $0 }),
                kind: .editor
            )
            defer { withExtendedLifetime(runtime) {} }

            let lineHeight = RetainedTextMetrics.size(of: "ab", style: label.textStyle).height

            // First row, second caret boundary.
            node.onDragStart?(DragSelectionHarness.rootPoint(textX: DragSelectionHarness.x(atOffset: 1)))
            XCTAssertEqual(node.textInputCaretOffset, 1)

            // Second row (line range 3..<5), one character in.
            node.onDragChange?(
                DragSelectionHarness.rootPoint(
                    textX: DragSelectionHarness.x(atOffset: 1),
                    textY: lineHeight * 1.5
                ),
                Point(x: 0, y: lineHeight * 1.5)
            )

            XCTAssertEqual(node.textInputCaretOffset, 4)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(1..<4), affinity: .downstream)
            )

            // Below the last row clamps to the final line.
            node.onDragChange?(
                DragSelectionHarness.rootPoint(textX: 1000, textY: 1000),
                Point(x: 1000, y: 1000)
            )
            XCTAssertEqual(node.textInputCaretOffset, 5)
        }
    }

    func testMetricsFacadeFallsBackToPixelAdvancesWithoutNativeLayout() async {
        await MainActor.run {
            NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
            NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in nil }
            defer { DragSelectionHarness.reset() }

            let style = PixelTextStyle(color: .white, scale: 2, letterSpacing: 1)
            let expectedAdvance =
                (Double(PixelFont.glyphWidth) * 2 + 1 * 2)  // per-character step between boundaries

            // Caret boundaries follow the fixed pixel advance: prefix width of
            // "ab" in "abc" is 2 glyphs + 1 letter-space, scaled.
            let prefixWidth = (2 * Double(PixelFont.glyphWidth) + 1) * 2
            XCTAssertEqual(
                RetainedTextMetrics.caretX(atOffset: 2, in: "abc", style: style),
                prefixWidth,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                RetainedTextMetrics.caretX(atOffset: 3, in: "abc", style: style),
                prefixWidth + expectedAdvance,
                accuracy: 0.0001
            )

            // Hit testing snaps to the nearest boundary and clamps.
            XCTAssertEqual(
                RetainedTextMetrics.characterOffset(atX: prefixWidth + 1, in: "abc", style: style),
                2
            )
            XCTAssertEqual(RetainedTextMetrics.characterOffset(atX: -50, in: "abc", style: style), 0)
            XCTAssertEqual(RetainedTextMetrics.characterOffset(atX: 10000, in: "abc", style: style), 3)
            XCTAssertEqual(RetainedTextMetrics.characterOffset(atX: 10, in: "", style: style), 0)
        }
    }
}
