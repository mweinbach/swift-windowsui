import SwiftWindowsCore

// Accessibility projection (Stabilization Roadmap, Phase 2 — headless slice).
//
// This file derives a platform-neutral accessibility element tree from a
// retained `ViewNode` tree at call time. It is the mapping layer a future
// Win32 UI Automation provider (WM_GETOBJECT wiring) will serve to assistive
// technology clients. Everything here is recomputed from live retained state
// on every `project` call — there is no second persistent tree and no cache
// that can go stale.
//
// Coordinate contract: projected bounds are in root-view space and mirror the
// painter/hit-test math in `Runtime.swift` exactly — a node's absolute origin
// is its parent's origin plus `resolvedFrame.origin`, a scroll container
// shifts its children's origins by `-resolvedScrollOffset`, and every node's
// transform is centered on its already-transformed frame before composing
// after its ancestors. Bounds are axis-aligned enclosures of that painted
// geometry, including for off-screen virtualized placeholders. The projection
// consumes the runtime's internal resolved layout state (`resolvedFrame`,
// `resolvedScrollOffset`) via same-module internal access, so no
// `Runtime.swift` visibility change was needed. Callers should re-project
// after a layout pass so bounds track the latest resize/scroll.

/// UIA-style control types projected from retained accessibility metadata.
///
/// The case names follow UI Automation control types so the later Win32
/// provider wave can map them mechanically. Cases with no current trait
/// mapping (`list`, `listItem`, `tab`, `tabItem`, `window`) are declared for
/// the provider wave; see the mapping table on
/// `AccessibilityProjection.resolveControlType`.
public enum AccessibilityControlType: String, Sendable, Equatable, CaseIterable {
    case button
    case text
    case edit
    case checkBox
    case header
    case hyperlink
    case image
    case slider
    case progressBar
    case list
    case listItem
    case tab
    case tabItem
    case group
    case pane
    case window
    case custom
}

/// A named, invokable action projected from a node's stored
/// `accessibilityActions` entry. `invoke()` calls through to the retained
/// node's stored closure at invocation time.
public struct AccessibilityProjectedAction {
    /// Display name: the stored action's name, or a fallback derived from
    /// its kind (e.g. "Increment" for `.increment`).
    public let name: String
    public let kind: RetainedAccessibilityActionKind?
    /// True when the stored action is the node's `.default` (activate) action.
    public let isDefault: Bool
    private let handler: () -> Bool

    public init(name: String, kind: RetainedAccessibilityActionKind?, isDefault: Bool, handler: @escaping () -> Void) {
        self.name = name
        self.kind = kind
        self.isDefault = isDefault
        self.handler = {
            handler()
            return true
        }
    }

    fileprivate init(
        name: String, kind: RetainedAccessibilityActionKind?, isDefault: Bool,
        invoke: @escaping () -> Bool
    ) {
        self.name = name
        self.kind = kind
        self.isDefault = isDefault
        self.handler = invoke
    }

    public func invoke() {
        _ = invokeIfPermitted()
    }

    fileprivate func invokeIfPermitted() -> Bool {
        handler()
    }
}

/// A platform-neutral accessibility element derived from a `ViewNode`.
///
/// Instances are snapshots produced by `AccessibilityProjection.project`;
/// they are value-like reads of retained state at projection time and are
/// discarded and rebuilt on the next projection pass.
@MainActor
public final class AccessibilityElementProjection {
    /// Bounds in root-view space (see the coordinate contract at the top of
    /// this file). Zero-size for nodes whose layout has not yet resolved a
    /// size.
    public let bounds: Rect
    /// Accessible name: `accessibilityLabel`, falling back to the node's
    /// bitmap text, and (for `.combine` containers) to descendant text.
    public let name: String
    public let value: String?
    public let hint: String?
    public let identifier: String?
    public let controlType: AccessibilityControlType
    /// The retained traits the projection was derived from, kept verbatim so
    /// the provider wave can map behavioral traits (`.updatesFrequently`,
    /// `.isModal`, ...) to UIA patterns/events without re-walking the tree.
    public let traits: RetainedAccessibilityTraits
    public let headingLevel: RetainedAccessibilityHeadingLevel?
    public let isEnabled: Bool
    public let isFocused: Bool
    public let isSelected: Bool
    /// The node's `accessibilitySortPriority`, retained for provider-side
    /// ordering decisions and testing. Siblings are already ordered by it.
    public let sortPriority: Double
    public let actions: [AccessibilityProjectedAction]
    public private(set) var children: [AccessibilityElementProjection]
    /// The retained node this element was projected from. Weak: the retained
    /// tree owns node lifetimes, and projections are short-lived reads.
    public private(set) weak var sourceNode: ViewNode?
    /// True when this element stands in for a subtree a lazy stack has not
    /// laid out yet — an off-screen row of a virtualized list.
    ///
    /// Its own `bounds` are real: a virtualizing stack still *places* every
    /// child, so the row rectangle is the same one an eager stack would
    /// produce. What does not exist yet is the geometry of anything inside
    /// it, so the element is projected childless rather than with a subtree
    /// of stale or zero-size rectangles — bounds are the one thing a UIA
    /// client is entitled to trust. The provider wave maps this onto the
    /// `VirtualizedItem` pattern; `Realize` is a layout pass away, because
    /// scrolling the row into view lays it out.
    public let isVirtualizedPlaceholder: Bool
    fileprivate var isStructuralModalAncestor = false
    fileprivate var implicitDefaultAction: (@MainActor () -> Bool)?

