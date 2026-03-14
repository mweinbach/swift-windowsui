import SwiftWindowsCore

@MainActor
/// Consumes renderer-neutral frames emitted by shared UI/runtime code.
public protocol RenderBackend: AnyObject {
    func attach(to surface: SurfaceDescriptor) throws
    func resize(to size: IntSize) throws
    func render(frame: RenderFrame) throws
}

/// Backend-neutral display list for a single frame.
public struct RenderFrame: Equatable, Sendable {
    public var clearColor: Color
    /// Ordered drawing commands produced by shared layout and view logic.
    public var commands: [RenderCommand]

    public init(clearColor: Color = .black, commands: [RenderCommand] = []) {
        self.clearColor = clearColor
        self.commands = commands
    }
}

/// Backend-neutral drawing commands. Future backends should interpret this
/// list rather than requiring shared UI code to branch on renderer type.
public enum RenderCommand: Equatable, Sendable {
    case fillRect(FillRectCommand)
}

/// Shared solid-fill primitive used by all current renderers.
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
