import SwiftWindowsCore
import SwiftWindowsGraphics

enum BorderSegments {
    static func dashedRects(
        frame: Rect,
        width: Double,
        cornerRadius: Double,
        strokeStyle: StrokeStyle?
    ) -> [Rect]? {
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
        var rects: [Rect] = []
        while distance < perimeter {
            let remainingPatternLength = dashPattern[patternIndex] - patternOffset
            let length = min(remainingPatternLength, perimeter - distance)
            if patternIndex.isMultiple(of: 2), length > 0 {
                appendRects(
                    from: distance,
                    to: distance + length,
                    frame: frame,
                    width: segmentWidth,
                    into: &rects
                )
            }

            distance += max(length, 0.01)
            patternIndex = (patternIndex + 1) % dashPattern.count
            patternOffset = 0
        }

        return rects
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

    private static func appendRects(
        from start: Double,
        to end: Double,
        frame: Rect,
        width: Double,
        into rects: inout [Rect]
    ) {
        let topEnd = frame.size.width
        let rightEnd = topEnd + frame.size.height
        let bottomEnd = rightEnd + frame.size.width
        let leftEnd = bottomEnd + frame.size.height

        appendHorizontalEdge(
            from: start,
            to: end,
            edgeStart: 0,
            edgeEnd: topEnd,
            xOrigin: frame.origin.x,
            y: frame.origin.y,
            leftToRight: true,
            width: width,
            into: &rects
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
            into: &rects
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
            into: &rects
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
            into: &rects
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
        into rects: inout [Rect]
    ) {
        let clippedStart = max(start, edgeStart)
        let clippedEnd = min(end, edgeEnd)
        guard clippedEnd > clippedStart else {
            return
        }

        let edgeLength = edgeEnd - edgeStart
        let localStart = clippedStart - edgeStart
        let localEnd = clippedEnd - edgeStart
        let x = leftToRight ? xOrigin + localStart : xOrigin + edgeLength - localEnd
        rects.append(Rect(x: x, y: y, width: localEnd - localStart, height: strokeWidth))
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
        into rects: inout [Rect]
    ) {
        let clippedStart = max(start, edgeStart)
        let clippedEnd = min(end, edgeEnd)
        guard clippedEnd > clippedStart else {
            return
        }

        let edgeLength = edgeEnd - edgeStart
        let localStart = clippedStart - edgeStart
        let localEnd = clippedEnd - edgeStart
        let y = topToBottom ? yOrigin + localStart : yOrigin + edgeLength - localEnd
        rects.append(Rect(x: x, y: y, width: strokeWidth, height: localEnd - localStart))
    }
}
