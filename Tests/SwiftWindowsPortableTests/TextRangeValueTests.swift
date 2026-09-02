import XCTest

@testable import SwiftWindowsCore

/// Pure text/index values only. These fixtures neither advertise TextPattern nor
/// qualify document ownership, editor effects, native UIA, geometry, or Narrator.
final class TextRangeValueTests: XCTestCase {
    private let unicodeSource = "Ae\u{301}\u{1F469}\u{200D}\u{1F4BB}\u{05D0}\r\n\0Z"

    func testUTF16BoundaryMapPreservesGraphemeStopsAndOriginalText() throws {
        let value = try snapshot(unicodeSource)
        let offsets = [0, 1, 3, 8, 9, 11, 12, 13]
        XCTAssertEqual(value.characterCount, 7)
        XCTAssertEqual(value.utf16Count, 13)
        for (character, utf16) in offsets.enumerated() {
            XCTAssertEqual(value.utf16Offset(atCharacterOffset: character), utf16)
            XCTAssertEqual(value.characterOffset(atUTF16Offset: utf16), character)
        }
        for interior in [2, 4, 5, 6, 7, 10] {
            XCTAssertNil(value.characterOffset(atUTF16Offset: interior))
        }
        for invalid in [Int.min, -1, 14, Int.max] {
            XCTAssertNil(value.characterOffset(atUTF16Offset: invalid))
        }
        for invalid in [Int.min, -1, 8, Int.max] {
            XCTAssertNil(value.utf16Offset(atCharacterOffset: invalid))
        }
        XCTAssertEqual(Array(value.text.utf16), Array(unicodeSource.utf16))
    }

    func testEmptySnapshotHasOnlyZeroBoundary() throws {
        let value = try snapshot("")
        XCTAssertEqual(value.characterCount, 0)
        XCTAssertEqual(value.utf16Count, 0)
        XCTAssertEqual(value.utf16Offset(atCharacterOffset: 0), 0)
        XCTAssertEqual(value.characterOffset(atUTF16Offset: 0), 0)
        XCTAssertNil(value.characterOffset(atUTF16Offset: 1))
        XCTAssertEqual(value.documentRange, try span(0, 0, length: 0))
        XCTAssertEqual(try value.getText(in: value.documentRange), "")
    }

    func testUTF16RangeConversionRejectsReversedInteriorAndOverflowEndpoints() throws {
        let value = try snapshot(unicodeSource)
        let selected = try XCTUnwrap(value.range(utf16Start: 1, utf16End: 8))
        XCTAssertEqual(selected, try span(1, 3, length: 7))
        XCTAssertEqual(value.utf16Range(for: selected), 1..<8)
        XCTAssertNil(value.range(utf16Start: 8, utf16End: 1))
        XCTAssertNil(value.range(utf16Start: 2, utf16End: 8))
        XCTAssertNil(value.range(utf16Start: 1, utf16End: 7))
        XCTAssertNil(value.range(utf16Start: Int.min, utf16End: Int.max))
        XCTAssertNil(value.utf16Range(for: try span(1, 3, length: 8)))
    }

    func testCheckedSpanRejectsInvalidLengthsAndEndpoints() throws {
        XCTAssertNil(TextRangeSpan(start: 0, end: 0, characterCount: -1))
        XCTAssertNil(TextRangeSpan(start: 0, end: 0, characterCount: Int.min))
        XCTAssertNil(TextRangeSpan(start: -1, end: 2, characterCount: 4))
        XCTAssertNil(TextRangeSpan(start: 3, end: 2, characterCount: 4))
        XCTAssertNil(TextRangeSpan(start: 0, end: 5, characterCount: 4))
        XCTAssertNil(TextRangeSpan(start: 0, end: Int.max, characterCount: 4))
        XCTAssertEqual(try span(4, 4, length: 4).characterRange, 4..<4)
    }

    func testClampingSortsAnchorAndExtentWithoutSignedOverflow() throws {
        XCTAssertEqual(
            TextRangeSpan(clampingAnchor: Int.max, extent: Int.min, characterCount: 5),
            try span(0, 5, length: 5))
        XCTAssertEqual(
            TextRangeSpan(clampingAnchor: 4, extent: 2, characterCount: 5),
            try span(2, 4, length: 5))
        XCTAssertEqual(
            TextRangeSpan(clampingAnchor: Int.min, extent: Int.max, characterCount: 0),
            try span(0, 0, length: 0))
        XCTAssertNil(TextRangeSpan(clampingAnchor: 1, extent: 2, characterCount: -1))
    }

