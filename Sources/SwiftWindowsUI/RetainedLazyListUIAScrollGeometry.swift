import SwiftWindowsCore

/// Finite arithmetic for one vertical, unanchored reveal. These values contain
/// no attachment, layout, input, or publication authority; the runtime must
/// separately validate the original request before applying the result.
struct RetainedLazyListUIAScrollGeometry: Sendable {
    struct Offset: Equatable, Sendable {
        let requestedOffset: Double
        let clampedOffset: Double
    }

    let targetFrame: Rect
    /// Intermediate origins in target-to-scroll order, excluding the scroll
    /// container's own origin, just like ViewNode.requestedScrollOffset.
    let ancestorOrigins: [Point]
    let viewportSize: Size
    let contentSize: Size
    let logicalOffset: Double
    let overshoot: Double
    let presentedDelta: Double

    func checkedOffset() -> Offset? {
        guard targetFrame.origin.x.isFinite, targetFrame.origin.y.isFinite,
            targetFrame.width.isFinite, targetFrame.width > 0,
            targetFrame.height.isFinite, targetFrame.height > 0,
            targetFrame.maxX.isFinite, targetFrame.maxY.isFinite,
            viewportSize.width.isFinite, viewportSize.width > 0,
            viewportSize.height.isFinite, viewportSize.height > 0,
            contentSize.width.isFinite, contentSize.width >= 0,
            contentSize.height.isFinite, contentSize.height >= 0,
            logicalOffset.isFinite, overshoot.isFinite, presentedDelta.isFinite
        else { return nil }

        var frame = targetFrame
        for origin in ancestorOrigins {
            guard origin.x.isFinite, origin.y.isFinite else { return nil }
            // Preserve the ordinary helper's addition order. Replacing this
            // walk with a root-space subtraction can change fractional bits.
            let x = frame.origin.x + origin.x
            let y = frame.origin.y + origin.y
            guard x.isFinite, y.isFinite else { return nil }
            frame = Rect(x: x, y: y, width: frame.width, height: frame.height)
            guard frame.maxX.isFinite, frame.maxY.isFinite else { return nil }
        }

        let range = contentSize.height - viewportSize.height
        guard range.isFinite else { return nil }
        let maximumOffset = max(0, range)
        let clampedLogicalOffset = min(max(logicalOffset, 0), maximumOffset)

        // effectiveScrollOffset composes these left to right. Validate each
        // stage instead of allowing its nonfinite fallback to hide bad input.
        let overshootOffset = clampedLogicalOffset + overshoot
        guard overshootOffset.isFinite else { return nil }
        let visibleOffset = overshootOffset + presentedDelta
        guard visibleOffset.isFinite else { return nil }

        let targetEnd = frame.minY + frame.height
        let visibleEnd = visibleOffset + viewportSize.height
        guard targetEnd.isFinite, visibleEnd.isFinite else { return nil }

        let requestedOffset: Double
        if frame.minY < visibleOffset {
            requestedOffset = frame.minY
        } else if targetEnd > visibleEnd {
            // Keep (start + extent) - viewport; regrouping the subtraction
            // changes rounding for large, still-finite coordinates.
            requestedOffset = targetEnd - viewportSize.height
        } else {
            requestedOffset = visibleOffset
        }
        guard requestedOffset.isFinite else { return nil }

        let clampedOffset = min(max(requestedOffset, 0), maximumOffset)
        guard clampedOffset.isFinite else { return nil }
        return Offset(requestedOffset: requestedOffset, clampedOffset: clampedOffset)
    }
}
