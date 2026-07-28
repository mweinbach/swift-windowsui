import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics

struct BorderSegment: Equatable, Sendable {
    var rect: Rect
    var cornerRadius: Double
}

enum BorderSegments {
    /// Largest number of dash-pattern steps one border walk may take.
    ///
    /// The walk advances by the current pattern entry, so a pattern finer than
    /// the perimeter can resolve — `StrokeStyle(dashPattern: [0.001, 0.001])`
    /// on a 4 000 pt perimeter — used to emit hundreds of thousands of
    /// segments per border per frame. The step floor below keeps the walk
    /// covering the whole perimeter while degrading dash granularity rather
    /// than frame time.
    private static let maxDashSteps = 4_096
    /// Generates solid border-ring segments (top/bottom/left/right edges and
    /// four corner arcs) so the border can be drawn as thin quads rather than
    /// a full-rect fill.  This keeps the border visible when it must be drawn
    /// after child content.
    static func solidSegments(
        frame: Rect,
        width: Double,
        cornerRadius: Double
    ) -> [BorderSegment] {
        guard width > 0, frame.size.width > 0, frame.size.height > 0 else {
            return []
        }

        let r = max(0, min(cornerRadius, min(frame.size.width, frame.size.height) * 0.5))
        let segmentWidth = min(width, frame.size.width * 0.5, frame.size.height * 0.5)
        guard segmentWidth > 0 else {
            return []
        }

        let topLength = max(0, frame.size.width - 2 * r)
        let rightLength = max(0, frame.size.height - 2 * r)
        let bottomLength = max(0, frame.size.width - 2 * r)
        let leftLength = max(0, frame.size.height - 2 * r)
        let arcLength = Double.pi * r / 2
        let perimeter = topLength + rightLength + bottomLength + leftLength + 4 * arcLength

        guard perimeter > 0 else {
            return []
        }

        var segments: [BorderSegment] = []
        appendDashSegment(
            from: 0,
            to: perimeter,
            frame: frame,
            width: segmentWidth,
            cornerRadii: RetainedCornerRadii(uniform: r),
            capExtension: 0,
            capRadius: 0,
            into: &segments
        )
        return segments
    }

    /// Per-corner variant of ``solidSegments(frame:width:cornerRadius:)``.
    /// Edge spans shrink by the radii of the corners they join, and only
    /// corners with a positive radius emit arc segments — square corners
    /// get no geometry, so the overlay can't paint faint arcs there.
    /// With four equal radii this produces the same segments as the
    /// uniform variant.
    static func solidSegments(
        frame: Rect,
        width: Double,
        cornerRadii: RetainedCornerRadii
    ) -> [BorderSegment] {
        guard width > 0, frame.size.width > 0, frame.size.height > 0 else {
            return []
        }

        let segmentWidth = min(width, frame.size.width * 0.5, frame.size.height * 0.5)
        guard segmentWidth > 0 else {
            return []
        }

        let radiusCap = min(frame.size.width, frame.size.height) * 0.5
        let topLeft = max(0, min(cornerRadii.topLeft, radiusCap))
        let topRight = max(0, min(cornerRadii.topRight, radiusCap))
        let bottomRight = max(0, min(cornerRadii.bottomRight, radiusCap))
        let bottomLeft = max(0, min(cornerRadii.bottomLeft, radiusCap))

        var segments: [BorderSegment] = []

        // Edges span between the corner zones; each corner's arc fills the
        // remaining gap (see appendCornerArc).
        let top = Rect(
            x: frame.origin.x + topLeft,
            y: frame.origin.y,
            width: frame.size.width - topLeft - topRight,
            height: segmentWidth
        )
        let right = Rect(
            x: frame.maxX - segmentWidth,
            y: frame.origin.y + topRight,
            width: segmentWidth,
            height: frame.size.height - topRight - bottomRight
        )
        let bottom = Rect(
            x: frame.origin.x + bottomLeft,
            y: frame.maxY - segmentWidth,
            width: frame.size.width - bottomLeft - bottomRight,
            height: segmentWidth
        )
        let left = Rect(
            x: frame.origin.x,
            y: frame.origin.y + topLeft,
            width: segmentWidth,
            height: frame.size.height - topLeft - bottomLeft
        )
        for edge in [top, right, bottom, left] where edge.size.width > 0 && edge.size.height > 0 {
            segments.append(BorderSegment(rect: edge, cornerRadius: 0))
        }

        let corners: [(arcIndex: Int, radius: Double)] = [
            (0, topRight),
            (1, bottomRight),
            (2, bottomLeft),
            (3, topLeft),
        ]
        for corner in corners where corner.radius > 0 {
            appendCornerArc(
                arcIndex: corner.arcIndex,
                from: 0,
                to: Double.pi * corner.radius / 2,
                frame: frame,
                width: segmentWidth,
                cornerRadius: corner.radius,
                arcLength: Double.pi * corner.radius / 2,
                capExtension: 0,
                into: &segments
            )
        }

        return segments
    }

