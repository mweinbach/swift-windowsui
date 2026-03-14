import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout

public enum ViewLayoutMode: Sendable {
    case absolute
    case stack(StackLayout)
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

    public private(set) weak var parent: ViewNode?
    public private(set) var children: [ViewNode]

    fileprivate weak var runtime: RetainedViewRuntime?
    fileprivate var resolvedFrame: Rect

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
        self.children = []
        self.resolvedFrame = frame

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
            for child in children {
                let size = child.intrinsicContentSize()
                let resolvedSize = Size(
                    width: child.frame.size.width > 0 ? child.frame.size.width : size.width,
                    height: child.frame.size.height > 0 ? child.frame.size.height : size.height
                )
                child.resolvedFrame = Rect(origin: child.frame.origin, size: resolvedSize)
                child.layoutSubtree()
            }

        case .stack(let stackLayout):
            let contentRect = resolvedFrame.inset(by: stackLayout.padding)
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
        }
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
            PixelFont.appendCommands(
                for: text,
                in: fillRect,
                style: textStyle,
                clipRect: effectiveClip,
                into: &commands
            )
        }

        for child in children {
            child.appendCommands(into: &commands, parentOrigin: absoluteOrigin, inheritedClip: effectiveClip)
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

        for child in children.reversed() {
            if let hitNode = child.hitTest(at: point, parentOrigin: absoluteOrigin, inheritedClip: effectiveClip) {
                return hitNode
            }
        }

        if isHitTestVisible, absoluteFrame.contains(point) {
            return self
        }

        return nil
    }

    private func invalidateRuntime() {
        runtime?.invalidate()
    }

    fileprivate func intrinsicContentSize() -> Size {
        if let preferredSize {
            return preferredSize
        }

        if let text, !text.isEmpty {
            return PixelFont.measure(text, style: textStyle)
        }

        return frame.size
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
        }
    }
}

@MainActor
public final class RetainedViewRuntime {
    public let root: ViewNode

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
    private var colorAnimations: [ColorAnimationKey: ViewColorAnimation] = [:]

    public init(clearColor: Color = .black, root: ViewNode = ViewNode()) {
        self.clearColor = clearColor
        self.root = root
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
        updateHoverTarget(to: hitTest(at: point))
    }

    public func pointerExitedWindow() {
        updateHoverTarget(to: nil)
    }

    public func pointerDown(at point: Point) {
        let hitNode = hitTest(at: point)
        updateFocusTarget(to: nearestFocusableNode(from: hitNode))
        updateHoverTarget(to: hitNode)
        pressedNode = hitNode
        hitNode?.onPointerDown?()
    }

    public func pointerUp(at point: Point) {
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

public enum AnimatedColorProperty: Hashable, Sendable {
    case background
    case border
    case outline
    case shadow
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
