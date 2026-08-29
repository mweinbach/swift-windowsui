import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class SettlementEditorModel {
    var text: String
    var selection: TextSelection?
    var revision = 0
    var bodyBuilds = 0
    var textReads = 0
    var selectionReads = 0
    var textWrites = 0
    var selectionWrites = 0
    let includesOuterScroll: Bool

    init(text: String, range: Range<Int>?, includesOuterScroll: Bool) {
        self.text = text
        self.includesOuterScroll = includesOuterScroll
        if let range {
            let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
            let upper = text.index(text.startIndex, offsetBy: range.upperBound)
            selection = TextSelection(range: lower..<upper)
        } else {
            selection = TextSelection(insertionPoint: text.endIndex)
        }
    }
}

@MainActor
private struct SettlementEditorRoot: View {
    let model: SettlementEditorModel

    var body: some View {
        model.bodyBuilds += 1
        let text = Binding<String>(
            get: {
                model.textReads += 1
                return model.text
            },
            set: {
                model.textWrites += 1
                model.text = $0
            })
        let selection = Binding<TextSelection?>(
            get: {
                model.selectionReads += 1
                return model.selection
            },
            set: {
                model.selectionWrites += 1
                model.selection = $0
            })
        let content = VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: text, selection: selection)
                .font(.system(size: 16))
                .lineSpacing(0)
                .id("settlement-editor")
                .frame(width: 300, height: 100)
            Text("Status \(model.revision)")
                .id("settlement-status")
                .accessibilityIdentifier("settlement.status")
                .frame(width: 120, height: 20)
            if model.includesOuterScroll {
                WinSwiftUI.Color.clear.frame(width: 300, height: 500)
                Text("Tail")
                    .id("settlement-outer-target")
                    .accessibilityIdentifier("settlement.outer-target")
                    .frame(width: 120, height: 20)
            }
        }
        if model.includesOuterScroll {
            return AnyView(
                ScrollView(.vertical, showsIndicators: false) { content }
                    .frame(width: 340, height: 180))
        }
        return AnyView(content)
    }
}

@MainActor
private func settlementEditorNodes(in root: ViewNode) -> [ViewNode] {
    var nodes: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        nodes.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return nodes
}

@MainActor
private func settlementEditorHasAncestor(_ node: ViewNode, _ ancestor: ViewNode) -> Bool {
    var current: ViewNode? = node
    while let candidate = current {
        if candidate === ancestor { return true }
        current = candidate.parent
    }
    return false
}

private enum SettlementEditorError: Error {
    case missingReceipt
}

@MainActor
private func settlementEditorReceipt(
    _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
) throws -> RetainedLayoutSettlementReceipt {
    guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
        XCTFail("The ordinary layout query must leave an actual settled receipt.", file: file, line: line)
        throw SettlementEditorError.missingReceipt
    }
    return receipt
}

/// Observes the real editor callback without supplying layout work of its own.
/// In particular this fixture never calls scheduleAfterLayout or the targeted
/// invalidator: the production chrome replacement must supply the follow-up.
@MainActor
private final class SettlementEditorLayoutTrace {
    var passes: [UInt64] = []
    var childReplacementPasses: [UInt64] = []
    var chromeInvalidationPasses: [UInt64] = []
    var afterRealLayout: (() -> Void)?

    func install(on editor: ViewNode, content: ViewNode, runtime: RetainedViewRuntime) throws {
        let realLayout = try XCTUnwrap(editor.onLayout)
        editor.onLayout = { [weak self, weak content, weak runtime] bounds in
            let childrenBefore = content?.children.map { ObjectIdentifier($0) }
            let scopeBefore = runtime?.textInputReplayScopeRevision
            let pass = runtime?.layoutPassID
            realLayout(bounds)
            guard let self, let runtime, let pass else { return }
            XCTAssertTrue(runtime.isLayoutInProgress)
            self.passes.append(pass)
            if content?.children.map({ ObjectIdentifier($0) }) != childrenBefore {
                self.childReplacementPasses.append(pass)
            }
            if runtime.textInputReplayScopeRevision != scopeBefore {
                self.chromeInvalidationPasses.append(pass)
            }
            self.afterRealLayout?()
        }
    }
}

@MainActor
private final class SettlementEditorFixture {
    let model: SettlementEditorModel
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let context: ViewBuildContext
    let clock = RuntimeTestClock()

