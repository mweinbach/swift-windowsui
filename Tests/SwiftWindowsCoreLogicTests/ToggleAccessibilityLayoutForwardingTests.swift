import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class ToggleLayoutModel {
    var isOn = false
    var writes: [Bool] = []
    var writeVersions: [Int] = []
    var version = 0
    var isHidden = false
    var labelActions = 0
    var text = "Editor"

    var binding: Binding<Bool> {
        let version = version
        return Binding(
            get: { self.isOn },
            set: {
                self.isOn = $0
                self.writes.append($0)
                self.writeVersions.append(version)
            })
    }

    var textBinding: Binding<String> {
        Binding(get: { self.text }, set: { self.text = $0 })
    }
}

@MainActor
private final class ToggleLayoutHost {
    let runtime: RetainedViewRuntime
    let componentHost: ComponentHost
    let coordinator: StateMountCoordinator
    let source: RuntimeUIAElementTreeSource
    private var isClosed = false

    init(content: @escaping @MainActor () -> AnyView) {
        let size = Size(width: 420, height: 280)
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: size.width, height: size.height)))
        runtime.clock = { 0 }
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

    func render() { if !isClosed { _ = runtime.renderScene() } }
    func reload() { if !isClosed { componentHost.reload() } }

    func snapshot(_ identifier: String = "subject") throws -> UIAElementSnapshot {
        let matches = source.uiaElementSnapshots().filter { $0.automationID == identifier }
        XCTAssertEqual(matches.count, 1, identifier)
        return try XCTUnwrap(matches.first)
    }

    func projection(_ identifier: String = "subject") throws -> AccessibilityElementProjection {
        let matches = (AccessibilityProjection.project(runtime: runtime)?.flattened() ?? [])
            .filter { $0.identifier == identifier }
        XCTAssertEqual(matches.count, 1, identifier)
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
private func toggleLayoutNodes(_ root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

/// Additive source behavior requirements for factory-owned labeled switch rows.
/// The original frame forwarding tests remain unchanged.
@MainActor
final class ToggleAccessibilityLayoutForwardingTests: XCTestCase {
    func testDefaultAndExplicitSwitchForwardThroughZeroOneAndTwoFrames() async throws {
        for explicitSwitch in [false, true] {
            for frameCount in 0...2 {
                for initialValue in [false, true] {
                    let model = ToggleLayoutModel()
                    model.isOn = initialValue
                    let host = ToggleLayoutHost {
                        let control = Toggle("Toggle label", isOn: model.binding)
                        var view = explicitSwitch ? AnyView(control.toggleStyle(.switch)) : AnyView(control)
                        for _ in 0..<frameCount { view = AnyView(view.frame(width: 240, height: 40)) }
                        return AnyView(view.accessibilityIdentifier("subject"))
                    }
                    defer { host.close() }
                    host.render()
                    let projection = try host.projection()
                    let actual = try XCTUnwrap(projection.sourceNode)
                    let row = try XCTUnwrap(actual.parent)
                    XCTAssertTrue(actual.accessibilityTraits.contains(.isToggle))
                    XCTAssertTrue(row.accessibilityDeclaredFrameContent === actual)
                    XCTAssertEqual(row.children.count, 2)
                    XCTAssertNil(row.onActivate)
                    XCTAssertFalse(row.isHitTestVisible)
                    if case .stack(let layout) = row.layoutMode {
                        XCTAssertEqual(layout, .horizontal(spacing: 10, alignment: .center))
                    } else {
                        XCTFail("The switch row must keep its existing horizontal layout")
                    }
                    XCTAssertEqual(projection.controlType, .checkBox)
                    XCTAssertEqual(projection.isSelected, initialValue)
                    let snapshot = try host.snapshot()
                    XCTAssertNotEqual(snapshot.id, UIAProviderBridge.rootElementID)
                    XCTAssertEqual(snapshot.controlType, Int32(SWU_UIA_CONTROL_TYPE_CHECK_BOX))
                    XCTAssertTrue(host.source.uiaToggle(elementID: snapshot.id))
                    XCTAssertEqual(model.writes, [!initialValue])
                    XCTAssertEqual(model.writeVersions, [0])
                }
            }
        }
    }

    func testGroupedFormDeclaresBothExactEdgesWithoutForwardingOtherRows() async throws {
        let model = ToggleLayoutModel()
        let host = ToggleLayoutHost {
            AnyView(
                Form {
                    Toggle(isOn: model.binding) {
                        Text("Grouped toggle label").accessibilityIdentifier("toggle-label")
                    }
                    .accessibilityIdentifier("subject")
                    TextField("Other editor", text: model.textBinding).accessibilityIdentifier("other-editor")
                }
                .formStyle(.grouped))
        }
        defer { host.close() }
        host.render()
        let actual = try XCTUnwrap(try host.projection().sourceNode)
        let valueColumn = try XCTUnwrap(actual.parent)
        let row = try XCTUnwrap(valueColumn.parent)
        XCTAssertTrue(actual.accessibilityTraits.contains(.isToggle))
        XCTAssertTrue(valueColumn.accessibilityDeclaredFrameContent === actual)
        XCTAssertTrue(row.accessibilityDeclaredFrameContent === valueColumn)
        XCTAssertEqual(row.formRowLabelChildIndex, 0)
        XCTAssertEqual(row.children.count, 2)
        let labelColumn = try XCTUnwrap(row.children.first)
        let declaredColumn = try XCTUnwrap(row.children.dropFirst().first)
        XCTAssertTrue(declaredColumn === valueColumn)
        XCTAssertNil(labelColumn.accessibilityDeclaredFrameContent)
        XCTAssertNil(row.onActivate)
        XCTAssertNil(valueColumn.onActivate)
        XCTAssertEqual(try host.projection("toggle-label").name, "Grouped toggle label")
        let otherRows = toggleLayoutNodes(host.runtime.root).filter {
            $0.formRowLabelChildIndex != nil && $0 !== row
        }
        XCTAssertEqual(otherRows.count, 1)
        XCTAssertTrue(otherRows.allSatisfy { $0.accessibilityDeclaredFrameContent == nil })
        // This change does not forward other grouped control factories. Their
        // existing outer Group and actual editor descendant stay separate.
        let otherRow = try host.snapshot("other-editor")
        XCTAssertEqual(otherRow.controlType, Int32(SWU_UIA_CONTROL_TYPE_GROUP))
        XCTAssertFalse(otherRow.supportsValue)
        let editors = host.source.uiaElementSnapshots().filter {
            $0.controlType == Int32(SWU_UIA_CONTROL_TYPE_EDIT)
        }
        XCTAssertEqual(editors.count, 1)
        XCTAssertTrue(try XCTUnwrap(editors.first).supportsValue)
        XCTAssertTrue(host.source.uiaToggle(elementID: try host.snapshot().id))
        XCTAssertEqual(model.writes, [true])
        XCTAssertEqual(model.text, "Editor")
    }

    func testLabelSiblingKeepsItsOwnActionAndNeverBecomesTheToggleTarget() async throws {
        let model = ToggleLayoutModel()
        let host = ToggleLayoutHost {
            AnyView(
                Toggle(isOn: model.binding) {
                    Text("Switch label").accessibilityIdentifier("label-text")
                    Button("Label help") { model.labelActions += 1 }.accessibilityIdentifier("label-action")
                }
                .frame(width: 320, height: 50).accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        XCTAssertEqual(try host.projection("label-text").name, "Switch label")
        let labelAction = try host.snapshot("label-action")
        let toggle = try host.snapshot()
        XCTAssertNotEqual(labelAction.id, toggle.id)
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: labelAction.id))
        XCTAssertEqual(model.labelActions, 1)
        XCTAssertTrue(model.writes.isEmpty)
        XCTAssertTrue(host.source.uiaToggle(elementID: toggle.id))
        XCTAssertEqual(model.writes, [true])
        XCTAssertEqual(model.labelActions, 1)
    }

    func testMetadataOverridesAndExplicitChildBoundaryKeepTheirMeaning() async throws {
        let model = ToggleLayoutModel()
        let host = ToggleLayoutHost {
            AnyView(
                Toggle("Visible label", isOn: model.binding)
                    .accessibilityLabel("Inner name").accessibilityHint("Inner hint")
                    .accessibilityIdentifier("inner-identifier")
                    .frame(width: 250, height: 40)
                    .accessibilityLabel("Outer name").accessibilityHint("Outer hint")
                    .accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let projection = try host.projection()
        XCTAssertEqual(projection.name, "Outer name")
        XCTAssertEqual(projection.hint, "Outer hint")
        XCTAssertEqual(projection.controlType, .checkBox)
        XCTAssertTrue(try XCTUnwrap(projection.sourceNode).accessibilityTraits.contains(.isToggle))
        XCTAssertFalse(host.source.uiaElementSnapshots().contains { $0.automationID == "inner-identifier" })
        XCTAssertTrue(host.source.uiaToggle(elementID: try host.snapshot().id))
        XCTAssertEqual(model.writes, [true])
        let boundaryModel = ToggleLayoutModel()
        let boundaryHost = ToggleLayoutHost {
            AnyView(
                Toggle("Boundary label", isOn: boundaryModel.binding)
                    .accessibilityElement(children: .contain)
                    .frame(width: 250, height: 40).accessibilityIdentifier("subject"))
        }
        defer { boundaryHost.close() }
        boundaryHost.render()
        let boundary = try boundaryHost.projection()
        XCTAssertEqual(boundary.controlType, .group)
        XCTAssertFalse(try XCTUnwrap(boundary.sourceNode).accessibilityTraits.contains(.isToggle))
        XCTAssertFalse(boundaryHost.source.uiaToggle(elementID: try boundaryHost.snapshot().id))
        XCTAssertTrue(boundaryModel.writes.isEmpty)
    }

    func testDisabledAndHiddenSwitchRowsDoNotWrite() async throws {
        let disabledModel = ToggleLayoutModel()
        let disabled = ToggleLayoutHost {
            AnyView(
                Toggle("Disabled", isOn: disabledModel.binding).disabled(true)
                    .frame(width: 200, height: 40).accessibilityIdentifier("subject"))
        }
        defer { disabled.close() }
        disabled.render()
        let snapshot = try disabled.snapshot()
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertFalse(disabled.source.uiaToggle(elementID: snapshot.id))
        XCTAssertTrue(disabledModel.writes.isEmpty)

        let hiddenModel = ToggleLayoutModel()
        let hidden = ToggleLayoutHost {
            AnyView(
                Toggle("Hidden", isOn: hiddenModel.binding).frame(width: 200, height: 40)
                    .accessibilityIdentifier("subject").accessibilityHidden(hiddenModel.isHidden))
        }
        defer { hidden.close() }
        hidden.render()
        let visibleID = try hidden.snapshot().id
        let saved = try hidden.projection()
        hiddenModel.isHidden = true
        hidden.reload()
        hidden.render()
        XCTAssertFalse(hidden.source.uiaElementSnapshots().contains { $0.automationID == "subject" })
        XCTAssertFalse(hidden.source.uiaToggle(elementID: visibleID))
        XCTAssertFalse(saved.invokeDefaultAction())
        XCTAssertTrue(hiddenModel.writes.isEmpty)
    }

    func testRebuildMapsToRetainedSwitchAndRejectsTheSavedPublication() async throws {
        let model = ToggleLayoutModel()
        let host = ToggleLayoutHost {
            AnyView(
                Toggle("Label \(model.version)", isOn: model.binding)
                    .frame(width: 250, height: 40).accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let oldProjection = try host.projection()
        let actual = try XCTUnwrap(oldProjection.sourceNode)
        let originalRow = try XCTUnwrap(actual.parent)
        let id = try host.snapshot().id
        model.version = 1
        host.reload()
        host.render()
        let current = try host.projection()
        XCTAssertTrue(current.sourceNode === actual)
        XCTAssertTrue(actual.parent === originalRow)
        XCTAssertTrue(originalRow.accessibilityDeclaredFrameContent === actual)
        XCTAssertEqual(try host.snapshot().id, id)
        XCTAssertFalse(oldProjection.invokeDefaultAction())
        XCTAssertTrue(model.writes.isEmpty)
        XCTAssertTrue(host.source.uiaToggle(elementID: id))
        XCTAssertEqual(model.writes, [true])
        XCTAssertEqual(model.writeVersions, [1])
    }

    func testRemovingAndRestoringDeclaredSwitchDoesNotReviveSavedAuthority() async throws {
        let model = ToggleLayoutModel()
        let host = ToggleLayoutHost {
            AnyView(Toggle("Toggle", isOn: model.binding).accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let saved = try host.projection()
        let actual = try XCTUnwrap(saved.sourceNode)
        let row = try XCTUnwrap(actual.parent)
        let originalOrder = row.children
        XCTAssertTrue(saved.semanticRequest?.isCurrent == true)
        row.removeChild(actual)
        row.addChild(actual)
        XCTAssertEqual(row.children.map(ObjectIdentifier.init), originalOrder.map(ObjectIdentifier.init))
        XCTAssertTrue(row.accessibilityDeclaredFrameContent === actual)
        XCTAssertFalse(saved.semanticRequest?.isCurrent == true)
        XCTAssertFalse(saved.invokeDefaultAction())
        XCTAssertTrue(model.writes.isEmpty)
    }

    func testBareLabeledToggleRootKeepsWindowZeroSeparateFromSwitch() async throws {
        let model = ToggleLayoutModel()
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 100)))
        runtime.clock = { 0 }
        defer {
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            runtime.root.removeAllChildren()
        }
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 320, height: 100) }, invalidateHandler: {})
        let candidate = Toggle("Root switch label", isOn: model.binding).accessibilityIdentifier("subject")
            .makeComponent(context: context).makeNode(runtime: runtime)
        XCTAssertTrue(ComponentHost.adopt(source: candidate, into: runtime.root).completed)
        _ = runtime.renderScene()
        let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")
        let snapshots = source.uiaElementSnapshots()
        let window = try XCTUnwrap(snapshots.first { $0.id == UIAProviderBridge.rootElementID })
        let switches = snapshots.filter { $0.automationID == "subject" }
        XCTAssertEqual(switches.count, 1)
        let control = try XCTUnwrap(switches.first)
        XCTAssertEqual(window.controlType, Int32(SWU_UIA_CONTROL_TYPE_PANE))
        XCTAssertEqual(window.name, "Window caption")
        XCTAssertFalse(window.hasDefaultAction)
        XCTAssertFalse(window.isKeyboardFocusable)
        XCTAssertNotEqual(control.id, UIAProviderBridge.rootElementID)
        XCTAssertEqual(control.parentID, UIAProviderBridge.rootElementID)
        XCTAssertEqual(control.controlType, Int32(SWU_UIA_CONTROL_TYPE_CHECK_BOX))
        XCTAssertTrue(snapshots.contains { $0.name == "Root switch label" && $0.id != control.id })
        XCTAssertFalse(source.uiaToggle(elementID: UIAProviderBridge.rootElementID))
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: UIAProviderBridge.rootElementID))
        XCTAssertFalse(source.uiaSetFocusResult(elementID: UIAProviderBridge.rootElementID))
        XCTAssertTrue(model.writes.isEmpty)
        XCTAssertTrue(source.uiaToggle(elementID: control.id))
        XCTAssertEqual(model.writes, [true])
    }
}
