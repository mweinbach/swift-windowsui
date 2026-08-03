import Foundation
import SwiftWindowsCore

/// Resolves a `StrokeStyle` dash pattern into explicit on-run geometry, for
/// the stroke lowerings whose outline is not a rect.
///
/// Dashes have always been resolved *before* the path contract — a
/// `PathPrimitive` carries no `dashPattern`, and both stroke rasterizers draw
/// every element solid. `BorderSegments` does that resolution for the one
/// outline that is a rounded rectangle, walking its perimeter and emitting
/// one quad per dash. Every other stroke lowering had nowhere to send the
/// pattern, so it dropped it: `Circle().stroke(style: StrokeStyle(dash:
/// [4, 4]))` and a dashed `Canvas` `strokePath` both shipped solid.
///
/// This is the same walk over an arbitrary path. The output is a new element
/// stream containing only the "on" runs, as open subpaths, so the existing
/// solid stroker draws the dashes — including the cap on each dash end, which
/// is where a `.round` dash pattern gets its dots.
public enum PathDashing {

    /// Largest number of on/off steps one dash walk takes before it stops.
    ///
    /// A pattern finer than the path is long — `dash: [0.0001]` on a
    /// 4,000-point chart — would otherwise emit millions of subpaths. The
    /// same bound `BorderSegments` uses, for the same reason.
    public static let maxDashSteps = 4_096

    /// The pattern a walk actually uses: non-positive entries dropped, and an
    /// odd-length pattern doubled so on/off alternation lands where
    /// `StrokeStyle` says it does. Empty means "nothing to resolve".
    public static func normalizedPattern(_ pattern: [Double]) -> [Double] {
        let positive = pattern.filter { $0 > 0 && $0.isFinite }
        guard !positive.isEmpty else { return [] }
        if positive.count.isMultiple(of: 2) { return positive }
        return positive + positive
    }

    /// Returns `elements` rewritten as the pattern's "on" runs, or `nil` when
    /// there is nothing to resolve (an empty or degenerate pattern), which
    /// tells the caller to keep the solid geometry it already has.
    ///
    /// Curves and arcs are flattened first — a dash is a length along the
    /// outline, and length is what a curve does not give in closed form — so
    /// a dashed circle arrives as a dashed polygon at the same flattening
    /// tolerance the coverage rasterizer would have used anyway.
    public static func dashed(
        _ elements: [PathElement],
        pattern: [Double],
        offset: Double
    ) -> [PathElement]? {
        let dashPattern = normalizedPattern(pattern)
        guard !dashPattern.isEmpty else { return nil }
        let patternLength = dashPattern.reduce(0, +)
        guard patternLength > 0, patternLength.isFinite else { return nil }
        guard offset.isFinite else { return nil }

        var result: [PathElement] = []
        var steps = 0
        for subpath in FlattenedPath(elements).subpaths {
            var points = subpath.points
            if subpath.isClosed, let first = points.first, let last = points.last, first != last {
                points.append(first)
            }
            guard points.count >= 2 else { continue }
            appendDashes(
                along: points, pattern: dashPattern, patternLength: patternLength, offset: offset,
                steps: &steps, into: &result)
            if steps >= maxDashSteps { break }
        }
        return result
    }

    /// Walks one flattened subpath, emitting a `moveTo` + `lineTo`… run per
    /// "on" span. A span that crosses a vertex keeps that vertex, so a dash
    /// spanning a corner still turns the corner (and still gets its join).
    private static func appendDashes(
        along points: [Point],
        pattern: [Double],
        patternLength: Double,
        offset: Double,
        steps: inout Int,
        into result: inout [PathElement]
    ) {
        // Where in the pattern this subpath starts. Each subpath restarts the
        // phase, which is what Core Graphics does with a multi-subpath path.
        var patternIndex = 0
        var patternOffset = positiveRemainder(offset, by: patternLength)
        while patternOffset >= pattern[patternIndex] {
            patternOffset -= pattern[patternIndex]
            patternIndex = (patternIndex + 1) % pattern.count
        }

        var isOn = patternIndex.isMultiple(of: 2)
        var remainingInStep = pattern[patternIndex] - patternOffset
        var open = false

        func advanceStep() {
            patternIndex = (patternIndex + 1) % pattern.count
            remainingInStep = pattern[patternIndex]
            isOn = patternIndex.isMultiple(of: 2)
            if !isOn { open = false }
            steps += 1
        }

        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            let length = (deltaX * deltaX + deltaY * deltaY).squareRoot()
            guard length > 0, length.isFinite else { continue }
            let unitX = deltaX / length
            let unitY = deltaY / length

            var travelled = 0.0
            while travelled < length {
                guard steps < maxDashSteps else { return }
                let span = min(remainingInStep, length - travelled)
                if isOn {
                    let from = Point(x: start.x + unitX * travelled, y: start.y + unitY * travelled)
                    let to = Point(
                        x: start.x + unitX * (travelled + span), y: start.y + unitY * (travelled + span))
                    if open {
                        result.append(.lineTo(to))
                    } else {
                        result.append(.moveTo(from))
                        result.append(.lineTo(to))
                        open = true
                    }
                }
                travelled += span
                remainingInStep -= span
                // A pattern entry finer than floating point can subtract
                // would spin here forever; every step either consumes a
                // pattern entry or reaches the segment end.
                if remainingInStep <= 0 {
                    advanceStep()
                } else if span <= 0 {
                    break
                }
            }
            // A dash that continues past this vertex keeps drawing from the
            // next segment's start, which is the same point; nothing to do.
        }
    }

    private static func positiveRemainder(_ value: Double, by divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
