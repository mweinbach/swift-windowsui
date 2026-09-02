import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Diagnostic companion that observes the original keyboard regression's layout traversal.
/// Snapshots read existing native scalars; they do not query, schedule, or change layout.
/// The original immediate assertions remain unchanged and may still fail.
@MainActor
final class ListKeyboardTraversalTests: XCTestCase {
    private static let viewport = IntSize(width: 260, height: 200)

    private func makeManagedRuntime<V: View>(
        _ view: V, size: IntSize = ListKeyboardTraversalTests.viewport
    ) -> MountedLazyListTestHost {
        MountedLazyListTestHost(size: Size(width: Double(size.width), height: Double(size.height))) {
            view.frame(width: Double(size.width), height: Double(size.height))
        }
    }

    private func row(_ index: Int, height: Double = 24) -> some View {
        Text("ROW \(index)")
            .frame(width: 220, height: height)
            .accessibilityIdentifier("virtual-row-\(index)")
    }

    @discardableResult
    private func settle(
        _ host: MountedLazyListTestHost, file: StaticString = #filePath, line: UInt = #line
    ) throws -> GPUIScene {
        for _ in 0..<16 {
            let scene = host.runtime.renderScene(at: 1)
            if !host.runtime.isDirty { return scene }
        }
        return try XCTUnwrap(
            nil as GPUIScene?, "Expected ordinary bounded List work to settle within 16 renders", file: file, line: line
        )
    }

    private struct RuntimeSnapshot {
        let visits: Int
        let pass: UInt64
        let reuse: Int
        let pending: Bool?
    }

    private struct NodeSnapshot {
        let visit: UInt64
        let descent: UInt64
        let dirty: UInt64
    }

    private func runtimeSnapshot(_ runtime: RetainedViewRuntime, content: ViewNode?) -> RuntimeSnapshot {
        RuntimeSnapshot(
            visits: runtime.layoutVisitCount, pass: runtime.layoutPassID, reuse: runtime.lastLayoutReuseCount,
            pending: content?.retainedLazyListAdapter?.hasUnresolvedWork)
    }

    private func nodeSnapshot(_ node: ViewNode?) -> NodeSnapshot? {
        guard let node else { return nil }
        return NodeSnapshot(
            visit: node.lastLayoutVisitPassID, descent: node.virtualizationDescentPassID,
            dirty: UInt64(node.subtreeDirtyFlags.rawValue))
    }

    private func pendingText(_ pending: Bool?) -> String {
        guard let pending else { return "unavailable" }
        return pending ? "true" : "false"
    }

    private func nodeText(_ snapshot: NodeSnapshot?) -> String {
        guard let snapshot else { return "unavailable" }
        return "visit=\(snapshot.visit) descent=\(snapshot.descent) dirty=\(snapshot.dirty)"
    }

    func testKeyboardSelectionCanRevealADeferredFarAwayRow() async throws {
        var selection: Int? = 0
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        let result = makeManagedRuntime(
            List(0..<1_000, id: \.self, selection: binding) { index in self.row(index) }
        )
        defer { result.close() }
        try settle(result)
        let source = try result.rowRoot("virtual-row-0")
        let sourceKeyDown = try XCTUnwrap(source.onKeyDown)
        XCTAssertNil(result.find("virtual-row-900"))
        XCTAssertNil(result.find("virtual-row-899"))

        // Source 0 is the real attached handler. Selection metadata, not an
        // imaginary mounted row 899, selects the distant next logical record.
        selection = 899
        // Read only the original source's short ancestor path before the key.
        let traceRuntime = result.runtime
        let traceRoot = traceRuntime.root
        var traceContent: ViewNode?
        var traceScroll: ViewNode?
        var traceWrapper: ViewNode?
        var traceAncestor: ViewNode? = source
        var traceAncestorCount = 0
        var traceReachedRoot = false
        for _ in 0..<16 {
            guard let ancestor = traceAncestor?.parent else { break }
            if traceAncestor === traceScroll { traceWrapper = ancestor }
            traceAncestor = ancestor
            traceAncestorCount += 1
            if traceContent == nil, ancestor.retainedLazyListAdapter != nil {
                traceContent = ancestor
            }
            if traceContent != nil, traceScroll == nil, ancestor.scrollAxis == .vertical {
                traceScroll = ancestor
            }
            if ancestor === traceRoot {
                traceReachedRoot = true
                break
            }
        }
        let traceWrapperIsRoot = traceWrapper === traceRoot
        let beforeRuntime = runtimeSnapshot(traceRuntime, content: traceContent)
        let beforeRoot = nodeSnapshot(traceRoot)
        let beforeWrapper = nodeSnapshot(traceWrapper)
        let beforeContent = nodeSnapshot(traceContent)
        let beforeScroll = nodeSnapshot(traceScroll)
        sourceKeyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
        // Capture scalars from those same nodes before formatting or assertions.
        let afterRuntime = runtimeSnapshot(traceRuntime, content: traceContent)
        let afterRoot = nodeSnapshot(traceRoot)
        let afterWrapper = nodeSnapshot(traceWrapper)
        let afterContent = nodeSnapshot(traceContent)
        let afterScroll = nodeSnapshot(traceScroll)
        print(
            "ListKeyboardTraversalTests pre visits=\(beforeRuntime.visits) pass=\(beforeRuntime.pass)"
                + " reuse=\(beforeRuntime.reuse) pending=\(pendingText(beforeRuntime.pending))"
                + " ancestors=\(traceAncestorCount) reachedRoot=\(traceReachedRoot) wrapperIsRoot=\(traceWrapperIsRoot)"
        )
        print(
            "ListKeyboardTraversalTests post visits=\(afterRuntime.visits) pass=\(afterRuntime.pass)"
                + " reuse=\(afterRuntime.reuse) pending=\(pendingText(afterRuntime.pending))"
        )
        print(
            "ListKeyboardTraversalTests root pre[\(nodeText(beforeRoot))] post[\(nodeText(afterRoot))]"
        )
        print(
            "ListKeyboardTraversalTests wrapper pre[\(nodeText(beforeWrapper))] post[\(nodeText(afterWrapper))]"
        )
        print(
            "ListKeyboardTraversalTests content pre[\(nodeText(beforeContent))] post[\(nodeText(afterContent))]"
        )
        print(
            "ListKeyboardTraversalTests scroll pre[\(nodeText(beforeScroll))] post[\(nodeText(afterScroll))]"
        )

        XCTAssertEqual(selection, 900)
        let target = try result.rowRoot("virtual-row-900")
        XCTAssertGreaterThan(try result.scrollContainer().scrollOffset, 20_000)
        XCTAssertTrue(result.runtime.focusedNode === target, "A supported distant navigation must focus immediately")
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)

        let targetKeyDown = try XCTUnwrap(target.onKeyDown)
        targetKeyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
        XCTAssertEqual(selection, 899)
        let previous = try result.rowRoot("virtual-row-899")
        XCTAssertTrue(result.runtime.focusedNode === previous)
        XCTAssertFalse(previous.isLayoutDeferredByVirtualization)
        try settle(result)
    }
}
