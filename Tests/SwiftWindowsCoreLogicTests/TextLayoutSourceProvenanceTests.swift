import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Synthetic value/assembly coverage only. No font, native layout, caret, or UIA qualification.
@MainActor
final class TextLayoutSourceProvenanceTests: XCTestCase {
    func testSourceExtentPreservesExactUTF16AndImmutableInput() async throws {
        let cases: [(String, [UInt16])] = [
            ("", []),
            ("A\u{0}B", [65, 0, 66]),
            ("\r\n", [13, 10]),
            ("e\u{301}", [101, 769]),
            ("\u{1F469}\u{200D}\u{1F4BB}", [0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDCBB]),
        ]
        for (text, expectedUnits) in cases {
            let source = TextLayoutSourceText(text)
            XCTAssertEqual(Array(source.text.utf16), expectedUnits)
            XCTAssertEqual(source.utf16Length, expectedUnits.count)
        }

        var input = "A\u{0}e\u{301}\r\n"
        let source = TextLayoutSourceText(input)
        let originalUnits = Array(input.utf16)
        input.removeAll()
        input.append("changed")
        XCTAssertEqual(Array(source.text.utf16), originalUnits)
        XCTAssertEqual(source.utf16Length, 6)
        XCTAssertEqual(source, TextLayoutSourceText(String(decoding: originalUnits, as: UTF16.self)))
    }

    func testCanonicalEquivalentSourceKeysRemainDistinct() async throws {
        let pairs = [("\u{E9}", "e\u{301}"), ("\u{C5}", "\u{212B}")]
        let style = Self.style()
        for (left, right) in pairs {
            XCTAssertEqual(left, right, "The control uses Swift canonical String equality")
            XCTAssertNotEqual(Array(left.utf16), Array(right.utf16))
            XCTAssertNotEqual(TextLayoutSourceText(left), TextLayoutSourceText(right))
            XCTAssertEqual(Set([TextLayoutSourceText(left), TextLayoutSourceText(right)]).count, 2)

            let leftKey = WindowTextSystem.LayoutKey(text: left, style: style, maxWidth: 20)
            let rightKey = WindowTextSystem.LayoutKey(text: right, style: style, maxWidth: 20)
            XCTAssertNotEqual(leftKey, rightKey)
            XCTAssertEqual(Set([leftKey, rightKey]).count, 2)
        }
        XCTAssertEqual("\u{C5}".utf16.count, "\u{212B}".utf16.count)
    }

    func testEqualUTF16SourceAssignmentsReuseCachedLayout() async throws {
        let savedOverrides = NativeTextRenderer.testingOverrides
        defer { NativeTextRenderer.testingOverrides = savedOverrides }
        var calls: [[UInt16]] = []
        var scales: [Double] = []
        NativeTextRenderer.testingOverrides.layout = { text, _, scale, _ in
            calls.append(Array(text.utf16))
            scales.append(scale)
            return Self.assemble(text, [TextLayoutSourceProvenance.sourceFragment(for: text)])
        }

        let system = WindowTextSystem()
        let text = "\u{C5}"
        let recreated = String(decoding: Array(text.utf16), as: UTF16.self)
        let first = try XCTUnwrap(system.layout(text, style: Self.style(), maxWidth: 20, scaleFactor: 1))
        let second = try XCTUnwrap(system.layout(recreated, style: Self.style(), maxWidth: 20, scaleFactor: 2))
        XCTAssertEqual(calls, [[0xC5]])
        XCTAssertEqual(scales, [1])
        XCTAssertEqual(system.cachedLayoutCount, 1)
        XCTAssertEqual(first.lines, second.lines)
        XCTAssertEqual(first.sourceProvenance, second.sourceProvenance)

        let different = try XCTUnwrap(system.layout("\u{212B}", style: Self.style(), maxWidth: 20, scaleFactor: 1))
        XCTAssertEqual(calls, [[0xC5], [0x212B]])
        XCTAssertEqual(scales, [1, 1])
        XCTAssertEqual(system.cachedLayoutCount, 2)
        XCTAssertEqual(Array(try XCTUnwrap(first.sourceProvenance).source.text.utf16), [0xC5])
        XCTAssertEqual(Array(try XCTUnwrap(different.sourceProvenance).source.text.utf16), [0x212B])
    }

    func testUnstyledFinalLinesRetainOriginalSourceMappings() async throws {
        let text = "Plain label\r\nsecond"
        let style = Self.style()
        XCTAssertNil(style.spans)
        let resolved = Self.resolve(text, style: style)
        XCTAssertEqual(resolved.lines, ["Plain label", "second"])
        XCTAssertEqual(resolved.fragments[0].mappings, [Self.mapping(0..<11, 0..<11)])
        XCTAssertEqual(resolved.fragments[1].mappings, [Self.mapping(0..<6, 13..<19)])

        let original = Self.drawable(resolved.lines)
        XCTAssertTrue(original.lines.allSatisfy { $0.sourceProvenance == nil })
        XCTAssertNil(original.sourceProvenance)
        let attached = TextLayoutSourceProvenance.attaching(to: original, source: text, fragments: resolved.fragments)
        XCTAssertEqual(try XCTUnwrap(attached.lines[0].sourceProvenance).segments, [Self.copied(0..<11, 0..<11)])
        XCTAssertEqual(try XCTUnwrap(attached.lines[1].sourceProvenance).segments, [Self.copied(0..<6, 13..<19)])
        XCTAssertEqual(try XCTUnwrap(attached.sourceProvenance).unrepresentedSourceUTF16Ranges, [11..<13])
        Self.assertDrawableEqual(attached, original)
    }

