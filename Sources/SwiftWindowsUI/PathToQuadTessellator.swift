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
///   subdivided into short line segments; each becomes one quad, unrotated
///   when the segment is axis-aligned and rotated otherwise. Caps and joins
///   are honoured exactly — butt, square and round ends, right-angle miters
///   and round joins — and a join the quad family cannot draw exactly (a
///   bevel, or a miter at any other angle) becomes one wedge in
///   `residualPath` for the CPU stroker, which draws every style. Only a
///   *translucent* stroke still sends the whole path there, because a wedge
///   overlaps the bodies it joins.
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

    /// Largest number of scanline rows a single triangle may emit. The strip
    /// fill produces one quad per row, so an outlier vertex at `y = 2_000_000`
    /// used to cost ~2 M `QuadPrimitive`s (≈288 MB) and 2 M bounds-tree inserts
    /// per frame — all of them discarded by the clip. Past the budget the path
    /// falls back to CPU rasterization, which is bounded by the surface.
    private static let maxScanlineRows = 8_192

    /// Largest number of quads one path may tessellate into across all of its
    /// triangles. Bounds fan and ear-clipped fills, where no single triangle
    /// need be pathological for the total to be.
    private static let maxTessellatedQuads = 65_536

    /// Largest polygon the ear clipper will attempt. Ear clipping is O(n³) in
    /// vertices, and `sampleClosedFillBoundary` multiplies every curve by
    /// `curveSubdivisions`, so a 300-segment concave area-chart path arrives
    /// with ~4 800 vertices — ~10¹¹ containment tests. Bigger polygons go to
    /// the CPU rasterizer, which is linear in area.
    private static let maxEarClipVertices = 256

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
    static func tessellate(_ path: PathPrimitive, surfaceSize: Size? = nil) -> [QuadPrimitive]? {
        guard let mixed = tessellateMixed(path, surfaceSize: surfaceSize), mixed.residualPath == nil else {
            return nil
        }
        return mixed.quads.isEmpty ? nil : mixed.quads
    }

    /// Mixed-output entry point: emits as many axis-aligned segments as
    /// possible as GPU quads, packaging the remaining diagonal/curved
    /// fragments into a residual `PathPrimitive` that still goes to
    /// CPU. Returns nil when the input contributes nothing tessellatable
    /// at all (so the caller falls back to a single CPU path primitive).
    /// The optional target is in the same coordinate space as the path.
    static func tessellateMixed(_ path: PathPrimitive, surfaceSize: Size? = nil) -> Result? {
        // Geometry helpers keep their existing decisions and budgets. Lower
        // the complete clip once at their shared exit, including scanline
        // strips, stroke bodies/discs and residual join paths.
        func radius(_ value: Double) -> Float {
            value.isFinite ? Float(min(max(0, value), Double(GPUISceneLimits.maxCoordinate))) : 0
        }
        let hasExplicitRadii =
            (path.clipCornerRadiusTopLeft.isFinite && path.clipCornerRadiusTopLeft > 0)
            || (path.clipCornerRadiusTopRight.isFinite && path.clipCornerRadiusTopRight > 0)
            || (path.clipCornerRadiusBottomRight.isFinite && path.clipCornerRadiusBottomRight > 0)
            || (path.clipCornerRadiusBottomLeft.isFinite && path.clipCornerRadiusBottomLeft > 0)
        let topLeft = radius(path.clipCornerRadiusTopLeft)
        let topRight = radius(path.clipCornerRadiusTopRight)
        let bottomRight = radius(path.clipCornerRadiusBottomRight)
        let bottomLeft = radius(path.clipCornerRadiusBottomLeft)
        let hasConvertedRadii = topLeft > 0 || topRight > 0 || bottomRight > 0 || bottomLeft > 0
        let uniform = radius(path.clipCornerRadius)
        let usesTargetClip =
            path.clipBounds == nil
            && (hasExplicitRadii || uniform > 0 || path.clipShapeBounds != nil)
        if usesTargetClip {
            // Unlike packed quads, a path with no clip rect can round its
            // render target. Without that target, retaining the path is the
            // only representation that does not silently discard its clip.
            guard let surfaceSize, surfaceSize.width.isFinite, surfaceSize.height.isFinite,
                surfaceSize.width > 0, surfaceSize.height > 0
            else { return nil }
        }
        guard var result = tessellateGeometry(path) else { return nil }
        for index in result.quads.indices {
            if usesTargetClip, let surfaceSize {
                result.quads[index].contentMask = GPUIContentMask(bounds: Rect(origin: .zero, size: surfaceSize))
            }
            // Select C in the Path's Double space, before Float conversion.
            // If every selected radius underflows, preserve its square limit
            // rather than reactivating the legacy scalar fallback.
            if hasExplicitRadii && !hasConvertedRadii {
                result.quads[index].clipCornerRadius = 0
            }
            // Otherwise helper scalar bytes stay unchanged, including the old
            // scanline helpers whose scalar field remained zero. The current
            // scalar resolves into C only when no explicit Path radius exists.
            result.quads[index].clipCornerRadiusTopLeft = hasExplicitRadii ? topLeft : uniform
            result.quads[index].clipCornerRadiusTopRight = hasExplicitRadii ? topRight : uniform
            result.quads[index].clipCornerRadiusBottomRight = hasExplicitRadii ? bottomRight : uniform
            result.quads[index].clipCornerRadiusBottomLeft = hasExplicitRadii ? bottomLeft : uniform
            result.quads[index].clipShapeBounds = path.clipShapeBounds
        }
        if var residual = result.residualPath {
            residual.clipCornerRadiusTopLeft = path.clipCornerRadiusTopLeft
            residual.clipCornerRadiusTopRight = path.clipCornerRadiusTopRight
            residual.clipCornerRadiusBottomRight = path.clipCornerRadiusBottomRight
            residual.clipCornerRadiusBottomLeft = path.clipCornerRadiusBottomLeft
            residual.clipShapeBounds = path.clipShapeBounds
            result.residualPath = residual
        }
        return result
    }

    private static func tessellateGeometry(_ path: PathPrimitive) -> Result? {
        // Reject any path whose vertex stream contains a non-finite
        // coordinate. Downstream we do `Int(floor(y))` on vertex y for
        // scanline strip allocation, which traps on Inf/NaN. Bailing
        // here keeps the renderer crash-free when an app feeds garbage
        // through Path APIs.
        guard pathHasFiniteCoordinates(path) else { return nil }

        // Fill-only path: try rect → triangle → convex polygon (fan
        // triangulated) → concave polygon (ear-clipped). Only
        // self-intersecting or otherwise pathological paths still
        // fall through.
        if path.fillColor.alpha > 0, path.strokeColor.alpha == 0 || path.lineWidth <= 0 {
            // These quad routes describe one contour. A close followed by
            // more drawing, or a second move, must retain the full coverage
            // path when its crossings decide an even-odd hole.
            if path.fillRule == .evenOdd, !hasOneFillContour(path.elements) { return nil }
            if let rectQuads = rectFill(for: path) {
                return Result(quads: rectQuads, residualPath: nil)
            }
            if let roundedQuads = roundedRectFill(for: path) {
                return Result(quads: roundedQuads, residualPath: nil)
            }
            if let triQuads = triangleFill(for: path) {
                return Result(quads: triQuads, residualPath: nil)
            }
            // Equal turn signs alone do not prove a simple polygon: a
            // pentagram passes that test. Keep bounded, provably simple
            // straight polygons on the existing GPU routes; ambiguous curves
            // and intersecting contours use the shared cached coverage path.
            if path.fillRule == .evenOdd, !hasSimpleStraightFillBoundary(path.elements) { return nil }
            if let polyQuads = convexPolygonFill(for: path) {
                return Result(quads: polyQuads, residualPath: nil)
            }
            if let earQuads = earClippedPolygonFill(for: path) {
                return Result(quads: earQuads, residualPath: nil)
            }
            return nil
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

    private static func hasOneFillContour(_ elements: [PathElement]) -> Bool {
        guard case .moveTo? = elements.first else { return false }
        for index in elements.indices {
            switch elements[index] {
            case .moveTo where index != elements.startIndex:
                return false
            case .close where index != elements.endIndex - 1:
                return false
            default:
                break
            }
        }
        return true
    }

    /// The proof budget is the existing ear-clip vertex limit. No topology
    /// test may turn a large authored path into an unbounded pairwise walk.
    private static func hasSimpleStraightFillBoundary(_ elements: [PathElement]) -> Bool {
        guard elements.count <= maxEarClipVertices + 2 else { return false }
        for element in elements {
            switch element {
            case .moveTo, .lineTo, .close:
                break
            case .quadraticCurveTo, .cubicCurveTo, .arc:
                return false
            }
        }
        guard let points = sampleClosedFillBoundary(elements: elements),
            points.count >= 3, points.count <= maxEarClipVertices
        else { return false }

        func orientation(_ a: Point, _ b: Point, _ c: Point) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }

        for first in points.indices {
            let a = points[first]
            let b = points[(first + 1) % points.count]
            guard a != b else { return false }
            for second in (first + 1)..<points.count {
                if second == first + 1 || (first == 0 && second == points.count - 1) { continue }
                let c = points[second]
                let d = points[(second + 1) % points.count]
                if max(a.x, b.x) < min(c.x, d.x) || max(c.x, d.x) < min(a.x, b.x)
                    || max(a.y, b.y) < min(c.y, d.y) || max(c.y, d.y) < min(a.y, b.y)
                {
                    continue
                }
                let abC = orientation(a, b, c)
                let abD = orientation(a, b, d)
                let cdA = orientation(c, d, a)
                let cdB = orientation(c, d, b)
                guard abC.isFinite, abD.isFinite, cdA.isFinite, cdB.isFinite else { return false }
                if ((abC <= 0 && abD >= 0) || (abC >= 0 && abD <= 0))
                    && ((cdA <= 0 && cdB >= 0) || (cdA >= 0 && cdB <= 0))
                {
                    return false
                }
            }
        }
        return true
    }

    /// Scanline-tessellates a triangle fill into a series of 1-pixel-tall
    /// axis-aligned `QuadPrimitive`s. Each scanline becomes a horizontal
    /// strip running between the triangle's left and right edges at that
    /// row. Returns nil if the path isn't a triangle (3 vertices + close
    /// or 3 vertices + closing-point + close) or if all three vertices
    /// are colinear (degenerate, zero area).
    private static func triangleFill(for path: PathPrimitive) -> [QuadPrimitive]? {
        // Extract the three vertices from a simple closed path.
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
        // Accept "moveTo + 2 lineTo (+ close)" or
        // "moveTo + 2 lineTo + closing-point (+ close)".
        if points.count == 4, points.first == points.last {
            points.removeLast()
        }
        guard points.count == 3 else { return nil }

        let v0 = points[0]
        let v1 = points[1]
        let v2 = points[2]
        // Twice the signed area; if zero the triangle is degenerate
        // (vertices colinear).
        let area2 = (v1.x - v0.x) * (v2.y - v0.y) - (v2.x - v0.x) * (v1.y - v0.y)
        guard abs(area2) > 0.001 else { return nil }

        guard
            let quads = scanlineFillTriangle(
                v0: v0, v1: v1, v2: v2, color: path.fillColor, clip: path.clipBounds,
                clipCornerRadius: path.clipCornerRadius)
        else {
            return nil
        }
        return quads.isEmpty ? nil : quads
    }

    /// Scanline-tessellates a convex polygon as **one** figure: for each
    /// row, the span between the leftmost and rightmost edge crossing.
    /// Curves in the path are first subdivided into line segments so
    /// RoundedRectangle, Circle, Capsule, and other curved closed shapes
    /// also qualify. Returns nil if the path can't be expressed as a simple
    /// convex polygon (concave, self-intersecting, or non-closed).
    ///
    /// This used to fan the polygon from vertex 0 into N-2 triangles and fill
    /// each separately. Two neighbouring triangles then computed their spans
    /// independently and each dropped its sub-pixel sliver (the
    /// `> 0.5` span test that keeps a strip from degenerating), so every
    /// shared fan edge came out as a hairline of background *through the
    /// fill* — a rounded chart bar arrived with a diagonal scratch from
    /// corner to corner. A convex polygon crosses any scanline exactly twice,
    /// so the span is min..max over all edges and there are no interior edges
    /// left to leak. It is also strictly fewer quads than the fan.
    private static func convexPolygonFill(for path: PathPrimitive) -> [QuadPrimitive]? {
        guard let polygonVertices = sampleClosedFillBoundary(elements: path.elements) else {
            return nil
        }
        guard polygonVertices.count >= 4 else { return nil }
        guard isConvex(polygonVertices) else { return nil }

        guard
            let quads = scanlineFillConvexPolygon(
                polygonVertices,
                color: path.fillColor,
                clip: path.clipBounds,
                clipCornerRadius: path.clipCornerRadius
            ),
            quads.count <= maxTessellatedQuads
        else {
            return nil
        }
        return quads.isEmpty ? nil : quads
    }

    /// One horizontal strip per row between the polygon's outermost edge
    /// crossings. Same budget rules as `scanlineFillTriangle`: an empty
    /// array for a fully-clipped or degenerate polygon, `nil` past the row
    /// budget or when unit row steps are not representable so the caller
    /// abandons GPU promotion for the whole path.
    private static func scanlineFillConvexPolygon(
        _ vertices: [Point], color: Color, clip: Rect?, clipCornerRadius: Double = 0
    ) -> [QuadPrimitive]? {
        var minY = Double.infinity
        var maxY = -Double.infinity
        for vertex in vertices {
            minY = min(minY, vertex.y)
            maxY = max(maxY, vertex.y)
        }
        guard minY.isFinite, maxY.isFinite else { return [] }
        minY = floor(minY)
        maxY = ceil(maxY)
        if let clip, clip.size.width > 0, clip.size.height > 0 {
            minY = max(minY, floor(clip.minY))
            maxY = min(maxY, ceil(clip.maxY))
        }
        guard maxY > minY else { return [] }
        let rowCount = GPUISceneValue.int(maxY - minY)
        guard rowCount > 0, rowCount <= maxScanlineRows else { return nil }

        var quads: [QuadPrimitive] = []
        quads.reserveCapacity(rowCount + 1)
        var y = minY
        for _ in 0..<rowCount {
            let nextY = y + 1
            guard nextY.isFinite, nextY - y == 1 else { return nil }
            let scanY = y + 0.5
            var left = Double.infinity
            var right = -Double.infinity
            var index = 0
            while index < vertices.count {
                let a = vertices[index]
                let b = vertices[(index + 1) % vertices.count]
                if let xAtY = intersectX(edgeStart: a, edgeEnd: b, atY: scanY) {
                    left = min(left, xAtY)
                    right = max(right, xAtY)
                }
                index += 1
            }
            if left.isFinite, right.isFinite, right - left > 0.5 {
                quads.append(
                    quad(for: Rect(x: left, y: y, width: right - left, height: 1), color: color, clip: clip))
            }
            y = nextY
        }
        return quads
    }

    /// Ear-clipping triangulation for **simple** concave polygons.
    /// Repeatedly finds a "convex" vertex whose triangle (prev, v, next)
    /// is entirely inside the polygon (i.e. doesn't contain any other
    /// vertex), emits that triangle as scanline strips, and removes
    /// the vertex. Continues until 3 vertices remain.
    ///
    /// Falls through when the polygon is degenerate, self-intersecting,
    /// or the algorithm can't find an ear (which only happens for
    /// non-simple polygons in this implementation).
    private static func earClippedPolygonFill(for path: PathPrimitive) -> [QuadPrimitive]? {
        guard let raw = sampleClosedFillBoundary(elements: path.elements) else {
            return nil
        }
        guard raw.count >= 4, raw.count <= maxEarClipVertices else { return nil }

        // Polygon winding sign — used to identify "convex" (interior)
        // vertices regardless of overall winding direction.
        var indices = Array(raw.indices)
        let windingSign = polygonWindingSign(raw)
        guard windingSign != 0 else { return nil }

        var quads: [QuadPrimitive] = []
        // Cap iterations so a pathological polygon can't loop forever;
        // each successful ear removal shrinks the polygon by one vertex,
        // so 4×N rounds is plenty.
        let maxIterations = raw.count * 4
        var iteration = 0
        while indices.count > 3, iteration < maxIterations {
            iteration += 1
            var clipped = false
            for i in 0..<indices.count {
                let prevIndex = indices[(i + indices.count - 1) % indices.count]
                let currIndex = indices[i]
                let nextIndex = indices[(i + 1) % indices.count]
                let prev = raw[prevIndex]
                let curr = raw[currIndex]
                let next = raw[nextIndex]

                // Convex check: cross product sign must agree with the
                // polygon's winding.
                let cross = (curr.x - prev.x) * (next.y - curr.y) - (curr.y - prev.y) * (next.x - curr.x)
                if (cross > 0 ? 1.0 : -1.0) != windingSign {
                    continue
                }

                // Containment: no other vertex must be inside the
                // candidate triangle (prev, curr, next).
                var containsOther = false
                for j in indices where j != prevIndex && j != currIndex && j != nextIndex {
                    if pointInTriangle(raw[j], a: prev, b: curr, c: next) {
                        containsOther = true
                        break
                    }
                }
                if containsOther { continue }

                // Valid ear. Emit and remove.
                guard
                    let strip = scanlineFillTriangle(
                        v0: prev, v1: curr, v2: next,
                        color: path.fillColor, clip: path.clipBounds, clipCornerRadius: path.clipCornerRadius),
                    quads.count + strip.count <= maxTessellatedQuads
                else {
                    return nil
                }
                quads.append(contentsOf: strip)
                indices.remove(at: i)
                clipped = true
                break
            }
            if !clipped {
                // No ear found — polygon is likely self-intersecting.
                return nil
            }
        }
        // Final triangle.
        if indices.count == 3 {
            guard
                let strip = scanlineFillTriangle(
                    v0: raw[indices[0]], v1: raw[indices[1]], v2: raw[indices[2]],
                    color: path.fillColor, clip: path.clipBounds, clipCornerRadius: path.clipCornerRadius),
                quads.count + strip.count <= maxTessellatedQuads
            else {
                return nil
            }
            quads.append(contentsOf: strip)
        }
        return quads.isEmpty ? nil : quads
    }

    /// Returns +1 for counter-clockwise winding, -1 for clockwise, 0
    /// for a degenerate (zero-area) polygon.
    private static func polygonWindingSign(_ vertices: [Point]) -> Double {
        var area2: Double = 0
        let n = vertices.count
        for i in 0..<n {
            let a = vertices[i]
            let b = vertices[(i + 1) % n]
            area2 += (b.x - a.x) * (b.y + a.y)
        }
        if abs(area2) < 0.0001 { return 0 }
        return area2 > 0 ? -1 : 1  // y-axis points down in screen space
    }

    /// Barycentric-style point-in-triangle test. Returns true when `p`
    /// lies strictly inside (or on the edge of) triangle `(a, b, c)`.
    private static func pointInTriangle(_ p: Point, a: Point, b: Point, c: Point) -> Bool {
        let v0x = c.x - a.x
        let v0y = c.y - a.y
        let v1x = b.x - a.x
        let v1y = b.y - a.y
        let v2x = p.x - a.x
        let v2y = p.y - a.y
        let dot00 = v0x * v0x + v0y * v0y
        let dot01 = v0x * v1x + v0y * v1y
        let dot02 = v0x * v2x + v0y * v2y
        let dot11 = v1x * v1x + v1y * v1y
        let dot12 = v1x * v2x + v1y * v2y
        let denom = dot00 * dot11 - dot01 * dot01
        guard abs(denom) > 0.000001 else { return false }
        let invDenom = 1.0 / denom
        let u = (dot11 * dot02 - dot01 * dot12) * invDenom
        let v = (dot00 * dot12 - dot01 * dot02) * invDenom
        return u >= -0.0001 && v >= -0.0001 && (u + v) <= 1.0001
    }

    /// Returns false if any point in `path.elements` has a non-finite
    /// coordinate. Apps occasionally feed `Path` infinities or NaNs
    /// (division by zero, log of negative, etc.), and the scanline
    /// fillers convert vertex y values to `Int` for row allocation
    /// which traps on non-finite Doubles.
    private static func pathHasFiniteCoordinates(_ path: PathPrimitive) -> Bool {
        func isFinitePoint(_ p: Point) -> Bool { p.x.isFinite && p.y.isFinite }
        for element in path.elements {
            switch element {
            case .moveTo(let p), .lineTo(let p):
                if !isFinitePoint(p) { return false }
            case .quadraticCurveTo(let c, let e):
                if !isFinitePoint(c) || !isFinitePoint(e) { return false }
            case .cubicCurveTo(let c1, let c2, let e):
                if !isFinitePoint(c1) || !isFinitePoint(c2) || !isFinitePoint(e) {
                    return false
                }
            case .arc(let center, let r, let s, let en, _):
                if !isFinitePoint(center) || !r.isFinite || !s.isFinite || !en.isFinite {
                    return false
                }
            case .close:
                break
            }
        }
        return true
    }

    /// Walks the path's elements producing the polygon's boundary as a
    /// flat list of points. Curves are adaptively subdivided into line
    /// segments. Returns nil for paths that aren't a single closed
    /// subpath.
    private static func sampleClosedFillBoundary(elements: [PathElement]) -> [Point]? {
        var points: [Point] = []
        var didMove = false
        var subpathStart: Point?
        for element in elements {
            switch element {
            case .moveTo(let p):
                guard !didMove else { return nil }
                didMove = true
                subpathStart = p
                points.append(p)
            case .lineTo(let p):
                guard didMove else { return nil }
                points.append(p)
            case .quadraticCurveTo(let control, let end):
                guard let from = points.last else { return nil }
                points.append(contentsOf: sampleQuadratic(from: from, control: control, end: end))
            case .cubicCurveTo(let c1, let c2, let end):
                guard let from = points.last else { return nil }
                points.append(contentsOf: sampleCubic(from: from, control1: c1, control2: c2, end: end))
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                let samples = sampleArc(
                    center: center, radius: radius,
                    startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
                if !didMove, let first = samples.first {
                    didMove = true
                    subpathStart = first
                    points.append(first)
                    points.append(contentsOf: samples.dropFirst())
                } else {
                    points.append(contentsOf: samples)
                }
            case .close:
                break
            }
        }
        // Drop a trailing duplicate of the start point (the path
        // explicitly closes by repeating vertex 0); subsequent
        // convexity / scanline checks expect distinct vertices.
        if points.count >= 2, points.first == points.last {
            points.removeLast()
        }
        _ = subpathStart
        return points.isEmpty ? nil : points
    }

    /// Returns true if the polygon vertices form a convex shape. Tests
    /// that every adjacent-edge cross product has the same sign — for
    /// a convex polygon (in either winding) all signs agree.
    private static func isConvex(_ vertices: [Point]) -> Bool {
        guard vertices.count >= 3 else { return false }
        var sign: Double = 0
        let n = vertices.count
        for i in 0..<n {
            let a = vertices[i]
            let b = vertices[(i + 1) % n]
            let c = vertices[(i + 2) % n]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 0.0001 {
                continue  // colinear triple — fine, doesn't violate convexity
            }
            if sign == 0 {
                sign = cross > 0 ? 1 : -1
            } else if (cross > 0 ? 1.0 : -1.0) != sign {
                return false
            }
        }
        return true
    }

    /// Produces axis-aligned scanline strip quads covering the
    /// triangle (v0, v1, v2). Shared by triangleFill and convex-polygon
    /// fan triangulation.
    ///
    /// Returns an empty array for a degenerate (zero-area, or entirely clipped
    /// out) triangle, and `nil` when the triangle exceeds the row budget or
    /// cannot advance by representable unit row steps — in which case the
    /// caller abandons GPU promotion for the whole path and falls back to CPU
    /// rasterization.
    private static func scanlineFillTriangle(
        v0: Point, v1: Point, v2: Point, color: Color, clip: Rect?, clipCornerRadius: Double = 0
    ) -> [QuadPrimitive]? {
        let area2 = (v1.x - v0.x) * (v2.y - v0.y) - (v2.x - v0.x) * (v1.y - v0.y)
        if abs(area2) < 0.001 { return [] }
        var minY = floor(min(v0.y, v1.y, v2.y))
        var maxY = ceil(max(v0.y, v1.y, v2.y))
        // Rows outside the clip cannot show a pixel, so they are not worth a
        // quad. Without this a chart with one outlier vertex emitted millions
        // of strips per frame that the clip then discarded.
        if let clip, clip.size.width > 0, clip.size.height > 0 {
            minY = max(minY, floor(clip.minY))
            maxY = min(maxY, ceil(clip.maxY))
        }
        guard maxY > minY else { return [] }
        // Saturating rather than trapping: `Int(1e300)` is a process kill, and
        // a finite-but-huge coordinate is easy to produce from app arithmetic.
        let rowCount = GPUISceneValue.int(maxY - minY)
        guard rowCount > 0, rowCount <= maxScanlineRows else { return nil }

        let edges = [(v0, v1), (v1, v2), (v2, v0)]
        var quads: [QuadPrimitive] = []
        quads.reserveCapacity(rowCount + 1)
        var y = minY
        for _ in 0..<rowCount {
            let nextY = y + 1
            guard nextY.isFinite, nextY - y == 1 else { return nil }
            let scanY = y + 0.5
            var hits: [Double] = []
            for (a, b) in edges {
                if let xAtY = intersectX(edgeStart: a, edgeEnd: b, atY: scanY) {
                    hits.append(xAtY)
                }
            }
            hits.sort()
            if hits.count >= 2, abs(hits[0] - hits[1]) > 0.5 {
                let rect = Rect(x: hits[0], y: y, width: hits[1] - hits[0], height: 1)
                quads.append(quad(for: rect, color: color, clip: clip))
            }
            y = nextY
        }
        return quads
    }

    /// Returns the x value where the line through `(edgeStart, edgeEnd)`
    /// crosses the horizontal line `y = atY`, or nil when the edge is
    /// horizontal (no clean intersection) or atY is outside the edge's
    /// y-range.
    private static func intersectX(edgeStart a: Point, edgeEnd b: Point, atY: Double) -> Double? {
        let dy = b.y - a.y
        if abs(dy) < 0.0001 {
            return nil
        }
        let lo = min(a.y, b.y)
        let hi = max(a.y, b.y)
        guard atY >= lo && atY <= hi else { return nil }
        let t = (atY - a.y) / dy
        return a.x + t * (b.x - a.x)
    }

    /// An axis-aligned rounded rectangle is a *quad*, not a polygon.
    ///
    /// The quad family already carries a corner radius — it is what every
    /// rounded control background in the stack is drawn with — so a
    /// `Path(roundedRect:cornerRadius:)` fill costs one primitive with
    /// shader-quality corner anti-aliasing. Falling through to the convex
    /// polygon lane instead spends one scanline strip per row (a 40pt bar is
    /// ~40 quads) and steps its corners in whole pixels, which is what pushed
    /// a ten-bar chart past the scene-primitive budget.
    ///
    /// Matches the element stream `Path.addRoundedRect` emits: a `moveTo`
    /// then four `lineTo`/`arc` pairs. The geometry is verified rather than
    /// the angles — four equal radii whose centres are the corners inset by
    /// that radius can only describe this shape.
    private static func roundedRectFill(for path: PathPrimitive) -> [QuadPrimitive]? {
        var elements = path.elements
        if elements.last == .close {
            elements.removeLast()
        }
        guard elements.count == 9 else { return nil }
        guard case .moveTo(let start) = elements[0] else { return nil }

        var radius: Double?
        var centers: [Point] = []
        var index = 1
        while index < elements.count {
            guard case .lineTo = elements[index] else { return nil }
            guard case .arc(let center, let arcRadius, _, _, _) = elements[index + 1] else { return nil }
            if let radius, abs(radius - arcRadius) > 0.001 { return nil }
            radius = arcRadius
            centers.append(center)
            index += 2
        }
        guard centers.count == 4, let r = radius, r > 0 else { return nil }

        let xs = centers.map(\.x)
        let ys = centers.map(\.y)
        guard let cornerMinX = xs.min(), let cornerMaxX = xs.max(),
            let cornerMinY = ys.min(), let cornerMaxY = ys.max()
        else { return nil }
        // The four arc centres must be the four distinct inset corners.
        let expectedCenters: Set<[Double]> = [
            [cornerMinX, cornerMinY], [cornerMaxX, cornerMinY],
            [cornerMaxX, cornerMaxY], [cornerMinX, cornerMaxY],
        ]
        guard expectedCenters.count == 4,
            Set(centers.map { [$0.x, $0.y] }) == expectedCenters
        else { return nil }

        let rect = Rect(
            x: cornerMinX - r,
            y: cornerMinY - r,
            width: (cornerMaxX - cornerMinX) + 2 * r,
            height: (cornerMaxY - cornerMinY) + 2 * r
        )
        // A radius past half the shorter side is a different shape (the arcs
        // would overlap); leave those to the polygon lane.
        guard 2 * r <= min(rect.size.width, rect.size.height) + 0.001 else { return nil }
        // The subpath starts on the top edge, just past the first corner.
        guard abs(start.y - rect.minY) < 0.001, abs(start.x - (cornerMinX)) < 0.001 else { return nil }

        if path.fillRule == .evenOdd {
            // Matching corner centres alone does not establish coverage:
            // reordered or multi-turn arcs can change crossing parity. Only
            // the canonical quarter-arc contour takes this special case.
            var canonical = Path()
            canonical.addRoundedRect(rect, cornerRadius: r)
            guard elements.elementsEqual(canonical.elements.dropLast()) else { return nil }
        }

        return [
            quad(
                for: rect,
                color: path.fillColor,
                clip: path.clipBounds,
                clipCornerRadius: path.clipCornerRadius,
                cornerRadius: Float(r)
            )
        ]
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
        if path.fillRule == .evenOdd, !hasSimpleStraightFillBoundary(path.elements) { return nil }

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

        // Adjacency check: every consecutive pair of vertices must share
        // exactly one coordinate (i.e. form a horizontal or vertical
        // edge). A bowtie / figure-8 has the same four corner points
        // but its diagonal edges differ on both coordinates, so this
        // rejects it cleanly.
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let sharesX = abs(a.x - b.x) < 0.0001
            let sharesY = abs(a.y - b.y) < 0.0001
            guard sharesX != sharesY else {
                return nil
            }
        }

        let rect = Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return [quad(for: rect, color: path.fillColor, clip: path.clipBounds, clipCornerRadius: path.clipCornerRadius)]
    }

    /// One flattened subpath of a stroked path, with the closure flag the
    /// caps depend on: an open subpath has two ends to cap, a closed one has
    /// none.
    private struct StrokeSubpath {
        var points: [Point]
        var isClosed: Bool
    }

    /// What the quad family has to draw at one vertex or one end.
    private enum StrokeTerminal {
        /// Covered by the segment bodies alone — extending both across the
        /// vertex is free and leaves no seam.
        case extend
        /// A butt end: the body stops exactly at the point.
        case flush
        /// A disc centred on the point, which a `lineWidth × lineWidth` quad
        /// with a half-width corner radius draws exactly.
        case disc
        /// A shape the quad family has no primitive for — a bevel triangle,
        /// or a miter kite at anything but a right angle. The bodies stop
        /// flush and this one wedge goes to the CPU stroker through
        /// ``Result/residualPath``.
        case wedge
    }

    /// How far along each adjacent segment a wedge stub reaches, in half
    /// widths. The stub only has to be long enough for the stroker to see two
    /// real directions at the vertex; everything past that is body the quads
    /// already drew.
    private static let joinWedgeStubHalfWidths: Double = 1

    /// Mixed-output stroked-line tessellator. Walks the path subpath by
    /// subpath; axis-aligned segments become unrotated GPU quads and
    /// diagonal ones rotated quads, with caps and joins honoured exactly or
    /// not at all.
    ///
    /// "Exactly or not at all" is the rule that changed here. Every segment
    /// used to be extended by half a line width at both ends, which is a
    /// square cap on every open end and a right-angle miter at every corner
    /// — whatever the `StrokeStyle` said. Now a butt end stops flush, a
    /// square end extends, a round end (or a round join) gets its disc, and
    /// a join the quad family cannot draw exactly sends the *whole* path to
    /// `PathCoverageRasterizer`, which can.
    private static func axisAlignedStrokedLinesMixed(for path: PathPrimitive) -> Result? {
        let halfWidth = path.lineWidth / 2
        guard halfWidth > 0 else { return nil }
        let subpaths = strokeSubpaths(for: path.elements)
        guard !subpaths.isEmpty else { return nil }

        var quads: [QuadPrimitive] = []
        var residualPolylines: [[Point]] = []

        for subpath in subpaths {
            let points = subpath.points
            guard points.count >= 2 else { continue }
            let segmentCount = points.count - 1

            // Resolve every vertex first: a vertex the quads cannot draw
            // becomes one residual wedge, not a discarded path, so there is
            // never a half-drawn stroke to unwind either way.
            var terminals = [StrokeTerminal](repeating: .extend, count: points.count)
            for index in 1..<segmentCount {
                guard
                    let terminal = joinTerminal(
                        at: index, points: points, halfWidth: halfWidth, path: path)
                else { return nil }
                terminals[index] = terminal
                if terminal == .wedge,
                    let stub = joinWedgeStub(
                        before: points[index - 1], at: points[index], after: points[index + 1],
                        halfWidth: halfWidth)
                {
                    residualPolylines.append(stub)
                }
            }
            if subpath.isClosed {
                // The start/end vertex is a corner like any other.
                guard
                    let terminal = closingJoinTerminal(points: points, halfWidth: halfWidth, path: path)
                else { return nil }
                terminals[0] = terminal
                terminals[segmentCount] = terminal
                if terminal == .wedge,
                    let stub = joinWedgeStub(
                        before: points[points.count - 2], at: points[0], after: points[1],
                        halfWidth: halfWidth)
                {
                    residualPolylines.append(stub)
                }
            } else {
                let capTerminal: StrokeTerminal
                switch path.lineCap {
                case .butt: capTerminal = .flush
                case .square: capTerminal = .extend
                case .round: capTerminal = .disc
                }
                terminals[0] = capTerminal
                terminals[segmentCount] = capTerminal
            }

            for index in 0..<segmentCount {
                let from = points[index]
                let to = points[index + 1]
                if let segment = strokedSegmentQuad(
                    from: from, to: to, lineWidth: path.lineWidth,
                    startExtension: terminals[index] == .extend ? halfWidth : 0,
                    endExtension: terminals[index + 1] == .extend ? halfWidth : 0,
                    color: path.strokeColor, clip: path.clipBounds, clipCornerRadius: path.clipCornerRadius)
                {
                    quads.append(segment)
                } else {
                    residualPolylines.append([from, to])
                }
            }
            for index in 0...segmentCount where terminals[index] == .disc {
                // A closed subpath repeats its first point last; one disc is
                // enough for the vertex they share.
                if subpath.isClosed, index == segmentCount { continue }
                quads.append(
                    discQuad(
                        at: points[index], halfWidth: halfWidth, color: path.strokeColor,
                        clip: path.clipBounds, clipCornerRadius: path.clipCornerRadius))
            }
        }

        if quads.isEmpty && residualPolylines.isEmpty {
            return nil
        }

        // Build the residual path from the leftover fragments: diagonal or
        // curved bodies the quad family declined, and the join wedges it has
        // no primitive for. Each becomes a moveTo + lineTo…; the residual is
        // rendered by the CPU rasterizer with the same stroke style and clip
        // as the original.
        let residualPath: PathPrimitive?
        if residualPolylines.isEmpty {
            residualPath = nil
        } else {
            var elements: [PathElement] = []
            for polyline in residualPolylines {
                guard let first = polyline.first else { continue }
                elements.append(.moveTo(first))
                for point in polyline.dropFirst() {
                    elements.append(.lineTo(point))
                }
            }
            // Compute residual bounds for the painter's clip/visibility
            // checks; outset by half-lineWidth so a zero-thickness
            // diagonal bounding box still has area.
            let allPoints = residualPolylines.flatMap { $0 }
            let minX = allPoints.map(\.x).min() ?? 0
            let minY = allPoints.map(\.y).min() ?? 0
            let maxX = allPoints.map(\.x).max() ?? 0
            let maxY = allPoints.map(\.y).max() ?? 0
            let rawBounds = Rect(
                x: minX, y: minY,
                width: max(0, maxX - minX), height: max(0, maxY - minY))
            residualPath = PathPrimitive(
                elements: elements,
                bounds: rawBounds.outset(
                    by: StrokeOutlineGeometry.boundsOutset(
                        forElements: elements, lineWidth: path.lineWidth, lineCap: path.lineCap,
                        lineJoin: path.lineJoin, miterLimit: path.miterLimit)),
                strokeColor: path.strokeColor,
                lineWidth: path.lineWidth,
                lineCap: path.lineCap,
                lineJoin: path.lineJoin,
                miterLimit: path.miterLimit,
                clipBounds: path.clipBounds,
                clipCornerRadius: path.clipCornerRadius
            )
        }

        return Result(quads: quads, residualPath: residualPath)
    }

    // MARK: - Stroke subpaths, joins and caps

    /// Flattens `elements` into the polylines the stroker walks, keeping
    /// subpath identity: filling closes every subpath, stroking only closes
    /// the ones that asked to be closed, and caps only exist on the rest.
    private static func strokeSubpaths(for elements: [PathElement]) -> [StrokeSubpath] {
        var result: [StrokeSubpath] = []
        var current: [Point] = []
        var subpathStart: Point?

        func append(_ points: [Point]) {
            for point in points where current.last != point {
                current.append(point)
            }
        }

        func flush(closed: Bool) {
            if current.count >= 2 {
                result.append(StrokeSubpath(points: current, isClosed: closed))
            }
            current = []
        }

        for element in elements {
            switch element {
            case .moveTo(let point):
                flush(closed: false)
                subpathStart = point
                current = [point]
            case .lineTo(let point):
                guard !current.isEmpty else { continue }
                append([point])
            case .close:
                if let start = subpathStart, current.count >= 2 {
                    append([start])
                    flush(closed: true)
                } else {
                    flush(closed: false)
                }
                // A `close` returns the pen to the subpath origin; anything
                // that follows without a `moveTo` continues from there.
                current = subpathStart.map { [$0] } ?? []
            case .quadraticCurveTo(let control, let end):
                guard let from = current.last else { continue }
                append(sampleQuadratic(from: from, control: control, end: end))
            case .cubicCurveTo(let control1, let control2, let end):
                guard let from = current.last else { continue }
                append(sampleCubic(from: from, control1: control1, control2: control2, end: end))
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                let samples = sampleArc(
                    center: center, radius: radius, startAngle: startAngle, endAngle: endAngle,
                    clockwise: clockwise)
                if current.isEmpty, let first = samples.first {
                    subpathStart = first
                    current = [first]
                }
                append(samples)
            }
        }
        flush(closed: false)
        return result
    }

    /// What the quad family has to draw at the interior vertex `index`, or
    /// `nil` when it cannot draw that join exactly.
    private static func joinTerminal(
        at index: Int, points: [Point], halfWidth: Double, path: PathPrimitive
    ) -> StrokeTerminal? {
        guard
            let incoming = unitDirection(from: points[index - 1], to: points[index]),
            let outgoing = unitDirection(from: points[index], to: points[index + 1])
        else {
            return .extend
        }
        return joinTerminal(from: incoming, to: outgoing, halfWidth: halfWidth, path: path)
    }

    /// The same decision at the vertex a closed subpath starts and ends on.
    private static func closingJoinTerminal(
        points: [Point], halfWidth: Double, path: PathPrimitive
    ) -> StrokeTerminal? {
        guard
            let incoming = unitDirection(from: points[points.count - 2], to: points[points.count - 1]),
            let outgoing = unitDirection(from: points[0], to: points[1])
        else {
            return .extend
        }
        return joinTerminal(from: incoming, to: outgoing, halfWidth: halfWidth, path: path)
    }

    private static func joinTerminal(
        from incoming: (x: Double, y: Double),
        to outgoing: (x: Double, y: Double),
        halfWidth: Double,
        path: PathPrimitive
    ) -> StrokeTerminal? {
        let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
        let resolved = StrokeOutlineGeometry.resolvedJoin(
            path.lineJoin, directionDot: dot, miterLimit: path.miterLimit)
        guard
            StrokeOutlineGeometry.joinIsVisible(halfWidth: halfWidth, directionDot: dot, join: resolved)
        else {
            // Below the tolerance the two bodies already cover the wedge;
            // overlapping them keeps the seam closed at no extra cost.
            return .extend
        }
        switch resolved {
        case .round:
            return .disc
        case .miter:
            // Two bodies extended across a *right-angle* turn cover exactly
            // the miter wedge — the outer half-width square — and nothing
            // else. At any other angle the wedge is a kite, which no
            // axis-aligned or rotated rectangle is, and the extension's
            // error grows as `halfWidth · |cos(turn)|`: it under-fills the
            // long spike of a shallow turn and over-fills a sharp one. Past
            // the same tolerance the CPU stroker uses, the wedge goes there.
            if halfWidth * abs(dot) <= StrokeOutlineGeometry.joinTolerance { return .extend }
            return wedgeOrWholePathFallback(for: path)
        case .bevel:
            // A bevel is a triangle. Nothing in the quad family is.
            return wedgeOrWholePathFallback(for: path)
        }
    }

    /// A join the quads cannot draw is one wedge on the CPU — unless the
    /// stroke is translucent, in which case it is the whole path.
    ///
    /// A wedge stub overlaps the two segment bodies the quads already drew,
    /// because a stroker draws a join by stroking the corner it belongs to.
    /// Painting an opaque colour twice is invisible; painting a translucent
    /// one twice is a dark notch at every corner. So the fast route is taken
    /// only where it cannot be seen, and everything else keeps the
    /// whole-path CPU raster that was the only behaviour before — a
    /// three-corner bevelled polyline used to abandon GPU promotion for
    /// *every* segment over three wedges' worth of geometry.
    private static func wedgeOrWholePathFallback(for path: PathPrimitive) -> StrokeTerminal? {
        path.strokeColor.alpha >= 1 ? .wedge : nil
    }

    /// The short polyline whose stroke *is* one join: a stub back along the
    /// incoming segment, the vertex, and a stub forward along the outgoing
    /// one. The stroker draws the bevel triangle or the miter kite from the
    /// two directions it sees there.
    private static func joinWedgeStub(
        before: Point, at vertex: Point, after: Point, halfWidth: Double
    ) -> [Point]? {
        guard let incoming = unitDirection(from: before, to: vertex),
            let outgoing = unitDirection(from: vertex, to: after)
        else { return nil }
        let reach = halfWidth * joinWedgeStubHalfWidths
        let back = min(reach, distance(from: before, to: vertex))
        let forward = min(reach, distance(from: vertex, to: after))
        guard back > 0, forward > 0 else { return nil }
        return [
            Point(x: vertex.x - incoming.x * back, y: vertex.y - incoming.y * back),
            vertex,
            Point(x: vertex.x + outgoing.x * forward, y: vertex.y + outgoing.y * forward),
        ]
    }

    private static func distance(from start: Point, to end: Point) -> Double {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }

    private static func unitDirection(from start: Point, to end: Point) -> (x: Double, y: Double)? {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = (deltaX * deltaX + deltaY * deltaY).squareRoot()
        guard length > 0.0001, length.isFinite else { return nil }
        return (x: deltaX / length, y: deltaY / length)
    }

    /// A disc as a quad: a `lineWidth × lineWidth` square whose corner radius
    /// is half its side, which both backends' rounded-rect coverage resolves
    /// to a circle.
    private static func discQuad(
        at centre: Point, halfWidth: Double, color: Color, clip: Rect?, clipCornerRadius: Double
    ) -> QuadPrimitive {
        let rect = Rect(
            x: centre.x - halfWidth, y: centre.y - halfWidth,
            width: halfWidth * 2, height: halfWidth * 2)
        return quad(
            for: rect, color: color, clip: clip, clipCornerRadius: clipCornerRadius,
            cornerRadius: Float(halfWidth))
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

    /// The body of one stroke segment, grown past `from` by `startExtension`
    /// and past `to` by `endExtension`.
    ///
    /// The extensions are what a join or a square cap needs and a butt cap
    /// must not have, so they are per-end and directed: the segment runs
    /// `from → to`, and swapping the endpoints swaps which end grows.
    private static func strokedSegmentQuad(
        from: Point,
        to: Point,
        lineWidth: Double,
        startExtension: Double,
        endExtension: Double,
        color: Color,
        clip: Rect?,
        clipCornerRadius: Double = 0
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
        // The extensions follow the segment's own direction, so on a
        // right-to-left or bottom-to-top run the *end* extension is the one
        // that grows the min side.
        if isHorizontal {
            let minExtension = dx > 0 ? startExtension : endExtension
            let maxExtension = dx > 0 ? endExtension : startExtension
            let minX = min(from.x, to.x)
            let maxX = max(from.x, to.x)
            let rect = Rect(
                x: minX - minExtension,
                y: from.y - halfWidth,
                width: (maxX - minX) + minExtension + maxExtension,
                height: lineWidth
            )
            return quad(for: rect, color: color, clip: clip, clipCornerRadius: clipCornerRadius)
        }
        if isVertical {
            let minExtension = dy > 0 ? startExtension : endExtension
            let maxExtension = dy > 0 ? endExtension : startExtension
            let minY = min(from.y, to.y)
            let maxY = max(from.y, to.y)
            let rect = Rect(
                x: from.x - halfWidth,
                y: minY - minExtension,
                width: lineWidth,
                height: (maxY - minY) + minExtension + maxExtension
            )
            return quad(for: rect, color: color, clip: clip, clipCornerRadius: clipCornerRadius)
        }

        // Diagonal segment: emit a rotated quad. The unrotated rect covers
        // `length + extensions` along the x-axis with `lineWidth` thickness;
        // rotating around its centre by atan2(dy, dx) aligns it with the
        // segment. An asymmetric pair of extensions moves the centre, so the
        // midpoint is taken after they are applied.
        let extendedLength = length + startExtension + endExtension
        let unitX = dx / length
        let unitY = dy / length
        let centreX = (from.x + to.x) * 0.5 + unitX * (endExtension - startExtension) * 0.5
        let centreY = (from.y + to.y) * 0.5 + unitY * (endExtension - startExtension) * 0.5
        let rect = Rect(
            x: centreX - extendedLength * 0.5,
            y: centreY - halfWidth,
            width: extendedLength,
            height: lineWidth
        )
        let angle = atan2(dy, dx)
        return quad(for: rect, color: color, clip: clip, clipCornerRadius: clipCornerRadius, rotation: Float(angle))
    }

    private static func quad(
        for rect: Rect, color: Color, clip: Rect?, clipCornerRadius: Double = 0, rotation: Float = 0,
        cornerRadius: Float = 0
    ) -> QuadPrimitive {
        let clipRect = clip ?? Rect(x: 0, y: 0, width: 0, height: 0)
        return QuadPrimitive(
            x: Float(rect.origin.x),
            y: Float(rect.origin.y),
            width: Float(rect.size.width),
            height: Float(rect.size.height),
            cornerRadius: cornerRadius,
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha,
            gradientAxis: 0,
            clipX: Float(clipRect.origin.x),
            clipY: Float(clipRect.origin.y),
            clipWidth: Float(clipRect.size.width),
            clipHeight: Float(clipRect.size.height),
            clipCornerRadius: Float(clipCornerRadius),
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
