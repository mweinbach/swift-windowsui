import Foundation
import SwiftWindowsCore

/// A half-open integer pixel window, in surface coordinates.
struct PixelBounds {
    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int

    var width: Int { x1 - x0 }
    var height: Int { y1 - y0 }
}

/// One directed edge of a polygon, in surface coordinates.
///
/// Direction carries the winding: an edge running down the surface counts
/// `+1`, one running up counts `-1`. That is what makes the non-zero fill
/// rule expressible, which is what SwiftUI's `Path` fill and this stack's
/// own `Path.contains(_:eoFill: false)` already use — the rasterizer's
/// old even-odd pairing filled a star or a figure-eight with holes its own
/// hit testing said were solid.
struct CoverageEdge {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
}

/// Scanline coverage accumulation for polygon sets.
///
/// One buffer per path per pass, so a pixel is blended **once** no matter
/// how many segments cover it. The rasterizer used to scanline-fill every
/// flattened stroke segment as an independent quad, which double-blended
/// every shared vertex — a translucent polyline came out blotchy and
/// progressively darker, and the same output is what the D3D11 path
/// texture cache uploads, so it was the shipping appearance of `Canvas`,
/// chart strokes and the SF-symbol vector fallback.
enum PathCoverageRasterizer {

    /// Sub-scanlines per pixel row. Coverage is exact in x (spans are
    /// clipped analytically against each pixel column) and sampled in y,
    /// so this is the only quantization: 8 rows give alpha steps of 1/8
    /// on a perfectly horizontal edge and much finer than that on any
    /// other angle, which is below the parity suite's ±4/255 tolerance
    /// for everything except a pathological axis-aligned half-pixel edge.
    static let subsamplesPerRow = 8

    /// Accumulates the non-zero-winding coverage of `edges` into a
    /// `bounds.width * bounds.height` buffer of `[0, 1]` values.
    static func accumulate(edges: [CoverageEdge], bounds: PixelBounds, into coverage: inout [Float]) {
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0, !edges.isEmpty else { return }

        let subsamples = subsamplesPerRow
        let rowCount = height * subsamples
        let originY = Double(bounds.y0)
        let inverseSubsamples = 1.0 / Double(subsamples)

        // Active-edge table: an edge only participates in the sub-rows its
        // own y-extent spans, so a 2,000-segment flattened curve costs its
        // own length rather than length × surface height.
        struct ActiveEdge {
            var xAtFirstRow: Double
            var slope: Double
            var firstRow: Int
            var endRow: Int
            var winding: Double
        }

        var prepared: [ActiveEdge] = []
        prepared.reserveCapacity(edges.count)
        var buckets = [[Int]](repeating: [], count: rowCount)

        for edge in edges {
            guard edge.y0.isFinite, edge.y1.isFinite, edge.x0.isFinite, edge.x1.isFinite else { continue }
            guard edge.y0 != edge.y1 else { continue }
            let winding: Double = edge.y1 > edge.y0 ? 1 : -1
            let minY = min(edge.y0, edge.y1)
            let maxY = max(edge.y0, edge.y1)
            // Sub-row j samples at originY + (j + 0.5) / subsamples.
            let firstRow = max(0, Int(((minY - originY) * Double(subsamples) - 0.5).rounded(.up)))
            let endRow = min(rowCount, Int(((maxY - originY) * Double(subsamples) - 0.5).rounded(.up)))
            guard endRow > firstRow else { continue }
            let slope = (edge.x1 - edge.x0) / (edge.y1 - edge.y0)
            let sampleY = originY + (Double(firstRow) + 0.5) * inverseSubsamples
            prepared.append(
                ActiveEdge(
                    xAtFirstRow: edge.x0 + (sampleY - edge.y0) * slope,
                    slope: slope * inverseSubsamples,
                    firstRow: firstRow,
                    endRow: endRow,
                    winding: winding))
            buckets[firstRow].append(prepared.count - 1)
        }
        guard !prepared.isEmpty else { return }

        var active: [Int] = []
        var crossings: [(x: Double, winding: Double)] = []
        for row in 0..<rowCount {
            if !buckets[row].isEmpty {
                active.append(contentsOf: buckets[row])
            }
            guard !active.isEmpty else { continue }
            active.removeAll { prepared[$0].endRow <= row }
            guard !active.isEmpty else { continue }

            crossings.removeAll(keepingCapacity: true)
            for index in active {
                let edge = prepared[index]
                crossings.append(
                    (x: edge.xAtFirstRow + Double(row - edge.firstRow) * edge.slope, winding: edge.winding))
            }
            guard crossings.count >= 2 else { continue }
            crossings.sort { $0.x < $1.x }

            let pixelRow = row / subsamples
            let rowOffset = pixelRow * width
            var winding: Double = 0
            var spanStart: Double = 0
            for crossing in crossings {
                let wasInside = winding != 0
                winding += crossing.winding
                let isInside = winding != 0
                if !wasInside, isInside {
                    spanStart = crossing.x
                } else if wasInside, !isInside {
                    addSpan(
                        from: spanStart, to: crossing.x, rowOffset: rowOffset, bounds: bounds,
                        weight: Float(inverseSubsamples), into: &coverage)
                }
            }
        }

        for index in coverage.indices where coverage[index] > 1 {
            coverage[index] = 1
        }
    }