    init(text: String, focused: Bool, range: Range<Int>?, includesOuterScroll: Bool) throws {
        let model = SettlementEditorModel(text: text, range: range, includesOuterScroll: includesOuterScroll)
        self.model = model
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 20, y: 30, width: 420, height: 700)))
        self.runtime = runtime
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 420, height: 700) },
            invalidateHandler: { [weak host] in host?.reload() })
        self.context = context
        clock.now = 1_000
        runtime.clock = { [clock] in clock.now }
        host.setComponents { [SettlementEditorRoot(model: model).makeComponent(context: context)] }
        if focused { runtime.requestFocus(try editor()) }
        // One ordinary baseline paint establishes the existing editing state.
        // None of the tested status rebuilds is followed by an inserted paint.
        _ = runtime.renderScene(at: clock.now)
        _ = try settlementEditorReceipt(runtime)
    }

    func editor() throws -> ViewNode {
        try XCTUnwrap(settlementEditorNodes(in: runtime.root).first { $0.accessibilityTraits.contains(.isTextInput) })
    }

    func viewport() throws -> ViewNode {
        try XCTUnwrap(try editor().children.first { $0.scrollAxis == .vertical })
    }

    func content() throws -> ViewNode { try XCTUnwrap(try viewport().children.first) }

    func element(_ identifier: String) throws -> ViewNode {
        try XCTUnwrap(settlementEditorNodes(in: runtime.root).first { $0.accessibilityIdentifier == identifier })
    }

    func outerScroll() throws -> ViewNode {
        let viewport = try viewport()
        return try XCTUnwrap(
            settlementEditorNodes(in: runtime.root).first { $0.scrollAxis == .vertical && $0 !== viewport })
    }

    func statusFrameWrapper() throws -> ViewNode {
        var ancestor = try element("settlement.status").parent
        while let node = ancestor {
            if node.preferredSize == Size(width: 120, height: 20) { return node }
            ancestor = node.parent
        }
        return try XCTUnwrap(Optional<ViewNode>.none, "The real status frame wrapper must exist.")
    }

    func rebuildStatus() {
        model.revision += 1
        host.reload()
    }

    func assertNoBindingWrites(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.textWrites, 0, file: file, line: line)
        XCTAssertEqual(model.selectionWrites, 0, file: file, line: line)
    }

    func assertTailIsOffscreen(file: StaticString = #filePath, line: UInt = #line) throws {
        let viewport = try viewport()
        let lastLine = try XCTUnwrap(try content().children.last { $0.text?.isEmpty == false }, file: file, line: line)
        let presentedBottom =
            viewport.scrollOffset + viewport.scrollPresentedDelta + viewport.scrollOvershoot
            + viewport.resolvedFrame.height
        XCTAssertGreaterThan(lastLine.frame.minY, presentedBottom, file: file, line: line)
        XCTAssertEqual(try editor().textInputCaretOffset, model.text.count, file: file, line: line)
    }
}

private enum SettlementEditorRetirement: CaseIterable, Equatable {
    case current
    case controller
    case content
    case detached
    case movedToOtherRuntime
    case terminal
}

/// Pure retained editor fixtures: no window, platform message, dialog, or IO.
@MainActor
final class TextEditorLayoutSettlementTests: XCTestCase {
    private var longText: String { Array(repeating: "abcdefghij", count: 30).joined(separator: "\n") }