    func testRepeatedStyledWordsKeepDistinctOriginalOffsets() async throws {
        let text = "ECHO ECHO ECHO"
        var style = Self.style(.wrap)
        let weights: [TextWeight] = [.regular, .bold, .semibold]
        style.spans = [0, 5, 10].enumerated().map { index, start in
            var spanStyle = Self.style()
            spanStyle.weight = weights[index]
            let lower = text.index(text.startIndex, offsetBy: start)
            let upper = text.index(lower, offsetBy: 4)
            return TextSpan(text: "ECHO", style: spanStyle, range: lower..<upper)
        }
        let wrapped = Self.resolve(text, style: style, width: 4)
        XCTAssertEqual(wrapped.lines, ["ECHO", "ECHO", "ECHO"])
        let attached = Self.assemble(text, wrapped.fragments)
        for index in 0..<3 {
            let start = index * 5
            XCTAssertEqual(
                try XCTUnwrap(attached.lines[index].sourceProvenance).segments,
                [Self.copied(0..<4, start..<(start + 4))])
            let rebased = wrapped.fragments[index].rebasedStyle(style, sourceText: text)
            XCTAssertEqual(rebased.spans?.map(\.text), ["ECHO"])
            XCTAssertEqual(rebased.spans?.map { $0.style.weight }, [weights[index]])
        }
        XCTAssertEqual(try XCTUnwrap(attached.sourceProvenance).unrepresentedSourceUTF16Ranges, [4..<5, 9..<10])

        style.lineBreakMode = .truncateHead
        let truncated = Self.resolve(text, style: style, width: 7)
        XCTAssertEqual(truncated.lines, ["...ECHO"])
        let line = try XCTUnwrap(Self.assemble(text, truncated.fragments).lines[0].sourceProvenance)
        XCTAssertEqual(line.segments, [Self.generated(0..<3), Self.copied(3..<7, 10..<14)])
        XCTAssertEqual(
            truncated.fragments[0].rebasedStyle(style, sourceText: text).spans?.map { $0.style.weight }, [.semibold])
    }

    func testHardBreakAndEmptyLineAnchorsPreserveCRLFOffsets() async throws {
        let text = "\nA\rB\r\n\n"
        let resolved = Self.resolve(text)
        XCTAssertEqual(resolved.lines, ["", "A", "B", "", ""])
        XCTAssertEqual(resolved.fragments.map(\.emptySourceUTF16Anchor), [0, nil, nil, 6, 7])
        let attached = Self.assemble(text, resolved.fragments)
        XCTAssertEqual(attached.lines.compactMap { $0.sourceProvenance?.emptySourceUTF16Anchor }, [0, 6, 7])
        XCTAssertEqual(try XCTUnwrap(attached.sourceProvenance).unrepresentedSourceUTF16Ranges, [0..<1, 2..<3, 4..<7])
        XCTAssertEqual(try XCTUnwrap(attached.lines[1].sourceProvenance).segments, [Self.copied(0..<1, 1..<2)])
        XCTAssertEqual(try XCTUnwrap(attached.lines[2].sourceProvenance).segments, [Self.copied(0..<1, 3..<4)])

        for (hardBreak, end) in [("\n", 1), ("\r", 1), ("\r\n", 2)] {
            let fragments = TextLayoutSourceProvenance.sourceFragment(for: hardBreak).normalizedLines()
            XCTAssertEqual(fragments.map(\.text), ["", ""])
            XCTAssertEqual(fragments.map(\.emptySourceUTF16Anchor), [0, end])
            let projection = try XCTUnwrap(Self.assemble(hardBreak, fragments).sourceProvenance)
            XCTAssertEqual(projection.source.utf16Length, end)
            XCTAssertEqual(projection.unrepresentedSourceUTF16Ranges, [0..<end])
        }
        let whitespace = TextLayoutSourceProvenance.sourceFragment(for: " \t ").trimmingWhitespace()
        XCTAssertEqual(whitespace.text, "")
        XCTAssertEqual(whitespace.emptySourceUTF16Anchor, 3)
    }

    func testCollapsedWhitespaceIsReplacementNotCopiedText() async throws {
        let tabText = "A\tB"
        let tab = Self.resolve(tabText, style: Self.style(.wrap), width: 10)
        XCTAssertEqual(tab.lines, ["A B"])
        XCTAssertEqual(
            tab.fragments[0].mappings, [Self.mapping(0..<3, 0..<3)], "Existing joins coalesce the tab mapping")
        let attachedTab = Self.assemble(tabText, tab.fragments)
        XCTAssertEqual(
            try XCTUnwrap(attachedTab.lines[0].sourceProvenance).segments,
            [Self.copied(0..<1, 0..<1), Self.replaced(1..<2, 1..<2), Self.copied(2..<3, 2..<3)])
        XCTAssertEqual(try XCTUnwrap(attachedTab.sourceProvenance).unrepresentedSourceUTF16Ranges, [])
        XCTAssertEqual(Array(try XCTUnwrap(attachedTab.sourceProvenance).source.text.utf16), [65, 9, 66])

        let repeatedText = "A   B"
        let repeated = Self.resolve(repeatedText, style: Self.style(.wrap), width: 10)
        XCTAssertEqual(repeated.lines, ["A B"])
        let attachedSpaces = Self.assemble(repeatedText, repeated.fragments)
        XCTAssertEqual(
            try XCTUnwrap(attachedSpaces.lines[0].sourceProvenance).segments,
            [Self.copied(0..<2, 0..<2), Self.copied(2..<3, 4..<5)])
        XCTAssertEqual(try XCTUnwrap(attachedSpaces.sourceProvenance).unrepresentedSourceUTF16Ranges, [2..<4])

        let mixed = try XCTUnwrap(
            TextLayoutSourceProvenance.projectLine(
                source: TextLayoutSourceText("A\t\tBC\tD"), outputText: "A  BC D",
                mappings: [Self.mapping(0..<7, 0..<7)]))
        XCTAssertEqual(
            mixed.segments,
            [
                Self.copied(0..<1, 0..<1), Self.replaced(1..<3, 1..<3), Self.copied(3..<5, 3..<5),
                Self.replaced(5..<6, 5..<6), Self.copied(6..<7, 6..<7),
            ])
    }

