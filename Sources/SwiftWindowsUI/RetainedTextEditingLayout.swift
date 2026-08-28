import Foundation
import SwiftWindowsCore

package struct RetainedTextCaretPosition: Equatable, Hashable, Sendable {
    package var characterOffset: Int
    package var affinity: RetainedTextSelectionAffinity

    package init(characterOffset: Int, affinity: RetainedTextSelectionAffinity = .downstream) {
        self.characterOffset = characterOffset
        self.affinity = affinity
    }
}

package struct RetainedTextCaretGeometry: Equatable, Sendable {
    package var position: RetainedTextCaretPosition
    package var rect: Rect
    package var lineIndex: Int

    package init(position: RetainedTextCaretPosition, rect: Rect, lineIndex: Int) {
        self.position = position
        self.rect = rect
        self.lineIndex = lineIndex
    }
}

package struct RetainedTextVisualLine: Equatable, Sendable {
    package var text: String
    package var sourceRange: Range<Int>
    package var hardBreakRange: Range<Int>?
    package var rect: Rect
    package var carets: [RetainedTextCaretGeometry]
}

/// One immutable source/geometry snapshot for editor painting, navigation,
/// pointer hit testing, and IME placement. Offsets count Swift Characters;
/// rectangles are in the text content's logical coordinate system.
package struct RetainedTextEditingLayout: Equatable, Sendable {
    package let contentSize: Size
    package let lines: [RetainedTextVisualLine]
    package let characterCount: Int
    /// Native text can remain fully drawable when exact caret extraction is
    /// unavailable. Never put a pixel-font approximation over native glyphs.
    package let hasCompleteCaretGeometry: Bool
    private let regionsByLine: [[NativeTextEditingRegion]]

    package func caret(at position: RetainedTextCaretPosition) -> RetainedTextCaretGeometry? {
        guard hasCompleteCaretGeometry else { return nil }
        let offset = min(max(0, position.characterOffset), characterCount)
        let affinity: RetainedTextSelectionAffinity = position.affinity == .upstream ? .upstream : .downstream
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lines[middle].sourceRange.upperBound < offset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        var candidates: [RetainedTextCaretGeometry] = []
        var index = lower
        while index < lines.count, lines[index].sourceRange.lowerBound <= offset {
            candidates.append(contentsOf: lines[index].carets)
            index += 1
        }
        let exact = candidates.filter { $0.position.characterOffset == offset }
        let matchingAffinity = exact.filter { $0.position.affinity == affinity }
        if !matchingAffinity.isEmpty {
            return affinity == .upstream ? matchingAffinity.first : matchingAffinity.last
        }
        if !exact.isEmpty {
            return affinity == .upstream ? exact.first : exact.last
        }
        // A shaped cluster can omit interior grapheme stops. Resolve to a
        // native stop on the requested logical side, never to an invented X.
        let onRequestedSide = candidates.filter {
            affinity == .upstream
                ? $0.position.characterOffset < offset : $0.position.characterOffset > offset
        }
        return (onRequestedSide.isEmpty ? candidates : onRequestedSide).min {
            abs($0.position.characterOffset - offset) < abs($1.position.characterOffset - offset)
        }
    }

    package func caret(onLine index: Int, nearestX: Double) -> RetainedTextCaretGeometry? {
        guard hasCompleteCaretGeometry, lines.indices.contains(index), nearestX.isFinite,
            let first = lines[index].carets.first
        else { return nil }
        let carets = lines[index].carets
        let minimumX = carets.reduce(first.rect.minX) { min($0, $1.rect.minX) }
        let maximumX = carets.reduce(first.rect.minX) { max($0, $1.rect.minX) }
        let x = min(max(nearestX, minimumX), maximumX)
        // At a bidi boundary two different logical caret positions can share
        // the same X. First identify the native character cell under the
        // point; otherwise a nearby LTR run can steal a hit inside an RTL run.
        var ownedCarets: [RetainedTextCaretGeometry] = []
        for region in regionsByLine[index]
        where region.characterRange.overlaps(lines[index].sourceRange)
            && region.rect.width > 0 && region.rect.minX <= x
            && (x < region.rect.maxX || (x == maximumX && x == region.rect.maxX))
        {
            let leading = carets.filter {
                $0.position.characterOffset <= region.characterRange.lowerBound
                    && $0.position.affinity == .downstream
            }.max { $0.position.characterOffset < $1.position.characterOffset }
            let trailing = carets.filter {
                $0.position.characterOffset >= region.characterRange.upperBound
                    && $0.position.affinity == .upstream
            }.min { $0.position.characterOffset < $1.position.characterOffset }
            if let leading { ownedCarets.append(leading) }
            if let trailing { ownedCarets.append(trailing) }
        }
        let candidates = ownedCarets.isEmpty ? carets : ownedCarets
        var best = candidates[0]
        var bestDistance = abs(best.rect.minX - x)
        for candidate in candidates.dropFirst() {
            let distance = abs(candidate.rect.minX - x)
            if distance < bestDistance
                || (distance == bestDistance && best.position.affinity != .downstream
                    && candidate.position.affinity == .downstream)
            {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }

    package func hitTest(_ point: Point) -> RetainedTextCaretGeometry? {
        guard hasCompleteCaretGeometry, point.x.isFinite, point.y.isFinite, !lines.isEmpty else { return nil }
        var bestLine = 0
        var bestDistance = Double.infinity
        for (index, line) in lines.enumerated() {
            let distance = max(max(line.rect.minY - point.y, point.y - line.rect.maxY), 0)
            if distance < bestDistance {
                bestLine = index
                bestDistance = distance
            }
        }
        return caret(onLine: bestLine, nearestX: point.x)
    }

    /// Native range pieces are retained separately, so a logical selection
    /// crossing bidi runs does not incorrectly fill the unselected gap.
    package func selectionRects(for range: Range<Int>) -> [Rect] {
        guard hasCompleteCaretGeometry else { return [] }
        let lower = min(max(0, range.lowerBound), characterCount)
        let upper = min(max(lower, range.upperBound), characterCount)
        guard lower < upper else { return [] }
        let pieces = regionsByLine.joined().filter {
            $0.characterRange.lowerBound < upper && $0.characterRange.upperBound > lower
                && $0.rect.width > 0 && $0.rect.height > 0
        }.map(\.rect).sorted {
            if $0.minY != $1.minY { return $0.minY < $1.minY }
            if $0.height != $1.height { return $0.height < $1.height }
            return $0.minX < $1.minX
        }
        var result: [Rect] = []
        for piece in pieces {
            if let previous = result.last,
                previous.minY == piece.minY, previous.height == piece.height,
                piece.minX <= previous.maxX
            {
                result[result.count - 1] = Rect(
                    x: previous.minX, y: previous.minY,
                    width: max(previous.maxX, piece.maxX) - previous.minX, height: previous.height)
            } else {
                result.append(piece)
            }
        }
        return result
    }

    fileprivate init(
        contentSize: Size, lines: [RetainedTextVisualLine], characterCount: Int,
        hasCompleteCaretGeometry: Bool, regionsByLine: [[NativeTextEditingRegion]]
    ) {
        self.contentSize = contentSize
        self.lines = lines
        self.characterCount = characterCount
        self.hasCompleteCaretGeometry = hasCompleteCaretGeometry
        self.regionsByLine = regionsByLine
    }
}

extension RetainedTextMetrics {
    /// Preserves the document exactly. Generic label wrapping deliberately
    /// normalizes whitespace; editable fragments must not use that policy.
    package static func editingLayout(
        of text: String, style: PixelTextStyle, contentWidth: Double, displayScale: Double
    ) -> RetainedTextEditingLayout? {
        guard contentWidth.isFinite, contentWidth > 0,
            displayScale.isFinite, displayScale > 0,
            style.scale.isFinite, style.nativeFontPixelSize.isFinite, style.nativeFontPixelSize > 0,
            style.letterSpacing.isFinite, style.nativeLetterSpacing?.isFinite != false, style.lineSpacing.isFinite
        else { return nil }

        var lineStyle = style
        lineStyle.insets = .zero
        lineStyle.alignment = .leading
        lineStyle.verticalAlignment = .top
        lineStyle.lineBreakMode = .clip
        lineStyle.maximumNumberOfLines = 1
        lineStyle.minimumNumberOfLines = nil
        lineStyle.minimumScaleFactor = 1
        lineStyle.reservesLineLimitSpace = false

        let characters = Array(text)
        var boundaries = Array(text.indices)
        boundaries.append(text.endIndex)
        guard characters.count < Int.max, boundaries.count == characters.count + 1 else { return nil }
        let source = TextLayoutFragment(source: text)
        var measured: [Range<Int>: Size] = [:]
        func fragment(_ range: Range<Int>) -> TextLayoutFragment {
            source.slice(boundaries[range.lowerBound]..<boundaries[range.upperBound])
        }
        func fragmentStyle(_ fragment: TextLayoutFragment) -> PixelTextStyle {
            fragment.rebasedStyle(lineStyle, sourceText: text)
        }
        func measure(_ range: Range<Int>) -> Size? {
            if let value = measured[range] { return value }
            let part = fragment(range)
            guard
                let value = NativeTextRenderer.editingLineSize(
                    part.text, style: fragmentStyle(part), scaleFactor: displayScale),
                value.width.isFinite, value.width >= 0, value.height.isFinite, value.height > 0
            else { return nil }
            measured[range] = value
            return value
        }

        var fragments: [(range: Range<Int>, hardBreak: Range<Int>?)] = []
        for hardLine in editingHardLines(in: characters) {
            var start = hardLine.range.lowerBound
            if hardLine.range.isEmpty {
                fragments.append(hardLine)
                continue
            }
            while start < hardLine.range.upperBound {
                guard
                    let end = editingFittingEnd(
                        from: start, through: hardLine.range.upperBound, characters: characters,
                        width: contentWidth, measure: measure)
                else { return nil }
                fragments.append((start..<end, end == hardLine.range.upperBound ? hardLine.hardBreak : nil))
                start = end
            }
        }

        var lines: [RetainedTextVisualLine] = []
        var regionsByLine: [[NativeTextEditingRegion]] = []
        var top = 0.0
        var extentWidth = contentWidth
        var extentHeight = 0.0
        var complete = true
        for (lineIndex, item) in fragments.enumerated() {
            let part = fragment(item.range)
            guard
                let metrics = NativeTextRenderer.editingLine(
                    part.text, style: fragmentStyle(part), scaleFactor: displayScale),
                metrics.text == part.text, metrics.width.isFinite, metrics.width >= 0,
                metrics.height.isFinite, metrics.height > 0, metrics.lineSpacing.isFinite,
                metrics.height + metrics.lineSpacing > 0
            else { return nil }
            let x: Double
            switch style.alignment {
            case .leading: x = 0
            case .center: x = max(0, (contentWidth - metrics.width) * 0.5)
            case .trailing: x = contentWidth - metrics.width
            }
            let rect = Rect(x: x, y: top, width: metrics.width, height: metrics.height)
            guard rect.maxX.isFinite, rect.maxY.isFinite else { return nil }
            let count = item.range.count
            let validCarets = metrics.carets.filter {
                $0.characterOffset >= 0 && $0.characterOffset <= count && $0.x.isFinite
            }
            let validRegions = metrics.selectionRegions.filter {
                $0.characterRange.lowerBound >= 0 && $0.characterRange.upperBound <= count
                    && $0.rect.minX.isFinite && $0.rect.minY.isFinite
                    && $0.rect.width.isFinite && $0.rect.height.isFinite
                    && $0.rect.width >= 0 && $0.rect.height >= 0
                    && $0.rect.maxX.isFinite && $0.rect.maxY.isFinite
            }
            complete =
                complete && !validCarets.isEmpty && validCarets.count == metrics.carets.count
                && validRegions.count == metrics.selectionRegions.count
            let beginsAfterSoftWrap =
                lineIndex > 0 && fragments[lineIndex - 1].hardBreak == nil
                && fragments[lineIndex - 1].range.upperBound == item.range.lowerBound
            let endsAtSoftWrap =
                lineIndex + 1 < fragments.count && item.hardBreak == nil
                && fragments[lineIndex + 1].range.lowerBound == item.range.upperBound
            let visibleCarets = validCarets.filter { caret in
                if beginsAfterSoftWrap, caret.characterOffset == 0, caret.affinity == .upstream { return false }
                if endsAtSoftWrap, caret.characterOffset == count, caret.affinity != .upstream { return false }
                return true
            }
            let carets = visibleCarets.compactMap { caret -> RetainedTextCaretGeometry? in
                let caretRect = Rect(x: x + caret.x, y: top, width: 0, height: metrics.height)
                guard caretRect.minX.isFinite, caretRect.maxY.isFinite else { return nil }
                return RetainedTextCaretGeometry(
                    position: RetainedTextCaretPosition(
                        characterOffset: item.range.lowerBound + caret.characterOffset, affinity: caret.affinity),
                    rect: caretRect,
                    lineIndex: lineIndex)
            }
            complete =
                complete && carets.count == visibleCarets.count
                && carets.contains { $0.position.characterOffset == item.range.lowerBound }
                && carets.contains { $0.position.characterOffset == item.range.upperBound }
            lines.append(
                RetainedTextVisualLine(
                    text: part.text, sourceRange: item.range, hardBreakRange: item.hardBreak,
                    rect: rect, carets: carets))
            var regions = validRegions.compactMap { region -> NativeTextEditingRegion? in
                let regionRect = Rect(
                    x: x + region.rect.minX, y: top + region.rect.minY,
                    width: region.rect.width, height: region.rect.height)
                guard regionRect.minX.isFinite, regionRect.minY.isFinite,
                    regionRect.maxX.isFinite, regionRect.maxY.isFinite
                else { return nil }
                let lower = item.range.lowerBound + region.characterRange.lowerBound
                let upper = item.range.lowerBound + region.characterRange.upperBound
                return NativeTextEditingRegion(
                    characterRange: lower..<upper,
                    rect: regionRect)
            }
            complete = complete && regions.count == validRegions.count
            if let hardBreak = item.hardBreak,
                let end = carets.last(where: { $0.position.characterOffset == item.range.upperBound })
            {
                let preceding = carets.last {
                    $0.position.characterOffset < item.range.upperBound && $0.position.affinity == .downstream
                }
                let extendsLeft = preceding.map { end.rect.minX < $0.rect.minX } ?? false
                regions.append(
                    NativeTextEditingRegion(
                        characterRange: hardBreak,
                        rect: Rect(
                            x: end.rect.minX - (extendsLeft ? 4.5 : 0), y: top, width: 4.5, height: metrics.height)))
            }
            regionsByLine.append(regions)
            extentWidth = max(extentWidth, max(metrics.width, rect.maxX))
            extentHeight = max(extentHeight, rect.maxY)
            top = rect.maxY + metrics.lineSpacing
            guard top.isFinite else { return nil }
        }
        return RetainedTextEditingLayout(
            contentSize: Size(width: extentWidth, height: extentHeight), lines: lines, characterCount: characters.count,
            hasCompleteCaretGeometry: complete, regionsByLine: regionsByLine)
    }
}

private func editingHardLines(in characters: [Character]) -> [(range: Range<Int>, hardBreak: Range<Int>?)] {
    var result: [(range: Range<Int>, hardBreak: Range<Int>?)] = []
    var start = 0
    for (offset, character) in characters.enumerated() where character.isNewline {
        result.append((start..<offset, offset..<(offset + 1)))
        start = offset + 1
    }
    result.append((start..<characters.count, nil))
    return result
}

/// Exponential probes then a bounded prefix search avoid measuring the whole
/// remaining paragraph for every short visual line. Every accepted fragment
/// has been measured as a whole; an indivisible oversized grapheme is the only
/// deliberate overflow. Prefer an existing whitespace boundary without
/// dropping that whitespace or synthesizing a replacement separator.
@MainActor
private func editingFittingEnd(
    from start: Int, through limit: Int, characters: [Character], width: Double,
    measure: @MainActor (Range<Int>) -> Size?
) -> Int? {
    let remaining = limit - start
    var fitted = 0
    var probe = 1
    var upper = remaining
    while probe <= remaining {
        guard let size = measure(start..<(start + probe)) else { return nil }
        if size.width <= width {
            fitted = probe
            if fitted == remaining { return limit }
            probe = probe > remaining / 2 ? remaining : probe * 2
        } else {
            upper = probe - 1
            break
        }
    }
    guard fitted > 0 else { return start + 1 }
    var lower = fitted + 1
    while lower <= upper {
        let middle = lower + (upper - lower) / 2
        guard let size = measure(start..<(start + middle)) else { return nil }
        if size.width <= width {
            fitted = middle
            lower = middle + 1
        } else {
            upper = middle - 1
        }
    }
    let end = start + fitted
    if end == limit { return end }
    for index in stride(from: end - 1, through: start, by: -1) where characters[index].isWhitespace {
        // Shaping and negative tracking need not have monotonic prefix
        // widths. A shorter whitespace slice must pass its own whole-line
        // measurement before it can replace the already measured fragment.
        let preferredEnd = index + 1
        guard let size = measure(start..<preferredEnd) else { return nil }
        return size.width <= width ? preferredEnd : end
    }
    return end
}
