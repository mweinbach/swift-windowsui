import CUIAInterop
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Additive source-only acceptance for selected-content/frame composition.
/// Public ViewThatFits chooses the first two fixtures; the root fixtures use
/// the existing retained selected-boundary factory, not a fabricated permission.
@MainActor
final class FrameAccessibilitySelectedCompositionTests: XCTestCase {
    func testOuterFramePreservesPublicSelectedImageMetadataAndGeometry() async throws {
        let baseline = FrameSelectedHost { frameSelectedImage(labelled: false) }
        let labelled = FrameSelectedHost { frameSelectedImage(labelled: true) }
        defer {
            baseline.close()
            labelled.close()
        }
        baseline.render()
        labelled.render()

        let outerFrame = try XCTUnwrap(labelled.runtime.root.children.first)
        let boundary = try XCTUnwrap(outerFrame.children.first)
        let innerFrame = try XCTUnwrap(boundary.children.first)
        let image = try XCTUnwrap(innerFrame.children.first)
        XCTAssertNil(outerFrame.selectedContentRole)
        XCTAssertEqual(boundary.selectedContentRole, .viewThatFits)
        XCTAssertNil(innerFrame.selectedContentRole)
        XCTAssertEqual(boundary.children.count, 1)
        XCTAssertTrue(image.accessibilityTraits.contains(.isImage))
        let selectedPath = try XCTUnwrap(boundary.captureSelectedContentPath(in: labelled.runtime))
        XCTAssertTrue(selectedPath.isCurrent)
        XCTAssertTrue(selectedPath.isInstalled(in: labelled.runtime))
        XCTAssertTrue(selectedPath.selectedNode === innerFrame)
        XCTAssertTrue(selectedPath.selectedNode !== image)

        let request = try XCTUnwrap(labelled.runtime.accessibilitySemanticRequest(for: outerFrame))
        let leafRequest = try XCTUnwrap(labelled.runtime.accessibilitySemanticRequest(for: image))
        XCTAssertTrue(request.isCurrent(in: labelled.runtime))
        XCTAssertTrue(leafRequest.isCurrent(in: labelled.runtime))
        XCTAssertTrue(request.semanticNode === image)
        XCTAssertTrue(leafRequest.semanticNode === image)
        XCTAssertEqual(request.metadata.label, "Selected image overlay")
        XCTAssertEqual(leafRequest.metadata.label, "Selected image overlay")
        XCTAssertEqual(request.metadata.traits, .isImage)

        let original = try XCTUnwrap(baseline.projections.first { $0.controlType == .image })
        let changed = try labelled.projection()
        XCTAssertTrue(changed.sourceNode === image)
        XCTAssertEqual(changed.name, "Selected image overlay")
        XCTAssertEqual(changed.controlType, .image)
        XCTAssertEqual(changed.bounds, original.bounds)
        XCTAssertEqual(labelled.projections.filter { $0.controlType == .image }.count, 1)
        XCTAssertEqual(
            frameSelectedNodes(baseline.runtime.root).map(\.resolvedFrame),
            frameSelectedNodes(labelled.runtime.root).map(\.resolvedFrame))
        XCTAssertEqual(
            frameSelectedNodes(baseline.runtime.root).map(\.selectedContentRole),
            frameSelectedNodes(labelled.runtime.root).map(\.selectedContentRole))
        let snapshot = try labelled.snapshot()
        XCTAssertEqual(snapshot.controlType, Int32(SWU_UIA_CONTROL_TYPE_IMAGE))
        XCTAssertEqual(snapshot.name, "Selected image overlay")
        XCTAssertFalse(snapshot.hasDefaultAction)
        XCTAssertFalse(snapshot.supportsValue)
        XCTAssertTrue(selectedPath.isCurrent)
    }

