import Foundation
@preconcurrency import XCTest

@testable import SwiftWindowsDemo
@testable import WinSwiftUI

@MainActor
final class DemoDashboardDataModelTests: XCTestCase {
    func testConstructionKeepsAnExplicitPreviewAndStartsNoRead() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        let model = harness.model
        XCTAssertEqual(model.snapshot.phase, .preview)
        XCTAssertEqual(model.snapshot.content, .preview)
        XCTAssertEqual(model.snapshot.selectedSample, .valid)
        XCTAssertNil(model.snapshot.requestID)
        XCTAssertNil(model.snapshot.requestSample)
        XCTAssertNil(model.snapshot.error)
        XCTAssertNil(model.activeReadTask)
        XCTAssertFalse(model.isReading)
        XCTAssertFalse(model.canCancel)
        XCTAssertFalse(model.canRetry)
        XCTAssertFalse(model.isClosed)
        XCTAssertEqual(model.pendingRequestCount, 0)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        let reading = await harness.service.isReading
        XCTAssertFalse(reading)
        XCTAssertEqual(DemoDashboardDataService.maximumEncodedBytes, 16_384)
        XCTAssertEqual(DemoDashboardDataService.maximumPointsPerRange, 12)
        XCTAssertEqual(DemoDashboardDataService.maximumLabelBytes, 24)
        XCTAssertEqual(DemoDashboardDataService.maximumActiveReads, 1)
    }

    func testBuiltInBytesDecodeRealValidEmptyAndMalformedInputs() async throws {
        let report = try DemoDashboardDataService.decode(DemoDashboardDataService.encodedSample(.valid))
        XCTAssertEqual(report.pointCount, 29)
        XCTAssertEqual(report.day.map(\.label), (1...10).map(String.init))
        XCTAssertEqual(report.day.map(\.fraction), [0.35, 0.52, 0.40, 0.68, 0.56, 0.82, 0.64, 0.94, 0.72, 0.58])
        XCTAssertEqual(report.week.map(\.label), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(report.week.map(\.fraction), [0.41, 0.56, 0.49, 0.73, 0.64, 0.88, 0.70])
        XCTAssertEqual(
            report.all.map(\.label),
            ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
        XCTAssertEqual(
            report.all.map(\.fraction), [0.28, 0.34, 0.39, 0.44, 0.50, 0.47, 0.58, 0.63, 0.69, 0.74, 0.81, 0.92])
        let empty = try DemoDashboardDataService.decode(DemoDashboardDataService.encodedSample(.empty))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual([empty.day.count, empty.week.count, empty.all.count], [0, 0, 0])
        assertDecodeError(DemoDashboardDataService.encodedSample(.malformed), .malformedJSON)
        XCTAssertEqual(
            DemoDashboardDataService.encodedSample(.valid), DemoDashboardDataService.encodedSample(.valid),
            "Encoded sample content is deterministic, not a timer or random result generator")
    }

    func testDefaultRefreshPublishesTheActualAsynchronouslyDecodedReport() async throws {
        let model = DemoDashboardDataModel()
        defer { model.close() }
        XCTAssertTrue(model.refresh())
        let requestID = try XCTUnwrap(model.snapshot.requestID)
        XCTAssertEqual(model.snapshot.phase, .loading)
        XCTAssertTrue(model.isReading)
        XCTAssertTrue(model.canCancel)
        XCTAssertFalse(model.canRetry)
        try await dashboardDataAwait(XCTUnwrap(model.activeReadTask))
        let decoded = try DemoDashboardDataService.decode(DemoDashboardDataService.encodedSample(.valid))
        XCTAssertEqual(model.snapshot.content, .report(decoded))
        XCTAssertEqual(model.snapshot.phase, .ready)
        XCTAssertEqual(model.snapshot.requestID, requestID)
        XCTAssertEqual(model.snapshot.requestSample, .valid)
        XCTAssertFalse(model.isReading)
        XCTAssertFalse(model.canCancel)
        XCTAssertNil(model.snapshot.error)
    }

    func testDecoderEnforcesTheEncodedByteBoundaryBeforeParsing() async throws {
        var bytes = DemoDashboardDataService.encodedSample(.empty)
        bytes.append(Data(repeating: 32, count: DemoDashboardDataService.maximumEncodedBytes - bytes.count))
        XCTAssertEqual(bytes.count, 16_384)
        XCTAssertTrue(try DemoDashboardDataService.decode(bytes).isEmpty)
        bytes.append(32)
        assertDecodeError(bytes, .encodedDataTooLarge)
        assertDecodeError(Data(repeating: 0, count: 16_385), .encodedDataTooLarge)
        assertDecodeError(Data(), .malformedJSON)
    }

    func testDecoderAcceptsTwelvePointsPerRangeButRejectsAThirteenth() async throws {
        let points = (0..<12).map { ["label": "P\($0)", "fraction": 0.5] as [String: Any] }
        let report = try DemoDashboardDataService.decode(dashboardDataJSON(day: points, week: points, all: points))
        XCTAssertEqual([report.day.count, report.week.count, report.all.count], [12, 12, 12])
        XCTAssertEqual(report.pointCount, 36)
        let excess = points + [["label": "excess", "fraction": 0.5]]
        assertDecodeError(try dashboardDataJSON(day: excess), .tooManyPoints)
        assertDecodeError(try dashboardDataJSON(week: excess), .tooManyPoints)
        assertDecodeError(try dashboardDataJSON(all: excess), .tooManyPoints)
        let partial = try DemoDashboardDataService.decode(
            dashboardDataJSON(week: [["label": "Only", "fraction": 1.0]]))
        XCTAssertFalse(partial.isEmpty)
        XCTAssertTrue(partial.day.isEmpty)
        XCTAssertTrue(partial.all.isEmpty)
        XCTAssertEqual(partial.week.map(\.label), ["Only"])
    }

    func testDecoderRejectsUnsupportedVersionMissingFieldsAndWrongTypes() async throws {
        assertDecodeError(try dashboardDataJSON(version: 2), .unsupportedVersion)
        for json in [
            #"{"version":1,"day":[],"week":[]}"#,
            #"{"version":1,"day":[{"label":"A","fraction":"0.5"}],"week":[],"all":[]}"#,
            #"{"version":1,"day":[{"fraction":0.5}],"week":[],"all":[]}"#,
            #"{"version":1,"day":null,"week":[],"all":[]}"#,
            #"[]"#,
        ] {
            assertDecodeError(Data(json.utf8), .malformedJSON)
        }
        assertDecodeError(Data([255, 254, 255]), .malformedJSON)
    }

    func testDecoderRejectsNonFiniteOrOutOfRangeFractionsWithoutClamping() async throws {
        for fraction in [-0.001, 1.001] {
            assertDecodeError(try dashboardDataJSON(day: [["label": "A", "fraction": fraction]]), .invalidFraction)
        }
        let boundaries = try DemoDashboardDataService.decode(
            dashboardDataJSON(day: [["label": "Zero", "fraction": 0.0], ["label": "One", "fraction": 1.0]]))
        XCTAssertEqual(boundaries.day.map(\.fraction), [0, 1])
        XCTAssertEqual(DemoChartCard.bars(report: boundaries, interactions: 0, range: .day).map(\.value), [0, 40])
        XCTAssertTrue(DemoChartCard.bars(report: boundaries, interactions: 0, range: .week).isEmpty)
        assertDecodeError(
            Data(#"{"version":1,"day":[{"label":"A","fraction":NaN}],"week":[],"all":[]}"#.utf8), .malformedJSON)
        // Foundation may reject overflow during JSON conversion; otherwise the
        // report's finite-number validation must reject it. Neither may clamp.
        XCTAssertThrowsError(
            try DemoDashboardDataService.decode(
                Data(#"{"version":1,"day":[{"label":"A","fraction":1e9999}],"week":[],"all":[]}"#.utf8)))
    }

    func testDecoderBoundsUTF8LabelsAndRejectsControlOrLineBreakText() async throws {
        for label in [String(repeating: "a", count: 24), String(repeating: "\u{1F600}", count: 6)] {
            let report = try DemoDashboardDataService.decode(
                dashboardDataJSON(day: [["label": label, "fraction": 0.5]]))
            XCTAssertEqual(report.day.first?.label, label)
            XCTAssertEqual(label.utf8.count, 24)
        }
        for label in [
            "", "   ", "\t", "A\nB", "A\rB", "A\u{0000}B", "A\u{2028}B", "A\u{2029}B",
            String(repeating: "a", count: 25), String(repeating: "\u{1F600}", count: 7),
        ] {
            assertDecodeError(try dashboardDataJSON(day: [["label": label, "fraction": 0.5]]), .invalidLabel)
        }
    }

    func testDecoderRequiresUniqueLabelsWithinEachRangeOnly() async throws {
        let point: [String: Any] = ["label": "A", "fraction": 0.5]
        assertDecodeError(try dashboardDataJSON(day: [point, point]), .duplicateLabel)
        let report = try DemoDashboardDataService.decode(dashboardDataJSON(day: [point], week: [point], all: [point]))
        XCTAssertEqual(report.pointCount, 3)
        XCTAssertEqual([report.day[0].label, report.week[0].label, report.all[0].label], ["A", "A", "A"])
        assertDecodeError(
            try dashboardDataJSON(day: [
                ["label": "\u{00E9}", "fraction": 0.5], ["label": "e\u{0301}", "fraction": 0.6],
            ]), .duplicateLabel)
    }

    func testReaderFailureIsVisibleAndRetryPerformsAnotherRealRead() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        let firstID = try XCTUnwrap(harness.model.snapshot.requestID)
        try await harness.starts(1)
        try await harness.finish(0, result: .failure(NSError(domain: "private-local-store", code: 19)))
        XCTAssertEqual(harness.model.snapshot.phase, .failed)
        XCTAssertEqual(harness.model.snapshot.error, .readFailed)
        XCTAssertEqual(harness.model.snapshot.content, .preview)
        XCTAssertTrue(harness.model.canRetry)
        XCTAssertTrue(harness.model.retry())
        XCTAssertNotEqual(harness.model.snapshot.requestID, firstID)
        try await harness.starts(2)
        XCTAssertEqual(harness.gate.snapshot.starts.map(\.sample), [.valid, .valid])
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.valid))
        XCTAssertEqual(harness.model.snapshot.phase, .ready)
        XCTAssertEqual(try harness.report().pointCount, 29)
        XCTAssertNil(harness.model.snapshot.error)
        XCTAssertFalse(harness.model.canRetry)
    }

    func testMalformedPayloadFailsAndRetryDecodesNewlyReturnedBytes() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.select(.malformed))
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.malformed))
        XCTAssertEqual(harness.model.snapshot.phase, .failed)
        XCTAssertEqual(harness.model.snapshot.error, .malformedJSON)
        let firstID = harness.model.snapshot.requestID
        XCTAssertTrue(harness.model.retry())
        try await harness.starts(2)
        XCTAssertEqual(harness.gate.snapshot.starts.map(\.sample), [.malformed, .malformed])
        let repaired = try dashboardDataJSON(day: [["label": "Repaired", "fraction": 0.625]])
        try await harness.finish(1, bytes: repaired)
        XCTAssertEqual(harness.model.snapshot.phase, .ready)
        XCTAssertNotEqual(harness.model.snapshot.requestID, firstID)
        XCTAssertEqual(try harness.report().day.map(\.label), ["Repaired"])
        XCTAssertEqual(try harness.report().day.map(\.fraction), [0.625])
        XCTAssertEqual(harness.model.snapshot.requestSample, .malformed)
    }

    func testEmptySuccessReplacesThePreviousReportWithoutPreviewFallback() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        let previous = harness.model.snapshot.content
        XCTAssertTrue(harness.model.select(.empty))
        XCTAssertTrue(harness.model.refresh())
        XCTAssertEqual(harness.model.snapshot.content, previous, "Loading preserves the last successful content")
        try await harness.starts(2)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.empty))
        XCTAssertEqual(harness.model.snapshot.phase, .empty)
        XCTAssertTrue(try harness.report().isEmpty)
        XCTAssertNotEqual(harness.model.snapshot.content, previous)
        XCTAssertNotEqual(harness.model.snapshot.content, .preview)
        XCTAssertFalse(harness.model.canRetry)
        XCTAssertNil(harness.model.snapshot.error)
    }

    func testSelectionAloneDoesNotStartOrRelabelAnExistingRequest() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        let id = harness.model.snapshot.requestID
        XCTAssertTrue(harness.model.select(.empty))
        XCTAssertFalse(harness.model.select(.empty))
        XCTAssertEqual(harness.model.snapshot.requestID, id)
        XCTAssertEqual(harness.model.snapshot.requestSample, .valid)
        XCTAssertEqual(harness.model.snapshot.selectedSample, .empty)
        XCTAssertEqual(harness.model.pendingRequestCount, 0)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        XCTAssertEqual(harness.model.snapshot.phase, .ready)
        XCTAssertEqual(harness.model.snapshot.requestSample, .valid)
        XCTAssertEqual(harness.model.snapshot.selectedSample, .empty)
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(2)
        XCTAssertEqual(harness.gate.snapshot.starts[1].sample, .empty)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.empty))
        XCTAssertEqual(harness.model.snapshot.phase, .empty)
    }

    func testRefreshCoalescesOnlyTheLatestIntentBehindOnePhysicalRead() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        var identifiers: Set<UUID> = [try XCTUnwrap(harness.model.snapshot.requestID)]
        for index in 0..<40 {
            _ = harness.model.select(index.isMultiple(of: 2) ? .malformed : .empty)
            XCTAssertTrue(harness.model.refresh())
            XCTAssertTrue(identifiers.insert(try XCTUnwrap(harness.model.snapshot.requestID)).inserted)
            XCTAssertEqual(harness.model.pendingRequestCount, 1)
            XCTAssertTrue(harness.model.isWaitingForPreviousRead)
            XCTAssertEqual(harness.gate.snapshot.starts.count, 1)
            XCTAssertEqual(harness.gate.snapshot.active, [0])
        }
        let newest = harness.model.snapshot.requestID
        XCTAssertEqual(identifiers.count, 41)
        try await harness.cancelled(0)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        try await harness.starts(2)
        XCTAssertEqual(harness.model.snapshot.phase, .loading)
        XCTAssertEqual(harness.model.snapshot.content, .preview, "The superseded success cannot publish")
        XCTAssertEqual(harness.model.snapshot.requestID, newest)
        XCTAssertEqual(harness.gate.snapshot.starts.map(\.sample), [.valid, .empty])
        XCTAssertEqual(harness.model.pendingRequestCount, 0)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.empty))
        XCTAssertEqual(harness.model.snapshot.phase, .empty)
        XCTAssertEqual(harness.model.snapshot.requestID, newest)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 1)
        XCTAssertTrue(harness.gate.snapshot.active.isEmpty)
    }

    func testCancelRetainsItsPhysicalSlotAndRejectsLateSuccessfulBytes() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        let id = harness.model.snapshot.requestID
        XCTAssertTrue(harness.model.cancel())
        XCTAssertFalse(harness.model.cancel())
        XCTAssertEqual(harness.model.snapshot.phase, .cancelled)
        XCTAssertTrue(harness.model.canRetry)
        XCTAssertTrue(harness.model.isReading)
        XCTAssertFalse(harness.model.canCancel)
        XCTAssertEqual(harness.model.pendingRequestCount, 0)
        try await harness.cancelled(0)
        let reading = await harness.service.isReading
        XCTAssertTrue(reading)
        XCTAssertEqual(harness.gate.snapshot.active, [0])
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        XCTAssertEqual(harness.model.snapshot.phase, .cancelled)
        XCTAssertEqual(harness.model.snapshot.requestID, id)
        XCTAssertEqual(harness.model.snapshot.content, .preview)
        XCTAssertFalse(harness.model.isReading)
        let drained = await harness.service.isReading
        XCTAssertFalse(drained)
    }

    func testCancellationBeforeTaskEntryDoesNotCallTheReader() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        let task = try XCTUnwrap(harness.model.activeReadTask)
        XCTAssertTrue(harness.model.cancel())
        try await dashboardDataAwait(task)
        XCTAssertEqual(harness.model.snapshot.phase, .cancelled)
        XCTAssertEqual(harness.model.snapshot.content, .preview)
        XCTAssertNil(harness.model.activeReadTask)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        let reading = await harness.service.isReading
        XCTAssertFalse(reading)
    }

    func testCancelDropsTheQueuedReplacementWithoutStartingIt() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        XCTAssertTrue(harness.model.select(.empty))
        XCTAssertTrue(harness.model.refresh())
        let queuedID = harness.model.snapshot.requestID
        XCTAssertEqual(harness.model.pendingRequestCount, 1)
        XCTAssertTrue(harness.model.cancel())
        XCTAssertEqual(harness.model.pendingRequestCount, 0)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        XCTAssertEqual(harness.model.snapshot.phase, .cancelled)
        XCTAssertEqual(harness.model.snapshot.requestID, queuedID)
        XCTAssertEqual(harness.model.snapshot.requestSample, .empty)
        XCTAssertNil(harness.model.activeReadTask)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1)
        XCTAssertTrue(harness.model.retry())
        try await harness.starts(2)
        XCTAssertEqual(harness.gate.snapshot.starts[1].sample, .empty)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.empty))
        XCTAssertEqual(harness.model.snapshot.phase, .empty)
    }

    func testRetryUsesTheFailedInputWhileRefreshUsesTheNewSelection() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertFalse(harness.model.retry())
        XCTAssertTrue(harness.model.select(.malformed))
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.malformed))
        XCTAssertTrue(harness.model.select(.valid))
        XCTAssertTrue(harness.model.retry())
        XCTAssertFalse(harness.model.retry())
        try await harness.starts(2)
        XCTAssertEqual(harness.model.snapshot.selectedSample, .valid)
        XCTAssertEqual(harness.model.snapshot.requestSample, .malformed)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.malformed))
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(3)
        XCTAssertEqual(harness.gate.snapshot.starts.map(\.sample), [.malformed, .malformed, .valid])
        try await harness.finish(2, bytes: DemoDashboardDataService.encodedSample(.valid))
        XCTAssertEqual(harness.model.snapshot.phase, .ready)
        XCTAssertEqual(harness.model.snapshot.requestSample, .valid)
    }

    func testReaderCancellationIsCancelledRatherThanAFabricatedFailure() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        try await harness.finish(0, result: .failure(CancellationError()))
        XCTAssertEqual(harness.model.snapshot.phase, .cancelled)
        XCTAssertEqual(harness.model.snapshot.content, .preview)
        XCTAssertNil(harness.model.snapshot.error)
        XCTAssertTrue(harness.model.canRetry)
        XCTAssertFalse(harness.model.isReading)
    }

    func testCloseReleasesTheReportAndRevokesQueuedAndPhysicalWork() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(2)
        XCTAssertTrue(harness.model.select(.empty))
        XCTAssertTrue(harness.model.refresh())
        XCTAssertEqual(harness.model.pendingRequestCount, 1)
        harness.model.close()
        harness.model.close()
        XCTAssertEqual(harness.model.snapshot.phase, .closed)
        XCTAssertEqual(harness.model.snapshot.content, .released)
        XCTAssertNil(harness.model.snapshot.requestID)
        XCTAssertNil(harness.model.snapshot.requestSample)
        XCTAssertEqual(harness.model.pendingRequestCount, 0)
        XCTAssertTrue(harness.model.isClosed)
        XCTAssertTrue(harness.model.isReading)
        XCTAssertFalse(harness.model.refresh())
        XCTAssertFalse(harness.model.retry())
        XCTAssertFalse(harness.model.cancel())
        XCTAssertFalse(harness.model.select(.valid))
        try await harness.cancelled(1)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.valid))
        XCTAssertEqual(harness.model.snapshot.phase, .closed)
        XCTAssertEqual(harness.model.snapshot.content, .released)
        XCTAssertNil(harness.model.activeReadTask)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
    }

    func testAnAwaitedReaderDoesNotKeepItsModelAlive() async throws {
        let gate = DemoDashboardDataGate()
        defer { gate.close() }
        let service = DemoDashboardDataService { try await gate.read($0) }
        var model: DemoDashboardDataModel? = DemoDashboardDataModel(service: service)
        weak var weakModel = model
        XCTAssertTrue(try XCTUnwrap(model).refresh())
        let task = try XCTUnwrap(model?.activeReadTask)
        let started = await gate.waitForStarts(1)
        XCTAssertTrue(started)
        guard started else { throw DemoDashboardDataTestError.missingRead }
        model = nil
        XCTAssertNil(weakModel, "The task must not hold a strong model across the reader suspension")
        let cancelled = await gate.waitForCancellation(0)
        XCTAssertTrue(cancelled)
        XCTAssertEqual(gate.snapshot.active, [0])
        XCTAssertTrue(gate.finish(0, result: .success(DemoDashboardDataService.encodedSample(.valid))))
        try await dashboardDataAwait(task)
        XCTAssertTrue(gate.snapshot.active.isEmpty)
        let reading = await service.isReading
        XCTAssertFalse(reading)
    }

    func testSharedServiceRejectsOverlappingReadsEvenFromDifferentModels() async throws {
        let gate = DemoDashboardDataGate()
        let service = DemoDashboardDataService { try await gate.read($0) }
        let first = DemoDashboardDataModel(service: service)
        let second = DemoDashboardDataModel(service: service)
        defer {
            first.close()
            second.close()
            gate.close()
        }
        XCTAssertTrue(first.refresh())
        let started = await gate.waitForStarts(1)
        XCTAssertTrue(started)
        guard started else { throw DemoDashboardDataTestError.missingRead }
        let firstTask = try XCTUnwrap(first.activeReadTask)
        XCTAssertTrue(second.refresh())
        try await dashboardDataAwait(XCTUnwrap(second.activeReadTask))
        XCTAssertEqual(second.snapshot.phase, .failed)
        XCTAssertEqual(second.snapshot.error, .busy)
        XCTAssertTrue(first.cancel())
        XCTAssertTrue(second.retry())
        try await dashboardDataAwait(XCTUnwrap(second.activeReadTask))
        XCTAssertEqual(second.snapshot.error, .busy, "Cancellation does not free the occupied physical slot")
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertTrue(gate.finish(0, result: .success(DemoDashboardDataService.encodedSample(.valid))))
        try await dashboardDataAwait(firstTask)
        XCTAssertTrue(second.retry())
        let secondStarted = await gate.waitForStarts(2)
        XCTAssertTrue(secondStarted)
        guard secondStarted else { throw DemoDashboardDataTestError.missingRead }
        let secondTask = try XCTUnwrap(second.activeReadTask)
        XCTAssertTrue(gate.finish(1, result: .success(DemoDashboardDataService.encodedSample(.empty))))
        try await dashboardDataAwait(secondTask)
        XCTAssertEqual(second.snapshot.phase, .empty)
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
        XCTAssertEqual(gate.snapshot.starts.count, 2)
    }

    func testLoadingObserverCanSupersedeIntentBeforeTheOldReaderEnters() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        let model = harness.model
        var replaced = false
        var originalID: UUID?
        let subscription = model.objectWillChange.sink { _ in
            guard !replaced, model.snapshot.phase == .loading else { return }
            replaced = true
            originalID = model.snapshot.requestID
            XCTAssertTrue(model.select(.empty))
            XCTAssertTrue(model.refresh())
        }
        defer { subscription.cancel() }
        XCTAssertTrue(model.refresh())
        XCTAssertTrue(replaced)
        XCTAssertNotEqual(model.snapshot.requestID, originalID)
        try await harness.starts(1)
        XCTAssertEqual(harness.gate.snapshot.starts.map(\.sample), [.empty])
        XCTAssertFalse(harness.gate.snapshot.starts[0].wasCancelledAtEntry)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.empty))
        XCTAssertEqual(model.snapshot.phase, .empty)
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 1)
    }

    func testCompletionObserverCanRefreshWithoutAnOlderFinisherOverwritingIt() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        let model = harness.model
        var replaced = false
        var replacementID: UUID?
        let subscription = model.objectWillChange.sink { _ in
            guard !replaced, model.snapshot.phase == .ready else { return }
            replaced = true
            XCTAssertTrue(model.select(.empty))
            XCTAssertTrue(model.refresh())
            replacementID = model.snapshot.requestID
        }
        defer { subscription.cancel() }
        XCTAssertTrue(model.refresh())
        try await harness.starts(1)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        try await harness.starts(2)
        XCTAssertTrue(replaced)
        XCTAssertEqual(model.snapshot.phase, .loading)
        XCTAssertEqual(model.snapshot.requestID, replacementID)
        XCTAssertEqual(model.snapshot.requestSample, .empty)
        XCTAssertEqual(try harness.report().pointCount, 29)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.empty))
        XCTAssertEqual(model.snapshot.phase, .empty)
        XCTAssertEqual(model.snapshot.requestID, replacementID)
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 1)
    }

    func testDecodeFailurePreservesTheLastSuccessfulReportAndItsValues() async throws {
        let harness = DemoDashboardDataHarness()
        defer { harness.close() }
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(1)
        let payload = try dashboardDataJSON(day: [["label": "Saved", "fraction": 0.375]])
        try await harness.finish(0, bytes: payload)
        let previous = harness.model.snapshot.content
        XCTAssertTrue(harness.model.select(.malformed))
        XCTAssertTrue(harness.model.refresh())
        try await harness.starts(2)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.malformed))
        XCTAssertEqual(harness.model.snapshot.phase, .failed)
        XCTAssertEqual(harness.model.snapshot.error, .malformedJSON)
        XCTAssertEqual(harness.model.snapshot.content, previous)
        XCTAssertEqual(try harness.report().day.map(\.label), ["Saved"])
        XCTAssertEqual(try harness.report().day.map(\.fraction), [0.375])
    }

    private func assertDecodeError(
        _ bytes: Data, _ error: DemoDashboardDataError, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try DemoDashboardDataService.decode(bytes), file: file, line: line) {
            XCTAssertEqual($0 as? DemoDashboardDataError, error, file: file, line: line)
        }
    }
}
