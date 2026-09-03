import CUIAInterop
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class FrameChromePayloadInventoryTests: XCTestCase {
    func testRecipeNodesAndReadOnlyIdentityObservationsKeepClosedPayload() async throws {
        let label = ViewNode(text: "label", isHitTestVisible: false)
        let caret = ViewNode(isHitTestVisible: false)
        caret.preferredSize = Size(width: 1, height: 16)
        caret.isTextInputCaret = true
        let tail = ViewNode(isHitTestVisible: false)
        tail.preferredSize = Size(width: 4, height: 16)
        let row = Controls.stackPanel(
            stackLayout: .horizontal(spacing: 0, padding: .zero, alignment: .center),
            isHitTestVisible: false, children: [label, caret, tail])
        let root = Controls.stackPanel(
            stackLayout: .vertical(spacing: 0, padding: .zero, alignment: .leading),
            isHitTestVisible: false, children: [row])
        for node in frameChromePayloadNodes(root) {
            XCTAssertTrue(node.hasClosedTextInputChromePayload)
            XCTAssertEqual(node.accessibilityFrameIntent, RetainedFrameAccessibilityIntent())
            XCTAssertNil(node.accessibilityDeclaredFrameContent)
            XCTAssertNil(node.currentAccessibilitySemanticRequest)
            XCTAssertNil(node.effectiveAccessibilityMetadata?.label)
            XCTAssertTrue(node.accessibilityActions.isEmpty)
            XCTAssertNil(node.accessibilityActionMutationIdentity)
            _ = node.captureLazyListAttachmentProof()
            _ = node.captureLazyListIdentityProof()
            _ = node.captureTextInputChromeLocalLayoutWitness()
            _ = node.captureAccessibilityTextContentIdentity()
            XCTAssertTrue(node.hasClosedTextInputChromePayload)
        }
        root.isHidden = true
        XCTAssertTrue(root.hasClosedTextInputChromePayload)
        root.isHidden = false
        XCTAssertTrue(root.hasClosedTextInputChromePayload)
    }

    func testDeclaredContentAndExplicitDefaultIntentAreNotClosedPayload() async throws {
        let node = ViewNode(isHitTestVisible: false)
        let operand = ViewNode(isHitTestVisible: false)
        XCTAssertTrue(node.hasClosedTextInputChromePayload)
        node.declareAccessibilityFrameContent(operand)
        XCTAssertFalse(node.hasClosedTextInputChromePayload)
        // These public writes have default raw values but retain authored intent.
        node.accessibilityLabel = nil
        node.accessibilitySortPriority = 0
        node.isAccessibilityHidden = false
        XCTAssertNil(node.accessibilityLabel)
        XCTAssertEqual(node.accessibilitySortPriority, 0)
        XCTAssertFalse(node.isAccessibilityHidden)
        XCTAssertNotEqual(node.accessibilityFrameIntent, RetainedFrameAccessibilityIntent())
        node.replaceAccessibilityFrameDeclaration(content: nil)
        XCTAssertNil(node.accessibilityFrameContentStorage)
        XCTAssertFalse(node.hasClosedTextInputChromePayload)
        node.accessibilityFrameIntent = RetainedFrameAccessibilityIntent()
        XCTAssertTrue(node.hasClosedTextInputChromePayload)
        node.accessibilityFrameIntent.label = .set("authored")
        XCTAssertNil(node.accessibilityLabel)
        XCTAssertFalse(node.hasClosedTextInputChromePayload)

        let dangling = ViewNode(isHitTestVisible: false)
        var borrowed: ViewNode? = ViewNode(isHitTestVisible: false)
        dangling.declareAccessibilityFrameContent(try XCTUnwrap(borrowed))
        borrowed = nil
        XCTAssertNil(dangling.accessibilityDeclaredFrameContent)
        XCTAssertNotNil(dangling.accessibilityFrameContentStorage)
        XCTAssertFalse(dangling.hasClosedTextInputChromePayload)
    }

    func testPendingAndRetiredFrameStateCannotEnterClosedPayload() async throws {
        let pending = ViewNode(isHitTestVisible: false)
        pending.accessibilityFrameUpdateIdentity = RetainedAccessibilityIdentity()
        XCTAssertFalse(pending.hasClosedTextInputChromePayload)
        pending.accessibilityFrameUpdateIdentity = nil
        XCTAssertTrue(pending.hasClosedTextInputChromePayload)
        pending.accessibilityFrameMetadataMutationDepth = 1
        XCTAssertFalse(pending.hasClosedTextInputChromePayload)
        pending.accessibilityFrameMetadataMutationDepth = 0
        XCTAssertTrue(pending.hasClosedTextInputChromePayload)

        let leaf = ViewNode(isHitTestVisible: false)
        let frame = Controls.stackPanel(
            stackLayout: .horizontal(spacing: 0, padding: .zero, alignment: .center),
            isHitTestVisible: false, children: [leaf])
        frame.declareAccessibilityFrameContent(leaf)
        frame.recordAccessibilityFrameTraits(adding: .isModal)
        let runtime = RetainedViewRuntime(root: frame)
        defer {
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            runtime.root.removeAllChildren()
        }
        let element = try XCTUnwrap(leaf.accessibilitySemanticElement)
        XCTAssertTrue(leaf.accessibilityTraits.isEmpty)
        XCTAssertTrue(leaf.effectiveAccessibilityTraits.contains(.isModal))
        XCTAssertFalse(leaf.hasClosedTextInputChromePayload)
        element.retire()
        XCTAssertFalse(element.isAvailable)
        XCTAssertFalse(leaf.hasClosedTextInputChromePayload)
        pending.accessibilityFrameMetadataMutationElement = element
        XCTAssertEqual(pending.accessibilityFrameMetadataMutationDepth, 0)
        XCTAssertFalse(pending.hasClosedTextInputChromePayload)
        pending.accessibilityFrameMetadataMutationElement = nil
        XCTAssertTrue(pending.hasClosedTextInputChromePayload)
    }

    func testAuthoredActionsAndClearedActionHistoryAreNotClosedPayload() async throws {
        var calls = 0
        let constructed = ViewNode(isHitTestVisible: false, accessibilityActions: [])
        XCTAssertTrue(constructed.hasClosedTextInputChromePayload)
        XCTAssertNil(constructed.accessibilityActionMutationIdentity)
        constructed.accessibilityActions = [RetainedAccessibilityAction(name: "authored") { calls += 1 }]
        XCTAssertFalse(constructed.hasClosedTextInputChromePayload)
        XCTAssertEqual(calls, 0)
        constructed.accessibilityActions = []
        XCTAssertTrue(constructed.accessibilityActions.isEmpty)
        XCTAssertNotNil(constructed.accessibilityActionMutationIdentity)
        XCTAssertFalse(constructed.hasClosedTextInputChromePayload)
        XCTAssertEqual(calls, 0)
        // This native marker is not callback ownership. It is excluded only from
        // the closed generated recipe; an ordinary empty-action setter stays valid.
        let explicitlyCleared = ViewNode(isHitTestVisible: false)
        explicitlyCleared.accessibilityActions = []
        XCTAssertNotNil(explicitlyCleared.accessibilityActionMutationIdentity)
        XCTAssertFalse(explicitlyCleared.hasClosedTextInputChromePayload)
    }

    func testFramedSynchronousValueAdoptionPublishesChromeAndFrameMetadata() async throws {
        let model = FrameChromePayloadModel()
        let fixture = FrameChromePayloadHost(model: model)
        defer { fixture.close() }
        let field = try fixture.field()
        fixture.runtime.requestFocus(field)
        fixture.render()
        let frame = try XCTUnwrap(fixture.runtime.root.children.first)
        XCTAssertTrue(frame.accessibilityDeclaredFrameContent === field)
        XCTAssertNil(frame.textInputController)
        let originalController = try XCTUnwrap(field.textInputController)
        let original = try fixture.snapshot()
        XCTAssertEqual(original.controlType, Int32(SWU_UIA_CONTROL_TYPE_EDIT))
        XCTAssertTrue(original.supportsValue)
        XCTAssertFalse(original.isReadOnly)
        let builds = model.builds
        var passAtWrite: UInt64?
        model.afterWrite = { [weak fixture] in
            guard let fixture else { return }
            passAtWrite = fixture.runtime.layoutPassID
            model.version += 1
            fixture.host.reload()
        }
        XCTAssertTrue(fixture.source.uiaSetValue(elementID: original.id, value: "adopted"))
        model.afterWrite = nil
        XCTAssertEqual(model.values, ["adopted"])
        XCTAssertEqual(model.writeVersions, [0])
        XCTAssertEqual(model.builds, builds + 1)
        XCTAssertEqual(fixture.runtime.layoutPassID, try XCTUnwrap(passAtWrite))
        XCTAssertTrue(try fixture.field() === field)
        XCTAssertTrue(frame.accessibilityDeclaredFrameContent === field)
        XCTAssertFalse(field.textInputController === originalController)
        XCTAssertTrue(fixture.runtime.focusedNode === field)
        XCTAssertNil(frame.textInputController)
        let controller = try XCTUnwrap(field.textInputController as? any TextInputAccessibilityValueReplacing)
        XCTAssertTrue(controller.hasCurrentAccessibilityValueOwnership)
        XCTAssertEqual(field.children.count, 2)
        let base = try XCTUnwrap(field.children.first)
        let chrome = try XCTUnwrap(field.children.last)
        XCTAssertFalse(base === chrome)
        XCTAssertTrue(base.isHidden)
        XCTAssertFalse(chrome.isHidden)
        XCTAssertEqual(frameChromePayloadNodes(chrome).filter(\.isTextInputCaret).count, 1)
        for node in frameChromePayloadNodes(chrome) {
            XCTAssertTrue(node.hasClosedTextInputChromePayload)
            XCTAssertNil(node.accessibilityFrameContentStorage)
            XCTAssertNil(node.accessibilityFrameUpdateIdentity)
            XCTAssertNil(node.accessibilitySemanticElement)
            XCTAssertNil(node.accessibilityActionMutationIdentity)
        }
        XCTAssertNotNil(frame.currentAccessibilitySemanticRequest)
        XCTAssertNotNil(field.currentAccessibilitySemanticRequest)
        XCTAssertEqual(field.effectiveAccessibilityMetadata?.label, "Framed editor")
        XCTAssertEqual(field.effectiveAccessibilityMetadata?.value, "adopted")
        XCTAssertEqual(try fixture.snapshot().id, original.id)
    }
}

