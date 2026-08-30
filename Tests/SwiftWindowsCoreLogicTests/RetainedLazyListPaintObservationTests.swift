import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedLazyListPaintObservationTests: XCTestCase {
    func testOriginalPoseIsPreservedAndAnEqualIdentityWriteRevokesItsWitness() async throws {
        let root = ViewNode()
        let node = ViewNode()
        node.opacity = 0.65
        node.transform.scaleX = 1.25
        node.transform.translationX = 8
        root.addChild(node)
        let observation = try XCTUnwrap(RetainedLazyListPaintObservation(root: root))
        let entry = try XCTUnwrap(observation.entry(for: node))

        node.opacity = 0.2
        node.transform.scaleX = 2
        node.transform.translationX = -4
        XCTAssertEqual(entry.initialOpacity, 0.65)
        XCTAssertEqual(entry.initialTransform.scaleX, 1.25)
        XCTAssertEqual(entry.initialTransform.translationX, 8)

        let sameIdentity = node.retainedViewIdentity
        node.retainedViewIdentity = sameIdentity
        XCTAssertFalse(entry.isCurrent)
        XCTAssertFalse(observation.isCurrent)
        XCTAssertNil(observation.entry(for: node))
    }

    func testSourceOrderChangeInvalidatesTheObservationWithoutRevokingAttachments() async throws {
        let root = ViewNode()
        let first = ViewNode()
        let second = ViewNode()
        root.setChildren([first, second])
        let observation = try XCTUnwrap(RetainedLazyListPaintObservation(root: root))
        let firstEntry = try XCTUnwrap(observation.entry(for: first))
        let secondEntry = try XCTUnwrap(observation.entry(for: second))

        root.setChildren([second, first])

        XCTAssertTrue(firstEntry.isCurrent)
        XCTAssertTrue(secondEntry.isCurrent)
        XCTAssertFalse(observation.isCurrent)
    }

    func testObservationAndExportedEntryDoNotKeepANodeAlive() async throws {
        let (observation, entry) = try makeUnownedPaintObservation()

        XCTAssertNil(entry.node)
        XCTAssertFalse(entry.isCurrent)
        XCTAssertFalse(observation.isCurrent)
    }

    func testAlphaProofUsesOriginalStoredPaintInputsRatherThanLaterSanitizedValues() async throws {
        let node = ViewNode(backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 2))
        let observation = try XCTUnwrap(RetainedLazyListPaintObservation(root: node))
        let entry = try XCTUnwrap(observation.entry(for: node))
        XCTAssertFalse(entry.permitsInheritedOpacityProjection)
        node.backgroundColor = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        XCTAssertFalse(entry.permitsInheritedOpacityProjection)
        let current = try XCTUnwrap(RetainedLazyListPaintObservation(root: node))
        XCTAssertTrue(try XCTUnwrap(current.entry(for: node)).permitsInheritedOpacityProjection)
    }

    func testCanvasAlphaCannotRecoverFromAnUnsupportedOccurrenceWithoutANewAssignment() async throws {
        let node = ViewNode()
        node.canvasDraw = { _, _ in }
        let original = try XCTUnwrap(node.captureLazyListCanvasPaintAlpha())
        let rect = Rect(x: 0, y: 0, width: 8, height: 8)
        XCTAssertFalse(original.permitsProjection)
        original.record([.fillRect(rect, Color(red: 1, green: 0, blue: 0, alpha: 2))])
        original.record([.fillRect(rect, .white)])
        XCTAssertFalse(original.permitsProjection)
        XCTAssertTrue(node.captureLazyListCanvasPaintAlpha() === original)

        node.canvasDraw = { _, _ in }
        let replacement = try XCTUnwrap(node.captureLazyListCanvasPaintAlpha())
        XCTAssertFalse(replacement === original)
        original.record([.fillRect(rect, .white)])
        XCTAssertFalse(replacement.permitsProjection)
        replacement.record([.fillRect(rect, .white)])
        XCTAssertTrue(replacement.permitsProjection)
        XCTAssertFalse(original.permitsProjection)
    }

    func testSceneCanvasReplacingItsCallbackCannotCertifyTheReplacement() async throws {
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 16, height: 16))
        let runtime = RetainedViewRuntime(root: node)
        defer { runtime.stopRenderLifecycleCallbacks() }
        var originalCalls = 0
        var replacementCalls = 0
        node.canvasDraw = { [weak node] context, size in
            originalCalls += 1
            node?.canvasDraw = { context, size in
                replacementCalls += 1
                context.fill(Rect(origin: .zero, size: size), with: .color(.white))
            }
            context.fill(Rect(origin: .zero, size: size), with: .color(.white))
        }
        let original = try XCTUnwrap(node.captureLazyListCanvasPaintAlpha())

        _ = runtime.renderScene()

        XCTAssertEqual(originalCalls, 1)
        XCTAssertEqual(replacementCalls, 0)
        XCTAssertTrue(original.permitsProjection)
        let replacement = try XCTUnwrap(node.captureLazyListCanvasPaintAlpha())
        XCTAssertFalse(replacement === original)
        XCTAssertFalse(replacement.permitsProjection)
        // A separate ordinary paint can establish the replacement's output.
        node.backgroundColor = .clear
        _ = runtime.renderScene()
        XCTAssertEqual(originalCalls, 1)
        XCTAssertEqual(replacementCalls, 1)
        XCTAssertTrue(replacement.permitsProjection)
    }

    func testFrameCanvasReturningFromADetachedAttachmentCannotCertifyItsReinsertion() async throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 32, height: 32))
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 16, height: 16))
        root.addChild(node)
        let runtime = RetainedViewRuntime(root: root)
        defer { runtime.stopRenderLifecycleCallbacks() }
        var calls = 0
        node.canvasDraw = { [weak root, weak node] context, size in
            calls += 1
            if calls == 1, let root, let node {
                root.removeChild(node)
                root.addChild(node)
            }
            context.fill(Rect(origin: .zero, size: size), with: .color(.white))
        }
        let original = try XCTUnwrap(node.captureLazyListCanvasPaintAlpha())
        let attachment = node.captureLazyListAttachmentProof()

        _ = runtime.renderFrame()

        XCTAssertEqual(calls, 1)
        XCTAssertFalse(attachment.isCurrent)
        XCTAssertTrue(original.permitsProjection)
        let replacement = try XCTUnwrap(node.captureLazyListCanvasPaintAlpha())
        XCTAssertFalse(replacement === original)
        XCTAssertFalse(replacement.permitsProjection)
    }
}

@MainActor
private func makeUnownedPaintObservation() throws -> (
    RetainedLazyListPaintObservation, RetainedLazyListPaintObservation.Entry
) {
    let node = ViewNode()
    let observation = try XCTUnwrap(RetainedLazyListPaintObservation(root: node))
    return (observation, try XCTUnwrap(observation.entry(for: node)))
}
