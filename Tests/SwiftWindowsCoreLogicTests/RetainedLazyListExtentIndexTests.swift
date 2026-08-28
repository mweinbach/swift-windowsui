import XCTest

@testable import SwiftWindowsUI

/// Source-only model coverage. These cases create no retained tree or native
/// window and make no claim about lazy List construction or native parity.
@MainActor
final class RetainedLazyListExtentIndexTests: XCTestCase {
    private func context(
        width: Double = 320,
        displayScale: Double = 1,
        contentRevision: UInt64 = 1,
        environmentRevision: UInt64 = 1
    ) throws -> RetainedLazyListMeasurementContext {
        try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: width, displayScale: displayScale,
                contentRevision: contentRevision, environmentRevision: environmentRevision))
    }

    private func tokens(count: Int) throws -> [RetainedLazyListRowToken] {
        let source = RetainedLazyListDataSource<Int, Int>()
        var factoryCalls = 0
        XCTAssertTrue(
            source.replaceData(Array(0..<count), id: \.self) {
                factoryCalls += 1
                return $0
            })
        XCTAssertEqual(factoryCalls, 0)
        return try XCTUnwrap(source.metadata).rows.map(\.token)
    }

    private func extents(_ heights: [Double]) throws -> [RetainedLazyListExtent] {
        try heights.map { try XCTUnwrap(RetainedLazyListExtent.measured([$0])) }
    }

    private func index(_ heights: [Double]) throws -> RetainedLazyListExtentIndex {
        try XCTUnwrap(
            RetainedLazyListExtentIndex(
                tokens: tokens(count: heights.count), extents: extents(heights), context: context()))
    }

    func testMeasurementContextValidatesWidthAndDisplayScale() async throws {
        for invalid in [-1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(
                RetainedLazyListMeasurementContext(
                    width: invalid, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        }
        for invalid in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(
                RetainedLazyListMeasurementContext(
                    width: 1, displayScale: invalid, contentRevision: 0, environmentRevision: 0))
        }
        let emptyWidth = try context(width: 0, displayScale: 1.25)
        XCTAssertEqual(emptyWidth.width, 0)
        XCTAssertEqual(emptyWidth.displayScale, 1.25)
        XCTAssertEqual(try context(contentRevision: .max, environmentRevision: .max).contentRevision, .max)
    }

    func testUnknownEstimateRequiresFinitePositiveExtentWithoutInventingLeafCount() async throws {
        for invalid in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(RetainedLazyListExtent.estimated(invalid))
        }
        let estimate = try XCTUnwrap(RetainedLazyListExtent.estimated(24))
        XCTAssertEqual(estimate.totalExtent, 24)
        XCTAssertNil(estimate.measuredLeafCount)
        XCTAssertNotNil(RetainedLazyListExtent.estimated(.leastNonzeroMagnitude))
        XCTAssertNotNil(RetainedLazyListExtent.estimated(.greatestFiniteMagnitude))
    }

    func testMeasuredZeroAndMultipleLeavesKeepTheirCardinality() async throws {
        let empty = try XCTUnwrap(RetainedLazyListExtent.measured([]))
        let zeroLeaves = try XCTUnwrap(RetainedLazyListExtent.measured([0, 0]))
        let multiple = try XCTUnwrap(RetainedLazyListExtent.measured([8, 0, 13, 3]))
        XCTAssertEqual(empty.totalExtent, 0)
        XCTAssertEqual(empty.measuredLeafCount, 0)
        XCTAssertEqual(zeroLeaves.totalExtent, 0)
        XCTAssertEqual(zeroLeaves.measuredLeafCount, 2)
        XCTAssertNotEqual(empty, zeroLeaves)
        XCTAssertEqual(multiple.totalExtent, 24)
        XCTAssertEqual(multiple.measuredLeafCount, 4)
    }

    func testMeasuredLeavesRejectNegativeNonfiniteAndOverflowingContributions() async {
        for invalid in [-1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(RetainedLazyListExtent.measured([2, invalid, 3]))
        }
        XCTAssertNil(RetainedLazyListExtent.measured([.greatestFiniteMagnitude, .greatestFiniteMagnitude]))
        XCTAssertNotNil(RetainedLazyListExtent.measured([-0.0]))
    }

    func testIndexRejectsCountMismatchDuplicateTokensAndOverflow() async throws {
        let rows = try tokens(count: 2)
        let measurement = try context()
        let one = try XCTUnwrap(RetainedLazyListExtent.estimated(1))
        let largest = try XCTUnwrap(RetainedLazyListExtent.estimated(.greatestFiniteMagnitude))
        XCTAssertNil(RetainedLazyListExtentIndex(tokens: rows, extents: [one], context: measurement))
        XCTAssertNil(RetainedLazyListExtentIndex(tokens: [], extents: [one], context: measurement))
        XCTAssertNil(
            RetainedLazyListExtentIndex(tokens: [rows[0], rows[0]], extents: [one, one], context: measurement))
        XCTAssertNil(RetainedLazyListExtentIndex(tokens: rows, extents: [largest, largest], context: measurement))
        XCTAssertNotNil(RetainedLazyListExtentIndex(tokens: [rows[0]], extents: [largest], context: measurement))
    }

    func testEmptyIndexHasOnlyItsTerminalPrefixAndNoAnchor() async throws {
        var empty = try index([])
        XCTAssertEqual(empty.count, 0)
        XCTAssertEqual(empty.totalExtent, 0)
        XCTAssertEqual(empty.prefixOffset(before: 0), 0)
        XCTAssertNil(empty.prefixOffset(before: -1))
        XCTAssertNil(empty.prefixOffset(before: 1))
        XCTAssertEqual(empty.window(offset: 0, viewportExtent: 100), 0..<0)
        XCTAssertEqual(empty.window(offset: 200, viewportExtent: 0, prefetchExtent: 10), 0..<0)
        XCTAssertNil(empty.captureAnchor(at: 0))
        let foreign = try tokens(count: 1)[0]
        let extent = try XCTUnwrap(RetainedLazyListExtent.estimated(10))
        XCTAssertFalse(empty.updateExtent(for: foreign, to: extent, context: empty.context))
    }

    func testPrefixOffsetsIncludeTerminalPrefixAndRejectInvalidIndices() async throws {
        let result = try index([3, 0, 5, 2, 7])
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.totalExtent, 17)
        XCTAssertEqual((0...5).compactMap { result.prefixOffset(before: $0) }, [0, 3, 3, 8, 10, 17])
        for invalid in [Int.min, -1, 6, Int.max] { XCTAssertNil(result.prefixOffset(before: invalid)) }
    }

    func testHalfOpenWindowsExcludeLeadingTrailingAndBoundaryZeroRecords() async throws {
        let result = try index([0, 5, 0, 0, 7, 0])
        XCTAssertEqual(result.window(offset: 0, viewportExtent: 5), 1..<2)
        XCTAssertEqual(result.window(offset: 5, viewportExtent: 7), 4..<5)
        XCTAssertEqual(result.window(offset: 4, viewportExtent: 2), 1..<5)
        XCTAssertEqual(result.window(offset: 0, viewportExtent: 12), 1..<5)
        XCTAssertEqual(result.window(offset: 12, viewportExtent: 20), 6..<6)
        XCTAssertEqual(result.window(offset: -20, viewportExtent: 20), 0..<0)
        XCTAssertEqual(result.window(offset: 5, viewportExtent: 0), 4..<4)
    }

    func testPrefetchExpandsBothSidesAndNegativeOffsetsAreAccepted() async throws {
        let result = try index([10, 10, 10, 10, 10])
        XCTAssertEqual(result.window(offset: 20, viewportExtent: 10, prefetchExtent: 10), 1..<4)
        XCTAssertEqual(result.window(offset: -5, viewportExtent: 10, prefetchExtent: 2), 0..<1)
        XCTAssertEqual(result.window(offset: 20, viewportExtent: 0, prefetchExtent: 5), 1..<3)
        XCTAssertEqual(result.window(offset: 50, viewportExtent: 0, prefetchExtent: 5), 4..<5)
        XCTAssertEqual(result.window(offset: 100, viewportExtent: 10), 5..<5)
    }

    func testFractionalExtentsPreserveHalfOpenBoundariesAndWithinRecordAnchor() async throws {
        let rows = try tokens(count: 5)
        var result = try XCTUnwrap(
            RetainedLazyListExtentIndex(
                tokens: rows, extents: extents([0.25, 0, 0.5, 0.125, 2.25]), context: context(displayScale: 1.25)))
        XCTAssertEqual((0...5).compactMap { result.prefixOffset(before: $0) }, [0, 0.25, 0.25, 0.75, 0.875, 3.125])
        XCTAssertEqual(result.window(offset: 0.25, viewportExtent: 0.5), 2..<3)
        XCTAssertEqual(result.window(offset: 0.75, viewportExtent: 0.125), 3..<4)
        XCTAssertEqual(result.window(offset: 0.875, viewportExtent: 2.25), 4..<5)
        let anchor = try XCTUnwrap(result.captureAnchor(at: 0.625))
        XCTAssertEqual(anchor.token, rows[2])
        XCTAssertEqual(anchor.offsetWithinRecord, 0.375)
        let shorter = try XCTUnwrap(RetainedLazyListExtent.measured([0.125, 0.125]))
        XCTAssertTrue(result.updateExtent(for: rows[2], to: shorter, context: result.context))
        XCTAssertEqual(result.resolveAnchor(anchor, viewportExtent: 0), 0.5)
    }

    func testWindowRejectsNonfiniteNegativeExtentsAndExpandedEndpointOverflow() async throws {
        let result = try index([10])
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(result.window(offset: invalid, viewportExtent: 1))
            XCTAssertNil(result.window(offset: 0, viewportExtent: invalid))
            XCTAssertNil(result.window(offset: 0, viewportExtent: 1, prefetchExtent: invalid))
        }
        XCTAssertNil(result.window(offset: 0, viewportExtent: -1))
        XCTAssertNil(result.window(offset: 0, viewportExtent: 1, prefetchExtent: -1))
        XCTAssertNil(result.window(offset: .greatestFiniteMagnitude, viewportExtent: .greatestFiniteMagnitude))
        XCTAssertNil(
            result.window(
                offset: -.greatestFiniteMagnitude, viewportExtent: 0, prefetchExtent: .greatestFiniteMagnitude))
        XCTAssertNil(
            result.window(offset: 0, viewportExtent: .greatestFiniteMagnitude, prefetchExtent: .greatestFiniteMagnitude)
        )
    }

    func testAllZeroRecordsProduceNoWindowOrCaptureAnchor() async throws {
        let result = try index([0, 0, 0, 0, 0])
        XCTAssertEqual((0...5).compactMap { result.prefixOffset(before: $0) }, [0, 0, 0, 0, 0, 0])
        for offset in [-100.0, 0, 100] {
            XCTAssertEqual(result.window(offset: offset, viewportExtent: 50, prefetchExtent: 10), 0..<0)
            XCTAssertNil(result.captureAnchor(at: offset))
        }
    }

    func testPointUpdatePreservesMeasuredZeroAndMultipleLeafCounts() async throws {
        let rows = try tokens(count: 3)
        let unknown = try XCTUnwrap(RetainedLazyListExtent.estimated(20))
        var result = try XCTUnwrap(
            RetainedLazyListExtentIndex(tokens: rows, extents: [unknown, unknown, unknown], context: context()))
        let empty = try XCTUnwrap(RetainedLazyListExtent.measured([]))
        let multiple = try XCTUnwrap(RetainedLazyListExtent.measured([4, 0, 9]))
        XCTAssertTrue(result.updateExtent(for: rows[0], to: empty, context: result.context))
        XCTAssertTrue(result.updateExtent(for: rows[1], to: multiple, context: result.context))
        XCTAssertEqual(result.extent(for: rows[0]), empty)
        XCTAssertEqual(result.extent(for: rows[1])?.measuredLeafCount, 3)
        XCTAssertNil(result.extent(for: rows[2])?.measuredLeafCount)
        XCTAssertEqual((0...3).compactMap { result.prefixOffset(before: $0) }, [0, 0, 13, 33])
        XCTAssertEqual(result.window(offset: 0, viewportExtent: 13), 1..<2)
    }

    func testPointUpdatesRejectEveryDifferentMeasurementContextWithoutMutation() async throws {
        let rows = try tokens(count: 1)
        let original = try XCTUnwrap(RetainedLazyListExtent.estimated(20))
        let next = try XCTUnwrap(RetainedLazyListExtent.measured([10, 15]))
        let measurement = try context()
        var result = try XCTUnwrap(
            RetainedLazyListExtentIndex(tokens: rows, extents: [original], context: measurement))
        let staleContexts = try [
            context(width: 321), context(displayScale: 2),
            context(contentRevision: 2), context(environmentRevision: 2),
        ]
        for stale in staleContexts {
            XCTAssertFalse(result.updateExtent(for: rows[0], to: next, context: stale))
            XCTAssertEqual(result.totalExtent, 20)
            XCTAssertEqual(result.extent(for: rows[0]), original)
            XCTAssertEqual(result.context, measurement)
        }
        XCTAssertTrue(result.updateExtent(for: rows[0], to: next, context: measurement))
        XCTAssertEqual(result.totalExtent, 25)
    }

    func testForeignTokenCannotReadOrUpdateAnotherIndex() async throws {
        let rows = try tokens(count: 1)
        let foreign = try tokens(count: 1)[0]
        let original = try XCTUnwrap(RetainedLazyListExtent.measured([5]))
        var result = try XCTUnwrap(
            RetainedLazyListExtentIndex(tokens: rows, extents: [original], context: context()))
        XCTAssertNil(result.extent(for: foreign))
        XCTAssertFalse(result.updateExtent(for: foreign, to: original, context: result.context))
        XCTAssertEqual(result.totalExtent, 5)
    }

    func testOverflowAtRootDoesNotPublishAnyStagedLowerNodeUpdate() async throws {
        let rows = try tokens(count: 4)
        let large = Double.greatestFiniteMagnitude
        let originals = try extents([large * 0.4, 0, large * 0.4, 0])
        var result = try XCTUnwrap(
            RetainedLazyListExtentIndex(tokens: rows, extents: originals, context: context()))
        let prefixes = (0...4).compactMap { result.prefixOffset(before: $0) }
        let total = result.totalExtent
        let overflowing = try XCTUnwrap(RetainedLazyListExtent.measured([large * 0.3]))
        XCTAssertFalse(result.updateExtent(for: rows[1], to: overflowing, context: result.context))
        XCTAssertEqual(result.totalExtent, total)
        XCTAssertEqual((0...4).compactMap { result.prefixOffset(before: $0) }, prefixes)
        for position in rows.indices { XCTAssertEqual(result.extent(for: rows[position]), originals[position]) }
    }

    func testReducingAnExtentAllowsAPreviouslyOverflowingIncrease() async throws {
        let rows = try tokens(count: 2)
        let large = Double.greatestFiniteMagnitude
        var result = try XCTUnwrap(
            RetainedLazyListExtentIndex(
                tokens: rows, extents: extents([large * 0.75, large * 0.125]), context: context()))
        let increased = try XCTUnwrap(RetainedLazyListExtent.measured([large * 0.5]))
        XCTAssertFalse(result.updateExtent(for: rows[1], to: increased, context: result.context))
        XCTAssertTrue(
            result.updateExtent(
                for: rows[0], to: try XCTUnwrap(RetainedLazyListExtent.measured([])), context: result.context))
        XCTAssertTrue(result.updateExtent(for: rows[1], to: increased, context: result.context))
        XCTAssertEqual(result.totalExtent, large * 0.5)
        XCTAssertEqual(result.prefixOffset(before: 1), 0)
    }

    func testIndexValueCopyKeepsItsOriginalMeasurements() async throws {
        let rows = try tokens(count: 2)
        let original = try XCTUnwrap(
            RetainedLazyListExtentIndex(tokens: rows, extents: extents([10, 20]), context: context()))
        var changed = original
        XCTAssertTrue(
            changed.updateExtent(
                for: rows[0], to: try XCTUnwrap(RetainedLazyListExtent.measured([4])), context: changed.context))
        XCTAssertEqual(original.totalExtent, 30)
        XCTAssertEqual(original.prefixOffset(before: 1), 10)
        XCTAssertEqual(changed.totalExtent, 24)
        XCTAssertEqual(changed.prefixOffset(before: 1), 4)
    }

    func testAnchorBoundariesChooseFollowingRecordAndContentEndChoosesLast() async throws {
        let rows = try tokens(count: 5)
        let result = try XCTUnwrap(
            RetainedLazyListExtentIndex(tokens: rows, extents: extents([0, 10, 0, 20, 0]), context: context()))
        let start = try XCTUnwrap(result.captureAnchor(at: -50))
        let boundary = try XCTUnwrap(result.captureAnchor(at: 10))
        let end = try XCTUnwrap(result.captureAnchor(at: 100))
        XCTAssertEqual(start.token, rows[1])
        XCTAssertEqual(start.offsetWithinRecord, 0)
        XCTAssertEqual(boundary.token, rows[3])
        XCTAssertEqual(boundary.offsetWithinRecord, 0)
        XCTAssertEqual(end.token, rows[3])
        XCTAssertEqual(end.offsetWithinRecord, 20)
    }

    func testAnchorSurvivesReorderingAndClampsAfterRecordShrink() async throws {
        let rows = try tokens(count: 3)
        let initial = try XCTUnwrap(
            RetainedLazyListExtentIndex(tokens: rows, extents: extents([10, 20, 30]), context: context()))
        let anchor = try XCTUnwrap(initial.captureAnchor(at: 15))
        XCTAssertEqual(anchor.token, rows[1])
        XCTAssertEqual(anchor.offsetWithinRecord, 5)
        let reordered = try XCTUnwrap(
            RetainedLazyListExtentIndex(
                tokens: [rows[2], rows[0], rows[1]], extents: extents([30, 10, 3]),
                context: context(contentRevision: 2)))
        XCTAssertEqual(reordered.resolveAnchor(anchor, viewportExtent: 0), 43)
        XCTAssertEqual(reordered.resolveAnchor(anchor, viewportExtent: 10), 33)
        XCTAssertEqual(reordered.resolveAnchor(anchor, viewportExtent: 100), 0)
    }

    func testRemovedAnchorTokenHasNoInventedNeighborFallback() async throws {
        let rows = try tokens(count: 3)
        let initial = try XCTUnwrap(
            RetainedLazyListExtentIndex(tokens: rows, extents: extents([10, 20, 30]), context: context()))
        let anchor = try XCTUnwrap(initial.captureAnchor(at: 15))
        let removed = try XCTUnwrap(
            RetainedLazyListExtentIndex(
                tokens: [rows[0], rows[2]], extents: extents([10, 30]), context: context(contentRevision: 2)))
        XCTAssertNil(removed.resolveAnchor(anchor, viewportExtent: 10))
    }

    func testAnchorToExistingZeroRecordResolvesItsCurrentPrefix() async throws {
        let rows = try tokens(count: 3)
        var result = try XCTUnwrap(
            RetainedLazyListExtentIndex(tokens: rows, extents: extents([10, 20, 30]), context: context()))
        let anchor = try XCTUnwrap(result.captureAnchor(at: 15))
        XCTAssertTrue(
            result.updateExtent(
                for: rows[1], to: try XCTUnwrap(RetainedLazyListExtent.measured([])), context: result.context))
        XCTAssertEqual(result.resolveAnchor(anchor, viewportExtent: 0), 10)
        XCTAssertEqual(result.resolveAnchor(anchor, viewportExtent: 35), 5)
        for row in rows {
            XCTAssertTrue(
                result.updateExtent(
                    for: row, to: try XCTUnwrap(RetainedLazyListExtent.measured([])), context: result.context))
        }
        XCTAssertNil(result.captureAnchor(at: 0))
        XCTAssertEqual(result.resolveAnchor(anchor, viewportExtent: 0), 0)
    }

    func testAnchorQueriesRejectInvalidNumbers() async throws {
        let result = try index([10, 20])
        let anchor = try XCTUnwrap(result.captureAnchor(at: 5))
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(result.captureAnchor(at: invalid))
            XCTAssertNil(result.resolveAnchor(anchor, viewportExtent: invalid))
        }
        XCTAssertNil(result.resolveAnchor(anchor, viewportExtent: -1))
    }

    func testExtremeFiniteExtentsKeepPrefixesMonotonicAndZeroRecordsEmpty() async throws {
        let large = Double.greatestFiniteMagnitude / 4
        let heights = [large, 0, 1, 0, large, 0, 1]
        let result = try index(heights)
        let prefixes = try (0...heights.count).map { try XCTUnwrap(result.prefixOffset(before: $0)) }
        XCTAssertTrue(result.totalExtent.isFinite)
        for position in heights.indices {
            XCTAssertTrue(prefixes[position].isFinite)
            XCTAssertLessThanOrEqual(prefixes[position], prefixes[position + 1])
            if heights[position] == 0 { XCTAssertEqual(prefixes[position], prefixes[position + 1]) }
        }
        XCTAssertEqual(prefixes.last, result.totalExtent)
    }

    func testContentEndAnchorPreservesLastLogicalExtentAcrossCoordinateRoundingAndReorder() async throws {
        let large: Double = 9_007_199_254_740_992
        for heights in [[large, 1], [large, 1, 1, 1]] {
            let rows = try tokens(count: heights.count)
            let initial = try XCTUnwrap(
                RetainedLazyListExtentIndex(tokens: rows, extents: extents(heights), context: context()))
            let anchor = try XCTUnwrap(initial.captureAnchor(at: initial.totalExtent))
            let last = try XCTUnwrap(rows.last)
            XCTAssertEqual(anchor.token, last)
            XCTAssertEqual(anchor.offsetWithinRecord, 1)
            let reordered = try XCTUnwrap(
                RetainedLazyListExtentIndex(
                    tokens: [last] + Array(rows.dropLast()),
                    extents: extents([1] + Array(heights.dropLast())), context: context(contentRevision: 2)))
            XCTAssertEqual(reordered.resolveAnchor(anchor, viewportExtent: 0), 1)
        }
    }

    func testDeterministicPrefixesWindowsUpdatesAndAnchorsMatchBruteForceAcrossLargeCounts() async throws {
        for count in [100, 1_000, 10_000] {
            let rows = try tokens(count: count)
            var heights = (0..<count).map { $0.isMultiple(of: 7) ? 0 : Double(($0 * 17) % 63 + 1) }
            var result = try XCTUnwrap(
                RetainedLazyListExtentIndex(tokens: rows, extents: extents(heights), context: context()))
            var expected = prefixes(of: heights)
            for position in 0...count { XCTAssertEqual(result.prefixOffset(before: position), expected[position]) }
            var seed: UInt64 = 0x5EED_1234

            for round in 0..<64 {
                let position = next(&seed, upperBound: count)
                let height = Double(next(&seed, upperBound: 65))
                heights[position] = height
                let measured = try XCTUnwrap(
                    RetainedLazyListExtent.measured(height == 0 ? [] : [height / 2, height / 2]))
                XCTAssertTrue(result.updateExtent(for: rows[position], to: measured, context: result.context))
                expected = prefixes(of: heights)
                XCTAssertEqual(result.totalExtent, expected[count])
                for _ in 0..<9 {
                    let boundary = next(&seed, upperBound: count + 1)
                    XCTAssertEqual(result.prefixOffset(before: boundary), expected[boundary])
                }
                for _ in 0..<4 {
                    let offset = Double(next(&seed, upperBound: Int(result.totalExtent) + 201)) - 100
                    let viewport = Double(next(&seed, upperBound: 301))
                    let prefetch = Double(next(&seed, upperBound: 151))
                    XCTAssertEqual(
                        result.window(offset: offset, viewportExtent: viewport, prefetchExtent: prefetch),
                        referenceWindow(
                            heights: heights, prefixes: expected, offset: offset, viewport: viewport, prefetch: prefetch
                        ),
                        "count \(count), update \(round)")
                    let anchor = try XCTUnwrap(result.captureAnchor(at: offset))
                    let point = min(max(offset, 0), result.totalExtent)
                    let anchorIndex =
                        point == result.totalExtent
                        ? try XCTUnwrap(heights.indices.last { heights[$0] > 0 })
                        : try XCTUnwrap(heights.indices.first { heights[$0] > 0 && expected[$0 + 1] > point })
                    XCTAssertEqual(anchor.token, rows[anchorIndex])
                    XCTAssertEqual(anchor.offsetWithinRecord, point - expected[anchorIndex])
                    XCTAssertEqual(
                        result.resolveAnchor(anchor, viewportExtent: viewport),
                        min(point, max(0, result.totalExtent - viewport)))
                }
            }
        }
    }

    private func prefixes(of heights: [Double]) -> [Double] {
        var result: [Double] = [0]
        var total: Double = 0
        for height in heights {
            total += height
            result.append(total)
        }
        return result
    }

    private func referenceWindow(
        heights: [Double], prefixes: [Double], offset: Double, viewport: Double, prefetch: Double
    ) -> Range<Int> {
        let total = prefixes[heights.count]
        guard total > 0 else { return 0..<0 }
        let lower = offset - prefetch
        let upper = offset + viewport + prefetch
        if upper <= 0 { return 0..<0 }
        if lower >= total { return heights.count..<heights.count }
        let start = max(0, lower)
        let end = min(total, upper)
        let first = heights.indices.first { heights[$0] > 0 && prefixes[$0 + 1] > start } ?? heights.count
        guard start < end else { return first..<first }
        let last = heights.indices.last { heights[$0] > 0 && prefixes[$0] < end }
        return first..<((last ?? first - 1) + 1)
    }

    private func next(_ state: inout UInt64, upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int(state % UInt64(upperBound))
    }
}
