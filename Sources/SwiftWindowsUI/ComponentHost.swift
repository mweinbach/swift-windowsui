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
        if target.borderGradient != source.borderGradient { target.borderGradient = source.borderGradient }
        if target.borderWidth != source.borderWidth { target.borderWidth = source.borderWidth }
        if target.borderStrokeStyle != source.borderStrokeStyle { target.borderStrokeStyle = source.borderStrokeStyle }
        if target.outlineColor != source.outlineColor { target.outlineColor = source.outlineColor }
        if target.outlineWidth != source.outlineWidth { target.outlineWidth = source.outlineWidth }
        if target.shadowColor != source.shadowColor { target.shadowColor = source.shadowColor }
        if target.shadowOffset != source.shadowOffset { target.shadowOffset = source.shadowOffset }
        if target.shadowSpread != source.shadowSpread { target.shadowSpread = source.shadowSpread }
        if target.cornerRadius != source.cornerRadius { target.cornerRadius = source.cornerRadius }
        if target.clipsToBounds != source.clipsToBounds { target.clipsToBounds = source.clipsToBounds }
        if target.clipFillStyle != source.clipFillStyle { target.clipFillStyle = source.clipFillStyle }
        if target.preferredSize != source.preferredSize { target.preferredSize = source.preferredSize }
        if target.layoutConstraints != source.layoutConstraints { target.layoutConstraints = source.layoutConstraints }
        if target.fixedSizeAxes != source.fixedSizeAxes { target.fixedSizeAxes = source.fixedSizeAxes }
        if target.layoutPriority != source.layoutPriority { target.layoutPriority = source.layoutPriority }
        if target.gridCellAnchor != source.gridCellAnchor { target.gridCellAnchor = source.gridCellAnchor }
        if target.gridCellUnsizedAxes != source.gridCellUnsizedAxes { target.gridCellUnsizedAxes = source.gridCellUnsizedAxes }
        if target.gridColumnAlignment != source.gridColumnAlignment { target.gridColumnAlignment = source.gridColumnAlignment }
        if target.blurRadius != source.blurRadius { target.blurRadius = source.blurRadius }
        if target.opacity != source.opacity { target.opacity = source.opacity }
        if target.blendMode != source.blendMode { target.blendMode = source.blendMode }
        if target.isCompositingGroup != source.isCompositingGroup { target.isCompositingGroup = source.isCompositingGroup }
        if target.drawingGroup != source.drawingGroup { target.drawingGroup = source.drawingGroup }
        if target.colorEffects != source.colorEffects { target.colorEffects = source.colorEffects }
        if target.viewMask != source.viewMask { target.viewMask = source.viewMask }
        if target.listRowSeparator != source.listRowSeparator { target.listRowSeparator = source.listRowSeparator }
        if target.listRowSeparatorTint != source.listRowSeparatorTint { target.listRowSeparatorTint = source.listRowSeparatorTint }
        if target.listSectionSeparator != source.listSectionSeparator { target.listSectionSeparator = source.listSectionSeparator }
        if target.listSectionSeparatorTint != source.listSectionSeparatorTint { target.listSectionSeparatorTint = source.listSectionSeparatorTint }
        if target.listItemTint != source.listItemTint { target.listItemTint = source.listItemTint }
        if target.selectionDisabled != source.selectionDisabled { target.selectionDisabled = source.selectionDisabled }
        if target.selectionDisabledOverride != source.selectionDisabledOverride { target.selectionDisabledOverride = source.selectionDisabledOverride }
        if target.deleteDisabled != source.deleteDisabled { target.deleteDisabled = source.deleteDisabled }
        if target.deleteDisabledOverride != source.deleteDisabledOverride { target.deleteDisabledOverride = source.deleteDisabledOverride }
        if target.moveDisabled != source.moveDisabled { target.moveDisabled = source.moveDisabled }
        if target.moveDisabledOverride != source.moveDisabledOverride { target.moveDisabledOverride = source.moveDisabledOverride }
        if target.dynamicContentIndex != source.dynamicContentIndex { target.dynamicContentIndex = source.dynamicContentIndex }
        if target.dynamicInsertContentTypes != source.dynamicInsertContentTypes { target.dynamicInsertContentTypes = source.dynamicInsertContentTypes }
        if target.dynamicDropPayloadType != source.dynamicDropPayloadType { target.dynamicDropPayloadType = source.dynamicDropPayloadType }
        if target.dropAcceptedContentTypes != source.dropAcceptedContentTypes { target.dropAcceptedContentTypes = source.dropAcceptedContentTypes }
        if target.dropPayloadType != source.dropPayloadType { target.dropPayloadType = source.dropPayloadType }
        if target.isDropDestinationEnabled != source.isDropDestinationEnabled { target.isDropDestinationEnabled = source.isDropDestinationEnabled }
        if target.hasDropConfiguration != source.hasDropConfiguration { target.hasDropConfiguration = source.hasDropConfiguration }
        if target.dragDropPreviewsFormation != source.dragDropPreviewsFormation { target.dragDropPreviewsFormation = source.dragDropPreviewsFormation }
        if target.springLoadingBehavior != source.springLoadingBehavior { target.springLoadingBehavior = source.springLoadingBehavior }
        if target.dragPayloadType != source.dragPayloadType { target.dragPayloadType = source.dragPayloadType }
        if target.dragItemProviderTypeIdentifiers != source.dragItemProviderTypeIdentifiers { target.dragItemProviderTypeIdentifiers = source.dragItemProviderTypeIdentifiers }
        if target.dragContainerItemID != source.dragContainerItemID { target.dragContainerItemID = source.dragContainerItemID }
        if target.dragContainerNamespaceID != source.dragContainerNamespaceID { target.dragContainerNamespaceID = source.dragContainerNamespaceID }
        if target.hasDragPreview != source.hasDragPreview { target.hasDragPreview = source.hasDragPreview }
        if target.horizontalScrollBounceBehavior != source.horizontalScrollBounceBehavior { target.horizontalScrollBounceBehavior = source.horizontalScrollBounceBehavior }
        if target.verticalScrollBounceBehavior != source.verticalScrollBounceBehavior { target.verticalScrollBounceBehavior = source.verticalScrollBounceBehavior }
        if target.scrollTargetBehavior != source.scrollTargetBehavior { target.scrollTargetBehavior = source.scrollTargetBehavior }
        if target.isScrollTargetLayout != source.isScrollTargetLayout { target.isScrollTargetLayout = source.isScrollTargetLayout }
        if target.scrollInputBehaviors != source.scrollInputBehaviors { target.scrollInputBehaviors = source.scrollInputBehaviors }
        if target.scrollIndicatorsFlashOnAppear != source.scrollIndicatorsFlashOnAppear { target.scrollIndicatorsFlashOnAppear = source.scrollIndicatorsFlashOnAppear }
        if target.scrollIndicatorsFlashTrigger != source.scrollIndicatorsFlashTrigger { target.scrollIndicatorsFlashTrigger = source.scrollIndicatorsFlashTrigger }
        if target.scrollTransition != source.scrollTransition { target.scrollTransition = source.scrollTransition }
        if target.scrollPosition != source.scrollPosition { target.scrollPosition = source.scrollPosition }
        if target.scrollObservations != source.scrollObservations { target.scrollObservations = source.scrollObservations }
        if target.scrollReaderID != source.scrollReaderID { target.scrollReaderID = source.scrollReaderID }
        if target.scrollProxyRequests != source.scrollProxyRequests { target.scrollProxyRequests = source.scrollProxyRequests }
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
        if target.scrollIndicatorInsets != source.scrollIndicatorInsets { target.scrollIndicatorInsets = source.scrollIndicatorInsets }
        if target.initialScrollAnchor != source.initialScrollAnchor { target.initialScrollAnchor = source.initialScrollAnchor }
        if target.scrollSizeChangeAnchor != source.scrollSizeChangeAnchor { target.scrollSizeChangeAnchor = source.scrollSizeChangeAnchor }
        if target.isFocusable != source.isFocusable { target.isFocusable = source.isFocusable }
        if target.isHitTestVisible != source.isHitTestVisible { target.isHitTestVisible = source.isHitTestVisible }
        if target.isHidden != source.isHidden { target.isHidden = source.isHidden }
        if target.accessibilityLabel != source.accessibilityLabel { target.accessibilityLabel = source.accessibilityLabel }
        if target.accessibilityValue != source.accessibilityValue { target.accessibilityValue = source.accessibilityValue }
        if target.accessibilityHint != source.accessibilityHint { target.accessibilityHint = source.accessibilityHint }
        if target.accessibilityIdentifier != source.accessibilityIdentifier { target.accessibilityIdentifier = source.accessibilityIdentifier }
        if target.accessibilityTraits != source.accessibilityTraits { target.accessibilityTraits = source.accessibilityTraits }
        if target.accessibilityChildBehavior != source.accessibilityChildBehavior { target.accessibilityChildBehavior = source.accessibilityChildBehavior }
        if target.accessibilitySortPriority != source.accessibilitySortPriority { target.accessibilitySortPriority = source.accessibilitySortPriority }
        target.accessibilityActions = source.accessibilityActions
        if target.isAccessibilityHidden != source.isAccessibilityHidden { target.isAccessibilityHidden = source.isAccessibilityHidden }
        if target.symbolVariableValue != source.symbolVariableValue { target.symbolVariableValue = source.symbolVariableValue }
        if target.symbolRenderingMode != source.symbolRenderingMode { target.symbolRenderingMode = source.symbolRenderingMode }
        if target.symbolVariants != source.symbolVariants { target.symbolVariants = source.symbolVariants }
        if target.imageResizingMode != source.imageResizingMode { target.imageResizingMode = source.imageResizingMode }
        if target.imageCapInsets != source.imageCapInsets { target.imageCapInsets = source.imageCapInsets }
        if target.imageRenderingMode != source.imageRenderingMode { target.imageRenderingMode = source.imageRenderingMode }
        if target.imageInterpolation != source.imageInterpolation { target.imageInterpolation = source.imageInterpolation }
        if target.imageAntialiased != source.imageAntialiased { target.imageAntialiased = source.imageAntialiased }
        if target.keyboardShortcuts != source.keyboardShortcuts { target.keyboardShortcuts = source.keyboardShortcuts }
        if target.textInputSubmitLabel != source.textInputSubmitLabel { target.textInputSubmitLabel = source.textInputSubmitLabel }
        if target.textInputCaretOffset != source.textInputCaretOffset { target.textInputCaretOffset = source.textInputCaretOffset }
        if target.textSelectability != source.textSelectability { target.textSelectability = source.textSelectability }
        if target.textSelectionAffinity != source.textSelectionAffinity { target.textSelectionAffinity = source.textSelectionAffinity }
        if target.textInputSelection != source.textInputSelection { target.textInputSelection = source.textInputSelection }
        if target.textContentType != source.textContentType { target.textContentType = source.textContentType }
        if target.textInputKeyboardType != source.textInputKeyboardType { target.textInputKeyboardType = source.textInputKeyboardType }
        if target.textInputCompletion != source.textInputCompletion { target.textInputCompletion = source.textInputCompletion }
        if target.textInputSuggestions != source.textInputSuggestions { target.textInputSuggestions = source.textInputSuggestions }
        if target.writingToolsBehavior != source.writingToolsBehavior { target.writingToolsBehavior = source.writingToolsBehavior }
        if target.writingToolsAffordanceVisibility != source.writingToolsAffordanceVisibility { target.writingToolsAffordanceVisibility = source.writingToolsAffordanceVisibility }
        if target.textInputDictationBehavior != source.textInputDictationBehavior { target.textInputDictationBehavior = source.textInputDictationBehavior }
        if target.isFindDisabled != source.isFindDisabled { target.isFindDisabled = source.isFindDisabled }
        if target.isReplaceDisabled != source.isReplaceDisabled { target.isReplaceDisabled = source.isReplaceDisabled }
        if target.isFindNavigatorPresented != source.isFindNavigatorPresented { target.isFindNavigatorPresented = source.isFindNavigatorPresented }
        if target.isSubmitScopeBoundary != source.isSubmitScopeBoundary { target.isSubmitScopeBoundary = source.isSubmitScopeBoundary }
        if target.hoverEffect != source.hoverEffect { target.hoverEffect = source.hoverEffect }
        if target.isHoverEffectDisabled != source.isHoverEffectDisabled { target.isHoverEffectDisabled = source.isHoverEffectDisabled }
        if target.isFocusEffectDisabled != source.isFocusEffectDisabled { target.isFocusEffectDisabled = source.isFocusEffectDisabled }
        if target.contentShapes != source.contentShapes { target.contentShapes = source.contentShapes }
        if target.redactionReasons != source.redactionReasons { target.redactionReasons = source.redactionReasons }
        if target.isPrivacySensitive != source.isPrivacySensitive { target.isPrivacySensitive = source.isPrivacySensitive }
        if target.matchedGeometryEffect != source.matchedGeometryEffect { target.matchedGeometryEffect = source.matchedGeometryEffect }
        if target.presentationChrome != source.presentationChrome { target.presentationChrome = source.presentationChrome }
        if target.isToolbarContainer != source.isToolbarContainer { target.isToolbarContainer = source.isToolbarContainer }
        if target.toolbarPlacementTags != source.toolbarPlacementTags { target.toolbarPlacementTags = source.toolbarPlacementTags }
        if target.sectionHeaderChildCount != source.sectionHeaderChildCount { target.sectionHeaderChildCount = source.sectionHeaderChildCount }
        if target.sectionFooterChildCount != source.sectionFooterChildCount { target.sectionFooterChildCount = source.sectionFooterChildCount }
        target.retainedPreferenceValues = source.retainedPreferenceValues
        target.retainedPreferenceTransformBoundaries = source.retainedPreferenceTransformBoundaries
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
        target.onPointerMove = source.onPointerMove
        target.onPointerDown = source.onPointerDown
        target.onPointerUpInside = source.onPointerUpInside
        target.onPointerUpInsideAt = source.onPointerUpInsideAt
        target.onPointerUpOutside = source.onPointerUpOutside
        target.onContextMenu = source.onContextMenu
        target.onFocusEnter = source.onFocusEnter
        target.onFocusExit = source.onFocusExit
        target.onKeyDown = source.onKeyDown
        target.onActivate = source.onActivate
        target.onRepeatActivate = source.onRepeatActivate
        target.onDeleteRows = source.onDeleteRows
        target.onMoveRows = source.onMoveRows
        target.onInsertRows = source.onInsertRows
        target.onDropRows = source.onDropRows
        target.onValidateDrop = source.onValidateDrop
        target.onDropEntered = source.onDropEntered
        target.onDropUpdated = source.onDropUpdated
        target.onDropExited = source.onDropExited
        target.onDropProviders = source.onDropProviders
        target.onDropPayloads = source.onDropPayloads
        target.onMakeDropConfiguration = source.onMakeDropConfiguration
        target.onMakeDragPayload = source.onMakeDragPayload
        target.onMakeDragItemProvider = source.onMakeDragItemProvider
        target.onDragStart = source.onDragStart
        target.onDragChange = source.onDragChange
        target.onDragEnd = source.onDragEnd
        target.onLayout = source.onLayout
        target.onAppear = source.onAppear
        target.onDisappear = source.onDisappear
        target.onAppearWithNode = source.onAppearWithNode
        target.onDisappearWithNode = source.onDisappearWithNode
        target.onSizeChange = source.onSizeChange

        if target.hasAppeared {
            for launch in source.pendingLifecycleTaskLaunches {
                target.launchLifecycleTask(launch)
            }
        }
    }
}
