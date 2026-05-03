import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsPlatform

// Gap/Fix: Granular dirty tracking — OptionSet replaces single isDirty boolean.
public struct DirtyFlags: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Property changes that affect size or position (frame, preferredSize, layoutMode, etc.).
    public static let layout  = DirtyFlags(rawValue: 1 << 0)
    /// Property changes that only affect visual appearance (color, opacity, borderColor, etc.).
    public static let paint   = DirtyFlags(rawValue: 1 << 1)
    /// Child list changed (add/remove).
    public static let children = DirtyFlags(rawValue: 1 << 2)

    public static let all: DirtyFlags = [.layout, .paint, .children]
}

public enum ViewLayoutMode: Sendable {
    case absolute
    case stack(StackLayout)
    case flex(FlexStyle)
}

public enum ScrollAxis: Sendable {
    case horizontal
    case vertical
}

@MainActor
public final class ViewNode {
    public var frame: Rect {
        didSet { invalidateRuntime(.layout) }
    }

    public var backgroundColor: Color? {
        didSet { invalidateRuntime(.paint) }
    }

    public var backgroundGradient: LinearGradient? {
        didSet { invalidateRuntime(.paint) }
    }

    public var text: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var textStyle: PixelTextStyle {
        didSet { invalidateRuntime(.layout) }
    }

    public var borderColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var borderWidth: Double {
        didSet { invalidateRuntime(.layout) }
    }

    public var outlineColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var outlineWidth: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var shadowColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var shadowOffset: Point {
        didSet { invalidateRuntime(.paint) }
    }

    public var shadowSpread: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var cornerRadius: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var clipsToBounds: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var layoutMode: ViewLayoutMode {
        didSet { invalidateRuntime(.layout) }
    }

    public var preferredSize: Size? {
        didSet { invalidateRuntime(.layout) }
    }

    public var minimumSize: Size? {
        didSet { invalidateRuntime(.layout) }
    }

    public var maximumSize: Size? {
        didSet { invalidateRuntime(.layout) }
    }

    public var fillsAvailableWidth: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var fillsAvailableHeight: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var layoutPriority: Double {
        didSet { invalidateRuntime(.layout) }
    }

    // Gap/Fix: Blur radius — property for requesting a Gaussian blur over the view's content.
    public var blurRadius: Double {
        didSet { invalidateRuntime(.paint) }
    }

    // Gap/Fix: Opacity — per-node opacity multiplier (0..1).
    public var opacity: Double {
        didSet { invalidateRuntime(.paint) }
    }

    // Gap/Fix: Z-index for sibling sort order.
    // NOTE: zIndex only sorts among siblings within the same parent.
    // For cross-subtree ordering (e.g. modals, overlays), add the view
    // at the root level or to a dedicated overlay container instead.
    public var zIndex: Double {
        didSet { invalidateRuntime(.paint) }
    }

    // Gap/Fix: Per-node 2D affine transform (applied around the view's center).
    public var transform: Transform2D {
        didSet { invalidateRuntime(.paint) }
    }

    public var flexItem: FlexProperties {
        didSet { invalidateRuntime() }
    }

    public var flexItemStyle: FlexItemStyle {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollAxis: ScrollAxis? {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollOffset: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollStep: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var showsScrollIndicator: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorIdleColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorHoverColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorActiveColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorThickness: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var isFocusable: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isHitTestVisible: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isHidden: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    /// Optional stable identity tag used by the diffing algorithm to match
    /// nodes across rebuilds.  When present, two nodes with the same tag are
    /// considered equivalent and will have their properties updated in-place
    /// rather than being torn down and recreated.
    public var nodeTag: String?

    /// Snapshot of previous property values for animation interpolation.
    /// When an animation context is active and a property changes, the old
    /// value is recorded here so that the runtime can interpolate between old
    /// and new over time.
    public var previousPropertyValues: PropertySnapshot?

    /// Active per-property animation states driven by the `animation()` modifier.
    public var animationStates: [AnimatableProperty: AnimationState] = [:]

    public var onPointerEnter: (() -> Void)?
    public var onPointerExit: (() -> Void)?
    public var onPointerDown: (() -> Void)?
    public var onPointerUpInside: (() -> Void)?
    public var onPointerUpOutside: (() -> Void)?
    public var onFocusEnter: (() -> Void)?
    public var onFocusExit: (() -> Void)?
    public var onKeyDown: ((KeyboardEvent) -> Void)?
    public var onTextInput: ((String) -> Void)?
    public var onActivate: (() -> Void)?
    public var onDragStart: ((Point) -> Void)?
    public var onDragChange: ((Point, Point) -> Void)?
    public var onDragEnd: ((Point, Point) -> Void)?
    public var onLayout: ((Rect) -> Void)?

    // Gap/Fix: Lifecycle hooks — called during appendCommands when node
    // first appears, disappears (removeFromParent), or changes frame size.
    public var onAppear: (() -> Void)?
    public var onDisappear: (() -> Void)?
    public var onSizeChange: ((Rect) -> Void)?
    private var hasAppeared = false
    private var previousFrame: Rect?

    public private(set) weak var parent: ViewNode?
    public private(set) var children: [ViewNode]

    fileprivate weak var runtime: RetainedViewRuntime?
    internal var resolvedFrame: Rect
    internal var resolvedContentSize: Size
    internal var resolvedScrollOffset: Double

    public init(
        frame: Rect = .zero,
        backgroundColor: Color? = nil,
        backgroundGradient: LinearGradient? = nil,
        text: String? = nil,
        textStyle: PixelTextStyle = PixelTextStyle(color: .white),
        borderColor: Color = .clear,
        borderWidth: Double = 0,
        outlineColor: Color = .clear,
        outlineWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        clipsToBounds: Bool = false,
        layoutMode: ViewLayoutMode = .absolute,
        preferredSize: Size? = nil,
        minimumSize: Size? = nil,
        maximumSize: Size? = nil,
        fillsAvailableWidth: Bool = false,
        fillsAvailableHeight: Bool = false,
        layoutPriority: Double = 0,
        flexItem: FlexProperties = .default,
        flexItemStyle: FlexItemStyle = FlexItemStyle(),
        blurRadius: Double = 0,
        opacity: Double = 1.0,
        zIndex: Double = 0,
        transform: Transform2D = .identity,
        scrollAxis: ScrollAxis? = nil,
        scrollOffset: Double = 0,
        scrollStep: Double = 64,
        showsScrollIndicator: Bool = false,
        scrollIndicatorColor: Color = Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.26),
        scrollIndicatorIdleColor: Color? = nil,
        scrollIndicatorHoverColor: Color = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
        scrollIndicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.72),
        scrollIndicatorThickness: Double = 6,
        isFocusable: Bool = false,
        isHitTestVisible: Bool = true,
        isHidden: Bool = false,
        children: [ViewNode] = []
    ) {
        self.frame = frame
        self.backgroundColor = backgroundColor
        self.backgroundGradient = backgroundGradient
        self.text = text
        self.textStyle = textStyle
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowSpread = shadowSpread
        self.cornerRadius = cornerRadius
        self.clipsToBounds = clipsToBounds
        self.layoutMode = layoutMode
        self.preferredSize = preferredSize
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.fillsAvailableWidth = fillsAvailableWidth
        self.fillsAvailableHeight = fillsAvailableHeight
        self.layoutPriority = layoutPriority
        self.flexItem = flexItem
        self.flexItemStyle = flexItemStyle
        self.blurRadius = blurRadius
        self.opacity = opacity
        self.zIndex = zIndex
        self.transform = transform
        self.scrollAxis = scrollAxis
        self.scrollOffset = scrollOffset
        self.scrollStep = scrollStep
        self.showsScrollIndicator = showsScrollIndicator
        self.scrollIndicatorColor = scrollIndicatorColor
        self.scrollIndicatorIdleColor = scrollIndicatorIdleColor ?? scrollIndicatorColor
        self.scrollIndicatorHoverColor = scrollIndicatorHoverColor
        self.scrollIndicatorActiveColor = scrollIndicatorActiveColor
        self.scrollIndicatorThickness = scrollIndicatorThickness
        self.isFocusable = isFocusable
        self.isHitTestVisible = isHitTestVisible
        self.isHidden = isHidden
        self.onPointerEnter = nil
        self.onPointerExit = nil
        self.onPointerDown = nil
        self.onPointerUpInside = nil
        self.onPointerUpOutside = nil
        self.onFocusEnter = nil
        self.onFocusExit = nil
        self.onKeyDown = nil
        self.onTextInput = nil
        self.onActivate = nil
        self.onDragStart = nil
        self.onDragChange = nil
        self.onDragEnd = nil
        self.onLayout = nil
        self.children = []
        self.resolvedFrame = frame
        self.resolvedContentSize = frame.size
        self.resolvedScrollOffset = 0

        for child in children {
            addChild(child)
        }
    }

