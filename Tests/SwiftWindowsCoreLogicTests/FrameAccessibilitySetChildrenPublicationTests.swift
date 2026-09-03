import CUIAInterop
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class FrameAccessibilitySetChildrenPublicationTests: XCTestCase {
    func testSelectedRootPublishesFramedButtonAfterFinalMembershipBeforeFirstRead() async throws {
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: ViewNode())
        let runtime = RetainedViewRuntime(root: root)
        runtime.setRootSize(IntSize(width: 160, height: 60))
        defer { frameSetChildrenClose(runtime) }
        var calls = 0
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {})
        let frame = Button("Control") { calls += 1 }
            .frame(alignment: .leading)
            .accessibilityLabel("Selected framed control")
            .accessibilityIdentifier("subject")
            .makeComponent(context: context).makeNode(runtime: runtime)
        let button = try XCTUnwrap(frame.children.first)
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: frame))

        let result = root.setChildren([frame])

        XCTAssertTrue(result.completed)
        let path = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        let request = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertTrue(path.isInstalled(in: runtime))
        XCTAssertTrue(path.selectedNode === frame)
        XCTAssertTrue(request.semanticNode === button)
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertEqual(request.metadata.label, "Selected framed control")
        XCTAssertNil(root.onActivate)
        XCTAssertNil(frame.onActivate)
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let snapshots = source.uiaElementSnapshots()
        XCTAssertEqual(snapshots.count, 1)
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.id, UIAProviderBridge.rootElementID)
        XCTAssertEqual(snapshot.controlType, Int32(SWU_UIA_CONTROL_TYPE_BUTTON))
        XCTAssertTrue(snapshot.hasDefaultAction)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: snapshot.id))
        XCTAssertEqual(calls, 1)
    }

    func testOrdinaryParentPublishesNestedOwnerlessFrameWithoutChangingItsRole() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 60)))
        defer { frameSetChildrenClose(runtime) }
        let inner = frameSetChildrenImage()
        let outer = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 40), children: [inner])
        outer.declareAccessibilityFrameContent(inner)
        outer.accessibilityLabel = "Outer image label"
        let container = ViewNode(children: [outer])
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: outer))

        XCTAssertTrue(runtime.root.setChildren([container]).completed)

        let request = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: outer))
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertTrue(request.semanticNode === inner.accessibilityDeclaredFrameContent)
        XCTAssertEqual(request.metadata.label, "Outer image label")
        XCTAssertEqual(request.metadata.traits, .isImage)
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: container))
        XCTAssertNil(container.selectedContentRole)
        XCTAssertNil(runtime.root.selectedContentRole)
        XCTAssertTrue(try XCTUnwrap(runtime.accessibilitySemanticRequest(for: inner)).element === request.element)
    }

    func testUnchangedChildrenKeepOriginalPublicationAndCannotRepairSuspendedAdoption() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        defer { frameSetChildrenClose(runtime) }
        let frame = frameSetChildrenImage()
        XCTAssertTrue(runtime.root.setChildren([frame]).completed)
        let original = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))

        let unchanged = runtime.root.setChildren([frame])

        XCTAssertTrue(unchanged.completed)
        XCTAssertFalse(unchanged.didMutate)
        XCTAssertTrue(original.isCurrent(in: runtime))
        XCTAssertTrue(try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame)).element === original.element)
        let scope = try XCTUnwrap(RetainedFrameAccessibilityAdoption(retainedRoots: [frame], sourceRoots: [frame]))
        XCTAssertTrue(scope.isCurrent)
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertFalse(original.isCurrent(in: runtime))
        XCTAssertTrue(runtime.root.setChildren([frame]).completed)
        XCTAssertTrue(scope.isCurrent)
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: frame))
        withExtendedLifetime(scope) {}
    }

    func testFinalWriteReleasesDisplacedPayloadBeforePublishingTheOriginalFrame() async throws {
        try assertFinalWriteRelease(mutation: .none)
    }

    func testFinalWriteCleanupCannotPublishAfterOriginalIncomingIdentityABA() async throws {
        try assertFinalWriteRelease(mutation: .incomingIdentity)
    }

    func testFinalWriteCleanupCannotPublishAfterOriginalParentIdentityABA() async throws {
        try assertFinalWriteRelease(mutation: .parentIdentity)
    }

    private func assertFinalWriteRelease(mutation: FrameSetChildrenReleaseMutation) throws {
        let outgoing = ViewNode()
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: outgoing)
        let runtime = RetainedViewRuntime(root: root)
        defer {
            outgoing.onDismantlePlatformView = nil
            frameSetChildrenClose(runtime)
        }
        let frame = frameSetChildrenImage()
        let leaf = try XCTUnwrap(frame.accessibilityDeclaredFrameContent)
        var releases = 0
        var fieldWasFinal = false
        var publicationWasAbsent = false
        weak var displaced: ViewNode?
        outgoing.onDismantlePlatformView = { [weak root] _ in
            guard let root else { return }
            XCTAssertTrue(root.children.isEmpty)
            displaced = frameSetChildrenInstallRelease(in: root) {
                releases += 1
                fieldWasFinal = root.children.count == 1 && root.children.first === frame
                publicationWasAbsent = runtime.accessibilitySemanticRequest(for: frame) == nil
                let changed: ViewNode?
                switch mutation {
                case .none: changed = nil
                case .incomingIdentity: changed = leaf
                case .parentIdentity: changed = root
                }
                if let changed {
                    let original = changed.retainedViewIdentity
                    changed.retainedViewIdentity = RetainedViewIdentity(segments: [.explicit(.init("cleanup"))])
                    changed.retainedViewIdentity = original
                }
            }
            XCTAssertNotNil(displaced)
            XCTAssertEqual(releases, 0)
        }

        let result = root.setChildren([frame])

        XCTAssertTrue(result.completed, "The existing raw child-table result is unchanged")
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(releases, 1)
        XCTAssertNil(displaced, "Publication proof must not extend an authored payload's lifetime")
        XCTAssertTrue(fieldWasFinal)
        XCTAssertTrue(publicationWasAbsent)
        XCTAssertTrue(root.children.first === frame)
        XCTAssertTrue(frame.parent === root)
        XCTAssertTrue(frame.children.first === leaf)
        XCTAssertTrue(try XCTUnwrap(root.captureSelectedContentPath(in: runtime)).isInstalled(in: runtime))
        if mutation == .none {
            let request = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
            XCTAssertTrue(request.isCurrent(in: runtime))
            XCTAssertTrue(request.semanticNode === leaf)
            XCTAssertEqual(request.metadata.label, "Frame image")
        } else {
            XCTAssertNil(runtime.accessibilitySemanticRequest(for: frame))
            XCTAssertNil(runtime.accessibilitySemanticRequest(for: leaf))
            XCTAssertTrue(root.setChildren([frame]).completed)
            XCTAssertNil(runtime.accessibilitySemanticRequest(for: frame), "An unchanged setter is not a retry")
        }
    }
}

private enum FrameSetChildrenReleaseMutation {
    case none
    case incomingIdentity
    case parentIdentity
}

@MainActor
private final class FrameSetChildrenReleasePayload {
    let release: @MainActor () -> Void
    init(release: @escaping @MainActor () -> Void) { self.release = release }
    isolated deinit { release() }
}

@MainActor
@inline(never)
private func frameSetChildrenInstallRelease(in parent: ViewNode, release: @escaping @MainActor () -> Void) -> ViewNode {
    let payload = FrameSetChildrenReleasePayload(release: release)
    let node = ViewNode()
    node.onActivate = { [payload] in withExtendedLifetime(payload) {} }
    parent.addChild(node)
    return node
}

@MainActor
private func frameSetChildrenImage() -> ViewNode {
    let image = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 24))
    image.accessibilityTraits = .isImage
    image.accessibilityLabel = "Image"
    let frame = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 32), children: [image])
    frame.declareAccessibilityFrameContent(image)
    frame.accessibilityLabel = "Frame image"
    return frame
}

@MainActor
private func frameSetChildrenClose(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}
