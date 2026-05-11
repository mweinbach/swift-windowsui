import SwiftWindowsCore
import SwiftWindowsGraphics

struct BorderSegment: Equatable, Sendable {
    var rect: Rect
    var cornerRadius: Double
}

enum BorderSegments {
    static func dashedSegments(
        frame: Rect,
        width: Double,
        cornerRadius: Double,
        strokeStyle: StrokeStyle?
    ) -> [BorderSegment]? {
        guard cornerRadius <= 0, width > 0, frame.size.width > 0, frame.size.height > 0 else {
            return nil
        }
        guard let strokeStyle else {
            return nil
        }

        let dashPattern = normalizedDashPattern(strokeStyle.dashPattern)
        guard !dashPattern.isEmpty else {
            return nil
        }

        let segmentWidth = min(width, frame.size.width * 0.5, frame.size.height * 0.5)
        guard segmentWidth > 0 else {
            return []
        }

        let perimeter = (frame.size.width + frame.size.height) * 2
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

        var distance = 0.0
        var segments: [BorderSegment] = []
        while distance < perimeter {
            let remainingPatternLength = dashPattern[patternIndex] - patternOffset
            let length = min(remainingPatternLength, perimeter - distance)
            if patternIndex.isMultiple(of: 2), length > 0 {
                appendSegments(
                    from: distance,
                    to: distance + length,
                    frame: frame,
                    width: segmentWidth,
                    lineCap: strokeStyle.lineCap,
                    into: &segments
                )
            }

            distance += max(length, 0.01)
            patternIndex = (patternIndex + 1) % dashPattern.count
            patternOffset = 0
        }

        return segments
    }

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

    private static func appendSegments(
        from start: Double,
        to end: Double,
        frame: Rect,
        width: Double,
        lineCap: StrokeStyle.LineCap,
        into segments: inout [BorderSegment]
    ) {
        let topEnd = frame.size.width
        let rightEnd = topEnd + frame.size.height
        let bottomEnd = rightEnd + frame.size.width
        let leftEnd = bottomEnd + frame.size.height
        let capExtension = lineCap == .butt ? 0 : width * 0.5
        let capRadius = lineCap == .round ? width * 0.5 : 0

        appendHorizontalEdge(
            from: start,
            to: end,
            edgeStart: 0,
            edgeEnd: topEnd,
            xOrigin: frame.origin.x,
            y: frame.origin.y,
            leftToRight: true,
            width: width,
            capExtension: capExtension,
            capRadius: capRadius,
            into: &segments
        )
        appendVerticalEdge(
            from: start,
            to: end,
            edgeStart: topEnd,
            edgeEnd: rightEnd,
            x: frame.maxX - width,
            yOrigin: frame.origin.y,
            topToBottom: true,
            width: width,
            capExtension: capExtension,
            capRadius: capRadius,
            into: &segments
        )
        appendHorizontalEdge(
            from: start,
            to: end,
            edgeStart: rightEnd,
            edgeEnd: bottomEnd,
            xOrigin: frame.origin.x,
            y: frame.maxY - width,
            leftToRight: false,
            width: width,
            capExtension: capExtension,
            capRadius: capRadius,
            into: &segments
        )
        appendVerticalEdge(
            from: start,
            to: end,
            edgeStart: bottomEnd,
            edgeEnd: leftEnd,
            x: frame.origin.x,
            yOrigin: frame.origin.y,
            topToBottom: false,
            width: width,
            capExtension: capExtension,
            capRadius: capRadius,
            into: &segments
        )
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