    func testWrappedAndTrimmedFragmentsKeepSourceOrder() async throws {
        let text = "  ALPHA   BETA GAMMA  "
        var probes: [String] = []
        let resolved = resolveTextLayout(
            for: TextLayoutSourceProvenance.sourceFragment(for: text), style: Self.style(.wrap), maxContentWidth: 10
        ) { fragment in
            probes.append(fragment.text)
            return Double(fragment.text.count)
        }
        XCTAssertEqual(resolved.lines, ["ALPHA BETA", "GAMMA"])
        XCTAssertFalse(probes.isEmpty)
        let attached = Self.assemble(text, resolved.fragments)
        XCTAssertEqual(
            try XCTUnwrap(attached.lines[0].sourceProvenance).segments,
            [Self.copied(0..<6, 2..<8), Self.copied(6..<10, 10..<14)])
        XCTAssertEqual(try XCTUnwrap(attached.lines[1].sourceProvenance).segments, [Self.copied(0..<5, 15..<20)])
        XCTAssertEqual(
            try XCTUnwrap(attached.sourceProvenance).unrepresentedSourceUTF16Ranges, [0..<2, 8..<10, 14..<15, 20..<22])

        let token = Self.resolve("ABCDEFG", style: Self.style(.wrap), width: 3)
        XCTAssertEqual(token.lines, ["ABC", "DEF", "G"])
        let tokenLayout = Self.assemble("ABCDEFG", token.fragments)
        XCTAssertEqual(
            tokenLayout.lines.compactMap { $0.sourceProvenance?.segments.first?.sourceUTF16Range },
            [0..<3, 3..<6, 6..<7])
        XCTAssertEqual(try XCTUnwrap(tokenLayout.sourceProvenance).unrepresentedSourceUTF16Ranges, [])
    }

    func testTailTruncationDotsAreGeneratedWithoutSourceIdentity() async throws {
        let text = "ABC...DEF...GHI"
        let resolved = Self.resolve(text, style: Self.style(.truncateTail), width: 8)
        XCTAssertEqual(resolved.lines, ["ABC....."])
        let attached = Self.assemble(text, resolved.fragments)
        XCTAssertEqual(
            try XCTUnwrap(attached.lines[0].sourceProvenance).segments,
            [Self.copied(0..<5, 0..<5), Self.generated(5..<8)])
        XCTAssertEqual(try XCTUnwrap(attached.sourceProvenance).unrepresentedSourceUTF16Ranges, [5..<15])

        let generated = try XCTUnwrap(
            TextLayoutSourceProvenance.projectLine(source: TextLayoutSourceText("..."), outputText: "...", mappings: [])
        )
        XCTAssertEqual(generated.segments, [Self.generated(0..<3)], "Equal text is not a provenance witness")
        let failedFit = Self.resolve(text, style: Self.style(.truncateTail), width: 0)
        XCTAssertEqual(failedFit.lines, [""])
        XCTAssertNil(failedFit.fragments[0].emptySourceUTF16Anchor)
        let failedLayout = Self.assemble(text, failedFit.fragments)
        XCTAssertEqual(try XCTUnwrap(failedLayout.lines[0].sourceProvenance).segments, [])
        XCTAssertEqual(try XCTUnwrap(failedLayout.sourceProvenance).unrepresentedSourceUTF16Ranges, [0..<15])
    }

    func testHeadAndMiddleTruncationPreserveDisjointSourceSegments() async throws {
        let text = "ABCDEFGHIJK"
        let head = Self.resolve(text, style: Self.style(.truncateHead), width: 8)
        XCTAssertEqual(head.lines, ["...GHIJK"])
        let headLayout = Self.assemble(text, head.fragments)
        XCTAssertEqual(
            try XCTUnwrap(headLayout.lines[0].sourceProvenance).segments,
            [Self.generated(0..<3), Self.copied(3..<8, 6..<11)])
        XCTAssertEqual(try XCTUnwrap(headLayout.sourceProvenance).unrepresentedSourceUTF16Ranges, [0..<6])

        let middle = Self.resolve(text, style: Self.style(.truncateMiddle), width: 8)
        XCTAssertEqual(middle.lines, ["AB...IJK"])
        let middleLayout = Self.assemble(text, middle.fragments)
        XCTAssertEqual(
            try XCTUnwrap(middleLayout.lines[0].sourceProvenance).segments,
            [Self.copied(0..<2, 0..<2), Self.generated(2..<5), Self.copied(5..<8, 8..<11)])
        XCTAssertEqual(try XCTUnwrap(middleLayout.sourceProvenance).unrepresentedSourceUTF16Ranges, [2..<8])
        XCTAssertEqual(middle.fragments[0].mappings, [Self.mapping(0..<2, 0..<2), Self.mapping(5..<8, 8..<11)])
    }

