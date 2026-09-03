import CUIAInterop
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Passive Images exercise adoption without any native Button owner witness.
/// These additive tests are frozen before the optional native tree witness change.
@MainActor
final class FrameAccessibilityPassiveAdoptionTests: XCTestCase {
    func testDirectPassiveImageAdoptionRejectsChildABADuringActionCleanup() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120)))
        defer { framePassiveClose(runtime) }
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        weak var frameForCleanup: ViewNode?
        weak var imageForCleanup: ViewNode?
        var cleanups = 0
        var actions = 0
        let original = framePassiveImageNode(
            label: "Original overlay", in: runtime,
            onRelease: {
                cleanups += 1
                guard let frame = frameForCleanup, let image = imageForCleanup else {
                    return XCTFail("Cleanup must still have the original attached Image")
                }
                XCTAssertTrue(frame.children.first === image)
                XCTAssertTrue(image.parent === frame)
                frame.removeAllChildren()
                XCTAssertNil(image.parent)
                frame.addChild(image)
                XCTAssertTrue(frame.children.first === image)
                XCTAssertTrue(image.parent === frame)
            }, onInvoke: { actions += 1 })
        frameForCleanup = original
        let image = try XCTUnwrap(original.children.first)
        imageForCleanup = image
        runtime.root.addChild(original)
        _ = runtime.renderFrame()
        let originalIdentity = try XCTUnwrap(image.retainedViewIdentity)
        let originalAttachment = try XCTUnwrap(runtime.accessibilityTarget(for: image))
        let originalRequest = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: original))
        let snapshots = source.uiaElementSnapshots().filter { $0.automationID == "passive-subject" }
        XCTAssertEqual(snapshots.count, 1)
        let old = try XCTUnwrap(snapshots.first)
        XCTAssertNotEqual(old.id, UIAProviderBridge.rootElementID)
        XCTAssertEqual(old.name, "Original overlay")
        XCTAssertEqual(old.controlType, Int32(SWU_UIA_CONTROL_TYPE_IMAGE))
        XCTAssertTrue(old.hasDefaultAction)
        XCTAssertTrue(originalRequest.semanticNode === image)
        let candidate = framePassiveImageNode(label: "Candidate overlay", in: runtime)
        XCTAssertNotNil(original.retainedViewIdentity)
        XCTAssertEqual(
            framePassiveNodes(original).map(\.retainedViewIdentity),
            framePassiveNodes(candidate).map(\.retainedViewIdentity))
        XCTAssertTrue(candidate.accessibilityActions.isEmpty)
        XCTAssertEqual(original.accessibilityActions.map(\.name), ["Inspect"])
        for node in framePassiveNodes(runtime.root) + framePassiveNodes(candidate) {
            XCTAssertNil(node.buttonActionOwner, "No Button owner may supply this test's rejection witness")
        }
        XCTAssertEqual(cleanups, 0)

        let result = ComponentHost.adopt(source: candidate, into: original)

        XCTAssertEqual(cleanups, 1, "The action payload must retire during this adoption")
        XCTAssertFalse(result.completed)
        XCTAssertTrue(runtime.permitsRenderLifecycleCallbacks)
        XCTAssertTrue(runtime.root.children.first === original)
        XCTAssertTrue(original.children.first === image)
        XCTAssertTrue(image.parent === original)
        XCTAssertEqual(image.retainedViewIdentity, originalIdentity)
        XCTAssertFalse(runtime.isAccessibilityAttachmentCurrent(originalAttachment))
        XCTAssertFalse(originalRequest.isCurrent(in: runtime))
        for _ in 0..<3 {
            XCTAssertNil(runtime.accessibilitySemanticRequest(for: original))
            XCTAssertNil(runtime.accessibilitySemanticRequest(for: image))
            let current = source.uiaElementSnapshots()
            XCTAssertFalse(current.contains { $0.id == old.id })
            XCTAssertFalse(current.contains { $0.automationID == "passive-subject" })
            XCTAssertFalse(current.contains { $0.name == "Candidate overlay" })
            XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: old.id))
            XCTAssertEqual(cleanups, 1)
            XCTAssertEqual(actions, 0)
        }
        for node in framePassiveNodes(runtime.root) + framePassiveNodes(candidate) {
            XCTAssertNil(node.buttonActionOwner)
        }
    }

    func testMatchedPassiveImageAdoptionRejectsChildABADuringActionCleanup() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120)))
        defer { framePassiveClose(runtime) }
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        weak var frameForCleanup: ViewNode?
        weak var imageForCleanup: ViewNode?
        var cleanups = 0
        var actions = 0
        let original = framePassiveImageNode(
            label: "Original overlay", in: runtime,
            onRelease: {
                cleanups += 1
                guard let frame = frameForCleanup, let image = imageForCleanup else {
                    return XCTFail("Cleanup must still have the original attached Image")
                }
                XCTAssertTrue(frame.children.first === image)
                XCTAssertTrue(image.parent === frame)
                frame.removeAllChildren()
                XCTAssertNil(image.parent)
                frame.addChild(image)
                XCTAssertTrue(frame.children.first === image)
                XCTAssertTrue(image.parent === frame)
            }, onInvoke: { actions += 1 })
        frameForCleanup = original
        let image = try XCTUnwrap(original.children.first)
        imageForCleanup = image
        runtime.root.addChild(original)
        _ = runtime.renderFrame()
        let originalIdentity = try XCTUnwrap(image.retainedViewIdentity)
        let originalAttachment = try XCTUnwrap(runtime.accessibilityTarget(for: image))
        let originalRequest = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: original))
        let snapshots = source.uiaElementSnapshots().filter { $0.automationID == "passive-subject" }
        XCTAssertEqual(snapshots.count, 1)
        let old = try XCTUnwrap(snapshots.first)
        XCTAssertNotEqual(old.id, UIAProviderBridge.rootElementID)
        XCTAssertEqual(old.name, "Original overlay")
        XCTAssertEqual(old.controlType, Int32(SWU_UIA_CONTROL_TYPE_IMAGE))
        XCTAssertTrue(old.hasDefaultAction)
        XCTAssertTrue(originalRequest.semanticNode === image)
        let candidate = framePassiveImageNode(label: "Candidate overlay", in: runtime)
        XCTAssertNotNil(original.retainedViewIdentity)
        XCTAssertEqual(
            framePassiveNodes(original).map(\.retainedViewIdentity),
            framePassiveNodes(candidate).map(\.retainedViewIdentity))
        XCTAssertTrue(candidate.accessibilityActions.isEmpty)
        XCTAssertEqual(original.accessibilityActions.map(\.name), ["Inspect"])
        for node in framePassiveNodes(runtime.root) + framePassiveNodes(candidate) {
            XCTAssertNil(node.buttonActionOwner, "No Button owner may supply this test's rejection witness")
        }
        XCTAssertEqual(cleanups, 0)

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [candidate])

        XCTAssertEqual(cleanups, 1, "The matched child's action payload must retire during reconciliation")
        XCTAssertFalse(result.completed)
        XCTAssertTrue(runtime.permitsRenderLifecycleCallbacks)
        XCTAssertTrue(runtime.root.children.first === original)
        XCTAssertTrue(original.children.first === image)
        XCTAssertTrue(image.parent === original)
        XCTAssertEqual(image.retainedViewIdentity, originalIdentity)
        XCTAssertFalse(runtime.isAccessibilityAttachmentCurrent(originalAttachment))
        XCTAssertFalse(originalRequest.isCurrent(in: runtime))
        for _ in 0..<3 {
            XCTAssertNil(runtime.accessibilitySemanticRequest(for: original))
            XCTAssertNil(runtime.accessibilitySemanticRequest(for: image))
            let current = source.uiaElementSnapshots()
            XCTAssertFalse(current.contains { $0.id == old.id })
            XCTAssertFalse(current.contains { $0.automationID == "passive-subject" })
            XCTAssertFalse(current.contains { $0.name == "Candidate overlay" })
            XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: old.id))
            XCTAssertEqual(cleanups, 1)
            XCTAssertEqual(actions, 0)
        }
        for node in framePassiveNodes(runtime.root) + framePassiveNodes(candidate) {
            XCTAssertNil(node.buttonActionOwner)
        }
    }
}

@MainActor
@inline(never)
private func framePassiveImageNode(
    label: String, in runtime: RetainedViewRuntime,
    onRelease: (@MainActor () -> Void)? = nil,
    onInvoke: @escaping @MainActor () -> Void = {}
) -> ViewNode {
    let context = ViewBuildContext(canvasSizeProvider: { Size(width: 200, height: 120) }, invalidateHandler: {})
    let base = Image(bitmap: BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 255, 0, 255])))
        .resizable().frame(width: 48, height: 32)
        .accessibilityLabel(label).accessibilityIdentifier("passive-subject")
    if let onRelease {
        let payload = FramePassiveRetirement(onRelease)
        return base.accessibilityAction(named: "Inspect") { [payload] in
            onInvoke()
            withExtendedLifetime(payload) {}
        }.makeComponent(context: context).makeNode(runtime: runtime)
    }
    // The incoming candidate removes only the action, preserving modifier depth.
    return base.opacity(1).makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private final class FramePassiveRetirement {
    private let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    deinit { MainActor.assumeIsolated { onRelease() } }
}

@MainActor
private func framePassiveNodes(_ root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private func framePassiveClose(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}
