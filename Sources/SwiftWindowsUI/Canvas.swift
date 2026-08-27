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
        case positionedGradient(LinearGradient, startPoint: Point, endPoint: Point)
    }

    public enum Operation {
        case fillPath(RenderPath, Color)
        case fillPathGradient(RenderPath, LinearGradient, startPoint: Point?, endPoint: Point?)
        case strokePath(RenderPath, Color, StrokeStyle)
        case strokePathGradient(RenderPath, LinearGradient, StrokeStyle, startPoint: Point?, endPoint: Point?)
        case fillRect(Rect, Color)
        case fillRectGradient(Rect, LinearGradient)
        case strokeRect(Rect, Color, Double)
        case drawText(String, Rect, PixelTextStyle)
        case drawImage(BitmapSurface, Rect, Float)
        case drawSymbol(CanvasSymbolSource, Rect, CGAffineTransform, Float)
        case pushClip(Rect)
        case popClip
    }

    /// Copies of a graphics context share a drawing destination, while each
    /// copy keeps its own drawing state. Appends therefore preserve the actual
    /// call order even when the renderer interleaves several context values.
    private final class OperationSink {
        var operations: [Operation] = []
    }

    private let sink = OperationSink()
    internal var operations: [Operation] { sink.operations }
    internal private(set) var currentClip: Rect? = nil
    private var clipStack: [Rect?] = []

    public init() {}

    // MARK: - Path drawing

    public mutating func fill(_ path: Path, with shading: Shading) {
        let renderPath = path.asRenderPath()
        switch shading {
        case .color(let color):
            record(.fillPath(renderPath, color))
        case .gradient(let gradient):
            record(.fillPathGradient(renderPath, gradient, startPoint: nil, endPoint: nil))
        case .positionedGradient(let gradient, let startPoint, let endPoint):
            record(
                .fillPathGradient(renderPath, gradient, startPoint: startPoint, endPoint: endPoint))
        }
    }

    public mutating func stroke(_ path: Path, with shading: Shading, style: StrokeStyle = StrokeStyle(lineWidth: 1)) {
        let renderPath = path.asRenderPath()
        switch shading {
        case .color(let color):
            record(.strokePath(renderPath, color, style))
        case .gradient(let gradient):
            record(.strokePathGradient(renderPath, gradient, style, startPoint: nil, endPoint: nil))
        case .positionedGradient(let gradient, let startPoint, let endPoint):
            record(
                .strokePathGradient(renderPath, gradient, style, startPoint: startPoint, endPoint: endPoint))
        }
    }

    // MARK: - Rect drawing

    public mutating func fill(_ rect: Rect, with shading: Shading) {
        switch shading {
        case .color(let color):
            record(.fillRect(rect, color))
        case .gradient(let gradient):
            record(.fillRectGradient(rect, gradient))
        case .positionedGradient:
            // A positioned ramp can begin/end inside the rectangle or follow
            // a transformed vector; only the path pipeline can preserve that
            // geometry. Existing plain gradients keep the exact quad fast path.
            fill(Path(rect), with: shading)
        }
    }

    public mutating func stroke(_ rect: Rect, with shading: Shading, lineWidth: Double = 1) {
        switch shading {
        case .color(let color):
            record(.strokeRect(rect, color, lineWidth))
        case .gradient(let gradient):
            record(
                .strokePathGradient(
                    RenderPath(path: Path(rect)), gradient, StrokeStyle(lineWidth: lineWidth),
                    startPoint: nil, endPoint: nil))
        case .positionedGradient(let gradient, let startPoint, let endPoint):
            record(
                .strokePathGradient(
                    RenderPath(path: Path(rect)), gradient, StrokeStyle(lineWidth: lineWidth),
                    startPoint: startPoint, endPoint: endPoint))
        }
    }

    // MARK: - Text drawing

    public mutating func draw(
        _ text: String,
        in rect: Rect,
        style: PixelTextStyle
    ) {
        record(.drawText(text, rect, style))
    }

    public mutating func draw(
        _ text: String,
        at point: Point,
        style: PixelTextStyle
    ) {
        let size = textSizeThatFits(text, style: style)
        let rect = Rect(origin: point, size: size)
        record(.drawText(text, rect, style))
    }

    // MARK: - Image drawing

    public mutating func draw(_ image: BitmapSurface, in rect: Rect, opacity: Float = 1) {
        record(.drawImage(image, rect, opacity))
    }

    /// Records a retained symbol separately from its destination transform.
    /// ScenePainter keeps this as a scene-backed image source on the GPU path.
    public mutating func draw(
        _ symbol: CanvasSymbolSource, in rect: Rect,
        transform: CGAffineTransform = .identity, opacity: Float = 1
    ) {
        record(.drawSymbol(symbol, rect, transform, opacity))
    }

    // MARK: - Clipping

    public mutating func clip(to rect: Rect) {
        clipStack.append(currentClip)
        guard rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite, !rect.isEmpty else {
            currentClip = .zero
            return
        }
        currentClip = currentClip.map { $0.intersected(with: rect) ?? .zero } ?? rect
    }

    public mutating func popClip() {
        currentClip = clipStack.popLast() ?? nil
    }

    // MARK: - Layer scope

    /// A layer context shares the destination and copies the current clip.
    /// Drawing through it records immediately; no later append is needed.
    public func makeLayerContext() -> CanvasGraphicsContext { self }

    /// Append an independent command stream, preserving this value's clip.
    /// Copies already share a sink and must never append themselves twice.
    public mutating func append(contentsOf other: CanvasGraphicsContext) {
        guard sink !== other.sink else { return }
        if let currentClip { sink.operations.append(.pushClip(currentClip)) }
        sink.operations.append(contentsOf: other.operations)
        if currentClip != nil { sink.operations.append(.popClip) }
    }

    // MARK: - Internal helpers

    /// Each draw carries its own clip scope so no copied context can leave
    /// drawing state behind for the next context that writes to the sink.
    private func record(_ operation: Operation) {
        if let currentClip { sink.operations.append(.pushClip(currentClip)) }
        sink.operations.append(operation)
        if currentClip != nil { sink.operations.append(.popClip) }
    }

    private func textSizeThatFits(_ text: String, style: PixelTextStyle) -> Size {
        PixelFont.measure(text, style: style)
    }

    /// View placement scales Canvas coordinates after the authored context
    /// transform. Keep the recorded sink unchanged: other value copies still
    /// share it, and identity placement must keep its original operations.
    internal func operationsScaled(by factor: Double) -> [Operation] {
        guard factor != 1 else { return operations }
        guard factor.isFinite, factor > 0 else { return [] }
        let pathScale = Rect(x: 0, y: 0, width: factor, height: factor)
        let transformScale = CGAffineTransform(scaleX: factor, y: factor)
        return operations.map { operation in
            switch operation {
            case .fillPath(let path, let color):
                return .fillPath(path.scaled(to: pathScale), color)
            case .fillPathGradient(let path, let gradient, let start, let end):
                return .fillPathGradient(
                    path.scaled(to: pathScale), gradient,
                    startPoint: start?.scaled(by: factor), endPoint: end?.scaled(by: factor))
            case .strokePath(let path, let color, let style):
                return .strokePath(path.scaled(to: pathScale), color, Self.scaled(style, by: factor))
            case .strokePathGradient(let path, let gradient, let style, let start, let end):
                return .strokePathGradient(
                    path.scaled(to: pathScale), gradient, Self.scaled(style, by: factor),
                    startPoint: start?.scaled(by: factor), endPoint: end?.scaled(by: factor))
            case .fillRect(let rect, let color):
                return .fillRect(rect.scaled(by: factor), color)
            case .fillRectGradient(let rect, let gradient):
                return .fillRectGradient(rect.scaled(by: factor), gradient)
            case .strokeRect(let rect, let color, let width):
                return .strokeRect(rect.scaled(by: factor), color, width * factor)
            case .drawText(let text, let rect, let style):
                return .drawText(text, rect.scaled(by: factor), Self.scaled(style, by: factor))
            case .drawImage(let bitmap, let rect, let opacity):
                return .drawImage(bitmap, rect.scaled(by: factor), opacity)
            case .drawSymbol(let symbol, let rect, let transform, let opacity):
                return .drawSymbol(symbol, rect, transform.concatenating(transformScale), opacity)
            case .pushClip(let rect):
                return .pushClip(rect.scaled(by: factor))
            case .popClip:
                return .popClip
            }
        }
    }

    private static func scaled(_ style: StrokeStyle, by factor: Double) -> StrokeStyle {
        var result = style
        result.lineWidth *= factor
        result.dashOffset *= factor
        result.dashPattern = style.dashPattern.map { $0 * factor }
        return result
    }

    private static func scaled(_ style: PixelTextStyle, by factor: Double) -> PixelTextStyle {
        var result = style
        result.scale *= factor
        result.nativeFontSize = style.nativeFontPixelSize * factor
        result.nativeLetterSpacing = style.nativeLetterSpacing.map { $0 * factor }
        result.lineSpacing *= factor
        result.insets = EdgeInsets(
            top: style.insets.top * factor, leading: style.insets.leading * factor,
            bottom: style.insets.bottom * factor, trailing: style.insets.trailing * factor)
        // Pixel-font letterSpacing is in atlas units and already receives
        // `scale`; multiplying it here would apply the transform twice.
        result.spans = style.spans?.map { span in
            var result = span
            result.style = scaled(span.style, by: factor)
            return result
        }
        return result
    }
}