    func testLineLimitAndSyntheticSeparatorsDoNotInventSourceCoverage() async throws {
        let text = "ONE\nTWO\nTHREE"
        var style = Self.style(.wrap)
        style.maximumNumberOfLines = 2
        let limited = Self.resolve(text, style: style, width: 6)
        XCTAssertEqual(limited.lines, ["ONE", "TWO..."])
        let attached = Self.assemble(text, limited.fragments)
        XCTAssertEqual(
            try XCTUnwrap(attached.lines[1].sourceProvenance).segments,
            [Self.copied(0..<3, 4..<7), Self.generated(3..<6)])
        XCTAssertEqual(try XCTUnwrap(attached.sourceProvenance).unrepresentedSourceUTF16Ranges, [3..<4, 7..<13])

        let joined = limited.fragment
        XCTAssertEqual(joined.text, "ONE\nTWO...")
        let joinedLayout = Self.assemble(text, [joined])
        XCTAssertEqual(
            try XCTUnwrap(joinedLayout.lines[0].sourceProvenance).segments,
            [Self.copied(0..<3, 0..<3), Self.generated(3..<4), Self.copied(4..<7, 4..<7), Self.generated(7..<10)])
        XCTAssertEqual(try XCTUnwrap(joinedLayout.sourceProvenance).unrepresentedSourceUTF16Ranges, [3..<4, 7..<13])

        style.lineBreakMode = .clip
        let clipped = Self.resolve(text, style: style, width: 6)
        XCTAssertEqual(clipped.lines, ["ONE", "TWO"])
        XCTAssertEqual(
            try XCTUnwrap(Self.assemble(text, clipped.fragments).sourceProvenance).unrepresentedSourceUTF16Ranges,
            [3..<4, 7..<13])
    }

    func testScalarPrecisionNeverPromotesPartialGraphemesToStops() async throws {
        let text = "e\u{301}X"
        let fragment = TextLayoutSourceProvenance.sourceFragment(for: text)
        let scalarEnd = text.unicodeScalars.index(after: text.unicodeScalars.startIndex)
        let scalar = fragment.slice(text.startIndex..<scalarEnd)
        XCTAssertEqual(Array(scalar.text.utf16), [101])
        XCTAssertEqual(scalar.mappings, [Self.mapping(0..<1, 0..<1)])
        let attached = Self.assemble(text, [scalar])
        XCTAssertEqual(try XCTUnwrap(attached.lines[0].sourceProvenance).segments, [Self.copied(0..<1, 0..<1)])
        XCTAssertEqual(try XCTUnwrap(attached.sourceProvenance).unrepresentedSourceUTF16Ranges, [1..<3])
        let rawAnchor = fragment.slice(scalarEnd..<scalarEnd)
        XCTAssertEqual(rawAnchor.emptySourceUTF16Anchor, 1)

        let snapshot = try XCTUnwrap(TextRangeSnapshot(text))
        XCTAssertNil(snapshot.characterOffset(atUTF16Offset: 1))
        XCTAssertNil(snapshot.range(utf16Start: 0, utf16End: 1))
        XCTAssertNotNil(snapshot.range(utf16Start: 0, utf16End: 2))
        XCTAssertNil(try XCTUnwrap(TextRangeSnapshot("\r\n")).characterOffset(atUTF16Offset: 1))

        let emoji = "\u{1F469}\u{200D}\u{1F4BB}"
        let emojiFragment = TextLayoutSourceProvenance.sourceFragment(for: emoji)
        let emojiLayout = Self.assemble(emoji, [emojiFragment])
        XCTAssertEqual(emoji.count, 1)
        XCTAssertEqual(try XCTUnwrap(emojiLayout.lines[0].sourceProvenance).outputUTF16Length, 5)
        let firstScalarEnd = emoji.unicodeScalars.index(after: emoji.unicodeScalars.startIndex)
        let firstScalar = emojiFragment.slice(emoji.startIndex..<firstScalarEnd)
        XCTAssertEqual(firstScalar.mappings, [Self.mapping(0..<2, 0..<2)])
        let emojiSnapshot = try XCTUnwrap(TextRangeSnapshot(emoji))
        XCTAssertNil(emojiSnapshot.characterOffset(atUTF16Offset: 1), "Surrogate interior stays illegal")
        XCTAssertNil(
            emojiSnapshot.characterOffset(atUTF16Offset: 2), "Scalar end inside the ZWJ Character stays illegal")
        XCTAssertNotNil(emojiSnapshot.range(utf16Start: 0, utf16End: 5))
    }

