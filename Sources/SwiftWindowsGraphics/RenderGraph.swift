import SwiftWindowsCore

@MainActor
public protocol RenderBackend: AnyObject {
    func attach(to surface: SurfaceDescriptor) throws
    func resize(to size: IntSize) throws
    func render(frame: RenderFrame) throws
}

public struct RenderFrame: Equatable, Sendable {
    public var clearColor: Color
    public var commands: [RenderCommand]

    public init(clearColor: Color = .black, commands: [RenderCommand] = []) {
        self.clearColor = clearColor
        self.commands = commands
    }
}

public enum RenderCommand: Equatable, Sendable {
    case fillRect(FillRectCommand)
}

public struct FillRectCommand: Equatable, Sendable {
    public var rect: Rect
    public var color: Color
    public var cornerRadius: Double
    public var clipRect: Rect?

    public init(rect: Rect, color: Color, cornerRadius: Double = 0, clipRect: Rect? = nil) {
        self.rect = rect
        self.color = color
        self.cornerRadius = cornerRadius
        self.clipRect = clipRect
    }
}
