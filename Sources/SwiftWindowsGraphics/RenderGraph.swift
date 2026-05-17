import Foundation

import SwiftWindowsCore

/// Backend-neutral display list for a single frame.

// MARK: - Render Commands

/// Backend-neutral drawing commands. Future backends should interpret this
/// list rather than requiring shared UI code to branch on renderer type.
///
/// The active demo path currently renders `fillRect` and `drawBitmap`.
/// Additional cases exist so the shared contract can grow toward the typed
/// scene/batch pipeline, but renderers must opt into them explicitly instead
/// of silently dropping them.

// MARK: - Blend Mode (Gap 4 fix)

/// Gap 4: no per-command blend control existed. Fix: BlendMode enum lets
/// each drawing command specify its compositing operation.

// MARK: - Gradient Types (Gaps 2 & 3 fix)

/// A single color stop within a gradient. Position is in 0...1.
///
/// Gap 3: the old LinearGradient had only startColor/endColor (2 stops).
/// Fix: gradients now carry an unlimited array of GradientStop values.

/// Linear gradient with unlimited color stops.
///
/// Gap 3 fix: replaces the old 2-stop startColor/endColor design.
/// Backends that only support 2 stops can fall back to first/last.

/// Gap 2 fix: radial gradient radiating from a center point.

/// Gap 2 fix: conic (angular/sweep) gradient around a center point.

/// Gap 2 fix: unified gradient type covering linear, radial, and conic.

// MARK: - Render Path (Gap 1 fix)

/// Renderer-neutral path representation. Mirrors common path segment types
/// so that RenderGraph stays independent of any platform path API.
///
/// Gap 1: no path primitives existed in the render graph. Fix: RenderPath
/// captures move/line/quad/cubic/close segments that backends translate to
/// their native path types (e.g. ID2D1PathGeometry on Direct2D).

// MARK: - Clip Shapes (Gap 5 fix)

/// Gap 5: clipping only supported axis-aligned rects via clipRect on each
/// command. Fix: ClipShape supports rects, ellipses, and arbitrary paths.

/// Controls how a new clip interacts with the existing clip region.

// MARK: - Command Structs

/// Shared solid-fill / gradient-fill rect primitive used by all renderers.
///
/// Gap 2 fix: `gradient` field widened from `LinearGradient?` to
/// `GradientType?` so radial and conic fills are representable.
/// Gap 4 fix: optional `blendMode` added.

/// Gap 4 fix: optional blendMode added to DrawBitmapCommand.

/// Gap 1 fix: fill an arbitrary path with a solid color or gradient.

/// Gap 1 fix: stroke an arbitrary path with configurable style.

/// Simple 2D affine transform for path commands.

/// Gap 6 fix: Gaussian blur applied to a rectangular region.

/// First-class text drawing command reserved for renderer paths that can own
/// text shaping/rasterization directly instead of relying on pre-baked bitmaps.

/// Gap 5 fix: push an arbitrary clip shape onto the clip stack.

/// Command to apply a Gaussian blur over a rectangular region.
@MainActor
/// Consumes renderer-neutral frames emitted by shared UI/runtime code.
public protocol RenderBackend: AnyObject {
    var backendDisplayName: String { get }
    var backendStatusDescription: String { get }

    func attach(to surface: SurfaceDescriptor) throws
    func resize(to size: IntSize) throws
    func render(frame: RenderFrame) throws
}
extension RenderBackend {
    public var backendDisplayName: String { "2D RENDERER" }

    public var backendStatusDescription: String { "\(backendDisplayName) READY" }
}
public struct RenderFrame: Equatable, Sendable {
    public var clearColor: Color
    /// Ordered drawing commands produced by shared layout and view logic.
    public var commands: [RenderCommand]

    public init(clearColor: Color = .black, commands: [RenderCommand] = []) {
        self.clearColor = clearColor
        self.commands = commands
    }
}
public enum RenderCommand: Equatable, Sendable {
    case fillRect(FillRectCommand)
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
public enum BlendMode: Int, Equatable, Sendable {
    case normal = 0
    case multiply = 1
    case screen = 2
    case overlay = 3
    case additive = 4
}
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
public enum GradientType: Equatable, Sendable {
    case linear(LinearGradient)
    case radial(RadialGradient)
    case conic(ConicGradient)

    public var startColor: Color {
        switch self {
        case .linear(let g): return g.startColor
        case .radial(let g): return g.stops.first?.color ?? .clear
        case .conic(let g): return g.stops.first?.color ?? .clear
        }
    }

    public var endColor: Color {
        switch self {
        case .linear(let g): return g.stops.last?.color ?? g.startColor
        case .radial(let g): return g.stops.last?.color ?? .clear
        case .conic(let g): return g.stops.last?.color ?? .clear
        }
    }