@MainActor
private final class FrameChromePayloadModel {
    var text = "base"
    var version = 0
    var builds = 0
    var values: [String] = []
    var writeVersions: [Int] = []
    var afterWrite: (() -> Void)?
}

@MainActor
private final class FrameChromePayloadHost {
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let coordinator: StateMountCoordinator
    let source: RuntimeUIAElementTreeSource
    let model: FrameChromePayloadModel
    private var isClosed = false

    init(model: FrameChromePayloadModel) {
        self.model = model
        let size = Size(width: 240, height: 100)
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: size.width, height: size.height)))
        let host = ComponentHost(runtime: runtime)
        let coordinator = StateMountCoordinator(
            invalidate: { [weak host] in host?.reload() },
            observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        self.runtime = runtime
        self.host = host
        self.coordinator = coordinator
        self.source = RuntimeUIAElementTreeSource(runtime: runtime)
        runtime.clock = { 0 }
        host.buildLifecycle = coordinator
        host.shouldUpdate = { [weak self] in self?.isClosed == false }
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { size },
            invalidateHandler: { [weak host] in host?.reload() })
        host.setComponents { [weak self] in
            guard self?.isClosed == false else { return [] }
            model.builds += 1
            let version = model.version
            let binding = Binding<String>(
                get: { model.text },
                set: {
                    model.values.append($0)
                    model.writeVersions.append(version)
                    model.text = $0
                    model.afterWrite?()
                })
            let content = TextField("Field", text: binding).frame(width: 180, height: 32)
                .accessibilityLabel("Framed editor").accessibilityIdentifier("frame-chrome-subject")
            return [makeViewComponent(content, context: context)]
        }
    }

    func field() throws -> ViewNode {
        try XCTUnwrap(frameChromePayloadNodes(runtime.root).first { $0.textInputController != nil })
    }

    func snapshot() throws -> UIAElementSnapshot {
        let matches = source.uiaElementSnapshots().filter { $0.automationID == "frame-chrome-subject" }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

    func render() { if !isClosed { _ = runtime.renderScene() } }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        model.afterWrite = nil
        runtime.stopRenderLifecycleCallbacks()
        coordinator.close()
        host.onReloadCompleted = nil
        host.setComponents { [] }
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private func frameChromePayloadNodes(_ root: ViewNode) -> [ViewNode] {
    var nodes: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        nodes.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return nodes
}