    /// Structural modal ancestors remain in the tree for bounds/navigation,
    /// but their activation fallback is no more eligible than stored actions.
    package var permitsModalActions: Bool { !isStructuralModalAncestor }

    public init(
        bounds: Rect,
        name: String,
        value: String?,
        hint: String?,
        identifier: String?,
        controlType: AccessibilityControlType,
        traits: RetainedAccessibilityTraits,
        headingLevel: RetainedAccessibilityHeadingLevel?,
        isEnabled: Bool,
        isFocused: Bool,
        isSelected: Bool,
        sortPriority: Double,
        actions: [AccessibilityProjectedAction],
        children: [AccessibilityElementProjection],
        sourceNode: ViewNode?,
        isVirtualizedPlaceholder: Bool = false
    ) {
        self.bounds = bounds
        self.name = name
        self.value = value
        self.hint = hint
        self.identifier = identifier
        self.controlType = controlType
        self.traits = traits
        self.headingLevel = headingLevel
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.isSelected = isSelected
        self.sortPriority = sortPriority
        self.actions = actions
        self.children = children
        self.sourceNode = sourceNode
        self.isVirtualizedPlaceholder = isVirtualizedPlaceholder
    }

    /// Invokes the stored default action, or the first stored action when no
    /// kind is marked. A projection with no stored actions can instead invoke
    /// current activation while the source's stored action list remains empty.
    /// Returns true when the selected Void handler was called; its internal
    /// action owner may still reject the effect.
    @discardableResult
    public func invokeDefaultAction() -> Bool {
        guard isEnabled, permitsModalActions else { return false }
        if let defaultAction = actions.first(where: { $0.isDefault }) ?? actions.first {
            return defaultAction.invokeIfPermitted()
        }
        return implicitDefaultAction?() ?? false
    }

    /// Pre-order flattening of this element and its descendants.
    public func flattened() -> [AccessibilityElementProjection] {
        var result: [AccessibilityElementProjection] = [self]
        for child in children {
            result.append(contentsOf: child.flattened())
        }
        return result
    }

    /// The first focused element in this subtree, if any.
    public func firstFocusedElement() -> AccessibilityElementProjection? {
        if isFocused { return self }
        for child in children {
            if let focused = child.firstFocusedElement() { return focused }
        }
        return nil
    }
}

/// These intents inspect the same current element that supplies the action.
/// They do not carry a callback that could invalidate admission between the
/// operation-specific predicate and handler selection.
package enum AccessibilityDefaultActionIntent {
    case invoke
    case toggle
    case select
    case removeFromSelection
}

/// A projection may outlive its source tree or an action implementation.
/// Keep only a weak scope and resolve the current handler after one bounded
/// layout query. Synthetic representation children are validated by a fresh
/// projection of their owner, not by assuming they have a retained parent.
@MainActor
private final class AccessibilityActionScope {
    private weak var root: ViewNode?
    private weak var runtime: RetainedViewRuntime?
    private let hasRuntime: Bool
    private let selectedPath: RetainedSelectedContentPath?
    private var isInvoking = false

    init(
        root: ViewNode, runtime: RetainedViewRuntime? = nil,
        selectedPath: RetainedSelectedContentPath? = nil
    ) {
        self.root = root
        self.runtime = runtime
        self.hasRuntime = runtime != nil
        self.selectedPath = selectedPath
    }

    private func selectedPathIsCurrent(
        _ path: RetainedSelectedContentPath?, for node: ViewNode, in runtime: RetainedViewRuntime?
    ) -> Bool {
        guard let path else { return true }
        guard path.physicalRoot === root, path.selectedNode === node, path.isCurrent else { return false }
        guard hasRuntime else { return true }
        guard let runtime, root === runtime.root else { return false }
        return path.isInstalled(in: runtime)
    }

    func invokeAction(
        on node: ViewNode, at index: Int, count: Int,
        name: String?, kind: RetainedAccessibilityActionKind?, isProjectedRoot: Bool = false
    ) -> Bool {
        withCurrentElement(for: node, requiresSelectedRoot: isProjectedRoot) { _ in
            let actions = node.accessibilityActions
            guard actions.count == count, actions.indices.contains(index) else { return false }
            let action = actions[index]
            guard action.name == name, action.kind == kind else { return false }
            action.handler()
            return true
        }
    }