    func testEndpointReplacementCollapsesOnCrossingAndRejectsInvalidOffsets() throws {
        let original = try span(2, 5, length: 8)
        XCTAssertEqual(original.replacingEndpoint(.start, with: 7), try span(7, 7, length: 8))
        XCTAssertEqual(original.replacingEndpoint(.end, with: 1), try span(1, 1, length: 8))
        XCTAssertEqual(original.replacingEndpoint(.start, with: 3), try span(3, 5, length: 8))
        XCTAssertEqual(original.replacingEndpoint(.end, with: 8), try span(2, 8, length: 8))
        XCTAssertNil(original.replacingEndpoint(.start, with: Int.min))
        XCTAssertNil(original.replacingEndpoint(.end, with: Int.max))
    }

    func testSpanCopyEqualityAndEndpointDistanceAreValuesOnly() throws {
        let original = try span(2, 5, length: 8)
        let copy = original
        let changed = try XCTUnwrap(copy.replacingEndpoint(.start, with: 4))
        let other = try span(4, 8, length: 8)
        XCTAssertEqual(original, copy)
        XCTAssertEqual(original, try span(2, 5, length: 8))
        XCTAssertNotEqual(changed, original)
        XCTAssertEqual(original.characterRange, 2..<5)
        XCTAssertEqual(original.compareEndpoint(.start, to: other, endpoint: .end), -6)
        XCTAssertEqual(original.compareEndpoint(.end, to: other, endpoint: .start), 1)
        XCTAssertEqual(original.compareEndpoint(.end, to: copy, endpoint: .end), 0)
        let differentLength = try span(2, 5, length: 9)
        XCTAssertNotEqual(original, differentLength)
        XCTAssertNil(original.compareEndpoint(.start, to: differentLength, endpoint: .start))
    }

    func testTextExtractionPreservesUTF16AndDoesNotNormalizeSource() throws {
        let value = try snapshot("e\u{301}\r\n\0\u{E9}")
        let full = try value.getText(in: value.documentRange)
        XCTAssertEqual(Array(full.utf16), [101, 769, 13, 10, 0, 233])
        XCTAssertEqual(
            Array(try value.getText(in: try span(0, 1, length: 4)).utf16), [101, 769])
        XCTAssertEqual(
            Array(try value.getText(in: value.documentRange, maximumUTF16Length: Int.max).utf16),
            [101, 769, 13, 10, 0, 233])
    }

    func testTextLimitUsesUTF16BudgetAndKeepsWholeGraphemes() throws {
        let emoji = "\u{1F469}\u{200D}\u{1F4BB}"
        let value = try snapshot("A\(emoji)e\u{301}B")
        let cases: [(Int, String)] = [
            (0, ""), (1, "A"), (2, "A"), (5, "A"), (6, "A\(emoji)"),
            (7, "A\(emoji)"), (8, "A\(emoji)e\u{301}"), (9, value.text),
        ]
        for (limit, expected) in cases {
            let actual = try value.getText(in: value.documentRange, maximumUTF16Length: limit)
            XCTAssertEqual(Array(actual.utf16), Array(expected.utf16))
            XCTAssertLessThanOrEqual(actual.utf16.count, limit)
        }
        let tail = try span(1, 4, length: 4)
        XCTAssertEqual(try value.getText(in: tail, maximumUTF16Length: 4), "")
        XCTAssertEqual(try value.getText(in: tail, maximumUTF16Length: 5), emoji)
        XCTAssertEqual(try value.getText(in: tail, maximumUTF16Length: 6), emoji)
        XCTAssertEqual(try value.getText(in: tail, maximumUTF16Length: 7), "\(emoji)e\u{301}")
        XCTAssertEqual(try value.getText(in: tail, maximumUTF16Length: 8), "\(emoji)e\u{301}B")
    }

