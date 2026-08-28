import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum NavigationInputKind: Equatable {
    case editor
    case field
    case secure
}

@MainActor
private final class NavigationDocument {
    var text: String
    var selection: TextSelection?
    var textWrites: [String] = []
    var selectionWrites = 0
    var beforeTextRead: (() -> Void)?

    init(text: String, insertion: Int) {
        self.text = text
        selection = navigationInsertion(insertion, in: text)
    }
}

@MainActor
private final class NavigationState {
    var document: NavigationDocument
    let kind: NavigationInputKind
    let undoManager = WinSwiftUI.UndoManager()
    let nestedOuterScroll: Bool
    var width = 300.0
    var height: Double
    var fontSize = 16.0
    var lineSpacing = 0.0
    var revision = 0
    var showsInput = true
    var isDisabled = false
    var automaticallyReloads = true
    var otherActivations = 0

    init(text: String, insertion: Int, height: Double, nestedOuterScroll: Bool, kind: NavigationInputKind) {
        document = NavigationDocument(text: text, insertion: insertion)
        self.height = height
        self.nestedOuterScroll = nestedOuterScroll
        self.kind = kind
    }
}

@MainActor
private func navigationInsertion(
    _ offset: Int, in text: String, affinity: TextSelectionAffinity = .downstream
) -> TextSelection {
    var selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: offset))
    selection.affinity = affinity
    return selection
}

@MainActor
private func navigationSelection(
    _ range: Range<Int>, in text: String, affinity: TextSelectionAffinity = .downstream
) -> TextSelection {
    let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: range.upperBound)
    var selection = TextSelection(range: lower..<upper)
    selection.affinity = affinity
    return selection
}

@MainActor
private func navigationNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private struct NavigationRoot: View {
    let state: NavigationState

    var body: some View {
        // Each build captures its document. A stale controller cannot appear
        // correct by reading whichever document the fixture now presents.
        let document = state.document
        let text = Binding<String>(
            get: {
                document.beforeTextRead?()
                return document.text
            },
            set: {
                document.textWrites.append($0)
                document.text = $0
            }
        )
        let selection = Binding<TextSelection?>(
            get: { document.selection },
            set: {
                document.selectionWrites += 1
                document.selection = $0
            }
        )
        let input: AnyView
        switch state.kind {
        case .editor:
            input = AnyView(TextEditor(text: text, selection: selection))
        case .field:
            input = AnyView(TextField("Value", text: text, selection: selection))
        case .secure:
            input = AnyView(SecureField("Password", text: text))
        }
        let content = VStack(alignment: .leading, spacing: 0) {
            if state.showsInput {
                input
                    .font(.system(size: state.fontSize))
                    .lineSpacing(state.lineSpacing)
                    .disabled(state.isDisabled)
                    .environment(\.undoManager, Optional(state.undoManager))
                    .id("navigation-input")
                    .frame(width: state.width, height: state.height)
            }
            Button("Other") { state.otherActivations += 1 }
                .frame(width: 80, height: 24)
            Text("Revision \(state.revision)")
                .frame(width: 120, height: 20)
            if state.nestedOuterScroll {
                WinSwiftUI.Color.clear.frame(width: 100, height: 500)
            }
        }
        if state.nestedOuterScroll {
            return AnyView(
                ScrollView(.vertical, showsIndicators: false) { content }
                    .frame(width: state.width + 40, height: 180)
            )
        }
        return AnyView(content)
    }
}

@MainActor
private final class NavigationFixture {
    let state: NavigationState
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let initialInput: ViewNode