    public func addChild(_ child: ViewNode) {
        child.removeFromParent()
        child.parent = self
        child.setRuntime(runtime)
        children.append(child)
        invalidateRuntime(.children)
    }

    public func removeChild(_ child: ViewNode) {
        guard let index = children.firstIndex(where: { $0 === child }) else {
            return
        }

        let removed = children.remove(at: index)
        // Gap/Fix: Lifecycle — fire onDisappear when node is removed from tree.
        if removed.hasAppeared {
            removed.onDisappear?()
            removed.hasAppeared = false
        }
        removed.parent = nil
        removed.setRuntime(nil)
        invalidateRuntime(.children)
    }

    public func removeFromParent() {
        parent?.removeChild(self)
    }

    public func removeAllChildren() {
        for child in children {
            // Gap/Fix: Lifecycle — fire onDisappear when node is removed from tree.
            if child.hasAppeared {
                child.onDisappear?()
                child.hasAppeared = false
            }
            child.parent = nil
            child.setRuntime(nil)
        }

        children.removeAll(keepingCapacity: false)
        invalidateRuntime(.children)
    }

    /// Replace the child at the given index with a new node.
    public func replaceChild(at index: Int, with newChild: ViewNode) {
        guard index >= 0, index < children.count else {
            return
        }

        let old = children[index]
        old.parent = nil
        old.setRuntime(nil)

        newChild.removeFromParent()
        newChild.parent = self
        newChild.setRuntime(runtime)
        children[index] = newChild
        invalidateRuntime()
    }

    /// Remove the child at the given index.
    public func removeChild(at index: Int) {
        guard index >= 0, index < children.count else {
            return
        }

        let removed = children.remove(at: index)
        removed.parent = nil
        removed.setRuntime(nil)
        invalidateRuntime()
    }

    fileprivate func setRuntime(_ runtime: RetainedViewRuntime?) {
        self.runtime = runtime
        for child in children {
            child.setRuntime(runtime)
        }
    }

    fileprivate func layoutSubtree() {
        onLayout?(resolvedFrame)

        switch layoutMode {
        case .absolute:
            var maxChildX: Double = 0
            var maxChildY: Double = 0

            for child in children {
                let childConstraints = LayoutConstraints(
                    maxWidth: remainingConstraintExtent(resolvedFrame.size.width, offset: child.frame.origin.x),
                    maxHeight: remainingConstraintExtent(resolvedFrame.size.height, offset: child.frame.origin.y)
                )
                let size = child.sizeThatFits(in: childConstraints)
                let resolvedSize = Size(
                    width: child.explicitWidth ?? size.width,
                    height: child.explicitHeight ?? size.height
                )
                child.resolvedFrame = Rect(origin: child.frame.origin, size: resolvedSize)
                child.layoutSubtree()
                maxChildX = max(maxChildX, child.resolvedFrame.maxX)
                maxChildY = max(maxChildY, child.resolvedFrame.maxY)
            }

            resolvedContentSize = Size(
                width: max(resolvedFrame.size.width, maxChildX),
                height: max(resolvedFrame.size.height, maxChildY)
            )

        case .stack(let stackLayout):
            let contentRect = Rect(origin: .zero, size: resolvedFrame.size).inset(by: stackLayout.padding)
            let visibleChildren = children.filter { !$0.isHidden }
            let childConstraints = stackChildConstraints(for: contentRect.size, axis: stackLayout.axis)
            let desiredSizes = visibleChildren.map { $0.sizeThatFits(in: childConstraints) }
            let desiredMainSizes = desiredSizes.map { size in
                stackLayout.axis == .vertical ? size.height : size.width
            }
            let spacingTotal = stackLayoutSpacingTotal(count: visibleChildren.count, spacing: stackLayout.spacing)
            let availableMainExtent = stackLayout.axis == .vertical ? max(0, contentRect.size.height) : max(0, contentRect.size.width)
            let availableChildMainExtent = max(0, availableMainExtent - spacingTotal)
            let allowsOverflowAlongMainAxis = scrollAxis == stackScrollAxis(for: stackLayout.axis)

            // Allocate main sizes with flex support
            var allocatedMainSizes: [Double]
            if allowsOverflowAlongMainAxis {
                allocatedMainSizes = desiredMainSizes
            } else {
                allocatedMainSizes = allocateMainSizes(
                    desiredSizes: desiredMainSizes,
                    children: visibleChildren,
                    availableExtent: availableChildMainExtent
                )
            }

            // Apply flex grow/shrink
            if !allowsOverflowAlongMainAxis, !visibleChildren.isEmpty {
                let allocatedTotal = allocatedMainSizes.reduce(0, +)
                let remaining = availableChildMainExtent - allocatedTotal

                if remaining > 0 {
                    // Distribute remaining space to items with flexGrow > 0
                    let totalGrow = visibleChildren.reduce(0.0) { $0 + $1.flexItem.grow }
                    if totalGrow > 0 {
                        var leftover = remaining
                        for (i, child) in visibleChildren.enumerated() {
                            guard child.flexItem.grow > 0 else { continue }
                            let share: Double
                            if i == visibleChildren.count - 1 {
                                share = leftover
                            } else {
                                share = remaining * (child.flexItem.grow / totalGrow)
                                leftover -= share
                            }
                            allocatedMainSizes[i] += share
                        }
                    }
                } else if remaining < 0 {
                    // Shrink items with flexShrink > 0
                    let deficit = -remaining
                    let totalShrink = visibleChildren.reduce(0.0) { $0 + $1.flexItem.shrink }
                    if totalShrink > 0 {
                        var leftover = deficit
                        for (i, child) in visibleChildren.enumerated() {
                            guard child.flexItem.shrink > 0 else { continue }
                            let share: Double
                            if i == visibleChildren.count - 1 {
                                share = leftover
                            } else {
                                share = deficit * (child.flexItem.shrink / totalShrink)
                                leftover -= share
                            }
                            allocatedMainSizes[i] = max(0, allocatedMainSizes[i] - share)
                        }
                    }
                }
            }

            let occupiedMainExtent = allocatedMainSizes.reduce(0, +) + spacingTotal

            // Calculate spacing and start position based on distribution
            let mainOrigin = stackLayout.axis == .vertical ? contentRect.origin.y : contentRect.origin.x
            let mainCursorStart: Double
            let effectiveSpacing: Double

            switch stackLayout.distribution {
            case .fill:
                effectiveSpacing = stackLayout.spacing
                switch stackLayout.mainAlignment {
                case .start:
                    mainCursorStart = mainOrigin
                case .center:
                    mainCursorStart = mainOrigin + max(0, (availableMainExtent - occupiedMainExtent) * 0.5)
                case .end:
                    mainCursorStart = mainOrigin + max(0, availableMainExtent - occupiedMainExtent)
                }

            case .spaceBetween:
                let itemsTotal = allocatedMainSizes.reduce(0, +)
                let freeSpace = max(0, availableMainExtent - itemsTotal)
                effectiveSpacing = visibleChildren.count > 1 ? freeSpace / Double(visibleChildren.count - 1) : 0
                mainCursorStart = mainOrigin

            case .spaceAround:
                let itemsTotal = allocatedMainSizes.reduce(0, +)
                let freeSpace = max(0, availableMainExtent - itemsTotal)
                let slotSpace = visibleChildren.count > 0 ? freeSpace / Double(visibleChildren.count) : 0
                effectiveSpacing = slotSpace
                mainCursorStart = mainOrigin + slotSpace * 0.5

            case .spaceEvenly:
                let itemsTotal = allocatedMainSizes.reduce(0, +)
                let freeSpace = max(0, availableMainExtent - itemsTotal)
                let slotSpace = visibleChildren.count > 0 ? freeSpace / Double(visibleChildren.count + 1) : 0
                effectiveSpacing = slotSpace
                mainCursorStart = mainOrigin + slotSpace
            }

            var mainCursor = mainCursorStart
            var visibleIndex = 0
            var maxCrossExtent: Double = 0

            for child in children {
                if child.isHidden {
                    child.resolvedFrame = Rect(x: 0, y: 0, width: 0, height: 0)
                    continue
                }

                let desiredSize = desiredSizes[visibleIndex]
                let allocatedMainSize = allocatedMainSizes[visibleIndex]
                let childFrame: Rect

                switch stackLayout.axis {
                case .vertical:
                    let width = stackLayout.alignment == .stretch ? max(0, contentRect.size.width) : min(desiredSize.width, max(0, contentRect.size.width))
                    let height = max(0, allocatedMainSize)

                    let x: Double
                    switch stackLayout.alignment {
                    case .leading, .stretch:
                        x = contentRect.origin.x
                    case .center:
                        x = contentRect.origin.x + max(0, (contentRect.size.width - width) * 0.5)
                    case .trailing:
                        x = contentRect.maxX - width
                    }

                    childFrame = Rect(x: x, y: mainCursor, width: max(0, width), height: max(0, height))
                    mainCursor += height + effectiveSpacing
                    maxCrossExtent = max(maxCrossExtent, width)

                case .horizontal:
                    let width = max(0, allocatedMainSize)
                    let height = stackLayout.alignment == .stretch ? max(0, contentRect.size.height) : min(desiredSize.height, max(0, contentRect.size.height))

                    let y: Double
                    switch stackLayout.alignment {
                    case .leading, .stretch:
                        y = contentRect.origin.y
                    case .center:
                        y = contentRect.origin.y + max(0, (contentRect.size.height - height) * 0.5)
                    case .trailing:
                        y = contentRect.maxY - height
                    }

                    childFrame = Rect(x: mainCursor, y: y, width: max(0, width), height: max(0, height))
                    mainCursor += width + effectiveSpacing
                    maxCrossExtent = max(maxCrossExtent, height)
                }

                child.resolvedFrame = childFrame
                child.layoutSubtree()
                visibleIndex += 1
            }

            let contentMainExtent = (
                (allowsOverflowAlongMainAxis ? desiredMainSizes : allocatedMainSizes).reduce(0, +) +
                spacingTotal +
                stackMainPadding(for: stackLayout)
            )
            let contentCrossExtent = maxCrossExtent + stackCrossPadding(for: stackLayout)

            switch stackLayout.axis {
            case .vertical:
                resolvedContentSize = Size(
                    width: max(resolvedFrame.size.width, contentCrossExtent),
                    height: max(resolvedFrame.size.height, contentMainExtent)
                )
            case .horizontal:
                resolvedContentSize = Size(
                    width: max(resolvedFrame.size.width, contentMainExtent),
                    height: max(resolvedFrame.size.height, contentCrossExtent)
                )
            }

        case .flex(let flexStyle):
            let visibleChildren = children.filter { !$0.isHidden }

            let childInputs = visibleChildren.map { child -> FlexboxEngine.LayoutInput.ChildInput in
                let intrinsicSize = child.intrinsicContentSize()
                return FlexboxEngine.LayoutInput.ChildInput(
                    itemStyle: child.flexItemStyle,
                    intrinsicWidth: child.preferredSize?.width ?? intrinsicSize.width,
                    intrinsicHeight: child.preferredSize?.height ?? intrinsicSize.height
                )
            }

            let input = FlexboxEngine.LayoutInput(
                containerWidth: resolvedFrame.size.width,
                containerHeight: resolvedFrame.size.height,
                style: flexStyle,
                children: childInputs
            )

            let layouts = FlexboxEngine.layout(input)

            var visibleIndex = 0
            for child in children {
                if child.isHidden {
                    child.resolvedFrame = Rect(x: 0, y: 0, width: 0, height: 0)
                    continue
                }

                let childLayout = layouts[visibleIndex]
                child.resolvedFrame = Rect(x: childLayout.x, y: childLayout.y, width: childLayout.width, height: childLayout.height)
                child.layoutSubtree()
                visibleIndex += 1
            }

            resolvedContentSize = resolvedFrame.size
        }

        resolvedScrollOffset = clampedScrollOffset(for: scrollOffset)
    }

