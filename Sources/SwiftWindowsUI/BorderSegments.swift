import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics

struct BorderSegment: Equatable, Sendable {
    var rect: Rect
    var cornerRadius: Double
}

enum BorderSegments {
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
            cornerRadius: r,
            topLength: topLength,
            rightLength: rightLength,
            bottomLength: bottomLength,
            leftLength: leftLength,
            arcLength: arcLength,
            capExtension: 0,
            capRadius: 0,
            into: &segments
        )
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

        let topLength = max(0, frame.size.width - 2 * r)
        let rightLength = max(0, frame.size.height - 2 * r)
        let bottomLength = max(0, frame.size.width - 2 * r)
        let leftLength = max(0, frame.size.height - 2 * r)
        let arcLength = Double.pi * r / 2
        let perimeter = topLength + rightLength + bottomLength + leftLength + 4 * arcLength

        guard perimeter > 0 else {
            return []
        }

        let patternLength = dashPattern.reduce(0, +)
        guard patternLength > 0 else {
            return nil
        }

        var patternIndex = 0
        var patternOffset = positiveRemainder(strokeStyle.dashOffset, by: patternLength)
        while patternOffset >= dashPattern[patternIndex] {
            patternOffset -= dashPattern[patternIndex]
            patternIndex = (patternIndex + 1) % dashPattern.count
        }

        let capExtension = strokeStyle.lineCap == .butt ? 0 : segmentWidth * 0.5
        let capRadius = strokeStyle.lineCap == .round ? segmentWidth * 0.5 : 0

        var distance = 0.0
        var segments: [BorderSegment] = []
        while distance < perimeter {
            let remainingPatternLength = dashPattern[patternIndex] - patternOffset
            let length = min(remainingPatternLength, perimeter - distance)
            if patternIndex.isMultiple(of: 2), length > 0 {
                appendDashSegment(
                    from: distance,
                    to: distance + length,
                    frame: frame,
                    width: segmentWidth,
                    cornerRadius: r,
                    topLength: topLength,
                    rightLength: rightLength,
                    bottomLength: bottomLength,
                    leftLength: leftLength,
                    arcLength: arcLength,
                    capExtension: capExtension,
                    capRadius: capRadius,
                    into: &segments
                )
            }

            distance += max(length, 0.01)
            patternIndex = (patternIndex + 1) % dashPattern.count
            patternOffset = 0
        }

        return segments
    }

    // MARK: - Dash segment decomposition

    private static func appendDashSegment(
        from start: Double,
        to end: Double,
        frame: Rect,
        width: Double,
        cornerRadius: Double,
        topLength: Double,
        rightLength: Double,
        bottomLength: Double,
        leftLength: Double,
        arcLength: Double,
        capExtension: Double,
        capRadius: Double,
        into segments: inout [BorderSegment]
    ) {
        let perimeterRegions = [
            (length: topLength, kind: PerimeterRegionKind.topEdge),
            (length: arcLength, kind: PerimeterRegionKind.topRightArc),
            (length: rightLength, kind: PerimeterRegionKind.rightEdge),
            (length: arcLength, kind: PerimeterRegionKind.bottomRightArc),
            (length: bottomLength, kind: PerimeterRegionKind.bottomEdge),
            (length: arcLength, kind: PerimeterRegionKind.bottomLeftArc),
            (length: leftLength, kind: PerimeterRegionKind.leftEdge),
            (length: arcLength, kind: PerimeterRegionKind.topLeftArc),
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
                    xOrigin: frame.origin.x + cornerRadius,
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
                    cornerRadius: cornerRadius,
                    arcLength: arcLength,
                    capExtension: capExtension,
                    into: &segments
                )
            case .rightEdge:
                appendVerticalEdge(
                    from: regionStart + localStart,
                    to: regionStart + localEnd,
                    edgeStart: topLength + arcLength,
                    edgeEnd: topLength + arcLength + rightLength,
                    x: frame.maxX - width,
                    yOrigin: frame.origin.y + cornerRadius,
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
                    cornerRadius: cornerRadius,
                    arcLength: arcLength,
                    capExtension: capExtension,
                    into: &segments
                )
            case .bottomEdge:
                appendHorizontalEdge(
                    from: regionStart + localStart,
                    to: regionStart + localEnd,
                    edgeStart: topLength + arcLength + rightLength + arcLength,
                    edgeEnd: topLength + arcLength + rightLength + arcLength + bottomLength,
                    xOrigin: frame.origin.x + cornerRadius,
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
                    cornerRadius: cornerRadius,
                    arcLength: arcLength,
                    capExtension: capExtension,
                    into: &segments
                )
            case .leftEdge:
                appendVerticalEdge(
                    from: regionStart + localStart,
                    to: regionStart + localEnd,
                    edgeStart: topLength + arcLength + rightLength + arcLength + bottomLength + arcLength,
                    edgeEnd: topLength + arcLength + rightLength + arcLength + bottomLength + arcLength + leftLength,
                    x: frame.origin.x,
                    yOrigin: frame.origin.y + cornerRadius,
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
                    cornerRadius: cornerRadius,
                    arcLength: arcLength,
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
            (frame.maxX - r, frame.origin.y + r),   // top-right
            (frame.maxX - r, frame.maxY - r),         // bottom-right
            (frame.origin.x + r, frame.maxY - r),     // bottom-left
            (frame.origin.x + r, frame.origin.y + r), // top-left
        ]
        // Start angles for the four corners (top, right, bottom, left edges)
        let baseAngles: [Double] = [
            -Double.pi / 2, // top-right: starts at top
            0,              // bottom-right: starts at right
            Double.pi / 2,  // bottom-left: starts at bottom
            Double.pi,      // top-left: starts at left
        ]

        let (cx, cy) = centers[arcIndex]
        let baseAngle = baseAngles[arcIndex]

        for i in 0..<subCount {
            let subStart = start + Double(i) * step
            let subEnd = min(subStart + step, end)
            let subLength = subEnd - subStart
            guard subLength > 0 else { continue }

            let θ1 = baseAngle + (subStart / arcLength) * (Double.pi / 2)
            let θ2 = baseAngle + (subEnd / arcLength) * (Double.pi / 2)

            // Bounding box of the annular sector from innerR to r, θ1..θ2
            let xs = [cos(θ1), cos(θ2)].sorted()
            let ys = [sin(θ1), sin(θ2)].sorted()

            let minX = cx + innerR * xs[0]
            let maxX = cx + r * xs[1]
            let minY = cy + r * ys[0]
            let maxY = cy + innerR * ys[1]

            // Apply square/round cap extension along the arc tangent.
            // This is an axis-aligned approximation of the true tangent extension.
            let capX = capExtension * abs(cos((θ1 + θ2) * 0.5))
            let capY = capExtension * abs(sin((θ1 + θ2) * 0.5))

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