    func invokeDefaultAction(on node: ViewNode, intent: AccessibilityDefaultActionIntent) -> Bool {
        withCurrentElement(for: node) { element in
            switch intent {
            case .invoke:
                break
            case .toggle:
                guard element.controlType == .checkBox else { return false }
            case .select:
                guard element.traits.contains(.isSelectable) else { return false }
                if element.isSelected { return true }
            case .removeFromSelection:
                guard element.traits.contains(.isSelectable) else { return false }
                if !element.isSelected { return true }
            }
            // Select only after validation. Rejection never falls through to
            // another handler, and callback reentry cannot cause a second call.
            if let action = node.accessibilityActions.first(where: { $0.kind == .default })
                ?? node.accessibilityActions.first
            {
                action.handler()
                return true
            }
            guard let activate = node.onActivate else { return false }
            activate()
            return true
        }
    }

    func invokeImplicitDefaultAction(on node: ViewNode, isProjectedRoot: Bool = false) -> Bool {
        withCurrentElement(for: node, requiresSelectedRoot: isProjectedRoot) { _ in
            // A saved implicit route cannot retarget a newly stored action.
            // Layout may install that list, so check only after validation.
            guard node.accessibilityActions.isEmpty, let activate = node.onActivate else { return false }
            activate()
            return true
        }
    }

    private func withCurrentElement(
        for node: ViewNode, requiresSelectedRoot: Bool = false,
        perform: (AccessibilityElementProjection) -> Bool
    ) -> Bool {
        guard !isInvoking, let root else { return false }
        let invocationRuntime = runtime
        let invocationPath: RetainedSelectedContentPath?
        if let selectedPath {
            invocationPath = selectedPath
        } else if requiresSelectedRoot, root.selectedContentRole != nil {
            if hasRuntime {
                guard let invocationRuntime, root === invocationRuntime.root,
                    let path = root.captureSelectedContentPath(in: invocationRuntime)
                else { return false }
                invocationPath = path
            } else {
                guard let scope = root.captureSelectedContentMutationScope(), scope.isCurrent else { return false }
                invocationPath = scope.path
            }
        } else {
            invocationPath = nil
        }
        guard selectedPathIsCurrent(invocationPath, for: node, in: invocationRuntime) else { return false }
        isInvoking = true
        defer {
            isInvoking = false
            withExtendedLifetime(invocationRuntime) {}
        }

        let projection: AccessibilityElementProjection?
        if hasRuntime {
            guard let runtime = invocationRuntime, runtime.root === root, runtime.permitsRetainedActionInvocation,
                runtime.resolvedLayoutFrame(of: root) != nil,
                runtime.permitsRetainedActionInvocation, case .settled = runtime.layoutSettlementStatus,
                runtime.hasCurrentAccessibilityPrepaint,
                selectedPathIsCurrent(invocationPath, for: node, in: runtime)
            else { return false }
            projection = AccessibilityProjection.project(runtime: runtime)
        } else {
            projection = AccessibilityProjection.project(root: root)
        }
        guard selectedPathIsCurrent(invocationPath, for: node, in: invocationRuntime),
            let element = projection?.flattened().first(where: { $0.sourceNode === node }),
            element.isEnabled, element.permitsModalActions
        else { return false }
        return perform(element)
    }
}

/// Builds `AccessibilityElementProjection` trees from retained `ViewNode`
/// state. All entry points re-derive the whole projection at call time.
/// Main-actor isolated, matching the retained runtime it reads from.
@MainActor
public enum AccessibilityProjection {
    /// Projects the subtree rooted at `root`. `root` itself is always
    /// projected as an element (typically a `pane`/`group` container) unless
    /// it is hidden, in which case the result is nil.
    public static func project(root: ViewNode) -> AccessibilityElementProjection? {
        project(
            root: root, activeModalNode: topmostModalNode(in: root),
            actionScope: AccessibilityActionScope(root: root)
        )
    }

    private static func project(
        root: ViewNode,
        activeModalNode: ViewNode?,
        actionScope: AccessibilityActionScope
    ) -> AccessibilityElementProjection? {
        guard let operand = selectedContentOperand(for: root, inheritedIsEnabled: true) else { return nil }
        let result = projectElement(
            operand.node,
            parentOrigin: .zero,
            inheritedTransform: .identity,
            forceElement: true,
            activeModalNode: activeModalNode,
            actionScope: actionScope,
            inheritedIsEnabled: operand.inheritedIsEnabled
        )
        return operand.isCurrent ? result : nil
    }

