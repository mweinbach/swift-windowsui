import Foundation

import SwiftWindowsCore

/// Frame-fallback path degradation (Phase 6 — frame fallback policy).
///
/// The frame renderer contract is `fillRect` + `drawBitmap` + an axis-aligned
/// clip stack. `fillPath` / `strokePath` commands still arrive from Canvas
/// drawing, `backgroundPath` nodes, and the SF-symbol vector fallback; a
/// backend that soft-skips them makes vector chrome (icons, gauges, chart
/// strokes) silently invisible in a downgraded session. To keep Supported
/// controls *readable* on the frame path, each path command is CPU-rasterized
/// into a `BitmapSurface` via `GPUIRawSceneRasterizer` and rewritten as an
/// equivalent `drawBitmap`, preserving presentation order and clip rects.
///
/// This is a degradation, not parity: per-frame rasterization costs more than
/// the scene path's GPU tessellation, and curved output is scanline- rather
/// than shader-antialiased. The scene backend remains the default; this only
/// runs when the frame backend presents.
public enum FramePathDegradation {
    /// Rewrites `fillPath` / `strokePath` commands in `frame` as pre-rasterized
    /// `drawBitmap` commands, preserving presentation order, per-command clip
    /// rects, and the clear color. `applyBlur` / `drawText` pass through
    /// untouched (backends keep soft-skipping them with diagnostics).
    ///
    /// `scaleFactor` is the display scale; path geometry is rasterized in
    /// device pixels so the emitted bitmaps match the native-text bitmaps the
    /// frame path already draws 1:1 against physical pixels. Frames without
    /// path commands are returned unchanged.
    public static func degradingPathsToBitmaps(in frame: RenderFrame, scaleFactor: Double = 1.0) -> RenderFrame {
        guard frame.commands.contains(where: \.isPathCommand) else {
            return frame
        }

        let scale = max(scaleFactor, 1.0)
        var commands: [RenderCommand] = []
        commands.reserveCapacity(frame.commands.count)

        for command in frame.commands {
            switch command {
            case .fillPath(let fill):
                if let bitmapCommand = degradedDrawBitmap(
                    path: fill.path,
                    fillColor: fill.color,
                    strokeColor: .clear,
                    strokeStyle: StrokeStyle(lineWidth: 0),
                    clipRect: fill.clipRect,
                    scaleFactor: scale
                ) {
                    commands.append(.drawBitmap(bitmapCommand))
                }

            case .strokePath(let stroke):
                if let bitmapCommand = degradedDrawBitmap(
                    path: stroke.path,
                    fillColor: .clear,
                    strokeColor: stroke.color,
                    strokeStyle: stroke.style,
                    clipRect: stroke.clipRect,
                    scaleFactor: scale
                ) {
                    commands.append(.drawBitmap(bitmapCommand))
                }

            default:
                commands.append(command)
            }
        }

        return RenderFrame(clearColor: frame.clearColor, commands: commands)
    }

    /// Commands in `frame` that a `fillRect` + `drawBitmap` frame backend
    /// cannot paint even after `degradingPathsToBitmaps` (today: `applyBlur`
    /// and `drawText`, which no frame-path producer currently emits).
    /// Diagnostics and tests use this to assert the readable-degradation
    /// contract: everything else in a frame is guaranteed paintable.
    public static func unpaintableCommandsAfterDegradation(
        in frame: RenderFrame,
        scaleFactor: Double = 1.0
    ) -> [RenderCommand] {
        degradingPathsToBitmaps(in: frame, scaleFactor: scaleFactor).commands.filter(\.isReservedCommand)
    }