    fileprivate func appendCommands(
        into commands: inout [RenderCommand],
        parentOrigin: Point,
        inheritedClip: Rect?,
        inheritedOpacity: Double
    ) {
        if isHidden {
            return
        }

        let absoluteFrame = Rect(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y,
            width: resolvedFrame.size.width,
            height: resolvedFrame.size.height
        )

        // Gap/Fix: Occlusion culling — skip the entire node early if it is
        // fully outside the inherited clip bounds (before allocating any
        // command structs).
        if !baseClipAllowsDrawing(baseClip: inheritedClip, rect: absoluteFrame) {
            return
        }

        // Gap/Fix: Lifecycle — fire onAppear the first time a node is rendered.
        if !hasAppeared {
            hasAppeared = true
            onAppear?()
            previousFrame = absoluteFrame
        }

        // Gap/Fix: Lifecycle — fire onSizeChange when the resolved frame differs
        // from the previously recorded frame.
        if let prev = previousFrame, prev != absoluteFrame {
            onSizeChange?(absoluteFrame)
        }
        previousFrame = absoluteFrame

        let effectiveOpacity = clampedOpacity(inheritedOpacity * opacity)
        guard effectiveOpacity > 0 else {
            return
        }

        var effectiveClip = inheritedClip
        if clipsToBounds {
            if let inheritedClip {
                guard let clippedRect = inheritedClip.intersected(with: absoluteFrame) else {
                    return
                }

                effectiveClip = clippedRect
            } else {
                effectiveClip = absoluteFrame
            }
        }

        // Gap/Fix: Opacity group compositing — when a view has opacity < 1 AND
        // has children, the correct result requires compositing into an offscreen
        // texture first. Without that, each child is blended individually, which
        // causes overlapping children to double-blend.
        // TODO: Opacity < 1 with overlapping children double-blends. Requires render-to-texture for correct compositing.

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        let resolvedShadowColor = applyingOpacity(effectiveOpacity, to: shadowColor)
        if resolvedShadowColor.alpha > 0 {
            let shadowRect = absoluteFrame
                .outset(by: max(0, shadowSpread))
                .offsetBy(dx: shadowOffset.x, dy: shadowOffset.y)

            if baseClipAllowsDrawing(baseClip: inheritedClip, rect: shadowRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: shadowRect,
                            color: resolvedShadowColor,
                            cornerRadius: cornerRadius + max(0, shadowSpread),
                            clipRect: inheritedClip
                        )
                    )
                )
            }
        }

        let resolvedOutlineColor = applyingOpacity(effectiveOpacity, to: outlineColor)
        if resolvedOutlineColor.alpha > 0, outlineWidth > 0 {
            let outlineRect = absoluteFrame.outset(by: outlineWidth)
            if baseClipAllowsDrawing(baseClip: inheritedClip, rect: outlineRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: outlineRect,
                            color: resolvedOutlineColor,
                            cornerRadius: cornerRadius + outlineWidth,
                            clipRect: inheritedClip
                        )
                    )
                )
            }
        }

        let resolvedBorderColor = applyingOpacity(effectiveOpacity, to: borderColor)
        if resolvedBorderColor.alpha > 0, borderWidth > 0, baseClipAllowsDrawing(baseClip: effectiveClip, rect: absoluteFrame) {
            commands.append(
                .fillRect(
                    FillRectCommand(
                        rect: absoluteFrame,
                        color: resolvedBorderColor,
                        cornerRadius: cornerRadius,
                        clipRect: effectiveClip
                    )
                )
            )
        }

        let fillRect = borderWidth > 0 ? absoluteFrame.inset(by: borderWidth) : absoluteFrame
        let fillCornerRadius = max(0, cornerRadius - borderWidth)

        let resolvedBackgroundColor = backgroundColor ?? backgroundGradient?.startColor
        if let resolvedBackgroundColor, resolvedBackgroundColor.alpha > 0, fillRect.size.width > 0, fillRect.size.height > 0 {
            if baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: fillRect,
                            color: applyingOpacity(effectiveOpacity, to: resolvedBackgroundColor),
                            cornerRadius: fillCornerRadius,
                            clipRect: effectiveClip,
                            gradient: backgroundGradient.map { applyingOpacity(effectiveOpacity, to: $0) }
                        )
                    )
                )
            }
        }

        if let text, !text.isEmpty, baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
            let displayScale = runtime?.displayScale ?? 1.0
            let textCommandStartIndex = commands.count
            if !NativeTextRenderer.appendCommands(for: text, in: fillRect, style: textStyle, scaleFactor: displayScale, clipRect: effectiveClip, into: &commands) {
                PixelFont.appendCommands(
                    for: text,
                    in: fillRect,
                    style: textStyle,
                    clipRect: effectiveClip,
                    into: &commands
                )
            }
            applyOpacity(to: &commands, from: textCommandStartIndex, opacity: effectiveOpacity)
        }

        // Gap/Fix: Emit blur render command — apply Gaussian blur over
        // the view's content region when blurRadius is set.
        if blurRadius > 0, baseClipAllowsDrawing(baseClip: effectiveClip, rect: absoluteFrame) {
            commands.append(
                .applyBlur(
                    BlurCommand(
                        region: absoluteFrame,
                        radius: blurRadius
                    )
                )
            )
        }

        // Gap/Fix: Z-index sibling sort — children are drawn in zIndex
        // order (stable sort preserves original order for equal zIndex).
        // NOTE: zIndex only sorts among siblings within the same parent.
        // For cross-subtree ordering (e.g. modals, overlays, popups),
        // views should be added at the root level or to a dedicated
        // overlay container rather than relying on zIndex across
        // different subtrees.
        let sortedChildren: [ViewNode]
        if children.contains(where: { $0.zIndex != 0 }) {
            sortedChildren = children.enumerated()
                .sorted { a, b in
                    if a.element.zIndex != b.element.zIndex {
                        return a.element.zIndex < b.element.zIndex
                    }
                    return a.offset < b.offset
                }
                .map(\.element)
        } else {
            sortedChildren = children
        }

        for child in sortedChildren {
            child.appendCommands(
                into: &commands,
                parentOrigin: childOrigin,
                inheritedClip: effectiveClip,
                inheritedOpacity: effectiveOpacity
            )
        }

        let resolvedScrollIndicatorColor = applyingOpacity(effectiveOpacity, to: scrollIndicatorColor)
        if let scrollIndicator = scrollIndicatorRect(in: absoluteFrame), resolvedScrollIndicatorColor.alpha > 0 {
            commands.append(
                .fillRect(
                    FillRectCommand(
                        rect: scrollIndicator,
                        color: resolvedScrollIndicatorColor,
                        cornerRadius: min(scrollIndicator.size.width, scrollIndicator.size.height) * 0.5,
                        clipRect: effectiveClip
                    )
                )
            )
        }
    }

    fileprivate func hitTest(at point: Point, parentOrigin: Point, inheritedClip: Rect?) -> ViewNode? {
        if isHidden {
            return nil
        }

        let absoluteFrame = Rect(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y,
            width: resolvedFrame.size.width,
            height: resolvedFrame.size.height
        )

        var effectiveClip = inheritedClip
        if clipsToBounds {
            if let inheritedClip {
                guard let clippedRect = inheritedClip.intersected(with: absoluteFrame) else {
                    return nil
                }

                effectiveClip = clippedRect
            } else {
                effectiveClip = absoluteFrame
            }
        }

        if let effectiveClip, !effectiveClip.contains(point) {
            return nil
        }

        // Gap/Fix: Hit testing with transforms — apply the inverse of the view's
        // transform (centered on the view's center) to the test point before
        // checking containment. This ensures rotated/scaled views are hit-tested
        // in their local coordinate space.
        let testPoint: Point
        if !transform.isIdentity {
            let cx = absoluteFrame.origin.x + absoluteFrame.size.width * 0.5
            let cy = absoluteFrame.origin.y + absoluteFrame.size.height * 0.5
            let centeredTransform = Transform2D.translation(x: cx, y: cy)
                .concatenating(transform)
                .concatenating(.translation(x: -cx, y: -cy))
            if let inverseTransform = centeredTransform.inverseOrNil() {
                testPoint = inverseTransform.applying(to: point)
            } else {
                testPoint = point
            }
        } else {
            testPoint = point
        }

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        for child in children.reversed() {
            if let hitNode = child.hitTest(at: testPoint, parentOrigin: childOrigin, inheritedClip: effectiveClip) {
                return hitNode
            }
        }

        if isHitTestVisible, absoluteFrame.contains(testPoint) {
            return self
        }

        return nil
    }

    fileprivate func scrollTarget(at point: Point, parentOrigin: Point, inheritedClip: Rect?) -> ViewNode? {
        if isHidden {
            return nil
        }

        let absoluteFrame = Rect(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y,
            width: resolvedFrame.size.width,
            height: resolvedFrame.size.height
        )

        var effectiveClip = inheritedClip
        if clipsToBounds {
            if let inheritedClip {
                guard let clippedRect = inheritedClip.intersected(with: absoluteFrame) else {
                    return nil
                }

                effectiveClip = clippedRect
            } else {
                effectiveClip = absoluteFrame
            }
        }

        if let effectiveClip, !effectiveClip.contains(point) {
            return nil
        }

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        for child in children.reversed() {
            if let target = child.scrollTarget(at: point, parentOrigin: childOrigin, inheritedClip: effectiveClip) {
                return target
            }
        }

        if isScrollable, absoluteFrame.contains(point) {
            return self
        }

        return nil
    }

    fileprivate func scrollIndicatorHit(at point: Point, parentOrigin: Point, inheritedClip: Rect?) -> ScrollIndicatorHit? {
        if isHidden {
            return nil
        }

        let absoluteFrame = Rect(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y,
            width: resolvedFrame.size.width,
            height: resolvedFrame.size.height
        )

        var effectiveClip = inheritedClip
        if clipsToBounds {
            if let inheritedClip {
                guard let clippedRect = inheritedClip.intersected(with: absoluteFrame) else {
                    return nil
                }

                effectiveClip = clippedRect
            } else {
                effectiveClip = absoluteFrame
            }
        }

        if let effectiveClip, !effectiveClip.contains(point) {
            return nil
        }

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        for child in children.reversed() {
            if let hit = child.scrollIndicatorHit(at: point, parentOrigin: childOrigin, inheritedClip: effectiveClip) {
                return hit
            }
        }

        guard let track = scrollIndicatorTrack(in: absoluteFrame), track.indicatorRect.contains(point) else {
            return nil
        }

        return ScrollIndicatorHit(node: self, track: track)
    }

    private func invalidateRuntime(_ flags: DirtyFlags = .all) {
        runtime?.invalidate(flags)
    }

    fileprivate func sizeThatFits(in constraints: LayoutConstraints) -> Size {
        var measuredSize = textContentSize(in: constraints) ?? .zero

        switch layoutMode {
        case .absolute:
            var maxChildX = measuredSize.width
            var maxChildY = measuredSize.height

            for child in children where !child.isHidden {
                let childConstraints = LayoutConstraints(
                    maxWidth: remainingConstraintExtent(constraints.maxWidth, offset: child.frame.origin.x),
                    maxHeight: remainingConstraintExtent(constraints.maxHeight, offset: child.frame.origin.y)
                )
                let childSize = child.sizeThatFits(in: childConstraints)
                let resolvedWidth = child.explicitWidth ?? childSize.width
                let resolvedHeight = child.explicitHeight ?? childSize.height
                maxChildX = max(maxChildX, child.frame.origin.x + resolvedWidth)
                maxChildY = max(maxChildY, child.frame.origin.y + resolvedHeight)
            }

            measuredSize = Size(width: maxChildX, height: maxChildY)

        case .stack(let stackLayout):
            let contentConstraints = insetConstraints(constraints, by: stackLayout.padding)
            let childConstraints = stackChildConstraints(for: contentConstraints, axis: stackLayout.axis)
            let visibleChildren = children.filter { !$0.isHidden }
            let childSizes = visibleChildren.map { $0.sizeThatFits(in: childConstraints) }
            let spacingTotal = stackLayoutSpacingTotal(count: childSizes.count, spacing: stackLayout.spacing)
            let mainExtent = childSizes.reduce(0.0) { partialResult, size in
                partialResult + (stackLayout.axis == .vertical ? size.height : size.width)
            } + spacingTotal + stackMainPadding(for: stackLayout)
            let crossExtent = (childSizes.map { size in
                stackLayout.axis == .vertical ? size.width : size.height
            }.max() ?? 0) + stackCrossPadding(for: stackLayout)

            measuredSize = Size(
                width: stackLayout.axis == .vertical ? crossExtent : mainExtent,
                height: stackLayout.axis == .vertical ? mainExtent : crossExtent
            )

        case .flex(let flexStyle):
            let visibleChildren = children.filter { !$0.isHidden }
            let childSizes = visibleChildren.map { $0.sizeThatFits(in: .unconstrained) }
            let isRow = flexStyle.direction == .row || flexStyle.direction == .rowReverse
            let gapTotal = visibleChildren.count > 1 ? flexStyle.gap * Double(visibleChildren.count - 1) : 0

            let mainExtent = childSizes.reduce(0.0) { partialResult, size in
                partialResult + (isRow ? size.width : size.height)
            } + gapTotal + (isRow
                ? flexStyle.padding.leading + flexStyle.padding.trailing
                : flexStyle.padding.top + flexStyle.padding.bottom)

            let crossExtent = (childSizes.map { size in
                isRow ? size.height : size.width
            }.max() ?? 0) + (isRow
                ? flexStyle.padding.top + flexStyle.padding.bottom
                : flexStyle.padding.leading + flexStyle.padding.trailing)

            measuredSize = Size(
                width: isRow ? mainExtent : crossExtent,
                height: isRow ? crossExtent : mainExtent
            )
        }

        return applyingExplicitDimensions(to: measuredSize, constraints: constraints)
    }

    public func intrinsicContentSize() -> Size {
        sizeThatFits(in: .unconstrained)
    }

    private func textContentSize(in constraints: LayoutConstraints) -> Size? {
        guard let text, !text.isEmpty else {
            return nil
        }

        let displayScale = runtime?.displayScale ?? 1.0
        let maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : nil
        return NativeTextRenderer.measure(text, style: textStyle, scaleFactor: displayScale, maxWidth: maxWidth)
            ?? PixelFont.measure(text, style: textStyle, maxWidth: maxWidth)
    }

    private func applyingExplicitDimensions(to size: Size, constraints: LayoutConstraints) -> Size {
        var measuredWidth = explicitWidth ?? size.width
        var measuredHeight = explicitHeight ?? size.height
        let resolvedMinimumWidth = max(constraints.minWidth, minimumSize?.width ?? 0)
        let resolvedMinimumHeight = max(constraints.minHeight, minimumSize?.height ?? 0)
        let resolvedMaximumWidth = minimumFiniteExtent(constraints.maxWidth, maximumSize?.width)
        let resolvedMaximumHeight = minimumFiniteExtent(constraints.maxHeight, maximumSize?.height)

        if fillsAvailableWidth, constraints.maxWidth.isFinite {
            measuredWidth = max(measuredWidth, constraints.maxWidth)
        }

        if fillsAvailableHeight, constraints.maxHeight.isFinite {
            measuredHeight = max(measuredHeight, constraints.maxHeight)
        }

        return Size(
            width: clampedExtent(measuredWidth, min: resolvedMinimumWidth, max: resolvedMaximumWidth),
            height: clampedExtent(measuredHeight, min: resolvedMinimumHeight, max: resolvedMaximumHeight)
        )
    }

    private var explicitWidth: Double? {
        if let preferredSize, preferredSize.width > 0 {
            return preferredSize.width
        }

        if frame.size.width > 0 {
            return frame.size.width
        }

        return nil
    }

    private var explicitHeight: Double? {
        if let preferredSize, preferredSize.height > 0 {
            return preferredSize.height
        }

        if frame.size.height > 0 {
            return frame.size.height
        }

        return nil
    }

    private func allocateMainSizes(
        desiredSizes: [Double],
        children: [ViewNode],
        availableExtent: Double
    ) -> [Double] {
        var allocatedSizes = desiredSizes
        let desiredExtent = desiredSizes.reduce(0, +)

        if desiredExtent > availableExtent {
            shrinkMainSizes(&allocatedSizes, children: children, deficit: desiredExtent - availableExtent)
        } else if desiredExtent < availableExtent {
            growMainSizes(&allocatedSizes, children: children, extraExtent: availableExtent - desiredExtent)
        }

        return allocatedSizes
    }

    private func growMainSizes(_ sizes: inout [Double], children: [ViewNode], extraExtent: Double) {
        let participantIndices = children.indices.filter { children[$0].layoutPriority > 0 }
        guard !participantIndices.isEmpty else {
            return
        }

        let totalPriority = participantIndices.reduce(0.0) { partialResult, index in
            partialResult + children[index].layoutPriority
        }
        guard totalPriority > 0 else {
            return
        }

        var remainingExtent = extraExtent
        for (offset, index) in participantIndices.enumerated() {
            let share: Double
            if offset == participantIndices.count - 1 {
                share = remainingExtent
            } else {
                share = extraExtent * (children[index].layoutPriority / totalPriority)
                remainingExtent -= share
            }

            sizes[index] += share
        }
    }

    private func shrinkMainSizes(_ sizes: inout [Double], children: [ViewNode], deficit: Double) {
        var remainingDeficit = deficit
        let priorities = Array(Set(children.map(\.layoutPriority))).sorted()

        for priority in priorities where remainingDeficit > 0 {
            let indices = children.indices.filter { children[$0].layoutPriority == priority && sizes[$0] > 0 }
            guard !indices.isEmpty else {
                continue
            }

            let shrinkCapacity = indices.reduce(0.0) { partialResult, index in
                partialResult + sizes[index]
            }
            guard shrinkCapacity > 0 else {
                continue
            }

            let targetReduction = min(remainingDeficit, shrinkCapacity)
            var remainingReduction = targetReduction

            for (offset, index) in indices.enumerated() {
                let reduction: Double
                if offset == indices.count - 1 {
                    reduction = remainingReduction
                } else {
                    reduction = targetReduction * (sizes[index] / shrinkCapacity)
                    remainingReduction -= reduction
                }

                let appliedReduction = min(sizes[index], reduction)
                sizes[index] -= appliedReduction
            }

            remainingDeficit -= targetReduction
        }
    }

    fileprivate var isScrollable: Bool {
        scrollAxis != nil
    }

    fileprivate var isDraggable: Bool {
        onDragStart != nil || onDragChange != nil || onDragEnd != nil
    }

    fileprivate var maxScrollOffset: Double {
        switch scrollAxis {
        case .horizontal:
            return max(0, resolvedContentSize.width - resolvedFrame.size.width)
        case .vertical:
            return max(0, resolvedContentSize.height - resolvedFrame.size.height)
        case nil:
            return 0
        }
    }

    fileprivate func applyMouseWheelDelta(_ delta: Double) -> Bool {
        guard isScrollable else {
            return false
        }

        let nextOffset = clampedScrollOffset(for: scrollOffset - delta * scrollStep)
        guard nextOffset != scrollOffset else {
            return false
        }

        scrollOffset = nextOffset
        return true
    }

    fileprivate func applyKeyboardScroll(_ key: KeyboardKey) -> Bool {
        guard isScrollable else {
            return false
        }

        switch (scrollAxis, key) {
        case (.vertical, .downArrow), (.horizontal, .rightArrow):
            return applyScrollDelta(scrollStep)
        case (.vertical, .upArrow), (.horizontal, .leftArrow):
            return applyScrollDelta(-scrollStep)
        case (_, .pageDown):
            return applyScrollDelta((scrollAxis == .vertical ? resolvedFrame.size.height : resolvedFrame.size.width) * 0.85)
        case (_, .pageUp):
            return applyScrollDelta(-(scrollAxis == .vertical ? resolvedFrame.size.height : resolvedFrame.size.width) * 0.85)
        case (_, .home):
            return setScrollOffset(0)
        case (_, .end):
            return setScrollOffset(maxScrollOffset)
        default:
            return false
        }
    }

    fileprivate func applyScrollIndicatorDrag(startOffset: Double, delta: Double, travel: Double) -> Bool {
        guard maxScrollOffset > 0, travel > 0 else {
            return false
        }

        let translatedOffset = startOffset + delta * (maxScrollOffset / travel)
        return setScrollOffset(translatedOffset)
    }

    fileprivate func scrollIndicatorRect(in absoluteFrame: Rect) -> Rect? {
        guard showsScrollIndicator, isScrollable, maxScrollOffset > 0, scrollIndicatorColor.alpha > 0 else {
            return nil
        }

        let indicatorInset = 6.0
        let indicatorThickness = max(4, scrollIndicatorThickness)

        switch scrollAxis {
        case .vertical:
            let trackHeight = max(0, absoluteFrame.size.height - indicatorInset * 2)
            guard trackHeight > 0 else { return nil }
            let visibleRatio = max(0.08, absoluteFrame.size.height / max(resolvedContentSize.height, absoluteFrame.size.height))
            let indicatorHeight = max(24, trackHeight * visibleRatio)
            let travel = max(0, trackHeight - indicatorHeight)
            let progress = maxScrollOffset > 0 ? resolvedScrollOffset / maxScrollOffset : 0
            return Rect(
                x: absoluteFrame.maxX - indicatorInset - indicatorThickness,
                y: absoluteFrame.origin.y + indicatorInset + travel * progress,
                width: indicatorThickness,
                height: indicatorHeight
            )

        case .horizontal:
            let trackWidth = max(0, absoluteFrame.size.width - indicatorInset * 2)
            guard trackWidth > 0 else { return nil }
            let visibleRatio = max(0.08, absoluteFrame.size.width / max(resolvedContentSize.width, absoluteFrame.size.width))
            let indicatorWidth = max(24, trackWidth * visibleRatio)
            let travel = max(0, trackWidth - indicatorWidth)
            let progress = maxScrollOffset > 0 ? resolvedScrollOffset / maxScrollOffset : 0
            return Rect(
                x: absoluteFrame.origin.x + indicatorInset + travel * progress,
                y: absoluteFrame.maxY - indicatorInset - indicatorThickness,
                width: indicatorWidth,
                height: indicatorThickness
            )

        case nil:
            return nil
        }
    }

    fileprivate func scrollIndicatorTrack(in absoluteFrame: Rect) -> ScrollIndicatorTrack? {
        guard let indicatorRect = scrollIndicatorRect(in: absoluteFrame), let scrollAxis else {
            return nil
        }

        let inset = 6.0

        switch scrollAxis {
        case .vertical:
            let trackLength = max(0, absoluteFrame.size.height - inset * 2)
            return ScrollIndicatorTrack(
                axis: .vertical,
                origin: absoluteFrame.origin.y + inset,
                travel: max(0, trackLength - indicatorRect.size.height),
                indicatorRect: indicatorRect
            )

        case .horizontal:
            let trackLength = max(0, absoluteFrame.size.width - inset * 2)
            return ScrollIndicatorTrack(
                axis: .horizontal,
                origin: absoluteFrame.origin.x + inset,
                travel: max(0, trackLength - indicatorRect.size.width),
                indicatorRect: indicatorRect
            )
        }
    }

    private func clampedScrollOffset(for value: Double) -> Double {
        min(max(value, 0), maxScrollOffset)
    }

    private func applyScrollDelta(_ delta: Double) -> Bool {
        setScrollOffset(scrollOffset + delta)
    }

    private func setScrollOffset(_ value: Double) -> Bool {
        let nextOffset = clampedScrollOffset(for: value)
        guard nextOffset != scrollOffset else {
            return false
        }

        scrollOffset = nextOffset
        return true
    }

    fileprivate func color(for property: AnimatedColorProperty) -> Color {
        switch property {
        case .background:
            return backgroundColor ?? .clear
        case .border:
            return borderColor
        case .outline:
            return outlineColor
        case .shadow:
            return shadowColor
        case .scrollIndicator:
            return scrollIndicatorColor
        }
    }

    fileprivate func setColor(_ color: Color, for property: AnimatedColorProperty) {
        switch property {
        case .background:
            backgroundColor = color
        case .border:
            borderColor = color
        case .outline:
            outlineColor = color
        case .shadow:
            shadowColor = color
        case .scrollIndicator:
            scrollIndicatorColor = color
        }
    }
}