    /// Projects a runtime's retained root. Its modal scope comes from the
    /// exact prepaint order that keyboard routing and both renderers share.
    public static func project(runtime: RetainedViewRuntime) -> AccessibilityElementProjection? {
        project(
            root: runtime.root, activeModalNode: runtime.activeModalPresentationNode,
            actionScope: AccessibilityActionScope(root: runtime.root, runtime: runtime)
        )
    }

    /// The live provider resolves one current explicit/default-fallback action.
    /// This is separate from the public projection's snapshot-only metadata.
    package static func invokeDefaultAction(
        on node: ViewNode, in runtime: RetainedViewRuntime, intent: AccessibilityDefaultActionIntent = .invoke,
        selectedPath: RetainedSelectedContentPath? = nil
    ) -> Bool {
        AccessibilityActionScope(root: runtime.root, runtime: runtime, selectedPath: selectedPath)
            .invokeDefaultAction(on: node, intent: intent)
    }

    /// A mutating scroll request resolves the original attachment, not a
    /// replacement with the same identifier. Synthetic representation nodes
    /// have no physical scroll owner and cannot qualify through this route.
    package static func mutationElement(
        for target: RetainedAccessibilityTarget, in runtime: RetainedViewRuntime,
        during mutation: RetainedAccessibilityMutation, resolvingLayout: Bool
    ) -> AccessibilityElementProjection? {
        guard runtime.isAccessibilityTargetCurrent(target, during: mutation),
            !resolvingLayout || runtime.prepareAccessibilityMutation(mutation),
            runtime.isAccessibilityTargetCurrent(target, during: mutation),
            case .settled = runtime.layoutSettlementStatus, runtime.hasCurrentAccessibilityPrepaint,
            let node = target.node,
            let element = project(runtime: runtime)?.flattened().first(where: { $0.sourceNode === node }),
            element.isEnabled, element.permitsModalActions
        else { return nil }
        return element
    }

    // MARK: - Trait → control type mapping table
    //
    // First match wins, in the order listed. Traits not listed here have no
    // control-type mapping and are documented below the resolver.
    //
    //   .isToggle           → checkBox    (before isButton: toggles keep the
    //                                      button trait from the retained
    //                                      button builder but are checkboxes
    //                                      to assistive technology)
    //   .isSelectable       → listItem    (List/Table rows expose selection
    //                                      even while they are not selected)
    //   .isButton           → button
    //   .isLink             → hyperlink
    //   .isSearchField      → edit        (UIA has no Search control type)
    //   .isTextInput        → edit
    //   .isProgressIndicator → progressBar
    //   .isKeyboardKey      → button      (UIA has no KeyboardKey control type)
    //   .isHeader           → header
    //   .isImage / isAccessibilityImage → image
    //   .isStaticText       → text
    //   accessibilityPrefersSliderBehavior == true → slider
    //   .isSummaryElement   → group       (weak mapping; UIA has no Summary type)
    //   node.text != nil    → text        (unlabeled bitmap text fallback)
    //   otherwise           → group       (labeled content with no type signal)
    public static func resolveControlType(for node: ViewNode) -> AccessibilityControlType {
        let traits = node.accessibilityTraits
        if traits.contains(.isToggle) { return .checkBox }
        if traits.contains(.isSelectable) { return .listItem }
        if traits.contains(.isButton) { return .button }
        if traits.contains(.isLink) { return .hyperlink }
        if traits.contains(.isSearchField) { return .edit }
        if traits.contains(.isTextInput) { return .edit }
        if traits.contains(.isProgressIndicator) { return .progressBar }
        if traits.contains(.isKeyboardKey) { return .button }
        if traits.contains(.isHeader) { return .header }
        if traits.contains(.isImage) || node.isAccessibilityImage { return .image }
        if traits.contains(.isStaticText) { return .text }
        if node.accessibilityPrefersSliderBehavior == true { return .slider }
        if traits.contains(.isSummaryElement) { return .group }
        if node.text != nil { return .text }
        return .group
    }
    // Traits with no control-type mapping, kept verbatim on the projection:
    //   .isSelected      → projected as the `isSelected` state, not a type
    //   .isModal         → behavioral; provider wave should map to UIA
    //                      Window/Pane layering, not a control type
    //   .updatesFrequently, .startsMediaSession, .playsSound,
    //   .allowsDirectInteraction, .causesPageTurn
    //                    → behavioral; candidates for UIA live-region /
    //                      notification events, not control types

    // MARK: - Walk

    /// Nodes hidden from accessibility. Both `isAccessibilityHidden` and the
    /// visual `isHidden` omit the node *and its entire subtree*, matching how
    /// hit testing skips hidden subtrees.
    private static func isSubtreeHidden(_ node: ViewNode) -> Bool {
        node.isAccessibilityHidden || node.isHidden
    }

    @MainActor
    private struct SelectedContentOperand {
        let node: ViewNode
        let inheritedIsEnabled: Bool
        let isVirtualized: Bool
        let path: RetainedSelectedContentPath?

