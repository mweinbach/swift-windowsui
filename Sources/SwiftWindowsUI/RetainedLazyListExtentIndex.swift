/// A measurement cache tag, not authority to build, adopt, or invoke a row.
/// Equality only checks the supplied dimensions and revisions; callers still
/// establish whether those values describe the current retained environment.
package struct RetainedLazyListMeasurementContext: Hashable, Sendable {
    package let width: Double
    package let displayScale: Double
    package let contentRevision: UInt64
    package let environmentRevision: UInt64

    package init?(width: Double, displayScale: Double, contentRevision: UInt64, environmentRevision: UInt64) {
        guard width.isFinite, width >= 0, displayScale.isFinite, displayScale > 0 else { return nil }
        self.width = width
        self.displayScale = displayScale
        self.contentRevision = contentRevision
        self.environmentRevision = environmentRevision
    }
}

/// One model record's scalar extent. A record may eventually produce zero or
/// multiple leaves; a positive estimate never claims a known leaf count.
package struct RetainedLazyListExtent: Equatable, Sendable {
    package let totalExtent: Double
    package let measuredLeafCount: Int?

    private init(totalExtent: Double, measuredLeafCount: Int?) {
        self.totalExtent = totalExtent
        self.measuredLeafCount = measuredLeafCount
    }

    package static func estimated(_ extent: Double) -> Self? {
        guard extent.isFinite, extent > 0 else { return nil }
        return Self(totalExtent: extent, measuredLeafCount: nil)
    }

    /// The caller includes the leaf contributions appropriate to its layout.
    /// No leaf objects or arrays are retained, and an empty result stays empty.
    package static func measured(_ leafExtents: [Double]) -> Self? {
        var total: Double = 0
        for extent in leafExtents {
            guard extent.isFinite, extent >= 0 else { return nil }
            total += extent
            guard total.isFinite else { return nil }
        }
        return Self(totalExtent: total, measuredLeafCount: leafExtents.count)
    }
}

/// A logical position only. Applying authored scroll anchors, animation,
/// focus, and interaction policy belongs to a later retained integration.
package struct RetainedLazyListAnchor: Equatable, Sendable {
    package let token: RetainedLazyListRowToken
    package let offsetWithinRecord: Double

    fileprivate init(token: RetainedLazyListRowToken, offsetWithinRecord: Double) {
        self.token = token
        self.offsetWithinRecord = offsetWithinRecord
    }
}

