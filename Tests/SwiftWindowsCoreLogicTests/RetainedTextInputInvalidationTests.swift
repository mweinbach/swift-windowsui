import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
private final class LayoutInvalidationController: RetainedTextInputController {
    func attach(to node: ViewNode) {}
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func detach(from node: ViewNode) {}
}

@MainActor
private final class TextInputInvalidationFixture {
    let controller = LayoutInvalidationController()
    let node: ViewNode
    let runtime: RetainedViewRuntime
    private(set) var layoutCalls = 0

    init() {
        let node = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 40), backgroundColor: .white)
        self.node = node
        node.accessibilityTraits = .isTextInput
        node.textInputController = controller
        runtime = RetainedViewRuntime(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 240, height: 120),
                isHitTestVisible: false, children: [node]))
        runtime.clock = { 0 }
        node.onLayout = { [weak self] _ in self?.layoutCalls += 1 }
    }

    func render(usesScene: Bool) {
        if usesScene {
            _ = runtime.renderScene()
        } else {
            _ = runtime.renderFrame()
        }
    }

    func assertClean(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(runtime.isDirty, file: file, line: line)
        XCTAssertFalse(runtime.hasPendingLayout, file: file, line: line)
        XCTAssertTrue(runtime.root.subtreeDirtyFlags.isEmpty, file: file, line: line)
        XCTAssertTrue(node.subtreeDirtyFlags.isEmpty, file: file, line: line)
    }
}

private enum TextInputInvalidationFixtureError: Error {
    case missingReceipt
}

@MainActor
private func textInputInvalidationReceipt(
    _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
) throws -> RetainedLayoutSettlementReceipt {
    guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
        XCTFail("Expected settled layout from an ordinary render.", file: file, line: line)
        throw TextInputInvalidationFixtureError.missingReceipt
    }
    return receipt
}

@MainActor
final class RetainedTextInputInvalidationTests: XCTestCase {
    func testCurrentCachedInputQueuesLayoutWithoutCallingLayoutUntilTheNextRender() async throws {
        for usesScene in [false, true] {
            let fixture = TextInputInvalidationFixture()
            fixture.render(usesScene: usesScene)
            fixture.assertClean()
            XCTAssertNotNil(fixture.node.cachedLayoutKey)
            let receipt = try textInputInvalidationReceipt(fixture.runtime)
            let pass = fixture.runtime.layoutPassID
            let revision = fixture.runtime.contentRevision
            let calls = fixture.layoutCalls
            XCTAssertGreaterThan(calls, 0)

            fixture.render(usesScene: usesScene)
            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
            XCTAssertEqual(fixture.runtime.contentRevision, revision)
            XCTAssertEqual(fixture.layoutCalls, calls)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))

            fixture.runtime.invalidateTextInputLayout(for: fixture.node, controller: fixture.controller)

            XCTAssertEqual(fixture.runtime.dirtyFlags, .layout)
            XCTAssertTrue(fixture.runtime.hasPendingLayout)
            XCTAssertTrue(fixture.node.subtreeDirtyFlags.contains(.layout))
            XCTAssertTrue(fixture.runtime.root.subtreeDirtyFlags.contains(.layout))
            XCTAssertFalse(fixture.runtime.isLayoutInProgress)
            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
            XCTAssertEqual(fixture.runtime.contentRevision, revision)
            XCTAssertEqual(fixture.layoutCalls, calls)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
            guard case .unsettled = fixture.runtime.layoutSettlementStatus else {
                return XCTFail("An invalidated receipt cannot remain settled before the next layout.")
            }
            XCTAssertEqual(fixture.layoutCalls, calls, "Reading settlement must not run the queued callback.")

            fixture.render(usesScene: usesScene)