    func testOuterFrameKeepsPublicSelectedButtonAcrossAcceptedRebuild() async throws {
        let probe = FrameSelectedProbe()
        let host = FrameSelectedHost {
            AnyView(
                ViewThatFits(in: .horizontal) {
                    Color.clear.frame(width: 1_000, height: 20)
                    Button("Selected control") { probe.calls += 1 }
                }.frame(width: 160, height: 60, alignment: .leading)
                    .accessibilityLabel("Selected button overlay").accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let outerFrame = try XCTUnwrap(host.runtime.root.children.first)
        let boundary = try XCTUnwrap(outerFrame.children.first)
        let button = try XCTUnwrap(boundary.children.first)
        XCTAssertEqual(boundary.selectedContentRole, .viewThatFits)
        XCTAssertTrue(button.accessibilityTraits.contains(.isButton))
        let originalPath = try XCTUnwrap(boundary.captureSelectedContentPath(in: host.runtime))
        XCTAssertTrue(originalPath.selectedNode === button)
        XCTAssertTrue(originalPath.isCurrent)
        let originalRequest = try XCTUnwrap(host.runtime.accessibilitySemanticRequest(for: outerFrame))
        XCTAssertTrue(originalRequest.semanticNode === button)
        XCTAssertEqual(originalRequest.metadata.label, "Selected button overlay")
        let original = try host.snapshot()
        XCTAssertEqual(original.controlType, Int32(SWU_UIA_CONTROL_TYPE_BUTTON))
        XCTAssertTrue(original.hasDefaultAction)
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: original.id))
        XCTAssertEqual(probe.calls, 1)

        host.reload()
        host.render()
        XCTAssertTrue(host.runtime.root.children.first === outerFrame)
        XCTAssertTrue(outerFrame.children.first === boundary)
        XCTAssertTrue(boundary.children.first === button)
        XCTAssertTrue(button.parent === boundary)
        let freshPath = try XCTUnwrap(boundary.captureSelectedContentPath(in: host.runtime))
        XCTAssertTrue(freshPath.selectedNode === button)
        XCTAssertTrue(freshPath.isCurrent)
        let fresh = try XCTUnwrap(host.runtime.accessibilitySemanticRequest(for: outerFrame))
        let fromLeaf = try XCTUnwrap(host.runtime.accessibilitySemanticRequest(for: button))
        XCTAssertTrue(fresh.semanticNode === button)
        XCTAssertTrue(fromLeaf.semanticNode === button)
        XCTAssertTrue(fresh.isCurrent(in: host.runtime))
        XCTAssertTrue(fromLeaf.isCurrent(in: host.runtime))
        XCTAssertEqual(fresh.metadata.label, "Selected button overlay")
        XCTAssertEqual(try host.snapshot().id, original.id)
        XCTAssertEqual(try host.snapshot().bounds, original.bounds)
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: original.id))
        XCTAssertEqual(probe.calls, 2)
    }

    func testSelectedRootKeepsFrameAnchorSeparateFromSemanticButton() async throws {
        let probe = FrameSelectedProbe()
        let fixture = try FrameSelectedRootFixture(probe: probe)
        defer { fixture.close() }
        let originalPath = try XCTUnwrap(fixture.root.captureSelectedContentPath(in: fixture.runtime))
        XCTAssertTrue(originalPath.selectedNode === fixture.frame)
        XCTAssertTrue(originalPath.selectedNode !== fixture.button)
        XCTAssertTrue(originalPath.isInstalled(in: fixture.runtime))
        let request = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.frame))
        let fromLeaf = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.button))
        XCTAssertTrue(request.semanticNode === fixture.button)
        XCTAssertTrue(fromLeaf.semanticNode === fixture.button)
        XCTAssertTrue(request.isCurrent(in: fixture.runtime))
        XCTAssertEqual(request.metadata.label, "Selected root overlay")
        let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: fixture.runtime))
        XCTAssertTrue(projection.sourceNode === fixture.button)
        XCTAssertEqual(projection.flattened().count, 1)
        XCTAssertEqual(projection.name, "Selected root overlay")
        XCTAssertEqual(projection.controlType, .button)
        XCTAssertEqual(projection.bounds, fixture.runtime.resolvedLayoutFrame(of: fixture.button))
        XCTAssertTrue(projection.actions.isEmpty, "Use the real Button's implicit activation")
        XCTAssertNil(fixture.root.onActivate)
        XCTAssertNil(fixture.frame.onActivate)
        XCTAssertFalse(fixture.root.isFocusable)
        XCTAssertFalse(fixture.frame.isFocusable)

        let snapshots = fixture.source.uiaElementSnapshots()
        XCTAssertEqual(snapshots.count, 1)
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.id, UIAProviderBridge.rootElementID)
        XCTAssertNil(snapshot.parentID)
        XCTAssertEqual(snapshot.name, "Selected root overlay")
        XCTAssertEqual(snapshot.controlType, Int32(SWU_UIA_CONTROL_TYPE_BUTTON))
        XCTAssertTrue(snapshot.hasDefaultAction)
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))
        XCTAssertEqual(probe.calls, 1)
        XCTAssertTrue(originalPath.isCurrent)
        XCTAssertTrue(fixture.root.children.first === fixture.frame)
        XCTAssertTrue(fixture.frame.children.first === fixture.button)
    }

    func testSelectedRootFrameActionRejectsQueryTimeCardinalityABA() async throws {
        let probe = FrameSelectedProbe()
        let fixture = try FrameSelectedRootFixture(probe: probe)
        defer { fixture.close() }
        let originalPath = try XCTUnwrap(fixture.root.captureSelectedContentPath(in: fixture.runtime))
        let originalRequest = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.frame))
        let originalAttachment = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.button))
        let originalProjection = try XCTUnwrap(AccessibilityProjection.project(runtime: fixture.runtime))
        XCTAssertTrue(originalProjection.sourceNode === fixture.button)
        XCTAssertTrue(originalProjection.actions.isEmpty)
        let extra = ViewNode(preferredSize: Size(width: 5, height: 5))
        var layouts = 0
        var selectionChanges = 0
        var isInvoking = false
        fixture.frame.onLayoutWithNode = { [weak root = fixture.root, weak frame = fixture.frame] node, _ in
            layouts += 1
            guard selectionChanges == 0 else { return }
            XCTAssertTrue(isInvoking, "The ABA must occur inside the original invocation's layout query")
            guard isInvoking, let root, let frame else { return }
            XCTAssertTrue(node === frame)
            XCTAssertTrue(root.children.first === frame)
            selectionChanges += 1
            root.addChild(extra)
            XCTAssertEqual(root.children.count, 2)
            XCTAssertTrue(frame.parent === root)
            extra.removeFromParent()
            XCTAssertEqual(root.children.count, 1)
            XCTAssertTrue(root.children.first === frame)
            XCTAssertTrue(frame.parent === root)
        }
        fixture.runtime.setRootSize(IntSize(width: 120, height: 40))
        XCTAssertEqual(layouts, 0)
        XCTAssertEqual(selectionChanges, 0)
        XCTAssertEqual(probe.calls, 0)

        isInvoking = true
        let result = originalProjection.invokeDefaultAction()
        isInvoking = false

        XCTAssertFalse(result)
        XCTAssertEqual(selectionChanges, 1)
        XCTAssertGreaterThanOrEqual(layouts, 1)
        XCTAssertEqual(probe.calls, 0, "Neither the old frame anchor nor the unchanged Button can refresh this request")
        XCTAssertTrue(fixture.root.children.first === fixture.frame)
        XCTAssertTrue(fixture.frame.children.first === fixture.button)
        XCTAssertTrue(fixture.button.parent === fixture.frame)
        XCTAssertNil(extra.parent)
        XCTAssertTrue(
            fixture.runtime.isAccessibilityAttachmentCurrent(originalAttachment), "The semantic leaf never detached")
        XCTAssertFalse(originalPath.isCurrent)
        XCTAssertFalse(originalPath.isInstalled(in: fixture.runtime))
        XCTAssertFalse(
            originalRequest.isCurrent(in: fixture.runtime), "An unchanged leaf cannot erase selected-path ABA")

        // This is a separate read and invocation, not a retry of the old proof.
        // No render or additional explicit settlement is inserted between them.
        let freshPath = try XCTUnwrap(fixture.root.captureSelectedContentPath(in: fixture.runtime))
        let freshRequest = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.frame))
        let leafRequest = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.button))
        XCTAssertTrue(freshPath.selectedNode === fixture.frame)
        XCTAssertTrue(freshPath.isCurrent)
        XCTAssertTrue(freshRequest.semanticNode === fixture.button)
        XCTAssertTrue(leafRequest.semanticNode === fixture.button)
        XCTAssertTrue(freshRequest.isCurrent(in: fixture.runtime))
        XCTAssertTrue(leafRequest.isCurrent(in: fixture.runtime))
        XCTAssertEqual(freshRequest.metadata.label, "Selected root overlay")
        let freshProjection = try XCTUnwrap(AccessibilityProjection.project(runtime: fixture.runtime))
        XCTAssertTrue(freshProjection.sourceNode === fixture.button)
        XCTAssertTrue(freshProjection.actions.isEmpty)
        XCTAssertTrue(freshProjection.invokeDefaultAction())
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(selectionChanges, 1)
        XCTAssertFalse(originalPath.isCurrent)
        XCTAssertFalse(originalRequest.isCurrent(in: fixture.runtime))
    }
}