private func insetConstraints(_ constraints: LayoutConstraints, by padding: EdgeInsets) -> LayoutConstraints {
    LayoutConstraints(
        minWidth: max(0, constraints.minWidth - padding.leading - padding.trailing),
        maxWidth: remainingConstraintExtent(constraints.maxWidth, offset: padding.leading + padding.trailing),
        minHeight: max(0, constraints.minHeight - padding.top - padding.bottom),
        maxHeight: remainingConstraintExtent(constraints.maxHeight, offset: padding.top + padding.bottom)
    )
}

private func stackChildConstraints(for size: Size, axis: StackAxis) -> LayoutConstraints {
    switch axis {
    case .vertical:
        return LayoutConstraints(maxWidth: max(0, size.width))
    case .horizontal:
        return LayoutConstraints(maxHeight: max(0, size.height))
    }
}

private func stackChildConstraints(for constraints: LayoutConstraints, axis: StackAxis) -> LayoutConstraints {
    switch axis {
    case .vertical:
        return LayoutConstraints(maxWidth: constraints.maxWidth)
    case .horizontal:
        return LayoutConstraints(maxHeight: constraints.maxHeight)
    }
}

private func stackLayoutSpacingTotal(count: Int, spacing: Double) -> Double {
    guard count > 1 else {
        return 0
    }

    return Double(count - 1) * spacing
}

