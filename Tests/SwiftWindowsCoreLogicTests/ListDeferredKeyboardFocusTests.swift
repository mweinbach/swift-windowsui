import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Additional public List coverage. These tests do not relax ordinary focus
/// eligibility or replace the existing ListVirtualizationTests oracles.
@MainActor
final class ListDeferredKeyboardFocusTests: XCTestCase {
    private static let viewport = IntSize(width: 260, height: 200)

    @MainActor
    private final class SelectionState {
        var value: Int?
        var reads = 0
        var writes: [Int?] = []
        var invalidations = 0
        var onSet: (() -> Void)?
        var onInvalidate: (() -> Void)?

        init(value: Int?) {
            self.value = value
        }

        var binding: Binding<Int?> {
            Binding(
                get: {
                    self.reads += 1
                    return self.value
                },
                set: { value in
                    self.value = value
                    self.writes.append(value)
                    self.onSet?()
                })
        }
    }

    @MainActor
    private struct Fixture {
        let runtime: RetainedViewRuntime
        let list: ViewNode
        let rows: [ViewNode]
        let alternate: ViewNode
        let selection: SelectionState
        let clock: RuntimeTestClock

        func row(_ index: Int) throws -> ViewNode {
            try XCTUnwrap(rows.dropFirst(index).first, "Expected selectable row \(index)")
        }

        func retire() {
            selection.onSet = nil
            selection.onInvalidate = nil
            list.onLayout = nil
            for row in rows {
                row.onFocusEnter = nil
                row.onFocusExit = nil
            }
            alternate.onFocusEnter = nil
            alternate.onFocusExit = nil
            runtime.onAccessibilityFocusChanged = nil
            runtime.stopRenderLifecycleCallbacks()
        }
    }

    private static func selectionList(_ selection: SelectionState, rowCount: Int) -> some View {
        List(0..<rowCount, id: \.self, selection: selection.binding) { index in
            Text("ROW \(index)")
                .frame(width: 220, height: 24)
        }
    }