    static func dashedSegments(
        frame: Rect,
        width: Double,
        cornerRadius: Double,
        strokeStyle: StrokeStyle?
    ) -> [BorderSegment]? {
        guard width > 0, frame.size.width > 0, frame.size.height > 0 else {
            return nil
        }
        guard let strokeStyle else {
            return nil
        }

        let dashPattern = normalizedDashPattern(strokeStyle.dashPattern)
        guard !dashPattern.isEmpty else {
            return nil
        }

        let r = max(0, min(cornerRadius, min(frame.size.width, frame.size.height) * 0.5))
        let segmentWidth = min(width, frame.size.width * 0.5, frame.size.height * 0.5)
        guard segmentWidth > 0 else {
            return []
        }

        return dashedSegments(
            frame: frame,
            segmentWidth: segmentWidth,
            cornerRadii: RetainedCornerRadii(uniform: r),
            dashPattern: dashPattern,
            dashOffset: strokeStyle.dashOffset,
            lineCap: strokeStyle.lineCap
        )
    }

    /// Per-corner variant of ``dashedSegments(frame:width:cornerRadius:strokeStyle:)``.
    /// Edge spans shrink by the radii of the corners they join, and
    /// zero-radius corners contribute no arc region, so dashed borders no
    /// longer paint arcs at deliberately square corners. With four equal
    /// radii this produces the same segments as the uniform variant (both
    /// share the same walk below).
    static func dashedSegments(
        frame: Rect,
        width: Double,
        cornerRadii: RetainedCornerRadii,
        strokeStyle: StrokeStyle?
    ) -> [BorderSegment]? {
        guard width > 0, frame.size.width > 0, frame.size.height > 0 else {
            return nil
        }
        guard let strokeStyle else {
            return nil
        }

        let dashPattern = normalizedDashPattern(strokeStyle.dashPattern)
        guard !dashPattern.isEmpty else {
            return nil
        }

        let radiusCap = min(frame.size.width, frame.size.height) * 0.5
        let clampedRadii = RetainedCornerRadii(
            topLeft: max(0, min(cornerRadii.topLeft, radiusCap)),
            topRight: max(0, min(cornerRadii.topRight, radiusCap)),
            bottomRight: max(0, min(cornerRadii.bottomRight, radiusCap)),
            bottomLeft: max(0, min(cornerRadii.bottomLeft, radiusCap))
        )
        let segmentWidth = min(width, frame.size.width * 0.5, frame.size.height * 0.5)
        guard segmentWidth > 0 else {
            return []
        }

        return dashedSegments(
            frame: frame,
            segmentWidth: segmentWidth,
            cornerRadii: clampedRadii,
            dashPattern: dashPattern,
            dashOffset: strokeStyle.dashOffset,
            lineCap: strokeStyle.lineCap
        )
    }

