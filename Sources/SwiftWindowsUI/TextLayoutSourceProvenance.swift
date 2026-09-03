/// Exact submitted layout text. This value supplies neither navigation units
/// nor ownership, and never reads a node, binding, or editor controller.
struct TextLayoutSourceText: Hashable, Sendable {
    let text: String
    let utf16Length: Int
    fileprivate let units: [UInt16]

    init(_ text: String) {
        let units = Array(text.utf16)
        self.text = text
        self.utf16Length = units.count
        self.units = units
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.units == rhs.units
    }

    func hash(into hasher: inout Hasher) {
        // Canonically equivalent strings may collide, but exact equality
        // still distinguishes their original UTF16 representations.
        hasher.combine(text)
    }
}

struct TextLayoutSourceSegment: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case copied
        case replaced
        case generated
    }

    let kind: Kind
    let outputUTF16Range: Range<Int>
    let sourceUTF16Range: Range<Int>?
}

struct TextLayoutLineSource: Equatable, Sendable {
    let outputUTF16Length: Int
    let segments: [TextLayoutSourceSegment]
    /// A unique raw source coordinate for empty output, not a caret stop.
    let emptySourceUTF16Anchor: Int?
}

struct TextLayoutSourceProjection: Equatable, Sendable {
    let source: TextLayoutSourceText
    /// Source units absent from final display mappings, not a visibility test.
    let unrepresentedSourceUTF16Ranges: [Range<Int>]
}

enum TextLayoutSourceProvenance {
    static func sourceFragment(for text: String) -> TextLayoutFragment {
        TextLayoutFragment(source: text)
    }

    static func projectLine(
        source: TextLayoutSourceText, outputText: String,
        mappings: [TextLayoutFragment.Mapping], emptySourceUTF16Anchor: Int? = nil
    ) -> TextLayoutLineSource? {
        let output = Array(outputText.utf16)
        if let anchor = emptySourceUTF16Anchor {
            guard output.isEmpty, anchor >= 0, anchor <= source.utf16Length else { return nil }
        }
        guard !output.isEmpty else {
            guard mappings.isEmpty else { return nil }
            return TextLayoutLineSource(
                outputUTF16Length: 0, segments: [], emptySourceUTF16Anchor: emptySourceUTF16Anchor)
        }

        var previousOutput = 0
        var previousSource = 0
        for mapping in mappings {
            let rendered = mapping.outputUTF16Range
            let original = mapping.sourceUTF16Range
            // Establish bounded nonnegative endpoints before subtracting.
            guard rendered.lowerBound >= previousOutput, rendered.lowerBound >= 0,
                rendered.upperBound > rendered.lowerBound, rendered.upperBound <= output.count,
                original.lowerBound >= previousSource, original.lowerBound >= 0,
                original.upperBound > original.lowerBound, original.upperBound <= source.utf16Length,
                rendered.upperBound - rendered.lowerBound == original.upperBound - original.lowerBound
            else { return nil }
            previousOutput = rendered.upperBound
            previousSource = original.upperBound
        }

        var segments: [TextLayoutSourceSegment] = []
        var outputCursor = 0
        for mapping in mappings {
            let rendered = mapping.outputUTF16Range
            let original = mapping.sourceUTF16Range
            if outputCursor < rendered.lowerBound {
                segments.append(
                    TextLayoutSourceSegment(
                        kind: .generated, outputUTF16Range: outputCursor..<rendered.lowerBound,
                        sourceUTF16Range: nil))
            }
            var runStart = rendered.lowerBound
            while runStart < rendered.upperBound {
                let sourceStart = original.lowerBound + (runStart - rendered.lowerBound)
                let isCopied = output[runStart] == source.units[sourceStart]
                var runEnd = runStart + 1
                while runEnd < rendered.upperBound {
                    let sourceOffset = original.lowerBound + (runEnd - rendered.lowerBound)
                    guard (output[runEnd] == source.units[sourceOffset]) == isCopied else { break }
                    runEnd += 1
                }
                let sourceEnd = sourceStart + (runEnd - runStart)
                segments.append(
                    TextLayoutSourceSegment(
                        kind: isCopied ? .copied : .replaced, outputUTF16Range: runStart..<runEnd,
                        sourceUTF16Range: sourceStart..<sourceEnd))
                runStart = runEnd
            }
            outputCursor = rendered.upperBound
        }
        if outputCursor < output.count {
            segments.append(
                TextLayoutSourceSegment(
                    kind: .generated, outputUTF16Range: outputCursor..<output.count,
                    sourceUTF16Range: nil))
        }
        return TextLayoutLineSource(
            outputUTF16Length: output.count, segments: segments, emptySourceUTF16Anchor: nil)
    }

    /// Failure removes metadata only. It must not change drawing or trigger a
    /// new native layout/fallback. One shared source buffer bounds the work to
    /// source units plus final output units and segments, not source times lines.
    static func attaching(
        to layout: NativeTextLayoutResult, source: String, fragments: [TextLayoutFragment]
    ) -> NativeTextLayoutResult {
        var result = layout
        result.sourceProvenance = nil
        for index in result.lines.indices {
            result.lines[index].sourceProvenance = nil
        }
        guard result.lines.count == fragments.count else { return result }

        let original = TextLayoutSourceText(source)
        var lineSources: [TextLayoutLineSource] = []
        lineSources.reserveCapacity(fragments.count)
        var unrepresented: [Range<Int>] = []
        var sourceCursor = 0
        // Positions include empty anchors; represented coverage does not.
        var sourcePosition = 0
        for index in fragments.indices {
            let fragment = fragments[index]
            guard result.lines[index].text.utf16.elementsEqual(fragment.text.utf16),
                let lineSource = projectLine(
                    source: original, outputText: fragment.text, mappings: fragment.mappings,
                    emptySourceUTF16Anchor: fragment.emptySourceUTF16Anchor)
            else { return result }
            if let anchor = lineSource.emptySourceUTF16Anchor {
                guard anchor >= sourcePosition else { return result }
                sourcePosition = anchor
            }
            for segment in lineSource.segments {
                guard let represented = segment.sourceUTF16Range else { continue }
                guard represented.lowerBound >= sourceCursor, represented.lowerBound >= sourcePosition else {
                    return result
                }
                if sourceCursor < represented.lowerBound {
                    unrepresented.append(sourceCursor..<represented.lowerBound)
                }
                sourceCursor = represented.upperBound
                sourcePosition = represented.upperBound
            }
            lineSources.append(lineSource)
        }
        if sourceCursor < original.utf16Length {
            unrepresented.append(sourceCursor..<original.utf16Length)
        }
        // Publish only the complete projection. An invalid later line cannot
        // make earlier metadata look complete or turn unknown coverage into gaps.
        for index in result.lines.indices {
            result.lines[index].sourceProvenance = lineSources[index]
        }
        result.sourceProvenance = TextLayoutSourceProjection(
            source: original, unrepresentedSourceUTF16Ranges: unrepresented)
        return result
    }
}