/// Pure extent metadata, independent of ViewNode, row factories, or state.
/// Construction and storage are O(records); a point update, prefix, window,
/// or anchor query follows a bounded number of segment-tree paths, O(log N).
/// Updating a shared value also incurs normal Array copy-on-write, O(records).
/// Reordering creates a new index with the surviving logical tokens.
package struct RetainedLazyListExtentIndex: Sendable {
    package let context: RetainedLazyListMeasurementContext

    private let tokens: [RetainedLazyListRowToken]
    private let indicesByToken: [RetainedLazyListRowToken: Int]
    private let leafBase: Int
    private var extents: [RetainedLazyListExtent]
    private var sums: [Double]

    package var count: Int { tokens.count }
    package var totalExtent: Double { sums[1] }

    package init?(
        tokens: [RetainedLazyListRowToken],
        extents: [RetainedLazyListExtent],
        context: RetainedLazyListMeasurementContext
    ) {
        guard tokens.count == extents.count else { return nil }
        var indicesByToken: [RetainedLazyListRowToken: Int] = [:]
        indicesByToken.reserveCapacity(tokens.count)
        for (index, token) in tokens.enumerated() {
            guard indicesByToken.updateValue(index, forKey: token) == nil else { return nil }
        }

        var leafBase = 1
        while leafBase < tokens.count {
            guard leafBase <= Int.max / 2 else { return nil }
            leafBase *= 2
        }
        guard leafBase <= Int.max / 2 else { return nil }
        var sums = [Double](repeating: 0, count: leafBase * 2)
        for (index, extent) in extents.enumerated() {
            sums[leafBase + index] = extent.totalExtent
        }
        if leafBase > 1 {
            for node in stride(from: leafBase - 1, through: 1, by: -1) {
                let sum = sums[node * 2] + sums[node * 2 + 1]
                guard sum.isFinite else { return nil }
                sums[node] = sum
            }
        }

        self.tokens = tokens
        self.extents = extents
        self.context = context
        self.indicesByToken = indicesByToken
        self.leafBase = leafBase
        self.sums = sums
    }

    package func extent(for token: RetainedLazyListRowToken) -> RetainedLazyListExtent? {
        guard let index = indicesByToken[token] else { return nil }
        return extents[index]
    }

    /// Refuses a different cache context or an overflowing sum without
    /// changing either the stored extent or any ancestor in the tree.
    @discardableResult
    package mutating func updateExtent(
        for token: RetainedLazyListRowToken,
        to extent: RetainedLazyListExtent,
        context: RetainedLazyListMeasurementContext
    ) -> Bool {
        guard context == self.context, let index = indicesByToken[token] else { return false }
        var node = leafBase + index
        var value = extent.totalExtent
        var replacements: [(node: Int, value: Double)] = [(node, value)]
        while node > 1 {
            value = node.isMultiple(of: 2) ? value + sums[node + 1] : sums[node - 1] + value
            guard value.isFinite else { return false }
            node /= 2
            replacements.append((node, value))
        }
        for replacement in replacements { sums[replacement.node] = replacement.value }
        extents[index] = extent
        return true
    }

    /// Includes the terminal prefix at count. Invalid indices return nil.
    package func prefixOffset(before index: Int) -> Double? {
        guard index >= 0, index <= count else { return nil }
        if index == count { return totalExtent }
        return bounds(at: index).start
    }

    /// Returns the smallest contiguous range covering nonempty coordinate
    /// intervals intersecting [offset - prefetch, offset + viewport + prefetch). Known
    /// zero-extent records between its endpoints remain metadata in the range;
    /// leading and trailing zero records are excluded. Negative offsets allow
    /// overshoot. Nonfinite inputs or expanded endpoints are rejected.
    package func window(offset: Double, viewportExtent: Double, prefetchExtent: Double = 0) -> Range<Int>? {
        guard offset.isFinite, viewportExtent.isFinite, viewportExtent >= 0,
            prefetchExtent.isFinite, prefetchExtent >= 0
        else { return nil }
        let lower = offset - prefetchExtent
        let upper = offset + viewportExtent + prefetchExtent
        guard lower.isFinite, upper.isFinite else { return nil }
        guard totalExtent > 0 else { return 0..<0 }
        if upper <= 0 { return 0..<0 }
        if lower >= totalExtent { return count..<count }
        let start = max(0, lower)
        let end = min(totalExtent, upper)
        let first = firstRecordEnding(after: start)
        guard start < end else { return first..<first }
        return first..<endIndex(through: end)
    }

    /// Interior boundaries choose the following positive record. Content end
    /// chooses the last positive record; all-zero and empty content has none.
    package func captureAnchor(at offset: Double) -> RetainedLazyListAnchor? {
        guard offset.isFinite, totalExtent > 0 else { return nil }
        let position = min(max(offset, 0), totalExtent)
        if position == totalExtent {
            let index = lastRecordWithPositiveExtent()
            return RetainedLazyListAnchor(token: tokens[index], offsetWithinRecord: extents[index].totalExtent)
        }
        let index = firstRecordEnding(after: position)
        guard index >= 0, index < count else { return nil }
        let interval = bounds(at: index)
        return RetainedLazyListAnchor(
            token: tokens[index],
            offsetWithinRecord: min(max(0, position - interval.start), extents[index].totalExtent))
    }

    /// A surviving record keeps its within-record offset, clamped if its
    /// extent shrank, before the viewport clamp is applied. An existing token
    /// with zero extent resolves to its prefix. A missing token has no fallback.
    package func resolveAnchor(_ anchor: RetainedLazyListAnchor, viewportExtent: Double) -> Double? {
        guard viewportExtent.isFinite, viewportExtent >= 0,
            anchor.offsetWithinRecord.isFinite, anchor.offsetWithinRecord >= 0,
            let index = indicesByToken[anchor.token]
        else { return nil }
        let interval = bounds(at: index)
        let within = min(anchor.offsetWithinRecord, extents[index].totalExtent)
        let position = min(interval.end, interval.start + within)
        return min(max(0, position), max(0, totalExtent - viewportExtent))
    }

    /// Each node partitions its parent's finite coordinate interval. Clamping
    /// a rounded boundary keeps prefixes monotonic at extreme Double scales;
    /// zero-sum branches always occupy zero space rather than rounding slack.
    /// A positive extent below coordinate precision can also have an empty
    /// interval; its logical token, scalar extent, and leaf count are retained.
    private func split(at node: Int, start: Double, end: Double) -> Double {
        let left = sums[node * 2]
        let right = sums[node * 2 + 1]
        if left == 0 { return start }
        if right == 0 { return end }
        return min(end, start + left)
    }

    private func bounds(at index: Int) -> (start: Double, end: Double) {
        var node = 1
        var lower = 0
        var upper = leafBase
        var start: Double = 0
        var end = totalExtent
        while upper - lower > 1 {
            let middle = lower + (upper - lower) / 2
            let boundary = split(at: node, start: start, end: end)
            if index < middle {
                node *= 2
                upper = middle
                end = boundary
            } else {
                node = node * 2 + 1
                lower = middle
                start = boundary
            }
        }
        return (start, end)
    }

    private func firstRecordEnding(after position: Double) -> Int {
        guard position < totalExtent else { return count }
        var node = 1
        var lower = 0
        var upper = leafBase
        var start: Double = 0
        var end = totalExtent
        while upper - lower > 1 {
            let middle = lower + (upper - lower) / 2
            let boundary = split(at: node, start: start, end: end)
            if position < boundary {
                node *= 2
                upper = middle
                end = boundary
            } else {
                node = node * 2 + 1
                lower = middle
                start = boundary
            }
        }
        return min(lower, count)
    }

    private func endIndex(through position: Double) -> Int {
        guard position > 0 else { return 0 }
        var node = 1
        var lower = 0
        var upper = leafBase
        var start: Double = 0
        var end = totalExtent
        while upper - lower > 1 {
            let middle = lower + (upper - lower) / 2
            let boundary = split(at: node, start: start, end: end)
            if position <= boundary {
                node *= 2
                upper = middle
                end = boundary
            } else {
                node = node * 2 + 1
                lower = middle
                start = boundary
            }
        }
        return min(lower + 1, count)
    }

    /// At content end, logical identity must survive a positive extent whose
    /// coordinate span rounded to zero. The caller has established total > 0.
    private func lastRecordWithPositiveExtent() -> Int {
        var node = 1
        while node < leafBase {
            let right = node * 2 + 1
            node = sums[right] > 0 ? right : node * 2
        }
        return node - leafBase
    }
}
