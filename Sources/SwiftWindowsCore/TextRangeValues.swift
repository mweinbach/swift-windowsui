import Foundation

/// Numeric endpoints only. This type supplies no document identity or lifetime.
package enum TextRangeEndpoint: Sendable {
    case start
    case end
}

package enum TextRangeValueError: Error, Equatable, Sendable {
    case incompatibleLength
    case invalidMaximumLength
    case emptySearchText
}

/// An ordered range of Swift Character offsets in a declared length.
/// Equal lengths and equal spans do not establish that two documents are peers.
package struct TextRangeSpan: Equatable, Sendable {
    package let start: Int
    package let end: Int
    package let characterCount: Int

    package init?(start: Int, end: Int, characterCount: Int) {
        guard characterCount >= 0, start >= 0, start <= end, end <= characterCount else { return nil }
        self.start = start
        self.end = end
        self.characterCount = characterCount
    }

    /// Clamps a possibly reversed selection without subtracting its endpoints.
    package init?(clampingAnchor anchor: Int, extent: Int, characterCount: Int) {
        guard characterCount >= 0 else { return nil }
        let anchor = min(max(0, anchor), characterCount)
        let extent = min(max(0, extent), characterCount)
        self.init(start: min(anchor, extent), end: max(anchor, extent), characterCount: characterCount)
    }

    package var characterRange: Range<Int> { start..<end }
    package var isEmpty: Bool { start == end }

    /// A crossing endpoint collapses its peer; it does not reverse the range.
    package func replacingEndpoint(_ endpoint: TextRangeEndpoint, with offset: Int) -> Self? {
        guard offset >= 0, offset <= characterCount else { return nil }
        switch endpoint {
        case .start:
            return Self(start: offset, end: max(offset, end), characterCount: characterCount)
        case .end:
            return Self(start: min(start, offset), end: offset, characterCount: characterCount)
        }
    }

    /// The difference is representable because both offsets are nonnegative.
    /// The length check is not a document-identity check.
    package func compareEndpoint(
        _ endpoint: TextRangeEndpoint, to other: Self, endpoint otherEndpoint: TextRangeEndpoint
    ) -> Int? {
        guard characterCount == other.characterCount else { return nil }
        return offset(of: endpoint) - other.offset(of: otherEndpoint)
    }

    fileprivate func offset(of endpoint: TextRangeEndpoint) -> Int {
        switch endpoint {
        case .start: start
        case .end: end
        }
    }
}

