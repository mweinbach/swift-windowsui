import Foundation
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsGraphics

private typealias DisplayFacts = NativeDisplayMeasurement

private func displayFactUUID(_ value: UInt8) -> UUID {
    UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}

private func displayFactID(_ ordinal: UInt64, source: UInt32 = 1, part: UInt32 = 0) -> DisplayFacts.FactID {
    DisplayFacts.FactID(source: source, ordinal: ordinal, part: part)
}

private func displayFactStamp(_ ticks: UInt64, clock: UInt32 = 1) -> DisplayFacts.Stamp {
    DisplayFacts.Stamp(clock: clock, ticks: ticks)
}

private func displayFactSpan(_ begin: UInt64, _ end: UInt64, clock: UInt32 = 1) -> DisplayFacts.Interval {
    DisplayFacts.Interval(begin: displayFactStamp(begin, clock: clock), end: displayFactStamp(end, clock: clock))
}

private func displayFactCall(
    _ begin: UInt64 = 20, _ end: UInt64 = 40, epoch: UInt64 = 10, address: UInt64 = 4096,
    sync: UInt32 = 1, flags: UInt32 = 0, result: Int32 = 0
) -> DisplayFacts.Presentation {
    .called(
        epoch: epoch, address: address, interval: displayFactSpan(begin, end),
        syncInterval: sync, flags: flags, result: result)
}

private struct NativeDisplayFactFixture {
    var batch: DisplayFacts.Batch

    init() {
        let process = DisplayFacts.Process(pid: 7, lifetime: displayFactUUID(1))
        let thread = DisplayFacts.Thread(process: process, tid: 9, lifetime: displayFactUUID(2))
        let window = DisplayFacts.Window(
            process: process,
            key: NativeWindowKey(windowID: displayFactUUID(3), lifetimeID: displayFactUUID(4)))
        let attachment = NativeWindowAttachmentID(displayFactUUID(5))
        let request = NativeWindowRequestID(displayFactUUID(6))
        let frame = BackendFrameID(deviceGeneration: 0, frameNumber: 0)
        let nativeHealth = DisplayFacts.Health(
            finalized: true, decoderComplete: true, eventsLost: nil, buffersLost: nil,
            decoderOverflow: 0, rejectedRecords: 0)
        let etlHealth = DisplayFacts.Health(
            finalized: true, decoderComplete: true, eventsLost: 0, buffersLost: 0,
            decoderOverflow: 0, rejectedRecords: nil)
        batch = DisplayFacts.Batch(
            clocks: [
                .init(id: 1, origin: 7, frequency: 10_000_000, source: .nativeQPC, health: nativeHealth),
                .init(
                    id: 2, origin: 7, frequency: 10_000_000,
                    source: .etl(clockType: 1, rawTimestamps: true), health: etlHealth),
            ],
            epochs: [
                .init(
                    id: displayFactID(1), epoch: 10, thread: thread, window: window,
                    attachment: attachment, surfaceGeneration: 1, deviceGeneration: 0,
                    address: 4096, interval: displayFactSpan(0, 1000))
            ],
            attempts: [
                .init(
                    id: displayFactID(2), request: request, thread: thread, window: window,
                    attachment: attachment, surfaceGeneration: 1, frame: frame,
                    prepared: displayFactStamp(10), presentation: displayFactCall())
            ],
            events: [
                .init(
                    id: displayFactID(1, source: 2), thread: thread,
                    at: displayFactStamp(25, clock: 2), kind: .start(address: 4096, syncInterval: 1, flags: 0)),
                .init(
                    id: displayFactID(2, source: 2), thread: thread,
                    at: displayFactStamp(35, clock: 2), kind: .stop(result: 0)),
            ],
            dispositions: [
                .init(id: displayFactID(3, source: 2), start: displayFactID(1, source: 2), state: .displayed)
            ],
            displays: [
                .init(
                    id: displayFactID(4, source: 2), start: displayFactID(1, source: 2), index: 0,
                    output: .init(adapter: 0, source: 0, epoch: 0), at: displayFactStamp(30, clock: 2))
            ],
            receipts: [
                .init(
                    id: displayFactID(3), request: request, thread: thread, window: window,
                    attachment: attachment, surfaceGeneration: 1, frame: frame,
                    completed: displayFactStamp(45), delivered: displayFactStamp(70), outcome: .returned)
            ],
            inputs: [
                .init(
                    id: displayFactID(4), input: .init(window: window, nativeSequence: 0),
                    at: displayFactStamp(5), boundary: .nativeDequeue, effect: .represented(request: request))
            ],
            coverage: .init(
                window: window, requested: displayFactSpan(0, 1000), observed: displayFactSpan(0, 1000),
                headComplete: true, tailComplete: true, missing: []))
    }

    mutating func appendSecondCall() {
        var attempt = batch.attempts[0]
        attempt.id = displayFactID(10)
        attempt.request = NativeWindowRequestID(displayFactUUID(10))
        attempt.frame = BackendFrameID(deviceGeneration: 0, frameNumber: 1)
        attempt.prepared = displayFactStamp(50)
        attempt.presentation = displayFactCall(60, 80)
        batch.attempts.append(attempt)
        var receipt = batch.receipts[0]
        receipt.id = displayFactID(11)
        receipt.request = attempt.request
        receipt.frame = attempt.frame
        receipt.completed = displayFactStamp(85)
        receipt.delivered = displayFactStamp(95)
        batch.receipts.append(receipt)
        batch.events.append(
            .init(
                id: displayFactID(10, source: 2), thread: attempt.thread,
                at: displayFactStamp(65, clock: 2), kind: .start(address: 4096, syncInterval: 1, flags: 0)))
        batch.events.append(
            .init(
                id: displayFactID(11, source: 2), thread: attempt.thread,
                at: displayFactStamp(75, clock: 2), kind: .stop(result: 0)))
        batch.dispositions.append(
            .init(id: displayFactID(12, source: 2), start: displayFactID(10, source: 2), state: .displayed))
        batch.displays.append(
            .init(
                id: displayFactID(13, source: 2), start: displayFactID(10, source: 2), index: 0,
                output: .init(adapter: 0, source: 0, epoch: 0), at: displayFactStamp(70, clock: 2)))
    }

    mutating func removeAllWork() {
        batch.epochs = []
        batch.attempts = []
        batch.events = []
        batch.dispositions = []
        batch.displays = []
        batch.receipts = []
        batch.inputs = []
    }
}

private enum NativeDisplayFactTestFailure: Error {
    case rejected
}

/// These are synthetic supplied facts. No test is native capture or performance evidence.
final class NativeDisplayMeasurementTests: XCTestCase {
    private func report(
        _ batch: DisplayFacts.Batch, file: StaticString = #filePath, line: UInt = #line
    ) throws -> DisplayFacts.Report {
        switch DisplayFacts.check(batch) {
        case .checked(let report):
            return report
        case .rejected(let rejection):
            XCTFail("Unexpected whole-batch rejection: \(rejection)", file: file, line: line)
            throw NativeDisplayFactTestFailure.rejected
        }
    }

