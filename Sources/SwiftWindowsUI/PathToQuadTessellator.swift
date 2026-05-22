import Foundation

import SwiftWindowsCore
import SwiftWindowsGraphics

/// Attempts to tessellate a `PathPrimitive` into a series of axis-aligned
/// `QuadPrimitive`s so the path can render entirely on the GPU via the
/// existing structured-buffer instance pipeline, bypassing
/// `GPUIRawSceneRasterizer.rasterizePath` (CPU rasterization +
/// texture-per-frame upload).
///
/// Coverage:
///
/// - **Stroked paths** consisting of `.moveTo` + `.lineTo` + `.close` plus
///   `.quadraticCurveTo` / `.cubicCurveTo` / `.arc`. Curves and arcs are
///   adaptively subdivided into short line segments; if every resulting
///   line segment is axis-aligned (purely horizontal or vertical) the
///   path is emitted as one quad per segment. Curves whose subdivisions
///   produce diagonal pieces fall through to CPU.
/// - **Filled paths** that describe exactly one axis-aligned rectangle
///   (`moveTo + 3×lineTo + close` forming a closed rect). The rect
///   becomes a single quad.
///
/// Anything else — diagonal strokes, non-axis-aligned curved geometry,
/// arbitrary filled shapes, paths that combine fill + stroke — returns
/// `nil` and falls back to the CPU rasterization path. Rotated-quad
/// support and full convex polygon triangulation remain on the
/// roadmap.
enum PathToQuadTessellator {

    /// Number of line segments produced when sampling a curve or arc.
    /// 16 is enough to detect axis-alignment for the common cases
    /// (degenerate beziers, axis-aligned arcs) without flooding the
    /// quad buffer for genuinely curved geometry that's going to fail
    /// the axis-aligned check anyway.
    private static let curveSubdivisions = 16

    /// Mixed-emission result. `quads` cover the axis-aligned portions
    /// of the input path (rendered purely on the GPU); `residualPath`,
    /// when non-nil, contains the diagonal/curved fragments that still
    /// need CPU rasterization. Both can be populated for a single
    /// input path so partially-tessellatable paths still get
    /// per-segment GPU promotion instead of an all-or-nothing fallback.
    struct Result: Equatable {
        var quads: [QuadPrimitive]
        var residualPath: PathPrimitive?

        static let empty = Result(quads: [], residualPath: nil)
    }

    /// Returns axis-aligned quads that cover `path`, or `nil` if the path
    /// can't be tessellated by this pass.
    static func tessellate(_ path: PathPrimitive) -> [QuadPrimitive]? {
        guard let mixed = tessellateMixed(path), mixed.residualPath == nil else {
            return nil
        }
        return mixed.quads.isEmpty ? nil : mixed.quads
    }