    init(
        text: String, insertion: Int, height: Double = 100, nestedOuterScroll: Bool = false,
        kind: NavigationInputKind = .editor
    ) throws {
        let state = NavigationState(
            text: text, insertion: insertion, height: height, nestedOuterScroll: nestedOuterScroll, kind: kind)
        self.state = state
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 31, y: 47, width: 700, height: 480)))
        self.runtime = runtime
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 700, height: 480) },
            invalidateHandler: { [weak host, weak state] in
                guard state?.automaticallyReloads == true else { return }
                host?.reload()
            }
        )
        host.setComponents { [NavigationRoot(state: state).makeComponent(context: context)] }
        initialInput = try XCTUnwrap(
            navigationNodes(in: runtime.root).first { $0.accessibilityTraits.contains(.isTextInput) })
        runtime.requestFocus(initialInput)
        render()
    }

    var document: NavigationDocument { state.document }

    func currentInput() -> ViewNode? {
        navigationNodes(in: runtime.root).first { $0.accessibilityTraits.contains(.isTextInput) }
    }

    func input() throws -> ViewNode { try XCTUnwrap(currentInput()) }

    func viewport() throws -> ViewNode {
        let input = try input()
        return try XCTUnwrap(input.children.first { $0.scrollAxis == .vertical })
    }

    func content() throws -> ViewNode { try XCTUnwrap(try viewport().children.first) }

    func outerScroll() throws -> ViewNode {
        let viewport = try viewport()
        return try XCTUnwrap(navigationNodes(in: runtime.root).first { $0.scrollAxis == .vertical && $0 !== viewport })
    }

    func frameWrapper() throws -> ViewNode {
        var ancestor = try input().parent
        while let candidate = ancestor {
            if candidate.preferredSize == Size(width: state.width, height: state.height),
                candidate.forwardsStackMainAxisProposal
            {
                return candidate
            }
            ancestor = candidate.parent
        }
        return try XCTUnwrap(Optional<ViewNode>.none, "The public frame wrapper must be retained")
    }

    func otherButton() throws -> ViewNode {
        try XCTUnwrap(
            navigationNodes(in: runtime.root).first {
                $0.isFocusable && !$0.accessibilityTraits.contains(.isTextInput) && $0.onActivate != nil
            })
    }

    func render() { _ = runtime.renderScene() }

    func reload() {
        state.revision += 1
        host.reload()
        render()
    }

    func key(_ key: KeyboardKey, modifiers: KeyboardModifiers = [], renderAfter: Bool = true) {
        runtime.keyDown(KeyboardEvent(keyCode: key.rawValue, modifiers: modifiers, textInputDelivery: .systemCharacter))
        if renderAfter { render() }
    }

    func type(_ text: String) {
        runtime.imeComposition(IMECompositionEvent(phase: .committed(text), source: .keyboard))
        render()
    }

    func compose(_ phase: IMECompositionEvent.Phase) {
        runtime.imeComposition(IMECompositionEvent(phase: phase))
        render()
    }

    func setInsertion(_ offset: Int, affinity: TextSelectionAffinity = .downstream) {
        document.selection = navigationInsertion(offset, in: document.text, affinity: affinity)
        reload()
    }

    func setWrapWidth(_ width: Double) throws {
        let viewport = try viewport()
        let placed = try XCTUnwrap(runtime.resolvedLayoutFrame(of: viewport))
        // Derive the current bezel/padding from actual placement. The extra
        // 1.5 points belong to the editor's insertion-indicator reservation.
        state.width += width + 1.5 - placed.width
        reload()
        let resized = try XCTUnwrap(runtime.resolvedLayoutFrame(of: try self.viewport()))
        XCTAssertEqual(resized.width - 1.5, width, accuracy: 0.001)
    }

    func layout(displayText: String? = nil) throws -> RetainedTextEditingLayout {
        let viewport = try viewport()
        let frame = try XCTUnwrap(runtime.resolvedLayoutFrame(of: viewport))
        return try XCTUnwrap(
            RetainedTextMetrics.editingLayout(
                of: displayText ?? document.text, style: viewport.textStyle,
                contentWidth: frame.width - 1.5, displayScale: runtime.displayScale))
    }

    func pointerPoint(at offset: Int, affinity: RetainedTextSelectionAffinity = .downstream) throws -> Point {
        let geometry = try XCTUnwrap(
            try layout().caret(at: RetainedTextCaretPosition(characterOffset: offset, affinity: affinity)))
        let contentFrame = try XCTUnwrap(runtime.resolvedLayoutFrame(of: try content()))
        return Point(
            x: contentFrame.minX + geometry.rect.minX + 0.25,
            y: contentFrame.minY + geometry.rect.minY + geometry.rect.height * 0.5)
    }

    func boundRange() -> Range<Int>? {
        guard case .selection(let range) = document.selection?.indices else { return nil }
        let lower = document.text.distance(from: document.text.startIndex, to: range.lowerBound)
        let upper = document.text.distance(from: document.text.startIndex, to: range.upperBound)
        return lower..<upper
    }

    func assertInsertion(
        _ offset: Int, affinity: TextSelectionAffinity? = nil, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(try input().textInputCaretOffset, offset, file: file, line: line)
        XCTAssertEqual(boundRange(), offset..<offset, file: file, line: line)
        XCTAssertEqual(try input().textInputSelection?.indices, .insertionPoint(offset), file: file, line: line)
        if let affinity {
            XCTAssertEqual(document.selection?.affinity, affinity, file: file, line: line)
        }
    }

    func assertSelection(
        _ range: Range<Int>, caret: Int, affinity: TextSelectionAffinity,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(try input().textInputCaretOffset, caret, file: file, line: line)
        XCTAssertEqual(try input().textInputSelection?.indices, .range(range), file: file, line: line)
        XCTAssertEqual(boundRange(), range, file: file, line: line)
        XCTAssertEqual(document.selection?.affinity, affinity, file: file, line: line)
    }

    func assertCaretVisible(file: StaticString = #filePath, line: UInt = #line) throws {
        let viewportFrame = try XCTUnwrap(runtime.resolvedLayoutFrame(of: try viewport()), file: file, line: line)
        let caret = try XCTUnwrap(runtime.focusedTextInputCaretRect, file: file, line: line)
        XCTAssertGreaterThanOrEqual(caret.minY, viewportFrame.minY - 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(caret.maxY, viewportFrame.maxY + 0.001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(caret.minX, viewportFrame.minX - 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(caret.maxX, viewportFrame.maxX + 0.001, file: file, line: line)
    }

    func assertCandidate(
        matches geometry: RetainedTextCaretGeometry, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let contentFrame = try XCTUnwrap(runtime.resolvedLayoutFrame(of: try content()), file: file, line: line)
        let candidate = try XCTUnwrap(runtime.focusedTextInputCaretRect, file: file, line: line)
        XCTAssertEqual(candidate.minX, contentFrame.minX + geometry.rect.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(candidate.minY, contentFrame.minY + geometry.rect.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(candidate.height, geometry.rect.height, accuracy: 0.001, file: file, line: line)
    }

    func visibleFragments() throws -> [ViewNode] {
        try content().children.filter { !$0.isHidden && $0.text?.isEmpty == false }
    }
}

/// Public facade and retained-host coverage. The synthetic native layout has
/// unequal advances, so preserving string columns cannot satisfy these tests.
/// The final test deliberately uses DirectWrite without a layout override.
@MainActor
final class TextEditorNavigationTests: XCTestCase {
    private func withFixture(
        text: String = "WWii\nx\nWWii", insertion: Int = 3, height: Double = 100,
        nestedOuterScroll: Bool = false, kind: NavigationInputKind = .editor,
        _ body: (NavigationFixture) throws -> Void
    ) throws {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            var x = 0.0
            var glyphs: [NativeTextGlyphLayout] = []
            for (index, character) in text.enumerated() {
                let advance: Double
                switch character {
                case "W": advance = 18
                case "i": advance = 4
                case " ": advance = 6
                default: advance = 9
                }
                glyphs.append(
                    NativeTextGlyphLayout(
                        character: character, origin: Point(x: x, y: 0), advance: advance,
                        glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                        fontSize: style.nativeFontPixelSize, sourceIndex: index))
                x += advance
            }
            let size = Size(width: x, height: 20)
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: x, height: 20, glyphs: glyphs)],
                lineSpacing: style.lineSpacing, contentSize: size, measuredSize: size)
        }
        defer { NativeTextRenderer.resetTestingOverrides() }
        let fixture = try NavigationFixture(
            text: text, insertion: insertion, height: height, nestedOuterScroll: nestedOuterScroll, kind: kind)
        try body(fixture)
    }

    func testUpDownPreservesVisualXAcrossShortAndLongLines() async throws {
        try withFixture { fixture in
            let layout = try fixture.layout()
            XCTAssertTrue(layout.hasCompleteCaretGeometry)
            XCTAssertEqual(layout.lines.map(\.sourceRange), [0..<4, 5..<6, 7..<11])
            try fixture.assertInsertion(3)

            for (key, offset) in [
                (KeyboardKey.downArrow, 6), (.downArrow, 10), (.upArrow, 6), (.upArrow, 3),
            ] {
                fixture.key(key)
                try fixture.assertInsertion(offset)
                try fixture.assertCaretVisible()
            }

            XCTAssertEqual(fixture.document.text, "WWii\nx\nWWii")
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
            XCTAssertEqual(fixture.document.selectionWrites, 4)
        }
    }

    func testShiftVerticalMovementKeepsAnchorAcrossCollapseAndDirectionChanges() async throws {
        try withFixture(insertion: 6) { fixture in
            // Establish X=40 before making the short line the selection anchor.
            fixture.setInsertion(3)
            fixture.key(.downArrow)
            fixture.key(.upArrow, modifiers: [.shift])
            try fixture.assertSelection(3..<6, caret: 3, affinity: .upstream)
            fixture.key(.downArrow, modifiers: [.shift])
            try fixture.assertInsertion(6)
            fixture.key(.downArrow, modifiers: [.shift])
            try fixture.assertSelection(6..<10, caret: 10, affinity: .downstream)
            fixture.key(.upArrow)
            try fixture.assertInsertion(6)
            fixture.key(.upArrow)
            try fixture.assertInsertion(3)
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
        }
    }

    func testHorizontalMovementResetsThePreferredVisualX() async throws {
        try withFixture { fixture in
            fixture.key(.downArrow)
            try fixture.assertInsertion(6)
            fixture.key(.leftArrow)
            try fixture.assertInsertion(5)
            fixture.key(.downArrow)
            try fixture.assertInsertion(7)
            fixture.key(.rightArrow)
            try fixture.assertInsertion(8)
            fixture.key(.upArrow)
            try fixture.assertInsertion(6)
            fixture.key(.upArrow)
            try fixture.assertInsertion(1)
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
        }
    }

    func testHomeEndRespectSoftWrapAffinityAndControlUsesDocumentBounds() async throws {
        try withFixture(text: "WWiiiiWWiiii", insertion: 2) { fixture in
            try fixture.setWrapWidth(44)
            let layout = try fixture.layout()
            XCTAssertEqual(layout.lines.map(\.sourceRange), [0..<4, 4..<8, 8..<12])

            fixture.key(.end)
            try fixture.assertInsertion(4, affinity: .upstream)
            try fixture.assertCandidate(
                matches: XCTUnwrap(layout.caret(at: RetainedTextCaretPosition(characterOffset: 4, affinity: .upstream)))
            )
            fixture.key(.home)
            try fixture.assertInsertion(0, affinity: .downstream)

            fixture.setInsertion(4, affinity: .downstream)
            fixture.key(.home)
            try fixture.assertInsertion(4, affinity: .downstream)
            fixture.key(.end)
            try fixture.assertInsertion(8, affinity: .upstream)
            fixture.key(.home)
            try fixture.assertInsertion(4, affinity: .downstream)

            fixture.key(.end, modifiers: [.control])
            try fixture.assertInsertion(12, affinity: .upstream)
            fixture.key(.home)
            try fixture.assertInsertion(8, affinity: .downstream)
            fixture.key(.home, modifiers: [.control, .shift])
            try fixture.assertSelection(0..<8, caret: 0, affinity: .upstream)
            fixture.key(.end, modifiers: [.control, .shift])
            try fixture.assertSelection(8..<12, caret: 12, affinity: .downstream)
            fixture.key(.home, modifiers: [.control])
            try fixture.assertInsertion(0, affinity: .downstream)
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
        }
    }

    func testNavigationPreservesGraphemesCRLFAndTheTrailingEmptyLine() async throws {
        let line = "W👩🏽‍💻e\u{301}i"
        let text = line + "\r\nx\r\n" + line + "\n"
        XCTAssertEqual(line.count, 4)
        XCTAssertEqual(text.count, 12)
        try withFixture(text: text) { fixture in
            let layout = try fixture.layout()
            XCTAssertEqual(layout.lines.map(\.text), [line, "x", line, ""])
            XCTAssertEqual(layout.lines.map(\.sourceRange), [0..<4, 5..<6, 7..<11, 12..<12])
            XCTAssertEqual(layout.lines.map(\.hardBreakRange), [4..<5, 6..<7, 11..<12, nil])
            fixture.key(.downArrow)
            try fixture.assertInsertion(6)
            fixture.key(.downArrow)
            try fixture.assertInsertion(10)
            fixture.key(.upArrow, modifiers: [.shift])
            try fixture.assertSelection(6..<10, caret: 6, affinity: .upstream)
            fixture.key(.end, modifiers: [.control])
            try fixture.assertInsertion(12)
            try fixture.assertCandidate(
                matches: XCTUnwrap(
                    layout.caret(at: RetainedTextCaretPosition(characterOffset: 12, affinity: .upstream))))
            XCTAssertEqual(Array(fixture.document.text.utf8), Array(text.utf8))
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
        }
    }

    func testCompatibleRebuildKeepsInputViewportScrollAndPreferredX() async throws {
        let text = ["WWii", "x", "WWii", "x", "WWii", "x", "WWii"].joined(separator: "\n")
        try withFixture(text: text, height: 74) { fixture in
            let input = try fixture.input()
            let viewport = try fixture.viewport()
            fixture.key(.downArrow)
            fixture.key(.downArrow)
            fixture.key(.downArrow)
            try fixture.assertInsertion(13)
            let offset = viewport.scrollOffset
            XCTAssertGreaterThan(offset, 0)

            fixture.reload()

            XCTAssertTrue(try fixture.input() === input)
            XCTAssertTrue(try fixture.viewport() === viewport)
            XCTAssertTrue(fixture.runtime.focusedNode === input)
            XCTAssertEqual(viewport.scrollOffset, offset, accuracy: 0.001)
            fixture.key(.downArrow)
            try fixture.assertInsertion(17)
            try fixture.assertCaretVisible()
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
        }
    }

    func testExplicitSelectionChangeResetsThePreferredVisualX() async throws {
        try withFixture { fixture in
            fixture.key(.downArrow)
            try fixture.assertInsertion(6)
            let retained = try fixture.input()

            fixture.setInsertion(5)

            XCTAssertTrue(try fixture.input() === retained)
            fixture.key(.downArrow)
            try fixture.assertInsertion(7)
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
        }
    }

    func testExternalTextAndWidthChangesResetPreferredXAndReflowTheActualFragments() async throws {
        try withFixture { fixture in
            fixture.key(.downArrow)
            try fixture.assertInsertion(6)
            fixture.document.text = "WWii\nx\niiii"
            fixture.document.selection = navigationInsertion(6, in: fixture.document.text, affinity: .upstream)
            fixture.reload()
            fixture.key(.downArrow)
            try fixture.assertInsertion(9)

            fixture.setInsertion(3)
            fixture.key(.downArrow)
            try fixture.assertInsertion(6)
            try fixture.setWrapWidth(80)
            fixture.key(.downArrow)
            try fixture.assertInsertion(9)

            let before = try fixture.layout()
            try fixture.setWrapWidth(22)
            let after = try fixture.layout()
            XCTAssertGreaterThan(after.lines.count, before.lines.count)
            XCTAssertTrue(after.lines.allSatisfy { $0.rect.width <= 22 })
            XCTAssertEqual(
                try fixture.visibleFragments().compactMap(\.text), after.lines.map(\.text).filter { !$0.isEmpty })
            let caret = try XCTUnwrap(after.caret(at: RetainedTextCaretPosition(characterOffset: 9)))
            fixture.key(.home)
            try fixture.assertInsertion(after.lines[caret.lineIndex].sourceRange.lowerBound)
            try fixture.assertCaretVisible()
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
        }
    }

    func testTypingUndoRedoAndRebuildRevealTheCurrentCaret() async throws {
        try withFixture(text: "Start", insertion: 5, height: 74) { fixture in
            let suffix = "\n" + Array(repeating: "WWii", count: 12).joined(separator: "\n")
            fixture.type(suffix)
            XCTAssertEqual(fixture.document.text, "Start" + suffix)
            try fixture.assertInsertion(fixture.document.text.count)
            XCTAssertGreaterThan(try fixture.viewport().scrollOffset, 0)
            try fixture.assertCaretVisible()
            XCTAssertTrue(fixture.state.undoManager.canUndo)

            fixture.reload()
            try fixture.assertCaretVisible()
            fixture.state.undoManager.undo()
            fixture.render()
            XCTAssertEqual(fixture.document.text, "Start")
            try fixture.assertInsertion(5)
            XCTAssertEqual(try fixture.viewport().scrollOffset, 0, accuracy: 0.001)
            try fixture.assertCaretVisible()

            fixture.state.undoManager.redo()
            fixture.render()
            XCTAssertEqual(fixture.document.text, "Start" + suffix)
            try fixture.assertInsertion(fixture.document.text.count)
            XCTAssertGreaterThan(try fixture.viewport().scrollOffset, 0)
            try fixture.assertCaretVisible()
        }
    }

    func testEditorNavigationAndControlArrowsNeverScrollTheOuterView() async throws {
        let text = Array(repeating: "WWii", count: 16).joined(separator: "\n")
        try withFixture(text: text, insertion: 0, height: 74, nestedOuterScroll: true) { fixture in
            let outer = try fixture.outerScroll()
            outer.scrollOffset = 18
            fixture.render()
            let originalOffset = outer.scrollOffset
            fixture.key(.end, modifiers: [.control])
            XCTAssertGreaterThan(try fixture.viewport().scrollOffset, 0)
            XCTAssertEqual(outer.scrollOffset, originalOffset, accuracy: 0.001)
            try fixture.assertCaretVisible()
            fixture.key(.upArrow, modifiers: [.shift])
            XCTAssertEqual(outer.scrollOffset, originalOffset, accuracy: 0.001)
            fixture.key(.home, modifiers: [.control])
            try fixture.assertInsertion(0)
            XCTAssertEqual(try fixture.viewport().scrollOffset, 0, accuracy: 0.001)

            let selection = fixture.document.selection
            let writes = fixture.document.selectionWrites
            let modifierCases: [KeyboardModifiers] = [[.control], [.control, .shift]]
            for modifiers in modifierCases {
                fixture.key(.upArrow, modifiers: modifiers)
                fixture.key(.downArrow, modifiers: modifiers)
            }
            XCTAssertEqual(fixture.document.selection, selection)
            XCTAssertEqual(fixture.document.selectionWrites, writes)
            XCTAssertEqual(outer.scrollOffset, originalOffset, accuracy: 0.001)
            XCTAssertEqual(try fixture.viewport().scrollOffset, 0, accuracy: 0.001)
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
        }
    }

    func testReconciliationDoesNotRevealAnEditorWhileAnotherControlOrNothingHasFocus() async throws {
        let text = Array(repeating: "WWii", count: 16).joined(separator: "\n")
        try withFixture(text: text, insertion: 0, height: 74, nestedOuterScroll: true) { fixture in
            fixture.key(.end, modifiers: [.control])
            let viewport = try fixture.viewport()
            let outer = try fixture.outerScroll()
            let offset = viewport.scrollOffset
            let outerOffset = outer.scrollOffset
            let other = try fixture.otherButton()
            fixture.runtime.requestFocus(other)
            fixture.document.text += "\n" + text
            fixture.document.selection = navigationInsertion(fixture.document.text.count, in: fixture.document.text)
            fixture.reload()
            XCTAssertTrue(fixture.runtime.focusedNode === other)
            XCTAssertEqual(viewport.scrollOffset, offset, accuracy: 0.001)
            XCTAssertEqual(outer.scrollOffset, outerOffset, accuracy: 0.001)
            XCTAssertNil(fixture.runtime.focusedTextInputCaretRect)

            fixture.runtime.requestFocus(nil)
            fixture.setInsertion(0)
            XCTAssertNil(fixture.runtime.focusedNode)
            XCTAssertEqual(viewport.scrollOffset, offset, accuracy: 0.001)
            XCTAssertEqual(outer.scrollOffset, outerOffset, accuracy: 0.001)
            XCTAssertNil(fixture.runtime.focusedTextInputCaretRect)
        }
    }

    func testQueuedCaretRevealCannotActAfterThePublicEditorIsRemoved() async throws {
        let text = Array(repeating: "WWii", count: 16).joined(separator: "\n")
        try withFixture(text: text, insertion: 0, height: 74) { fixture in
            let input = try fixture.input()
            let viewport = try fixture.viewport()
            let obsoleteCandidate = input.textInputCaretRectProvider
            fixture.state.automaticallyReloads = false
            // Do not render or query geometry between the edit and removal:
            // the reveal must still be waiting in the after-layout queue.
            fixture.key(.end, modifiers: [.control], renderAfter: false)
            XCTAssertEqual(input.textInputCaretOffset, text.count)
            XCTAssertEqual(viewport.scrollOffset, 0, accuracy: 0.001)
            fixture.state.showsInput = false
            fixture.host.reload()
            fixture.render()

            XCTAssertNil(fixture.currentInput())
            XCTAssertNil(fixture.runtime.focusedNode)
            XCTAssertNil(obsoleteCandidate?())
            XCTAssertEqual(viewport.scrollOffset, 0, accuracy: 0.001)
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
        }
    }

    func testDisabledEditorDrawsItsDocumentWithoutAcceptingNavigationOrText() async throws {
        try withFixture { fixture in
            fixture.state.isDisabled = true
            fixture.reload()
            let input = try fixture.input()
            let selection = fixture.document.selection
            let writes = fixture.document.selectionWrites
            XCTAssertFalse(input.isFocusable)
            XCTAssertNil(input.onKeyDown)
            XCTAssertNil(input.onIMEComposition)
            fixture.runtime.requestFocus(input)
            fixture.key(.downArrow)
            fixture.type("Z")
            XCTAssertEqual(fixture.document.selection, selection)
            XCTAssertEqual(fixture.document.selectionWrites, writes)
            XCTAssertEqual(fixture.document.text, "WWii\nx\nWWii")
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
            XCTAssertFalse(try fixture.visibleFragments().isEmpty)
            XCTAssertEqual(try fixture.viewport().scrollOffset, 0, accuracy: 0.001)
        }
    }

    func testSingleLineAndSecureInputsKeepTheirExistingNavigationAndMasking() async throws {
        let text = "W👩🏽‍💻e\u{301}"
        for kind in [NavigationInputKind.field, .secure] {
            try withFixture(text: text, insertion: 2, kind: kind) { fixture in
                XCTAssertFalse(try fixture.input().children.contains { $0.scrollAxis != nil })
                fixture.key(.home)
                fixture.key(.rightArrow)
                XCTAssertEqual(try fixture.input().textInputCaretOffset, 1)
                fixture.key(.upArrow)
                fixture.key(.downArrow)
                XCTAssertEqual(try fixture.input().textInputCaretOffset, 1)
                fixture.key(.end)
                XCTAssertEqual(try fixture.input().textInputCaretOffset, text.count)
                fixture.type("Z")
                XCTAssertEqual(fixture.document.text, text + "Z")
                if kind == .secure {
                    XCTAssertNil(try fixture.input().accessibilityValue)
                    XCTAssertFalse(fixture.state.undoManager.canUndo)
                    XCTAssertFalse(
                        navigationNodes(in: try fixture.input()).contains { $0.text?.contains(text) == true })
                } else {
                    XCTAssertTrue(fixture.state.undoManager.canUndo)
                }
            }
        }
    }

    func testWrappedCompositionKeepsCandidateGeometryAndOwnsNavigationWithoutBindingWrites() async throws {
        try withFixture(text: "Wi", insertion: 1, height: 60) { fixture in
            try fixture.setWrapWidth(40)
            let marked = "👩🏽‍💻e\u{301}WWiiiiWW"
            let display = "W" + marked + "i"
            let selection = fixture.document.selection
            let selectionWrites = fixture.document.selectionWrites
            fixture.compose(.started)
            fixture.compose(.updated(marked))
            let layout = try fixture.layout(displayText: display)
            XCTAssertGreaterThan(layout.lines.count, 2)
            XCTAssertEqual(
                try fixture.visibleFragments().compactMap(\.text), layout.lines.map(\.text).filter { !$0.isEmpty })
            let candidate = try XCTUnwrap(
                layout.caret(at: RetainedTextCaretPosition(characterOffset: 1 + marked.count)))
            try fixture.assertCandidate(matches: candidate)
            try fixture.assertCaretVisible()
            let underlines = try fixture.content().children.filter {
                $0.text == nil && !$0.isTextInputCaret && $0.frame.height > 0 && $0.frame.height <= 1
            }
            XCTAssertGreaterThan(underlines.count, 1)

            for key in [KeyboardKey.upArrow, .downArrow, .home, .end] {
                fixture.key(key)
                fixture.key(key, modifiers: [.control, .shift])
            }
            XCTAssertEqual(fixture.document.text, "Wi")
            XCTAssertEqual(fixture.document.selection, selection)
            XCTAssertEqual(fixture.document.selectionWrites, selectionWrites)
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
            XCTAssertEqual(try fixture.input().textInputMarkedText, marked)
            XCTAssertEqual(try fixture.input().textInputCaretOffset, 1)
            try fixture.assertCandidate(matches: candidate)

            fixture.compose(.ended)
            XCTAssertNil(try fixture.input().textInputMarkedText)
            XCTAssertEqual(fixture.document.text, "Wi")
            try fixture.assertInsertion(1)
            try fixture.assertCaretVisible()
        }
    }

    func testNavigationGetterReentryCannotOverwriteAReplacementDocumentOnTheSameRetainedInput() async throws {
        try withFixture { fixture in
            let input = try fixture.input()
            let original = fixture.document
            let replacement = NavigationDocument(text: "replacement", insertion: 0)
            replacement.selection = navigationSelection(1..<3, in: replacement.text, affinity: .downstream)
            // Settle the geometry query before arming the hook. With no dirty
            // layout, Up/Down reads text first for refreshChrome and then for
            // applySelection. The second read is the reentry point.
            _ = fixture.runtime.resolvedLayoutFrame(of: try fixture.content())
            var reads = 0
            var replaced = false
            original.beforeTextRead = { [weak host = fixture.host, weak state = fixture.state] in
                reads += 1
                guard reads == 2, let host, let state else { return }
                original.beforeTextRead = nil
                state.document = replacement
                host.reload()
                replaced = true
            }
            defer { original.beforeTextRead = nil }

            fixture.key(.downArrow)

            XCTAssertTrue(replaced, "The getter reentry must execute, not silently become an ordinary key test")
            XCTAssertEqual(reads, 2)
            XCTAssertTrue(try fixture.input() === input, "The public id deliberately survives the binding replacement")
            XCTAssertTrue(fixture.runtime.focusedNode === input)
            try fixture.assertSelection(1..<3, caret: 3, affinity: .downstream)
            XCTAssertEqual(original.selectionWrites, 0)
            XCTAssertEqual(replacement.selectionWrites, 0)
            XCTAssertTrue(original.textWrites.isEmpty)
            XCTAssertTrue(replacement.textWrites.isEmpty)
        }
    }

    func testChangedTextDuringSelectionReadQueuesLayoutWithoutAnotherGetterOrSelectionWrite() async throws {
        for rendersScene in [true, false] {
            try withFixture { fixture in
                for _ in 0..<4 where fixture.runtime.isDirty { fixture.render() }
                XCTAssertFalse(fixture.runtime.isDirty, "The editor must begin with clean retained caches")
                XCTAssertFalse(fixture.runtime.hasPendingLayout)
                let input = try fixture.input()
                let controller = try XCTUnwrap(input.textInputController)
                let document = fixture.document
                let selection = document.selection
                let retainedSelection = input.textInputSelection
                let caret = input.textInputCaretOffset
                let selectionWrites = document.selectionWrites
                let fragments = try fixture.visibleFragments().compactMap(\.text)
                let replacement = "iiWW\nx\niiWW"
                fixture.state.automaticallyReloads = false
                var reads = 0
                document.beforeTextRead = {
                    reads += 1
                    if reads == 2 { document.text = replacement }
                }
                defer { document.beforeTextRead = nil }

                fixture.key(.downArrow, renderAfter: false)

                XCTAssertEqual(reads, 2, "Rejection must queue layout without another application getter")
                XCTAssertTrue(input.textInputController === controller)
                XCTAssertEqual(document.text, replacement)
                XCTAssertEqual(document.selection, selection)
                XCTAssertEqual(input.textInputSelection, retainedSelection)
                XCTAssertEqual(input.textInputCaretOffset, caret)
                XCTAssertEqual(document.selectionWrites, selectionWrites)
                XCTAssertTrue(document.textWrites.isEmpty)
                XCTAssertTrue(fixture.runtime.hasPendingLayout, "The editor and its ancestors must be dirty")
                XCTAssertEqual(try fixture.visibleFragments().compactMap(\.text), fragments)

                document.beforeTextRead = nil
                if rendersScene {
                    _ = fixture.runtime.renderScene()
                } else {
                    _ = fixture.runtime.renderFrame()
                }

                XCTAssertEqual(try fixture.visibleFragments().compactMap(\.text), ["iiWW", "x", "iiWW"])
                XCTAssertTrue(input.textInputController === controller)
                XCTAssertEqual(input.textInputCaretOffset, caret)
                XCTAssertEqual(document.selection, selection)
                XCTAssertEqual(document.selectionWrites, selectionWrites)
                XCTAssertTrue(document.textWrites.isEmpty)
                let layout = try fixture.layout()
                try fixture.assertCandidate(
                    matches: XCTUnwrap(layout.caret(at: RetainedTextCaretPosition(characterOffset: caret))))
            }
        }
    }

    func testNavigationUsesLayoutResizedByAGetterWithoutReplacingTheController() async throws {
        try withFixture(text: "WWiiiiWWiiii", insertion: 2) { fixture in
            let input = try fixture.input()
            let viewport = try fixture.viewport()
            let controller = try XCTUnwrap(input.textInputController)
            let oldViewportFrame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: viewport))
            XCTAssertEqual(try fixture.layout().lines.count, 1)
            let wrapper = try fixture.frameWrapper()
            let size = try XCTUnwrap(wrapper.preferredSize)
            let resizedWidth = size.width + 44 + 1.5 - oldViewportFrame.width
            fixture.state.automaticallyReloads = false
            let document = fixture.document
            var resized = false
            document.beforeTextRead = { [weak runtime = fixture.runtime, weak wrapper, weak viewport] in
                guard !resized, let runtime, let wrapper, let viewport else { return }
                resized = true
                document.beforeTextRead = nil
                wrapper.preferredSize = Size(width: resizedWidth, height: size.height)
                _ = runtime.resolvedLayoutFrame(of: viewport)
            }
            defer { document.beforeTextRead = nil }

            fixture.key(.downArrow)

            XCTAssertTrue(resized)
            XCTAssertTrue(input.textInputController === controller)
            let placed = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: viewport))
            XCTAssertEqual(placed.width - 1.5, 44, accuracy: 0.001)
            let layout = try fixture.layout()
            XCTAssertEqual(layout.lines.map(\.sourceRange), [0..<4, 4..<8, 8..<12])
            try fixture.assertInsertion(8, affinity: .upstream)
            try fixture.assertCandidate(
                matches: XCTUnwrap(layout.caret(at: RetainedTextCaretPosition(characterOffset: 8, affinity: .upstream)))
            )
            XCTAssertEqual(document.selectionWrites, 1)
            XCTAssertTrue(document.textWrites.isEmpty)
        }
    }

    func testResizeDuringTheSelectionGetterRejectsThePreparedNavigationDestination() async throws {
        try withFixture { fixture in
            let input = try fixture.input()
            let controller = try XCTUnwrap(input.textInputController)
            let viewport = try fixture.viewport()
            let wrapper = try fixture.frameWrapper()
            let size = try XCTUnwrap(wrapper.preferredSize)
            let oldFrame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: viewport))
            let resizedWidth = size.width + 22 + 1.5 - oldFrame.width
            _ = fixture.runtime.resolvedLayoutFrame(of: try fixture.content())
            fixture.state.automaticallyReloads = false
            let document = fixture.document
            var reads = 0
            var resized = false
            var reflowFrame: Rect?
            for _ in 0..<4 where fixture.runtime.isDirty { fixture.render() }
            XCTAssertFalse(fixture.runtime.isDirty, "Routing must not consume the counted getter during layout")
            XCTAssertFalse(fixture.runtime.hasPendingLayout)
            document.beforeTextRead = { [weak runtime = fixture.runtime, weak wrapper, weak viewport] in
                reads += 1
                guard reads == 2, let runtime, let wrapper, let viewport else { return }
                resized = true
                document.beforeTextRead = nil
                wrapper.preferredSize = Size(width: resizedWidth, height: size.height)
                reflowFrame = runtime.resolvedLayoutFrame(of: viewport)
            }
            defer { document.beforeTextRead = nil }

            fixture.key(.downArrow)

            XCTAssertTrue(resized)
            XCTAssertEqual(reads, 2)
            XCTAssertNotNil(reflowFrame, "The resize getter must run outside a routing layout callback")
            XCTAssertTrue(input.textInputController === controller)
            XCTAssertEqual(
                try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: viewport)).width - 1.5, 22, accuracy: 0.001)
            XCTAssertGreaterThan(try fixture.layout().lines.count, 3)
            try fixture.assertInsertion(3)
            XCTAssertEqual(document.selectionWrites, 0, "The destination computed before reflow is obsolete")
            XCTAssertTrue(document.textWrites.isEmpty)

            fixture.key(.downArrow)
            try fixture.assertInsertion(5)
            XCTAssertEqual(document.selectionWrites, 1)
        }
    }

    func testCompositionStartedByTheSelectionGetterRejectsPreparedNavigation() async throws {
        try withFixture { fixture in
            let input = try fixture.input()
            let controller = try XCTUnwrap(input.textInputController)
            _ = fixture.runtime.resolvedLayoutFrame(of: try fixture.content())
            let document = fixture.document
            var reads = 0
            var started = false
            for _ in 0..<4 where fixture.runtime.isDirty { fixture.render() }
            XCTAssertFalse(fixture.runtime.isDirty, "Routing must not consume the counted getter during layout")
            XCTAssertFalse(fixture.runtime.hasPendingLayout)
            document.beforeTextRead = { [weak runtime = fixture.runtime] in
                reads += 1
                guard reads == 2, let runtime else { return }
                started = true
                document.beforeTextRead = nil
                // No marked text or source change: the composition owner
                // itself must invalidate the prepared keyboard movement.
                runtime.imeComposition(IMECompositionEvent(phase: .started))
            }
            defer { document.beforeTextRead = nil }

            fixture.key(.downArrow)

            XCTAssertTrue(started)
            XCTAssertEqual(reads, 2)
            XCTAssertTrue(input.textInputController === controller)
            XCTAssertNil(input.textInputMarkedText)
            try fixture.assertInsertion(3)
            XCTAssertEqual(document.selectionWrites, 0)
            XCTAssertTrue(document.textWrites.isEmpty)
            fixture.key(.downArrow)
            try fixture.assertInsertion(3)
            XCTAssertEqual(document.selectionWrites, 0)

            fixture.compose(.ended)
            fixture.key(.downArrow)
            try fixture.assertInsertion(6)
            XCTAssertEqual(document.selectionWrites, 1)
        }
    }

    func testRejectedPointerStartKeepsWrapAffinityAndCannotReuseAnEarlierDragAnchor() async throws {
        for startsComposition in [true, false] {
            try withFixture(text: "WWiiiiWWiiii", insertion: 2) { fixture in
                try fixture.setWrapWidth(44)
                // Leave an earlier drag active. A rejected new press must
                // revoke that gesture, not resume selection from its anchor.
                fixture.runtime.pointerDown(at: try fixture.pointerPoint(at: 2))
                fixture.render()
                try fixture.assertInsertion(2)
                fixture.key(.end)
                try fixture.assertInsertion(4, affinity: .upstream)
                let input = try fixture.input()
                let controller = try XCTUnwrap(input.textInputController)
                let viewport = try fixture.viewport()
                let wrapper = try fixture.frameWrapper()
                let originalSize = try XCTUnwrap(wrapper.preferredSize)
                let originalFrame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: viewport))
                let resizedWidth = originalSize.width + 40 + 1.5 - originalFrame.width
                let boundaryPoint = try fixture.pointerPoint(at: 4, affinity: .downstream)
                let dragPoint = try fixture.pointerPoint(at: 10)
                let originalCaret = try XCTUnwrap(
                    try fixture.layout().caret(at: RetainedTextCaretPosition(characterOffset: 4, affinity: .upstream)))
                let document = fixture.document
                let selection = document.selection
                let writes = document.selectionWrites
                fixture.state.automaticallyReloads = false
                var reads = 0
                var rejected = false
                var reflowFrame: Rect?
                for _ in 0..<4 where fixture.runtime.isDirty { fixture.render() }
                XCTAssertFalse(fixture.runtime.isDirty, "Routing must not consume the counted getter during layout")
                XCTAssertFalse(fixture.runtime.hasPendingLayout)
                document.beforeTextRead = { [weak runtime = fixture.runtime, weak wrapper, weak viewport] in
                    reads += 1
                    guard reads == 2, let runtime, let wrapper, let viewport else { return }
                    rejected = true
                    document.beforeTextRead = nil
                    if startsComposition {
                        runtime.imeComposition(IMECompositionEvent(phase: .started))
                    } else {
                        wrapper.preferredSize = Size(width: resizedWidth, height: originalSize.height)
                        reflowFrame = runtime.resolvedLayoutFrame(of: viewport)
                    }
                }
                defer { document.beforeTextRead = nil }

                fixture.runtime.pointerDown(at: boundaryPoint)
                fixture.render()

                XCTAssertTrue(rejected, "The final selection getter must invalidate the proposed pointer start")
                XCTAssertEqual(reads, 2)
                XCTAssertTrue(input.textInputController === controller)
                try fixture.assertInsertion(4, affinity: .upstream)
                XCTAssertEqual(document.selection, selection)
                XCTAssertEqual(document.selectionWrites, writes)
                if startsComposition {
                    try fixture.assertCandidate(matches: originalCaret)
                    fixture.compose(.ended)
                } else {
                    XCTAssertNotNil(reflowFrame, "The resize getter must run outside a routing layout callback")
                    XCTAssertEqual(
                        try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: viewport)).width - 1.5, 40,
                        accuracy: 0.001)
                    // Returning to the original wrap makes a prematurely
                    // staged downstream affinity visible on the next line.
                    wrapper.preferredSize = originalSize
                    fixture.render()
                }
                try fixture.assertCandidate(matches: originalCaret)

                fixture.runtime.pointerMoved(to: dragPoint)
                fixture.render()
                try fixture.assertInsertion(4, affinity: .upstream)
                XCTAssertEqual(document.selectionWrites, writes, "No accepted new press owns this drag")
                fixture.runtime.pointerUp(at: dragPoint)
                fixture.render()
                XCTAssertTrue(document.textWrites.isEmpty)
                XCTAssertEqual(document.text, "WWiiiiWWiiii")
            }
        }
    }

    func testAcceptedPointerInputResetsPreferredXAndKeepsItsDragAnchorAcrossRebuilds() async throws {
        try withFixture { fixture in
            fixture.key(.downArrow)
            try fixture.assertInsertion(6)
            let click = try fixture.pointerPoint(at: 5)
            fixture.runtime.pointerDown(at: click)
            fixture.runtime.pointerUp(at: click)
            fixture.render()
            try fixture.assertInsertion(5)
            fixture.key(.downArrow)
            try fixture.assertInsertion(7, affinity: .downstream)

            fixture.setInsertion(3)
            fixture.key(.downArrow)
            try fixture.assertInsertion(6)
            let input = try fixture.input()
            let viewport = try fixture.viewport()
            fixture.runtime.pointerDown(at: try fixture.pointerPoint(at: 5))
            fixture.render()
            try fixture.assertInsertion(5)
            fixture.reload()
            XCTAssertTrue(try fixture.input() === input)
            XCTAssertTrue(try fixture.viewport() === viewport)

            fixture.runtime.pointerMoved(to: try fixture.pointerPoint(at: 9))
            fixture.render()
            try fixture.assertSelection(5..<9, caret: 9, affinity: .downstream)
            fixture.reload()
            let lastPoint = try fixture.pointerPoint(at: 8)
            fixture.runtime.pointerMoved(to: lastPoint)
            fixture.runtime.pointerUp(at: lastPoint)
            fixture.render()
            try fixture.assertSelection(5..<8, caret: 8, affinity: .downstream)
            XCTAssertTrue(fixture.runtime.focusedNode === input)

            fixture.key(.upArrow)
            try fixture.assertInsertion(6)
            fixture.key(.upArrow)
            try fixture.assertInsertion(1, affinity: .downstream)
            XCTAssertTrue(fixture.document.textWrites.isEmpty)
            XCTAssertEqual(fixture.document.text, "WWii\nx\nWWii")
        }
    }

    func testHeightOnlyResizeRevealsMinimallyWithoutResettingPreferredXOrMovingOuterScroll() async throws {
        let text = Array(repeating: ["WWii", "x"], count: 6).flatMap { $0 }.joined(separator: "\n")
        try withFixture(text: text, height: 140, nestedOuterScroll: true) { fixture in
            let outer = try fixture.outerScroll()
            outer.scrollOffset = 17
            fixture.render()
            fixture.key(.downArrow)
            fixture.key(.downArrow)
            fixture.key(.downArrow)
            try fixture.assertInsertion(13)
            XCTAssertEqual(try fixture.viewport().scrollOffset, 0, accuracy: 0.001)
            let width = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: try fixture.viewport())).width

            fixture.state.height = 70
            fixture.reload()

            let viewport = try fixture.viewport()
            let frame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: viewport))
            XCTAssertEqual(frame.width, width, accuracy: 0.001)
            let caret = try XCTUnwrap(
                try fixture.layout().caret(at: RetainedTextCaretPosition(characterOffset: 13, affinity: .upstream)))
            XCTAssertEqual(viewport.scrollOffset, max(0, caret.rect.maxY - frame.height), accuracy: 0.001)
            XCTAssertGreaterThan(viewport.scrollOffset, 0)
            XCTAssertEqual(outer.scrollOffset, 17, accuracy: 0.001)
            try fixture.assertCaretVisible()
            fixture.key(.downArrow)
            try fixture.assertInsertion(17)
            let offsetAfterNavigation = viewport.scrollOffset

            fixture.state.height = 140
            fixture.reload()
            XCTAssertEqual(viewport.scrollOffset, offsetAfterNavigation, accuracy: 0.001)
            XCTAssertEqual(outer.scrollOffset, 17, accuracy: 0.001)
            try fixture.assertCaretVisible()
        }
    }

    func testDirectWriteKeepsLigatureAndBidirectionalTextInWholeRetainedFragments() async throws {
        let shapingWasEnabled = NativeTextRenderer.isGlyphShapingEnabled
        NativeTextRenderer.isGlyphShapingEnabled = true
        NativeTextRenderer.resetTestingOverrides()
        defer {
            NativeTextRenderer.isGlyphShapingEnabled = shapingWasEnabled
            NativeTextRenderer.resetTestingOverrides()
        }
        guard TextSystem.capabilities().dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }
        let text = "office ffi سلام עברית"
        let fixture = try NavigationFixture(text: text, insertion: 0)
        fixture.state.width = 600
        fixture.state.fontSize = 18
        fixture.document.selection = navigationSelection(2..<8, in: text)
        fixture.reload()
        let viewport = try fixture.viewport()
        let native = try XCTUnwrap(
            DirectWriteTextRenderer.editingLine(
                text, style: viewport.textStyle, scaleFactor: fixture.runtime.displayScale))
        XCTAssertFalse(native.carets.isEmpty)
        let layout = try fixture.layout()
        XCTAssertTrue(layout.hasCompleteCaretGeometry)
        XCTAssertEqual(layout.lines.count, 1)
        XCTAssertEqual(layout.lines.first?.text, text)
        XCTAssertEqual(try XCTUnwrap(layout.lines.first).rect.width, native.width, accuracy: 0.001)
        let fragments = try fixture.visibleFragments()
        XCTAssertEqual(fragments.compactMap(\.text), [text], "Selection must not split a shaping run into labels")
        let fragment = try XCTUnwrap(fragments.first)
        let retained = try XCTUnwrap(
            DirectWriteTextRenderer.layout(
                try XCTUnwrap(fragment.text), style: fragment.textStyle, scaleFactor: fixture.runtime.displayScale))
        XCTAssertFalse(retained.lines.flatMap(\.glyphs).isEmpty)
        let hebrewRange = try XCTUnwrap(text.range(of: "עברית"))
        let hebrewStart = text.distance(from: text.startIndex, to: hebrewRange.lowerBound)
        let earlier = try XCTUnwrap(
            native.carets.first { $0.characterOffset == hebrewStart + 1 && $0.affinity == .downstream })
        let later = try XCTUnwrap(
            native.carets.first { $0.characterOffset == hebrewStart + 2 && $0.affinity == .downstream })
        XCTAssertGreaterThan(earlier.x, later.x, "The real native geometry must preserve the right-to-left run")

        fixture.setInsertion(text.count - 2)
        let caret = try XCTUnwrap(
            try fixture.layout().caret(at: RetainedTextCaretPosition(characterOffset: text.count - 2)))
        try fixture.assertCandidate(matches: caret)
        XCTAssertEqual(try fixture.visibleFragments().compactMap(\.text), [text])
        XCTAssertEqual(Array(fixture.document.text.utf8), Array(text.utf8))
        XCTAssertTrue(fixture.document.textWrites.isEmpty)
    }
}
