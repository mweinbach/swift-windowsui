import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout

// MARK: - Canvas Graphics Context

/// A drawing context for retained-mode canvas operations.
/// Accumulates draw commands that are later translated into `RenderCommand`
/// or `PathPrimitive` output during the view tree render pass.
@MainActor
public struct CanvasGraphicsContext {
    public enum Shading {
        case color(Color)
        case gradient(LinearGradient)
    }

    public enum Operation {
        case fillPath(RenderPath, Color)
        case strokePath(RenderPath, Color, StrokeStyle)
        case fillRect(Rect, Color)
        case fillRectGradient(Rect, LinearGradient)
        case strokeRect(Rect, Color, Double)
        case drawText(String, Rect, PixelTextStyle)
        case drawImage(BitmapSurface, Rect, Float)
        case pushClip(Rect)
        case popClip
    }

    internal var operations: [Operation] = []
    internal var currentClip: Rect? = nil

    public init() {}

    // MARK: - Path drawing

    public mutating func fill(_ path: Path, with shading: Shading) {
        let renderPath = path.asRenderPath()
        switch shading {
        case .color(let color):
            operations.append(.fillPath(renderPath, color))
        case .gradient(let gradient):
            // Gap: gradient fill on path is not yet supported by the render pipeline.
            // Fall back to the first stop color.
            operations.append(.fillPath(renderPath, gradient.stops.first?.color ?? .clear))
        }
    }

    public mutating func stroke(_ path: Path, with shading: Shading, style: StrokeStyle = StrokeStyle(lineWidth: 1)) {
        let renderPath = path.asRenderPath()
        switch shading {
        case .color(let color):
            operations.append(.strokePath(renderPath, color, style))
        case .gradient(let gradient):
            operations.append(.strokePath(renderPath, gradient.stops.first?.color ?? .clear, style))
        }
    }

    // MARK: - Rect drawing

    public mutating func fill(_ rect: Rect, with shading: Shading) {
        switch shading {
        case .color(let color):
            operations.append(.fillRect(rect, color))
        case .gradient(let gradient):
            operations.append(.fillRectGradient(rect, gradient))
        }
    }

    public mutating func stroke(_ rect: Rect, with shading: Shading, lineWidth: Double = 1) {
        switch shading {
        case .color(let color):
            operations.append(.strokeRect(rect, color, lineWidth))
        case .gradient(let gradient):
            operations.append(.strokeRect(rect, gradient.stops.first?.color ?? .clear, lineWidth))
        }
    }

    // MARK: - Text drawing

    public mutating func draw(
        _ text: String,
        in rect: Rect,
        style: PixelTextStyle
    ) {
        operations.append(.drawText(text, rect, style))
    }

    public mutating func draw(
        _ text: String,
        at point: Point,
        style: PixelTextStyle
    ) {
        let size = textSizeThatFits(text, style: style)
        let rect = Rect(origin: point, size: size)
        operations.append(.drawText(text, rect, style))
    }

    // MARK: - Image drawing

    public mutating func draw(_ image: BitmapSurface, in rect: Rect, opacity: Float = 1) {
        operations.append(.drawImage(image, rect, opacity))
    }

    // MARK: - Clipping

    public mutating func clip(to rect: Rect) {
        operations.append(.pushClip(rect))
        currentClip = rect
    }

    public mutating func popClip() {
        operations.append(.popClip)
        currentClip = nil
    }

    // MARK: - Layer scope

    /// Append all operations recorded in `other` onto this context.  Used by
    /// SwiftUI-shape ``GraphicsContext.drawLayer`` helpers in the WinSwiftUI
    /// module to composite a sub-context's operations back into the parent.
    public mutating func append(contentsOf other: CanvasGraphicsContext) {
        operations.append(contentsOf: other.operations)
    }

    // MARK: - Internal helpers

    private func textSizeThatFits(_ text: String, style: PixelTextStyle) -> Size {
        PixelFont.measure(text, style: style)
    }
}

// MARK: - Path → RenderPath conversion

extension Path {
    func asRenderPath() -> RenderPath {
        var segments: [RenderPath.Segment] = []
        for element in elements {
            switch element {
            case .moveTo(let p):
                segments.append(.moveTo(p))
            case .lineTo(let p):
                segments.append(.lineTo(p))
            case .quadraticCurveTo(let control, let end):
                segments.append(.quadCurveTo(control: control, end: end))
            case .cubicCurveTo(let c1, let c2, let end):
                segments.append(.cubicCurveTo(control1: c1, control2: c2, end: end))
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                segments.append(
                    .arc(
                        center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise
                    ))
            case .close:
                segments.append(.close)
            }
        }
        return RenderPath(segments: segments)
    }
}

