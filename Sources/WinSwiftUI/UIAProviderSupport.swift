import CUIAInterop
import SwiftWindowsCore
import SwiftWindowsPlatform
import SwiftWindowsUI

// UI Automation projection adapter (Stabilization Roadmap, Phase 2).
//
// Maps the retained runtime's `AccessibilityProjection` output onto the
// platform-neutral `UIAElementTreeSource` consumed by `UIAProviderBridge`
// (in SwiftWindowsPlatform). All tree truth comes from live re-projection of
// the retained `ViewNode` tree; the only state kept here is the stable
// element-id assignment, which UIA requires for runtime ids and for event
// targets across snapshots.

@MainActor
final class RuntimeUIAElementTreeSource: UIAElementTreeSource {
    private final class WeakNode {
        weak var node: ViewNode?

        init(_ node: ViewNode) {
            self.node = node
        }
    }

    // The host owns its runtime. An accessibility bridge may outlive that
    // owner, so keep the projection source without keeping the view tree alive.
    private weak var runtime: RetainedViewRuntime?
    /// Maps root-view-space bounds to screen coordinates; injected so tests
    /// can run headlessly (identity) and the window host can supply the real
    /// client-to-screen conversion.
    private let screenBoundsMapper: (Rect) -> Rect
    private var idsByNode: [ObjectIdentifier: UInt64] = [:]
    private var nodesByID: [UInt64: WeakNode] = [:]
    private var nextID: UInt64 = 1

    init(runtime: RetainedViewRuntime, screenBoundsMapper: @escaping (Rect) -> Rect = { $0 }) {
        self.runtime = runtime
        self.screenBoundsMapper = screenBoundsMapper
    }