    private static func addSpan(
        from spanStart: Double,
        to spanEnd: Double,
        rowOffset: Int,
        bounds: PixelBounds,
        weight: Float,
        into coverage: inout [Float]
    ) {
        let left = max(spanStart, Double(bounds.x0))
        let right = min(spanEnd, Double(bounds.x1))
        guard right > left else { return }
        var pixel = Int(left.rounded(.down))
        let lastPixel = Int(right.rounded(.up))
        while pixel < lastPixel {
            let overlap = min(right, Double(pixel + 1)) - max(left, Double(pixel))
            if overlap > 0 {
                let index = rowOffset + (pixel - bounds.x0)
                if index >= 0, index < coverage.count {
                    coverage[index] += weight * Float(overlap)
                }
            }
            pixel += 1
        }
    }
}

// MARK: - Flattening

/// A polyline produced by flattening one subpath.
struct FlattenedSubpath {
    var points: [Point]
    /// Set by an explicit `.close`. Filling closes every subpath either
    /// way; stroking only draws the closing segment when it was asked for.
    var isClosed: Bool
}

/// A `PathPrimitive`'s elements flattened to polylines, keeping subpath
/// identity so fill and stroke can disagree about closure the way SwiftUI
/// does.
struct FlattenedPath {
    var subpaths: [FlattenedSubpath]

    init(_ elements: [PathElement]) {
        var result: [FlattenedSubpath] = []
        var current: [Point] = []
        var closed = false

        func flush() {
            if current.count >= 2 {
                result.append(FlattenedSubpath(points: current, isClosed: closed))
            }
            current = []
            closed = false
        }

        for element in elements {
            switch element {
            case .moveTo(let point):
                flush()
                current = [point]
            case .lineTo(let point):
                guard !current.isEmpty else { continue }
                current.append(point)
            case .quadraticCurveTo(let control, let end):
                guard let start = current.last else { continue }
                current.append(contentsOf: flattenQuadratic(start: start, control: control, end: end))
            case .cubicCurveTo(let control1, let control2, let end):
                guard let start = current.last else { continue }
                current.append(
                    contentsOf: flattenCubic(start: start, control1: control1, control2: control2, end: end))
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                let arcPoints = flattenArc(
                    center: center, radius: radius, startAngle: startAngle, endAngle: endAngle,
                    clockwise: clockwise)
                if current.isEmpty {
                    current = arcPoints
                } else {
                    current.append(contentsOf: arcPoints)
                }
            case .close:
                closed = true
                flush()
            }
        }
        flush()
        self.subpaths = result
    }

    /// Edges for filling. Every subpath is closed whether or not it says
    /// so — SwiftUI's fill semantics, and the reason a three-point
    /// triangle without `.close` used to be invisible here (most
    /// scanlines produced a single crossing, which the old pairing loop
    /// discarded).
    var fillEdges: [CoverageEdge] {
        var edges: [CoverageEdge] = []
        for subpath in subpaths {
            let points = subpath.points
            guard points.count >= 2 else { continue }
            for index in 0..<points.count {
                let next = points[(index + 1) % points.count]
                let point = points[index]
                edges.append(CoverageEdge(x0: point.x, y0: point.y, x1: next.x, y1: next.y))
            }
        }
        return edges
    }