    /// Mixed-output entry point: emits as many axis-aligned segments as
    /// possible as GPU quads, packaging the remaining diagonal/curved
    /// fragments into a residual `PathPrimitive` that still goes to
    /// CPU. Returns nil when the input contributes nothing tessellatable
    /// at all (so the caller falls back to a single CPU path primitive).
    static func tessellateMixed(_ path: PathPrimitive) -> Result? {
        // Fill-only path: rect-fill is the only fill case we handle, and
        // it's all-or-nothing — a non-rectangular fill can't be partially
        // promoted because the interior region matters.
        if path.fillColor.alpha > 0, path.strokeColor.alpha == 0 || path.lineWidth <= 0 {
            guard let quads = rectFill(for: path) else { return nil }
            return Result(quads: quads, residualPath: nil)
        }

        // Stroke-only path: per-segment promotion. Axis-aligned segments
        // become quads; diagonal/curved residue goes back to a CPU path.
        if path.strokeColor.alpha > 0, path.lineWidth > 0,
            path.fillColor.alpha == 0
        {
            return axisAlignedStrokedLinesMixed(for: path)
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

    /// Mixed-output stroked-line tessellator. Walks the path
    /// segment-by-segment; axis-aligned segments become GPU quads,
    /// diagonal/curved segments are collected into a residual stroked
    /// `PathPrimitive`. Returns the combined result, or nil if neither
    /// a quad nor a residual segment was produced.
    private static func axisAlignedStrokedLinesMixed(for path: PathPrimitive) -> Result? {
        var cursor: Point?
        var subpathStart: Point?
        var quads: [QuadPrimitive] = []
        var residualSegments: [(from: Point, to: Point)] = []

        func appendStraightSegments(through points: [Point]) {
            guard let start = cursor else { return }
            var previous = start
            for next in points {
                if previous == next { continue }
                if let segment = strokedSegmentQuad(
                    from: previous, to: next, lineWidth: path.lineWidth,
                    color: path.strokeColor, clip: path.clipBounds)
                {
                    quads.append(segment)
                } else {
                    residualSegments.append((previous, next))
                }
                previous = next
            }
            cursor = previous
        }

        for element in path.elements {
            switch element {
            case .moveTo(let p):
                cursor = p
                subpathStart = p
            case .lineTo(let p):
                appendStraightSegments(through: [p])
            case .close:
                guard let from = cursor, let start = subpathStart, from != start else {
                    continue
                }
                appendStraightSegments(through: [start])
            case .quadraticCurveTo(let control, let end):
                guard cursor != nil else { return nil }
                let samples = sampleQuadratic(from: cursor!, control: control, end: end)
                appendStraightSegments(through: samples)
            case .cubicCurveTo(let c1, let c2, let end):
                guard cursor != nil else { return nil }
                let samples = sampleCubic(
                    from: cursor!, control1: c1, control2: c2, end: end)
                appendStraightSegments(through: samples)
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                let samples = sampleArc(
                    center: center, radius: radius,
                    startAngle: startAngle, endAngle: endAngle,
                    clockwise: clockwise)
                if cursor == nil, let first = samples.first {
                    cursor = first
                    subpathStart = first
                }
                appendStraightSegments(through: samples)
            }
        }

        if quads.isEmpty && residualSegments.isEmpty {
            return nil
        }

        // Build the residual path from the leftover diagonal/curved
        // fragments. Each fragment becomes a moveTo + lineTo; the
        // residual is rendered by the CPU rasterizer with the same
        // stroke style and clip as the original.
        let residualPath: PathPrimitive?
        if residualSegments.isEmpty {
            residualPath = nil
        } else {
            var elements: [PathElement] = []
            for segment in residualSegments {
                elements.append(.moveTo(segment.from))
                elements.append(.lineTo(segment.to))
            }
            // Compute residual bounds for the painter's clip/visibility
            // checks; outset by half-lineWidth so a zero-thickness
            // diagonal bounding box still has area.
            let allPoints = residualSegments.flatMap { [$0.from, $0.to] }
            let minX = allPoints.map(\.x).min() ?? 0
            let minY = allPoints.map(\.y).min() ?? 0
            let maxX = allPoints.map(\.x).max() ?? 0
            let maxY = allPoints.map(\.y).max() ?? 0
            let rawBounds = Rect(
                x: minX, y: minY,
                width: max(0, maxX - minX), height: max(0, maxY - minY))
            residualPath = PathPrimitive(
                elements: elements,
                bounds: rawBounds.outset(by: path.lineWidth / 2),
                strokeColor: path.strokeColor,
                lineWidth: path.lineWidth,
                clipBounds: path.clipBounds
            )
        }

        return Result(quads: quads, residualPath: residualPath)
    }

    // MARK: - Curve sampling

    private static func sampleQuadratic(from: Point, control: Point, end: Point) -> [Point] {
        var points: [Point] = []
        points.reserveCapacity(curveSubdivisions)
        let n = curveSubdivisions
        for step in 1...n {
            let t = Double(step) / Double(n)
            let mt = 1 - t
            let x = mt * mt * from.x + 2 * mt * t * control.x + t * t * end.x
            let y = mt * mt * from.y + 2 * mt * t * control.y + t * t * end.y
            points.append(Point(x: x, y: y))
        }
        return points
    }

    private static func sampleCubic(from: Point, control1: Point, control2: Point, end: Point) -> [Point] {
        var points: [Point] = []
        points.reserveCapacity(curveSubdivisions)
        let n = curveSubdivisions
        for step in 1...n {
            let t = Double(step) / Double(n)
            let mt = 1 - t
            let mt2 = mt * mt
            let t2 = t * t
            let x = mt2 * mt * from.x + 3 * mt2 * t * control1.x + 3 * mt * t2 * control2.x + t2 * t * end.x
            let y = mt2 * mt * from.y + 3 * mt2 * t * control1.y + 3 * mt * t2 * control2.y + t2 * t * end.y
            points.append(Point(x: x, y: y))
        }
        return points
    }

    private static func sampleArc(
        center: Point, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool
    ) -> [Point] {
        var sweep = endAngle - startAngle
        if clockwise {
            if sweep > 0 { sweep -= 2 * .pi }
        } else {
            if sweep < 0 { sweep += 2 * .pi }
        }
        var points: [Point] = []
        points.reserveCapacity(curveSubdivisions + 1)
        // Include the start point so the very first segment of the arc
        // has a fromPoint relative to the actual arc curve, not an
        // arbitrary prior cursor.
        let totalSamples = curveSubdivisions
        for step in 0...totalSamples {
            let t = Double(step) / Double(totalSamples)
            let angle = startAngle + sweep * t
            points.append(Point(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
        }
        return points
    }

    private static func strokedSegmentQuad(
        from: Point, to: Point, lineWidth: Double, color: Color, clip: Rect?
    ) -> QuadPrimitive? {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.001 else {
            return nil
        }

        let isHorizontal = abs(dy) < 0.001 && abs(dx) >= 0.001
        let isVertical = abs(dx) < 0.001 && abs(dy) >= 0.001

        let halfWidth = lineWidth / 2
        if isHorizontal {
            let minX = min(from.x, to.x)
            let maxX = max(from.x, to.x)
            let rect = Rect(
                x: minX - halfWidth,
                y: from.y - halfWidth,
                width: (maxX - minX) + lineWidth,
                height: lineWidth
            )
            return quad(for: rect, color: color, clip: clip)
        }
        if isVertical {
            let minY = min(from.y, to.y)
            let maxY = max(from.y, to.y)
            let rect = Rect(
                x: from.x - halfWidth,
                y: minY - halfWidth,
                width: lineWidth,
                height: (maxY - minY) + lineWidth
            )
            return quad(for: rect, color: color, clip: clip)
        }

        // Diagonal segment: emit a rotated quad. The unrotated rect
        // covers `length + lineWidth` along the x-axis with `lineWidth`
        // thickness; rotating around its centre by atan2(dy, dx) aligns
        // it with the segment.
        let midX = (from.x + to.x) * 0.5
        let midY = (from.y + to.y) * 0.5
        let extendedLength = length + lineWidth
        let rect = Rect(
            x: midX - extendedLength * 0.5,
            y: midY - halfWidth,
            width: extendedLength,
            height: lineWidth
        )
        let angle = atan2(dy, dx)
        return quad(for: rect, color: color, clip: clip, rotation: Float(angle))
    }

    private static func quad(
        for rect: Rect, color: Color, clip: Rect?, rotation: Float = 0
    ) -> QuadPrimitive {
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
            effectParam4: 0,
            rotationRadians: rotation
        )
    }
}
