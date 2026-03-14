import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsPlatform

public enum ViewLayoutMode: Sendable {
    case absolute
    case stack(StackLayout)
}

public enum ScrollAxis: Sendable {
    case horizontal
    case vertical
}

@MainActor
public final class ViewNode {
    public var frame: Rect {
        didSet { invalidateRuntime() }
    }

    public var backgroundColor: Color? {
        didSet { invalidateRuntime() }
    }

    public var text: String? {
        didSet { invalidateRuntime() }
    }

    public var textStyle: PixelTextStyle {
        didSet { invalidateRuntime() }
    }

    public var borderColor: Color {
        didSet { invalidateRuntime() }
    }

    public var borderWidth: Double {
        didSet { invalidateRuntime() }
    }

    public var outlineColor: Color {
        didSet { invalidateRuntime() }
    }

    public var outlineWidth: Double {
        didSet { invalidateRuntime() }
    }

    public var shadowColor: Color {
        didSet { invalidateRuntime() }
    }

    public var shadowOffset: Point {
        didSet { invalidateRuntime() }
    }

    public var shadowSpread: Double {
        didSet { invalidateRuntime() }
    }

    public var cornerRadius: Double {
        didSet { invalidateRuntime() }
    }

    public var clipsToBounds: Bool {
        didSet { invalidateRuntime() }
    }

    public var layoutMode: ViewLayoutMode {
        didSet { invalidateRuntime() }
    }

    public var preferredSize: Size? {
        didSet { invalidateRuntime() }
    }

    public var scrollAxis: ScrollAxis? {
        didSet { invalidateRuntime() }
    }

    public var scrollOffset: Double {
        didSet { invalidateRuntime() }
    }

    public var scrollStep: Double {
        didSet { invalidateRuntime() }
    }

    public var showsScrollIndicator: Bool {
        didSet { invalidateRuntime() }
    }

    public var scrollIndicatorColor: Color {
        didSet { invalidateRuntime() }
    }

    public var scrollIndicatorIdleColor: Color {
        didSet { invalidateRuntime() }
    }

    public var scrollIndicatorHoverColor: Color {
        didSet { invalidateRuntime() }
    }

    public var scrollIndicatorActiveColor: Color {
        didSet { invalidateRuntime() }
    }

    public var scrollIndicatorThickness: Double {
        didSet { invalidateRuntime() }
    }

    public var isFocusable: Bool {
        didSet { invalidateRuntime() }
    }

    public var isHitTestVisible: Bool {
        didSet { invalidateRuntime() }
    }

    public var isHidden: Bool {
        didSet { invalidateRuntime() }
    }

    public var onPointerEnter: (() -> Void)?
    public var onPointerExit: (() -> Void)?
    public var onPointerDown: (() -> Void)?
    public var onPointerUpInside: (() -> Void)?
    public var onPointerUpOutside: (() -> Void)?
    public var onFocusEnter: (() -> Void)?
    public var onFocusExit: (() -> Void)?
    public var onKeyDown: ((KeyboardEvent) -> Void)?
    public var onActivate: (() -> Void)?
    public var onDragStart: ((Point) -> Void)?
    public var onDragChange: ((Point, Point) -> Void)?
    public var onDragEnd: ((Point, Point) -> Void)?

    public private(set) weak var parent: ViewNode?
    public private(set) var children: [ViewNode]

    fileprivate weak var runtime: RetainedViewRuntime?
    fileprivate var resolvedFrame: Rect
    fileprivate var resolvedContentSize: Size
    fileprivate var resolvedScrollOffset: Double

    public init(
        frame: Rect = .zero,
        backgroundColor: Color? = nil,
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
        self.onActivate = nil
        self.onDragStart = nil
        self.onDragChange = nil
        self.onDragEnd = nil
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
        invalidateRuntime()
    }

    public func removeChild(_ child: ViewNode) {
        guard let index = children.firstIndex(where: { $0 === child }) else {
            return
        }

        let removed = children.remove(at: index)
        removed.parent = nil
        removed.setRuntime(nil)
        invalidateRuntime()
    }

    public func removeFromParent() {
        parent?.removeChild(self)
    }