        var isCurrent: Bool { path?.isCurrent != false }
    }

    /// Only a factory-created role can omit its own geometry and metadata.
    /// Keep hidden/disabled state and physical virtualization on every skipped
    /// edge; the ordinary selected node still owns its normal projection.
    private static func selectedContentOperand(
        for physical: ViewNode, inheritedIsEnabled: Bool
    ) -> SelectedContentOperand? {
        guard !isSubtreeHidden(physical) else { return nil }
        guard physical.selectedContentRole != nil else {
            return SelectedContentOperand(
                node: physical, inheritedIsEnabled: inheritedIsEnabled,
                isVirtualized: physical.isLayoutDeferredByVirtualization, path: nil)
        }
        let path: RetainedSelectedContentPath?
        if let runtime = physical.retainedLazyListRuntime {
            path = physical.captureSelectedContentPath(in: runtime)
            guard path?.isInstalled(in: runtime) == true else { return nil }
        } else {
            path = physical.captureSelectedContentConstructionPath()
        }
        guard let path, path.isCurrent, path.physicalRoot === physical, let selected = path.selectedNode else {
            return nil
        }
        var current = physical
        var isEnabled = inheritedIsEnabled
        var isVirtualized = false
        var depth = 0
        while current !== selected {
            guard depth < ViewNode.maximumTraversalDepth, current.selectedContentRole != nil,
                !isSubtreeHidden(current), current.children.count == 1,
                let child = current.children.first, child.parent === current
            else { return nil }
            isEnabled = isEnabled && current.accessibilityRespondsToUserInteraction != false
            isVirtualized = isVirtualized || current.isLayoutDeferredByVirtualization
            current = child
            depth += 1
        }
        guard !isSubtreeHidden(selected), path.isCurrent else { return nil }
        return SelectedContentOperand(
            node: selected, inheritedIsEnabled: isEnabled,
            isVirtualized: isVirtualized || selected.isLayoutDeferredByVirtualization, path: path)
    }

    /// Mirror prepaint's iterative, round-based deferred traversal for callers
    /// that project a detached root without a runtime. Deferred overlays are
    /// global to their round, not merely later than their immediate siblings.
    private static func topmostModalNode(in node: ViewNode) -> ViewNode? {
        var pending: [(node: ViewNode, resumesDeferred: Bool, depth: Int)] = [(node, true, 0)]
        var deferred: [(node: ViewNode, depth: Int)] = []
        var frontmost: ViewNode?

        while !pending.isEmpty || !deferred.isEmpty {
            if pending.isEmpty {
                pending = deferred.reversed().map { ($0.node, true, $0.depth) }
                deferred.removeAll(keepingCapacity: true)
            }

            guard let current = pending.popLast(),
                current.depth <= ViewNode.maximumTraversalDepth,
                !isSubtreeHidden(current.node),
                !current.node.isLayoutDeferredByVirtualization
            else {
                continue
            }

            if current.node.selectedContentRole != nil {
                guard let operand = selectedContentOperand(for: current.node, inheritedIsEnabled: true),
                    operand.isCurrent, let child = current.node.children.first, child.parent === current.node
                else { continue }
                // A structural hop keeps its physical depth and deferred round.
                pending.append((child, current.resumesDeferred, current.depth + 1))
                continue
            }

            if !current.resumesDeferred, current.node.paintsInDeferredPhase {
                deferred.append((current.node, current.depth))
                continue
            }

            if current.node.isModalPresentationScope {
                frontmost = current.node
            }

            let operands = current.node.children.enumerated().compactMap { offset, child in
                selectedContentOperand(for: child, inheritedIsEnabled: true).map { operand in
                    (offset: offset, node: child, zIndex: operand.node.zIndex, operand: operand)
                }
            }
            let children =
                operands.contains(where: { $0.zIndex != 0 })
                ? operands.sorted { lhs, rhs in
                    if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
                    return lhs.offset < rhs.offset
                } : operands

            for child in children.reversed() where child.operand.isCurrent {
                pending.append((child.node, false, current.depth + 1))
            }
        }

        return frontmost
    }

    /// Keep the modal, every descendant inside it, and the ancestor chain
    /// needed to preserve its root-relative transformed geometry.
    private static func belongsToModalBranch(_ node: ViewNode, modal: ViewNode?) -> Bool {
        guard let modal else { return true }

        var ancestor: ViewNode? = node
        while let candidate = ancestor {
            if candidate === modal { return true }
            ancestor = candidate.parent
        }

        ancestor = modal
        while let candidate = ancestor {
            if candidate === node { return true }
            ancestor = candidate.parent
        }

        return false
    }