    /// The stroke's *outline* as one polygon set: a quad per segment, a join
    /// wherever consecutive segments turn enough for the wedge between their
    /// quads to be visible, and a cap at each end of an open subpath. Every
    /// polygon is wound the same way, so filling the set with the non-zero
    /// rule is exactly their union — one coverage value per pixel, one
    /// blend, no seams at the joints.
    ///
    /// Caps and joins used to be fixed at butt and round because
    /// `PathPrimitive` carried a `lineWidth` and nothing else, so a stroke
    /// asking for `StrokeStyle(lineCap: .round)` silently got neither the
    /// cap it asked for nor the miter join SwiftUI defaults to. The
    /// primitive carries all three now, and the visibility rule below is
    /// `StrokeOutlineGeometry`'s, shared with the painter's quad
    /// tessellator so a promoted stroke and a rasterized one are the same
    /// shape.
    func strokeOutlineEdges(
        lineWidth: Double,
        lineCap: StrokeStyle.LineCap = .butt,
        lineJoin: StrokeStyle.LineJoin = .miter,
        miterLimit: Double = 10
    ) -> [CoverageEdge] {
        let halfWidth = lineWidth / 2
        guard halfWidth > 0 else { return [] }
        var edges: [CoverageEdge] = []

        for subpath in subpaths {
            var points = subpath.points
            if subpath.isClosed, let first = points.first, let last = points.last, first != last {
                points.append(first)
            }
            guard points.count >= 2 else { continue }

            var leadingDirection: (x: Double, y: Double)?
            var leadingPoint = points[0]
            var trailingPoint = points[0]
            var previousDirection: (x: Double, y: Double)?
            for index in 0..<(points.count - 1) {
                let start = points[index]
                let end = points[index + 1]
                let deltaX = end.x - start.x
                let deltaY = end.y - start.y
                let length = (deltaX * deltaX + deltaY * deltaY).squareRoot()
                guard length > 0, length.isFinite else { continue }
                let normalX = -deltaY / length * halfWidth
                let normalY = deltaX / length * halfWidth
                appendPolygon(
                    [
                        Point(x: start.x + normalX, y: start.y + normalY),
                        Point(x: end.x + normalX, y: end.y + normalY),
                        Point(x: end.x - normalX, y: end.y - normalY),
                        Point(x: start.x - normalX, y: start.y - normalY),
                    ], to: &edges)

                let direction = (x: deltaX / length, y: deltaY / length)
                if let previous = previousDirection {
                    appendJoinIfNeeded(
                        at: start, from: previous, to: direction, halfWidth: halfWidth,
                        join: lineJoin, miterLimit: miterLimit, into: &edges)
                } else {
                    leadingDirection = direction
                    leadingPoint = start
                }
                previousDirection = direction
                trailingPoint = end
            }

            guard let lastDirection = previousDirection, let firstDirection = leadingDirection else {
                continue
            }
            if subpath.isClosed {
                // A closed subpath turns at its start/end vertex too, and has
                // no ends to cap.
                appendJoinIfNeeded(
                    at: leadingPoint, from: lastDirection, to: firstDirection, halfWidth: halfWidth,
                    join: lineJoin, miterLimit: miterLimit, into: &edges)
            } else {
                appendCap(
                    at: leadingPoint, facing: (x: -firstDirection.x, y: -firstDirection.y),
                    halfWidth: halfWidth, cap: lineCap, into: &edges)
                appendCap(
                    at: trailingPoint, facing: lastDirection, halfWidth: halfWidth, cap: lineCap,
                    into: &edges)
            }
        }
        return edges
    }

