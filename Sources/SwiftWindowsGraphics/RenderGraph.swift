import Foundation
import SwiftWindowsCore

@MainActor
/// Consumes renderer-neutral frames emitted by shared UI/runtime code.
public protocol RenderBackend: AnyObject {
    var backendDisplayName: String { get }
    var backendStatusDescription: String { get }

    func attach(to surface: SurfaceDescriptor) throws
    func resize(to size: IntSize) throws
    func render(frame: RenderFrame) throws
}

public extension RenderBackend {
    var backendDisplayName: String { "2D RENDERER" }

    var backendStatusDescription: String { "\(backendDisplayName) READY" }
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

// MARK: - Render Commands

/// Backend-neutral drawing commands. Future backends should interpret this
/// list rather than requiring shared UI code to branch on renderer type.
///
/// The active demo path currently renders `fillRect` and `drawBitmap`.
/// Additional cases exist so the shared contract can grow toward the typed
/// scene/batch pipeline, but renderers must opt into them explicitly instead
/// of silently dropping them.
public enum RenderCommand: Equatable, Sendable {
    case fillRect(FillRectCommand)
    /// Renderer-neutral soft shadow primitive. Backends without a native
    /// shadow path may conservatively lower it to an expanded fill rect.
    case shadowRect(ShadowRectCommand)
    case drawBitmap(DrawBitmapCommand)
    /// Reserved for backends that support vector path fills.
    case fillPath(FillPathCommand)
    /// Reserved for backends that support stroked vector paths.
    case strokePath(StrokePathCommand)
    /// Reserved for backends that support post-process blur.
    case applyBlur(BlurCommand)
    /// Reserved for first-class text rendering paths.
    case drawText(DrawTextCommand)
    /// Reserved for backends with clip-stack support.
    case pushClip(ClipCommand)
    /// Reserved for backends with clip-stack support.
    case popClip
}

// MARK: - Blend Mode (Gap 4 fix)

/// Gap 4: no per-command blend control existed. Fix: BlendMode enum lets
/// each drawing command specify its compositing operation.
public enum BlendMode: Equatable, Sendable {
    case normal
    case multiply
    case screen
    case overlay
    case additive
}

// MARK: - Gradient Types (Gaps 2 & 3 fix)

/// A single color stop within a gradient. Position is in 0...1.
///
/// Gap 3: the old LinearGradient had only startColor/endColor (2 stops).
/// Fix: gradients now carry an unlimited array of GradientStop values.
public struct GradientStop: Equatable, Sendable {
    public var color: Color
    /// Normalized position along the gradient axis, 0...1.
    public var position: Float

    public init(color: Color, position: Float) {
        self.color = color
        self.position = position
    }
}

public enum GradientAxis: Equatable, Sendable {
    case vertical
    case horizontal
}

/// Linear gradient with unlimited color stops.
///
/// Gap 3 fix: replaces the old 2-stop startColor/endColor design.
/// Backends that only support 2 stops can fall back to first/last.
public struct LinearGradient: Equatable, Sendable {
    public var stops: [GradientStop]
    public var axis: GradientAxis

    /// Full-control initializer with arbitrary stops.
    public init(stops: [GradientStop], axis: GradientAxis = .vertical) {
        self.stops = stops
        self.axis = axis
    }

    /// Convenience: 2-stop gradient matching the original API.
    public init(startColor: Color, endColor: Color, axis: GradientAxis = .vertical) {
        self.stops = [
            GradientStop(color: startColor, position: 0),
            GradientStop(color: endColor, position: 1),
        ]
        self.axis = axis
    }

    // MARK: Legacy accessors (keep existing call-sites compiling)

    /// First stop color, or .clear if stops is empty.
    public var startColor: Color {
        get { stops.first?.color ?? .clear }
        set {
            if stops.isEmpty {
                stops = [GradientStop(color: newValue, position: 0)]
            } else {
                stops[0].color = newValue
            }
        }
    }