    /// A node is an accessibility element when it carries any accessible
    /// content (label/value/hint/identifier, traits, actions, or bitmap text)
    /// or when an explicit child behavior was set on it.
    private static func isAccessibilityElement(_ node: ViewNode) -> Bool {
        if node.isModalPresentationScope { return true }
        if node.accessibilityChildBehavior != nil { return true }
        if node.accessibilityLabel != nil { return true }
        if node.accessibilityValue != nil { return true }
        if node.accessibilityHint != nil { return true }
        if node.accessibilityIdentifier != nil { return true }
        if !node.accessibilityTraits.isEmpty { return true }
        if !node.accessibilityActions.isEmpty { return true }
        if node.text != nil { return true }
        return false
    }

    /// Projects `node` as an element. `forceElement` is used for the root so
    /// the projection always has a single top-level element.
    private static func projectElement(
        _ node: ViewNode,
        parentOrigin: Point,
        inheritedTransform: Transform2D,
        forceElement: Bool,
        activeModalNode: ViewNode?,
        actionScope: AccessibilityActionScope,
        inheritedIsEnabled: Bool
    ) -> AccessibilityElementProjection {
        let geometry = projectedGeometry(
            of: node,
            parentOrigin: parentOrigin,
            inheritedTransform: inheritedTransform
        )
        let childOrigin = scrolledChildOrigin(of: node, absoluteOrigin: geometry.absoluteOrigin)

        let behavior = node.accessibilityChildBehavior
        let isEnabled = inheritedIsEnabled && node.accessibilityRespondsToUserInteraction != false
        let isStructuralModalAncestor = activeModalNode.map { $0 !== node } ?? false
        var name = node.accessibilityLabel ?? node.text ?? ""
        var projectedChildren: [AccessibilityElementProjection] = []

        if let activeModalNode, node !== activeModalNode {
            // A modal wins over an ancestor's combine/ignore behavior. Its
            // ancestors remain only as the geometry path needed to reach it;
            // combining the blocked siblings would leak their spoken labels.
            projectedChildren = projectChildren(
                of: node,
                parentOrigin: childOrigin,
                inheritedTransform: geometry.effectiveTransform,
                activeModalNode: activeModalNode,
                actionScope: actionScope,
                inheritedIsEnabled: isEnabled
            )
        } else {
            switch behavior {
            case .ignore:
                // Children are dropped from the accessibility tree entirely.
                break
            case .combine:
                // Children merge into this element: descendant labels/text
                // fold into its name unless an explicit label already wins.
                if node.accessibilityLabel == nil, node.text == nil {
                    name = combinedDescendantName(of: node)
                }
            case .contain, nil:
                // Once inside the selected modal, synthetic representation
                // nodes need no parent-chain membership: they intentionally
                // are not attached to the retained tree.
                projectedChildren = projectChildren(
                    of: node,
                    parentOrigin: childOrigin,
                    inheritedTransform: geometry.effectiveTransform,
                    activeModalNode: nil,
                    actionScope: actionScope,
                    inheritedIsEnabled: isEnabled
                )
            }
        }

        let result = AccessibilityElementProjection(
            bounds: geometry.paintedBounds,
            name: name,
            value: node.accessibilityValue,
            hint: node.accessibilityHint,
            identifier: node.accessibilityIdentifier,
            controlType: forceElement && !isAccessibilityElement(node)
                ? .pane
                : resolveControlType(for: node),
            traits: node.isModalPresentationScope
                ? node.accessibilityTraits.union(.isModal) : node.accessibilityTraits,
            headingLevel: node.accessibilityHeadingLevel,
            isEnabled: isEnabled,
            isFocused: node.isFocused,
            isSelected: node.accessibilityTraits.contains(.isSelected),
            sortPriority: node.accessibilitySortPriority,
            actions: isStructuralModalAncestor
                ? []
                : projectedActions(
                    for: node, scope: actionScope, isProjectedRoot: forceElement),
            children: projectedChildren,
            sourceNode: node
        )
        result.isStructuralModalAncestor = isStructuralModalAncestor
        if !isStructuralModalAncestor {
            result.implicitDefaultAction = projectedImplicitDefaultAction(
                for: node, scope: actionScope, isProjectedRoot: forceElement)
        }
        return result
    }

