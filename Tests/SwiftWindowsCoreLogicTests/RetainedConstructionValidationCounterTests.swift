import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedConstructionValidationCounterTests: XCTestCase {
    func testAdmissionForestAndRejectedVisitTotalsRemainDistinct() async {
        let counters = RetainedConstructionValidationCounters()
        counters.recordAdmissionCheck(count: 4)
        counters.recordForestStart()
        counters.recordCompletionValidation()
        counters.recordCompletionValidation()
        counters.recordForestResult(nodeVisits: 5, isCurrent: true)
        counters.recordForestStart()
        counters.recordCompletionValidation()
        counters.recordForestResult(nodeVisits: 2, isCurrent: false)
        let snapshot = counters.snapshot
        XCTAssertEqual(snapshot.admissionBuildChecks, 4)
        XCTAssertEqual(snapshot.forestValidations, 2)
        XCTAssertEqual(snapshot.completionValidations, 3)
        XCTAssertEqual(snapshot.forestNodeVisits, 7)
        XCTAssertEqual(snapshot.forestFailures, 1)
        XCTAssertEqual(snapshot.maximumForestNodeVisits, 5)
        XCTAssertFalse(snapshot.overflowed)
    }

    func testModalRequestsScansAndActualVisitedNodesRemainDistinct() async {
        let counters = RetainedConstructionValidationCounters()
        counters.recordModalRequest()
        counters.recordModalRequest()
        counters.recordModalScan()
        counters.recordModalResult(nodeVisits: 5)
        counters.recordModalRequest()
        counters.recordModalScan()
        counters.recordModalResult(nodeVisits: 2)
        XCTAssertEqual(counters.snapshot.modalSnapshotRequests, 3)
        XCTAssertEqual(counters.snapshot.modalScans, 2)
        XCTAssertEqual(counters.snapshot.modalDispatchNodeVisits, 7)
        XCTAssertEqual(counters.snapshot.maximumModalNodeVisits, 5)
        XCTAssertFalse(counters.snapshot.overflowed)
    }

    func testOverflowSaturatesAndMarksTheBoundaryRecordPartial() async throws {
        let fixture = try ValidationCounterTraceFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let counters = RetainedConstructionValidationCounters()
        counters.recordAdmissionCheck(count: UInt64.max)
        counters.recordAdmissionCheck()
        counters.recordAdmissionCheck()
        XCTAssertEqual(counters.snapshot.admissionBuildChecks, UInt64.max)
        XCTAssertTrue(counters.snapshot.overflowed)
        let phase = RetainedConstructionPhaseTrace(
            trace: try XCTUnwrap(writer.runtimeTrace(nativeID: 17)), counters: counters)
        XCTAssertNotNil(phase.record("overflow.returnBoundary"))
        let record = try XCTUnwrap(try fixture.records().last)
        XCTAssertEqual(record["coverage"] as? String, "PARTIAL")
        let values = try XCTUnwrap(record["validationCounts"] as? [String: Any])
        XCTAssertEqual((values["admissionBuildChecks"] as? NSNumber)?.uint64Value, UInt64.max)
        XCTAssertEqual(values["overflowed"] as? Bool, true)
    }

    func testPhaseCapWritesOnePartialRecordAndStopsOnlyTracing() async throws {
        let fixture = try ValidationCounterTraceFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let counters = RetainedConstructionValidationCounters(phaseRecordLimit: 2)
        let phase = RetainedConstructionPhaseTrace(
            trace: try XCTUnwrap(writer.runtimeTrace(nativeID: 17)), counters: counters)
        let span = try XCTUnwrap(phase.record("operation.enter"))
        counters.recordAdmissionCheck()
        XCTAssertNotNil(phase.record("operation.returnBoundary", span: span))
        XCTAssertNotNil(phase.record("after.cap"))
        let records = try fixture.records()
        XCTAssertEqual(
            records.compactMap { $0["event"] as? String },
            [
                "trace.open", "runtime.birth", "operation.enter", "operation.returnBoundary", "validation.capReached",
                "after.cap",
            ])
        XCTAssertEqual(records[4]["coverage"] as? String, "PARTIAL")
        XCTAssertNil(records.last?["validationCounts"])
        let bytes = writer.bytesWritten
        counters.recordAdmissionCheck()
        XCTAssertNotNil(phase.record("original.after.cap"))
        XCTAssertGreaterThan(writer.bytesWritten, bytes)
        XCTAssertEqual(counters.snapshot.admissionBuildChecks, 2)
        XCTAssertEqual(writer.status, .active)
    }

    func testPhaseRecordsPreserveSpanBirthAndMonotonicTime() async throws {
        let fixture = try ValidationCounterTraceFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let counters = RetainedConstructionValidationCounters()
        let phase = RetainedConstructionPhaseTrace(
            trace: try XCTUnwrap(writer.runtimeTrace(nativeID: 29)), counters: counters)
        let before = PlatformClock.now()
        let span = try XCTUnwrap(phase.record("operation.enter"))
        counters.recordAdmissionCheck()
        XCTAssertNotNil(phase.record("operation.returnBoundary", span: span))
        let after = PlatformClock.now()
        let records = try fixture.records()
        let start = records[2]
        let end = records[3]
        XCTAssertEqual((end["span"] as? NSNumber)?.uint64Value, span)
        XCTAssertEqual((start["birth"] as? NSNumber)?.uint64Value, (end["birth"] as? NSNumber)?.uint64Value)
        XCTAssertEqual((end["runtime"] as? NSNumber)?.uintValue, 29)
        let started = try XCTUnwrap((start["monotonicSeconds"] as? NSNumber)?.doubleValue)
        let ended = try XCTUnwrap((end["monotonicSeconds"] as? NSNumber)?.doubleValue)
        XCTAssertGreaterThanOrEqual(started, before)
        XCTAssertGreaterThanOrEqual(ended, started)
        XCTAssertLessThanOrEqual(ended, after)
        let values = try XCTUnwrap(end["validationCounts"] as? [String: Any])
        XCTAssertEqual((values["admissionBuildChecks"] as? NSNumber)?.uint64Value, 1)
        XCTAssertEqual(end["coverage"] as? String, "OBSERVED")
    }

    func testNonfiniteTimestampRejectsTheDiagnosticRecord() async throws {
        let fixture = try ValidationCounterTraceFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let trace = try XCTUnwrap(writer.runtimeTrace(nativeID: 17))
        XCTAssertNil(
            trace.recordValidationPhase(
                "invalid.timestamp", monotonicSeconds: .nan,
                snapshot: RetainedConstructionValidationCounters.Snapshot(), partial: false))
        XCTAssertEqual(writer.status, .recordRejected)
        XCTAssertEqual(try fixture.records().last?["event"] as? String, "trace.recordRejected")
    }

    func testCounterFlagRequiresExactlyOneAndAConfiguredTrace() async throws {
        XCTAssertNil(RetainedConstructionDiagnostics.validationCounters(for: nil, flag: "1"))
        let fixture = try ValidationCounterTraceFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let trace = try XCTUnwrap(writer.runtimeTrace(nativeID: 17))
        let flags: [String?] = [nil, "", "0", "true", "01", " 1", "1 ", "2"]
        for flag in flags {
            XCTAssertNil(RetainedConstructionDiagnostics.validationCounters(for: trace, flag: flag))
        }
        XCTAssertNotNil(RetainedConstructionDiagnostics.validationCounters(for: trace, flag: "1"))
    }

    func testFile14OnlyPreservesTheOriginalSchemaBytesAndSpans() async throws {
        let expected = try ValidationCounterTraceFixture()
        defer { expected.remove() }
        let observed = try ValidationCounterTraceFixture()
        defer { observed.remove() }
        let expectedWriter = try RetainedConstructionTraceWriter(path: expected.file.path)
        defer { expectedWriter.close() }
        let observedWriter = try RetainedConstructionTraceWriter(path: observed.file.path)
        defer { observedWriter.close() }
        let original = try XCTUnwrap(expectedWriter.runtimeTrace(nativeID: 17))
        let trace = try XCTUnwrap(observedWriter.runtimeTrace(nativeID: 17))
        let counters = RetainedConstructionDiagnostics.validationCounters(for: trace, flag: nil)
        XCTAssertNil(counters)
        let phase = RetainedConstructionPhaseTrace(trace: trace, counters: counters)
        let originalSpan = try XCTUnwrap(original.record("layout.enter"))
        let observedSpan = try XCTUnwrap(phase.record("layout.enter"))
        XCTAssertEqual(observedSpan, originalSpan)
        XCTAssertEqual(
            original.record("layout.returnBoundary", span: originalSpan),
            phase.record("layout.returnBoundary", span: observedSpan))
        XCTAssertEqual(try Data(contentsOf: observed.file), try Data(contentsOf: expected.file))
    }

    func testOriginalEventAndSpanPublicationContinuesAfterTheCounterCap() async throws {
        let fixture = try ValidationCounterTraceFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let counters = RetainedConstructionValidationCounters(phaseRecordLimit: 1)
        let phase = RetainedConstructionPhaseTrace(
            trace: try XCTUnwrap(writer.runtimeTrace(nativeID: 17)), counters: counters)
        let beforeCap = try XCTUnwrap(phase.record("layout.enter"))
        let returnAfterCap = try XCTUnwrap(phase.record("layout.returnBoundary", span: beforeCap))
        let afterCap = try XCTUnwrap(phase.record("scene.enter"))
        XCTAssertNotNil(phase.record("scene.returnBoundary", span: afterCap))
        let records = try fixture.records()
        XCTAssertEqual(
            records.compactMap { $0["event"] as? String },
            [
                "trace.open", "runtime.birth", "layout.enter", "validation.capReached", "layout.returnBoundary",
                "scene.enter", "scene.returnBoundary",
            ])
        XCTAssertEqual((records[4]["sequence"] as? NSNumber)?.uint64Value, returnAfterCap)
        XCTAssertEqual((records[4]["span"] as? NSNumber)?.uint64Value, beforeCap)
        XCTAssertEqual((records[6]["span"] as? NSNumber)?.uint64Value, afterCap)
        XCTAssertEqual(Set(records[4].keys), Set(["version", "sequence", "event", "span", "runtime", "birth"]))
        XCTAssertEqual(records.filter { $0["event"] as? String == "validation.capReached" }.count, 1)
        XCTAssertEqual(records[3]["coverage"] as? String, "PARTIAL")
    }
}

private struct ValidationCounterTraceFixture {
    let directory: URL
    let file: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "validation-counts-\(UUID().uuidString)")
        file = directory.appendingPathComponent("trace.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data().write(to: file, options: .withoutOverwriting)
    }

    func records() throws -> [[String: Any]] {
        let data = try Data(contentsOf: file)
        XCTAssertEqual(data.last, 0x0A)
        return try data.split(separator: 0x0A).map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        }
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
