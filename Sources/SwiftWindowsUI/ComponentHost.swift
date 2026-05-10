@MainActor
public final class ComponentHost {
    public let runtime: RetainedViewRuntime

    private var buildComponents: (() -> [Component])?

    /// Optional predicate that can skip rebuilds when it returns false.
    public var shouldUpdate: (() -> Bool)?

    /// Set of observed object identifiers that were accessed during the last rebuild.
    /// Used for dependency tracking so that only hosts that depend on a changed
    /// observable are rebuilt.
    public var observedObjects: Set<ObjectIdentifier> = []

    public init(runtime: RetainedViewRuntime) {
        self.runtime = runtime
    }

    public func setContent(_ component: Component) {
        buildComponents = { [component] }
        reload()
    }

    public func setComponents(_ content: @escaping () -> [Component]) {
        buildComponents = content
        reload()
    }

    public func setContent(@ComponentBuilder _ content: @escaping () -> [Component]) {
        setComponents(content)
    }

    public func reload() {
        if let shouldUpdate, !shouldUpdate() {
            return
        }

        guard let buildComponents else {
            runtime.root.removeAllChildren()
            return
        }

        let oldChildren = runtime.root.children
        let newNodes = buildComponents().map { $0.makeNode(runtime: runtime) }

        reconcileChildren(of: runtime.root, oldChildren: oldChildren, newNodes: newNodes)
    }

    /// Basic view-diffing reconciliation.  Walk old and new child lists in
    /// parallel and reuse existing nodes when possible.
    private func reconcileChildren(of parent: ViewNode, oldChildren: [ViewNode], newNodes: [ViewNode]) {
        let oldCount = oldChildren.count
        let newCount = newNodes.count
        let commonCount = min(oldCount, newCount)

        // Update nodes that exist at the same index.
        for i in 0..<commonCount {
            let oldNode = oldChildren[i]
            let newNode = newNodes[i]

            if nodesMatch(oldNode, newNode) {
                // Same structural type -- update properties in-place.
                updateNodeProperties(target: oldNode, source: newNode)
                // Recursively reconcile grandchildren.
                reconcileChildren(of: oldNode, oldChildren: oldNode.children, newNodes: newNode.children)
            } else {
                // Structural mismatch -- replace the child.
                parent.replaceChild(at: i, with: newNode)
            }
        }

        // Remove trailing old children that have no new counterpart.
        if oldCount > newCount {
            for i in stride(from: oldCount - 1, through: newCount, by: -1) {
                parent.removeChild(at: i)
            }
        }

        // Append new children that didn't exist before.
        if newCount > oldCount {
            for i in oldCount..<newCount {
                parent.addChild(newNodes[i])
            }
        }
    }

    /// Two nodes "match" when they carry the same stable identity tag or, in
    /// the absence of explicit tags, when their structural layout and text
    /// signatures are equivalent (same layoutMode category plus optional text).
    private func nodesMatch(_ a: ViewNode, _ b: ViewNode) -> Bool {
        // If both nodes carry an explicit tag, match on tag only.
        if let tagA = a.nodeTag, let tagB = b.nodeTag {
            return tagA == tagB
        }

        // Fall back to structural similarity.
        return layoutModeTag(a.layoutMode) == layoutModeTag(b.layoutMode)
    }

    /// Produce a cheap comparable key for a layout mode.
    private func layoutModeTag(_ mode: ViewLayoutMode) -> String {
        switch mode {
        case .absolute:
            return "absolute"
        case .stack(let layout):
            switch layout.axis {
            case .vertical:
                return "stack.v"
            case .horizontal:
                return "stack.h"
            }
        case .flex:
            return "flex"
        }
    }