/// Immutable source text and exact Character/UTF16 boundary conversion.
/// This owns only values, not bindings, editor geometry, or provider authority.
package struct TextRangeSnapshot: Sendable {
    package let text: String
    package let documentRange: TextRangeSpan
    private let characterIndices: [String.Index]
    private let utf16Offsets: [Int]

    package init?(_ text: String) {
        var indices = [text.startIndex]
        var offsets = [0]
        var cursor = text.startIndex
        var utf16Offset = 0
        while cursor < text.endIndex {
            let next = text.index(after: cursor)
            let addition = utf16Offset.addingReportingOverflow(text[cursor..<next].utf16.count)
            guard !addition.overflow else { return nil }
            utf16Offset = addition.partialValue
            indices.append(next)
            offsets.append(utf16Offset)
            cursor = next
        }
        let count = indices.count - 1
        guard let documentRange = TextRangeSpan(start: 0, end: count, characterCount: count) else { return nil }
        self.text = text
        self.documentRange = documentRange
        characterIndices = indices
        utf16Offsets = offsets
    }

    package var characterCount: Int { documentRange.characterCount }
    package var utf16Count: Int { utf16Offsets[utf16Offsets.count - 1] }

    package func utf16Offset(atCharacterOffset offset: Int) -> Int? {
        guard offset >= 0, offset <= characterCount else { return nil }
        return utf16Offsets[offset]
    }

    /// UTF16 positions inside a surrogate pair, CRLF, or grapheme are rejected.
    package func characterOffset(atUTF16Offset offset: Int) -> Int? {
        guard offset >= 0, offset <= utf16Count else { return nil }
        let index = textRangeLowerBound(utf16Offsets, offset)
        guard index < utf16Offsets.count, utf16Offsets[index] == offset else { return nil }
        return index
    }

    package func range(utf16Start: Int, utf16End: Int) -> TextRangeSpan? {
        guard utf16Start <= utf16End,
            let start = characterOffset(atUTF16Offset: utf16Start),
            let end = characterOffset(atUTF16Offset: utf16End)
        else { return nil }
        return TextRangeSpan(start: start, end: end, characterCount: characterCount)
    }

    package func utf16Range(for range: TextRangeSpan) -> Range<Int>? {
        guard range.characterCount == characterCount else { return nil }
        return utf16Offsets[range.start]..<utf16Offsets[range.end]
    }

    /// Local retrieval policy: -1 is unlimited; nonnegative limits count UTF16
    /// units but never split a Character. The result may underfill its budget.
    /// Source control characters and normalization are preserved unchanged.
    package func getText(
        in range: TextRangeSpan, maximumUTF16Length: Int = -1
    ) throws -> String {
        guard range.characterCount == characterCount else { throw TextRangeValueError.incompatibleLength }
        guard maximumUTF16Length >= -1 else { throw TextRangeValueError.invalidMaximumLength }
        var end = range.end
        let startUTF16 = utf16Offsets[range.start]
        let available = utf16Offsets[end] - startUTF16
        if maximumUTF16Length >= 0, maximumUTF16Length < available {
            // The limit is smaller than the remaining length, so this sum
            // cannot exceed the already-representable end UTF16 offset.
            let limit = startUTF16 + maximumUTF16Length
            let index = textRangeLowerBound(utf16Offsets, limit)
            end = utf16Offsets[index] == limit ? index : index - 1
        }
        return String(text[characterIndices[range.start]..<characterIndices[end]])
    }

    /// Literal Foundation matching, with optional case folding under a fixed
    /// en_US_POSIX locale. This is not a claim of Windows ordinal-search parity.
    /// Only complete Character matches are representable; partial matches are
    /// skipped, never enlarged. Empty needles are an explicit local error.
    /// Backward search returns the last eligible forward match by logical start.
    package func findText(
        _ needle: String, in range: TextRangeSpan, backward: Bool = false, ignoreCase: Bool = false
    ) throws -> TextRangeSpan? {
        guard range.characterCount == characterCount else { throw TextRangeValueError.incompatibleLength }
        guard !needle.isEmpty else { throw TextRangeValueError.emptySearchText }
        var options: String.CompareOptions = [.literal]
        if ignoreCase { options.insert(.caseInsensitive) }
        let locale = Locale(identifier: "en_US_POSIX")
        var start = range.start
        var lastMatch: TextRangeSpan?
        while start < range.end {
            let searchRange = characterIndices[start]..<characterIndices[range.end]
            guard let match = text.range(of: needle, options: options, range: searchRange, locale: locale) else {
                return lastMatch
            }
            let first = match.lowerBound.utf16Offset(in: text)
            let last = match.upperBound.utf16Offset(in: text)
            if first < last, let matchStart = characterOffset(atUTF16Offset: first),
                let matchEnd = characterOffset(atUTF16Offset: last)
            {
                let candidate = TextRangeSpan(start: matchStart, end: matchEnd, characterCount: characterCount)
                if !backward { return candidate }
                lastMatch = candidate
            }
            // Advance by starts, not ends, to retain overlapping occurrences.
            // Keeping the original end also avoids assuming equal-width case folds.
            var next = textRangeLowerBound(utf16Offsets, first)
            if next < utf16Offsets.count, utf16Offsets[next] == first { next += 1 }
            guard next > start, next <= range.end else { return lastMatch }
            start = next
        }
        return lastMatch
    }
}

package struct TextRangeMovement: Equatable, Sendable {
    package let span: TextRangeSpan
    package let unitsMoved: Int
}