    /// Last stop color, or .clear if stops is empty.
    public var endColor: Color {
        get { stops.last?.color ?? .clear }
        set {
            if stops.count < 2 {
                stops.append(GradientStop(color: newValue, position: 1))
            } else {
                stops[stops.count - 1].color = newValue
            }
        }
    }
}

/// Gap 2 fix: radial gradient radiating from a center point.
public struct RadialGradient: Equatable, Sendable {
    public var center: Point
    public var radius: Double
    public var stops: [GradientStop]

    public init(center: Point, radius: Double, stops: [GradientStop]) {
        self.center = center
        self.radius = radius
        self.stops = stops
    }
}

/// Gap 2 fix: conic (angular/sweep) gradient around a center point.
public struct ConicGradient: Equatable, Sendable {
    public var center: Point
    /// Starting angle in radians, measured clockwise from 12-o'clock.
    public var angle: Double
    public var stops: [GradientStop]

    public init(center: Point, angle: Double = 0, stops: [GradientStop]) {
        self.center = center
        self.angle = angle
        self.stops = stops
    }
}

/// Gap 2 fix: unified gradient type covering linear, radial, and conic.
public enum GradientType: Equatable, Sendable {
    case linear(LinearGradient)
    case radial(RadialGradient)
    case conic(ConicGradient)
}

// MARK: - Render Path (Gap 1 fix)

/// Renderer-neutral path representation. Mirrors common path segment types
/// so that RenderGraph stays independent of any platform path API.
///
/// Gap 1: no path primitives existed in the render graph. Fix: RenderPath
/// captures move/line/quad/cubic/close segments that backends translate to
/// their native path types (e.g. ID2D1PathGeometry on Direct2D).
public struct RenderPath: Equatable, Sendable {
    public enum Segment: Equatable, Sendable {
        case moveTo(Point)
        case lineTo(Point)
        case quadCurveTo(control: Point, end: Point)
        case cubicCurveTo(control1: Point, control2: Point, end: Point)
        case close
    }

    public var segments: [Segment]

    public init(segments: [Segment] = []) {
        self.segments = segments
    }

    // MARK: Builder helpers

    public mutating func move(to point: Point) {
        segments.append(.moveTo(point))
    }

    public mutating func addLine(to point: Point) {
        segments.append(.lineTo(point))
    }

    public mutating func addQuadCurve(to end: Point, control: Point) {
        segments.append(.quadCurveTo(control: control, end: end))
    }

    public mutating func addCubicCurve(to end: Point, control1: Point, control2: Point) {
        segments.append(.cubicCurveTo(control1: control1, control2: control2, end: end))
    }

    public mutating func close() {
        segments.append(.close)
    }
}

// MARK: - Stroke Style (Gap 8 fix)

/// Gap 8: stroke style only supported named presets; no dash pattern data.
/// Fix: StrokeStyle carries a full dash array and dash offset so backends
/// can render arbitrary dash patterns.
public struct StrokeStyle: Equatable, Sendable {
    public var lineWidth: Double
    /// Dash pattern as alternating on/off lengths (e.g. [6, 2, 2, 2]).
    /// Empty array means a solid stroke.
    public var dashPattern: [Double]
    /// Offset into the dash pattern at which the stroke begins.
    public var dashOffset: Double
    public var lineCap: LineCap
    public var lineJoin: LineJoin

    public init(
        lineWidth: Double = 1,
        dashPattern: [Double] = [],
        dashOffset: Double = 0,
        lineCap: LineCap = .butt,
        lineJoin: LineJoin = .miter
    ) {
        self.lineWidth = lineWidth
        self.dashPattern = dashPattern
        self.dashOffset = dashOffset
        self.lineCap = lineCap
        self.lineJoin = lineJoin
    }

    public enum LineCap: Equatable, Sendable {
        case butt
        case round
        case square
    }

