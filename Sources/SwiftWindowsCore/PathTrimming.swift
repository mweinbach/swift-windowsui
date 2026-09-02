/// Distance-along-path trimming for the portable path value.
///
/// Full-range copies are exact, including malformed elements that a downstream
/// renderer may reject. Partial copies admit ordered finite fractions in 0...1.
/// Invalid, unrepresentable, and over-budget partial copies fail as a whole;
/// the nonthrowing public API returns an empty path for those failures.
///
/// Curve length estimates use chord/control-polygon bounds. Their error budget
/// is 1e-7 logical units across the path plus 1e-8 of each control-polygon length.
/// Endpoint inversion uses 1e-7 units or 1e-8 of the selected segment's length,
/// whichever is greater; the path's accumulated length error is additional.
/// It measures a newly split prefix; a flat curve is not assumed to have constant
/// parameter speed. These are numerical approximation policies,
/// not native-platform conformance or a guarantee for every finite input.
enum PathTrimming {
    enum Failure: Error, Equatable {
        case invalidFractions
        case invalidGeometry
        case missingCurrentPoint
        case inputLimit
        case workLimit
        case numericalLimit
    }

    struct Limits {
        var maximumElements = 65_536
        var maximumSegments = 131_072
        var maximumWork = 1_048_576
        var maximumCurveDepth = 24
        var maximumInverseIterations = 56
    }

    static let absoluteLengthTolerance = 1e-7
    static let relativeLengthTolerance = 1e-8
    // Bound angle reduction and trigonometric inputs independently of magnitude.
    static let maximumArcAngle = 8_192 * Double.pi

    static func trim(_ path: Path, from: Double, to: Double) -> Path {
        switch checkedTrim(path, from: from, to: to) {
        case .success(let result): return result
        case .failure: return Path()
        }
    }