    /// The join geometry for one turn, emitted only when omitting it would
    /// move the stroke boundary by more than `StrokeOutlineGeometry`'s
    /// tolerance. Flattened curves turn by fractions of a degree per
    /// segment, so skipping the negligible ones keeps a 2,000-segment curve
    /// from paying for 2,000 wedges.
    private func appendJoinIfNeeded(
        at vertex: Point,
        from previous: (x: Double, y: Double),
        to next: (x: Double, y: Double),
        halfWidth: Double,
        join: StrokeStyle.LineJoin,
        miterLimit: Double,
        into edges: inout [CoverageEdge]
    ) {
        let dot = previous.x * next.x + previous.y * next.y
        let resolved = StrokeOutlineGeometry.resolvedJoin(join, directionDot: dot, miterLimit: miterLimit)
        guard
            StrokeOutlineGeometry.joinIsVisible(halfWidth: halfWidth, directionDot: dot, join: resolved)
        else { return }

        if resolved == .round {
            appendDisc(at: vertex, radius: halfWidth, into: &edges)
            return
        }

        // Screen space has y growing downward and the segment quads offset
        // along `(-dy, dx)`; the wedge the two quads leave open is on the
        // side away from the turn.
        let cross = previous.x * next.y - previous.y * next.x
        let outerSign: Double = cross > 0 ? -1 : 1
        let firstNormal = Point(
            x: -previous.y * halfWidth * outerSign, y: previous.x * halfWidth * outerSign)
        let secondNormal = Point(x: -next.y * halfWidth * outerSign, y: next.x * halfWidth * outerSign)
        let firstCorner = Point(x: vertex.x + firstNormal.x, y: vertex.y + firstNormal.y)
        let secondCorner = Point(x: vertex.x + secondNormal.x, y: vertex.y + secondNormal.y)

        if resolved == .miter {
            // The two outer offset lines meet at `(n1 + n2) / (1 + dot)` from
            // the vertex; `resolvedJoin` already rejected the reversal that
            // makes that denominator vanish.
            let denominator = 1 + dot
            if denominator > 0 {
                let tip = Point(
                    x: vertex.x + (firstNormal.x + secondNormal.x) / denominator,
                    y: vertex.y + (firstNormal.y + secondNormal.y) / denominator)
                appendPolygon([vertex, firstCorner, tip, secondCorner], to: &edges)
                return
            }
        }

        appendPolygon([vertex, firstCorner, secondCorner], to: &edges)
    }

    /// The cap at one end of an open subpath. `facing` points *out* of the
    /// stroke, so the start of a subpath passes its reversed direction.
    private func appendCap(
        at point: Point,
        facing direction: (x: Double, y: Double),
        halfWidth: Double,
        cap: StrokeStyle.LineCap,
        into edges: inout [CoverageEdge]
    ) {
        switch cap {
        case .butt:
            return
        case .round:
            appendDisc(at: point, radius: halfWidth, into: &edges)
        case .square:
            let normalX = -direction.y * halfWidth
            let normalY = direction.x * halfWidth
            let reachX = direction.x * halfWidth
            let reachY = direction.y * halfWidth
            appendPolygon(
                [
                    Point(x: point.x + normalX, y: point.y + normalY),
                    Point(x: point.x + normalX + reachX, y: point.y + normalY + reachY),
                    Point(x: point.x - normalX + reachX, y: point.y - normalY + reachY),
                    Point(x: point.x - normalX, y: point.y - normalY),
                ], to: &edges)
        }
    }

    /// A polygon approximating the disc a round cap or round join fills.
    ///
    /// The side count follows the radius so the chord sagitta stays under
    /// `StrokeOutlineGeometry.joinTolerance`: a round cap is now visible
    /// geometry an app asked for, not an internal stand-in for a corner
    /// nobody sees.
    private func appendDisc(at centre: Point, radius: Double, into edges: inout [CoverageEdge]) {
        let sides = Self.discSideCount(radius: radius)
        var disc: [Point] = []
        disc.reserveCapacity(sides)
        for index in 0..<sides {
            let angle = 2 * Double.pi * Double(index) / Double(sides)
            disc.append(Point(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius))
        }
        appendPolygon(disc, to: &edges)
    }

    /// Sides of an inscribed regular polygon whose sagitta, `r · (1 − cos(π/n))`,
    /// is at most the join tolerance.
    static func discSideCount(radius: Double) -> Int {
        guard radius.isFinite, radius > StrokeOutlineGeometry.joinTolerance else { return 8 }
        let step = acos(max(-1, min(1, 1 - StrokeOutlineGeometry.joinTolerance / radius)))
        guard step > 0 else { return 64 }
        return min(64, max(8, Int((Double.pi / step).rounded(.up))))
    }

    /// Appends a polygon with a normalized orientation. Consistent winding
    /// is what makes the non-zero rule a union instead of a set of
    /// cancelling overlaps.
    private func appendPolygon(_ points: [Point], to edges: inout [CoverageEdge]) {
        guard points.count >= 3 else { return }
        var signedArea: Double = 0
        for index in 0..<points.count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            signedArea += a.x * b.y - b.x * a.y
        }
        let ordered = signedArea < 0 ? points.reversed().map { $0 } : points
        for index in 0..<ordered.count {
            let a = ordered[index]
            let b = ordered[(index + 1) % ordered.count]
            edges.append(CoverageEdge(x0: a.x, y0: a.y, x1: b.x, y1: b.y))
        }
    }
}

