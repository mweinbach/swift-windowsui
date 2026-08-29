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

    /// The effect is already finished when this leaves the dispatch frame.
    /// No editor or application capture is kept alive by this receipt.
    private struct ValueCompletion {
        let result: TextInputAccessibilityValueResult
        let target: RetainedAccessibilityTarget
        weak var controller: (any RetainedTextInputController)?
        let focusRevision: UInt64
        let mutationRevision: UInt64
    }

    // The host owns its runtime. An accessibility bridge may outlive that
    // owner, so keep the projection source without keeping the view tree alive.
    private weak var runtime: RetainedViewRuntime?
    /// Legacy/headless mapping. Production native requests supply their copied
    /// geometry explicitly and never call this potentially effectful closure.
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
        elementSnapshots(screenBoundsMapper: screenBoundsMapper)
    }

    func uiaElementSnapshots(geometry: NativeWindowGeometry) throws -> [UIAElementSnapshot] {
        try elementSnapshots { bounds in
            guard let mapped = geometry.clientRectToScreen(bounds) else {
                throw UIAProviderRequestFailure.invalidGeometry
            }
            return mapped
        }
    }

    private func elementSnapshots(
        screenBoundsMapper: (Rect) throws -> Rect
    ) rethrows -> [UIAElementSnapshot] {
        guard let runtime else { return [] }
        defer { withExtendedLifetime(runtime) {} }
        pruneDeadNodes()
        guard let root = AccessibilityProjection.project(runtime: runtime) else {
            return []
        }
        var snapshots: [UIAElementSnapshot] = []
        let rootBounds = try screenBoundsMapper(root.bounds)
        try appendSnapshots(
            for: root, parentID: nil, rootBounds: rootBounds, into: &snapshots,
            screenBoundsMapper: screenBoundsMapper)
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
        withMutation { runtime, _ in
            invokeDefaultAction(elementID: elementID, in: runtime, intent: .invoke)
        }
    }

    func uiaSetFocus(elementID: UInt64) {
        _ = uiaSetFocusResult(elementID: elementID)
    }

    /// The legacy source/COM callback remains Void. This internal result is
    /// true only when the guarded retained transition is still qualified;
    /// false does not imply its earlier focus callbacks had no effects.
    func uiaSetFocusResult(elementID: UInt64) -> Bool {
        withMutation { runtime, _ in
            setFocusResult(elementID: elementID, in: runtime)
        }
    }

    @inline(never)
    private func setFocusResult(elementID: UInt64, in runtime: RetainedViewRuntime) -> Bool {
        guard runtime.permitsRetainedActionInvocation,
            let node = elementID == UIAProviderBridge.rootElementID ? runtime.root : nodesByID[elementID]?.node
        else { return false }
        return runtime.requestAccessibilityFocus(node)
    }

    @discardableResult
    func uiaSetValue(elementID: UInt64, value: String) -> Bool {
        withMutation { runtime, mutation in
            setValue(elementID: elementID, value: value, in: runtime, during: mutation)
        }
    }

    @discardableResult
    func uiaToggle(elementID: UInt64) -> Bool {
        withMutation { runtime, _ in
            invokeDefaultAction(elementID: elementID, in: runtime, intent: .toggle)
        }
    }

    @discardableResult
    func uiaSelect(elementID: UInt64) -> Bool {
        withMutation { runtime, _ in
            invokeDefaultAction(elementID: elementID, in: runtime, intent: .select)
        }
    }

    @discardableResult
    func uiaAddToSelection(elementID: UInt64) -> Bool {
        uiaSelect(elementID: elementID)
    }

    @discardableResult
    func uiaRemoveFromSelection(elementID: UInt64) -> Bool {
        withMutation { runtime, _ in
            invokeDefaultAction(elementID: elementID, in: runtime, intent: .removeFromSelection)
        }
    }

    @discardableResult
    func uiaRealizeVirtualizedItem(elementID: UInt64) -> Bool {
        withMutation { runtime, mutation in
            realize(elementID: elementID, in: runtime, during: mutation)
        }
    }

    @inline(never)
    private func withMutation(
        _ perform: (RetainedViewRuntime, RetainedAccessibilityMutation) -> Bool
    ) -> Bool {
        guard let runtime, let mutation = runtime.beginAccessibilityMutation() else { return false }
        defer {
            runtime.endAccessibilityMutation(mutation)
            withExtendedLifetime(runtime) {}
        }
        // Inner helpers release callback captures before admission is opened
        // again. A false result after an effect never schedules another attempt.
        return perform(runtime, mutation)
    }

    @inline(never)
    private func realize(
        elementID: UInt64, in runtime: RetainedViewRuntime, during mutation: RetainedAccessibilityMutation
    ) -> Bool {
        guard let node = retainedNode(for: elementID, in: runtime),
            let target = runtime.accessibilityTarget(for: node)
        else { return false }
        return runtime.realizeAccessibilityTarget(target, during: mutation)
    }

    @inline(never)
    private func setValue(
        elementID: UInt64, value: String, in runtime: RetainedViewRuntime,
        during mutation: RetainedAccessibilityMutation
    ) -> Bool {
        let completion = dispatchValue(elementID: elementID, value: value, in: runtime, during: mutation)
        // Retired original controllers can release arbitrary Binding captures
        // when dispatchValue returns. Admission is still held here. Do not
        // absorb effects of those destructors into the completed operation.
        guard let completion, completion.result.didDispatch, completion.result.accepted,
            completion.mutationRevision == mutation.revision,
            let controller = completion.controller,
            completion.target.node?.textInputController === controller
        else { return false }
        return Self.valueTargetIsCurrent(
            completion.target, in: runtime, during: mutation, focusRevision: completion.focusRevision)
    }

    @inline(never)
    private func dispatchValue(
        elementID: UInt64, value: String, in runtime: RetainedViewRuntime,
        during mutation: RetainedAccessibilityMutation
    ) -> ValueCompletion? {
        guard let node = retainedNode(for: elementID, in: runtime),
            let target = runtime.accessibilityTarget(for: node),
            let original = node.textInputController as? any TextInputAccessibilityValueReplacing,
            Self.isWritableValueNode(node)
        else { return nil }
        defer { withExtendedLifetime(original) {} }
        // The capability is the selected handler. Keep that exact controller
        // before any focus/layout callback; a replacement may not inherit the
        // request. Raw key and IME handlers are never a fallback.
        guard runtime.requestAccessibilityFocus(node),
            runtime.isAccessibilityTargetCurrent(target, during: mutation),
            node.textInputController === original
        else { return nil }
        let focusRevision = runtime.presentationFocusRevision
        guard Self.valueTargetIsCurrent(target, in: runtime, during: mutation, focusRevision: focusRevision) else {
            return nil
        }
        let result = original.replaceValueForAccessibility(
            value,
            validation: TextInputAccessibilityValueValidation(
                mayDispatch: {
                    node.textInputController === original
                        && Self.valueTargetIsCurrent(
                            target, in: runtime, during: mutation, focusRevision: focusRevision)
                },
                isRetainedTargetCurrent: {
                    Self.valueTargetIsCurrent(
                        target, in: runtime, during: mutation, focusRevision: focusRevision)
                }))
        // A compatible setter rebuild can replace the controller while the
        // capability preserves the accepted edit. Publish that completion's
        // weak identity before releasing the original controller's captures.
        return ValueCompletion(
            result: result, target: target, controller: node.textInputController,
            focusRevision: focusRevision, mutationRevision: mutation.revision)
    }

    private static func isWritableValueNode(_ node: ViewNode) -> Bool {
        guard AccessibilityProjection.resolveControlType(for: node) == .edit,
            !node.accessibilityTraits.contains(.isSecureTextInput),
            let controller = node.textInputController as? any TextInputAccessibilityValueReplacing
        else { return false }
        return controller.hasCurrentAccessibilityValueOwnership
    }

    /// Only stored retained state is read. Normal editor completion deliberately
    /// dirties layout, so an earlier settled/prepaint receipt cannot authorize
    /// or reject this semantic check. It never supplies geometry to UIA.
    private static func valueTargetIsCurrent(
        _ target: RetainedAccessibilityTarget, in runtime: RetainedViewRuntime,
        during mutation: RetainedAccessibilityMutation, focusRevision: UInt64
    ) -> Bool {
        guard runtime.isAccessibilityTargetCurrent(target, during: mutation), let node = target.node,
            runtime.focusedNode === node, node.isFocused, node.isFocusable,
            runtime.presentationFocusRevision == focusRevision, isWritableValueNode(node),
            runtime.permitsConservativeAccessibilityValueTarget(node),
            let element = AccessibilityProjection.project(root: runtime.root)?.flattened().first(where: {
                $0.sourceNode === node
            }),
            element.controlType == .edit, element.isEnabled, element.permitsModalActions,
            !element.isVirtualizedPlaceholder, !element.traits.contains(.isSecureTextInput)
        else { return false }
        return true
    }

    private func retainedNode(for elementID: UInt64, in runtime: RetainedViewRuntime) -> ViewNode? {
        elementID == UIAProviderBridge.rootElementID ? runtime.root : nodesByID[elementID]?.node
    }

    @inline(never)
    private func invokeDefaultAction(
        elementID: UInt64, in runtime: RetainedViewRuntime, intent: AccessibilityDefaultActionIntent
    ) -> Bool {
        guard runtime.permitsRetainedActionInvocation,
            let node = elementID == UIAProviderBridge.rootElementID ? runtime.root : nodesByID[elementID]?.node
        else { return false }
        // Role, selection state, and the handler belong to one post-query
        // element. A pre-query predicate must not authorize a different role
        // or an obsolete selection transition after layout callbacks run.
        return AccessibilityProjection.invokeDefaultAction(on: node, in: runtime, intent: intent)
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
        into list: inout [UIAElementSnapshot],
        screenBoundsMapper: (Rect) throws -> Rect
    ) rethrows {
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

        let screenBounds = try screenBoundsMapper(element.bounds)
        let isPassword = element.traits.contains(.isSecureTextInput)
        let supportsValue = element.controlType == .edit && !isPassword
        let isSelected: Bool? = element.traits.contains(.isSelectable) ? element.isSelected : nil
        let hasWritableCapability: Bool
        if let node = element.sourceNode {
            hasWritableCapability = Self.isWritableValueNode(node)
        } else {
            hasWritableCapability = false
        }

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
                hasDefaultAction: element.permitsModalActions
                    && (!element.actions.isEmpty || element.sourceNode?.onActivate != nil),
                isPassword: isPassword,
                supportsValue: supportsValue,
                isReadOnly: !element.isEnabled || !hasWritableCapability,
                toggleState: element.controlType == .checkBox ? (element.isSelected ? .on : .off) : nil,
                isSelected: isSelected,
                isVirtualizedPlaceholder: element.isVirtualizedPlaceholder
            )
        )

        for child in element.children {
            try appendSnapshots(
                for: child, parentID: id, rootBounds: rootBounds, into: &list,
                screenBoundsMapper: screenBoundsMapper)
        }
    }

    // MARK: - Stable element ids

    private func stableID(for node: ViewNode) -> UInt64 {
        let key = ObjectIdentifier(node)
        if let existing = idsByNode[key], nodesByID[existing]?.node === node {
            // A reused allocation address must not retarget an old UIA id.
            // Only the exact still-live node keeps its previous identity.
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