    /// Rasterizes one path command into a `drawBitmap` covering the path's
    /// (clip-masked) bounds, or `nil` when the path has no paintable
    /// footprint (empty geometry, fully transparent paint, empty clip) —
    /// dropping the command entirely matches the scene bridge's
    /// empty-clip suppression semantics.
    private static func degradedDrawBitmap(
        path: RenderPath,
        fillColor: Color,
        strokeColor: Color,
        strokeStyle: StrokeStyle,
        clipRect: Rect?,
        scaleFactor: Double
    ) -> DrawBitmapCommand? {
        let lineWidth = strokeStyle.lineWidth
        // A stroke with no width paints nothing (matches ScenePainter's
        // `style.lineWidth > 0` guard); a clear fill likewise.
        guard fillColor.alpha > 0 || (strokeColor.alpha > 0 && lineWidth > 0) else {
            return nil
        }
        guard let pathBounds = path.segments.boundingRect else {
            return nil
        }

        // `pathBounds` is logical, so the outset is measured on logical
        // elements and the whole rect is scaled once, below.
        let logicalElements = path.segments.map { $0.asPathElement(scaledBy: 1) }
        let elements = path.segments.map { $0.asPathElement(scaledBy: scaleFactor) }
        // Strokes can have zero-thickness bounds (e.g. a straight line), so
        // outset before the empty check — mirrors ScenePainter's strokeBounds,
        // caps and joins included.
        let strokeOutset =
            strokeColor.alpha > 0
            ? StrokeOutlineGeometry.boundsOutset(
                forElements: logicalElements,
                lineWidth: max(lineWidth, 0), lineCap: strokeStyle.lineCap,
                lineJoin: strokeStyle.lineJoin, miterLimit: strokeStyle.miterLimit)
            : 0
        let logicalBounds = pathBounds.outset(by: strokeOutset)
        guard !logicalBounds.isEmpty else {
            return nil
        }

        let primitive = PathPrimitive(
            elements: elements,
            bounds: logicalBounds.scaled(by: scaleFactor),
            fillColor: fillColor,
            strokeColor: strokeColor,
            lineWidth: lineWidth * scaleFactor,
            lineCap: strokeStyle.lineCap,
            lineJoin: strokeStyle.lineJoin,
            miterLimit: strokeStyle.miterLimit,
            clipBounds: clipRect?.scaled(by: scaleFactor)
        )
        guard let maskedBounds = primitive.contentMaskedBounds, !maskedBounds.isEmpty,
            let bitmap = GPUIRawSceneRasterizer.rasterizePath(primitive)
        else {
            return nil
        }

        // The frame backends draw bitmaps 1:1 against physical pixels and take
        // the draw origin from the command rect (see makeLogicalBitmapRect /
        // makePixelAlignedBitmapRect in D3D11Renderer), so report the masked
        // origin back in logical coordinates.
        return DrawBitmapCommand(
            rect: Rect(
                x: maskedBounds.origin.x / scaleFactor,
                y: maskedBounds.origin.y / scaleFactor,
                width: Double(bitmap.width) / scaleFactor,
                height: Double(bitmap.height) / scaleFactor
            ),
            bitmap: bitmap,
            opacity: 1,
            clipRect: clipRect
        )
    }
}

extension RenderCommand {
    /// `fillPath` / `strokePath` — paintable on frame backends only after
    /// `FramePathDegradation` rewrites them as bitmaps.
    fileprivate var isPathCommand: Bool {
        switch self {
        case .fillPath, .strokePath:
            return true
        case .fillRect, .drawBitmap, .applyBlur, .drawText, .pushClip, .popClip:
            return false
        }
    }

    /// Reserved commands no frame backend paints (soft-skipped with
    /// diagnostics).
    fileprivate var isReservedCommand: Bool {
        switch self {
        case .applyBlur, .drawText:
            return true
        case .fillRect, .drawBitmap, .fillPath, .strokePath, .pushClip, .popClip:
            return false
        }
    }
}

extension RenderPath.Segment {
    /// Converts to the scene primitive element type, scaling geometry into
    /// device pixels for rasterization. Mirrors the segment mapping in
    /// `GPUISceneBridge`.
    fileprivate func asPathElement(scaledBy scale: Double) -> PathElement {
        func scaled(_ point: Point) -> Point {
            point.scaled(by: scale)
        }

        switch self {
        case .moveTo(let p):
            return .moveTo(scaled(p))
        case .lineTo(let p):
            return .lineTo(scaled(p))
        case .quadCurveTo(let control, let end):
            return .quadraticCurveTo(control: scaled(control), end: scaled(end))
        case .cubicCurveTo(let control1, let control2, let end):
            return .cubicCurveTo(control1: scaled(control1), control2: scaled(control2), end: scaled(end))
        case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
            return .arc(
                center: scaled(center),
                radius: radius * scale,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: clockwise
            )
        case .close:
            return .close
        }
    }
}
