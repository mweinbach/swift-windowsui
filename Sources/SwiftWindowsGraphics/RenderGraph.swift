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

    /// What the last render left the presentation path in — occluded, or
    /// owing the screen a repaint after a device rebuild. Backends that
    /// cannot lose a device inherit the neutral value.
    var presentationState: PresentationState { get }

    /// Which clock is pacing this backend's presents. The frame path measured
    /// the *same* 252 ms present block as the batch path on the machine that
    /// motivated ``PresentPacingPolicy``, which is the evidence that the
    /// pathology is the compositor's and not one renderer's — so the fallback
    /// carries the same watchdog rather than being the slow path a user falls
    /// back to.
    var presentPacing: PresentPacingStatus { get }

    /// Tells the backend what one display period costs, so its pacing watchdog
    /// has something to judge present costs against.
    func setDisplayFrameInterval(_ seconds: Double)

    /// Hands the backend a previous session's pacing verdict. Same contract
    /// as `BatchRenderBackend.adoptRememberedSelfPacing()`: the fallback
    /// carries the same watchdog, so it starts from the same memory.
    func adoptRememberedSelfPacing()

    func attach(to surface: SurfaceDescriptor) throws
    func resize(to size: IntSize) throws
    func render(frame: RenderFrame) throws

    /// Releases every resource this backend acquired for its surface and
    /// returns it to the pre-attach state.
    ///
    /// The counterpart to ``attach(to:)``: a GPU backend holds a swap chain
    /// that pins its HWND, plus a device, pipeline objects and caches that
    /// nothing else in the process can release. Callers must invoke this
    /// when the window closes and before handing the same surface to a
    /// different backend, since flip-model presentation is exclusive per
    /// window. Detaching an unattached backend is a no-op, and a detached
    /// backend must be re-attachable.
    ///
    /// Deliberately has no protocol-extension default: a backend that owns
    /// a device and a swap chain used to satisfy this requirement by
    /// inheriting an empty implementation and leak exactly as it did before
    /// the requirement existed. Backends that own nothing write their own
    /// one-line no-op, where a reader can see that it is a decision.
    func detach()
}
extension RenderBackend {
    public var backendDisplayName: String { "2D RENDERER" }

    public var backendStatusDescription: String { "\(backendDisplayName) READY" }

    public var presentationState: PresentationState { PresentationState() }

    /// A backend with no swap chain never waits on a display.
    public var presentPacing: PresentPacingStatus { PresentPacingStatus() }

    public func setDisplayFrameInterval(_ seconds: Double) {}

    /// A backend with no pacing watchdog has nothing to seed.
    public func adoptRememberedSelfPacing() {}
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

    /// The SwiftUI bridge reversed authored stops to preserve an endpoint
    /// direction that the renderer's axis-only vocabulary cannot encode.
    public var reversesAuthoredStops: Bool

    /// Bounds the number of full-footprint quad passes a malformed or
    /// programmatically generated gradient can request in one frame.
    public static let maximumRenderedStops = 64

    /// Full-control initializer with arbitrary stops.
    public init(stops: [GradientStop], axis: GradientAxis = .vertical, reversesAuthoredStops: Bool = false) {
        self.stops = stops
        self.axis = axis
        self.reversesAuthoredStops = reversesAuthoredStops
    }