// MARK: - Render command emission

extension CanvasGraphicsContext {
    /// Translate accumulated canvas operations into `RenderCommand` values,
    /// appending them into the given command array.
    func appendCommands(
        into commands: inout [RenderCommand],
        origin: Point,
        clipRect: Rect?,
        opacity: Float,
        displayScale: Double
    ) {
        var clipStack: [Rect?] = []
        var currentClip = clipRect

        for operation in operations {
            switch operation {
            case .fillPath(let path, let color):
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0 else { continue }
                commands.append(
                    .fillPath(
                        FillPathCommand(
                            path: path.translated(by: origin),
                            color: effectiveColor,
                            clipRect: currentClip
                        )))

            case .strokePath(let path, let color, let style):
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0 else { continue }
                commands.append(
                    .strokePath(
                        StrokePathCommand(
                            path: path.translated(by: origin),
                            color: effectiveColor,
                            style: style,
                            clipRect: currentClip
                        )))

            case .fillRect(let rect, let color):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0 else { continue }
                if baseClipAllowsDrawing(baseClip: currentClip, rect: effectiveRect) {
                    commands.append(
                        .fillRect(
                            FillRectCommand(
                                rect: effectiveRect,
                                color: effectiveColor,
                                clipRect: currentClip
                            )))
                }

            case .fillRectGradient(let rect, let gradient):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let startColor = gradient.startColor.multipliedAlpha(by: opacity)
                guard opacity > 0, gradient.stops.contains(where: { $0.color.alpha > 0 }) else { continue }
                if baseClipAllowsDrawing(baseClip: currentClip, rect: effectiveRect) {
                    let scaledGradient = LinearGradient(
                        stops: gradient.stops.map {
                            GradientStop(color: $0.color.multipliedAlpha(by: opacity), position: $0.position)
                        },
                        axis: gradient.axis,
                        reversesAuthoredStops: gradient.reversesAuthoredStops
                    )
                    commands.append(
                        .fillRect(
                            FillRectCommand(
                                rect: effectiveRect,
                                color: startColor,
                                clipRect: currentClip,
                                gradient: scaledGradient
                            )))
                }

            case .strokeRect(let rect, let color, let lineWidth):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0, lineWidth > 0 else { continue }
                if baseClipAllowsDrawing(baseClip: currentClip, rect: effectiveRect) {
                    commands.append(
                        .fillRect(
                            FillRectCommand(
                                rect: effectiveRect,
                                color: effectiveColor,
                                clipRect: currentClip
                            )))
                }

            case .drawText(let text, let rect, let style):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveStyle = style.multipliedOpacity(by: opacity)
                if baseClipAllowsDrawing(baseClip: currentClip, rect: effectiveRect) {
                    if !NativeTextRenderer.appendCommands(
                        for: text, in: effectiveRect, style: effectiveStyle,
                        scaleFactor: displayScale, clipRect: currentClip, into: &commands
                    ) {
                        PixelFont.appendCommands(
                            for: text, in: effectiveRect, style: effectiveStyle,
                            clipRect: currentClip, into: &commands
                        )
                    }
                }

            case .drawImage(let bitmap, let rect, let imageOpacity):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveOpacity = opacity * imageOpacity
                guard effectiveOpacity > 0 else { continue }
                if baseClipAllowsDrawing(baseClip: currentClip, rect: effectiveRect) {
                    commands.append(
                        .drawBitmap(
                            DrawBitmapCommand(
                                rect: effectiveRect,
                                bitmap: bitmap,
                                opacity: effectiveOpacity,
                                clipRect: currentClip
                            )))
                }

            case .pushClip(let rect):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                clipStack.append(currentClip)
                if let existing = currentClip {
                    currentClip = existing.intersected(with: effectiveRect)
                } else {
                    currentClip = effectiveRect
                }
                commands.append(.pushClip(ClipCommand(shape: .rect(effectiveRect, cornerRadius: 0))))

            case .popClip:
                currentClip = clipStack.popLast() ?? nil
                commands.append(.popClip)
            }
        }
    }
}
