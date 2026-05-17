import SwiftWindowsCore

import SwiftWindowsGraphics

public struct Scene: Equatable, Sendable {
    public var clearColor: Color
    public var nodes: [SceneNode]

    public init(clearColor: Color = .black, nodes: [SceneNode] = []) {
        self.clearColor = clearColor
        self.nodes = nodes
    }

    public var frame: RenderFrame {
        RenderFrame(clearColor: clearColor, commands: nodes.map(\.renderCommand))
    }
}
public enum SceneNode: Equatable, Sendable {
    case solidRect(SolidRectNode)

    fileprivate var renderCommand: RenderCommand {
        switch self {
        case .solidRect(let node):
            return .fillRect(
                FillRectCommand(
                    rect: node.rect,
                    color: node.color,
                    cornerRadius: node.cornerRadius
                )
            )
        }
    }
}
public struct SolidRectNode: Equatable, Sendable {
    public var rect: Rect
    public var color: Color
    public var cornerRadius: Double

    public init(rect: Rect, color: Color, cornerRadius: Double = 0) {
        self.rect = rect
        self.color = color
        self.cornerRadius = cornerRadius
    }
}