    /// Convenience: 2-stop gradient matching the original API.
    public init(startColor: Color, endColor: Color, axis: GradientAxis = .vertical) {
        self.stops = [
            GradientStop(color: startColor, position: 0),
            GradientStop(color: endColor, position: 1),
        ]
        self.axis = axis
        self.reversesAuthoredStops = false
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

    /// Normalized, non-overlapping intervals in physical gradient order.
    ///
    /// SwiftUI extends the first and last colors to the ends of the filled
    /// shape, preserves hard transitions at duplicate positions, and ignores
    /// stops whose location is not finite. Keeping that policy here gives the
    /// retained painter and RenderFrame bridge exactly the same lowering.
    public var renderedSegments: [LinearGradientSegment] {
        var ordered = stops.enumerated().compactMap { index, stop -> (Int, GradientStop)? in
            guard stop.position.isFinite else { return nil }
            return (index, GradientStop(color: stop.color, position: min(max(stop.position, 0), 1)))
        }
        ordered.sort { lhs, rhs in
            lhs.1.position == rhs.1.position ? lhs.0 < rhs.0 : lhs.1.position < rhs.1.position
        }

        guard !ordered.isEmpty else {
            let fallback = stops.first?.color ?? .clear
            return [LinearGradientSegment(startColor: fallback, endColor: fallback, start: 0, end: 1)]
        }

        // Endpoint extensions are full-footprint passes too. With every
        // authored stop strictly inside the shape, retaining 64 stops would
        // emit 63 intervals plus both extensions: 65 passes. Reserve the
        // extra interval before sampling so the documented cap bounds the
        // actual renderer work rather than only the authored-stop count.
        let endpointExtensionCount =
            ((ordered.first?.1.position ?? 0) > 0 ? 1 : 0)
            + ((ordered.last?.1.position ?? 1) < 1 ? 1 : 0)
        let maximumRetainedStops = min(
            Self.maximumRenderedStops,
            Self.maximumRenderedStops + 1 - endpointExtensionCount)

        if ordered.count > maximumRetainedStops {
            let lastIndex = ordered.count - 1
            ordered = (0..<maximumRetainedStops).map { index in
                ordered[index * lastIndex / (maximumRetainedStops - 1)]
            }
        }

        var result: [LinearGradientSegment] = []
        result.reserveCapacity(ordered.count + 1)
        var previous = ordered[0].1
        if previous.position > 0 {
            result.append(
                LinearGradientSegment(
                    startColor: previous.color, endColor: previous.color, start: 0, end: previous.position))
        }

        for (_, stop) in ordered.dropFirst() {
            if stop.position > previous.position {
                result.append(
                    LinearGradientSegment(
                        startColor: previous.color, endColor: stop.color,
                        start: previous.position, end: stop.position))
            }
            // A duplicate has zero width but its color starts the next
            // interval, giving a genuine hard stop without double blending.
            previous = stop
        }

        if previous.position < 1 {
            result.append(
                LinearGradientSegment(
                    startColor: previous.color, endColor: previous.color, start: previous.position, end: 1))
        }

        if result.isEmpty {
            result.append(LinearGradientSegment(startColor: previous.color, endColor: previous.color, start: 0, end: 1))
        }
        return result
    }
}

/// One piecewise-linear interval of a normalized gradient.
public struct LinearGradientSegment: Equatable, Sendable {
    public var startColor: Color
    public var endColor: Color
    public var start: Float
    public var end: Float

    public init(startColor: Color, endColor: Color, start: Float, end: Float) {
        self.startColor = startColor
        self.endColor = endColor
        self.start = start
        self.end = end
    }
}
public struct RadialGradient: Equatable, Sendable {
    public var center: Point
    /// Logical radius where the first authored stop begins. Existing direct
    /// renderer callers default to zero, preserving their original API.
    public var startRadius: Double
    /// Logical radius where the final authored stop ends.
    public var radius: Double
    public var stops: [GradientStop]
    /// SwiftUI's `UnitPoint` centers are relative to the painted footprint;
    /// direct renderer-neutral centers remain absolute surface coordinates.
    public var centerIsUnitPoint: Bool

    public init(
        center: Point,
        radius: Double,
        stops: [GradientStop],
        startRadius: Double = 0,
        centerIsUnitPoint: Bool = false
    ) {
        self.center = center
        self.startRadius = startRadius
        self.radius = radius
        self.stops = stops
        self.centerIsUnitPoint = centerIsUnitPoint
    }
}
public struct ConicGradient: Equatable, Sendable {
    public var center: Point
    /// Starting angle in radians, measured clockwise from 12-o'clock.
    public var angle: Double
    /// Optional authored ending angle. `nil` and a zero-width interval both
    /// mean one complete revolution, matching existing conic callers.
    public var endAngle: Double?
    public var stops: [GradientStop]
    public var centerIsUnitPoint: Bool