/// A copied table of legal unit boundaries expressed in Character offsets.
/// The caller supplies linguistic/rendered boundaries and semantic fallback.
/// In particular, this does not equate Swift Character with UIA TextUnit_Character.
package struct TextRangeUnitBoundaries: Sendable {
    package let characterCount: Int
    private let offsets: [Int]

    package init?(characterCount: Int, offsets: [Int]) {
        guard characterCount >= 0, offsets.first == 0, offsets.last == characterCount else { return nil }
        var previous = -1
        for offset in offsets {
            guard offset > previous, offset <= characterCount else { return nil }
            previous = offset
        }
        self.characterCount = characterCount
        self.offsets = offsets
    }

    /// Normalizes to one supplied interval. The local EOF policy chooses the
    /// final existing interval; an empty document remains an empty range.
    package func expanded(_ range: TextRangeSpan) -> TextRangeSpan? {
        guard range.characterCount == characterCount else { return nil }
        guard characterCount > 0 else { return range }
        let interval = min(indexAtOrBefore(range.start), offsets.count - 2)
        return TextRangeSpan(
            start: offsets[interval], end: offsets[interval + 1], characterCount: characterCount)
    }

    /// Nonempty ranges normalize only after an actual interval translation.
    /// Zero count and zero achievable movement preserve the original range.
    package func moving(_ range: TextRangeSpan, by count: Int) -> TextRangeMovement? {
        guard range.characterCount == characterCount else { return nil }
        guard count != 0, characterCount > 0 else { return TextRangeMovement(span: range, unitsMoved: 0) }
        if range.isEmpty {
            let movement = movingOffset(range.start, by: count)
            guard
                let result = TextRangeSpan(
                    start: movement.offset, end: movement.offset, characterCount: characterCount)
            else { return nil }
            return TextRangeMovement(span: result, unitsMoved: movement.units)
        }
        let interval = indexAtOrBefore(range.start)
        let delta = clampedMovement(count, from: interval, through: offsets.count - 2)
        guard delta != 0 else { return TextRangeMovement(span: range, unitsMoved: 0) }
        let next = interval + delta
        guard
            let result = TextRangeSpan(
                start: offsets[next], end: offsets[next + 1], characterCount: characterCount)
        else { return nil }
        return TextRangeMovement(span: result, unitsMoved: delta)
    }

    package func movingEndpoint(
        _ endpoint: TextRangeEndpoint, in range: TextRangeSpan, by count: Int
    ) -> TextRangeMovement? {
        guard range.characterCount == characterCount else { return nil }
        let movement = movingOffset(range.offset(of: endpoint), by: count)
        guard let result = range.replacingEndpoint(endpoint, with: movement.offset) else { return nil }
        return TextRangeMovement(span: result, unitsMoved: movement.units)
    }

    private func indexAtOrBefore(_ offset: Int) -> Int {
        let index = textRangeLowerBound(offsets, offset)
        return offsets[index] == offset ? index : index - 1
    }

    private func movingOffset(_ offset: Int, by count: Int) -> (offset: Int, units: Int) {
        guard count != 0 else { return (offset, 0) }
        // From inside an interval, the first crossed boundary counts once.
        let origin = count > 0 ? indexAtOrBefore(offset) : textRangeLowerBound(offsets, offset)
        let delta = clampedMovement(count, from: origin, through: offsets.count - 1)
        guard delta != 0 else { return (offset, 0) }
        return (offsets[origin + delta], delta)
    }

    private func clampedMovement(_ count: Int, from index: Int, through lastIndex: Int) -> Int {
        // Compare before adding; never negate an arbitrary signed count.
        count > 0 ? min(count, lastIndex - index) : max(count, 0 - index)
    }
}

private func textRangeLowerBound(_ offsets: [Int], _ value: Int) -> Int {
    var lower = 0
    var upper = offsets.count
    while lower < upper {
        let middle = lower + (upper - lower) / 2
        if offsets[middle] < value {
            lower = middle + 1
        } else {
            upper = middle
        }
    }
    return lower
}