    /// Projects a node's child list, splicing the projected children of
    /// transparent (non-element) intermediate nodes into the result. The
    /// sibling list is then stable-sorted by descending
    /// `accessibilitySortPriority`, matching SwiftUI's ordering semantics
    /// (higher priority first; declaration order breaks ties).
    private static func projectChildren(
        of node: ViewNode,
        parentOrigin: Point,
        inheritedTransform: Transform2D,
        activeModalNode: ViewNode?,
        actionScope: AccessibilityActionScope,
        inheritedIsEnabled: Bool
    ) -> [AccessibilityElementProjection] {
        let childNodes =
            activeModalNode == nil
            ? (node.accessibilityRepresentationChildren ?? node.children)
            : node.children
        var projected: [AccessibilityElementProjection] = []
        for physicalChild in childNodes {
            guard let operand = selectedContentOperand(for: physicalChild, inheritedIsEnabled: inheritedIsEnabled)
            else { continue }
            let child = operand.node
            guard operand.isCurrent, belongsToModalBranch(child, modal: activeModalNode) else { continue }
            // A row a lazy stack has not laid out has a real frame of its own
            // and nothing but zeroes below it. Descending would report a
            // rectangle per descendant that a UIA client would take as real
            // screen geometry, so the row is projected as one placeholder
            // instead.
            if operand.isVirtualized {
                projected.append(
                    projectVirtualizedPlaceholder(
                        child,
                        parentOrigin: parentOrigin,
                        inheritedTransform: inheritedTransform,
                        activeModalNode: activeModalNode,
                        actionScope: actionScope,
                        inheritedIsEnabled: operand.inheritedIsEnabled
                    )
                )
                continue
            }
            if isAccessibilityElement(child) {
                projected.append(
                    projectElement(
                        child,
                        parentOrigin: parentOrigin,
                        inheritedTransform: inheritedTransform,
                        forceElement: false,
                        activeModalNode: activeModalNode,
                        actionScope: actionScope,
                        inheritedIsEnabled: operand.inheritedIsEnabled
                    )
                )
            } else {
                // Transparent node: not an element itself, but its accessible
                // descendants are spliced into this sibling list.
                let geometry = projectedGeometry(
                    of: child,
                    parentOrigin: parentOrigin,
                    inheritedTransform: inheritedTransform
                )
                let childOrigin = scrolledChildOrigin(of: child, absoluteOrigin: geometry.absoluteOrigin)
                projected.append(
                    contentsOf: projectChildren(
                        of: child,
                        parentOrigin: childOrigin,
                        inheritedTransform: geometry.effectiveTransform,
                        activeModalNode: activeModalNode,
                        actionScope: actionScope,
                        inheritedIsEnabled: operand.inheritedIsEnabled
                            && child.accessibilityRespondsToUserInteraction != false
                    )
                )
            }
        }
        return projected.stableSortedByDescendingSortPriority()
    }

    /// Projects a subtree whose recursive layout a lazy stack deferred as a
    /// single childless element.
    ///
    /// Everything here is geometry-free except the node's own frame, which a
    /// virtualizing stack keeps correct: the name still folds in descendant
    /// labels and text (structure, not layout), so an off-screen row is
    /// findable and correctly placed without a rectangle being invented for
    /// anything inside it.
    private static func projectVirtualizedPlaceholder(
        _ node: ViewNode,
        parentOrigin: Point,
        inheritedTransform: Transform2D,
        activeModalNode: ViewNode?,
        actionScope: AccessibilityActionScope,
        inheritedIsEnabled: Bool
    ) -> AccessibilityElementProjection {
        let geometry = projectedGeometry(
            of: node,
            parentOrigin: parentOrigin,
            inheritedTransform: inheritedTransform
        )
        // Runtime prepaint can select a modal inside a deferred row.
        let isStructuralModalAncestor = activeModalNode.map { $0 !== node } ?? false
        let ownName = node.accessibilityLabel ?? node.text
        let name =
            node.accessibilityChildBehavior == .ignore
            ? (ownName ?? "")
            : (ownName ?? combinedDescendantName(of: node))
        let result = AccessibilityElementProjection(
            bounds: geometry.paintedBounds,
            name: name,
            value: node.accessibilityValue,
            hint: node.accessibilityHint,
            identifier: node.accessibilityIdentifier,
            controlType: isAccessibilityElement(node) ? resolveControlType(for: node) : .group,
            traits: node.accessibilityTraits,
            headingLevel: node.accessibilityHeadingLevel,
            isEnabled: inheritedIsEnabled && node.accessibilityRespondsToUserInteraction != false,
            isFocused: node.isFocused,
            isSelected: node.accessibilityTraits.contains(.isSelected),
            sortPriority: node.accessibilitySortPriority,
            actions: isStructuralModalAncestor ? [] : projectedActions(for: node, scope: actionScope),
            children: [],
            sourceNode: node,
            isVirtualizedPlaceholder: true
        )
        result.isStructuralModalAncestor = isStructuralModalAncestor
        if !isStructuralModalAncestor {
            result.implicitDefaultAction = projectedImplicitDefaultAction(for: node, scope: actionScope)
        }
        return result
    }

    private struct ProjectedGeometry {
        let absoluteOrigin: Point
        let paintedBounds: Rect
        let effectiveTransform: Transform2D
    }