    static func checkedTrim(
        _ path: Path, from: Double, to: Double, limits: Limits = Limits()
    ) -> Result<Path, Failure> {
        if from == 0, to == 1 { return .success(path) }
        guard from.isFinite, to.isFinite, from >= 0, to <= 1, from <= to else {
            return .failure(.invalidFractions)
        }
        if from == to { return .success(Path()) }
        guard path.elements.count <= limits.maximumElements else { return .failure(.inputLimit) }
        do {
            var worker = Worker(limits: limits)
            return .success(try worker.trim(path, from: from, to: to))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.numericalLimit)
        }
    }

    private struct Arc: Equatable {
        var center: Point
        var radius: Double
        var startAngle: Double
        var sweep: Double
        var clockwise: Bool

        var start: Point { point(at: startAngle) }
        var end: Point { point(at: startAngle + sweep) }

        func point(at angle: Double) -> Point {
            Point(x: center.x + radius * _cos(angle), y: center.y + radius * _sin(angle))
        }
    }

    private enum Segment: Equatable {
        case line(Point, Point)
        case quadratic(Point, Point, Point)
        case cubic(Point, Point, Point, Point)
        case arc(Arc)

        var start: Point {
            switch self {
            case .line(let start, _), .quadratic(let start, _, _), .cubic(let start, _, _, _): return start
            case .arc(let arc): return arc.start
            }
        }

        var end: Point {
            switch self {
            case .line(_, let end), .quadratic(_, _, let end), .cubic(_, _, _, let end): return end
            case .arc(let arc): return arc.end
            }
        }

        var element: PathElement {
            switch self {
            case .line(_, let end): return .lineTo(end)
            case .quadratic(_, let control, let end): return .quadraticCurveTo(control: control, end: end)
            case .cubic(_, let first, let second, let end):
                return .cubicCurveTo(control1: first, control2: second, end: end)
            case .arc(let arc):
                return .arc(
                    center: arc.center, radius: arc.radius, startAngle: arc.startAngle,
                    endAngle: arc.startAngle + arc.sweep, clockwise: arc.clockwise)
            }
        }

        var isCurve: Bool {
            switch self {
            case .quadratic, .cubic: return true
            case .line, .arc: return false
            }
        }

        func bounds() throws -> (lower: Double, upper: Double) {
            switch self {
            case .line(let start, let end):
                let length = try PathTrimming.distance(start, end)
                return (length, length)
            case .quadratic(let start, let control, let end):
                let chord = try PathTrimming.distance(start, end)
                let polygon = try PathTrimming.adding(
                    try PathTrimming.distance(start, control), try PathTrimming.distance(control, end))
                return (chord, max(chord, polygon))
            case .cubic(let start, let first, let second, let end):
                let chord = try PathTrimming.distance(start, end)
                let polygon = try PathTrimming.adding(
                    try PathTrimming.adding(
                        try PathTrimming.distance(start, first), try PathTrimming.distance(first, second)),
                    try PathTrimming.distance(second, end))
                return (chord, max(chord, polygon))
            case .arc(let arc):
                let length = arc.radius * abs(arc.sweep)
                guard length.isFinite else { throw Failure.numericalLimit }
                return (length, length)
            }
        }

        func split(at fraction: Double) throws -> (Segment, Segment) {
            switch self {
            case .line(let start, let end):
                let middle = try PathTrimming.interpolate(start, end, fraction)
                return (.line(start, middle), .line(middle, end))
            case .quadratic(let start, let control, let end):
                let first = try PathTrimming.interpolate(start, control, fraction)
                let second = try PathTrimming.interpolate(control, end, fraction)
                let middle = try PathTrimming.interpolate(first, second, fraction)
                return (.quadratic(start, first, middle), .quadratic(middle, second, end))
            case .cubic(let start, let first, let second, let end):
                let a = try PathTrimming.interpolate(start, first, fraction)
                let b = try PathTrimming.interpolate(first, second, fraction)
                let c = try PathTrimming.interpolate(second, end, fraction)
                let d = try PathTrimming.interpolate(a, b, fraction)
                let e = try PathTrimming.interpolate(b, c, fraction)
                let middle = try PathTrimming.interpolate(d, e, fraction)
                return (.cubic(start, a, d, middle), .cubic(middle, e, c, end))
            case .arc(let arc):
                let sweep = arc.sweep * fraction
                var first = arc
                first.sweep = sweep
                var second = arc
                second.startAngle += sweep
                second.sweep -= sweep
                return (.arc(first), .arc(second))
            }
        }

        func sliced(from: Double, to: Double) throws -> Segment {
            if from == 0, to == 1 { return self }
            guard from >= 0, to <= 1, from < to else { throw Failure.numericalLimit }
            let prefix: Segment
            if to == 1 {
                prefix = self
            } else {
                prefix = try split(at: to).0
            }
            if from == 0 { return prefix }
            return try prefix.split(at: from / to).1
        }
    }

    private struct Contour {
        var origin: Point
        var segments: [Segment] = []
        var closed = false
    }

    private struct Length {
        var value: Double
        var error: Double
    }

    private struct MeasuredSegment {
        var segment: Segment
        var length: Length
    }

    private struct MeasuredContour {
        var source: Contour
        var segments: [MeasuredSegment]
        var length: Double
    }

    private struct Worker {
        let limits: Limits
        var remainingWork: Int

        init(limits: Limits) {
            self.limits = limits
            remainingWork = limits.maximumWork
        }

        mutating func spend() throws {
            guard remainingWork > 0 else { throw Failure.workLimit }
            remainingWork -= 1
        }

        mutating func trim(_ path: Path, from: Double, to: Double) throws -> Path {
            let contours = try decode(path)
            let count = contours.reduce(0) { $0 + $1.segments.count }
            guard count > 0 else { return Path() }
            let absoluteShare = PathTrimming.absoluteLengthTolerance / Double(count)
            var measured: [MeasuredContour] = []
            var total = 0.0
            for contour in contours {
                var segments: [MeasuredSegment] = []
                var contourLength = 0.0
                for segment in contour.segments {
                    try spend()
                    let upper = try segment.bounds().upper
                    let tolerance = absoluteShare + PathTrimming.relativeLengthTolerance * upper
                    guard tolerance.isFinite else { throw Failure.numericalLimit }
                    let length = try measure(segment, tolerance: tolerance, depth: 0)
                    contourLength = try PathTrimming.adding(contourLength, length.value)
                    segments.append(MeasuredSegment(segment: segment, length: length))
                }
                total = try PathTrimming.adding(total, contourLength)
                measured.append(MeasuredContour(source: contour, segments: segments, length: contourLength))
            }
            guard total > 0 else { return Path() }
            let firstDistance = from * total
            let lastDistance = to * total
            guard firstDistance < lastDistance else { throw Failure.numericalLimit }
            var output: [PathElement] = []
            var contourStart = 0.0
            for contour in measured {
                try spend()
                let contourEnd = try PathTrimming.adding(contourStart, contour.length)
                defer { contourStart = contourEnd }
                guard contour.length > 0, firstDistance < contourEnd, lastDistance > contourStart else { continue }
                if firstDistance <= contourStart, lastDistance >= contourEnd {
                    output.append(.moveTo(contour.source.origin))
                    let count = contour.segments.count - (contour.source.closed ? 1 : 0)
                    for segment in contour.segments.prefix(count) {
                        try spend()
                        output.append(segment.segment.element)
                    }
                    if contour.source.closed { output.append(.close) }
                    continue
                }
                var segmentStart = contourStart
                var began = false
                for measuredSegment in contour.segments {
                    try spend()
                    let length = measuredSegment.length.value
                    let segmentEnd = try PathTrimming.adding(segmentStart, length)
                    defer { segmentStart = segmentEnd }
                    let lower = max(firstDistance, segmentStart)
                    let upper = min(lastDistance, segmentEnd)
                    guard length > 0, lower < upper else { continue }
                    // A distant long line must not relax a small curve's
                    // endpoint precision. Aggregate path-length error remains
                    // separate from this local inversion allowance.
                    let endpointTolerance = max(
                        PathTrimming.absoluteLengthTolerance, PathTrimming.relativeLengthTolerance * length)
                    let startParameter: Double
                    if lower == segmentStart {
                        startParameter = 0
                    } else {
                        startParameter = try parameter(
                            for: lower - segmentStart, in: measuredSegment, tolerance: endpointTolerance)
                    }
                    let endParameter: Double
                    if upper == segmentEnd {
                        endParameter = 1
                    } else {
                        endParameter = try parameter(
                            for: upper - segmentStart, in: measuredSegment, tolerance: endpointTolerance)
                    }
                    let selected = try measuredSegment.segment.sliced(from: startParameter, to: endParameter)
                    try PathTrimming.validate(selected.start)
                    try PathTrimming.validate(selected.end)
                    if !began {
                        output.append(.moveTo(selected.start))
                        began = true
                    }
                    output.append(selected.element)
                }
            }
            return Path(elements: output)
        }

        mutating func decode(_ path: Path) throws -> [Contour] {
            var result: [Contour] = []
            var current: Contour?
            var point: Point?
            var segmentCount = 0
            for element in path.elements {
                try spend()
                switch element {
                case .moveTo(let next):
                    try PathTrimming.validate(next)
                    if let contour = current, !contour.segments.isEmpty { result.append(contour) }
                    current = Contour(origin: next)
                    point = next
                case .lineTo(let next):
                    try PathTrimming.validate(next)
                    guard let start = point, current != nil else { throw Failure.missingCurrentPoint }
                    current?.segments.append(.line(start, next))
                    segmentCount += 1
                    point = next
                case .quadraticCurveTo(let control, let next):
                    try PathTrimming.validate(control)
                    try PathTrimming.validate(next)
                    guard let start = point, current != nil else { throw Failure.missingCurrentPoint }
                    current?.segments.append(.quadratic(start, control, next))
                    segmentCount += 1
                    point = next
                case .cubicCurveTo(let first, let second, let next):
                    try PathTrimming.validate(first)
                    try PathTrimming.validate(second)
                    try PathTrimming.validate(next)
                    guard let start = point, current != nil else { throw Failure.missingCurrentPoint }
                    current?.segments.append(.cubic(start, first, second, next))
                    segmentCount += 1
                    point = next
                case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                    try PathTrimming.validate(center)
                    guard radius.isFinite, radius >= 0, startAngle.isFinite, endAngle.isFinite,
                        abs(startAngle) <= PathTrimming.maximumArcAngle, abs(endAngle) <= PathTrimming.maximumArcAngle
                    else { throw Failure.invalidGeometry }
                    let turn = 2 * Double.pi
                    var sweep = endAngle - startAngle
                    // A nonzero opposed whole turn keeps one requested-direction
                    // turn. Equal original angles bypass both branches and stay zero.
                    if clockwise, sweep > 0 {
                        sweep = sweep.truncatingRemainder(dividingBy: turn)
                        sweep -= turn
                    } else if !clockwise, sweep < 0 {
                        sweep = sweep.truncatingRemainder(dividingBy: turn)
                        sweep += turn
                    }
                    guard abs(sweep) <= PathTrimming.maximumArcAngle else { throw Failure.invalidGeometry }
                    guard (center.x - radius).isFinite, (center.x + radius).isFinite,
                        (center.y - radius).isFinite, (center.y + radius).isFinite
                    else { throw Failure.numericalLimit }
                    let arc = Arc(
                        center: center, radius: radius, startAngle: startAngle, sweep: sweep, clockwise: clockwise)
                    try PathTrimming.validate(arc.start)
                    try PathTrimming.validate(arc.end)
                    if let start = point, current != nil {
                        if start != arc.start {
                            current?.segments.append(.line(start, arc.start))
                            segmentCount += 1
                        }
                    } else {
                        current = Contour(origin: arc.start)
                    }
                    current?.segments.append(.arc(arc))
                    segmentCount += 1
                    point = arc.end
                case .close:
                    guard var contour = current, let start = point else { throw Failure.missingCurrentPoint }
                    contour.segments.append(.line(start, contour.origin))
                    contour.closed = true
                    result.append(contour)
                    segmentCount += 1
                    current = nil
                    point = nil
                }
                guard segmentCount <= limits.maximumSegments else { throw Failure.inputLimit }
            }
            if let contour = current, !contour.segments.isEmpty { result.append(contour) }
            return result
        }

        mutating func measure(
            _ segment: Segment, tolerance: Double, depth: Int,
            prepaidBounds: (lower: Double, upper: Double)? = nil
        ) throws -> Length {
            let bounds: (lower: Double, upper: Double)
            if let prepaidBounds {
                bounds = prepaidBounds
            } else {
                try spend()
                bounds = try segment.bounds()
            }
            guard tolerance.isFinite, tolerance >= 0 else { throw Failure.numericalLimit }
            guard segment.isCurve else { return Length(value: bounds.upper, error: 0) }
            let error = (bounds.upper - bounds.lower) * 0.5
            if error <= tolerance {
                return Length(value: bounds.lower + error, error: error)
            }
            guard depth < limits.maximumCurveDepth else { throw Failure.workLimit }
            let halves = try segment.split(at: 0.5)
            guard halves.0 != segment, halves.1 != segment else { throw Failure.numericalLimit }

            // Reserve only the sibling error that can be needed. A monotone
            // sibling must not discard half the allowance at a retracing cusp.
            // These right-child bounds are paid here and reused exactly once.
            try spend()
            let rightBounds = try halves.1.bounds()
            let reservedError = min(tolerance * 0.5, (rightBounds.upper - rightBounds.lower) * 0.5)
            let firstTolerance = tolerance - reservedError
            guard firstTolerance.isFinite, firstTolerance >= 0 else { throw Failure.numericalLimit }
            let first = try measure(halves.0, tolerance: firstTolerance, depth: depth + 1)
            let secondTolerance = tolerance - first.error
            guard secondTolerance.isFinite, secondTolerance >= 0 else { throw Failure.numericalLimit }
            let second = try measure(
                halves.1, tolerance: secondTolerance, depth: depth + 1, prepaidBounds: rightBounds)
            let length = try PathTrimming.adding(first.value, second.value)
            let combinedError = first.error + second.error
            guard combinedError.isFinite, combinedError <= tolerance else { throw Failure.numericalLimit }
            return Length(value: length, error: combinedError)
        }

        mutating func parameter(for distance: Double, in measured: MeasuredSegment, tolerance: Double) throws -> Double
        {
            guard distance > 0, distance < measured.length.value else { throw Failure.numericalLimit }
            guard measured.segment.isCurve else { return distance / measured.length.value }
            var lower = 0.0
            var upper = 1.0
            for _ in 0..<max(0, limits.maximumInverseIterations) {
                try spend()
                let middle = lower + (upper - lower) * 0.5
                guard middle > lower, middle < upper else { throw Failure.numericalLimit }
                let prefix = try measured.segment.split(at: middle).0
                let length = try measure(prefix, tolerance: tolerance * 0.25, depth: 0)
                if abs(length.value - distance) + length.error <= tolerance { return middle }
                if length.value < distance {
                    lower = middle
                } else {
                    upper = middle
                }
            }
            throw Failure.workLimit
        }
    }

    private static func validate(_ point: Point) throws {
        guard point.x.isFinite, point.y.isFinite else { throw Failure.invalidGeometry }
    }

    private static func distance(_ first: Point, _ second: Point) throws -> Double {
        let x = abs(second.x - first.x)
        let y = abs(second.y - first.y)
        guard x.isFinite, y.isFinite else { throw Failure.numericalLimit }
        let scale = max(x, y)
        if scale == 0 { return 0 }
        let length = scale * ((x / scale) * (x / scale) + (y / scale) * (y / scale)).squareRoot()
        guard length.isFinite else { throw Failure.numericalLimit }
        return length
    }

    private static func adding(_ first: Double, _ second: Double) throws -> Double {
        if first == 0 { return second }
        if second == 0 { return first }
        let result = first + second
        guard result.isFinite, result > first, result > second else { throw Failure.numericalLimit }
        return result
    }

    private static func interpolate(_ first: Point, _ second: Point, _ fraction: Double) throws -> Point {
        if fraction == 0 { return first }
        if fraction == 1 { return second }
        let result = Point(
            x: (1 - fraction) * first.x + fraction * second.x,
            y: (1 - fraction) * first.y + fraction * second.y)
        guard result.x.isFinite, result.y.isFinite else { throw Failure.numericalLimit }
        return result
    }
}
