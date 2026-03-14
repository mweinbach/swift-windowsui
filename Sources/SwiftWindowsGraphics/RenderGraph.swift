import Foundation
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
    case drawBitmap(DrawBitmapCommand)
}

public enum GradientAxis: Equatable, Sendable {
    case vertical
    case horizontal
}

public struct LinearGradient: Equatable, Sendable {
    public var startColor: Color
    public var endColor: Color
    public var axis: GradientAxis

    public init(startColor: Color, endColor: Color, axis: GradientAxis = .vertical) {
        self.startColor = startColor
        self.endColor = endColor
        self.axis = axis
    }
}

/// Shared solid-fill primitive used by all current renderers.
public struct FillRectCommand: Equatable, Sendable {
    public var rect: Rect
    public var color: Color
    public var cornerRadius: Double
    public var clipRect: Rect?
    public var gradient: LinearGradient?

    public init(rect: Rect, color: Color, cornerRadius: Double = 0, clipRect: Rect? = nil, gradient: LinearGradient? = nil) {
        self.rect = rect
        self.color = color
        self.cornerRadius = cornerRadius
        self.clipRect = clipRect
        self.gradient = gradient
    }
}

public struct BitmapSurface: Equatable, Sendable {
    public var width: Int32
    public var height: Int32
    public var bytesPerRow: Int32
    public var pixels: Data

    public init(width: Int32, height: Int32, bytesPerRow: Int32, pixels: Data) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }
}

public struct DrawBitmapCommand: Equatable, Sendable {
    public var rect: Rect
    public var bitmap: BitmapSurface
    public var opacity: Float
    public var clipRect: Rect?

    public init(rect: Rect, bitmap: BitmapSurface, opacity: Float = 1.0, clipRect: Rect? = nil) {
        self.rect = rect
        self.bitmap = bitmap
        self.opacity = opacity
        self.clipRect = clipRect
    }
}