    /// The same centered, ancestor-first transform composition used by
    /// retained prepaint and both paint paths. Keep the layout-space origin
    /// separate: scrolling shifts child layout before the accumulated
    /// transform maps its four corners into root-view space.
    private static func projectedGeometry(
        of node: ViewNode,
        parentOrigin: Point,
        inheritedTransform: Transform2D
    ) -> ProjectedGeometry {
        let absoluteOrigin = Point(
            x: parentOrigin.x + node.resolvedFrame.origin.x,
            y: parentOrigin.y + node.resolvedFrame.origin.y
        )
        let absoluteFrame = Rect(origin: absoluteOrigin, size: node.resolvedFrame.size)
        let inheritedFrame =
            inheritedTransform.isIdentity
            ? absoluteFrame : absoluteFrame.applying(transform: inheritedTransform)

        guard !node.transform.isIdentity else {
            return ProjectedGeometry(
                absoluteOrigin: absoluteOrigin,
                paintedBounds: inheritedFrame,
                effectiveTransform: inheritedTransform
            )
        }

        let center = Point(x: inheritedFrame.midX, y: inheritedFrame.midY)
        let centeredTransform = Transform2D.translation(x: -center.x, y: -center.y)
            .concatenating(node.transform)
            .concatenating(.translation(x: center.x, y: center.y))
        let effectiveTransform =
            inheritedTransform.isIdentity
            ? centeredTransform : inheritedTransform.concatenating(centeredTransform)

        return ProjectedGeometry(
            absoluteOrigin: absoluteOrigin,
            paintedBounds: absoluteFrame.applying(transform: effectiveTransform),
            effectiveTransform: effectiveTransform
        )
    }

    /// Child-content origin for a node, mirroring the painter/hit-test math:
    /// scroll containers shift their children by `-resolvedScrollOffset`
    /// along the scroll axis.
    private static func scrolledChildOrigin(of node: ViewNode, absoluteOrigin: Point) -> Point {
        Point(
            x: absoluteOrigin.x - (node.scrollAxis == .horizontal ? node.resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (node.scrollAxis == .vertical ? node.resolvedScrollOffset : 0)
        )
    }

    /// Depth-first concatenation of descendant labels and bitmap text, used
    /// for `.combine` containers without their own label. Hidden subtrees
    /// contribute nothing.
    private static func combinedDescendantName(of node: ViewNode) -> String {
        var parts: [String] = []
        collectDescendantNames(of: node, into: &parts)
        return parts.joined(separator: " ")
    }

    private static func collectDescendantNames(of node: ViewNode, into parts: inout [String]) {
        for physicalChild in node.accessibilityRepresentationChildren ?? node.children {
            guard let operand = selectedContentOperand(for: physicalChild, inheritedIsEnabled: true), operand.isCurrent
            else { continue }
            let child = operand.node
            if let label = child.accessibilityLabel ?? child.text, !label.isEmpty {
                parts.append(label)
            } else if child.accessibilityChildBehavior != .ignore {
                collectDescendantNames(of: child, into: &parts)
            }
        }
    }

    private static func projectedImplicitDefaultAction(
        for node: ViewNode, scope: AccessibilityActionScope, isProjectedRoot: Bool = false
    ) -> (@MainActor () -> Bool)? {
        guard node.accessibilityActions.isEmpty else { return nil }
        return { [weak node] in
            guard let node else { return false }
            return scope.invokeImplicitDefaultAction(on: node, isProjectedRoot: isProjectedRoot)
        }
    }

    private static func projectedActions(
        for node: ViewNode, scope: AccessibilityActionScope, isProjectedRoot: Bool = false
    ) -> [AccessibilityProjectedAction] {
        let actions = node.accessibilityActions
        let count = actions.count
        return actions.enumerated().map { index, action in
            let name = action.name
            let kind = action.kind
            return AccessibilityProjectedAction(
                name: name ?? fallbackActionName(for: kind),
                kind: kind,
                isDefault: kind == .default,
                invoke: { [weak node] in
                    guard let node else { return false }
                    return scope.invokeAction(
                        on: node, at: index, count: count, name: name, kind: kind,
                        isProjectedRoot: isProjectedRoot)
                }
            )
        }
    }

    private static func fallbackActionName(for kind: RetainedAccessibilityActionKind?) -> String {
        switch kind {
        case .default: return "Activate"
        case .escape: return "Escape"
        case .magicTap: return "Magic Tap"
        case .increment: return "Increment"
        case .decrement: return "Decrement"
        case .adjustable: return "Adjust"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case nil: return "Action"
        }
    }
}

extension Array where Element == AccessibilityElementProjection {
    /// Stable descending sort by `accessibilitySortPriority`.
    @MainActor
    fileprivate func stableSortedByDescendingSortPriority() -> [AccessibilityElementProjection] {
        enumerated()
            .sorted { lhs, rhs in
                if lhs.element.sortPriority != rhs.element.sortPriority {
                    return lhs.element.sortPriority > rhs.element.sortPriority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