extension PixelTextStyle {
    /// Canvas placement scales native line spacing in points. PixelFont
    /// instead stores that gap in atlas units and multiplies it by `scale`,
    /// which already contains the placement scale. Undo only the extra gap
    /// factor after native rendering declines; keep all native metrics intact.
    func canvasPixelFontFallback(coordinateScale: Double) -> PixelTextStyle {
        guard coordinateScale != 1, coordinateScale.isFinite, coordinateScale > 0 else { return self }
        var result = self
        result.lineSpacing /= coordinateScale
        result.spans = spans?.map { span in
            var result = span
            result.style = span.style.canvasPixelFontFallback(coordinateScale: coordinateScale)
            return result
        }
        return result
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
        displayScale: Double,
        coordinateScale: Double = 1
    ) {
        var clipStack: [Rect?] = []
        var currentClip = clipRect
        var symbols = CanvasSymbolFrameRenderer()

        for operation in operationsScaled(by: coordinateScale) {
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

            case .fillPathGradient(let path, let gradient, _, _):
                // RenderFrame has no gradient-bearing path command. Preserve
                // its documented first-stop fallback while the default scene
                // path carries the complete retained gradient.
                let effectiveColor = gradient.startColor.multipliedAlpha(by: opacity)
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

            case .strokePathGradient(let path, let gradient, let style, _, _):
                let effectiveColor = gradient.startColor.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0, style.lineWidth > 0 else { continue }
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
                            for: text, in: effectiveRect,
                            style: effectiveStyle.canvasPixelFontFallback(coordinateScale: coordinateScale),
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

            case .drawSymbol(let symbol, let rect, let transform, let symbolOpacity):
                symbols.append(
                    symbol, in: rect, transform: transform, origin: origin,
                    clipRect: currentClip, opacity: opacity * symbolOpacity,
                    displayScale: displayScale, to: &commands)

            case .pushClip(let rect):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                clipStack.append(currentClip)
                if let existing = currentClip {
                    currentClip = existing.intersected(with: effectiveRect) ?? .zero
                } else {
                    currentClip = effectiveRect
                }
                commands.append(.pushClip(ClipCommand(shape: .rect(effectiveRect, cornerRadius: 0))))

            case .popClip:
                currentClip = clipStack.popLast() ?? clipRect
                commands.append(.popClip)
            }
        }
    }
}