@MainActor
private func frameSelectedImage(labelled: Bool) -> AnyView {
    let content = ViewThatFits(in: .horizontal) {
        Color.clear.frame(width: 1_000, height: 20)
        Image(bitmap: BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 255, 0, 255])))
            .resizable().frame(width: 24, height: 16)
    }.frame(width: 80, height: 60, alignment: .bottomTrailing)
    if labelled {
        return AnyView(content.accessibilityLabel("Selected image overlay").accessibilityIdentifier("subject"))
    }
    return AnyView(content.opacity(1).opacity(1))
}

@MainActor
private final class FrameSelectedProbe {
    var calls = 0
}

@MainActor
private final class FrameSelectedRootFixture {
    let root: ViewNode
    let runtime: RetainedViewRuntime
    let frame: ViewNode
    let button: ViewNode
    let source: RuntimeUIAElementTreeSource

    init(probe: FrameSelectedProbe) throws {
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: ViewNode())
        let runtime = RetainedViewRuntime(root: root)
        runtime.setRootSize(IntSize(width: 80, height: 40))
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 80, height: 40) }, invalidateHandler: {})
        let frame = Button("Selected control") { probe.calls += 1 }
            .frame(alignment: .leading)
            .accessibilityLabel("Selected root overlay").accessibilityIdentifier("subject")
            .makeComponent(context: context).makeNode(runtime: runtime)
        self.root = root
        self.runtime = runtime
        self.frame = frame
        self.button = try XCTUnwrap(frame.children.first)
        self.source = RuntimeUIAElementTreeSource(runtime: runtime)
        root.setChildren([frame])
        _ = runtime.renderFrame()
        XCTAssertTrue(button.accessibilityTraits.contains(.isButton))
        XCTAssertNil(frame.selectedContentRole)
    }

    func close() {
        frame.onLayoutWithNode = nil
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        root.removeAllChildren()
    }
}