    func testBidiDisplayOrderDoesNotRewriteLogicalSourceOffsets() async throws {
        let text = "A\u{5D0}\u{5D1}B"
        let fragment = TextLayoutSourceProvenance.sourceFragment(for: text)
        var original = Self.drawable([text])
        original.lines[0].glyphs = [
            NativeTextGlyphLayout(character: "B", origin: Point(x: 0, y: 7), advance: 3, glyphID: 40, sourceIndex: 3),
            NativeTextGlyphLayout(
                character: "\u{5D1}", origin: Point(x: 3, y: 7), advance: 4, glyphID: 41, sourceIndex: 2),
            NativeTextGlyphLayout(
                character: "\u{5D0}", origin: Point(x: 7, y: 7), advance: 5, glyphID: 42, sourceIndex: 1),
            NativeTextGlyphLayout(character: "A", origin: Point(x: 12, y: 7), advance: 6, glyphID: 43, sourceIndex: 0),
        ]
        let attached = TextLayoutSourceProvenance.attaching(to: original, source: text, fragments: [fragment])
        XCTAssertEqual(try XCTUnwrap(attached.lines[0].sourceProvenance).segments, [Self.copied(0..<4, 0..<4)])
        XCTAssertEqual(attached.lines[0].glyphs.map(\.sourceIndex), [3, 2, 1, 0])
        XCTAssertEqual(attached.lines[0].glyphs.map { $0.origin.x }, [0, 3, 7, 12])
        XCTAssertEqual(Array(try XCTUnwrap(attached.sourceProvenance).source.text.utf16), [65, 0x5D0, 0x5D1, 66])
        Self.assertDrawableEqual(attached, original)
    }

    func testControlOnlySourceExtentDoesNotDependOnDisplaySegments() async throws {
        let controls = "\r\n"
        let controlLayout = Self.assemble(controls, Self.resolve(controls).fragments)
        let controlProjection = try XCTUnwrap(controlLayout.sourceProvenance)
        XCTAssertEqual(controlProjection.source.utf16Length, 2)
        XCTAssertEqual(Array(controlProjection.source.text.utf16), [13, 10])
        XCTAssertEqual(controlProjection.unrepresentedSourceUTF16Ranges, [0..<2])
        XCTAssertEqual(controlLayout.lines.map(\.text), ["", ""])
        XCTAssertTrue(controlLayout.lines.allSatisfy { $0.sourceProvenance?.segments.isEmpty == true })
        XCTAssertEqual(controlLayout.lines.map { $0.sourceProvenance?.emptySourceUTF16Anchor }, [0, 2])

        let emptyLayout = Self.assemble("", [TextLayoutSourceProvenance.sourceFragment(for: "")])
        XCTAssertEqual(try XCTUnwrap(emptyLayout.sourceProvenance).source.utf16Length, 0)
        XCTAssertEqual(try XCTUnwrap(emptyLayout.sourceProvenance).unrepresentedSourceUTF16Ranges, [])
        XCTAssertEqual(try XCTUnwrap(emptyLayout.lines[0].sourceProvenance).emptySourceUTF16Anchor, 0)
        XCTAssertNotEqual(controlProjection.source, try XCTUnwrap(emptyLayout.sourceProvenance).source)

        for text in ["", controls, "\u{0}\u{200E}"] {
            let noLines = Self.assemble(text, [])
            let projection = try XCTUnwrap(noLines.sourceProvenance)
            XCTAssertEqual(projection.source.utf16Length, text.utf16.count)
            XCTAssertEqual(projection.unrepresentedSourceUTF16Ranges, text.isEmpty ? [] : [0..<text.utf16.count])
        }
        let retainedControls = "\u{0}\u{200E}"
        let retained = Self.assemble(
            retainedControls, [TextLayoutSourceProvenance.sourceFragment(for: retainedControls)])
        XCTAssertEqual(try XCTUnwrap(retained.lines[0].sourceProvenance).segments, [Self.copied(0..<2, 0..<2)])
        XCTAssertEqual(Array(try XCTUnwrap(retained.sourceProvenance).source.text.utf16), [0, 0x200E])
        // These are source coordinates only; no semantic Character count is produced.
    }