    public func withMultipliedOpacity(_ opacity: Double) -> GradientType {
        let floatOpacity = Float(opacity)
        switch self {
        case .linear(var g):
            g.stops = g.stops.map {
                GradientStop(color: $0.color.multipliedAlpha(by: floatOpacity), position: $0.position)
            }
            return .linear(g)
        case .radial(var g):
            g.stops = g.stops.map {
                GradientStop(color: $0.color.multipliedAlpha(by: floatOpacity), position: $0.position)
            }
            return .radial(g)
        case .conic(var g):
            g.stops = g.stops.map {
                GradientStop(color: $0.color.multipliedAlpha(by: floatOpacity), position: $0.position)
            }
            return .conic(g)
        }
    }
}
public struct RenderPath: Equatable, Sendable {
    public enum Segment: Equatable, Sendable {
        case moveTo(Point)
        case lineTo(Point)
        case quadCurveTo(control: Point, end: Point)
        case cubicCurveTo(control1: Point, control2: Point, end: Point)
        case arc(center: Point, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool)
        case close
    }

    public var segments: [Segment]

    public init(segments: [Segment] = []) {
        self.segments = segments
    }

    public init(path: Path) {
        self.segments = path.elements.map { element in
            switch element {
            case .moveTo(let p): return .moveTo(p)
            case .lineTo(let p): return .lineTo(p)
            case .quadraticCurveTo(let control, let end): return .quadCurveTo(control: control, end: end)
            case .cubicCurveTo(let control1, let control2, let end):
                return .cubicCurveTo(control1: control1, control2: control2, end: end)
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                return .arc(
                    center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
            case .close: return .close
            }
        }
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

    public mutating func addArc(
        center: Point, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool = false
    ) {
        segments.append(
            .arc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise))
    }

    public var boundingRect: Rect? {
        segments.boundingRect
    }

    public func scaled(to rect: Rect) -> RenderPath {
        let sx = rect.size.width
        let sy = rect.size.height
        let ox = rect.origin.x
        let oy = rect.origin.y
        return RenderPath(
            segments: segments.map { segment in
                switch segment {
                case .moveTo(let p):
                    return .moveTo(Point(x: p.x * sx + ox, y: p.y * sy + oy))
                case .lineTo(let p):
                    return .lineTo(Point(x: p.x * sx + ox, y: p.y * sy + oy))
                case .quadCurveTo(let c, let e):
                    return .quadCurveTo(
                        control: Point(x: c.x * sx + ox, y: c.y * sy + oy),
                        end: Point(x: e.x * sx + ox, y: e.y * sy + oy)
                    )
                case .cubicCurveTo(let c1, let c2, let e):
                    return .cubicCurveTo(
                        control1: Point(x: c1.x * sx + ox, y: c1.y * sy + oy),
                        control2: Point(x: c2.x * sx + ox, y: c2.y * sy + oy),
                        end: Point(x: e.x * sx + ox, y: e.y * sy + oy)
                    )
                case .arc(let c, let r, let s, let e, let cw):
                    return .arc(
                        center: Point(x: c.x * sx + ox, y: c.y * sy + oy),
                        radius: r * max(sx, sy),
                        startAngle: s,
                        endAngle: e,
                        clockwise: cw
                    )
                case .close:
                    return .close
                }
            })
    }

    public func translated(by offset: Point) -> RenderPath {
        RenderPath(
            segments: segments.map { segment in
                switch segment {
                case .moveTo(let p):
                    return .moveTo(Point(x: p.x + offset.x, y: p.y + offset.y))
                case .lineTo(let p):
                    return .lineTo(Point(x: p.x + offset.x, y: p.y + offset.y))
                case .quadCurveTo(let c, let e):
                    return .quadCurveTo(
                        control: Point(x: c.x + offset.x, y: c.y + offset.y),
                        end: Point(x: e.x + offset.x, y: e.y + offset.y)
                    )
                case .cubicCurveTo(let c1, let c2, let e):
                    return .cubicCurveTo(
                        control1: Point(x: c1.x + offset.x, y: c1.y + offset.y),
                        control2: Point(x: c2.x + offset.x, y: c2.y + offset.y),
                        end: Point(x: e.x + offset.x, y: e.y + offset.y)
                    )
                case .arc(let c, let r, let s, let e, let cw):
                    return .arc(
                        center: Point(x: c.x + offset.x, y: c.y + offset.y),
                        radius: r,
                        startAngle: s,
                        endAngle: e,
                        clockwise: cw
                    )
                case .close:
                    return .close
                }
            })
    }
}
extension [RenderPath.Segment] {
    public var boundingRect: Rect? {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        var hasPoint = false
        var current = Point.zero

        for segment in self {
            switch segment {
            case .moveTo(let p), .lineTo(let p):
                current = p
                minX = Swift.min(minX, p.x)
                minY = Swift.min(minY, p.y)
                maxX = Swift.max(maxX, p.x)
                maxY = Swift.max(maxY, p.y)
                hasPoint = true
            case .quadCurveTo(let c, let e):
                minX = Swift.min(minX, current.x, c.x, e.x)
                minY = Swift.min(minY, current.y, c.y, e.y)
                maxX = Swift.max(maxX, current.x, c.x, e.x)
                maxY = Swift.max(maxY, current.y, c.y, e.y)
                current = e
                hasPoint = true
            case .cubicCurveTo(let c1, let c2, let e):
                minX = Swift.min(minX, current.x, c1.x, c2.x, e.x)
                minY = Swift.min(minY, current.y, c1.y, c2.y, e.y)
                maxX = Swift.max(maxX, current.x, c1.x, c2.x, e.x)
                maxY = Swift.max(maxY, current.y, c1.y, c2.y, e.y)
                current = e
                hasPoint = true
            case .arc(let c, let r, _, _, _):
                minX = Swift.min(minX, c.x - r)
                minY = Swift.min(minY, c.y - r)
                maxX = Swift.max(maxX, c.x + r)
                maxY = Swift.max(maxY, c.y + r)
                hasPoint = true
            case .close:
                break
            }
        }
        guard hasPoint else { return nil }
        return Rect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}
public enum ClipShape: Equatable, Sendable {
    case rect(Rect, cornerRadius: Double)
    case ellipse(center: Point, radiusX: Double, radiusY: Double)
    case path(RenderPath)
}
public enum ClipOperation: Equatable, Sendable {
    /// Intersect with the current clip (default, most common).
    case intersect
    /// Replace the current clip entirely.
    case replace
}
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