    private func withFixture(
        text: String? = nil, focused: Bool = true, range: Range<Int>? = nil, includesOuterScroll: Bool = false,
        _ body: (SettlementEditorFixture) throws -> Void
    ) throws {
        let previousOverrides = NativeTextRenderer.testingOverrides
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let glyphs = text.enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 8, y: 0), advance: 8,
                    glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                    fontSize: style.nativeFontPixelSize, sourceIndex: index)
            }
            let size = Size(width: Double(text.count) * 8, height: 20)
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: size.width, height: 20, glyphs: glyphs)],
                lineSpacing: style.lineSpacing, contentSize: size, measuredSize: size)
        }
        defer { NativeTextRenderer.testingOverrides = previousOverrides }
        let fixture = try SettlementEditorFixture(
            text: text ?? longText, focused: focused, range: range, includesOuterScroll: includesOuterScroll)
        defer { fixture.runtime.stopRenderLifecycleCallbacks() }
        try body(fixture)
    }

    func testFocusedStatusRebuildSettlesFirstLayoutQueryWithoutRevealingOffscreenCaret() async throws {
        try withFixture { fixture in
            let editor = try fixture.editor()
            let viewport = try fixture.viewport()
            let content = try fixture.content()
            let previousController = try XCTUnwrap(editor.textInputController)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
            XCTAssertEqual(editor.textInputSelection?.indices, .insertionPoint(fixture.model.text.count))
            XCTAssertGreaterThan(
                max(0, viewport.resolvedContentSize.height - viewport.resolvedFrame.size.height), 80)
            viewport.scrollOffset = 80
            _ = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: editor))
            try fixture.assertTailIsOffscreen()
            let previousReceipt = try settlementEditorReceipt(fixture.runtime)
            let selection = fixture.model.selection
            let builds = fixture.model.bodyBuilds
            let paints = fixture.runtime.sceneRebuildCount
            let contentRevision = fixture.runtime.contentRevision

            fixture.rebuildStatus()

            XCTAssertEqual(fixture.model.bodyBuilds, builds + 1)
            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertTrue(try fixture.viewport() === viewport)
            XCTAssertTrue(try fixture.content() === content)
            XCTAssertFalse(try XCTUnwrap(editor.textInputController) === previousController)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(previousReceipt))
            let trace = SettlementEditorLayoutTrace()
            try trace.install(on: editor, content: content, runtime: fixture.runtime)
            let pass = fixture.runtime.layoutPassID

            let frame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: editor))

            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertEqual(fixture.runtime.layoutPassID, pass + 2)
            XCTAssertEqual(trace.passes, [pass + 1, pass + 2])
            XCTAssertEqual(trace.childReplacementPasses, [pass + 1])
            let receipt = try settlementEditorReceipt(fixture.runtime)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
            XCTAssertEqual(fixture.runtime.sceneRebuildCount, paints)
            XCTAssertEqual(fixture.runtime.contentRevision, contentRevision)
            XCTAssertTrue(fixture.runtime.isDirty, "The layout query must leave the owed paint pending.")
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
            XCTAssertEqual(viewport.scrollOffset, 80, accuracy: 0.001)
            XCTAssertEqual(viewport.resolvedScrollOffset, 80, accuracy: 0.001)
            XCTAssertEqual(viewport.scrollPresentedDelta, 0)
            XCTAssertEqual(fixture.model.selection, selection)
            XCTAssertEqual(editor.textInputSelection?.indices, .insertionPoint(fixture.model.text.count))
            try fixture.assertTailIsOffscreen()
            fixture.assertNoBindingWrites()
        }
    }

    func testWheelScrolledSelectionAndExistingTweenSurviveStatusRebuildSettlement() async throws {
        let text = longText
        let range = (text.count - 4)..<text.count
        try withFixture(text: text, range: range, includesOuterScroll: true) { fixture in
            let editor = try fixture.editor()
            let viewport = try fixture.viewport()
            let content = try fixture.content()
            let outer = try fixture.outerScroll()
            let target = try fixture.element("settlement.outer-target")
            let viewportFrame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: viewport))
            let beforeWheel = viewport.scrollOffset
            XCTAssertGreaterThan(beforeWheel, 128)

            fixture.runtime.mouseWheel(
                at: Point(
                    x: viewportFrame.minX + viewportFrame.width / 2, y: viewportFrame.minY + viewportFrame.height / 2),
                delta: 2, axis: .vertical, source: .wheelNotch)

            let wheelOffset = viewport.scrollOffset
            XCTAssertLessThan(wheelOffset, beforeWheel)
            XCTAssertGreaterThan(wheelOffset, 0)
            XCTAssertEqual(viewport.scrollPresentedDelta, 0, "A detent must not invent a smooth editor tween.")
            XCTAssertEqual(viewport.scrollOvershoot, 0)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(range))
            let wheelSelection = fixture.model.selection
            // Consume the wheel's ordinary baseline paint before requesting
            // an independent ancestor tween, whose existing admission guard
            // requires no pending layout flags. This is before the status
            // rebuild under test; its first layout query gets no added paint.
            _ = fixture.runtime.renderScene(at: fixture.clock.now)
            XCTAssertFalse(fixture.runtime.hasPendingLayout)
            XCTAssertEqual(viewport.scrollOffset, wheelOffset)
            XCTAssertEqual(fixture.model.selection, wheelSelection)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(range))
            XCTAssertTrue(
                fixture.runtime.scrollToDescendant(
                    target, anchorY: 0, transaction: Transaction(animation: .linear(duration: 4))))
            _ = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: editor))
            try fixture.assertTailIsOffscreen()
            let outerOffset = outer.scrollOffset
            let outerDelta = outer.scrollPresentedDelta
            XCTAssertGreaterThan(outerOffset, 0)
            XCTAssertLessThan(outerDelta, 0)
            let selection = fixture.model.selection
            let paints = fixture.runtime.sceneRebuildCount
            let start = fixture.clock.now

            fixture.rebuildStatus()

            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertTrue(try fixture.viewport() === viewport)
            XCTAssertTrue(try fixture.outerScroll() === outer)
            let trace = SettlementEditorLayoutTrace()
            try trace.install(on: editor, content: content, runtime: fixture.runtime)
            let pass = fixture.runtime.layoutPassID
            _ = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: editor))

            XCTAssertEqual(fixture.runtime.layoutPassID, pass + 2)
            XCTAssertEqual(trace.childReplacementPasses, [pass + 1])
            let receipt = try settlementEditorReceipt(fixture.runtime)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
            XCTAssertEqual(fixture.runtime.sceneRebuildCount, paints)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
            XCTAssertEqual(viewport.scrollOffset, wheelOffset)
            XCTAssertEqual(viewport.resolvedScrollOffset, wheelOffset, accuracy: 0.001)
            XCTAssertEqual(viewport.scrollPresentedDelta, 0)
            XCTAssertEqual(outer.scrollOffset, outerOffset)
            XCTAssertEqual(outer.scrollPresentedDelta, outerDelta)
            XCTAssertEqual(fixture.model.selection, selection)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(range))
            try fixture.assertTailIsOffscreen()

            // The existing ancestor tween keeps its original four-second
            // clock. These ticks are after the first-query settlement proof.
            fixture.clock.now = start + 2
            _ = fixture.runtime.tickAnimations(at: fixture.clock.now)
            XCTAssertEqual(outer.scrollPresentedDelta, outerDelta * 0.5, accuracy: 0.001)
            XCTAssertEqual(viewport.scrollOffset, wheelOffset)
            fixture.clock.now = start + 4
            _ = fixture.runtime.tickAnimations(at: fixture.clock.now)
            XCTAssertEqual(outer.scrollPresentedDelta, 0, accuracy: 0.001)
            XCTAssertEqual(outer.scrollOffset, outerOffset)
            XCTAssertEqual(viewport.scrollOffset, wheelOffset)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(range))
            fixture.assertNoBindingWrites()
        }
    }

    func testUnfocusedStatusRebuildSettlesWithoutFocusOrCaretReveal() async throws {
        for text in [longText, ""] {
            try withFixture(text: text, focused: false) { fixture in
                let editor = try fixture.editor()
                let viewport = try fixture.viewport()
                let content = try fixture.content()
                let offset = text.isEmpty ? 0.0 : 80.0
                if !text.isEmpty {
                    viewport.scrollOffset = offset
                    _ = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: editor))
                    try fixture.assertTailIsOffscreen()
                }
                XCTAssertNil(fixture.runtime.focusedNode)
                XCTAssertFalse(editor.isFocused)
                XCTAssertEqual(editor.textInputSelection?.indices, .insertionPoint(text.count))
                let selection = fixture.model.selection
                let paints = fixture.runtime.sceneRebuildCount

                fixture.rebuildStatus()

                let trace = SettlementEditorLayoutTrace()
                try trace.install(on: editor, content: content, runtime: fixture.runtime)
                let pass = fixture.runtime.layoutPassID
                _ = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: editor))

                XCTAssertEqual(fixture.runtime.layoutPassID, pass + 2)
                XCTAssertEqual(trace.passes, [pass + 1, pass + 2])
                if text.isEmpty {
                    // Removing an already-empty chrome child list still
                    // invalidates children. A value-only identity comparison
                    // cannot witness that mutation, but the replay revision can.
                    XCTAssertTrue(content.children.isEmpty)
                    XCTAssertTrue(trace.chromeInvalidationPasses.contains(pass + 1))
                } else {
                    XCTAssertEqual(trace.childReplacementPasses, [pass + 1])
                    try fixture.assertTailIsOffscreen()
                }
                let receipt = try settlementEditorReceipt(fixture.runtime)
                XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
                XCTAssertEqual(fixture.runtime.sceneRebuildCount, paints)
                XCTAssertNil(fixture.runtime.focusedNode)
                XCTAssertFalse(editor.isFocused)
                XCTAssertFalse(content.children.contains { $0.isTextInputCaret })
                XCTAssertEqual(viewport.scrollOffset, offset, accuracy: 0.001)
                XCTAssertEqual(viewport.scrollPresentedDelta, 0)
                XCTAssertEqual(fixture.model.selection, selection)
                XCTAssertEqual(editor.textInputSelection?.indices, .insertionPoint(text.count))
                fixture.assertNoBindingWrites()
            }
        }
    }

    func testQueuedChromeSettlementRejectsReplacedDetachedAndRetiredOwners() async throws {
        for retirement in SettlementEditorRetirement.allCases {
            try withFixture(focused: false) { fixture in
                fixture.rebuildStatus()
                let runtime = fixture.runtime
                let editor = try fixture.editor()
                let viewport = try fixture.viewport()
                let content = try fixture.content()
                let controller = try XCTUnwrap(editor.textInputController)
                let status = try fixture.element("settlement.status")
                let beforeConstruction = runtime.textInputReplayScopeRevision
                let candidateRoot = TextEditor(text: .constant(fixture.model.text))
                    .makeComponent(context: fixture.context).makeNode(runtime: runtime)
                let candidate = try XCTUnwrap(
                    settlementEditorNodes(in: candidateRoot).first { $0.accessibilityTraits.contains(.isTextInput) })
                let candidateController = try XCTUnwrap(candidate.textInputController)
                let candidateViewport = try XCTUnwrap(candidate.children.first { $0.scrollAxis == .vertical })
                let candidateContent = try XCTUnwrap(candidateViewport.children.first)
                XCTAssertNil(candidateRoot.parent)
                XCTAssertFalse(settlementEditorHasAncestor(candidate, runtime.root))
                XCTAssertFalse(settlementEditorHasAncestor(candidateContent, runtime.root))
                XCTAssertEqual(runtime.textInputReplayScopeRevision, beforeConstruction)
                let foreign = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 420, height: 700)))
                defer { foreign.stopRenderLifecycleCallbacks() }
                let trace = SettlementEditorLayoutTrace()
                try trace.install(on: editor, content: content, runtime: runtime)
                let originalChildren = content.children.map { ObjectIdentifier($0) }
                let pass = runtime.layoutPassID
                let paints = runtime.sceneRebuildCount
                var rootPasses: [UInt64] = []
                var didRetire = false
                var scopeAfterRetirement: UInt64?
                var foreignScopeAfterMove: UInt64?
                var betweenPassInvalidations: [UInt64] = []
                runtime.root.onLayout = { [weak runtime] _ in
                    guard let runtime else { return }
                    rootPasses.append(runtime.layoutPassID)
                    guard runtime.layoutPassID == pass + 2 else { return }
                    guard let before = scopeAfterRetirement, let now = runtime.textInputReplayScopeRevision else {
                        return XCTFail("The between-pass ownership witness must remain available.")
                    }
                    XCTAssertGreaterThanOrEqual(now, before)
                    if now >= before { betweenPassInvalidations.append(now - before) }
                }
                status.onLayout = { [weak runtime] _ in
                    guard let runtime, !didRetire else { return }
                    didRetire = true
                    XCTAssertTrue(runtime.isLayoutInProgress)
                    XCTAssertEqual(runtime.layoutPassID, pass + 1)
                    XCTAssertTrue(trace.childReplacementPasses.contains(pass + 1))
                    XCTAssertNotEqual(content.children.map { ObjectIdentifier($0) }, originalChildren)
                    // This is a real trailing sibling callback, after the
                    // editor AND viewport have refreshed and queued chrome.
                    switch retirement {
                    case .current: break
                    case .controller:
                        editor.textInputController = candidateController
                        XCTAssertTrue(editor.textInputController === candidateController)
                        XCTAssertTrue(settlementEditorHasAncestor(editor, runtime.root))
                    case .content:
                        viewport.removeAllChildren()
                        viewport.addChild(candidateContent)
                        XCTAssertTrue(editor.textInputController === controller)
                        XCTAssertNil(content.parent)
                        XCTAssertTrue(candidateContent.parent === viewport)
                        XCTAssertTrue(settlementEditorHasAncestor(candidateContent, runtime.root))
                    case .detached:
                        editor.removeFromParent()
                        XCTAssertNil(editor.parent)
                        XCTAssertFalse(settlementEditorHasAncestor(editor, runtime.root))
                    case .movedToOtherRuntime:
                        foreign.root.addChild(editor)
                        XCTAssertTrue(editor.parent === foreign.root)
                        XCTAssertTrue(settlementEditorHasAncestor(editor, foreign.root))
                        XCTAssertFalse(settlementEditorHasAncestor(editor, runtime.root))
                        XCTAssertTrue(editor.textInputController === controller)
                        XCTAssertTrue(viewport.parent === editor)
                        XCTAssertTrue(content.parent === viewport)
                        foreignScopeAfterMove = foreign.textInputReplayScopeRevision
                        XCTAssertNotNil(foreignScopeAfterMove)
                    case .terminal:
                        runtime.stopRenderLifecycleCallbacks()
                        XCTAssertFalse(runtime.permitsRetainedActionInvocation)
                        XCTAssertTrue(settlementEditorHasAncestor(editor, runtime.root))
                        XCTAssertTrue(editor.textInputController === controller)
                    }
                    scopeAfterRetirement = runtime.textInputReplayScopeRevision
                    XCTAssertNotNil(scopeAfterRetirement)
                }

                _ = try XCTUnwrap(runtime.resolvedLayoutFrame(of: runtime.root))

                XCTAssertTrue(didRetire)
                XCTAssertEqual(runtime.layoutPassID, pass + 2)
                XCTAssertEqual(rootPasses, [pass + 1, pass + 2])
                XCTAssertEqual(betweenPassInvalidations, [retirement == .current ? 1 : 0])
                XCTAssertEqual(runtime.sceneRebuildCount, paints)
                XCTAssertNil(runtime.focusedNode)
                if retirement == .movedToOtherRuntime {
                    XCTAssertEqual(foreign.textInputReplayScopeRevision, foreignScopeAfterMove)
                    XCTAssertEqual(foreign.layoutPassID, 0)
                    XCTAssertEqual(foreign.sceneRebuildCount, 0)
                }
                fixture.assertNoBindingWrites()
                // Inspect at follow-up ENTRY above: a replacement may validly
                // rebuild or queue its own work later in that pass. Terminal
                // revocation likewise does not forbid read-only layout proof.
                withExtendedLifetime((controller, content, candidateRoot, candidateController)) {}
            }
        }
    }

    func testContinuousGeometryMutationRefusesSettlementAfterBoundedFollowUp() async throws {
        try withFixture(focused: false) { fixture in
            let originalReceipt = try settlementEditorReceipt(fixture.runtime)
            fixture.rebuildStatus()
            let editor = try fixture.editor()
            let content = try fixture.content()
            let geometry = try fixture.statusFrameWrapper()
            let originalSize = try XCTUnwrap(geometry.preferredSize)
            let trace = SettlementEditorLayoutTrace()
            try trace.install(on: editor, content: content, runtime: fixture.runtime)
            var mutations: [Size] = []
            trace.afterRealLayout = { [weak geometry] in
                guard let geometry, let before = geometry.preferredSize else {
                    return XCTFail("The live frame wrapper must survive both layout passes.")
                }
                let after = Size(width: before.width, height: before.height + 1)
                geometry.preferredSize = after
                XCTAssertNotEqual(before, after)
                mutations.append(after)
            }
            let pass = fixture.runtime.layoutPassID
            let paints = fixture.runtime.sceneRebuildCount

            _ = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: fixture.runtime.root))

            XCTAssertEqual(fixture.runtime.layoutPassID, pass + 2)
            XCTAssertEqual(trace.passes, [pass + 1, pass + 2])
            XCTAssertEqual(trace.childReplacementPasses, [pass + 1])
            XCTAssertEqual(
                mutations,
                [
                    Size(width: originalSize.width, height: originalSize.height + 1),
                    Size(width: originalSize.width, height: originalSize.height + 2),
                ])
            XCTAssertEqual(fixture.runtime.sceneRebuildCount, paints)
            let scope = fixture.runtime.textInputReplayScopeRevision
            let textReads = fixture.model.textReads
            let selectionReads = fixture.model.selectionReads
            let contentRevision = fixture.runtime.contentRevision
            for _ in 0..<4 {
                guard case .unavailable = fixture.runtime.layoutSettlementStatus else {
                    return XCTFail("Continuing geometry changes must not earn a settled layout receipt.")
                }
                XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(originalReceipt))
                XCTAssertEqual(fixture.runtime.layoutPassID, pass + 2)
                XCTAssertEqual(trace.passes.count, 2)
                XCTAssertEqual(mutations.count, 2)
                XCTAssertEqual(fixture.runtime.textInputReplayScopeRevision, scope)
                XCTAssertEqual(fixture.model.textReads, textReads)
                XCTAssertEqual(fixture.model.selectionReads, selectionReads)
                XCTAssertEqual(fixture.runtime.contentRevision, contentRevision)
            }
            fixture.assertNoBindingWrites()
        }
    }
}