    /// Copy visual / layout properties from `source` onto `target`, keeping
    /// `target`'s identity (parent, runtime, callbacks) intact.
    private func updateNodeProperties(target: ViewNode, source: ViewNode) {
        if target.frame != source.frame { target.frame = source.frame }
        if target.backgroundColor != source.backgroundColor { target.backgroundColor = source.backgroundColor }
        if target.backgroundGradient != source.backgroundGradient { target.backgroundGradient = source.backgroundGradient }
        if target.bitmapSurface != source.bitmapSurface { target.bitmapSurface = source.bitmapSurface }
        if target.text != source.text { target.text = source.text }
        if target.textStyle != source.textStyle { target.textStyle = source.textStyle }
        if target.borderColor != source.borderColor { target.borderColor = source.borderColor }
        if target.borderWidth != source.borderWidth { target.borderWidth = source.borderWidth }
        if target.outlineColor != source.outlineColor { target.outlineColor = source.outlineColor }
        if target.outlineWidth != source.outlineWidth { target.outlineWidth = source.outlineWidth }
        if target.shadowColor != source.shadowColor { target.shadowColor = source.shadowColor }
        if target.shadowOffset != source.shadowOffset { target.shadowOffset = source.shadowOffset }
        if target.shadowSpread != source.shadowSpread { target.shadowSpread = source.shadowSpread }
        if target.cornerRadius != source.cornerRadius { target.cornerRadius = source.cornerRadius }
        if target.clipsToBounds != source.clipsToBounds { target.clipsToBounds = source.clipsToBounds }
        if target.preferredSize != source.preferredSize { target.preferredSize = source.preferredSize }
        if target.layoutConstraints != source.layoutConstraints { target.layoutConstraints = source.layoutConstraints }
        if target.fixedSizeAxes != source.fixedSizeAxes { target.fixedSizeAxes = source.fixedSizeAxes }
        if target.layoutPriority != source.layoutPriority { target.layoutPriority = source.layoutPriority }
        if target.blurRadius != source.blurRadius { target.blurRadius = source.blurRadius }
        if target.opacity != source.opacity { target.opacity = source.opacity }
        if target.zIndex != source.zIndex { target.zIndex = source.zIndex }
        if target.transform != source.transform { target.transform = source.transform }
        if target.flexItem != source.flexItem { target.flexItem = source.flexItem }
        if target.flexItemStyle != source.flexItemStyle { target.flexItemStyle = source.flexItemStyle }
        if target.scrollAxis != source.scrollAxis { target.scrollAxis = source.scrollAxis }
        if target.scrollOffset != source.scrollOffset { target.scrollOffset = source.scrollOffset }
        if target.scrollStep != source.scrollStep { target.scrollStep = source.scrollStep }
        if target.showsScrollIndicator != source.showsScrollIndicator { target.showsScrollIndicator = source.showsScrollIndicator }
        if target.scrollIndicatorColor != source.scrollIndicatorColor { target.scrollIndicatorColor = source.scrollIndicatorColor }
        if target.scrollIndicatorIdleColor != source.scrollIndicatorIdleColor { target.scrollIndicatorIdleColor = source.scrollIndicatorIdleColor }
        if target.scrollIndicatorHoverColor != source.scrollIndicatorHoverColor { target.scrollIndicatorHoverColor = source.scrollIndicatorHoverColor }
        if target.scrollIndicatorActiveColor != source.scrollIndicatorActiveColor { target.scrollIndicatorActiveColor = source.scrollIndicatorActiveColor }
        if target.scrollIndicatorThickness != source.scrollIndicatorThickness { target.scrollIndicatorThickness = source.scrollIndicatorThickness }
        if target.isFocusable != source.isFocusable { target.isFocusable = source.isFocusable }
        if target.isHitTestVisible != source.isHitTestVisible { target.isHitTestVisible = source.isHitTestVisible }
        if target.isHidden != source.isHidden { target.isHidden = source.isHidden }
        if target.accessibilityLabel != source.accessibilityLabel { target.accessibilityLabel = source.accessibilityLabel }
        if target.accessibilityValue != source.accessibilityValue { target.accessibilityValue = source.accessibilityValue }
        if target.accessibilityHint != source.accessibilityHint { target.accessibilityHint = source.accessibilityHint }
        if target.accessibilityIdentifier != source.accessibilityIdentifier { target.accessibilityIdentifier = source.accessibilityIdentifier }
        if target.isAccessibilityHidden != source.isAccessibilityHidden { target.isAccessibilityHidden = source.isAccessibilityHidden }
        if target.nodeTag != source.nodeTag { target.nodeTag = source.nodeTag }
        let targetLayoutTag = layoutModeTag(target.layoutMode)
        let sourceLayoutTag = layoutModeTag(source.layoutMode)
        if targetLayoutTag != sourceLayoutTag {
            target.layoutMode = source.layoutMode
        }
        target.previousPropertyValues = source.previousPropertyValues
        target.animationStates = source.animationStates

        target.onPointerEnter = source.onPointerEnter
        target.onPointerExit = source.onPointerExit
        target.onPointerDown = source.onPointerDown
        target.onPointerUpInside = source.onPointerUpInside
        target.onPointerUpOutside = source.onPointerUpOutside
        target.onFocusEnter = source.onFocusEnter
        target.onFocusExit = source.onFocusExit
        target.onKeyDown = source.onKeyDown
        target.onActivate = source.onActivate
        target.onDragStart = source.onDragStart
        target.onDragChange = source.onDragChange
        target.onDragEnd = source.onDragEnd
        target.onLayout = source.onLayout
        target.onAppear = source.onAppear
        target.onDisappear = source.onDisappear
        target.onSizeChange = source.onSizeChange
    }
}