private func stackMainPadding(for layout: StackLayout) -> Double {
    switch layout.axis {
    case .vertical:
        return layout.padding.top + layout.padding.bottom
    case .horizontal:
        return layout.padding.leading + layout.padding.trailing
    }
}

private func stackCrossPadding(for layout: StackLayout) -> Double {
    switch layout.axis {
    case .vertical:
        return layout.padding.leading + layout.padding.trailing
    case .horizontal:
        return layout.padding.top + layout.padding.bottom
    }
}

private func stackScrollAxis(for axis: StackAxis) -> ScrollAxis {
    switch axis {
    case .vertical:
        return .vertical
    case .horizontal:
        return .horizontal
    }
}

private func remainingConstraintExtent(_ maxExtent: Double, offset: Double) -> Double {
    guard maxExtent.isFinite else {
        return .infinity
    }

    return max(0, maxExtent - offset)
}

private func minimumFiniteExtent(_ first: Double, _ second: Double?) -> Double {
    guard let second, second.isFinite else {
        return first
    }

    guard first.isFinite else {
        return second
    }

    return min(first, second)
}

private func clampedExtent(_ extent: Double, min minimum: Double, max maximum: Double) -> Double {
    var value = max(extent, minimum)
    if maximum.isFinite {
        value = min(value, maximum)
    }
    return value
}