    public init(
        center: Point,
        angle: Double = 0,
        stops: [GradientStop],
        endAngle: Double? = nil,
        centerIsUnitPoint: Bool = false
    ) {
        self.center = center
        self.angle = angle
        self.endAngle = endAngle
        self.stops = stops
        self.centerIsUnitPoint = centerIsUnitPoint
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

    /// The same gradient with its first stop recoloured — the animatable end
    /// of a two-stop control sheen. Position and axis are untouched.
    public func replacingStartColor(with color: Color) -> GradientType {
        replacingStop(at: 0, with: color)
    }

    /// The same gradient with its last stop recoloured.
    public func replacingEndColor(with color: Color) -> GradientType {
        switch self {
        case .linear(let g): return replacingStop(at: max(0, g.stops.count - 1), with: color)
        case .radial(let g): return replacingStop(at: max(0, g.stops.count - 1), with: color)
        case .conic(let g): return replacingStop(at: max(0, g.stops.count - 1), with: color)
        }
    }

    private func replacingStop(at index: Int, with color: Color) -> GradientType {
        func recoloured(_ stops: [GradientStop]) -> [GradientStop] {
            guard stops.indices.contains(index) else { return stops }
            var next = stops
            next[index] = GradientStop(color: color, position: stops[index].position)
            return next
        }
        switch self {
        case .linear(var g):
            g.stops = recoloured(g.stops)
            return .linear(g)
        case .radial(var g):
            g.stops = recoloured(g.stops)
            return .radial(g)
        case .conic(var g):
            g.stops = recoloured(g.stops)
            return .conic(g)
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
/// The channel order and alpha convention of a `BitmapSurface`'s bytes.
///
/// Before this type existed the convention was folklore, and the producers
/// disagreed: ordinary CPU rasterization stores straight alpha while the
/// DirectWrite/GDI text path stores premultiplied alpha. Every consumer
/// picked one and was therefore wrong about half its inputs. Carrying the
/// format in the surface makes each consumer convert instead of assume.
public struct BitmapPixelFormat: Hashable, Sendable, CustomStringConvertible {
    /// Byte order within a 32-bit pixel. Only BGRA exists today — it is
    /// what GDI DIBs, WIC's `32bppBGRA`, Direct2D and the swap chain's
    /// `B8G8R8A8_UNORM` all use — but naming it keeps the assumption
    /// checkable.
    public enum ChannelOrder: Hashable, Sendable {
        /// Byte 0 = blue, 1 = green, 2 = red, 3 = alpha.
        case bgra
    }

    /// Whether the colour channels have already been scaled by alpha.
    public enum AlphaMode: Hashable, Sendable {
        /// Colour channels are independent of alpha (`rgb`, `a`).
        case straight
        /// Colour channels are already scaled by alpha (`rgb * a`, `a`).
        /// Composited additive foregrounds can also carry emitted RGB greater
        /// than alpha; retain those raw premultiplied bytes during transport.
        /// This is what a `ONE`/`INV_SRC_ALPHA` blend state and Direct2D
        /// bitmaps require, and the only convention that survives bilinear
        /// filtering without bleeding transparent texels into edges.
        case premultiplied
    }

    public var channelOrder: ChannelOrder
    public var alphaMode: AlphaMode

    public init(channelOrder: ChannelOrder = .bgra, alphaMode: AlphaMode) {
        self.channelOrder = channelOrder
        self.alphaMode = alphaMode
    }

    /// The default for ordinary CPU rasterization and WIC image loading, and
    /// the interchange convention of `BitmapSurface.writePNG`. Additive scene
    /// emission can require the existing premultiplied format instead.
    public static let bgra8Straight = BitmapPixelFormat(channelOrder: .bgra, alphaMode: .straight)
    /// What the DirectWrite/GDI text path produces (`GDIRasterTextRenderer.tint`
    /// scales the colour channels by coverage) and what every GPU/Direct2D
    /// upload in this stack is normalized to.
    public static let bgra8Premultiplied = BitmapPixelFormat(channelOrder: .bgra, alphaMode: .premultiplied)

    public var description: String {
        switch alphaMode {
        case .straight: return "BGRA8/straight"
        case .premultiplied: return "BGRA8/premultiplied"
        }
    }
}

/// Why a `BitmapSurface` cannot be handed to a texture upload.
///
/// Every GPU and Direct2D upload reads `bytesPerRow * height` bytes out of
/// `pixels`; a surface that does not carry that many is a heap over-read,
/// so the uploads validate first and throw one of these instead.
public enum BitmapSurfaceError: Error, Equatable, CustomStringConvertible {
    case nonPositiveDimensions(width: Int32, height: Int32)
    case bytesPerRowTooSmall(bytesPerRow: Int32, minimum: Int32)
    case pixelBufferTooSmall(available: Int, required: Int)

    public var description: String {
        switch self {
        case .nonPositiveDimensions(let width, let height):
            return "Bitmap surface has non-positive dimensions (\(width)×\(height))."
        case .bytesPerRowTooSmall(let bytesPerRow, let minimum):
            return "Bitmap surface stride \(bytesPerRow) is below the \(minimum) bytes one row needs."
        case .pixelBufferTooSmall(let available, let required):
            return "Bitmap surface holds \(available) bytes but describes \(required)."
        }
    }
}

/// Identity of the *content* of a bitmap: the producer-minted token of the
/// bytes plus the geometry that says how to read them.
///
/// A texture cache keys on this. Unlike a byte comparison it is O(1), and
/// unlike a buffer address it stays valid after the surface it came from is
/// gone — an address can be recycled by a different allocation, a token
/// never is.
public struct BitmapContentKey: Hashable, Sendable {
    public var token: UInt64
    public var width: Int32
    public var height: Int32
    public var bytesPerRow: Int32
    public var alphaMode: BitmapPixelFormat.AlphaMode

    public init(
        token: UInt64,
        width: Int32,
        height: Int32,
        bytesPerRow: Int32,
        alphaMode: BitmapPixelFormat.AlphaMode
    ) {
        self.token = token
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.alphaMode = alphaMode
    }
}

public struct BitmapSurface: Equatable, Sendable {
    public var width: Int32
    public var height: Int32
    public var bytesPerRow: Int32
    /// Re-minting `contentToken` on every write is what makes the token
    /// safe: any mutation of the buffer — including `replaceSubrange` and
    /// `withUnsafeMutableBytes`, which are mutating accesses through this
    /// property — produces a new identity, so a cached texture keyed on the
    /// old token is never mistaken for the new bytes.
    public var pixels: Data {
        didSet { contentToken = RenderContentVersion.next() }
    }
    /// Channel order and alpha convention of `pixels`. Defaults to the
    /// straight-alpha BGRA ordinary CPU scenes produce; every producer that
    /// stores premultiplied bytes, including additive emission, must say so.
    public var format: BitmapPixelFormat

    /// Process-unique identity of this buffer's bytes, minted when the
    /// surface is created and re-minted on every write.
    ///
    /// Deliberately excluded from `==`: two surfaces with the same bytes
    /// and different tokens are equal (they draw the same), they just do
    /// not share a cache entry. The conservative direction — a redundant
    /// upload, never a stale texture.
    public private(set) var contentToken: UInt64 = RenderContentVersion.next()

    /// Cache key for this surface's content. Includes the geometry because
    /// the same bytes read at a different stride are a different image.
    public var contentKey: BitmapContentKey {
        BitmapContentKey(
            token: contentToken,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            alphaMode: format.alphaMode
        )
    }

    public init(
        width: Int32,
        height: Int32,
        bytesPerRow: Int32,
        pixels: Data,
        format: BitmapPixelFormat = .bgra8Straight
    ) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
        self.format = format
    }

    public static func == (lhs: BitmapSurface, rhs: BitmapSurface) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.bytesPerRow == rhs.bytesPerRow
            && lhs.format == rhs.format && lhs.pixels == rhs.pixels
    }

    /// Number of bytes an upload will read out of `pixels`.
    public var describedByteCount: Int {
        Int(bytesPerRow) * Int(height)
    }

    /// Throws when the surface's geometry does not match its buffer, i.e.
    /// when reading it as a texture would run off the end of `pixels`.
    /// Called before every GPU and Direct2D upload.
    public func validate() throws {
        guard width > 0, height > 0 else {
            throw BitmapSurfaceError.nonPositiveDimensions(width: width, height: height)
        }
        let minimumStride = width.multipliedReportingOverflow(by: 4)
        guard !minimumStride.overflow, bytesPerRow >= minimumStride.partialValue else {
            throw BitmapSurfaceError.bytesPerRowTooSmall(
                bytesPerRow: bytesPerRow, minimum: minimumStride.overflow ? Int32.max : minimumStride.partialValue)
        }
        let required = describedByteCount
        guard pixels.count >= required else {
            throw BitmapSurfaceError.pixelBufferTooSmall(available: pixels.count, required: required)
        }
    }

    /// The same image with premultiplied colour channels — the convention
    /// every GPU texture and Direct2D bitmap in this stack is uploaded in.
    /// Returns `self` untouched when the bytes are already premultiplied or
    /// when every pixel is opaque (the two conventions coincide there), so
    /// the common opaque upload copies nothing.
    public func premultipliedAlpha() -> BitmapSurface {
        converted(to: .premultiplied)
    }

    /// Convert to straight (non-premultiplied) colour channels for interchange.
    /// Returns `self` untouched when already straight or opaque. This bounded
    /// representation cannot preserve additive emission with RGB greater than
    /// alpha: zero-alpha RGB is cleared and larger straight channels clamp.
    public func straightAlpha() -> BitmapSurface {
        converted(to: .straight)
    }

    /// True as soon as one pixel carries alpha below 255.
    ///
    /// This is the whole question `converted(to:)` has to answer before it
    /// allocates anything: straight and premultiplied bytes are identical
    /// for an opaque pixel, so an all-opaque surface converts by relabelling
    /// its format. The scan touches one byte per pixel and stops at the
    /// first translucent one.
    private var containsTranslucentPixel: Bool {
        let rowStride = Int(bytesPerRow)
        let rowCount = Int(height)
        let pixelCount = Int(width)
        guard rowStride > 0, rowCount > 0, pixelCount > 0 else { return false }

        return pixels.withUnsafeBytes { buffer -> Bool in
            let byteCount = buffer.count
            for y in 0..<rowCount {
                let rowStart = y * rowStride
                // A short buffer is `validate()`'s business; here it just
                // ends the scan, since there is nothing left to convert.
                guard rowStart + 3 < byteCount else { return false }
                let lastInRow = min(pixelCount, (byteCount - rowStart) / 4)
                for x in 0..<lastInRow where buffer[rowStart + x * 4 + 3] < 255 {
                    return true
                }
            }
            return false
        }
    }

    private func converted(to alphaMode: BitmapPixelFormat.AlphaMode) -> BitmapSurface {
        guard format.alphaMode != alphaMode else { return self }

        // Scan before allocating. The old code copied the whole buffer and
        // only then discovered that nothing in it needed converting, which
        // put a full-surface `Data` copy plus a bounds-checked per-pixel
        // loop on the main thread for every image upload of every frame.
        guard containsTranslucentPixel else {
            var relabelled = self
            relabelled.format.alphaMode = alphaMode
            return relabelled
        }

        let rowStride = Int(bytesPerRow)
        let rowCount = Int(height)
        let pixelCount = Int(width)
        var converted = [UInt8](pixels)
        converted.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            let byteCount = buffer.count
            for y in 0..<rowCount {
                let rowStart = y * rowStride
                guard rowStart + 3 < byteCount else { break }
                let lastInRow = min(pixelCount, (byteCount - rowStart) / 4)
                for x in 0..<lastInRow {
                    let offset = rowStart + x * 4
                    let alpha = Int(base[offset + 3])
                    guard alpha < 255 else { continue }
                    if alpha == 0 {
                        base[offset] = 0
                        base[offset + 1] = 0
                        base[offset + 2] = 0
                        continue
                    }
                    for channel in 0..<3 {
                        let value = Int(base[offset + channel])
                        let scaled =
                            alphaMode == .premultiplied
                            ? (value * alpha + 127) / 255
                            : min(255, (value * 255 + alpha / 2) / alpha)
                        base[offset + channel] = UInt8(scaled)
                    }
                }
            }
        }

        var result = self
        result.format.alphaMode = alphaMode
        result.pixels = Data(converted)
        return result
    }

    /// Reads the straight-alpha BGRA color at the given pixel coordinates
    /// (top-left origin), un-premultiplying when the surface stores
    /// premultiplied bytes.
    public func pixelColor(atX x: Int, y: Int) -> Color? {
        guard x >= 0, x < Int(width), y >= 0, y < Int(height) else { return nil }
        let offset = y * Int(bytesPerRow) + x * 4
        guard offset + 3 < pixels.count else { return nil }
        let alpha = Float(pixels[offset + 3]) / 255
        let divisor = format.alphaMode == .premultiplied && alpha > 0 ? alpha : 1
        return Color(
            red: min(1, Float(pixels[offset + 2]) / 255 / divisor),
            green: min(1, Float(pixels[offset + 1]) / 255 / divisor),
            blue: min(1, Float(pixels[offset]) / 255 / divisor),
            alpha: alpha
        )
    }

    /// Writes the bitmap as an uncompressed 32-bit BGRA BMP file to `url`.
    /// The alpha channel is preserved; most viewers ignore it, so the
    /// pixels are written straight-alpha — a premultiplied surface would
    /// otherwise look darkened in every viewer that drops the channel.
    public func writeBMP(to url: URL) throws {
        let source = straightAlpha()
        let width = source.width
        let height = source.height
        let bytesPerRow = source.bytesPerRow
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
        data.append(source.pixels)
        try data.write(to: url)
    }
}
public struct DrawBitmapCommand: Equatable, Sendable {
    /// Logical destination. Native frame presenters only replace its extent
    /// for an explicitly declared destination-sized device-pixel raster.
    public var rect: Rect
    public var bitmap: BitmapSurface
    public var opacity: Float
    public var clipRect: Rect?
    /// Gap 4 fix: per-command blend mode, defaults to .normal.
    public var blendMode: BlendMode
    public var sampling: ImageSamplingDescriptor
    public var placement: BitmapPlacement

