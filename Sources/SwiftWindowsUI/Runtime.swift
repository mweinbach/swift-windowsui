import SwiftWindowsCore
import SwiftWindowsGraphics

@MainActor
public final class ViewNode {
    public var frame: Rect {
        didSet { invalidateRuntime() }
    }

    public var backgroundColor: Color? {
        didSet { invalidateRuntime() }
    }

    public var cornerRadius: Double {
        didSet { invalidateRuntime() }
    }

    public var isHidden: Bool {
        didSet { invalidateRuntime() }
    }

    public private(set) weak var parent: ViewNode?
    public private(set) var children: [ViewNode]

    fileprivate weak var runtime: RetainedViewRuntime?

    public init(
        frame: Rect = .zero,
        backgroundColor: Color? = nil,
        cornerRadius: Double = 0,
        isHidden: Bool = false,
        children: [ViewNode] = []
    ) {
        self.frame = frame
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.isHidden = isHidden
        self.children = []

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

    fileprivate func appendCommands(into commands: inout [RenderCommand], parentOrigin: Point) {
        if isHidden {
            return
        }

        let absoluteOrigin = Point(
            x: parentOrigin.x + frame.origin.x,
            y: parentOrigin.y + frame.origin.y
        )

        if let backgroundColor, backgroundColor.alpha > 0, frame.size.width > 0, frame.size.height > 0 {
            commands.append(
                .fillRect(
                    FillRectCommand(
                        rect: Rect(origin: absoluteOrigin, size: frame.size),
                        color: backgroundColor,
                        cornerRadius: cornerRadius
                    )
                )
            )
        }

        for child in children {
            child.appendCommands(into: &commands, parentOrigin: absoluteOrigin)
        }
    }

    private func invalidateRuntime() {
        runtime?.invalidate()
    }
}

@MainActor
public final class RetainedViewRuntime {
    public let root: ViewNode

    public var clearColor: Color {
        didSet { invalidate() }
    }

    public private(set) var isDirty = true
    private var cachedFrame: RenderFrame?

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

        var commands: [RenderCommand] = []
        root.appendCommands(into: &commands, parentOrigin: .zero)

        let frame = RenderFrame(clearColor: clearColor, commands: commands)
        cachedFrame = frame
        isDirty = false
        return frame
    }

    fileprivate func invalidate() {
        isDirty = true
    }
}