@MainActor
public final class RetainedViewRuntime {
    public let root: ViewNode

    public var displayScale: Double {
        didSet {
            // Gap/Fix: Text cache granular invalidation — only invalidate the
            // text raster cache when the scale factor actually changed, rather
            // than clearing it on every dirty pass.
            if oldValue != displayScale {
                textRasterCache?.clear()
            }
            invalidate()
        }
    }

    public var clearColor: Color {
        didSet { invalidate() }
    }

    public var hasActiveAnimations: Bool {
        !colorAnimations.isEmpty
    }

    // Gap/Fix: Granular dirty tracking — DirtyFlags replaces single boolean.
    public private(set) var dirtyFlags: DirtyFlags = .all
    public var isDirty: Bool { !dirtyFlags.isEmpty }
    private var cachedFrame: RenderFrame?
    private weak var hoveredNode: ViewNode?
    private weak var pressedNode: ViewNode?
    private weak var focusedNode: ViewNode?
    private weak var hoveredScrollIndicatorNode: ViewNode?
    private weak var activeScrollIndicatorNode: ViewNode?
    private var colorAnimations: [ColorAnimationKey: ViewColorAnimation] = [:]
    private var scrollDragState: ScrollDragState?
    private var nodeDragState: NodeDragState?

    /// Optional text raster cache for scale-aware invalidation.
    public var textRasterCache: TextRasterCache?

    // Gap/Fix: Frame pacing enforcement — minimum interval between renders.
    public var minimumFrameInterval: Double?
    private var lastRenderTime: Double = 0

    public init(clearColor: Color = .black, root: ViewNode = ViewNode(), displayScale: Double = 1.0) {
        self.clearColor = clearColor
        self.root = root
        self.displayScale = displayScale
        self.root.setRuntime(self)
    }

    public func setRootSize(_ size: IntSize) {
        let nextSize = Size(width: Double(size.width), height: Double(size.height))
        if root.frame.size != nextSize {
            root.frame.size = nextSize
        }
    }

    public func renderFrame(at timestamp: Double = 0) -> RenderFrame {
        if let cachedFrame, !isDirty {
            return cachedFrame
        }

        // Gap/Fix: Frame pacing enforcement — if minimumFrameInterval is set,
        // skip re-rendering when called too soon after the previous render.
        if let interval = minimumFrameInterval, timestamp > 0, lastRenderTime > 0 {
            let elapsed = timestamp - lastRenderTime
            if elapsed < interval, let cachedFrame {
                return cachedFrame
            }
        }

        updateResolvedLayout()

        var commands: [RenderCommand] = []
        root.appendCommands(into: &commands, parentOrigin: .zero, inheritedClip: nil, inheritedOpacity: 1.0)

        let frame = RenderFrame(clearColor: clearColor, commands: commands)
        cachedFrame = frame
        dirtyFlags = []
        if timestamp > 0 {
            lastRenderTime = timestamp
        }
        return frame
    }

    /// Render the current view tree as a GPUIScene for batch rendering.
    public func renderScene(at timestamp: Double = 0) -> GPUIScene {
        let frame = renderFrame(at: timestamp)
        return GPUIScene(from: frame, surfaceSize: root.frame.size)
    }

    public func pointerMoved(to point: Point) {
        if let dragState = scrollDragState {
            guard let node = dragState.node else {
                scrollDragState = nil
                updateScrollIndicatorHover(to: nil)
                return
            }

            let delta = dragState.axis == .vertical ? point.y - dragState.startPoint.y : point.x - dragState.startPoint.x
            _ = node.applyScrollIndicatorDrag(startOffset: dragState.startOffset, delta: delta, travel: dragState.track.travel)
            updateScrollIndicatorHover(to: ScrollIndicatorHit(node: node, track: dragState.track))
            return
        }

        if let dragState = nodeDragState {
            guard let node = dragState.node else {
                nodeDragState = nil
                return
            }

            let delta = Point(x: point.x - dragState.startPoint.x, y: point.y - dragState.startPoint.y)
            node.onDragChange?(point, delta)
            return
        }

        updateHoverTarget(to: hitTest(at: point))
        updateScrollIndicatorHover(to: scrollIndicatorHit(at: point))
    }