    /// Shared dash walk behind both public ``dashedSegments`` overloads.
    private static func dashedSegments(
        frame: Rect,
        segmentWidth: Double,
        cornerRadii: RetainedCornerRadii,
        dashPattern: [Double],
        dashOffset: Double,
        lineCap: StrokeStyle.LineCap
    ) -> [BorderSegment]? {
        let topLength = max(0, frame.size.width - cornerRadii.topLeft - cornerRadii.topRight)
        let rightLength = max(0, frame.size.height - cornerRadii.topRight - cornerRadii.bottomRight)
        let bottomLength = max(0, frame.size.width - cornerRadii.bottomLeft - cornerRadii.bottomRight)
        let leftLength = max(0, frame.size.height - cornerRadii.topLeft - cornerRadii.bottomLeft)
        let arcLength =
            Double.pi
            * (cornerRadii.topLeft + cornerRadii.topRight + cornerRadii.bottomRight + cornerRadii.bottomLeft)
            / 2
        let perimeter = topLength + rightLength + bottomLength + leftLength + arcLength

        guard perimeter > 0 else {
            return []
        }

        let patternLength = dashPattern.reduce(0, +)
        guard patternLength > 0 else {
            return nil
        }

        var patternIndex = 0
        var patternOffset = positiveRemainder(dashOffset, by: patternLength)
        while patternOffset >= dashPattern[patternIndex] {
            patternOffset -= dashPattern[patternIndex]
            patternIndex = (patternIndex + 1) % dashPattern.count
        }

        let capExtension = lineCap == .butt ? 0 : segmentWidth * 0.5
        let capRadius = lineCap == .round ? segmentWidth * 0.5 : 0

        // Every step advances at least this far, so the walk always terminates
        // within `maxDashSteps` regardless of how fine the pattern is. For any
        // pattern coarser than perimeter/4096 (i.e. every real one) the floor
        // is below the pattern entries and the walk is unchanged.
        let minimumStep = max(perimeter / Double(maxDashSteps), 0.01)

        var distance = 0.0
        var segments: [BorderSegment] = []
        var steps = 0
        while distance < perimeter, steps < maxDashSteps {
            steps += 1
            let remainingPatternLength = dashPattern[patternIndex] - patternOffset
            let length = min(remainingPatternLength, perimeter - distance)
            if patternIndex.isMultiple(of: 2), length > 0 {
                appendDashSegment(
                    from: distance,
                    to: distance + length,
                    frame: frame,
                    width: segmentWidth,
                    cornerRadii: cornerRadii,
                    capExtension: capExtension,
                    capRadius: capRadius,
                    into: &segments
                )
            }

            distance += max(length, minimumStep)
            patternIndex = (patternIndex + 1) % dashPattern.count
            patternOffset = 0
        }

        return segments
    }

    // MARK: - Dash segment decomposition