@MainActor
private final class FrameSelectedHost {
    let runtime: RetainedViewRuntime
    let componentHost: ComponentHost
    let coordinator: StateMountCoordinator
    let source: RuntimeUIAElementTreeSource
    private var isClosed = false

    init(content: @escaping @MainActor () -> AnyView) {
        let size = Size(width: 200, height: 120)
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: size.width, height: size.height)))
        let host = ComponentHost(runtime: runtime)
        let coordinator = StateMountCoordinator(
            invalidate: { [weak host] in host?.reload() },
            observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        self.runtime = runtime
        self.componentHost = host
        self.coordinator = coordinator
        self.source = RuntimeUIAElementTreeSource(runtime: runtime)
        host.buildLifecycle = coordinator
        host.shouldUpdate = { [weak self] in self?.isClosed == false }
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { size },
            invalidateHandler: { [weak host] in host?.reload() })
        host.setComponents { [weak self] in
            guard self?.isClosed == false else { return [] }
            return [makeViewComponent(content(), context: context)]
        }
    }

    var projections: [AccessibilityElementProjection] {
        AccessibilityProjection.project(runtime: runtime)?.flattened() ?? []
    }
    func render() { if !isClosed { _ = runtime.renderScene() } }
    func reload() { if !isClosed { componentHost.reload() } }
    func projection() throws -> AccessibilityElementProjection {
        let matches = projections.filter { $0.identifier == "subject" }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }
    func snapshot() throws -> UIAElementSnapshot {
        let matches = source.uiaElementSnapshots().filter { $0.automationID == "subject" }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }
    func close() {
        guard !isClosed else { return }
        isClosed = true
        runtime.stopRenderLifecycleCallbacks()
        coordinator.close()
        componentHost.onReloadCompleted = nil
        componentHost.setComponents { [] }
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private func frameSelectedNodes(_ root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}
