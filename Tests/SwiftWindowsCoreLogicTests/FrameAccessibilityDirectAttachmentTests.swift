import CUIAInterop
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class FrameAccessibilityDirectAttachmentTests: XCTestCase {
    func testDirectAddChildPublishesPublicFramedButtonBeforeFirstRead() async throws {
        let runtime = frameAddChildRuntime()
        defer { frameAddChildClose(runtime) }
        var activations = 0
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 120) }, invalidateHandler: {})
        let frame = Button("Control") { activations += 1 }
            .frame(width: 120, height: 32)
            .accessibilityLabel("Framed control")
            .accessibilityIdentifier("subject")
            .makeComponent(context: context).makeNode(runtime: runtime)
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: frame))

        runtime.root.addChild(frame)

        let request = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertTrue(request.semanticNode === frame.accessibilityDeclaredFrameContent)
        XCTAssertTrue(frame.parent === runtime.root)
        XCTAssertTrue(runtime.root.children.contains { $0 === frame })
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let first = try frameAddChildSnapshot(source)
        XCTAssertEqual(first.name, "Framed control")
        XCTAssertEqual(first.controlType, Int32(SWU_UIA_CONTROL_TYPE_BUTTON))
        XCTAssertTrue(first.hasDefaultAction)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: first.id))
        XCTAssertEqual(activations, 1)

        _ = runtime.renderFrame()
        XCTAssertEqual(try frameAddChildSnapshot(source).id, first.id)
        XCTAssertTrue(try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame)).element === request.element)
        XCTAssertTrue(request.isCurrent(in: runtime))
    }

    func testDirectAddChildPublishesNestedFramesInsideAnOrdinaryDetachedContainer() async throws {
        let runtime = frameAddChildRuntime()
        defer { frameAddChildClose(runtime) }
        let inner = frameAddChildNativeFrame()
        let outer = ViewNode(frame: Rect(x: 0, y: 0, width: 140, height: 40), children: [inner])
        outer.declareAccessibilityFrameContent(inner)
        outer.accessibilityLabel = "Outer label"
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 50), children: [outer])
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: outer))
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: inner))

        runtime.root.addChild(container)

        let request = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: outer))
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertTrue(try XCTUnwrap(runtime.accessibilitySemanticRequest(for: inner)).element === request.element)
        XCTAssertTrue(request.semanticNode === inner.accessibilityDeclaredFrameContent)
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: container))
        XCTAssertTrue(outer.parent === container)
        XCTAssertTrue(inner.parent === outer)
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        XCTAssertEqual(try frameAddChildSnapshot(source).name, "Outer label")
        XCTAssertEqual(source.uiaElementSnapshots().filter { $0.automationID == "subject" }.count, 1)
    }

    func testAddingDeclaredContentPublishesAnAlreadyAttachedFrame() async throws {
        let runtime = frameAddChildRuntime()
        defer { frameAddChildClose(runtime) }
        let content = ViewNode(frame: Rect(x: 0, y: 0, width: 60, height: 24))
        content.accessibilityTraits = [.isButton]
        content.accessibilityLabel = "Content"
        let frame = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 32))
        frame.declareAccessibilityFrameContent(content)
        frame.accessibilityLabel = "Declared content"
        frame.accessibilityIdentifier = "subject"
        runtime.root.addChild(frame)
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertNil(content.parent)

        frame.addChild(content)

        let request = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertTrue(request.semanticNode === content)
        XCTAssertTrue(content.parent === frame)
        XCTAssertEqual(frame.children.count, 1)
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let first = try frameAddChildSnapshot(source)
        XCTAssertEqual(first.name, "Declared content")
        XCTAssertEqual(first.controlType, Int32(SWU_UIA_CONTROL_TYPE_BUTTON))

        frame.addChild(ViewNode(frame: Rect(x: 80, y: 0, width: 10, height: 10)))
        _ = runtime.renderFrame()
        XCTAssertEqual(try frameAddChildSnapshot(source).id, first.id)
        XCTAssertTrue(try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame)).element === request.element)
        XCTAssertTrue(request.isCurrent(in: runtime))
    }

    func testDetachAndSameParentReattachmentNeverReviveTheOriginalIdentity() async throws {
        let runtime = frameAddChildRuntime()
        defer { frameAddChildClose(runtime) }
        var activations = 0
        let frame = frameAddChildNativeFrame { activations += 1 }
        runtime.root.addChild(frame)
        let original = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let originalID = try frameAddChildSnapshot(source).id
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: originalID))
        XCTAssertEqual(activations, 1)

        frame.removeFromParent()

        XCTAssertNil(frame.parent)
        XCTAssertFalse(original.isCurrent(in: runtime))
        XCTAssertFalse(original.isStructurallyCurrent(in: runtime))
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: originalID))
        XCTAssertEqual(activations, 1)

        runtime.root.addChild(frame)

        let replacement = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertTrue(replacement.isCurrent(in: runtime))
        XCTAssertFalse(replacement.element === original.element)
        XCTAssertFalse(original.isCurrent(in: runtime))
        _ = runtime.renderFrame()
        let replacementID = try frameAddChildSnapshot(source).id
        XCTAssertNotEqual(replacementID, originalID)
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: originalID))
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: replacementID))
        XCTAssertEqual(activations, 2)
    }

    func testReparentingRetiresEachOriginalPathAndPublishesTheNewPath() async throws {
        let runtime = frameAddChildRuntime()
        defer { frameAddChildClose(runtime) }
        let left = ViewNode(frame: Rect(x: 0, y: 0, width: 90, height: 50))
        let right = ViewNode(frame: Rect(x: 100, y: 0, width: 90, height: 50))
        runtime.root.addChild(left)
        runtime.root.addChild(right)
        var activations = 0
        let frame = frameAddChildNativeFrame { activations += 1 }
        left.addChild(frame)
        let leftRequest = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let leftID = try frameAddChildSnapshot(source).id

        right.addChild(frame)

        let rightRequest = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertTrue(frame.parent === right)
        XCTAssertTrue(left.children.isEmpty)
        XCTAssertTrue(right.children.first === frame)
        XCTAssertTrue(rightRequest.isCurrent(in: runtime))
        XCTAssertFalse(leftRequest.isCurrent(in: runtime))
        XCTAssertFalse(rightRequest.element === leftRequest.element)
        _ = runtime.renderFrame()
        let rightID = try frameAddChildSnapshot(source).id
        XCTAssertNotEqual(rightID, leftID)
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: leftID))
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: rightID))
        XCTAssertEqual(activations, 1)

        left.addChild(frame)

        let returned = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertTrue(frame.parent === left)
        XCTAssertTrue(right.children.isEmpty)
        XCTAssertTrue(returned.isCurrent(in: runtime))
        XCTAssertFalse(leftRequest.isCurrent(in: runtime))
        XCTAssertFalse(rightRequest.isCurrent(in: runtime))
        XCTAssertFalse(returned.element === leftRequest.element)
        XCTAssertFalse(returned.element === rightRequest.element)
        _ = runtime.renderFrame()
        let returnedID = try frameAddChildSnapshot(source).id
        XCTAssertNotEqual(returnedID, leftID)
        XCTAssertNotEqual(returnedID, rightID)
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: leftID))
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: rightID))
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: returnedID))
        XCTAssertEqual(activations, 2)
    }
}

@MainActor
private func frameAddChildRuntime() -> RetainedViewRuntime {
    RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120)))
}

@MainActor
private func frameAddChildNativeFrame(action: (() -> Void)? = nil) -> ViewNode {
    let content = ViewNode(frame: Rect(x: 0, y: 0, width: 60, height: 24))
    content.accessibilityTraits = [.isButton]
    content.accessibilityLabel = "Content"
    let frame = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 32), children: [content])
    frame.declareAccessibilityFrameContent(content)
    frame.accessibilityLabel = "Subject"
    frame.accessibilityIdentifier = "subject"
    if let action { frame.accessibilityActions = [RetainedAccessibilityAction(handler: action)] }
    return frame
}

@MainActor
private func frameAddChildSnapshot(_ source: RuntimeUIAElementTreeSource) throws -> UIAElementSnapshot {
    let matches = source.uiaElementSnapshots().filter { $0.automationID == "subject" }
    XCTAssertEqual(matches.count, 1)
    return try XCTUnwrap(matches.first)
}

@MainActor
private func frameAddChildClose(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}