    /// Walks the perimeter region list for a dash sub-range. Perimeter
    /// order matches the historic uniform walk: top edge, top-right arc,
    /// right edge, bottom-right arc, bottom edge, bottom-left arc, left
    /// edge, top-left arc. Edge spans shrink by the radii of the corners
    /// they join; a zero-radius corner contributes a zero-length arc
    /// region, so square corners get no arc geometry.
    private static func appendDashSegment(
        from start: Double,
        to end: Double,
        frame: Rect,
        width: Double,
        cornerRadii: RetainedCornerRadii,
        capExtension: Double,
        capRadius: Double,
        into segments: inout [BorderSegment]
    ) {
        let topLength = max(0, frame.size.width - cornerRadii.topLeft - cornerRadii.topRight)
        let rightLength = max(0, frame.size.height - cornerRadii.topRight - cornerRadii.bottomRight)
        let bottomLength = max(0, frame.size.width - cornerRadii.bottomLeft - cornerRadii.bottomRight)
        let leftLength = max(0, frame.size.height - cornerRadii.topLeft - cornerRadii.bottomLeft)
        let topRightArcLength = Double.pi * cornerRadii.topRight / 2
        let bottomRightArcLength = Double.pi * cornerRadii.bottomRight / 2
        let bottomLeftArcLength = Double.pi * cornerRadii.bottomLeft / 2
        let topLeftArcLength = Double.pi * cornerRadii.topLeft / 2

        let perimeterRegions = [
            (length: topLength, kind: PerimeterRegionKind.topEdge),
            (length: topRightArcLength, kind: PerimeterRegionKind.topRightArc),
            (length: rightLength, kind: PerimeterRegionKind.rightEdge),
            (length: bottomRightArcLength, kind: PerimeterRegionKind.bottomRightArc),
            (length: bottomLength, kind: PerimeterRegionKind.bottomEdge),
            (length: bottomLeftArcLength, kind: PerimeterRegionKind.bottomLeftArc),
            (length: leftLength, kind: PerimeterRegionKind.leftEdge),
            (length: topLeftArcLength, kind: PerimeterRegionKind.topLeftArc),
        ]

        var current = start
        var regionStart: Double = 0
        for region in perimeterRegions {
            let regionEnd = regionStart + region.length
            guard current < end, current < regionEnd else {
                regionStart = regionEnd
                continue
            }

            let localStart = max(0, current - regionStart)
            let localEnd = min(region.length, end - regionStart)
            let subLength = localEnd - localStart
            guard subLength > 0 else {
                regionStart = regionEnd
                continue
            }

            switch region.kind {
            case .topEdge:
                appendHorizontalEdge(
                    from: regionStart + localStart,
                    to: regionStart + localEnd,
                    edgeStart: 0,
                    edgeEnd: topLength,
                    xOrigin: frame.origin.x + cornerRadii.topLeft,
                    y: frame.origin.y,
                    leftToRight: true,
                    width: width,
                    capExtension: capExtension,
                    capRadius: capRadius,
                    into: &segments
                )
            case .topRightArc:
                appendCornerArc(
                    arcIndex: 0,
                    from: localStart,
                    to: localEnd,
                    frame: frame,
                    width: width,
                    cornerRadius: cornerRadii.topRight,
                    arcLength: topRightArcLength,
                    capExtension: capExtension,
                    into: &segments
                )
            case .rightEdge:
                appendVerticalEdge(
                    from: regionStart + localStart,
                    to: regionStart + localEnd,
                    edgeStart: topLength + topRightArcLength,
                    edgeEnd: topLength + topRightArcLength + rightLength,
                    x: frame.maxX - width,
                    yOrigin: frame.origin.y + cornerRadii.topRight,
                    topToBottom: true,
                    width: width,
                    capExtension: capExtension,
                    capRadius: capRadius,
                    into: &segments
                )
            case .bottomRightArc:
                appendCornerArc(
                    arcIndex: 1,
                    from: localStart,
                    to: localEnd,
                    frame: frame,
                    width: width,
                    cornerRadius: cornerRadii.bottomRight,
                    arcLength: bottomRightArcLength,
                    capExtension: capExtension,
                    into: &segments
                )
            case .bottomEdge:
                appendHorizontalEdge(
                    from: regionStart + localStart,
                    to: regionStart + localEnd,
                    edgeStart: topLength + topRightArcLength + rightLength + bottomRightArcLength,
                    edgeEnd: topLength + topRightArcLength + rightLength + bottomRightArcLength + bottomLength,
                    xOrigin: frame.origin.x + cornerRadii.bottomLeft,
                    y: frame.maxY - width,
                    leftToRight: false,
                    width: width,
                    capExtension: capExtension,
                    capRadius: capRadius,
                    into: &segments
                )
            case .bottomLeftArc:
                appendCornerArc(
                    arcIndex: 2,
                    from: localStart,
                    to: localEnd,
                    frame: frame,
                    width: width,
                    cornerRadius: cornerRadii.bottomLeft,
                    arcLength: bottomLeftArcLength,
                    capExtension: capExtension,
                    into: &segments
                )
            case .leftEdge:
                appendVerticalEdge(
                    from: regionStart + localStart,
                    to: regionStart + localEnd,
                    edgeStart: topLength + topRightArcLength + rightLength + bottomRightArcLength + bottomLength
                        + bottomLeftArcLength,
                    edgeEnd: topLength + topRightArcLength + rightLength + bottomRightArcLength + bottomLength
                        + bottomLeftArcLength + leftLength,
                    x: frame.origin.x,
                    yOrigin: frame.origin.y + cornerRadii.topLeft,
                    topToBottom: false,
                    width: width,
                    capExtension: capExtension,
                    capRadius: capRadius,
                    into: &segments
                )
            case .topLeftArc:
                appendCornerArc(
                    arcIndex: 3,
                    from: localStart,
                    to: localEnd,
                    frame: frame,
                    width: width,
                    cornerRadius: cornerRadii.topLeft,
                    arcLength: topLeftArcLength,
                    capExtension: capExtension,
                    into: &segments
                )
            }

            current = regionEnd
            regionStart = regionEnd
        }
    }

    private enum PerimeterRegionKind {
        case topEdge, topRightArc, rightEdge, bottomRightArc
        case bottomEdge, bottomLeftArc, leftEdge, topLeftArc
    }

    // MARK: - Corner arc approximation