    func testInvalidTextLimitAndForeignLengthFailWithoutTruncating() throws {
        let value = try snapshot("abc")
        for limit in [-2, Int.min] {
            XCTAssertThrowsError(try value.getText(in: value.documentRange, maximumUTF16Length: limit)) {
                XCTAssertEqual($0 as? TextRangeValueError, .invalidMaximumLength)
            }
        }
        let wrongLength = try span(0, 3, length: 4)
        XCTAssertThrowsError(try value.getText(in: wrongLength)) {
            XCTAssertEqual($0 as? TextRangeValueError, .incompatibleLength)
        }
    }

    func testForwardBackwardSearchFindsFirstLastAndOverlappingMatches() throws {
        let value = try snapshot("ababa")
        XCTAssertEqual(try value.findText("aba", in: value.documentRange), try span(0, 3, length: 5))
        XCTAssertEqual(
            try value.findText("aba", in: value.documentRange, backward: true), try span(2, 5, length: 5))
        XCTAssertEqual(
            try value.findText("aba", in: try span(1, 5, length: 5)), try span(2, 5, length: 5))
        XCTAssertNil(try value.findText("x", in: value.documentRange))
    }

    func testSearchRespectsRangeEdgesAndRejectsEmptyNeedles() throws {
        let value = try snapshot("abcabc")
        XCTAssertNil(try value.findText("abc", in: try span(1, 5, length: 6)))
        XCTAssertNil(try value.findText("a", in: try span(3, 3, length: 6)))
        XCTAssertThrowsError(try value.findText("", in: value.documentRange)) {
            XCTAssertEqual($0 as? TextRangeValueError, .emptySearchText)
        }
        let wrongLength = try span(0, 3, length: 5)
        XCTAssertThrowsError(try value.findText("a", in: wrongLength)) {
            XCTAssertEqual($0 as? TextRangeValueError, .incompatibleLength)
        }
    }

    func testLiteralSearchDoesNotNormalizeCombiningText() throws {
        let value = try snapshot("e\u{301}|\u{E9}")
        XCTAssertEqual(try value.findText("\u{E9}", in: value.documentRange), try span(2, 3, length: 3))
        XCTAssertEqual(try value.findText("e\u{301}", in: value.documentRange), try span(0, 1, length: 3))
        XCTAssertNil(try value.findText("e", in: value.documentRange))
        XCTAssertNil(try value.findText("\u{301}", in: value.documentRange))
    }

    func testSearchSkipsPartialGraphemesInBothDirections() throws {
        let value = try snapshot("e\u{301}e e\u{301}")
        XCTAssertEqual(try value.findText("e", in: value.documentRange), try span(1, 2, length: 4))
        XCTAssertEqual(
            try value.findText("e", in: value.documentRange, backward: true), try span(1, 2, length: 4))
        XCTAssertNil(try value.findText("\u{301}", in: value.documentRange))
        let emoji = try snapshot("\u{1F469}\u{200D}\u{1F4BB}\u{1F469}")
        XCTAssertEqual(
            try emoji.findText("\u{1F469}", in: emoji.documentRange), try span(1, 2, length: 2))
        XCTAssertNil(try emoji.findText("\u{200D}", in: emoji.documentRange))
    }

    func testSearchPreservesBidiCRLFAndNulMatches() throws {
        let value = try snapshot("\u{05D0}\u{05D1}\r\n\0\u{05D0}\u{05D1}")
        XCTAssertEqual(
            try value.findText("\u{05D0}\u{05D1}", in: value.documentRange), try span(0, 2, length: 6))
        XCTAssertEqual(
            try value.findText("\u{05D0}\u{05D1}", in: value.documentRange, backward: true),
            try span(4, 6, length: 6))
        XCTAssertEqual(try value.findText("\r\n\0", in: value.documentRange), try span(2, 4, length: 6))
        XCTAssertEqual(try value.findText("\0", in: value.documentRange), try span(3, 4, length: 6))
        XCTAssertNil(try value.findText("\n", in: value.documentRange))
    }

    func testCaseInsensitiveSearchUsesFixedComparisonWithoutChangingText() throws {
        let value = try snapshot("One oNE \u{C9} \u{E9}")
        XCTAssertNil(try value.findText("one", in: value.documentRange))
        XCTAssertEqual(
            try value.findText("one", in: value.documentRange, ignoreCase: true), try span(0, 3, length: 11))
        XCTAssertEqual(
            try value.findText("one", in: value.documentRange, backward: true, ignoreCase: true),
            try span(4, 7, length: 11))
        XCTAssertEqual(
            try value.findText("\u{E9}", in: value.documentRange, ignoreCase: true),
            try span(8, 9, length: 11))
        XCTAssertEqual(Array(value.text.utf16), Array("One oNE \u{C9} \u{E9}".utf16))
    }