    // MARK: - UIAElementTreeSource

    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        guard let runtime else { return [] }
        defer { withExtendedLifetime(runtime) {} }
        pruneDeadNodes()
        guard let root = AccessibilityProjection.project(runtime: runtime) else {
            return []
        }
        var snapshots: [UIAElementSnapshot] = []
        let rootBounds = screenBoundsMapper(root.bounds)
        appendSnapshots(for: root, parentID: nil, rootBounds: rootBounds, into: &snapshots)
        // Transparent retained containers are flattened by the accessibility
        // projection, so the nearest projected parent is the honest UIA
        // Selection container even when it is the window's root pane.
        let selectionParentIDs = Set(
            snapshots.compactMap { snapshot in
                snapshot.isSelected != nil ? snapshot.parentID : nil
            }
        )
        for index in snapshots.indices where selectionParentIDs.contains(snapshots[index].id) {
            snapshots[index].supportsSelection = true
        }
        return snapshots
    }

    @discardableResult
    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool {
        guard let runtime else { return false }
        defer { withExtendedLifetime(runtime) {} }
        guard let element = projectedElement(for: elementID), element.isEnabled else {
            return false
        }
        if element.invokeDefaultAction() {
            return true
        }
        // Controls without explicit accessibility actions still expose their
        // activation handler (e.g. retained buttons) as the UIA Invoke
        // pattern's default action.
        if let onActivate = element.sourceNode?.onActivate {
            onActivate()
            return true
        }
        return false
    }

    func uiaSetFocus(elementID: UInt64) {
        guard let runtime else { return }
        defer { withExtendedLifetime(runtime) {} }
        guard let node = projectedElement(for: elementID)?.sourceNode else {
            return
        }
        runtime.requestFocus(node)
    }

    @discardableResult
    func uiaSetValue(elementID: UInt64, value: String) -> Bool {
        guard let runtime else { return false }
        defer { withExtendedLifetime(runtime) {} }
        guard let element = projectedElement(for: elementID), element.isEnabled,
            element.controlType == .edit,
            !element.traits.contains(.isSecureTextInput),
            let node = element.sourceNode,
            let keyDown = node.onKeyDown,
            let commit = node.onIMEComposition
        else {
            return false
        }

        // The text input owns its Binding and its grapheme-aware replacement
        // rules. Select-all plus its existing Unicode commit path preserves
        // those rules rather than mutating presentation-only accessibility
        // metadata or inventing a second model value.
        runtime.requestFocus(node)
        keyDown(KeyboardEvent(keyCode: 0x41, modifiers: .control))
        if value.isEmpty {
            keyDown(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))
            node.accessibilityValue = nil
        } else {
            commit(IMECompositionEvent(phase: .committed(value)))
            node.accessibilityValue = value
        }
        return true
    }

    @discardableResult
    func uiaToggle(elementID: UInt64) -> Bool {
        guard let runtime else { return false }
        defer { withExtendedLifetime(runtime) {} }
        guard let element = projectedElement(for: elementID), element.controlType == .checkBox else {
            return false
        }
        return uiaInvokeDefaultAction(elementID: elementID)
    }

    @discardableResult
    func uiaSelect(elementID: UInt64) -> Bool {
        guard let runtime else { return false }
        defer { withExtendedLifetime(runtime) {} }
        guard let element = projectedElement(for: elementID), element.traits.contains(.isSelectable),
            element.isEnabled
        else {
            return false
        }
        if element.isSelected {
            return true
        }
        return uiaInvokeDefaultAction(elementID: elementID)
    }

    @discardableResult
    func uiaAddToSelection(elementID: UInt64) -> Bool {
        uiaSelect(elementID: elementID)
    }

    @discardableResult
    func uiaRemoveFromSelection(elementID: UInt64) -> Bool {
        guard let runtime else { return false }
        defer { withExtendedLifetime(runtime) {} }
        guard let element = projectedElement(for: elementID), element.traits.contains(.isSelectable),
            element.isEnabled
        else {
            return false
        }
        if !element.isSelected {
            return true
        }
        return uiaInvokeDefaultAction(elementID: elementID)
    }

    @discardableResult
    func uiaRealizeVirtualizedItem(elementID: UInt64) -> Bool {
        guard let runtime else { return false }
        defer { withExtendedLifetime(runtime) {} }
        guard let element = projectedElement(for: elementID), element.isVirtualizedPlaceholder,
            let node = element.sourceNode
        else {
            return false
        }
        return runtime.scrollToDescendant(node)
    }

    // MARK: - Focus event support

    /// Stable element id for the nearest projected element at or above
    /// `node`. Focus can land on a node that is not itself an accessibility
    /// element (e.g. a control's interactive root with no metadata); UIA
    /// focus events then target the nearest projected ancestor instead.
    func projectedElementID(forNodeOrAncestor node: ViewNode) -> UInt64? {
        guard let runtime else { return nil }
        defer { withExtendedLifetime(runtime) {} }
        guard let root = AccessibilityProjection.project(runtime: runtime) else {
            return nil
        }
        let flattened = root.flattened()
        var current: ViewNode? = node
        while let candidate = current {
            if flattened.contains(where: { $0.sourceNode === candidate }) {
                if candidate === runtime.root {
                    return UIAProviderBridge.rootElementID
                }
                return stableID(for: candidate)
            }
            current = candidate.parent
        }
        return nil
    }

    // MARK: - Snapshot flattening

    private func appendSnapshots(
        for element: AccessibilityElementProjection,
        parentID: UInt64?,
        rootBounds: Rect,
        into list: inout [UIAElementSnapshot]
    ) {
        let id: UInt64
        if parentID == nil {
            id = UIAProviderBridge.rootElementID
        } else if let node = element.sourceNode {
            id = stableID(for: node)
        } else {
            // Projections always carry a source node; this is a defensive
            // fallback that keeps the tree navigable if one ever does not.
            id = nextEphemeralID()
        }

        let screenBounds = screenBoundsMapper(element.bounds)
        let isPassword = element.traits.contains(.isSecureTextInput)
        let supportsValue = element.controlType == .edit && !isPassword
        let isSelected: Bool? = element.traits.contains(.isSelectable) ? element.isSelected : nil

        list.append(
            UIAElementSnapshot(
                id: id,
                parentID: parentID,
                name: element.name,
                value: element.value,
                helpText: element.hint,
                automationID: element.identifier,
                controlType: Self.controlTypeID(for: element.controlType),
                bounds: screenBounds,
                isEnabled: element.isEnabled,
                hasKeyboardFocus: element.isFocused,
                isKeyboardFocusable: element.sourceNode?.isFocusable ?? false,
                isOffscreen: element.isVirtualizedPlaceholder || screenBounds.intersected(with: rootBounds) == nil,
                hasDefaultAction: !element.actions.isEmpty || element.sourceNode?.onActivate != nil,
                isPassword: isPassword,
                supportsValue: supportsValue,
                isReadOnly: !element.isEnabled || element.sourceNode?.onIMEComposition == nil,
                toggleState: element.controlType == .checkBox ? (element.isSelected ? .on : .off) : nil,
                isSelected: isSelected,
                isVirtualizedPlaceholder: element.isVirtualizedPlaceholder
            )
        )

        for child in element.children {
            appendSnapshots(for: child, parentID: id, rootBounds: rootBounds, into: &list)
        }
    }

    private func projectedElement(for id: UInt64) -> AccessibilityElementProjection? {
        guard let runtime, let root = AccessibilityProjection.project(runtime: runtime) else {
            return nil
        }
        if id == UIAProviderBridge.rootElementID {
            return root
        }
        guard let node = nodesByID[id]?.node else {
            return nil
        }
        return root.flattened().first(where: { $0.sourceNode === node })
    }

    // MARK: - Stable element ids

    private func stableID(for node: ViewNode) -> UInt64 {
        let key = ObjectIdentifier(node)
        if let existing = idsByNode[key] {
            // Refresh the weak back-reference: an ObjectIdentifier can be
            // reused by a new allocation after the old node died.
            nodesByID[existing] = WeakNode(node)
            return existing
        }
        let id = nextID
        nextID += 1
        idsByNode[key] = id
        nodesByID[id] = WeakNode(node)
        return id
    }

    private func nextEphemeralID() -> UInt64 {
        let id = nextID
        nextID += 1
        return id
    }

    private func pruneDeadNodes() {
        let deadIDs = nodesByID.filter { $0.value.node == nil }.map(\.key)
        guard !deadIDs.isEmpty else {
            return
        }
        for id in deadIDs {
            nodesByID.removeValue(forKey: id)
        }
        let liveIDs = Set(nodesByID.keys)
        idsByNode = idsByNode.filter { liveIDs.contains($0.value) }
    }

    // MARK: - Control type mapping

    /// `AccessibilityControlType` → UIA control type id (constants mirrored
    /// and static-asserted in CUIAInterop).
    static func controlTypeID(for controlType: AccessibilityControlType) -> Int32 {
        switch controlType {
        case .button: return Int32(SWU_UIA_CONTROL_TYPE_BUTTON)
        case .text: return Int32(SWU_UIA_CONTROL_TYPE_TEXT)
        case .edit: return Int32(SWU_UIA_CONTROL_TYPE_EDIT)
        case .checkBox: return Int32(SWU_UIA_CONTROL_TYPE_CHECK_BOX)
        case .header: return Int32(SWU_UIA_CONTROL_TYPE_HEADER)
        case .hyperlink: return Int32(SWU_UIA_CONTROL_TYPE_HYPERLINK)
        case .image: return Int32(SWU_UIA_CONTROL_TYPE_IMAGE)
        case .slider: return Int32(SWU_UIA_CONTROL_TYPE_SLIDER)
        case .progressBar: return Int32(SWU_UIA_CONTROL_TYPE_PROGRESS_BAR)
        case .list: return Int32(SWU_UIA_CONTROL_TYPE_LIST)
        case .listItem: return Int32(SWU_UIA_CONTROL_TYPE_LIST_ITEM)
        case .tab: return Int32(SWU_UIA_CONTROL_TYPE_TAB)
        case .tabItem: return Int32(SWU_UIA_CONTROL_TYPE_TAB_ITEM)
        case .group: return Int32(SWU_UIA_CONTROL_TYPE_GROUP)
        case .pane: return Int32(SWU_UIA_CONTROL_TYPE_PANE)
        case .window: return Int32(SWU_UIA_CONTROL_TYPE_WINDOW)
        case .custom: return Int32(SWU_UIA_CONTROL_TYPE_CUSTOM)
        }
    }
}