    /// Approximates a dashed corner-arc segment with axis-aligned quads.
    ///
    /// Because `QuadPrimitive` only supports axis-aligned rectangles, a true
    /// curved arc segment is approximated by its bounding box.  For small
    /// arc pieces (typical dash lengths) the visual error is minimal.  For
    /// large pieces the arc is subdivided so each sub-box stays tight.
    ///
    /// Note: on fully-transparent fills the inward overdraw of the bounding
    /// box may be faintly visible at very large border widths.
    private static func appendCornerArc(
        arcIndex: Int,
        from start: Double,
        to end: Double,
        frame: Rect,
        width: Double,
        cornerRadius: Double,
        arcLength: Double,
        capExtension: Double,
        into segments: inout [BorderSegment]
    ) {
        guard cornerRadius > 0, arcLength > 0 else {
            return
        }

        let r = cornerRadius
        let innerR = max(0, r - width)
        let maxSubArcLength = max(2.0, width)
        let subCount = max(1, Int(ceil((end - start) / maxSubArcLength)))
        let step = (end - start) / Double(subCount)

        // Arc centres for the four corners (outer arc, inner arc share centre)
        let centers: [(cx: Double, cy: Double)] = [
            (frame.maxX - r, frame.origin.y + r),  // top-right
            (frame.maxX - r, frame.maxY - r),  // bottom-right
            (frame.origin.x + r, frame.maxY - r),  // bottom-left
            (frame.origin.x + r, frame.origin.y + r),  // top-left
        ]
        // Start angles for the four corners (top, right, bottom, left edges)
        let baseAngles: [Double] = [
            -Double.pi / 2,  // top-right: starts at top
            0,  // bottom-right: starts at right
            Double.pi / 2,  // bottom-left: starts at bottom
            Double.pi,  // top-left: starts at left
        ]

        let (cx, cy) = centers[arcIndex]
        let baseAngle = baseAngles[arcIndex]

        for i in 0..<subCount {
            let subStart = start + Double(i) * step
            let subEnd = min(subStart + step, end)
            let subLength = subEnd - subStart
            guard subLength > 0 else { continue }

            let theta1 = baseAngle + (subStart / arcLength) * (Double.pi / 2)
            let theta2 = baseAngle + (subEnd / arcLength) * (Double.pi / 2)

            // Bounding box of the annular sector from innerR to r, theta1..theta2
            let xs = [cos(theta1), cos(theta2)].sorted()
            let ys = [sin(theta1), sin(theta2)].sorted()

            let minX = cx + innerR * xs[0]
            let maxX = cx + r * xs[1]
            let minY = cy + r * ys[0]
            let maxY = cy + innerR * ys[1]

            // Apply square/round cap extension along the arc tangent.
            // This is an axis-aligned approximation of the true tangent extension.
            let capX = capExtension * abs(cos((theta1 + theta2) * 0.5))
            let capY = capExtension * abs(sin((theta1 + theta2) * 0.5))

            let rect = Rect(
                x: minX - capX,
                y: minY - capY,
                width: maxX - minX + capX * 2,
                height: maxY - minY + capY * 2
            )
            guard rect.size.width > 0, rect.size.height > 0 else { continue }

            let pillRadius = min(width * 0.5, min(rect.size.width, rect.size.height) * 0.5)
            segments.append(BorderSegment(rect: rect, cornerRadius: pillRadius))
        }
    }

    // MARK: - Existing helpers

    private static func normalizedDashPattern(_ pattern: [Double]) -> [Double] {
        let positivePattern = pattern.filter { $0 > 0 }
        guard !positivePattern.isEmpty else {
            return []
        }
        if positivePattern.count.isMultiple(of: 2) {
            return positivePattern
        }
        return positivePattern + positivePattern
    }

    private static func positiveRemainder(_ value: Double, by divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }

    private static func appendHorizontalEdge(
        from start: Double,
        to end: Double,
        edgeStart: Double,
        edgeEnd: Double,
        xOrigin: Double,
        y: Double,
        leftToRight: Bool,
        width strokeWidth: Double,
        capExtension: Double,
        capRadius: Double,
        into segments: inout [BorderSegment]
    ) {
        let clippedStart = max(start - capExtension, edgeStart)
        let clippedEnd = min(end + capExtension, edgeEnd)
        guard clippedEnd > clippedStart else {
            return
        }

        let edgeLength = edgeEnd - edgeStart
        let localStart = clippedStart - edgeStart
        let localEnd = clippedEnd - edgeStart
        let x = leftToRight ? xOrigin + localStart : xOrigin + edgeLength - localEnd
        let rect = Rect(x: x, y: y, width: localEnd - localStart, height: strokeWidth)
        segments.append(BorderSegment(rect: rect, cornerRadius: capRadius))
    }

    private static func appendVerticalEdge(
        from start: Double,
        to end: Double,
        edgeStart: Double,
        edgeEnd: Double,
        x: Double,
        yOrigin: Double,
        topToBottom: Bool,
        width strokeWidth: Double,
        capExtension: Double,
        capRadius: Double,
        into segments: inout [BorderSegment]
    ) {
        let clippedStart = max(start - capExtension, edgeStart)
        let clippedEnd = min(end + capExtension, edgeEnd)
        guard clippedEnd > clippedStart else {
            return
        }

        let edgeLength = edgeEnd - edgeStart
        let localStart = clippedStart - edgeStart
        let localEnd = clippedEnd - edgeStart
        let y = topToBottom ? yOrigin + localStart : yOrigin + edgeLength - localEnd
        let rect = Rect(x: x, y: y, width: strokeWidth, height: localEnd - localStart)
        segments.append(BorderSegment(rect: rect, cornerRadius: capRadius))
    }
}