// MARK: - Curve flattening

// The flatness tests below are `<=` comparisons, and every comparison
// against NaN is false — so a single non-finite control point makes
// subdivision permanent and the recursion is a stack overflow, not a
// slow frame. `GPUISceneSanitizer` keeps non-finite coordinates out of
// the scene; the depth cap is what makes termination a property of the
// algorithm rather than of its callers.
private func flattenQuadratic(start: Point, control: Point, end: Point, depth: Int = 0) -> [Point] {
    let flatness: Double = 0.25
    let dx = end.x - start.x
    let dy = end.y - start.y
    let d = abs((control.x - end.x) * dy - (control.y - end.y) * dx)
    if depth >= GPUISceneLimits.maxCurveFlatteningDepth || d * d <= flatness * flatness * (dx * dx + dy * dy) {
        return [end]
    }
    let m0 = Point(x: (start.x + control.x) * 0.5, y: (start.y + control.y) * 0.5)
    let m1 = Point(x: (control.x + end.x) * 0.5, y: (control.y + end.y) * 0.5)
    let mid = Point(x: (m0.x + m1.x) * 0.5, y: (m0.y + m1.y) * 0.5)
    var left = flattenQuadratic(start: start, control: m0, end: mid, depth: depth + 1)
    left.append(contentsOf: flattenQuadratic(start: mid, control: m1, end: end, depth: depth + 1))
    return left
}

private func flattenCubic(start: Point, control1: Point, control2: Point, end: Point, depth: Int = 0) -> [Point] {
    let flatness: Double = 0.25
    let dx = end.x - start.x
    let dy = end.y - start.y
    let d1 = abs((control1.x - end.x) * dy - (control1.y - end.y) * dx)
    let d2 = abs((control2.x - end.x) * dy - (control2.y - end.y) * dx)
    if depth >= GPUISceneLimits.maxCurveFlatteningDepth
        || (d1 * d1 + d2 * d2) <= flatness * flatness * (dx * dx + dy * dy)
    {
        return [end]
    }
    let m0 = Point(x: (start.x + control1.x) * 0.5, y: (start.y + control1.y) * 0.5)
    let m1 = Point(x: (control1.x + control2.x) * 0.5, y: (control1.y + control2.y) * 0.5)
    let m2 = Point(x: (control2.x + end.x) * 0.5, y: (control2.y + end.y) * 0.5)
    let n0 = Point(x: (m0.x + m1.x) * 0.5, y: (m0.y + m1.y) * 0.5)
    let n1 = Point(x: (m1.x + m2.x) * 0.5, y: (m1.y + m2.y) * 0.5)
    let mid = Point(x: (n0.x + n1.x) * 0.5, y: (n0.y + n1.y) * 0.5)
    var left = flattenCubic(start: start, control1: m0, control2: n0, end: mid, depth: depth + 1)
    left.append(contentsOf: flattenCubic(start: mid, control1: n1, control2: m2, end: end, depth: depth + 1))
    return left
}

private func flattenArc(center: Point, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool)
    -> [Point]
{
    // A non-finite angle makes both normalisation comparisons false-forever
    // (clockwise) or true-forever (counter-clockwise), so the walk is
    // bounded by turn count as well as by the comparison. One full turn per
    // iteration means `maxArcSegments` turns is far more than any real arc.
    guard radius.isFinite, startAngle.isFinite, endAngle.isFinite else {
        return []
    }
    // Only the end angle is normalized into the directed sweep range; start is fixed.
    var end = endAngle
    var turns = 0
    if clockwise {
        while end > startAngle, turns < GPUISceneLimits.maxArcSegments {
            end -= 2 * .pi
            turns += 1
        }
    } else {
        while end < startAngle, turns < GPUISceneLimits.maxArcSegments {
            end += 2 * .pi
            turns += 1
        }
    }
    let sweep = end - startAngle
    let steps = min(
        max(4, GPUISceneValue.int((abs(sweep) * radius * 0.5).rounded(.up))),
        GPUISceneLimits.maxArcSegments
    )
    var points: [Point] = [Point(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle))]
    let step = sweep / Double(steps)
    for index in 1...steps {
        let angle = startAngle + step * Double(index)
        points.append(Point(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
    }
    return points
}