    public func pointerExitedWindow() {
        updateHoverTarget(to: nil)
        if scrollDragState == nil {
            updateScrollIndicatorHover(to: nil)
        }
    }

    public func mouseWheel(at point: Point, delta: Double) {
        let scrollTarget = scrollTarget(at: point) ?? nearestScrollableNode(from: hoveredNode)
        guard let scrollableNode = scrollTarget else {
            return
        }

        if scrollableNode.applyMouseWheelDelta(delta) {
            updateHoverTarget(to: hitTest(at: point))
        }
    }

    public func pointerDown(at point: Point) {
        if let scrollIndicatorHit = scrollIndicatorHit(at: point) {
            scrollDragState = ScrollDragState(node: scrollIndicatorHit.node, axis: scrollIndicatorHit.track.axis, startPoint: point, startOffset: scrollIndicatorHit.node.scrollOffset, track: scrollIndicatorHit.track)
            activeScrollIndicatorNode = scrollIndicatorHit.node
            animateColor(.scrollIndicator, of: scrollIndicatorHit.node, to: scrollIndicatorHit.node.scrollIndicatorActiveColor, duration: 0.10, at: Win32Window.currentTimestampSeconds())
            return
        }

        let hitNode = hitTest(at: point)
        if let draggableNode = nearestDraggableNode(from: hitNode) {
            nodeDragState = NodeDragState(node: draggableNode, startPoint: point)
            draggableNode.onDragStart?(point)
            updateHoverTarget(to: hitNode)
            return
        }

        updateFocusTarget(to: nearestFocusableNode(from: hitNode))
        updateHoverTarget(to: hitNode)
        pressedNode = hitNode
        hitNode?.onPointerDown?()
    }

    public func pointerUp(at point: Point) {
        if let dragState = scrollDragState {
            scrollDragState = nil
            activeScrollIndicatorNode = nil
            let nextIndicatorHit = scrollIndicatorHit(at: point)
            updateScrollIndicatorHover(to: nextIndicatorHit)

            if let node = dragState.node {
                let targetColor = nextIndicatorHit?.node === node ? node.scrollIndicatorHoverColor : node.scrollIndicatorIdleColor
                animateColor(.scrollIndicator, of: node, to: targetColor, duration: 0.12, at: Win32Window.currentTimestampSeconds())
            }
            return
        }

        if let dragState = nodeDragState {
            nodeDragState = nil
            if let node = dragState.node {
                let delta = Point(x: point.x - dragState.startPoint.x, y: point.y - dragState.startPoint.y)
                node.onDragEnd?(point, delta)
            }
            updateHoverTarget(to: hitTest(at: point))
            updateScrollIndicatorHover(to: scrollIndicatorHit(at: point))
            return
        }

        let hitNode = hitTest(at: point)

        if let pressedNode {
            if pressedNode === hitNode {
                pressedNode.onPointerUpInside?()
                pressedNode.onActivate?()
            } else {
                pressedNode.onPointerUpOutside?()
            }
        }

        self.pressedNode = nil
        updateHoverTarget(to: hitNode)
    }

    public func keyDown(_ event: KeyboardEvent) {
        switch event.key {
        case .tab:
            moveFocus(reverse: event.modifiers.contains(.shift))
            return

        case .enter, .space:
            focusedNode?.onActivate?()

        case .escape:
            updateFocusTarget(to: nil)
            return

        default:
            break
        }

        if let key = event.key, handleScrollKey(key) {
            return
        }

        focusedNode?.onKeyDown?(event)
    }

    public func textInput(_ text: String) {
        focusedNode?.onTextInput?(text)
    }

    public func keyboardFocusDidLeaveWindow() {
        updateFocusTarget(to: nil)
    }

    public func animateBackgroundColor(of node: ViewNode, to targetColor: Color, duration: Double = 0.18, at timestamp: Double) {
        animateColor(.background, of: node, to: targetColor, duration: duration, at: timestamp)
    }

    public func animateColor(_ property: AnimatedColorProperty, of node: ViewNode, to targetColor: Color, duration: Double = 0.18, at timestamp: Double) {
        let animationKey = ColorAnimationKey(node: node, property: property)
        let startingColor = node.color(for: property)

        guard duration > 0, startingColor != targetColor else {
            colorAnimations.removeValue(forKey: animationKey)
            node.setColor(targetColor, for: property)
            return
        }

        colorAnimations[animationKey] = ViewColorAnimation(
            node: node,
            property: property,
            startColor: startingColor,
            endColor: targetColor,
            startTime: timestamp,
            duration: duration
        )
        invalidate()
    }

    @discardableResult
    public func tickAnimations(at timestamp: Double) -> Bool {
        guard !colorAnimations.isEmpty else {
            return false
        }

        var didUpdateAnyAnimation = false

        for animationKey in Array(colorAnimations.keys) {
            guard let animation = colorAnimations[animationKey] else {
                continue
            }

            guard let node = animation.node else {
                colorAnimations.removeValue(forKey: animationKey)
                continue
            }

            let progress = animation.progress(at: timestamp)
            let nextColor = animation.startColor.interpolated(to: animation.endColor, progress: progress)
            if node.color(for: animation.property) != nextColor {
                node.setColor(nextColor, for: animation.property)
                didUpdateAnyAnimation = true
            }

            if progress >= 1 {
                colorAnimations.removeValue(forKey: animationKey)
            }
        }

        return didUpdateAnyAnimation
    }

    fileprivate func invalidate(_ flags: DirtyFlags = .all) {
        dirtyFlags.insert(flags)
    }

    private func hitTest(at point: Point) -> ViewNode? {
        updateResolvedLayout()
        return root.hitTest(at: point, parentOrigin: .zero, inheritedClip: nil)
    }

    private func scrollTarget(at point: Point) -> ViewNode? {
        updateResolvedLayout()
        return root.scrollTarget(at: point, parentOrigin: .zero, inheritedClip: nil)
    }

    private func scrollIndicatorHit(at point: Point) -> ScrollIndicatorHit? {
        updateResolvedLayout()
        return root.scrollIndicatorHit(at: point, parentOrigin: .zero, inheritedClip: nil)
    }

    private func moveFocus(reverse: Bool) {
        let focusableNodes = focusableNodes(in: root)
        guard !focusableNodes.isEmpty else {
            return
        }

        guard let focusedNode, let index = focusableNodes.firstIndex(where: { $0 === focusedNode }) else {
            updateFocusTarget(to: reverse ? focusableNodes.last : focusableNodes.first)
            return
        }

        let nextIndex: Int
        if reverse {
            nextIndex = index == 0 ? focusableNodes.count - 1 : index - 1
        } else {
            nextIndex = index == focusableNodes.count - 1 ? 0 : index + 1
        }

        updateFocusTarget(to: focusableNodes[nextIndex])
    }

    private func focusableNodes(in node: ViewNode) -> [ViewNode] {
        if node.isHidden {
            return []
        }

        var result: [ViewNode] = []
        if node.isFocusable {
            result.append(node)
        }

        for child in node.children {
            result.append(contentsOf: focusableNodes(in: child))
        }

        return result
    }

    private func nearestFocusableNode(from node: ViewNode?) -> ViewNode? {
        var currentNode = node
        while let candidate = currentNode {
            if candidate.isFocusable {
                return candidate
            }

            currentNode = candidate.parent
        }

        return nil
    }

    private func nearestScrollableNode(from node: ViewNode?) -> ViewNode? {
        var currentNode = node
        while let candidate = currentNode {
            if candidate.isScrollable {
                return candidate
            }

            currentNode = candidate.parent
        }

        return nil
    }

    private func nearestDraggableNode(from node: ViewNode?) -> ViewNode? {
        var currentNode = node
        while let candidate = currentNode {
            if candidate.isDraggable {
                return candidate
            }

            currentNode = candidate.parent
        }

        return nil
    }

    private func handleScrollKey(_ key: KeyboardKey) -> Bool {
        let scrollableNode = nearestScrollableNode(from: focusedNode) ?? nearestScrollableNode(from: hoveredNode)
        guard let scrollableNode else {
            return false
        }

        return scrollableNode.applyKeyboardScroll(key)
    }

    private func updateResolvedLayout() {
        root.resolvedFrame = root.frame
        root.layoutSubtree()
    }