    /// Reads the BGRA color at the given pixel coordinates (top-left origin).
    public func pixelColor(atX x: Int, y: Int) -> Color? {
        guard x >= 0, x < Int(width), y >= 0, y < Int(height) else { return nil }
        let offset = y * Int(bytesPerRow) + x * 4
        guard offset + 3 < pixels.count else { return nil }
        return Color(
            red: Float(pixels[offset + 2]) / 255,
            green: Float(pixels[offset + 1]) / 255,
            blue: Float(pixels[offset]) / 255,
            alpha: Float(pixels[offset + 3]) / 255
        )
    }

    /// Writes the bitmap as an uncompressed 32-bit BGRA BMP file to `url`.
    /// The alpha channel is preserved; most viewers ignore it.
    public func writeBMP(to url: URL) throws {
        let fileHeaderSize = 14
        let dibHeaderSize = 40
        let pixelDataSize = Int(bytesPerRow) * Int(height)
        let fileSize = fileHeaderSize + dibHeaderSize + pixelDataSize

        var data = Data(capacity: fileSize)
        data.append(contentsOf: [0x42, 0x4D])  // "BM"
        data.append(contentsOf: withUnsafeBytes(of: Int32(fileSize)) { Array($0) })
        data.append(contentsOf: [0, 0, 0, 0])  // reserved
        // pixel offset
        data.append(contentsOf: withUnsafeBytes(of: Int32(fileHeaderSize + dibHeaderSize)) { Array($0) })

        // BITMAPINFOHEADER (40 bytes)
        data.append(contentsOf: withUnsafeBytes(of: Int32(dibHeaderSize)) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(width)) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(-height)) { Array($0) })  // negative = top-down
        data.append(contentsOf: [1, 0])  // planes
        data.append(contentsOf: [32, 0])  // bits per pixel
        data.append(contentsOf: withUnsafeBytes(of: Int32(0)) { Array($0) })  // BI_RGB compression
        data.append(contentsOf: withUnsafeBytes(of: Int32(pixelDataSize)) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(2835)) { Array($0) })  // X pixels/meter
        data.append(contentsOf: withUnsafeBytes(of: Int32(2835)) { Array($0) })  // Y pixels/meter
        data.append(contentsOf: withUnsafeBytes(of: Int32(0)) { Array($0) })  // colors in palette
        data.append(contentsOf: withUnsafeBytes(of: Int32(0)) { Array($0) })  // important colors

        // Pixel array
        data.append(pixels)
        try data.write(to: url)
    }
}
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
public struct FillPathCommand: Equatable, Sendable {
    public var path: RenderPath
    public var color: Color
    public var gradient: GradientType?
    public var transform: AffineTransform
    public var blendMode: BlendMode
    public var clipRect: Rect?

    public init(
        path: RenderPath,
        color: Color,
        gradient: GradientType? = nil,
        transform: AffineTransform = .identity,
        blendMode: BlendMode = .normal,
        clipRect: Rect? = nil
    ) {
        self.path = path
        self.color = color
        self.gradient = gradient
        self.transform = transform
        self.blendMode = blendMode
        self.clipRect = clipRect
    }
}
public struct StrokePathCommand: Equatable, Sendable {
    public var path: RenderPath
    public var color: Color
    public var style: StrokeStyle
    public var transform: AffineTransform
    public var blendMode: BlendMode
    public var clipRect: Rect?

    public init(
        path: RenderPath,
        color: Color,
        style: StrokeStyle = StrokeStyle(),
        transform: AffineTransform = .identity,
        blendMode: BlendMode = .normal,
        clipRect: Rect? = nil
    ) {
        self.path = path
        self.color = color
        self.style = style
        self.transform = transform
        self.blendMode = blendMode
        self.clipRect = clipRect
    }
}
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
public struct ClipCommand: Equatable, Sendable {
    public var shape: ClipShape
    public var operation: ClipOperation

    public init(shape: ClipShape, operation: ClipOperation = .intersect) {
        self.shape = shape
        self.operation = operation
    }
}
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
