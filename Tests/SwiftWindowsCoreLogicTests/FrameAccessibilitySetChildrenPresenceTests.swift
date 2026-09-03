import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class FrameAccessibilitySetChildrenPresenceTests: XCTestCase {
    func testDetachedFrameInsertionDoesNotAllocatePublicationWitnessStorage() async throws {
        let parent = ViewNode()
        let image = ViewNode()
        image.accessibilityTraits = .isImage
        let frame = ViewNode(children: [image])
        frame.declareAccessibilityFrameContent(image)
        XCTAssertFalse(parent.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(frame.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(image.hasAllocatedLifecycleHandlers)

        XCTAssertTrue(parent.setChildren([frame]).completed)

        XCTAssertFalse(parent.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(frame.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(image.hasAllocatedLifecycleHandlers)
        XCTAssertNil(frame.currentAccessibilitySemanticRequest)
        XCTAssertTrue(frame.parent === parent)
    }

    func testAttachedFrameFreeInsertionDoesNotAllocatePublicationWitnessStorage() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        defer {
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            runtime.root.removeAllChildren()
        }
        let child = ViewNode()
        let container = ViewNode(children: [child])
        XCTAssertFalse(container.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(child.hasAllocatedLifecycleHandlers)

        XCTAssertTrue(runtime.root.setChildren([container]).completed)

        XCTAssertFalse(container.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(child.hasAllocatedLifecycleHandlers)
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: container))
        XCTAssertTrue(container.parent === runtime.root)
        XCTAssertTrue(child.parent === container)
    }

    func testBareSelectedChildPublishesItsExistingDeclaredFrameAncestor() async throws {
        let placeholder = ViewNode()
        let boundary = ViewNode.selectedContentBoundary(role: .viewThatFits, child: placeholder)
        let frame = ViewNode(children: [boundary])
        frame.declareAccessibilityFrameContent(boundary)
        frame.accessibilityLabel = "Existing frame"
        let runtime = RetainedViewRuntime(root: ViewNode())
        defer {
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            runtime.root.removeAllChildren()
        }
        runtime.root.addChild(frame)
        let original = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertTrue(original.semanticNode === placeholder)
        let image = ViewNode()
        image.accessibilityTraits = .isImage
        XCTAssertNil(image.accessibilityDeclaredFrameContent)
        XCTAssertNil(boundary.accessibilityDeclaredFrameContent)

        XCTAssertTrue(boundary.setChildren([image]).completed)

        let request = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertTrue(request.semanticNode === image)
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertEqual(request.metadata.traits, .isImage)
        XCTAssertEqual(request.metadata.label, "Existing frame")
        XCTAssertFalse(original.isCurrent(in: runtime))
        XCTAssertTrue(try XCTUnwrap(boundary.captureSelectedContentPath(in: runtime)).isInstalled(in: runtime))
    }
}