    /// Keeps the original initializer's function type as well as its call
    /// syntax. Ordinary bitmap commands occupy their requested destination.
    public init(
        rect: Rect,
        bitmap: BitmapSurface,
        opacity: Float = 1.0,
        clipRect: Rect? = nil,
        blendMode: BlendMode = .normal,
        sampling: ImageSamplingDescriptor = .legacy
    ) {
        self.init(
            rect: rect, bitmap: bitmap, opacity: opacity, clipRect: clipRect, blendMode: blendMode,
            sampling: sampling, placement: .destinationRect)
    }

    public init(
        rect: Rect,
        bitmap: BitmapSurface,
        opacity: Float = 1.0,
        clipRect: Rect? = nil,
        blendMode: BlendMode = .normal,
        sampling: ImageSamplingDescriptor = .legacy,
        placement: BitmapPlacement
    ) {
        self.rect = rect
        self.bitmap = bitmap
        self.opacity = opacity
        self.clipRect = clipRect
        self.blendMode = blendMode
        self.sampling = sampling
        self.placement = placement
    }
}
public struct FillPathCommand: Equatable, Sendable {
    public var path: RenderPath
    public var color: Color
    public var gradient: GradientType?
    public var transform: AffineTransform
    public var blendMode: BlendMode
    public var clipRect: Rect?
    public var fillRule: PathFillRule

    public init(
        path: RenderPath,
        color: Color,
        gradient: GradientType? = nil,
        transform: AffineTransform = .identity,
        blendMode: BlendMode = .normal,
        clipRect: Rect? = nil,
        fillRule: PathFillRule = .nonZero
    ) {
        self.path = path
        self.color = color
        self.gradient = gradient
        self.transform = transform
        self.blendMode = blendMode
        self.clipRect = clipRect
        self.fillRule = fillRule
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