    func testUnitBoundaryTablesRejectMissingRepeatedUnorderedAndOutsideStops() throws {
        XCTAssertNotNil(TextRangeUnitBoundaries(characterCount: 10, offsets: [0, 4, 10]))
        for invalid in [[], [0], [1, 10], [0, 4, 4, 10], [0, 5, 3, 10], [0, 11, 10], [-1, 10]] {
            XCTAssertNil(TextRangeUnitBoundaries(characterCount: 10, offsets: invalid))
        }
        XCTAssertNil(TextRangeUnitBoundaries(characterCount: -1, offsets: [0]))
        XCTAssertNil(TextRangeUnitBoundaries(characterCount: 0, offsets: [0, 0]))
        XCTAssertNotNil(TextRangeUnitBoundaries(characterCount: 0, offsets: [0]))
        XCTAssertNotNil(TextRangeUnitBoundaries(characterCount: Int.max, offsets: [0, Int.max - 1, Int.max]))
    }

    func testUnitExpansionUsesExplicitIntervalsAndLastIntervalAtEOF() throws {
        let units = try boundaries([0, 3, 8, 10], length: 10)
        XCTAssertEqual(units.expanded(try span(1, 9, length: 10)), try span(0, 3, length: 10))
        XCTAssertEqual(units.expanded(try span(3, 3, length: 10)), try span(3, 8, length: 10))
        XCTAssertEqual(units.expanded(try span(10, 10, length: 10)), try span(8, 10, length: 10))
        XCTAssertEqual(units.expanded(try span(0, 0, length: 10)), try span(0, 3, length: 10))
    }

    func testWholeRangeMovementNormalizesOnlyAfterAnActualMove() throws {
        let units = try boundaries([0, 3, 8, 10], length: 10)
        let original = try span(1, 7, length: 10)
        try assertMovement(units.moving(original, by: 1), start: 3, end: 8, moved: 1)
        try assertMovement(units.moving(original, by: 3), start: 8, end: 10, moved: 2)
        try assertMovement(units.moving(original, by: -1), start: 1, end: 7, moved: 0)
        try assertMovement(units.moving(original, by: 0), start: 1, end: 7, moved: 0)
        try assertMovement(units.moving(try span(9, 10, length: 10), by: 1), start: 9, end: 10, moved: 0)
        try assertMovement(units.moving(try span(3, 10, length: 10), by: -1), start: 0, end: 3, moved: -1)
    }

    func testDegenerateMovementReachesDocumentEndAndPreservesDegeneracy() throws {
        let units = try boundaries([0, 3, 8, 10], length: 10)
        let caret = try span(2, 2, length: 10)
        try assertMovement(units.moving(caret, by: 1), start: 3, end: 3, moved: 1)
        try assertMovement(units.moving(caret, by: -1), start: 0, end: 0, moved: -1)
        try assertMovement(units.moving(caret, by: Int.max), start: 10, end: 10, moved: 3)
        try assertMovement(units.moving(caret, by: 0), start: 2, end: 2, moved: 0)
        let end = try span(10, 10, length: 10)
        try assertMovement(units.moving(end, by: -1), start: 8, end: 8, moved: -1)
        try assertMovement(units.moving(end, by: 1), start: 10, end: 10, moved: 0)
    }

    func testEndpointUnitMovementCrossesAndStopsAtDocumentBounds() throws {
        let units = try boundaries([0, 3, 8, 10], length: 10)
        let original = try span(2, 5, length: 10)
        try assertMovement(units.movingEndpoint(.start, in: original, by: 2), start: 8, end: 8, moved: 2)
        try assertMovement(units.movingEndpoint(.end, in: original, by: -2), start: 0, end: 0, moved: -2)
        try assertMovement(units.movingEndpoint(.start, in: original, by: 1), start: 3, end: 5, moved: 1)
        try assertMovement(units.movingEndpoint(.end, in: original, by: -1), start: 2, end: 3, moved: -1)
        try assertMovement(units.movingEndpoint(.end, in: original, by: 0), start: 2, end: 5, moved: 0)
    }