    private func assertIssue(
        _ report: DisplayFacts.Report, _ code: DisplayFacts.IssueCode,
        severity: DisplayFacts.Severity? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            report.issues.contains { $0.code == code && (severity == nil || $0.severity == severity) },
            "Missing supplied-fact issue: \(code)", file: file, line: line)
    }

    private func assertNoMatched(
        _ report: DisplayFacts.Report, file: StaticString = #filePath, line: UInt = #line
    ) {
        for attempt in report.attempts {
            if case .matched = attempt.join {
                XCTFail("Unresolved evidence must not produce a unique supplied-fact join.", file: file, line: line)
            }
        }
    }

    func testConsistentSuppliedFactsKeepZeroIDsAndDisplayBeforeStop() throws {
        let fixture = NativeDisplayFactFixture()
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(
            result.attempts[0].join, .matched(start: displayFactID(1, source: 2), stop: displayFactID(2, source: 2)))
        XCTAssertEqual(result.attempts[0].apiResult, .apiReturned(0))
        XCTAssertEqual(result.attempts[0].displayFactIDs, [displayFactID(4, source: 2)])
        XCTAssertEqual(result.inputs[0].relation, .consistent)
        XCTAssertEqual(fixture.batch.attempts[0].frame, BackendFrameID(deviceGeneration: 0, frameNumber: 0))
        XCTAssertEqual(fixture.batch.inputs[0].input.nativeSequence, 0)
        XCTAssertLessThan(fixture.batch.displays[0].at.ticks, fixture.batch.events[1].at.ticks)
        XCTAssertLessThan(fixture.batch.displays[0].at.ticks, fixture.batch.receipts[0].delivered.ticks)
    }

    func testManyDisplayObservationsAndLateReceiptKeepOriginalStart() throws {
        var fixture = NativeDisplayFactFixture()
        var second = fixture.batch.displays[0]
        second.id = displayFactID(5, source: 2)
        second.index = 1
        second.output.epoch = 1
        second.at = displayFactStamp(100, clock: 2)
        fixture.batch.displays.append(second)
        fixture.batch.receipts[0].delivered = displayFactStamp(150)
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertEqual(result.attempts[0].displayFactIDs, [displayFactID(4, source: 2), displayFactID(5, source: 2)])
        XCTAssertEqual(result.attempts[0].receiptFactID, displayFactID(3))
    }

    func testLostAndUnknownDispositionRetainKnownPartialDisplays() throws {
        let states: [DisplayFacts.DispositionState] = [.lost, .unknown]
        for state in states {
            var fixture = NativeDisplayFactFixture()
            fixture.batch.dispositions[0].state = state
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
            XCTAssertEqual(result.attempts[0].disposition, state)
            XCTAssertEqual(result.attempts[0].displayFactIDs.count, 1)
            XCTAssertEqual(
                result.attempts[0].join, .matched(start: displayFactID(1, source: 2), stop: displayFactID(2, source: 2))
            )
        }
    }

    func testDiscardedWithoutDisplayIsAnExplicitDisposition() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.dispositions[0].state = .discarded
        fixture.batch.displays = []
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertEqual(result.attempts[0].disposition, .discarded)
        XCTAssertTrue(result.attempts[0].displayFactIDs.isEmpty)
    }

    func testAPIFailureIsDistinctFromLostEvidenceAndReceiptOutcome() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.attempts[0].presentation = displayFactCall(result: -7)
        fixture.batch.events[1].kind = .stop(result: -7)
        fixture.batch.dispositions[0].state = .discarded
        fixture.batch.displays = []
        fixture.batch.receipts[0].outcome = .failed
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertEqual(result.attempts[0].apiResult, .apiFailed(-7))
        XCTAssertEqual(result.attempts[0].receiptOutcome, .failed)
        XCTAssertFalse(result.issues.contains { $0.code == .sourceLoss })
    }

    func testNonnegativeOcclusionStatusIsNotPromotedToDisplayed() throws {
        var fixture = NativeDisplayFactFixture()
        let status: Int32 = 0x087A_0001
        fixture.batch.attempts[0].presentation = displayFactCall(result: status)
        fixture.batch.events[1].kind = .stop(result: status)
        fixture.batch.dispositions[0].state = .unknown
        fixture.batch.displays = []
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
        XCTAssertEqual(result.attempts[0].apiResult, .apiReturned(status))
        XCTAssertEqual(result.attempts[0].disposition, .unknown)
        XCTAssertTrue(result.attempts[0].displayFactIDs.isEmpty)
    }

    func testKnownNoPresentReasonsAcceptNilFramesWithoutInventingPairs() throws {
        let reasons: [DisplayFacts.NoPresentReason] = [
            .commandRejected, .renderFailed, .cancelled, .skipped, .offscreen,
        ]
        for reason in reasons {
            var fixture = NativeDisplayFactFixture()
            fixture.batch.attempts[0].presentation = .notCalled(reason)
            fixture.batch.attempts[0].frame = nil
            fixture.batch.receipts[0].frame = nil
            fixture.batch.receipts[0].outcome = .rejected
            fixture.batch.inputs[0].effect = .ignored
            fixture.batch.events = []
            fixture.batch.dispositions = []
            fixture.batch.displays = []
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .consistentSuppliedFacts)
            XCTAssertEqual(result.attempts[0].apiResult, .notCalled(reason))
            XCTAssertEqual(result.attempts[0].join, .notApplicable)
            XCTAssertEqual(
                result.noSuppliedPresent,
                [.init(interval: displayFactSpan(0, 1000), includesBegin: true, includesEnd: true)])
        }
    }

    func testUnknownPresentationAndMissingReceiptAreNotInferredAPIFailure() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.attempts[0].presentation = .unknown
        fixture.batch.events = []
        fixture.batch.dispositions = []
        fixture.batch.displays = []
        fixture.batch.receipts = []
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
        XCTAssertEqual(result.attempts[0].apiResult, .unobserved)
        XCTAssertNil(result.attempts[0].receiptOutcome)
        assertIssue(result, .presentationUnknown)
        assertIssue(result, .receiptMissing)
    }

    func testPreparationAfterCalledBeginCannotSupportInputOrUniqueJoin() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.attempts[0].prepared = displayFactStamp(30)
        fixture.batch.inputs[0].at = displayFactStamp(28)
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .contradictorySuppliedFacts)
        assertIssue(result, .preparationOrder, severity: .contradictory)
        XCTAssertEqual(result.inputs[0].relation, .contradictory)
        assertNoMatched(result)
        XCTAssertTrue(result.noSuppliedPresent.isEmpty)
    }

    func testCalledNilFrameCannotBorrowDeviceGenerationFromEpoch() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.attempts[0].frame = nil
        fixture.batch.receipts[0].frame = nil
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
        assertIssue(result, .frameUnavailable)
        XCTAssertEqual(result.attempts[0].join, .unavailable)
    }

    func testCalledDeviceGenerationMustMatchOriginalEpoch() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.attempts[0].frame = BackendFrameID(deviceGeneration: 1, frameNumber: 0)
        fixture.batch.receipts[0].frame = fixture.batch.attempts[0].frame
        let result = try report(fixture.batch)
        assertIssue(result, .frameMismatch, severity: .contradictory)
        assertNoMatched(result)
    }

    func testLateDisplayAndReceiptDoNotRebindToReplacementEpoch() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.epochs[0].interval = displayFactSpan(0, 50)
        var replacement = fixture.batch.epochs[0]
        replacement.id = displayFactID(5)
        replacement.epoch = 11
        replacement.interval = displayFactSpan(51, 1000)
        replacement.attachment = NativeWindowAttachmentID(displayFactUUID(11))
        replacement.surfaceGeneration = 2
        replacement.deviceGeneration = 1
        replacement.window.key = NativeWindowKey(windowID: displayFactUUID(3), lifetimeID: displayFactUUID(12))
        fixture.batch.epochs.append(replacement)
        fixture.batch.displays[0].at = displayFactStamp(60, clock: 2)
        fixture.batch.receipts[0].delivered = displayFactStamp(80)
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertEqual(result.attempts[0].receiptFactID, displayFactID(3))
        XCTAssertEqual(result.attempts[0].displayFactIDs, [displayFactID(4, source: 2)])
    }

    func testReceiptMustKeepOriginalWindowThreadAttachmentAndSurface() throws {
        for variant in 0..<4 {
            var fixture = NativeDisplayFactFixture()
            switch variant {
            case 0:
                fixture.batch.receipts[0].window.key = NativeWindowKey(
                    windowID: displayFactUUID(3), lifetimeID: displayFactUUID(20))
            case 1:
                fixture.batch.receipts[0].thread.lifetime = displayFactUUID(20)
            case 2:
                fixture.batch.receipts[0].attachment = NativeWindowAttachmentID(displayFactUUID(20))
            default:
                fixture.batch.receipts[0].surfaceGeneration = 2
            }
            let result = try report(fixture.batch)
            assertIssue(result, .receiptIdentityMismatch, severity: .contradictory)
            XCTAssertNil(result.attempts[0].receiptFactID)
        }
    }

    func testReceiptFrameNumberCannotBeBorrowedFromAnotherFrame() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.receipts[0].frame = BackendFrameID(deviceGeneration: 0, frameNumber: 1)
        let result = try report(fixture.batch)
        assertIssue(result, .frameMismatch, severity: .contradictory)
        XCTAssertNil(result.attempts[0].receiptFactID)
    }

    func testReceiptCompletionAndDeliveryOrderingIsChecked() throws {
        for variant in 0..<3 {
            var fixture = NativeDisplayFactFixture()
            switch variant {
            case 0: fixture.batch.receipts[0].completed = displayFactStamp(5)
            case 1: fixture.batch.receipts[0].completed = displayFactStamp(35)
            default: fixture.batch.receipts[0].delivered = displayFactStamp(44)
            }
            let result = try report(fixture.batch)
            assertIssue(result, .receiptOrder, severity: .contradictory)
            XCTAssertNil(result.attempts[0].receiptFactID)
        }
    }

    func testMissingReceiptDoesNotEraseKnownAPIReturnOrUniqueSuppliedPair() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.receipts = []
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
        XCTAssertEqual(result.attempts[0].apiResult, .apiReturned(0))
        XCTAssertEqual(
            result.attempts[0].join, .matched(start: displayFactID(1, source: 2), stop: displayFactID(2, source: 2)))
        XCTAssertNil(result.attempts[0].receiptOutcome)
        assertIssue(result, .receiptMissing)
    }

    func testMultipleReceiptsNeverChooseTheFirst() throws {
        var fixture = NativeDisplayFactFixture()
        var other = fixture.batch.receipts[0]
        other.id = displayFactID(5)
        other.outcome = .failed
        fixture.batch.receipts.append(other)
        for _ in 0..<2 {
            let result = try report(fixture.batch)
            assertIssue(result, .receiptMultiple, severity: .contradictory)
            XCTAssertNil(result.attempts[0].receiptFactID)
            XCTAssertNil(result.attempts[0].receiptOutcome)
            fixture.batch.receipts.reverse()
        }
    }

    func testOrphanReceiptIsReportedByItsSourceFact() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.receipts[0].request = NativeWindowRequestID(displayFactUUID(99))
        let result = try report(fixture.batch)
        XCTAssertTrue(result.issues.contains { $0.code == .referenceMissing && $0.fact == displayFactID(3) })
        assertIssue(result, .receiptMissing)
        XCTAssertNil(result.attempts[0].receiptFactID)
    }

    func testUnknownClockMetadataWithholdsTheUniqueJoin() throws {
        for variant in 0..<4 {
            var fixture = NativeDisplayFactFixture()
            switch variant {
            case 0: fixture.batch.clocks[1].frequency = nil
            case 1: fixture.batch.clocks[1].origin = nil
            case 2: fixture.batch.clocks[1].source = .etl(clockType: nil, rawTimestamps: true)
            default: fixture.batch.clocks[1].source = .etl(clockType: 1, rawTimestamps: nil)
            }
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
            assertIssue(result, .clockMetadataMissing)
            assertNoMatched(result)
        }
    }

    func testClockOriginAndFrequencyMismatchAreContradictions() throws {
        for variant in 0..<2 {
            var fixture = NativeDisplayFactFixture()
            if variant == 0 {
                fixture.batch.clocks[1].origin = 8
            } else {
                fixture.batch.clocks[1].frequency = 9_999_999
            }
            let result = try report(fixture.batch)
            assertIssue(result, .clockMismatch, severity: .contradictory)
            assertNoMatched(result)
        }
    }

    func testConvertedOrNonQPCETLClocksAreNotRawFallbacks() throws {
        let sources: [DisplayFacts.ClockSource] = [
            .etl(clockType: 2, rawTimestamps: true), .etl(clockType: 1, rawTimestamps: false),
        ]
        for source in sources {
            var fixture = NativeDisplayFactFixture()
            fixture.batch.clocks[1].source = source
            let result = try report(fixture.batch)
            assertIssue(result, .clockNotQPC, severity: .contradictory)
            assertNoMatched(result)
        }
    }

    func testZeroNativeFrequencyPreventsComparisonsAndGapSubtraction() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.clocks[0].frequency = 0
        let result = try report(fixture.batch)
        assertIssue(result, .invalidFrequency, severity: .contradictory)
        assertNoMatched(result)
        XCTAssertTrue(result.noSuppliedPresent.isEmpty)
    }

    func testMissingNativeBasisDoesNotOrderRawCounters() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.clocks[0].origin = nil
        fixture.batch.attempts[0].prepared = displayFactStamp(100)
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
        assertNoMatched(result)
        XCTAssertTrue(result.noSuppliedPresent.isEmpty)
        XCTAssertFalse(result.issues.contains { $0.code == .preparationOrder || $0.code == .receiptOrder })
    }

    func testETLFactRolesCannotUseNativeClockToAvoidETLHealth() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.clocks[1].source = .nativeQPC
        fixture.batch.clocks[1].health.rejectedRecords = 0
        let result = try report(fixture.batch)
        assertIssue(result, .sourceRoleMismatch, severity: .contradictory)
        assertNoMatched(result)
    }

    func testETLStampsMustUseTheFactSourceEvenWhenBasesMatch() throws {
        for variant in 0..<2 {
            var fixture = NativeDisplayFactFixture()
            var other = fixture.batch.clocks[1]
            other.id = 3
            fixture.batch.clocks.append(other)
            if variant == 0 {
                fixture.batch.events[0].at.clock = 3
            } else {
                fixture.batch.displays[0].at.clock = 3
            }
            let result = try report(fixture.batch)
            assertIssue(result, .sourceRoleMismatch, severity: .contradictory)
            if variant == 0 { assertNoMatched(result) }
        }
    }

    func testNativeFactSourceCannotMasqueradeAsETL() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.attempts[0].id = displayFactID(100, source: 2)
        let result = try report(fixture.batch)
        assertIssue(result, .sourceRoleMismatch, severity: .contradictory)
        assertNoMatched(result)
    }

    func testInputEarlierBoundaryAllowsCompatibleETLButNativeDequeueDoesNot() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.inputs[0].at.clock = 2
        fixture.batch.inputs[0].boundary = .reportedEarlier
        XCTAssertEqual(try report(fixture.batch).summary, .consistentSuppliedFacts)
        fixture.batch.inputs[0].boundary = .nativeDequeue
        let result = try report(fixture.batch)
        assertIssue(result, .sourceRoleMismatch, severity: .contradictory)
        XCTAssertEqual(result.inputs[0].relation, .contradictory)
    }

    func testRequiredUnknownHealthRetainsIncompleteEvidenceWithSuppliedJoin() throws {
        for variant in 0..<9 {
            var fixture = NativeDisplayFactFixture()
            switch variant {
            case 0: fixture.batch.clocks[1].health.finalized = nil
            case 1: fixture.batch.clocks[1].health.decoderComplete = nil
            case 2: fixture.batch.clocks[1].health.decoderOverflow = nil
            case 3: fixture.batch.clocks[1].health.eventsLost = nil
            case 4: fixture.batch.clocks[1].health.buffersLost = nil
            case 5: fixture.batch.clocks[0].health.finalized = nil
            case 6: fixture.batch.clocks[0].health.decoderComplete = nil
            case 7: fixture.batch.clocks[0].health.decoderOverflow = nil
            default: fixture.batch.clocks[0].health.rejectedRecords = nil
            }
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
            assertIssue(result, .sourceHealthMissing)
            XCTAssertEqual(
                result.attempts[0].join, .matched(start: displayFactID(1, source: 2), stop: displayFactID(2, source: 2))
            )
        }
    }

    func testFalseCompletionAndNonzeroLossNeverBecomeAPIResults() throws {
        for variant in 0..<6 {
            var fixture = NativeDisplayFactFixture()
            switch variant {
            case 0: fixture.batch.clocks[1].health.finalized = false
            case 1: fixture.batch.clocks[1].health.decoderComplete = false
            case 2: fixture.batch.clocks[1].health.eventsLost = 1
            case 3: fixture.batch.clocks[1].health.buffersLost = 1
            case 4: fixture.batch.clocks[1].health.decoderOverflow = 1
            default: fixture.batch.clocks[0].health.rejectedRecords = 1
            }
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
            XCTAssertEqual(result.attempts[0].apiResult, .apiReturned(0))
            XCTAssertEqual(
                result.attempts[0].join, .matched(start: displayFactID(1, source: 2), stop: displayFactID(2, source: 2))
            )
            let expected: DisplayFacts.IssueCode =
                variant == 0 ? .sourceUnfinalized : (variant == 1 ? .sourceDecodeIncomplete : .sourceLoss)
            assertIssue(result, expected)
        }
    }

    func testNonapplicableNilHealthIsNotInventedZeroOrLoss() throws {
        let fixture = NativeDisplayFactFixture()
        let original = fixture.batch
        XCTAssertNil(original.clocks[0].health.eventsLost)
        XCTAssertNil(original.clocks[0].health.buffersLost)
        XCTAssertNil(original.clocks[1].health.rejectedRecords)
        XCTAssertEqual(try report(original).summary, .consistentSuppliedFacts)
        XCTAssertEqual(fixture.batch, original)
        var suppliedNonzero = fixture.batch
        suppliedNonzero.clocks[0].health.eventsLost = 1
        assertIssue(try report(suppliedNonzero), .sourceLoss, severity: .incomplete)
    }

    func testUnstampedDispositionStillRequiresETLRoleAndHealth() throws {
        var wrongRole = NativeDisplayFactFixture()
        wrongRole.batch.dispositions[0].id = displayFactID(100)
        assertIssue(try report(wrongRole.batch), .sourceRoleMismatch, severity: .contradictory)

        var unknownHealth = NativeDisplayFactFixture()
        var source = unknownHealth.batch.clocks[1]
        source.id = 3
        source.health.buffersLost = nil
        unknownHealth.batch.clocks.append(source)
        unknownHealth.batch.dispositions[0].id = displayFactID(100, source: 3)
        let result = try report(unknownHealth.batch)
        XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
        XCTAssertTrue(result.issues.contains { $0.code == .sourceHealthMissing && $0.clock == 3 })
    }

    func testMaximumFrequencyAndZeroClockIdentityNeedNoNumericConversion() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.removeAllWork()
        var clock = fixture.batch.clocks[0]
        clock.id = 0
        clock.origin = 0
        clock.frequency = UInt64.max
        fixture.batch.clocks = [clock]
        fixture.batch.coverage.requested = displayFactSpan(0, UInt64.max, clock: 0)
        fixture.batch.coverage.observed = fixture.batch.coverage.requested
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertEqual(
            result.noSuppliedPresent,
            [
                .init(interval: displayFactSpan(0, UInt64.max, clock: 0), includesBegin: true, includesEnd: true)
            ])
    }

    func testStartStopPairingUsesThreadTimeNotArrayOrder() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.appendSecondCall()
        fixture.batch.events.reverse()
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertEqual(
            result.attempts[0].join, .matched(start: displayFactID(1, source: 2), stop: displayFactID(2, source: 2)))
        XCTAssertEqual(
            result.attempts[1].join, .matched(start: displayFactID(10, source: 2), stop: displayFactID(11, source: 2)))
    }

    func testStopDoesNotAcquireStartAddressAcrossThreadOrProcessLifetimes() throws {
        for variant in 0..<2 {
            var fixture = NativeDisplayFactFixture()
            if variant == 0 {
                fixture.batch.events[1].thread.lifetime = displayFactUUID(20)
            } else {
                fixture.batch.events[1].thread.process.lifetime = displayFactUUID(20)
            }
            let result = try report(fixture.batch)
            assertNoMatched(result)
            assertIssue(result, .orphanStart)
            assertIssue(result, .orphanStop)
        }
    }

    func testEqualEventTicksAreAmbiguousWithoutFactIDTiebreak() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.events[1].at = fixture.batch.events[0].at
        for _ in 0..<2 {
            let result = try report(fixture.batch)
            XCTAssertEqual(result.attempts[0].join, .ambiguous)
            assertIssue(result, .threadOrderAmbiguous, severity: .incomplete)
            fixture.batch.events.reverse()
        }
    }

    func testNestedStartInvalidatesEveryPairOnThatThread() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.appendSecondCall()
        fixture.batch.events.append(
            .init(
                id: displayFactID(20, source: 2), thread: fixture.batch.events[0].thread,
                at: displayFactStamp(70, clock: 2), kind: .start(address: 8192, syncInterval: 1, flags: 0)))
        let result = try report(fixture.batch)
        XCTAssertEqual(result.attempts.map(\.join), [.ambiguous, .ambiguous])
        assertIssue(result, .threadOrderAmbiguous)
        assertNoMatched(result)
    }

    func testOrphanEventsDoNotSalvageAUniquePrefixOfTheThread() throws {
        for trailingStart in [false, true] {
            var fixture = NativeDisplayFactFixture()
            let kind: DisplayFacts.DXGIKind =
                trailingStart
                ? .start(address: 4096, syncInterval: 1, flags: 0) : .stop(result: 0)
            fixture.batch.events.append(
                .init(
                    id: displayFactID(20, source: 2), thread: fixture.batch.events[0].thread,
                    at: displayFactStamp(50, clock: 2), kind: kind))
            let result = try report(fixture.batch)
            assertNoMatched(result)
            assertIssue(result, trailingStart ? .orphanStart : .orphanStop)
        }
    }

    func testZeroBracketMatchesRemainMissingWithUnclaimedRawPair() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.attempts[0].presentation = displayFactCall(40, 60)
        fixture.batch.receipts[0].completed = displayFactStamp(65)
        let result = try report(fixture.batch)
        XCTAssertEqual(result.attempts[0].join, .missing)
        assertIssue(result, .pairMissing)
        assertIssue(result, .unclaimedPair)
    }

    func testMultipleBracketMatchesAreNotFilteredByExpectedAddress() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.appendSecondCall()
        fixture.batch.attempts.removeLast()
        fixture.batch.receipts.removeLast()
        fixture.batch.events[1].at = displayFactStamp(26, clock: 2)
        fixture.batch.events[2].at = displayFactStamp(30, clock: 2)
        fixture.batch.events[2].kind = .start(address: 8192, syncInterval: 1, flags: 0)
        fixture.batch.events[3].at = displayFactStamp(35, clock: 2)
        let result = try report(fixture.batch)
        XCTAssertEqual(result.attempts[0].join, .ambiguous)
        assertIssue(result, .pairAmbiguous, severity: .incomplete)
        assertNoMatched(result)
    }

    func testPairReuseInvalidatesAllAttemptsInEitherArrayOrder() throws {
        var fixture = NativeDisplayFactFixture()
        var duplicateBracket = fixture.batch.attempts[0]
        duplicateBracket.id = displayFactID(10)
        duplicateBracket.request = NativeWindowRequestID(displayFactUUID(10))
        fixture.batch.attempts.append(duplicateBracket)
        var secondReceipt = fixture.batch.receipts[0]
        secondReceipt.id = displayFactID(11)
        secondReceipt.request = duplicateBracket.request
        fixture.batch.receipts.append(secondReceipt)
        for _ in 0..<2 {
            let result = try report(fixture.batch)
            XCTAssertEqual(result.attempts.count, 2)
            XCTAssertTrue(result.attempts.allSatisfy { $0.join == .ambiguous })
            XCTAssertEqual(result.issues.filter { $0.code == .pairReused }.count, 2)
            assertNoMatched(result)
            fixture.batch.attempts.reverse()
            fixture.batch.receipts.reverse()
        }
    }

    func testOverlappingNativeBracketsInvalidateDistinctRawPairs() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.appendSecondCall()
        fixture.batch.attempts[0].presentation = displayFactCall(20, 70)
        fixture.batch.attempts[1].prepared = displayFactStamp(25)
        fixture.batch.attempts[1].presentation = displayFactCall(30, 80)
        fixture.batch.receipts[0].completed = displayFactStamp(80)
        fixture.batch.receipts[0].delivered = displayFactStamp(90)
        for _ in 0..<2 {
            let result = try report(fixture.batch)
            XCTAssertEqual(result.attempts.map(\.join), [.ambiguous, .ambiguous])
            XCTAssertEqual(result.issues.filter { $0.code == .nativeCallsOverlap }.count, 2)
            XCTAssertFalse(result.issues.contains { $0.code == .pairReused })
            fixture.batch.attempts.reverse()
        }
    }

    func testMissingEpochIsIncompleteNotInventedFromStartAddress() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.epochs = []
        let result = try report(fixture.batch)
        XCTAssertEqual(result.attempts[0].join, .missing)
        assertIssue(result, .epochMissing, severity: .incomplete)
    }

    func testClosedEpochBoundaryAmbiguityNeverChoosesNewestMapping() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.epochs[0].interval = displayFactSpan(0, 20)
        var replacement = fixture.batch.epochs[0]
        replacement.id = displayFactID(5)
        replacement.epoch = 11
        replacement.interval = displayFactSpan(20, 1000)
        fixture.batch.epochs.append(replacement)
        for _ in 0..<2 {
            let result = try report(fixture.batch)
            XCTAssertEqual(result.attempts[0].join, .ambiguous)
            assertIssue(result, .epochAmbiguous, severity: .incomplete)
            fixture.batch.epochs.reverse()
        }
    }

    func testEpochIdentityMustMatchOriginalIssuance() throws {
        for variant in 0..<5 {
            var fixture = NativeDisplayFactFixture()
            switch variant {
            case 0:
                fixture.batch.epochs[0].window.key = NativeWindowKey(
                    windowID: displayFactUUID(3), lifetimeID: displayFactUUID(20))
            case 1: fixture.batch.epochs[0].thread.lifetime = displayFactUUID(20)
            case 2: fixture.batch.epochs[0].attachment = NativeWindowAttachmentID(displayFactUUID(20))
            case 3: fixture.batch.epochs[0].surfaceGeneration = 2
            default: fixture.batch.epochs[0].thread.process.lifetime = displayFactUUID(20)
            }
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .contradictorySuppliedFacts)
            assertNoMatched(result)
            XCTAssertTrue(result.issues.contains { $0.code == .epochMismatch || $0.code == .identityMismatch })
        }
    }

    func testSameAddressInAnotherOriginalProcessIsNotAnEpochMatch() throws {
        var fixture = NativeDisplayFactFixture()
        var other = fixture.batch.epochs[0]
        other.id = displayFactID(5)
        other.epoch = 11
        other.window.process.lifetime = displayFactUUID(20)
        other.thread.process = other.window.process
        fixture.batch.epochs.append(other)
        XCTAssertEqual(try report(fixture.batch).summary, .consistentSuppliedFacts)
    }

    func testStartArgumentsAndStopResultMustMatchNativeCall() throws {
        for variant in 0..<4 {
            var fixture = NativeDisplayFactFixture()
            switch variant {
            case 0: fixture.batch.events[0].kind = .start(address: 8192, syncInterval: 1, flags: 0)
            case 1: fixture.batch.events[0].kind = .start(address: 4096, syncInterval: 2, flags: 0)
            case 2: fixture.batch.events[0].kind = .start(address: 4096, syncInterval: 1, flags: 8)
            default: fixture.batch.events[1].kind = .stop(result: -1)
            }
            let result = try report(fixture.batch)
            assertIssue(result, variant == 3 ? .stopMismatch : .startMismatch, severity: .contradictory)
            assertNoMatched(result)
        }
    }

    func testReversedNativeBracketDoesNotUnderflowGapArithmetic() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.attempts[0].presentation = displayFactCall(40, 20)
        let result = try report(fixture.batch)
        assertIssue(result, .reversedInterval, severity: .contradictory)
        assertNoMatched(result)
        XCTAssertTrue(result.noSuppliedPresent.isEmpty)
    }

    func testDisplayBeforeStartIsAContradictionButBeforeStopIsAllowed() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.displays[0].at = displayFactStamp(24, clock: 2)
        let result = try report(fixture.batch)
        assertIssue(result, .displayBeforeStart, severity: .contradictory)
        fixture.batch.displays[0].at = displayFactStamp(30, clock: 2)
        XCTAssertEqual(try report(fixture.batch).summary, .consistentSuppliedFacts)
    }

    func testMissingDisplayOrDispositionRemainsIncomplete() throws {
        for missingDisplay in [false, true] {
            var fixture = NativeDisplayFactFixture()
            if missingDisplay {
                fixture.batch.displays = []
            } else {
                fixture.batch.dispositions = []
            }
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
            assertIssue(result, missingDisplay ? .displayMissing : .dispositionMissing)
        }
    }

    func testMultipleDispositionsDoNotSelectOneAndDiscardCannotHaveDisplays() throws {
        var multiple = NativeDisplayFactFixture()
        var other = multiple.batch.dispositions[0]
        other.id = displayFactID(5, source: 2)
        multiple.batch.dispositions.append(other)
        let result = try report(multiple.batch)
        assertIssue(result, .dispositionMultiple, severity: .contradictory)
        XCTAssertNil(result.attempts[0].disposition)

        var discarded = NativeDisplayFactFixture()
        discarded.batch.dispositions[0].state = .discarded
        assertIssue(try report(discarded.batch), .displayContradiction, severity: .contradictory)
    }

    func testOrphanDisplayAndDispositionReferencesDistinguishMissingFromWrongKind() throws {
        for wrongKind in [false, true] {
            var fixture = NativeDisplayFactFixture()
            let reference = wrongKind ? displayFactID(2, source: 2) : displayFactID(99, source: 2)
            fixture.batch.displays[0].start = reference
            fixture.batch.dispositions[0].start = reference
            let result = try report(fixture.batch)
            let code: DisplayFacts.IssueCode = wrongKind ? .referenceWrongKind : .referenceMissing
            let severity: DisplayFacts.Severity = wrongKind ? .contradictory : .incomplete
            XCTAssertTrue(
                result.issues.contains {
                    $0.fact == displayFactID(3, source: 2) && $0.code == code && $0.severity == severity
                })
            XCTAssertTrue(
                result.issues.contains {
                    $0.fact == displayFactID(4, source: 2) && $0.code == code && $0.severity == severity
                })
        }
    }

    func testCoalescedCancelledIgnoredDeferredAndUnknownEffectsStayDistinct() throws {
        let effects: [DisplayFacts.Effect] = [.coalesced, .cancelled, .ignored, .deferred, .unknown]
        for effect in effects {
            var fixture = NativeDisplayFactFixture()
            fixture.batch.inputs[0].effect = effect
            let result = try report(fixture.batch)
            XCTAssertEqual(result.inputs[0].effect, effect)
            let unresolved = effect == .deferred || effect == .unknown
            XCTAssertEqual(result.inputs[0].relation, unresolved ? .incomplete : .consistent)
            XCTAssertEqual(result.summary, unresolved ? .incompleteSuppliedFacts : .consistentSuppliedFacts)
        }
    }

    func testRepresentedInputRequiresKnownRequestOriginalWindowAndPreparationOrder() throws {
        for variant in 0..<3 {
            var fixture = NativeDisplayFactFixture()
            switch variant {
            case 0:
                fixture.batch.inputs[0].effect = .represented(request: NativeWindowRequestID(displayFactUUID(99)))
            case 1:
                fixture.batch.inputs[0].input.window.key = NativeWindowKey(
                    windowID: displayFactUUID(3), lifetimeID: displayFactUUID(20))
            default:
                fixture.batch.inputs[0].at = displayFactStamp(11)
            }
            let result = try report(fixture.batch)
            let code: DisplayFacts.IssueCode =
                variant == 0 ? .referenceMissing : (variant == 1 ? .inputWindowMismatch : .inputOrder)
            assertIssue(result, code)
            XCTAssertEqual(result.inputs[0].relation, variant == 0 ? .incomplete : .contradictory)
        }
    }

    func testSupersessionRequiresDifferentKnownLaterInputOnSameWindow() throws {
        for variant in 0..<5 {
            var fixture = NativeDisplayFactFixture()
            var successor = fixture.batch.inputs[0]
            successor.id = displayFactID(5)
            successor.input.nativeSequence = 1
            successor.at = displayFactStamp(7)
            successor.effect = .ignored
            if variant == 2 {
                fixture.batch.inputs[0].input.nativeSequence = 2
                successor.at = displayFactStamp(3)
            }
            if variant == 3 {
                successor.input.window.key = NativeWindowKey(
                    windowID: displayFactUUID(3), lifetimeID: displayFactUUID(20))
            }
            fixture.batch.inputs.append(successor)
            var target = successor.input
            if variant == 1 { target = fixture.batch.inputs[0].input }
            if variant == 4 { target.nativeSequence = 99 }
            fixture.batch.inputs[0].effect = .superseded(by: target)
            let result = try report(fixture.batch)
            XCTAssertEqual(result.inputs[0].effect, .superseded(by: target))
            let expected: DisplayFacts.RelationValidity =
                variant == 0 ? .consistent : (variant == 4 ? .incomplete : .contradictory)
            XCTAssertEqual(result.inputs[0].relation, expected)
            if variant == 1 || variant == 2 { assertIssue(result, .supersessionInvalid) }
            if variant == 3 { assertIssue(result, .inputWindowMismatch) }
            if variant == 4 { assertIssue(result, .referenceMissing) }
        }
    }

    func testInputRelationResolutionDoesNotDependOnSuccessorArrayOrder() throws {
        var fixture = NativeDisplayFactFixture()
        var successor = fixture.batch.inputs[0]
        successor.id = displayFactID(5)
        successor.input.nativeSequence = 1
        successor.at = displayFactStamp(7)
        successor.effect = .unknown
        fixture.batch.inputs[0].effect = .superseded(by: successor.input)
        fixture.batch.inputs.append(successor)
        let originalID = fixture.batch.inputs[0].input
        for _ in 0..<2 {
            let result = try report(fixture.batch)
            XCTAssertEqual(result.inputs.first { $0.input == originalID }?.relation, .incomplete)
            fixture.batch.inputs.reverse()
        }
    }

    func testMissingInputClockCannotBecomeALatencyRelation() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.inputs[0].at.clock = 99
        let result = try report(fixture.batch)
        assertIssue(result, .clockMissing, severity: .incomplete)
        XCTAssertEqual(result.inputs[0].relation, .incomplete)
    }

    func testGapEndpointsExactlyComplementClosedSuppliedCalls() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.appendSecondCall()
        let result = try report(fixture.batch)
        XCTAssertEqual(
            result.noSuppliedPresent,
            [
                .init(interval: displayFactSpan(0, 20), includesBegin: true, includesEnd: false),
                .init(interval: displayFactSpan(40, 60), includesBegin: false, includesEnd: false),
                .init(interval: displayFactSpan(80, 1000), includesBegin: false, includesEnd: true),
            ])
    }

    func testClippedCallBoundariesDoNotAppearInsideGaps() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.coverage.requested = displayFactSpan(20, 40)
        XCTAssertTrue(try report(fixture.batch).noSuppliedPresent.isEmpty)
        fixture.batch.coverage.requested = displayFactSpan(0, 20)
        XCTAssertEqual(
            try report(fixture.batch).noSuppliedPresent,
            [
                .init(interval: displayFactSpan(0, 20), includesBegin: true, includesEnd: false)
            ])
        fixture.batch.coverage.requested = displayFactSpan(40, 50)
        XCTAssertEqual(
            try report(fixture.batch).noSuppliedPresent,
            [
                .init(interval: displayFactSpan(40, 50), includesBegin: false, includesEnd: true)
            ])
    }

    func testUnknownCoverageClockSuppressesGapSubtraction() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.coverage.requested = displayFactSpan(0, 1000, clock: 99)
        let result = try report(fixture.batch)
        assertIssue(result, .clockMissing)
        XCTAssertTrue(result.noSuppliedPresent.isEmpty)
    }

    func testMissingHeadTailObservedCoverageAndExplicitHolesRemainIncomplete() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.coverage.headComplete = nil
        fixture.batch.coverage.tailComplete = false
        fixture.batch.coverage.observed = displayFactSpan(5, 900)
        fixture.batch.coverage.missing = [displayFactSpan(50, 60)]
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
        assertIssue(result, .headIncomplete)
        assertIssue(result, .tailIncomplete)
        assertIssue(result, .coverageIncomplete)
        assertIssue(result, .coverageHole)
        fixture.batch.coverage.observed = nil
        assertIssue(try report(fixture.batch), .coverageMissing)
    }

    func testZeroCoverageIsIncompleteAndDoesNotDescribeASuccessfulRun() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.coverage.requested = displayFactSpan(10, 10)
        let result = try report(fixture.batch)
        assertIssue(result, .emptyCoverage, severity: .incomplete)
        XCTAssertTrue(result.noSuppliedPresent.isEmpty)
    }

    func testEmptySuppliedWorkPreservesGapWithoutInventingFrameDemand() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.removeAllWork()
        fixture.batch.coverage.requested = displayFactSpan(0, 300_000_000)
        fixture.batch.coverage.observed = fixture.batch.coverage.requested
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertTrue(result.attempts.isEmpty)
        XCTAssertTrue(result.inputs.isEmpty)
        XCTAssertEqual(
            result.noSuppliedPresent,
            [
                .init(interval: fixture.batch.coverage.requested, includesBegin: true, includesEnd: true)
            ])
        // Consistency of these declarations is not a thirty-second hardware pass.
    }

    func testEveryIndependentRosterCapRejectsBeforeDuplicateIndexing() throws {
        let caps: [(DisplayFacts.Resource, Int)] = [
            (.clocks, 8), (.epochs, 64), (.attempts, 8192), (.events, 16384),
            (.starts, 8192), (.stops, 8192), (.dispositions, 8192), (.displays, 16384),
            (.receipts, 8192), (.inputs, 8192), (.missingIntervals, 64),
        ]
        for (resource, limit) in caps {
            var fixture = NativeDisplayFactFixture()
            switch resource {
            case .clocks: fixture.batch.clocks = Array(repeating: fixture.batch.clocks[0], count: limit + 1)
            case .epochs: fixture.batch.epochs = Array(repeating: fixture.batch.epochs[0], count: limit + 1)
            case .attempts: fixture.batch.attempts = Array(repeating: fixture.batch.attempts[0], count: limit + 1)
            case .events, .starts: fixture.batch.events = Array(repeating: fixture.batch.events[0], count: limit + 1)
            case .stops: fixture.batch.events = Array(repeating: fixture.batch.events[1], count: limit + 1)
            case .dispositions:
                fixture.batch.dispositions = Array(repeating: fixture.batch.dispositions[0], count: limit + 1)
            case .displays: fixture.batch.displays = Array(repeating: fixture.batch.displays[0], count: limit + 1)
            case .receipts: fixture.batch.receipts = Array(repeating: fixture.batch.receipts[0], count: limit + 1)
            case .inputs: fixture.batch.inputs = Array(repeating: fixture.batch.inputs[0], count: limit + 1)
            case .missingIntervals:
                fixture.batch.coverage.missing = Array(repeating: displayFactSpan(50, 60), count: limit + 1)
            case .total, .issues, .gaps: XCTFail("Only input roster caps belong in this table.")
            }
            XCTAssertEqual(
                DisplayFacts.check(fixture.batch),
                .rejected(.capacity(resource: resource, actual: limit + 1, limit: limit)))
        }
    }

    func testTotalFactCapRejectsBeforePairingOrReturningAnyPrefix() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.clocks = Array(repeating: fixture.batch.clocks[0], count: 8)
        fixture.batch.epochs = Array(repeating: fixture.batch.epochs[0], count: 64)
        fixture.batch.attempts = Array(repeating: fixture.batch.attempts[0], count: 8192)
        fixture.batch.events = Array(repeating: fixture.batch.events[0], count: 16384)
        fixture.batch.dispositions = Array(repeating: fixture.batch.dispositions[0], count: 8192)
        fixture.batch.displays = Array(repeating: fixture.batch.displays[0], count: 16384)
        fixture.batch.receipts = Array(repeating: fixture.batch.receipts[0], count: 8192)
        fixture.batch.inputs = Array(repeating: fixture.batch.inputs[0], count: 8192)
        fixture.batch.coverage.missing = Array(repeating: displayFactSpan(50, 60), count: 64)
        XCTAssertEqual(
            DisplayFacts.check(fixture.batch),
            .rejected(.capacity(resource: .total, actual: 65673, limit: 65536)))
    }

    func testDuplicateClockEpochRequestInputAndDisplayIdentitiesRejectWholeBatch() throws {
        for variant in 0..<5 {
            var fixture = NativeDisplayFactFixture()
            let expected: DisplayFacts.Rejection
            switch variant {
            case 0:
                fixture.batch.clocks.append(fixture.batch.clocks[0])
                expected = .duplicateClock(1)
            case 1:
                var epoch = fixture.batch.epochs[0]
                epoch.id = displayFactID(5)
                fixture.batch.epochs.append(epoch)
                expected = .duplicateEpoch(10)
            case 2:
                var attempt = fixture.batch.attempts[0]
                attempt.id = displayFactID(5)
                fixture.batch.attempts.append(attempt)
                expected = .duplicateRequest(attempt.request)
            case 3:
                var input = fixture.batch.inputs[0]
                input.id = displayFactID(5)
                fixture.batch.inputs.append(input)
                expected = .duplicateInput(input.input)
            default:
                var display = fixture.batch.displays[0]
                display.id = displayFactID(5, source: 2)
                fixture.batch.displays.append(display)
                expected = .duplicateDisplay(start: display.start, index: 0)
            }
            XCTAssertEqual(DisplayFacts.check(fixture.batch), .rejected(expected))
        }
    }

    func testDuplicateSourceFactAcrossKindsOrIdenticalRowsIsNotDeduplicated() throws {
        var crossKind = NativeDisplayFactFixture()
        crossKind.batch.receipts[0].id = crossKind.batch.events[0].id
        XCTAssertEqual(
            DisplayFacts.check(crossKind.batch), .rejected(.duplicateFact(displayFactID(1, source: 2))))

        var identical = NativeDisplayFactFixture()
        identical.batch.dispositions.append(identical.batch.dispositions[0])
        XCTAssertEqual(
            DisplayFacts.check(identical.batch), .rejected(.duplicateFact(displayFactID(3, source: 2))))
    }

    func testDistinctNormalizedSubfactsCanShareRecordOrdinal() throws {
        var fixture = NativeDisplayFactFixture()
        var extra = fixture.batch.displays[0]
        extra.id.part = 1
        extra.index = 1
        fixture.batch.displays.append(extra)
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertEqual(
            result.attempts[0].displayFactIDs,
            [
                displayFactID(4, source: 2), displayFactID(4, source: 2, part: 1),
            ])
    }

    func testIssueCapacityRejectsInsteadOfReturningAValidPrefix() throws {
        var fixture = NativeDisplayFactFixture()
        let prototype = fixture.batch.receipts[0]
        fixture.removeAllWork()
        fixture.batch.receipts = (0..<1025).map { index in
            var receipt = prototype
            receipt.id = displayFactID(UInt64(index) + 100)
            return receipt
        }
        let original = fixture.batch
        XCTAssertEqual(
            DisplayFacts.check(fixture.batch),
            .rejected(.capacity(resource: .issues, actual: 1025, limit: 1024)))
        XCTAssertEqual(fixture.batch, original)
    }

    func testInputRosterBoundaryRetainsAllFactsWithoutSilentDrops() throws {
        var fixture = NativeDisplayFactFixture()
        let prototype = fixture.batch.inputs[0]
        fixture.removeAllWork()
        fixture.batch.inputs = (0..<8192).map { index in
            var input = prototype
            input.id = displayFactID(UInt64(index))
            input.input.nativeSequence = UInt64(index)
            input.effect = .ignored
            return input
        }
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .consistentSuppliedFacts)
        XCTAssertEqual(result.inputs.count, 8192)
        XCTAssertEqual(result.inputs.first?.input.nativeSequence, 0)
        XCTAssertEqual(result.inputs.last?.input.nativeSequence, 8191)
    }

    func testNoPresentReceiptStillRequiresPreparationBeforeCompletion() throws {
        var fixture = NativeDisplayFactFixture()
        fixture.batch.attempts[0].presentation = .notCalled(.commandRejected)
        fixture.batch.attempts[0].frame = nil
        fixture.batch.receipts[0].frame = nil
        fixture.batch.receipts[0].completed = displayFactStamp(5)
        fixture.batch.events = []
        fixture.batch.dispositions = []
        fixture.batch.displays = []
        fixture.batch.inputs[0].effect = .ignored
        let result = try report(fixture.batch)
        assertIssue(result, .receiptOrder, severity: .contradictory)
        XCTAssertEqual(result.attempts[0].apiResult, .notCalled(.commandRejected))
        XCTAssertEqual(result.attempts[0].join, .notApplicable)
        XCTAssertNil(result.attempts[0].receiptFactID)
    }

    func testUnstampedDispositionMustShareStartOriginAndFrequency() throws {
        for variant in 0..<2 {
            var fixture = NativeDisplayFactFixture()
            var other = fixture.batch.clocks[1]
            other.id = 3
            if variant == 0 { other.origin = 8 } else { other.frequency = 9_999_999 }
            fixture.batch.clocks.append(other)
            fixture.batch.dispositions[0].id.source = 3
            let result = try report(fixture.batch)
            assertIssue(result, .clockMismatch, severity: .contradictory)
            XCTAssertEqual(result.summary, .contradictorySuppliedFacts)
            XCTAssertNil(result.attempts[0].disposition)
        }
    }

    func testUnstampedDispositionMissingBasisCannotRetainAcceptedLink() throws {
        for variant in 0..<3 {
            var fixture = NativeDisplayFactFixture()
            var other = fixture.batch.clocks[1]
            other.id = 3
            switch variant {
            case 0: other.origin = nil
            case 1: other.frequency = nil
            default: other.source = .etl(clockType: 1, rawTimestamps: nil)
            }
            fixture.batch.clocks.append(other)
            fixture.batch.dispositions[0].id.source = 3
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
            assertIssue(result, .clockMetadataMissing)
            XCTAssertFalse(result.issues.contains { $0.code == .clockMismatch })
            XCTAssertNil(result.attempts[0].disposition)
            XCTAssertEqual(
                result.attempts[0].join, .matched(start: displayFactID(1, source: 2), stop: displayFactID(2, source: 2))
            )
        }
    }

    func testCoverageHoleMustShareRequestedOriginAndFrequency() throws {
        for variant in 0..<2 {
            var fixture = NativeDisplayFactFixture()
            var other = fixture.batch.clocks[1]
            other.id = 3
            if variant == 0 { other.origin = 8 } else { other.frequency = 9_999_999 }
            fixture.batch.clocks.append(other)
            fixture.batch.coverage.missing = [displayFactSpan(50, 60, clock: 3)]
            let result = try report(fixture.batch)
            assertIssue(result, .clockMismatch, severity: .contradictory)
            assertIssue(result, .coverageHole, severity: .incomplete)
            XCTAssertEqual(result.summary, .contradictorySuppliedFacts)
        }
    }

    func testCoverageHoleMissingBasisStaysIncompleteWithoutRawComparison() throws {
        var fixture = NativeDisplayFactFixture()
        var other = fixture.batch.clocks[1]
        other.id = 3
        other.origin = nil
        fixture.batch.clocks.append(other)
        fixture.batch.coverage.missing = [displayFactSpan(50, 60, clock: 3)]
        let result = try report(fixture.batch)
        XCTAssertEqual(result.summary, .incompleteSuppliedFacts)
        assertIssue(result, .clockMetadataMissing)
        assertIssue(result, .coverageHole)
        XCTAssertFalse(result.issues.contains { $0.code == .clockMismatch })
    }

    func testSameBasisDistinctSourceSupportsDispositionAndCoverageHole() throws {
        var fixture = NativeDisplayFactFixture()
        var other = fixture.batch.clocks[1]
        other.id = 3
        fixture.batch.clocks.append(other)
        fixture.batch.dispositions[0].id.source = 3
        let linked = try report(fixture.batch)
        XCTAssertEqual(linked.summary, .consistentSuppliedFacts)
        XCTAssertEqual(linked.attempts[0].disposition, .displayed)
        fixture.batch.coverage.missing = [displayFactSpan(50, 60, clock: 3)]
        let withHole = try report(fixture.batch)
        XCTAssertEqual(withHole.summary, .incompleteSuppliedFacts)
        XCTAssertEqual(withHole.attempts[0].disposition, .displayed)
        assertIssue(withHole, .coverageHole)
        XCTAssertFalse(withHole.issues.contains { $0.code == .clockMismatch || $0.code == .clockMetadataMissing })
    }

    func testMultipleOrphanDispositionsKeepMissingAndMultiplicityIssues() throws {
        var fixture = NativeDisplayFactFixture()
        var first = fixture.batch.dispositions[0]
        first.state = .discarded
        var second = first
        second.id = displayFactID(5, source: 2)
        fixture.removeAllWork()
        fixture.batch.dispositions = [first, second]
        for _ in 0..<2 {
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .contradictorySuppliedFacts)
            XCTAssertEqual(result.issues.filter { $0.code == .dispositionMultiple }.count, 1)
            let missing = result.issues.filter { $0.code == .referenceMissing }.compactMap(\.fact)
            XCTAssertEqual(Set(missing), Set([first.id, second.id]))
            XCTAssertTrue(result.attempts.isEmpty)
            fixture.batch.dispositions.reverse()
        }
    }

    func testMultipleOrphanReceiptsKeepMissingAndMultiplicityIssues() throws {
        var fixture = NativeDisplayFactFixture()
        let first = fixture.batch.receipts[0]
        var second = first
        second.id = displayFactID(5)
        fixture.removeAllWork()
        fixture.batch.receipts = [first, second]
        for _ in 0..<2 {
            let result = try report(fixture.batch)
            XCTAssertEqual(result.summary, .contradictorySuppliedFacts)
            XCTAssertEqual(result.issues.filter { $0.code == .receiptMultiple }.count, 1)
            let missing = result.issues.filter { $0.code == .referenceMissing }.compactMap(\.fact)
            XCTAssertEqual(Set(missing), Set([first.id, second.id]))
            XCTAssertTrue(result.attempts.isEmpty)
            fixture.batch.receipts.reverse()
        }
    }
}