    private func updateHoverTarget(to nextHoveredNode: ViewNode?) {
        guard hoveredNode !== nextHoveredNode else {
            return
        }

        hoveredNode?.onPointerExit?()
        hoveredNode = nextHoveredNode
        hoveredNode?.onPointerEnter?()
    }

    private func updateScrollIndicatorHover(to nextIndicatorHit: ScrollIndicatorHit?) {
        let nextNode = nextIndicatorHit?.node
        guard hoveredScrollIndicatorNode !== nextNode else {
            return
        }

        if let previousNode = hoveredScrollIndicatorNode, previousNode !== activeScrollIndicatorNode {
            animateColor(
                .scrollIndicator,
                of: previousNode,
                to: previousNode.scrollIndicatorIdleColor,
                duration: 0.12,
                at: Win32Window.currentTimestampSeconds()
            )
        }

        hoveredScrollIndicatorNode = nextNode

        if let nextNode, nextNode !== activeScrollIndicatorNode {
            animateColor(
                .scrollIndicator,
                of: nextNode,
                to: nextNode.scrollIndicatorHoverColor,
                duration: 0.12,
                at: Win32Window.currentTimestampSeconds()
            )
        }
    }

    private func updateFocusTarget(to nextFocusedNode: ViewNode?) {
        guard focusedNode !== nextFocusedNode else {
            return
        }

        focusedNode?.onFocusExit?()
        focusedNode = nextFocusedNode
        focusedNode?.onFocusEnter?()
        invalidate()
    }
}

private struct ScrollIndicatorTrack {
    let axis: ScrollAxis
    let origin: Double
    let travel: Double
    let indicatorRect: Rect
}

private struct ScrollIndicatorHit {
    unowned let node: ViewNode
    let track: ScrollIndicatorTrack
}

private struct ScrollDragState {
    weak var node: ViewNode?
    let axis: ScrollAxis
    let startPoint: Point
    let startOffset: Double
    let track: ScrollIndicatorTrack
}

private struct NodeDragState {
    weak var node: ViewNode?
    let startPoint: Point
}

public enum AnimatedColorProperty: Hashable, Sendable {
    case background
    case border
    case outline
    case shadow
    case scrollIndicator
}

private struct ColorAnimationKey: Hashable {
    let nodeIdentifier: ObjectIdentifier
    let property: AnimatedColorProperty

    init(node: ViewNode, property: AnimatedColorProperty) {
        self.nodeIdentifier = ObjectIdentifier(node)
        self.property = property
    }
}

private final class ViewColorAnimation {
    weak var node: ViewNode?
    let property: AnimatedColorProperty
    let startColor: Color
    let endColor: Color
    let startTime: Double
    let duration: Double

    init(node: ViewNode, property: AnimatedColorProperty, startColor: Color, endColor: Color, startTime: Double, duration: Double) {
        self.node = node
        self.property = property
        self.startColor = startColor
        self.endColor = endColor
        self.startTime = startTime
        self.duration = duration
    }

    func progress(at timestamp: Double) -> Double {
        let elapsed = timestamp - startTime
        guard duration > 0 else {
            return 1
        }

        return min(max(elapsed / duration, 0), 1)
    }
}

private func baseClipAllowsDrawing(baseClip: Rect?, rect: Rect) -> Bool {
    baseClip?.intersected(with: rect) != nil || baseClip == nil
}

private func clampedOpacity(_ opacity: Double) -> Double {
    min(max(opacity, 0), 1)
}

private func applyingOpacity(_ opacity: Double, to color: Color) -> Color {
    Color(
        red: color.red,
        green: color.green,
        blue: color.blue,
        alpha: color.alpha * Float(clampedOpacity(opacity))
    )
}

private func applyingOpacity(_ opacity: Double, to gradient: LinearGradient) -> LinearGradient {
    var gradient = gradient
    gradient.stops = gradient.stops.map { stop in
        GradientStop(color: applyingOpacity(opacity, to: stop.color), position: stop.position)
    }
    return gradient
}

private func applyingOpacity(_ opacity: Double, to gradient: GradientType?) -> GradientType? {
    guard let gradient else {
        return nil
    }

    switch gradient {
    case .linear(let linear):
        return .linear(applyingOpacity(opacity, to: linear))
    case .radial(var radial):
        radial.stops = radial.stops.map { stop in
            GradientStop(color: applyingOpacity(opacity, to: stop.color), position: stop.position)
        }
        return .radial(radial)
    case .conic(var conic):
        conic.stops = conic.stops.map { stop in
            GradientStop(color: applyingOpacity(opacity, to: stop.color), position: stop.position)
        }
        return .conic(conic)
    }
}

private func applyOpacity(to commands: inout [RenderCommand], from startIndex: Int, opacity: Double) {
    let opacity = clampedOpacity(opacity)
    guard opacity < 1, startIndex < commands.count else {
        return
    }

    for index in startIndex..<commands.count {
        commands[index] = renderCommand(commands[index], applyingOpacity: opacity)
    }
}

private func renderCommand(_ command: RenderCommand, applyingOpacity opacity: Double) -> RenderCommand {
    switch command {
    case .fillRect(var fillRect):
        fillRect.color = applyingOpacity(opacity, to: fillRect.color)
        fillRect.gradient = applyingOpacity(opacity, to: fillRect.gradient)
        return .fillRect(fillRect)
    case .drawBitmap(var drawBitmap):
        drawBitmap.opacity *= Float(clampedOpacity(opacity))
        return .drawBitmap(drawBitmap)
    case .fillPath(var fillPath):
        fillPath.color = applyingOpacity(opacity, to: fillPath.color)
        fillPath.gradient = applyingOpacity(opacity, to: fillPath.gradient)
        return .fillPath(fillPath)
    case .strokePath(var strokePath):
        strokePath.color = applyingOpacity(opacity, to: strokePath.color)
        return .strokePath(strokePath)
    case .drawText(var drawText):
        drawText.color = applyingOpacity(opacity, to: drawText.color)
        return .drawText(drawText)
    case .applyBlur, .pushClip, .popClip:
        return command
    }
}

// MARK: - Animation interpolation support

/// Properties that can be animated via the `animation()` view modifier.
public enum AnimatableProperty: Hashable, Sendable {
    case opacity
    case backgroundColor
}

/// Tracks the interpolation state for a single animated property change.
public struct AnimationState {
    public var startValue: Double
    public var endValue: Double
    public var startTime: Double
    public var duration: Double
    public var easing: AnimationEasing

    public init(startValue: Double, endValue: Double, startTime: Double, duration: Double, easing: AnimationEasing = .easeInOut) {
        self.startValue = startValue
        self.endValue = endValue
        self.startTime = startTime
        self.duration = duration
        self.easing = easing
    }

    /// Returns the interpolated value at the given timestamp.
    public func interpolatedValue(at timestamp: Double) -> Double {
        let elapsed = timestamp - startTime
        guard duration > 0 else {
            return endValue
        }

        let linearProgress = min(max(elapsed / duration, 0), 1)
        let easedProgress = easing.apply(linearProgress)
        return startValue + (endValue - startValue) * easedProgress
    }

    /// Whether the animation has completed at the given timestamp.
    public func isComplete(at timestamp: Double) -> Bool {
        (timestamp - startTime) >= duration
    }
}

/// Easing functions for animation interpolation.
public enum AnimationEasing: Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return t * (2 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        }
    }
}

/// Color-based animation state for interpolating between two colors over time.
public struct ColorAnimationState {
    public var startColor: Color
    public var endColor: Color
    public var startTime: Double
    public var duration: Double
    public var easing: AnimationEasing

    public init(startColor: Color, endColor: Color, startTime: Double, duration: Double, easing: AnimationEasing = .easeInOut) {
        self.startColor = startColor
        self.endColor = endColor
        self.startTime = startTime
        self.duration = duration
        self.easing = easing
    }

    public func interpolatedColor(at timestamp: Double) -> Color {
        let elapsed = timestamp - startTime
        guard duration > 0 else {
            return endColor
        }

        let linearProgress = min(max(elapsed / duration, 0), 1)
        let easedProgress = easing.apply(linearProgress)
        return startColor.interpolated(to: endColor, progress: easedProgress)
    }

    public func isComplete(at timestamp: Double) -> Bool {
        (timestamp - startTime) >= duration
    }
}

/// Snapshot of property values used by the animation system to track previous
/// state so it can interpolate between old and new values.
public struct PropertySnapshot {
    public var opacity: Double?
    public var backgroundColor: Color?

    public init(opacity: Double? = nil, backgroundColor: Color? = nil) {
        self.opacity = opacity
        self.backgroundColor = backgroundColor
    }
}