    func testInvalidMappingsAndAmbiguousEmptyAnchorsDoNotGuess() async throws {
        let source = TextLayoutSourceText("ABCD")
        let invalid: [[TextLayoutFragment.Mapping]] = [
            [Self.mapping(-1..<0, 0..<1)],
            [Self.mapping(0..<1, -1..<0)],
            [Self.mapping(0..<5, 0..<5)],
            [Self.mapping(0..<1, 4..<5)],
            [Self.mapping(4..<5, 0..<1)],
            [Self.mapping(0..<2, 0..<1)],
            [Self.mapping(0..<0, 0..<0)],
            [Self.mapping(0..<3, 0..<3), Self.mapping(2..<4, 2..<4)],
            [Self.mapping(1..<3, 0..<2), Self.mapping(2..<4, 2..<4)],
            [Self.mapping(0..<1, 2..<3), Self.mapping(1..<2, 1..<2)],
            [Self.mapping(0..<1, 0..<1), Self.mapping(1..<2, 0..<1)],
            [Self.mapping(0..<Int.max, 0..<Int.max)],
            [Self.mapping(Int.min..<Int.max, Int.min..<Int.max)],
        ]
        for mappings in invalid {
            XCTAssertNil(TextLayoutSourceProvenance.projectLine(source: source, outputText: "ABCD", mappings: mappings))
        }
        for anchor in [Int.min, -1, 5, Int.max] {
            XCTAssertNil(
                TextLayoutSourceProvenance.projectLine(
                    source: source, outputText: "", mappings: [], emptySourceUTF16Anchor: anchor))
        }
        XCTAssertNil(
            TextLayoutSourceProvenance.projectLine(
                source: source, outputText: "A", mappings: [], emptySourceUTF16Anchor: 0))
        XCTAssertNil(
            TextLayoutSourceProvenance.projectLine(
                source: source, outputText: "", mappings: [Self.mapping(0..<1, 0..<1)]))
        XCTAssertNotNil(
            TextLayoutSourceProvenance.projectLine(
                source: source, outputText: "", mappings: [], emptySourceUTF16Anchor: 4))

        let fragment = TextLayoutSourceProvenance.sourceFragment(for: "ABCD")
        let generated = TextLayoutFragment(synthetic: "...")
        let mixed = fragment.prefix(1).appending(generated).appending(fragment.suffix(1))
        let generatedInterior = mixed.text.index(mixed.text.startIndex, offsetBy: 2)
        XCTAssertNil(mixed.slice(generatedInterior..<generatedInterior).emptySourceUTF16Anchor)
        let sharedEdge = mixed.text.index(after: mixed.text.startIndex)
        XCTAssertEqual(mixed.slice(sharedEdge..<sharedEdge).emptySourceUTF16Anchor, 1)
        let disjoint = fragment.prefix(1).appending(fragment.suffix(1))
        let disjointEdge = disjoint.text.index(after: disjoint.text.startIndex)
        XCTAssertNil(disjoint.slice(disjointEdge..<disjointEdge).emptySourceUTF16Anchor)
        let contiguous = fragment.prefix(2).appending(fragment.droppingFirst(2))
        let agreedEdge = contiguous.text.index(contiguous.text.startIndex, offsetBy: 2)
        XCTAssertEqual(contiguous.slice(agreedEdge..<agreedEdge).emptySourceUTF16Anchor, 2)

        let knownZero = fragment.prefix(0)
        let knownFour = fragment.suffix(0)
        let unknown = TextLayoutFragment(synthetic: "")
        XCTAssertEqual(knownZero.emptySourceUTF16Anchor, 0)
        XCTAssertEqual(knownFour.emptySourceUTF16Anchor, 4)
        XCTAssertNil(unknown.emptySourceUTF16Anchor)
        XCTAssertEqual(knownFour.slice(knownFour.text.startIndex..<knownFour.text.endIndex).emptySourceUTF16Anchor, 4)
        XCTAssertEqual(knownZero.appending(knownZero).emptySourceUTF16Anchor, 0)
        XCTAssertNil(knownZero.appending(knownFour).emptySourceUTF16Anchor)
        XCTAssertNil(knownZero.appending(unknown).emptySourceUTF16Anchor)
        XCTAssertNil(unknown.appending(knownZero).emptySourceUTF16Anchor)
        XCTAssertEqual(TextLayoutFragment.joined([knownZero, knownZero], separator: unknown).emptySourceUTF16Anchor, 0)
        XCTAssertNil(TextLayoutFragment.joined([knownZero, knownZero], separator: knownFour).emptySourceUTF16Anchor)
        XCTAssertNil(TextLayoutFragment.joined([knownZero, unknown], separator: unknown).emptySourceUTF16Anchor)
        XCTAssertEqual(TextLayoutFragment.joined([knownZero], separator: knownFour).emptySourceUTF16Anchor, 0)
        XCTAssertNil(TextLayoutFragment.joined([], separator: knownZero).emptySourceUTF16Anchor)

        // Preserve old width-cache keys: empty anchors do not participate in fragment equality/hash.
        XCTAssertEqual(knownZero, knownFour)
        XCTAssertEqual(knownZero, unknown)
        XCTAssertEqual(Set([knownZero, knownFour, unknown]).count, 1)
        XCTAssertEqual(knownZero.hashValue, knownFour.hashValue)
        XCTAssertEqual(knownZero.hashValue, unknown.hashValue)

        // Empty anchors constrain logical order but never count as represented source coverage.
        let reversedAnchorCases = [
            [fragment.suffix(0), fragment.prefix(2)],
            [fragment.suffix(2), fragment.prefix(0)],
        ]
        XCTAssertEqual(reversedAnchorCases[0].map(\.emptySourceUTF16Anchor), [4, nil])
        XCTAssertEqual(reversedAnchorCases[1].map(\.emptySourceUTF16Anchor), [nil, 0])
        for fragments in reversedAnchorCases {
            let drawing = Self.drawable(fragments.map(\.text))
            let attached = TextLayoutSourceProvenance.attaching(
                to: drawing, source: "ABCD", fragments: fragments)
            Self.assertUnavailable(attached)
            Self.assertDrawableEqual(attached, drawing)
        }

        let gapAnchor = fragment.prefix(2).suffix(0)
        XCTAssertEqual(gapAnchor.emptySourceUTF16Anchor, 2)
        let withoutAnchors = Self.assemble("ABCD", [fragment.prefix(1), fragment.suffix(1)])
        let withoutAnchorsProjection = try XCTUnwrap(withoutAnchors.sourceProvenance)
        XCTAssertEqual(withoutAnchorsProjection.unrepresentedSourceUTF16Ranges, [1..<3])
        let withoutAnchorsSegments = withoutAnchors.lines.flatMap { $0.sourceProvenance?.segments ?? [] }
        XCTAssertEqual(withoutAnchorsSegments, [Self.copied(0..<1, 0..<1), Self.copied(0..<1, 3..<4)])
        let gapCases: [([TextLayoutFragment], [Int?])] = [
            ([fragment.prefix(1), gapAnchor, fragment.suffix(1)], [nil, 2, nil]),
            ([fragment.prefix(1), gapAnchor, gapAnchor, fragment.suffix(1)], [nil, 2, 2, nil]),
        ]
        for (fragments, expectedAnchors) in gapCases {
            XCTAssertEqual(fragments.map(\.emptySourceUTF16Anchor), expectedAnchors)
            let drawing = Self.drawable(fragments.map(\.text))
            let attached = TextLayoutSourceProvenance.attaching(
                to: drawing, source: "ABCD", fragments: fragments)
            let projection = try XCTUnwrap(attached.sourceProvenance)
            XCTAssertEqual(projection.unrepresentedSourceUTF16Ranges, [1..<3])
            XCTAssertEqual(projection, withoutAnchorsProjection)
            XCTAssertTrue(attached.lines.allSatisfy { $0.sourceProvenance != nil })
            XCTAssertEqual(attached.lines.map { $0.sourceProvenance?.emptySourceUTF16Anchor }, expectedAnchors)
            XCTAssertEqual(
                attached.lines.flatMap { $0.sourceProvenance?.segments ?? [] }, withoutAnchorsSegments)
            Self.assertDrawableEqual(attached, drawing)
        }

        let validFragments = [fragment.prefix(2), fragment.droppingFirst(2)]
        let previouslyAttached = Self.assemble("ABCD", validFragments)
        XCTAssertNotNil(previouslyAttached.sourceProvenance)
        let missing = TextLayoutSourceProvenance.attaching(
            to: previouslyAttached, source: "ABCD", fragments: [validFragments[0]])
        Self.assertUnavailable(missing)
        Self.assertDrawableEqual(missing, previouslyAttached)
        let extra = TextLayoutSourceProvenance.attaching(
            to: previouslyAttached, source: "ABCD", fragments: validFragments + [unknown])
        Self.assertUnavailable(extra)

        let mismatched = TextLayoutSourceProvenance.attaching(
            to: previouslyAttached, source: "ABCD", fragments: [validFragments[0], TextLayoutFragment(synthetic: "XY")])
        Self.assertUnavailable(mismatched)
        let outOfBounds = TextLayoutSourceProvenance.attaching(
            to: previouslyAttached, source: "AB", fragments: validFragments)
        Self.assertUnavailable(outOfBounds)
        let reversed = Self.assemble("ABCD", [fragment.droppingFirst(2), fragment.prefix(2)])
        Self.assertUnavailable(reversed)
        let overlapping = Self.assemble("ABCD", [fragment.prefix(2), fragment.prefix(2)])
        Self.assertUnavailable(overlapping)

        // Same Swift String and same UTF16 length still cannot validate a different exact fragment.
        let canonicalDrawing = Self.drawable(["\u{212B}"])
        let canonicalMismatch = TextLayoutSourceProvenance.attaching(
            to: canonicalDrawing, source: "\u{C5}",
            fragments: [TextLayoutSourceProvenance.sourceFragment(for: "\u{C5}")])
        Self.assertUnavailable(canonicalMismatch)
        Self.assertDrawableEqual(canonicalMismatch, canonicalDrawing)
        let preservedSource = try XCTUnwrap(previouslyAttached.sourceProvenance)
        XCTAssertEqual(preservedSource.source.utf16Length, 4)
        XCTAssertTrue(previouslyAttached.lines.allSatisfy { $0.sourceProvenance != nil })
    }