    public enum LineJoin: Equatable, Sendable {
        case miter
        case round
        case bevel
    }
}

// MARK: - Clip Shapes (Gap 5 fix)

/// Gap 5: clipping only supported axis-aligned rects via clipRect on each
/// command. Fix: ClipShape supports rects, ellipses, and arbitrary paths.
public enum ClipShape: Equatable, Sendable {
    case rect(Rect, cornerRadius: Double)
    case ellipse(center: Point, radiusX: Double, radiusY: Double)
    case path(RenderPath)
}

/// Controls how a new clip interacts with the existing clip region.
public enum ClipOperation: Equatable, Sendable {
    /// Intersect with the current clip (default, most common).
    case intersect
    /// Replace the current clip entirely.
    case replace
}

// MARK: - Command Structs

/// Shared solid-fill / gradient-fill rect primitive used by all renderers.
///
/// Gap 2 fix: `gradient` field widened from `LinearGradient?` to
/// `GradientType?` so radial and conic fills are representable.
/// Gap 4 fix: optional `blendMode` added.
public struct FillRectCommand: Equatable, Sendable {
    public var rect: Rect
    public var color: Color
    public var cornerRadius: Double
    public var clipRect: Rect?
    public var gradient: GradientType?
    /// Gap 4 fix: per-command blend mode, defaults to .normal.
    public var blendMode: BlendMode

    public init(
        rect: Rect,
        color: Color,
        cornerRadius: Double = 0,
        clipRect: Rect? = nil,
        gradient: GradientType? = nil,
        blendMode: BlendMode = .normal
    ) {
        self.rect = rect
        self.color = color
        self.cornerRadius = cornerRadius
        self.clipRect = clipRect
        self.gradient = gradient
        self.blendMode = blendMode
    }

    /// Convenience initializer preserving the original LinearGradient? API.
    public init(
        rect: Rect,
        color: Color,
        cornerRadius: Double = 0,
        clipRect: Rect? = nil,
        gradient: LinearGradient?,
        blendMode: BlendMode = .normal
    ) {
        self.rect = rect
        self.color = color
        self.cornerRadius = cornerRadius
        self.clipRect = clipRect
        self.gradient = gradient.map { .linear($0) }
        self.blendMode = blendMode
    }
}

/// Shared soft-shadow rectangle primitive used by retained chrome and batch
/// renderers.
public struct ShadowRectCommand: Equatable, Sendable {
    public var rect: Rect
    public var color: Color
    public var cornerRadius: Double
    public var blurRadius: Double
    public var offset: Point
    public var clipRect: Rect?
    public var blendMode: BlendMode

    public init(
        rect: Rect,
        color: Color,
        cornerRadius: Double = 0,
        blurRadius: Double = 0,
        offset: Point = .zero,
        clipRect: Rect? = nil,
        blendMode: BlendMode = .normal
    ) {
        self.rect = rect
        self.color = color
        self.cornerRadius = cornerRadius
        self.blurRadius = blurRadius
        self.offset = offset
        self.clipRect = clipRect
        self.blendMode = blendMode
    }

