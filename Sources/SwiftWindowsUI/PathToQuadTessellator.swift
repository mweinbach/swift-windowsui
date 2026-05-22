import SwiftWindowsCore
import SwiftWindowsGraphics

/// Attempts to tessellate a `PathPrimitive` into a series of axis-aligned
/// `QuadPrimitive`s so the path can render entirely on the GPU via the
/// existing structured-buffer instance pipeline, bypassing
/// `GPUIRawSceneRasterizer.rasterizePath` (CPU rasterization +
/// texture-per-frame upload).
///
/// This is a deliberately narrow first step in the GPU path tessellator
/// roadmap. We only handle:
///
/// - **Stroked paths** consisting entirely of `.moveTo` + `.lineTo` + `.close`
///   segments, where every line segment is axis-aligned (purely horizontal
///   or purely vertical). Each axis-aligned segment becomes one quad.
/// - **Filled paths** that describe exactly one axis-aligned rectangle
///   (`moveTo + 3×lineTo + close` forming a closed rect). The rect becomes
///   a single quad.
///
/// Anything else — diagonal strokes, curved segments, arcs, multi-region
/// filled paths — returns `nil` and falls back to the CPU rasterization
/// path. Curved-path tessellation will follow in a future change.
enum PathToQuadTessellator {

    /// Returns axis-aligned quads that cover `path`, or `nil` if the path
    /// can't be tessellated by this pass.
    static func tessellate(_ path: PathPrimitive) -> [QuadPrimitive]? {
        // Fill-only path: only handle paths that describe an axis-aligned
        // closed rectangle.
        if path.fillColor.alpha > 0, path.strokeColor.alpha == 0 || path.lineWidth <= 0 {
            return rectFill(for: path)
        }

        // Stroke-only path: try axis-aligned stroked-line tessellation.
        if path.strokeColor.alpha > 0, path.lineWidth > 0,
            path.fillColor.alpha == 0
        {
            return axisAlignedStrokedLines(for: path)
        }

        return nil
    }

    private static func rectFill(for path: PathPrimitive) -> [QuadPrimitive]? {
        // Collect points from a `moveTo … lineTo … close` sequence and check
        // whether they describe the four corners of an axis-aligned rect.
        var points: [Point] = []
        var didMove = false
        for element in path.elements {
            switch element {
            case .moveTo(let p):
                guard !didMove else { return nil }
                didMove = true
                points.append(p)
            case .lineTo(let p):
                points.append(p)
            case .close:
                break
            case .quadraticCurveTo, .cubicCurveTo, .arc:
                return nil
            }
        }
        guard points.count == 4 || points.count == 5 else { return nil }
        // If the path explicitly repeats the first point at the end, drop
        // it. Either way we should now have exactly 4 distinct corners.
        if points.count == 5, points.first == points.last {
            points.removeLast()
        }
        guard points.count == 4 else { return nil }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
            let minY = ys.min(), let maxY = ys.max()
        else { return nil }

        // The set of {x} must be {minX, maxX} and {y} must be {minY, maxY}
        // for the four points to form an axis-aligned rect.
        let uniqueX = Set(xs)
        let uniqueY = Set(ys)
        guard uniqueX.count == 2, uniqueY.count == 2,
            uniqueX.contains(minX), uniqueX.contains(maxX),
            uniqueY.contains(minY), uniqueY.contains(maxY)
        else { return nil }

        let rect = Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return [quad(for: rect, color: path.fillColor, clip: path.clipBounds)]
    }

    private static func axisAlignedStrokedLines(for path: PathPrimitive) -> [QuadPrimitive]? {
        var cursor: Point?
        var subpathStart: Point?
        var quads: [QuadPrimitive] = []

        for element in path.elements {
            switch element {
            case .moveTo(let p):
                cursor = p
                subpathStart = p
            case .lineTo(let p):
                guard let from = cursor else { return nil }
                guard
                    let segment = strokedSegmentQuad(
                        from: from, to: p, lineWidth: path.lineWidth,
                        color: path.strokeColor, clip: path.clipBounds)
                else { return nil }
                quads.append(segment)
                cursor = p
            case .close:
                guard let from = cursor, let start = subpathStart, from != start else {
                    continue
                }
                guard
                    let segment = strokedSegmentQuad(
                        from: from, to: start, lineWidth: path.lineWidth,
                        color: path.strokeColor, clip: path.clipBounds)
                else { return nil }
                quads.append(segment)
                cursor = start
            case .quadraticCurveTo, .cubicCurveTo, .arc:
                return nil
            }
        }

        return quads.isEmpty ? nil : quads
    }

    private static func strokedSegmentQuad(
        from: Point, to: Point, lineWidth: Double, color: Color, clip: Rect?
    ) -> QuadPrimitive? {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let isHorizontal = abs(dy) < 0.001 && abs(dx) >= 0.001
        let isVertical = abs(dx) < 0.001 && abs(dy) >= 0.001
        guard isHorizontal || isVertical else {
            return nil
        }

        let halfWidth = lineWidth / 2
        let rect: Rect
        if isHorizontal {
            let minX = min(from.x, to.x)
            let maxX = max(from.x, to.x)
            rect = Rect(
                x: minX - halfWidth,
                y: from.y - halfWidth,
                width: (maxX - minX) + lineWidth,
                height: lineWidth
            )
        } else {
            let minY = min(from.y, to.y)
            let maxY = max(from.y, to.y)
            rect = Rect(
                x: from.x - halfWidth,
                y: minY - halfWidth,
                width: lineWidth,
                height: (maxY - minY) + lineWidth
            )
        }
        return quad(for: rect, color: color, clip: clip)
    }

    private static func quad(for rect: Rect, color: Color, clip: Rect?) -> QuadPrimitive {
        let clipRect = clip ?? Rect(x: 0, y: 0, width: 0, height: 0)
        return QuadPrimitive(
            x: Float(rect.origin.x),
            y: Float(rect.origin.y),
            width: Float(rect.size.width),
            height: Float(rect.size.height),
            cornerRadius: 0,
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha,
            gradientAxis: 0,
            clipX: Float(clipRect.origin.x),
            clipY: Float(clipRect.origin.y),
            clipWidth: Float(clipRect.size.width),
            clipHeight: Float(clipRect.size.height),
            clipCornerRadius: 0,
            blendMode: 0,
            effectType: 0,
            effectIntensity: 0,
            blurRadius: 0,
            blurOpaque: 0,
            effectParam1: 0,
            effectParam2: 0,
            effectParam3: 0,
            effectParam4: 0
        )
    }
}