    public func removeAllChildren() {
        for child in children {
            child.parent = nil
            child.setRuntime(nil)
        }

        children.removeAll(keepingCapacity: false)
        invalidateRuntime()
    }

    fileprivate func setRuntime(_ runtime: RetainedViewRuntime?) {
        self.runtime = runtime
        for child in children {
            child.setRuntime(runtime)
        }
    }

    fileprivate func layoutSubtree() {
        switch layoutMode {
        case .absolute:
            var maxChildX: Double = 0
            var maxChildY: Double = 0

            for child in children {
                let size = child.intrinsicContentSize()
                let resolvedSize = Size(
                    width: child.frame.size.width > 0 ? child.frame.size.width : size.width,
                    height: child.frame.size.height > 0 ? child.frame.size.height : size.height
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
            let desiredSizes = visibleChildren.map { $0.intrinsicContentSize() }

            let totalMainExtent = desiredSizes.enumerated().reduce(0.0) { partialResult, element in
                let size = element.element
                let mainSize = stackLayout.axis == .vertical ? size.height : size.width
                let spacing = element.offset == 0 ? 0 : stackLayout.spacing
                return partialResult + spacing + mainSize
            }

            let availableMainExtent = stackLayout.axis == .vertical ? contentRect.size.height : contentRect.size.width
            let mainOrigin = stackLayout.axis == .vertical ? contentRect.origin.y : contentRect.origin.x
            let mainCursorStart: Double
            switch stackLayout.mainAlignment {
            case .start:
                mainCursorStart = mainOrigin
            case .center:
                mainCursorStart = mainOrigin + max(0, (availableMainExtent - totalMainExtent) * 0.5)
            case .end:
                mainCursorStart = mainOrigin + max(0, availableMainExtent - totalMainExtent)
            }

            var mainCursor = mainCursorStart

            for child in children {
                if child.isHidden {
                    child.resolvedFrame = Rect(x: 0, y: 0, width: 0, height: 0)
                    continue
                }

                let desiredSize = child.intrinsicContentSize()
                let childFrame: Rect

                switch stackLayout.axis {
                case .vertical:
                    let width = stackLayout.alignment == .stretch ? contentRect.size.width : min(desiredSize.width, contentRect.size.width)
                    let height = min(desiredSize.height, contentRect.size.height)

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
                    mainCursor += height + stackLayout.spacing

                case .horizontal:
                    let width = min(desiredSize.width, contentRect.size.width)
                    let height = stackLayout.alignment == .stretch ? contentRect.size.height : min(desiredSize.height, contentRect.size.height)

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
                    mainCursor += width + stackLayout.spacing
                }

                child.resolvedFrame = childFrame
                child.layoutSubtree()
            }

            switch stackLayout.axis {
            case .vertical:
                resolvedContentSize = Size(
                    width: resolvedFrame.size.width,
                    height: totalMainExtent + stackLayout.padding.top + stackLayout.padding.bottom
                )
            case .horizontal:
                resolvedContentSize = Size(
                    width: totalMainExtent + stackLayout.padding.leading + stackLayout.padding.trailing,
                    height: resolvedFrame.size.height
                )
            }
        }

        resolvedScrollOffset = clampedScrollOffset(for: scrollOffset)
    }

    fileprivate func appendCommands(into commands: inout [RenderCommand], parentOrigin: Point, inheritedClip: Rect?) {
        if isHidden {
            return
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
                    return
                }

                effectiveClip = clippedRect
            } else {
                effectiveClip = absoluteFrame
            }
        }

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        if shadowColor.alpha > 0 {
            let shadowRect = absoluteFrame
                .outset(by: max(0, shadowSpread))
                .offsetBy(dx: shadowOffset.x, dy: shadowOffset.y)

            if baseClipAllowsDrawing(baseClip: inheritedClip, rect: shadowRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: shadowRect,
                            color: shadowColor,
                            cornerRadius: cornerRadius + max(0, shadowSpread),
                            clipRect: inheritedClip
                        )
                    )
                )
            }
        }

        if outlineColor.alpha > 0, outlineWidth > 0 {
            let outlineRect = absoluteFrame.outset(by: outlineWidth)
            if baseClipAllowsDrawing(baseClip: inheritedClip, rect: outlineRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: outlineRect,
                            color: outlineColor,
                            cornerRadius: cornerRadius + outlineWidth,
                            clipRect: inheritedClip
                        )
                    )
                )
            }
        }

        if borderColor.alpha > 0, borderWidth > 0, baseClipAllowsDrawing(baseClip: effectiveClip, rect: absoluteFrame) {
            commands.append(
                .fillRect(
                    FillRectCommand(
                        rect: absoluteFrame,
                        color: borderColor,
                        cornerRadius: cornerRadius,
                        clipRect: effectiveClip
                    )
                )
            )
        }

        let fillRect = borderWidth > 0 ? absoluteFrame.inset(by: borderWidth) : absoluteFrame
        let fillCornerRadius = max(0, cornerRadius - borderWidth)

        if let backgroundColor, backgroundColor.alpha > 0, fillRect.size.width > 0, fillRect.size.height > 0 {
            if baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: fillRect,
                            color: backgroundColor,
                            cornerRadius: fillCornerRadius,
                            clipRect: effectiveClip
                        )
                    )
                )
            }
        }

        if let text, !text.isEmpty, baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
            let displayScale = runtime?.displayScale ?? 1.0
            if !NativeTextRenderer.appendCommands(for: text, in: fillRect, style: textStyle, scaleFactor: displayScale, clipRect: effectiveClip, into: &commands) {
                PixelFont.appendCommands(
                    for: text,
                    in: fillRect,
                    style: textStyle,
                    clipRect: effectiveClip,
                    into: &commands
                )
            }
        }

        for child in children {
            child.appendCommands(into: &commands, parentOrigin: childOrigin, inheritedClip: effectiveClip)
        }

        if let scrollIndicator = scrollIndicatorRect(in: absoluteFrame) {
            commands.append(
                .fillRect(
                    FillRectCommand(
                        rect: scrollIndicator,
                        color: scrollIndicatorColor,
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

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        for child in children.reversed() {
            if let hitNode = child.hitTest(at: point, parentOrigin: childOrigin, inheritedClip: effectiveClip) {
                return hitNode
            }
        }

        if isHitTestVisible, absoluteFrame.contains(point) {
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

    private func invalidateRuntime() {
        runtime?.invalidate()
    }

    fileprivate func intrinsicContentSize() -> Size {
        if let preferredSize {
            return preferredSize
        }

        if let text, !text.isEmpty {
            let displayScale = runtime?.displayScale ?? 1.0
            return NativeTextRenderer.measure(text, style: textStyle, scaleFactor: displayScale) ?? PixelFont.measure(text, style: textStyle)
        }

        return frame.size
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

@MainActor
public final class RetainedViewRuntime {
    public let root: ViewNode

    public var displayScale: Double {
        didSet { invalidate() }
    }

    public var clearColor: Color {
        didSet { invalidate() }
    }

    public var hasActiveAnimations: Bool {
        !colorAnimations.isEmpty
    }

    public private(set) var isDirty = true
    private var cachedFrame: RenderFrame?
    private weak var hoveredNode: ViewNode?
    private weak var pressedNode: ViewNode?
    private weak var focusedNode: ViewNode?
    private weak var hoveredScrollIndicatorNode: ViewNode?
    private weak var activeScrollIndicatorNode: ViewNode?
    private var colorAnimations: [ColorAnimationKey: ViewColorAnimation] = [:]
    private var scrollDragState: ScrollDragState?
    private var nodeDragState: NodeDragState?

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

    public func renderFrame() -> RenderFrame {
        if let cachedFrame, !isDirty {
            return cachedFrame
        }

        updateResolvedLayout()

        var commands: [RenderCommand] = []
        root.appendCommands(into: &commands, parentOrigin: .zero, inheritedClip: nil)

        let frame = RenderFrame(clearColor: clearColor, commands: commands)
        cachedFrame = frame
        isDirty = false
        return frame
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

    fileprivate func invalidate() {
        isDirty = true
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
