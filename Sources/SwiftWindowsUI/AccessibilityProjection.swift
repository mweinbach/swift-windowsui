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
    private let handler: () -> Void

    public init(name: String, kind: RetainedAccessibilityActionKind?, isDefault: Bool, handler: @escaping () -> Void) {
        self.name = name
        self.kind = kind
        self.isDefault = isDefault
        self.handler = handler
    }

    public func invoke() {
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

    /// Invokes the node's default action — the stored action of kind
    /// `.default`, or the first stored action when no kind is marked.
    /// Returns true when an action was invoked.
    @discardableResult
    public func invokeDefaultAction() -> Bool {
        guard isEnabled,
            let defaultAction = actions.first(where: { $0.isDefault }) ?? actions.first
        else {
            return false
        }

        defaultAction.invoke()
        return true
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

/// Builds `AccessibilityElementProjection` trees from retained `ViewNode`
/// state. All entry points re-derive the whole projection at call time.
/// Main-actor isolated, matching the retained runtime it reads from.
@MainActor
public enum AccessibilityProjection {
    /// Projects the subtree rooted at `root`. `root` itself is always
    /// projected as an element (typically a `pane`/`group` container) unless
    /// it is hidden, in which case the result is nil.
    public static func project(root: ViewNode) -> AccessibilityElementProjection? {
        guard !isSubtreeHidden(root) else { return nil }
        return projectElement(
            root,
            parentOrigin: .zero,
            inheritedTransform: .identity,
            forceElement: true
        )
    }

    /// Projects a runtime's retained root. Equivalent to `project(root:)`;
    /// focus state already rides on `ViewNode.isFocused`, so no separate
    /// runtime lookup is required.
    public static func project(runtime: RetainedViewRuntime) -> AccessibilityElementProjection? {
        project(root: runtime.root)
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

    /// A node is an accessibility element when it carries any accessible
    /// content (label/value/hint/identifier, traits, actions, or bitmap text)
    /// or when an explicit child behavior was set on it.
    private static func isAccessibilityElement(_ node: ViewNode) -> Bool {
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
        forceElement: Bool
    ) -> AccessibilityElementProjection {
        let geometry = projectedGeometry(
            of: node,
            parentOrigin: parentOrigin,
            inheritedTransform: inheritedTransform
        )
        let childOrigin = scrolledChildOrigin(of: node, absoluteOrigin: geometry.absoluteOrigin)

        let behavior = node.accessibilityChildBehavior
        var name = node.accessibilityLabel ?? node.text ?? ""
        var projectedChildren: [AccessibilityElementProjection] = []

        switch behavior {
        case .ignore:
            // Children are dropped from the accessibility tree entirely.
            break
        case .combine:
            // Children merge into this element: descendant labels/text fold
            // into the name (only when the node has no label of its own) and
            // no child elements are projected.
            if node.accessibilityLabel == nil, node.text == nil {
                name = combinedDescendantName(of: node)
            }
        case .contain, nil:
            projectedChildren = projectChildren(
                of: node,
                parentOrigin: childOrigin,
                inheritedTransform: geometry.effectiveTransform
            )
        }

        return AccessibilityElementProjection(
            bounds: geometry.paintedBounds,
            name: name,
            value: node.accessibilityValue,
            hint: node.accessibilityHint,
            identifier: node.accessibilityIdentifier,
            controlType: forceElement && !isAccessibilityElement(node)
                ? .pane
                : resolveControlType(for: node),
            traits: node.accessibilityTraits,
            headingLevel: node.accessibilityHeadingLevel,
            isEnabled: node.accessibilityRespondsToUserInteraction ?? true,
            isFocused: node.isFocused,
            isSelected: node.accessibilityTraits.contains(.isSelected),
            sortPriority: node.accessibilitySortPriority,
            actions: node.accessibilityActions.map(projectedAction(from:)),
            children: projectedChildren,
            sourceNode: node
        )
    }

    /// Projects a node's child list, splicing the projected children of
    /// transparent (non-element) intermediate nodes into the result. The
    /// sibling list is then stable-sorted by descending
    /// `accessibilitySortPriority`, matching SwiftUI's ordering semantics
    /// (higher priority first; declaration order breaks ties).
    private static func projectChildren(
        of node: ViewNode,
        parentOrigin: Point,
        inheritedTransform: Transform2D
    ) -> [AccessibilityElementProjection] {
        let childNodes = node.accessibilityRepresentationChildren ?? node.children
        var projected: [AccessibilityElementProjection] = []
        for child in childNodes {
            guard !isSubtreeHidden(child) else { continue }
            // A row a lazy stack has not laid out has a real frame of its own
            // and nothing but zeroes below it. Descending would report a
            // rectangle per descendant that a UIA client would take as real
            // screen geometry, so the row is projected as one placeholder
            // instead.
            if child.isLayoutDeferredByVirtualization {
                projected.append(
                    projectVirtualizedPlaceholder(
                        child,
                        parentOrigin: parentOrigin,
                        inheritedTransform: inheritedTransform
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
                        forceElement: false
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
                        inheritedTransform: geometry.effectiveTransform
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
        inheritedTransform: Transform2D
    ) -> AccessibilityElementProjection {
        let geometry = projectedGeometry(
            of: node,
            parentOrigin: parentOrigin,
            inheritedTransform: inheritedTransform
        )
        let ownName = node.accessibilityLabel ?? node.text
        let name =
            node.accessibilityChildBehavior == .ignore
            ? (ownName ?? "")
            : (ownName ?? combinedDescendantName(of: node))
        return AccessibilityElementProjection(
            bounds: geometry.paintedBounds,
            name: name,
            value: node.accessibilityValue,
            hint: node.accessibilityHint,
            identifier: node.accessibilityIdentifier,
            controlType: isAccessibilityElement(node) ? resolveControlType(for: node) : .group,
            traits: node.accessibilityTraits,
            headingLevel: node.accessibilityHeadingLevel,
            isEnabled: node.accessibilityRespondsToUserInteraction ?? true,
            isFocused: node.isFocused,
            isSelected: node.accessibilityTraits.contains(.isSelected),
            sortPriority: node.accessibilitySortPriority,
            actions: node.accessibilityActions.map(projectedAction(from:)),
            children: [],
            sourceNode: node,
            isVirtualizedPlaceholder: true
        )
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
        for child in node.accessibilityRepresentationChildren ?? node.children {
            guard !isSubtreeHidden(child) else { continue }
            if let label = child.accessibilityLabel ?? child.text, !label.isEmpty {
                parts.append(label)
            } else if child.accessibilityChildBehavior != .ignore {
                collectDescendantNames(of: child, into: &parts)
            }
        }
    }

    private static func projectedAction(from action: RetainedAccessibilityAction) -> AccessibilityProjectedAction {
        AccessibilityProjectedAction(
            name: action.name ?? fallbackActionName(for: action.kind),
            kind: action.kind,
            isDefault: action.kind == .default,
            handler: action.handler
        )
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