    func testUnitMovementClampsIntMinAndIntMaxWithoutOverflow() throws {
        let length = Int.max
        let units = try boundaries([0, length - 2, length - 1, length], length: length)
        let original = try span(1, length - 1, length: length)
        try assertMovement(
            units.moving(original, by: Int.max), start: length - 1, end: length, moved: 2, length: length)
        let middle = try span(length - 2, length - 1, length: length)
        try assertMovement(
            units.moving(middle, by: Int.min), start: 0, end: length - 2, moved: -1, length: length)
        let caret = try span(0, 0, length: length)
        try assertMovement(
            units.moving(caret, by: Int.max), start: length, end: length, moved: 3, length: length)
        try assertMovement(
            units.movingEndpoint(.end, in: middle, by: Int.min),
            start: 0, end: 0, moved: -2, length: length)
        let full = try span(0, length, length: length)
        XCTAssertEqual(full.compareEndpoint(.start, to: full, endpoint: .end), -Int.max)
    }

    func testUnitOperationsRejectMismatchedLengthAndKeepEmptyDocumentUnchanged() throws {
        let units = try boundaries([0, 3, 8, 10], length: 10)
        let wrongLength = try span(1, 3, length: 4)
        XCTAssertNil(units.expanded(wrongLength))
        XCTAssertNil(units.moving(wrongLength, by: 1))
        XCTAssertNil(units.movingEndpoint(.start, in: wrongLength, by: 1))
        let empty = try span(0, 0, length: 0)
        let emptyUnits = try boundaries([0], length: 0)
        XCTAssertEqual(emptyUnits.expanded(empty), empty)
        for count in [Int.min, 0, Int.max] {
            try assertMovement(emptyUnits.moving(empty, by: count), start: 0, end: 0, moved: 0, length: 0)
            try assertMovement(
                emptyUnits.movingEndpoint(.end, in: empty, by: count), start: 0, end: 0, moved: 0, length: 0)
        }
    }

    func testExplicitUnitsDoNotInventStopsForControlCharactersOrBidi() throws {
        let value = try snapshot("A\r\n\u{200E}B")
        XCTAssertEqual(value.characterCount, 4)
        let units = try boundaries([0, 3, 4], length: 4)
        let caret = try span(0, 0, length: 4)
        try assertMovement(units.moving(caret, by: 1), start: 3, end: 3, moved: 1, length: 4)
        let firstUnit = try XCTUnwrap(units.expanded(caret))
        XCTAssertEqual(Array(try value.getText(in: firstUnit).utf16), [65, 13, 10, 8206])
        XCTAssertEqual(value.characterOffset(atUTF16Offset: 3), 2)
    }

    func testSnapshotAndBoundariesCopiesRemainIndependentOfMutableInputs() throws {
        var input = "A\u{E9}"
        let value = try snapshot(input)
        input.append("B")
        XCTAssertEqual(try value.getText(in: value.documentRange), "A\u{E9}")
        XCTAssertEqual(value.characterCount, 2)
        var offsets = [0, 1, 2]
        let units = try boundaries(offsets, length: 2)
        offsets = [0, 2]
        XCTAssertEqual(units.expanded(try span(0, 0, length: 2)), try span(0, 1, length: 2))
        XCTAssertEqual(offsets, [0, 2])
    }

    private func snapshot(_ text: String) throws -> TextRangeSnapshot {
        try XCTUnwrap(TextRangeSnapshot(text))
    }

    private func span(_ start: Int, _ end: Int, length: Int) throws -> TextRangeSpan {
        try XCTUnwrap(TextRangeSpan(start: start, end: end, characterCount: length))
    }

    private func boundaries(_ offsets: [Int], length: Int) throws -> TextRangeUnitBoundaries {
        try XCTUnwrap(TextRangeUnitBoundaries(characterCount: length, offsets: offsets))
    }

    private func assertMovement(
        _ result: TextRangeMovement?, start: Int, end: Int, moved: Int, length: Int = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let result = try XCTUnwrap(result, file: file, line: line)
        XCTAssertEqual(result.span, try span(start, end, length: length), file: file, line: line)
        XCTAssertEqual(result.unitsMoved, moved, file: file, line: line)
    }
}