    func testProvenancePreservesPaintMetricsAndMeasurementProbePolicy() async throws {
        let text = "ALPHA BETA GAMMA DELTA"
        var style = Self.style(.wrap)
        style.maximumNumberOfLines = 2
        var legacyProbes: [String] = []
        let legacy = resolveTextLayout(for: text, style: style, maxContentWidth: 10) { probe in
            legacyProbes.append(probe)
            return Double(probe.count)
        }
        var sourceProbes: [String] = []
        let resolved = resolveTextLayout(
            for: TextLayoutSourceProvenance.sourceFragment(for: text), style: style, maxContentWidth: 10
        ) { probe in
            sourceProbes.append(probe.text)
            return Double(probe.text.count)
        }
        XCTAssertEqual(resolved.lines, ["ALPHA BETA", "GAMMA..."])
        XCTAssertEqual(resolved.lines, legacy.lines)
        XCTAssertEqual(sourceProbes, legacyProbes)
        XCTAssertFalse(sourceProbes.isEmpty)
        let frozenProbes = sourceProbes
        let original = Self.drawable(resolved.lines)
        let attached = TextLayoutSourceProvenance.attaching(to: original, source: text, fragments: resolved.fragments)
        Self.assertDrawableEqual(attached, original)
        XCTAssertEqual(sourceProbes, frozenProbes, "Assembly has no measurement callback")
        XCTAssertNotNil(attached.sourceProvenance)
        XCTAssertNil(original.sourceProvenance)

        let savedOverrides = NativeTextRenderer.testingOverrides
        defer { NativeTextRenderer.testingOverrides = savedOverrides }
        var layoutCalls = 0
        var measureCalls = 0
        var scales: [Double] = []
        NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in
            measureCalls += 1
            return Size(width: 999, height: 999)
        }
        NativeTextRenderer.testingOverrides.layout = { _, _, scale, _ in
            layoutCalls += 1
            scales.append(scale)
            return attached
        }
        let system = WindowTextSystem()
        let first = try XCTUnwrap(system.layout(text, style: style, maxWidth: 10, scaleFactor: 1))
        let second = try XCTUnwrap(system.layout(text, style: style, maxWidth: 10, scaleFactor: 2))
        XCTAssertEqual(layoutCalls, 1)
        XCTAssertEqual(measureCalls, 0)
        XCTAssertEqual(scales, [1])
        XCTAssertEqual(system.cachedLayoutCount, 1)
        XCTAssertEqual(first.lines, attached.lines)
        XCTAssertEqual(second.lines, attached.lines)
        XCTAssertEqual(first.contentSize, original.contentSize)
        XCTAssertEqual(second.contentSize, original.contentSize)
        XCTAssertEqual(first.lineSpacing, original.lineSpacing)
        XCTAssertEqual(second.lineSpacing, original.lineSpacing)
        XCTAssertEqual(first.measuredSize, Size(width: 13, height: 21))
        XCTAssertEqual(second.measuredSize, Size(width: 12.5, height: 20.5))
        XCTAssertEqual(first.sourceProvenance, attached.sourceProvenance)
        XCTAssertEqual(second.sourceProvenance, attached.sourceProvenance)

        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in
            layoutCalls += 1
            return original
        }
        let oldSystem = WindowTextSystem()
        let oldOverride = try XCTUnwrap(oldSystem.layout(text, style: style, maxWidth: 10, scaleFactor: 1))
        Self.assertUnavailable(oldOverride)
        XCTAssertEqual(oldOverride.lines, original.lines)
        XCTAssertEqual(layoutCalls, 2)
        XCTAssertEqual(measureCalls, 0)
        XCTAssertEqual(sourceProbes, frozenProbes)
    }

    private static func style(_ mode: TextLineBreakMode = .clip) -> PixelTextStyle {
        PixelTextStyle(
            color: .white, scale: 1, alignment: .leading, verticalAlignment: .top, nativeFontSize: 14,
            lineBreakMode: mode)
    }

    private static func resolve(_ text: String, style: PixelTextStyle? = nil, width: Double? = nil)
        -> ResolvedTextLayout
    {
        resolveTextLayout(
            for: TextLayoutSourceProvenance.sourceFragment(for: text), style: style ?? Self.style(),
            maxContentWidth: width
        ) { Double($0.text.count) }
    }

    private static func mapping(_ output: Range<Int>, _ source: Range<Int>) -> TextLayoutFragment.Mapping {
        TextLayoutFragment.Mapping(outputUTF16Range: output, sourceUTF16Range: source)
    }

    private static func copied(_ output: Range<Int>, _ source: Range<Int>) -> TextLayoutSourceSegment {
        TextLayoutSourceSegment(kind: .copied, outputUTF16Range: output, sourceUTF16Range: source)
    }

    private static func replaced(_ output: Range<Int>, _ source: Range<Int>) -> TextLayoutSourceSegment {
        TextLayoutSourceSegment(kind: .replaced, outputUTF16Range: output, sourceUTF16Range: source)
    }

    private static func generated(_ output: Range<Int>) -> TextLayoutSourceSegment {
        TextLayoutSourceSegment(kind: .generated, outputUTF16Range: output, sourceUTF16Range: nil)
    }

    private static func assemble(_ source: String, _ fragments: [TextLayoutFragment]) -> NativeTextLayoutResult {
        TextLayoutSourceProvenance.attaching(to: drawable(fragments.map(\.text)), source: source, fragments: fragments)
    }

    private static func drawable(_ texts: [String]) -> NativeTextLayoutResult {
        let lines = texts.enumerated().map { lineIndex, text in
            let glyphs = text.enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 2.5, y: Double(lineIndex) * 12 + 7.25),
                    advance: 2.5, glyphID: UInt32(index + 1), fontSize: 14, sourceIndex: index, verticalFrame: .baseline
                )
            }
            return NativeTextLineLayout(
                text: text, width: Double(text.utf16.count) + 0.25, height: 10.5, ascent: 7.25, descent: 3.25,
                glyphs: glyphs)
        }
        return NativeTextLayoutResult(
            lines: lines, lineSpacing: 1.5, contentSize: Size(width: 99.25, height: 50.25),
            measuredSize: Size(width: 12.25, height: 20.25))
    }

    private static func assertDrawableEqual(
        _ actual: NativeTextLayoutResult, _ expected: NativeTextLayoutResult, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var actualDrawing = actual
        var expectedDrawing = expected
        actualDrawing.sourceProvenance = nil
        expectedDrawing.sourceProvenance = nil
        for index in actualDrawing.lines.indices { actualDrawing.lines[index].sourceProvenance = nil }
        for index in expectedDrawing.lines.indices { expectedDrawing.lines[index].sourceProvenance = nil }
        XCTAssertEqual(actualDrawing, expectedDrawing, file: file, line: line)
        for (actualLine, expectedLine) in zip(actual.lines, expected.lines) {
            XCTAssertEqual(Array(actualLine.text.utf16), Array(expectedLine.text.utf16), file: file, line: line)
        }
    }

    private static func assertUnavailable(
        _ layout: NativeTextLayoutResult, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertNil(layout.sourceProvenance, file: file, line: line)
        XCTAssertTrue(layout.lines.allSatisfy { $0.sourceProvenance == nil }, file: file, line: line)
    }
}