            XCTAssertEqual(fixture.layoutCalls, calls + 1)
            XCTAssertEqual(fixture.runtime.layoutPassID, pass + 1)
            XCTAssertEqual(fixture.runtime.contentRevision, revision + 1)
            fixture.assertClean()
            let refreshed = try textInputInvalidationReceipt(fixture.runtime)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(refreshed))
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
            fixture.render(usesScene: usesScene)
            XCTAssertEqual(fixture.layoutCalls, calls + 1)
            XCTAssertEqual(fixture.runtime.contentRevision, revision + 1)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(refreshed))
        }
    }

    func testForeignDetachedAndReplacedControllersLeaveCleanOwnersAndReceiptsUnchanged() async throws {
        for usesScene in [false, true] {
            let local = TextInputInvalidationFixture()
            let foreign = TextInputInvalidationFixture()
            let detached = TextInputInvalidationFixture()
            let fixtures = [local, foreign, detached]
            for fixture in fixtures { fixture.render(usesScene: usesScene) }
            detached.node.removeFromParent()
            detached.render(usesScene: usesScene)
            XCTAssertNil(detached.node.parent)
            XCTAssertTrue(detached.node.textInputController === detached.controller)
            let replacement = LayoutInvalidationController()
            local.node.textInputController = replacement
            XCTAssertTrue(local.node.textInputController === replacement)
            for fixture in fixtures { fixture.assertClean() }
            let receipts = try fixtures.map { try textInputInvalidationReceipt($0.runtime) }
            let passes = fixtures.map { $0.runtime.layoutPassID }
            let revisions = fixtures.map { $0.runtime.contentRevision }
            let callbacks = fixtures.map { $0.layoutCalls }
            let staleTargets = [
                (foreign.node, foreign.controller),
                (detached.node, detached.controller),
                (local.node, local.controller),
            ]

            for (node, controller) in staleTargets {
                local.runtime.invalidateTextInputLayout(for: node, controller: controller)

                for (index, fixture) in fixtures.enumerated() {
                    fixture.assertClean()
                    XCTAssertEqual(fixture.runtime.layoutPassID, passes[index])
                    XCTAssertEqual(fixture.runtime.contentRevision, revisions[index])
                    XCTAssertEqual(fixture.layoutCalls, callbacks[index])
                    XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipts[index]))
                }
            }
        }
    }

    func testTerminalRuntimeRejectsItsStillAttachedCurrentInputWithoutInvalidation() async throws {
        for usesScene in [false, true] {
            let fixture = TextInputInvalidationFixture()
            fixture.render(usesScene: usesScene)
            let receipt = try textInputInvalidationReceipt(fixture.runtime)
            fixture.runtime.stopRenderLifecycleCallbacks()
            fixture.assertClean()
            XCTAssertTrue(fixture.node.textInputController === fixture.controller)
            XCTAssertTrue(fixture.node.parent === fixture.runtime.root)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
            let pass = fixture.runtime.layoutPassID
            let revision = fixture.runtime.contentRevision
            let callbacks = fixture.layoutCalls

            fixture.runtime.invalidateTextInputLayout(for: fixture.node, controller: fixture.controller)

            fixture.assertClean()
            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
            XCTAssertEqual(fixture.runtime.contentRevision, revision)
            XCTAssertEqual(fixture.layoutCalls, callbacks)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
        }
    }

    func testPaintCallbackInvalidationPreservesNodeAndRuntimeFlagsUntilTheFollowingPass() async throws {
        for usesScene in [false, true] {
            let fixture = TextInputInvalidationFixture()
            let trigger = ViewNode(
                frame: Rect(x: 130, y: 10, width: 40, height: 40), backgroundColor: .black)
            var invalidatesDuringPaint = false
            var requests = 0
            trigger.canvasDraw = { [weak fixture] _, _ in
                guard invalidatesDuringPaint, let fixture else { return }
                invalidatesDuringPaint = false
                requests += 1
                let pass = fixture.runtime.layoutPassID
                let callbacks = fixture.layoutCalls
                fixture.runtime.invalidateTextInputLayout(for: fixture.node, controller: fixture.controller)
                XCTAssertEqual(fixture.runtime.layoutPassID, pass)
                XCTAssertEqual(fixture.layoutCalls, callbacks, "The paint callback must not recursively run layout.")
                XCTAssertTrue(fixture.node.subtreeDirtyFlags.contains(.layout))
            }
            fixture.runtime.root.addChild(trigger)
            fixture.render(usesScene: usesScene)
            fixture.assertClean()
            XCTAssertEqual(requests, 0)
            XCTAssertNotNil(fixture.node.cachedLayoutKey)
            let beforePaint = try textInputInvalidationReceipt(fixture.runtime)

            invalidatesDuringPaint = true
            trigger.backgroundColor = .red
            XCTAssertTrue(
                fixture.runtime.isLayoutSettlementReceiptCurrent(beforePaint),
                "The paint-only trigger must not itself invalidate geometry.")
            fixture.render(usesScene: usesScene)

            XCTAssertEqual(requests, 1)
            XCTAssertEqual(fixture.runtime.dirtyFlags, .layout)
            XCTAssertTrue(fixture.runtime.hasPendingLayout)
            XCTAssertTrue(fixture.node.subtreeDirtyFlags.contains(.layout))
            XCTAssertTrue(fixture.runtime.root.subtreeDirtyFlags.contains(.layout))
            guard case .unsettled = fixture.runtime.layoutSettlementStatus else {
                return XCTFail("Paint-time layout invalidation must survive the outer render's cleanup.")
            }
            let passAfterPaint = fixture.runtime.layoutPassID
            let revisionAfterPaint = fixture.runtime.contentRevision
            let callbacksAfterPaint = fixture.layoutCalls

            fixture.render(usesScene: usesScene)

            XCTAssertEqual(requests, 1)
            XCTAssertEqual(fixture.runtime.layoutPassID, passAfterPaint + 1)
            XCTAssertEqual(fixture.runtime.contentRevision, revisionAfterPaint + 1)
            XCTAssertEqual(fixture.layoutCalls, callbacksAfterPaint + 1)
            fixture.assertClean()
            let refreshed = try textInputInvalidationReceipt(fixture.runtime)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(refreshed))
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(beforePaint))
            fixture.render(usesScene: usesScene)
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(fixture.layoutCalls, callbacksAfterPaint + 1)
            XCTAssertEqual(fixture.runtime.contentRevision, revisionAfterPaint + 1)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(refreshed))
        }
    }
}