    private static func context(for selection: SelectionState, size: IntSize) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { Size(width: Double(size.width), height: Double(size.height)) },
            invalidateHandler: {
                selection.invalidations += 1
                selection.onInvalidate?()
            })
    }

    private func makeFixture(
        rowCount: Int = 1000,
        selection initialSelection: Int? = 0,
        size: IntSize = ListDeferredKeyboardFocusTests.viewport
    ) throws -> Fixture {
        let logicalSize = Size(width: Double(size.width), height: Double(size.height))
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(origin: .zero, size: logicalSize)))
        let clock = RuntimeTestClock()
        runtime.clock = { clock.now }
        let selection = SelectionState(value: initialSelection)
        let list = Self.selectionList(selection, rowCount: rowCount)
            .makeComponent(context: Self.context(for: selection, size: size))
            .makeNode(runtime: runtime)
        list.frame = Rect(origin: .zero, size: logicalSize)
        // A sibling cannot become deferred when the List scrolls. It gives
        // reentrant focus a valid target without creating a native window.
        let alternate = ViewNode(
            frame: Rect(x: 240, y: 0, width: 20, height: 20),
            isFocusable: true)
        runtime.root.addChild(list)
        runtime.root.addChild(alternate)
        runtime.setRootSize(size)
        _ = runtime.renderScene(at: 0)
        let rows = list.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
        XCTAssertEqual(rows.count, rowCount)
        _ = try XCTUnwrap(rows.last)
        return Fixture(
            runtime: runtime, list: list, rows: rows, alternate: alternate,
            selection: selection, clock: clock)
    }

    private static func hasDeferredAncestor(_ target: ViewNode) -> Bool {
        var candidate: ViewNode? = target
        while let node = candidate {
            if node.isLayoutDeferredByVirtualization { return true }
            candidate = node.parent
        }
        return false
    }

    private static var downArrow: KeyboardEvent {
        KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue)
    }

    func testDeferredDestinationIsRealizedBeforeSynchronousFocusPublication() async throws {
        let fixture = try makeFixture()
        defer { fixture.retire() }
        let source = try fixture.row(899)
        let target = try fixture.row(900)
        XCTAssertTrue(Self.hasDeferredAncestor(target))
        fixture.selection.value = 899
        var deferredAtEntry: [Bool] = []
        var focusedAtEntry: [Bool] = []
        target.onFocusEnter = { [weak target, weak runtime = fixture.runtime] in
            guard let target else { return }
            deferredAtEntry.append(Self.hasDeferredAncestor(target))
            focusedAtEntry.append(runtime?.focusedNode === target)
        }
        let visitsBefore = fixture.runtime.layoutVisitCount
        let passesBefore = fixture.runtime.layoutPassID

        source.onKeyDown?(Self.downArrow)

        // No render or explicit layout query may repair these assertions.
        XCTAssertEqual(fixture.selection.value, 900)
        XCTAssertEqual(fixture.selection.writes, [900])
        XCTAssertEqual(fixture.selection.invalidations, 1)
        XCTAssertGreaterThan(fixture.list.scrollOffset, 20_000)
        XCTAssertTrue(fixture.runtime.focusedNode === target)
        XCTAssertTrue(target.isFocused)
        XCTAssertEqual(deferredAtEntry, [false])
        XCTAssertEqual(focusedAtEntry, [true])
        XCTAssertFalse(Self.hasDeferredAncestor(target))
        XCTAssertGreaterThan(fixture.runtime.layoutPassID, passesBefore)
        XCTAssertLessThanOrEqual(fixture.runtime.layoutPassID - passesBefore, 4)
        XCTAssertLessThan(fixture.runtime.maxLayoutVisitsInAnyPass, 240)
        XCTAssertLessThan(fixture.runtime.layoutVisitCount - visitsBefore, 960)
    }

    func testRealizedOffscreenDestinationFocusesBeforeItsReveal() async throws {
        let fixture = try makeFixture(rowCount: 6, selection: 3, size: IntSize(width: 260, height: 100))
        defer { fixture.retire() }
        let source = try fixture.row(3)
        let target = try fixture.row(4)
        XCTAssertFalse(fixture.list.layoutMode.virtualizesChildren)
        XCTAssertFalse(Self.hasDeferredAncestor(target))
        XCTAssertGreaterThan(target.resolvedFrame.origin.y, 100)
        fixture.runtime.requestFocus(source)
        XCTAssertTrue(fixture.runtime.focusedNode === source)
        let offsetBefore = fixture.list.scrollOffset
        var offsetsAtEntry: [Double] = []
        target.onFocusEnter = { [weak list = fixture.list] in
            if let list { offsetsAtEntry.append(list.scrollOffset) }
        }

        fixture.runtime.keyDown(Self.downArrow)

        XCTAssertEqual(fixture.selection.value, 4)
        XCTAssertEqual(fixture.selection.writes, [4])
        XCTAssertEqual(offsetsAtEntry, [offsetBefore], "Realized rows retain focus-before-reveal ordering")
        XCTAssertTrue(fixture.runtime.focusedNode === target)
        XCTAssertGreaterThan(fixture.list.scrollOffset, offsetBefore)
    }

    func testSynchronousRebuildFocusesTheRetainedRowAndRetiresTheOldHandler() async throws {
        let size = IntSize(width: 260, height: 100)
        let bounds = Rect(x: 0, y: 0, width: 260, height: 100)
        let runtime = RetainedViewRuntime(root: ViewNode(frame: bounds))
        let clock = RuntimeTestClock()
        runtime.clock = { clock.now }
        runtime.setRootSize(size)
        let host = ComponentHost(runtime: runtime)
        let selection = SelectionState(value: 3)
        let context = Self.context(for: selection, size: size)
        selection.onInvalidate = { [weak host] in host?.reload() }
        var buildCount = 0
        var freshRows: [ViewNode] = []
        var entries: [ObjectIdentifier] = []
        let component = Component { runtime in
            buildCount += 1
            let list = Self.selectionList(selection, rowCount: 6)
                .makeComponent(context: context).makeNode(runtime: runtime)
            list.frame = bounds
            let rows = list.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
            for row in rows {
                row.onFocusEnter = { [weak runtime] in
                    if let focused = runtime?.focusedNode { entries.append(ObjectIdentifier(focused)) }
                }
            }
            if buildCount > 1 { freshRows = rows }
            return list
        }
        host.setComponents { [component] }
        _ = runtime.renderScene(at: 0)
        let list = try XCTUnwrap(runtime.root.children.first)
        let rows = list.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
        let source = try XCTUnwrap(rows.dropFirst(3).first)
        let target = try XCTUnwrap(rows.dropFirst(4).first)
        XCTAssertFalse(list.layoutMode.virtualizesChildren)
        XCTAssertFalse(Self.hasDeferredAncestor(target))
        XCTAssertGreaterThan(target.resolvedFrame.origin.y, Double(size.height))
        let retiredHandler = try XCTUnwrap(source.onKeyDown)
        defer {
            selection.onSet = nil
            selection.onInvalidate = nil
            for row in rows + freshRows {
                row.onFocusEnter = nil
                row.onFocusExit = nil
            }
            runtime.stopRenderLifecycleCallbacks()
        }
        runtime.requestFocus(source)
        entries.removeAll()

        runtime.keyDown(Self.downArrow)

        let freshTarget = try XCTUnwrap(freshRows.dropFirst(4).first)
        let retainedRows = list.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
        XCTAssertEqual(buildCount, 2)
        XCTAssertEqual(selection.value, 4)
        XCTAssertEqual(selection.writes, [4])
        XCTAssertEqual(selection.invalidations, 1)
        XCTAssertTrue(runtime.root.children.first === list)
        XCTAssertTrue(retainedRows.dropFirst(4).first === target)
        XCTAssertFalse(freshTarget === target)
        XCTAssertFalse(runtime.focusedNode === freshTarget)
        XCTAssertTrue(runtime.focusedNode === target)
        XCTAssertEqual(entries, [ObjectIdentifier(target)])
        let readsAfterRebuild = selection.reads

        retiredHandler(Self.downArrow)

        XCTAssertEqual(selection.reads, readsAfterRebuild)
        XCTAssertEqual(selection.writes, [4])
        XCTAssertEqual(selection.invalidations, 1)
        XCTAssertEqual(buildCount, 2)
        XCTAssertTrue(runtime.focusedNode === target)

        // Reconciliation leaves pending layout, so the already realized row
        // keeps immediate focus while its single queued reveal waits for the
        // next ordinary render. Reading the stored receipt must not run layout.
        let passesBeforeReveal = runtime.layoutPassID
        _ = runtime.renderScene(at: clock.now)

        XCTAssertGreaterThan(list.scrollOffset, 0)
        XCTAssertLessThanOrEqual(runtime.layoutPassID - passesBeforeReveal, 2)
        XCTAssertEqual(selection.value, 4)
        XCTAssertEqual(selection.reads, readsAfterRebuild)
        XCTAssertEqual(selection.writes, [4])
        XCTAssertEqual(selection.invalidations, 1)
        XCTAssertEqual(buildCount, 2)
        XCTAssertTrue(runtime.focusedNode === target)
        XCTAssertEqual(entries, [ObjectIdentifier(target)])
        guard case .settled(let settlement) = runtime.layoutSettlementStatus else {
            XCTFail("The ordinary render must settle layout and drain the queued reveal")
            return
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(settlement))
    }

    func testSynchronousRebuildRevealsADeferredRetainedDestinationBeforeFocus() async throws {
        let size = Self.viewport
        let bounds = Rect(x: 0, y: 0, width: 260, height: 200)
        let runtime = RetainedViewRuntime(root: ViewNode(frame: bounds))
        let clock = RuntimeTestClock()
        runtime.clock = { clock.now }
        runtime.setRootSize(size)
        let host = ComponentHost(runtime: runtime)
        let selection = SelectionState(value: 899)
        let context = Self.context(for: selection, size: size)
        var pendingLayoutAfterRebuild: [Bool] = []
        selection.onInvalidate = { [weak host, weak runtime] in
            guard let host, let runtime else { return }
            host.reload()
            pendingLayoutAfterRebuild.append(runtime.hasPendingLayout)
        }
        var buildCount = 0
        var freshRows: [ViewNode] = []
        var entries: [ObjectIdentifier] = []
        var deferredAtEntry: [Bool] = []
        let component = Component { runtime in
            buildCount += 1
            let list = Self.selectionList(selection, rowCount: 1000)
                .makeComponent(context: context).makeNode(runtime: runtime)
            list.frame = bounds
            let rows = list.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
            for row in rows {
                row.onFocusEnter = { [weak runtime] in
                    guard let focused = runtime?.focusedNode else { return }
                    entries.append(ObjectIdentifier(focused))
                    deferredAtEntry.append(Self.hasDeferredAncestor(focused))
                }
            }
            if buildCount > 1 { freshRows = rows }
            return list
        }
        host.setComponents { [component] }
        _ = runtime.renderScene(at: 0)
        let list = try XCTUnwrap(runtime.root.children.first)
        let rows = list.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
        XCTAssertEqual(rows.count, 1000)
        let source = try XCTUnwrap(rows.first)
        let target = try XCTUnwrap(rows.dropFirst(900).first)
        let retiredHandler = try XCTUnwrap(source.onKeyDown)
        defer {
            selection.onSet = nil
            selection.onInvalidate = nil
            for row in rows + freshRows {
                row.onFocusEnter = nil
                row.onFocusExit = nil
            }
            runtime.stopRenderLifecycleCallbacks()
        }
        XCTAssertTrue(list.layoutMode.virtualizesChildren)
        XCTAssertFalse(Self.hasDeferredAncestor(source))
        XCTAssertGreaterThanOrEqual(source.resolvedFrame.origin.y, 0)
        XCTAssertLessThan(source.resolvedFrame.origin.y, Double(size.height))
        XCTAssertTrue(Self.hasDeferredAncestor(target))
        runtime.requestFocus(source)
        XCTAssertTrue(runtime.focusedNode === source)
        XCTAssertTrue(source.isFocused)
        entries.removeAll()
        deferredAtEntry.removeAll()

        runtime.keyDown(Self.downArrow)

        // No render or geometry query may make this rebuilt destination ready.
        let freshTarget = try XCTUnwrap(freshRows.dropFirst(900).first)
        let retainedRows = list.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
        XCTAssertEqual(buildCount, 2)
        XCTAssertEqual(selection.value, 900)
        XCTAssertEqual(selection.writes, [900])
        XCTAssertEqual(selection.invalidations, 1)
        XCTAssertEqual(pendingLayoutAfterRebuild, [true])
        XCTAssertTrue(runtime.root.children.first === list)
        XCTAssertEqual(retainedRows.count, 1000)
        XCTAssertTrue(retainedRows.dropFirst(900).first === target)
        XCTAssertFalse(freshTarget === target)
        XCTAssertFalse(runtime.focusedNode === freshTarget)
        XCTAssertGreaterThan(list.scrollOffset, 20_000)
        XCTAssertTrue(runtime.focusedNode === target)
        XCTAssertTrue(target.isFocused)
        XCTAssertFalse(Self.hasDeferredAncestor(target))
        XCTAssertEqual(entries, [ObjectIdentifier(target)])
        XCTAssertEqual(deferredAtEntry, [false])
        let readsAfterRebuild = selection.reads
        let offsetAfterRebuild = list.scrollOffset

        retiredHandler(Self.downArrow)

        XCTAssertEqual(selection.value, 900)
        XCTAssertEqual(selection.reads, readsAfterRebuild)
        XCTAssertEqual(selection.writes, [900])
        XCTAssertEqual(selection.invalidations, 1)
        XCTAssertEqual(pendingLayoutAfterRebuild, [true])
        XCTAssertEqual(buildCount, 2)
        XCTAssertEqual(list.scrollOffset, offsetAfterRebuild)
        XCTAssertTrue(runtime.focusedNode === target)
        XCTAssertEqual(entries, [ObjectIdentifier(target)])
        XCTAssertEqual(deferredAtEntry, [false])
    }

    func testFocusExitCannotReattachThePreparedDestinationAndPublishFocus() async throws {
        let fixture = try makeFixture(rowCount: 4)
        defer { fixture.retire() }
        let source = try fixture.row(0)
        let target = try fixture.row(1)
        fixture.runtime.requestFocus(source)
        let offsetBefore = fixture.list.scrollOffset
        let originalOrder = fixture.list.children.map(ObjectIdentifier.init)
        var exits = 0
        var entries = 0
        var notifications: [ObjectIdentifier] = []
        target.onFocusEnter = { entries += 1 }
        fixture.runtime.onAccessibilityFocusChanged = { node in
            if let node { notifications.append(ObjectIdentifier(node)) }
        }
        source.onFocusExit = { [weak list = fixture.list, weak target] in
            guard exits == 0, let list, let target else { return }
            exits += 1
            let retainedOrder = list.children
            target.removeFromParent()
            list.setChildren(retainedOrder)
        }

        fixture.runtime.keyDown(Self.downArrow)

        XCTAssertEqual(fixture.selection.value, 1)
        XCTAssertEqual(fixture.selection.writes, [1])
        XCTAssertEqual(fixture.selection.invalidations, 1)
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(entries, 0)
        XCTAssertTrue(notifications.isEmpty)
        XCTAssertTrue(target.parent === fixture.list)
        XCTAssertEqual(fixture.list.children.map(ObjectIdentifier.init), originalOrder)
        XCTAssertTrue(target.isFocusable)
        XCTAssertTrue(target.isFocusEnabled)
        XCTAssertFalse(Self.hasDeferredAncestor(target))
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertFalse(source.isFocused)
        XCTAssertFalse(target.isFocused)
        XCTAssertEqual(fixture.list.scrollOffset, offsetBefore)
    }

    func testNewerFocusFromTheBindingSetterStopsThePreparedReveal() async throws {
        let fixture = try makeFixture()
        defer { fixture.retire() }
        let source = try fixture.row(899)
        let target = try fixture.row(900)
        fixture.runtime.requestFocus(try fixture.row(0))
        fixture.selection.value = 899
        let offsetBefore = fixture.list.scrollOffset
        var entries = 0
        target.onFocusEnter = { entries += 1 }
        fixture.selection.onSet = { [weak runtime = fixture.runtime, weak alternate = fixture.alternate] in
            runtime?.requestFocus(alternate)
        }

        source.onKeyDown?(Self.downArrow)

        XCTAssertEqual(fixture.selection.value, 900)
        XCTAssertEqual(fixture.selection.writes, [900])
        XCTAssertEqual(fixture.selection.invalidations, 1, "The accepted binding write keeps its invalidation")
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
        XCTAssertTrue(fixture.alternate.isFocused)
        XCTAssertEqual(entries, 0)
        XCTAssertFalse(target.isFocused)
        XCTAssertEqual(fixture.list.scrollOffset, offsetBefore)
    }

    func testPostRevealLayoutFocusWinsWithoutRollingBackTheAcceptedOffset() async throws {
        let fixture = try makeFixture()
        defer { fixture.retire() }
        let source = try fixture.row(899)
        let target = try fixture.row(900)
        fixture.selection.value = 899
        XCTAssertNil(fixture.runtime.focusedNode)
        var offsetsAtRedirect: [Double] = []
        var entries = 0
        target.onFocusEnter = { entries += 1 }
        fixture.list.onLayout = {
            [weak runtime = fixture.runtime, weak list = fixture.list, weak alternate = fixture.alternate] _ in
            guard offsetsAtRedirect.isEmpty, let runtime, let list, let alternate, list.scrollOffset > 20_000 else {
                return
            }
            offsetsAtRedirect.append(list.scrollOffset)
            runtime.requestFocus(alternate)
        }

        source.onKeyDown?(Self.downArrow)

        let acceptedOffset = try XCTUnwrap(offsetsAtRedirect.first)
        XCTAssertEqual(offsetsAtRedirect.count, 1)
        XCTAssertEqual(fixture.selection.value, 900)
        XCTAssertEqual(fixture.selection.writes, [900])
        XCTAssertEqual(fixture.selection.invalidations, 1)
        XCTAssertGreaterThan(acceptedOffset, 20_000)
        XCTAssertEqual(fixture.list.scrollOffset, acceptedOffset, accuracy: 0.0001)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
        XCTAssertTrue(fixture.alternate.isFocused)
        XCTAssertEqual(entries, 0)
        XCTAssertFalse(target.isFocused)
    }

    func testRestoringARowFocusRoleDoesNotReviveItsPreparedOrEscapedAction() async throws {
        for changesFocusable in [true, false] {
            let fixture = try makeFixture(rowCount: 6, selection: 3, size: IntSize(width: 260, height: 100))
            defer { fixture.retire() }
            let source = try fixture.row(3)
            let target = try fixture.row(4)
            let escapedTargetHandler = try XCTUnwrap(target.onKeyDown)
            fixture.runtime.requestFocus(source)
            let offsetBefore = fixture.list.scrollOffset
            var entries = 0
            target.onFocusEnter = { entries += 1 }
            fixture.selection.onSet = { [weak target] in
                guard let target else { return }
                if changesFocusable {
                    target.isFocusable = false
                    target.isFocusable = true
                } else {
                    target.isFocusEnabled = false
                    target.isFocusEnabled = true
                }
            }

            fixture.runtime.keyDown(Self.downArrow)

            XCTAssertEqual(fixture.selection.value, 4)
            XCTAssertEqual(fixture.selection.writes, [4])
            XCTAssertEqual(fixture.selection.invalidations, 1)
            XCTAssertTrue(target.isFocusable)
            XCTAssertTrue(target.isFocusEnabled)
            XCTAssertTrue(fixture.runtime.focusedNode === source)
            XCTAssertEqual(entries, 0)
            XCTAssertFalse(target.isFocused)
            XCTAssertEqual(fixture.list.scrollOffset, offsetBefore)
            let readsAfterRevocation = fixture.selection.reads

            escapedTargetHandler(Self.downArrow)

            XCTAssertEqual(fixture.selection.reads, readsAfterRevocation)
            XCTAssertEqual(fixture.selection.writes, [4])
            XCTAssertEqual(fixture.selection.invalidations, 1)
            XCTAssertTrue(fixture.runtime.focusedNode === source)
        }
    }

    func testRuntimeCloseBoundaryRevokesPreparedAndEscapedListActions() async throws {
        let fixture = try makeFixture(rowCount: 6, selection: 3, size: IntSize(width: 260, height: 100))
        defer { fixture.retire() }
        let source = try fixture.row(3)
        let target = try fixture.row(4)
        let escapedTargetHandler = try XCTUnwrap(target.onKeyDown)
        let escapedActivation = try XCTUnwrap(target.onActivate)
        fixture.runtime.requestFocus(source)
        let focusRevisionBefore = fixture.runtime.presentationFocusRevision
        let offsetBefore = fixture.list.scrollOffset
        var entries = 0
        target.onFocusEnter = { entries += 1 }
        fixture.selection.onSet = { [weak runtime = fixture.runtime] in
            // This is the runtime revocation used by host close. It does not
            // create/destroy an HWND or perform native focus cleanup here.
            runtime?.stopRenderLifecycleCallbacks()
        }

        fixture.runtime.keyDown(Self.downArrow)

        XCTAssertEqual(fixture.selection.value, 4)
        XCTAssertEqual(fixture.selection.writes, [4])
        XCTAssertEqual(fixture.selection.invalidations, 1)
        XCTAssertTrue(fixture.runtime.focusedNode === source)
        XCTAssertEqual(fixture.runtime.presentationFocusRevision, focusRevisionBefore)
        XCTAssertEqual(entries, 0)
        XCTAssertFalse(target.isFocused)
        XCTAssertEqual(fixture.list.scrollOffset, offsetBefore)
        let readsAfterClose = fixture.selection.reads

        escapedTargetHandler(Self.downArrow)
        escapedActivation()

        XCTAssertEqual(fixture.selection.reads, readsAfterClose)
        XCTAssertEqual(fixture.selection.writes, [4])
        XCTAssertEqual(fixture.selection.invalidations, 1)
        XCTAssertTrue(fixture.runtime.focusedNode === source)
    }

    func testAnimatedDeferredRevealKeepsItsScrollIntentWithoutPrematureFocus() async throws {
        let fixture = try makeFixture()
        defer { fixture.retire() }
        let source = try fixture.row(899)
        let target = try fixture.row(900)
        fixture.selection.value = 899
        let offsetBefore = fixture.list.resolvedScrollOffset
        var deferredAtEntry: [Bool] = []
        target.onFocusEnter = { [weak target] in
            if let target { deferredAtEntry.append(Self.hasDeferredAncestor(target)) }
        }

        withAnimation(.linear(duration: 0.6)) {
            source.onKeyDown?(Self.downArrow)
        }

        let acceptedOffset = fixture.list.scrollOffset
        XCTAssertEqual(fixture.selection.value, 900)
        XCTAssertEqual(fixture.selection.writes, [900])
        XCTAssertEqual(fixture.selection.invalidations, 1)
        XCTAssertGreaterThan(acceptedOffset, 20_000)
        XCTAssertEqual(fixture.list.resolvedScrollOffset, offsetBefore, accuracy: 0.0001)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        XCTAssertTrue(Self.hasDeferredAncestor(target))
        XCTAssertFalse(fixture.runtime.focusedNode === target)
        XCTAssertFalse(target.isFocused)
        XCTAssertTrue(deferredAtEntry.isEmpty)

        fixture.clock.now = 0.3
        _ = fixture.runtime.tickAnimations(at: fixture.clock.now)
        _ = fixture.runtime.renderScene(at: fixture.clock.now)
        XCTAssertEqual(fixture.list.scrollOffset, acceptedOffset, accuracy: 0.0001)
        XCTAssertGreaterThan(fixture.list.resolvedScrollOffset, offsetBefore)
        XCTAssertLessThan(fixture.list.resolvedScrollOffset, acceptedOffset)
        if Self.hasDeferredAncestor(target) {
            XCTAssertFalse(fixture.runtime.focusedNode === target)
        }

        fixture.clock.now = 0.6
        _ = fixture.runtime.tickAnimations(at: fixture.clock.now)
        _ = fixture.runtime.renderScene(at: fixture.clock.now)
        XCTAssertEqual(fixture.list.scrollOffset, acceptedOffset, accuracy: 0.0001)
        XCTAssertEqual(fixture.list.resolvedScrollOffset, acceptedOffset, accuracy: 0.0001)
        XCTAssertFalse(Self.hasDeferredAncestor(target))
        XCTAssertTrue(deferredAtEntry.allSatisfy { !$0 })
        // Deferred focus completion after animation is not implemented by
        // this change. Do not make perpetual lack of focus a compatibility
        // oracle: the accepted scroll must finish, and any focus must be safe.
    }
}