    public var fallbackFillRect: FillRectCommand {
        let spread = max(0, blurRadius)
        return FillRectCommand(
            rect: rect
                .outset(by: spread)
                .offsetBy(dx: offset.x, dy: offset.y),
            color: color,
            cornerRadius: cornerRadius + spread,
            clipRect: clipRect,
            blendMode: blendMode
        )
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

/// Gap 4 fix: optional blendMode added to DrawBitmapCommand.
public struct DrawBitmapCommand: Equatable, Sendable {
    public var rect: Rect
    public var bitmap: BitmapSurface
    public var opacity: Float
    public var clipRect: Rect?
    /// Gap 4 fix: per-command blend mode, defaults to .normal.
    public var blendMode: BlendMode

    public init(
        rect: Rect,
        bitmap: BitmapSurface,
        opacity: Float = 1.0,
        clipRect: Rect? = nil,
        blendMode: BlendMode = .normal
    ) {
        self.rect = rect
        self.bitmap = bitmap
        self.opacity = opacity
        self.clipRect = clipRect
        self.blendMode = blendMode
    }
}

/// Gap 1 fix: fill an arbitrary path with a solid color or gradient.
public struct FillPathCommand: Equatable, Sendable {
    public var path: RenderPath
    public var color: Color
    public var gradient: GradientType?
    public var transform: AffineTransform
    public var blendMode: BlendMode

    public init(
        path: RenderPath,
        color: Color,
        gradient: GradientType? = nil,
        transform: AffineTransform = .identity,
        blendMode: BlendMode = .normal
    ) {
        self.path = path
        self.color = color
        self.gradient = gradient
        self.transform = transform
        self.blendMode = blendMode
    }
}

/// Gap 1 fix: stroke an arbitrary path with configurable style.
public struct StrokePathCommand: Equatable, Sendable {
    public var path: RenderPath
    public var color: Color
    public var style: StrokeStyle
    public var transform: AffineTransform
    public var blendMode: BlendMode

    public init(
        path: RenderPath,
        color: Color,
        style: StrokeStyle = StrokeStyle(),
        transform: AffineTransform = .identity,
        blendMode: BlendMode = .normal
    ) {
        self.path = path
        self.color = color
        self.style = style
        self.transform = transform
        self.blendMode = blendMode
    }
}

/// Simple 2D affine transform for path commands.
public struct AffineTransform: Equatable, Sendable {
    public var a: Double, b: Double
    public var c: Double, d: Double
    public var tx: Double, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = AffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(x: Double, y: Double) -> AffineTransform {
        AffineTransform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func scale(x: Double, y: Double) -> AffineTransform {
        AffineTransform(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }
}

/// Gap 6 fix: Gaussian blur applied to a rectangular region.
public struct BlurCommand: Equatable, Sendable {
    /// The region to blur in logical coordinates.
    public var region: Rect
    /// Blur radius in logical points.
    public var radius: Double

    public init(region: Rect, radius: Double) {
        self.region = region
        self.radius = radius
    }
}

/// First-class text drawing command reserved for renderer paths that can own
/// text shaping/rasterization directly instead of relying on pre-baked bitmaps.
public struct DrawTextCommand: Equatable, Sendable {
    public var text: String
    public var position: Point
    public var fontName: String
    public var fontSize: Double
    public var fontWeight: FontWeight
    public var color: Color
    public var maxWidth: Double?
    public var clipRect: Rect?
    public var blendMode: BlendMode

    public init(
        text: String,
        position: Point,
        fontName: String = "Segoe UI",
        fontSize: Double = 14,
        fontWeight: FontWeight = .regular,
        color: Color = .white,
        maxWidth: Double? = nil,
        clipRect: Rect? = nil,
        blendMode: BlendMode = .normal
    ) {
        self.text = text
        self.position = position
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.color = color
        self.maxWidth = maxWidth
        self.clipRect = clipRect
        self.blendMode = blendMode
    }

    public enum FontWeight: Equatable, Sendable {
        case thin
        case light
        case regular
        case medium
        case semibold
        case bold
        case heavy
        case black
    }
}

/// Gap 5 fix: push an arbitrary clip shape onto the clip stack.
public struct ClipCommand: Equatable, Sendable {
    public var shape: ClipShape
    public var operation: ClipOperation

    public init(shape: ClipShape, operation: ClipOperation = .intersect) {
        self.shape = shape
        self.operation = operation
    }
}

/// Command to apply a Gaussian blur over a rectangular region.
public struct ApplyBlurCommand: Equatable, Sendable {
    public var rect: Rect
    public var radius: Double
    public var clipRect: Rect?

    public init(rect: Rect, radius: Double, clipRect: Rect? = nil) {
        self.rect = rect
        self.radius = radius
        self.clipRect = clipRect
    }
}
