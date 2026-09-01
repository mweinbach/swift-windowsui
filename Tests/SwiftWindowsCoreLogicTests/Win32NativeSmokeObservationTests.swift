import Dispatch
import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform

/// Recorder value and capacity checks only; these rows are not native qualification evidence.
/// Every semaphore check uses an immediate deadline and consumes only an existing signal.
@MainActor
final class Win32NativeSmokeObservationTests: XCTestCase {
    private let runID = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
    private let windowKey = NativeWindowKey(
        windowID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        lifetimeID: UUID(uuidString: "abcdef01-2345-6789-abcd-ef0123456789")!)
    private let requestID = NativeWindowRequestID(UUID(uuidString: "fedcba98-7654-3210-fedc-ba9876543210")!)

    private func recordFullRow(_ observation: Win32NativeSmokeObservation) -> Bool {
        observation.record(
            .fixtureStarted, windowKey: windowKey, requestID: requestID,
            generation: UInt64.max, deviceGeneration: UInt64.max - 1, frameNumber: UInt64.max - 2,
            nativeSequence: UInt64.max - 3, revision: UInt64.max - 4,
            value: Int64.min, auxiliary: UInt64.max - 5, flags: UInt32.max)
    }

    /// Literal wire expectations pin field names, order, UUID spellings and integer precision.
    /// Only the ordinal and metadata sampled by record() vary between full rows.
    private func expectedFullLine(ordinal: UInt64, uptimeNanoseconds: UInt64, threadID: UInt32) -> String {
        "{\"runID\":\"01234567-89AB-CDEF-0123-456789ABCDEF\",\"ordinal\":\(ordinal),\"kind\":0,"
            + "\"uptimeNanoseconds\":\(uptimeNanoseconds),\"threadID\":\(threadID),"
            + "\"windowID\":\"11111111-2222-3333-4444-555555555555\","
            + "\"lifetimeID\":\"ABCDEF01-2345-6789-ABCD-EF0123456789\","
            + "\"requestID\":\"FEDCBA98-7654-3210-FEDC-BA9876543210\","
            + "\"generation\":18446744073709551615,\"deviceGeneration\":18446744073709551614,"
            + "\"frameNumber\":18446744073709551613,\"nativeSequence\":18446744073709551612,"
            + "\"revision\":18446744073709551611,\"value\":-9223372036854775808,"
            + "\"auxiliary\":18446744073709551610,\"flags\":4294967295}\n"
    }

    func testEmptySnapshotAndCaptureHaveNoRecordsCountersOrActivity() async {
        let observation = Win32NativeSmokeObservation(runID: runID)
        let snapshot = observation.snapshot()
        let capture = observation.capture()

        XCTAssertEqual(observation.runID, runID)
        XCTAssertEqual(snapshot.runID, runID)
        XCTAssertEqual(snapshot.recordCount, 0)
        XCTAssertEqual(snapshot.encodedBytes, 0)
        XCTAssertFalse(snapshot.overflowed)
        XCTAssertEqual(capture.snapshot.runID, runID)
        XCTAssertEqual(capture.snapshot.recordCount, 0)
        XCTAssertEqual(capture.snapshot.encodedBytes, 0)
        XCTAssertFalse(capture.snapshot.overflowed)
        XCTAssertEqual(capture.trace, Data())
        for kind in Win32NativeSmokeEventKind.allCases {
            XCTAssertEqual(snapshot.count(kind), 0)
            XCTAssertNil(snapshot.last(kind))
            XCTAssertEqual(capture.snapshot.count(kind), 0)
            XCTAssertNil(capture.snapshot.last(kind))
        }
        XCTAssertFalse(observation.waitForActivity(until: .now()))
    }

    func testCountsAndLastRecordsRemainSeparatedByKind() async throws {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertTrue(observation.record(.ingressQueued, nativeSequence: 7, value: 11))
        XCTAssertTrue(observation.record(.nativeTurnBegan, value: 16))
        XCTAssertTrue(observation.record(.ingressQueued, nativeSequence: 9, value: 22))

        let snapshot = observation.snapshot()
        let queued = try XCTUnwrap(snapshot.last(.ingressQueued))
        let turn = try XCTUnwrap(snapshot.last(.nativeTurnBegan))
        XCTAssertEqual(snapshot.recordCount, 3)
        XCTAssertEqual(snapshot.count(.ingressQueued), 2)
        XCTAssertEqual(snapshot.count(.nativeTurnBegan), 1)
        XCTAssertEqual(queued.ordinal, 3)
        XCTAssertEqual(queued.kind, .ingressQueued)
        XCTAssertEqual(queued.nativeSequence, 9)
        XCTAssertEqual(queued.value, 22)
        XCTAssertEqual(turn.ordinal, 2)
        XCTAssertEqual(turn.kind, .nativeTurnBegan)
        XCTAssertEqual(turn.value, 16)
        XCTAssertNil(turn.nativeSequence)
        XCTAssertNil(turn.windowKey)
        XCTAssertNil(turn.requestID)
        XCTAssertEqual(turn.flags, 0)
        for kind in Win32NativeSmokeEventKind.allCases where kind != .ingressQueued && kind != .nativeTurnBegan {
            XCTAssertEqual(snapshot.count(kind), 0)
            XCTAssertNil(snapshot.last(kind))
        }
    }

    func testProbeReturnCounterCountsOnlyAdmittedTaggedReturnsAndIsNotAUniquenessClaim() async {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertEqual(observation.snapshot().deliveredProbeCount, 0)
        XCTAssertTrue(observation.record(.ingressReceiveBegan, requestID: requestID))
        XCTAssertTrue(observation.record(.ingressReceiveReturned))
        XCTAssertEqual(observation.snapshot().deliveredProbeCount, 0)
        XCTAssertTrue(observation.record(.ingressReceiveReturned, requestID: requestID))
        let earlier = observation.capture()
        XCTAssertEqual(earlier.snapshot.deliveredProbeCount, 1)
        XCTAssertTrue(observation.record(.ingressReceiveReturned, requestID: requestID))
        XCTAssertEqual(observation.snapshot().deliveredProbeCount, 2)
        XCTAssertEqual(earlier.snapshot.deliveredProbeCount, 1)
        XCTAssertFalse(observation.record(.ingressReceiveReturned, requestID: requestID, nativeStartedAtSeconds: .nan))
        XCTAssertEqual(observation.capture().snapshot.deliveredProbeCount, 2)
    }

    func testFullIdentifiersAndIntegerExtremesHaveExactNDJSONEncoding() async throws {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertTrue(recordFullRow(observation))
        let full = try XCTUnwrap(observation.snapshot().last(.fixtureStarted))
        XCTAssertEqual(full.windowKey, windowKey)
        XCTAssertEqual(full.requestID, requestID)
        XCTAssertEqual(full.generation, UInt64.max)
        XCTAssertEqual(full.deviceGeneration, UInt64.max - 1)
        XCTAssertEqual(full.frameNumber, UInt64.max - 2)
        XCTAssertEqual(full.nativeSequence, UInt64.max - 3)
        XCTAssertEqual(full.revision, UInt64.max - 4)
        XCTAssertEqual(full.value, Int64.min)
        XCTAssertEqual(full.auxiliary, UInt64.max - 5)
        XCTAssertEqual(full.flags, UInt32.max)

        XCTAssertTrue(
            observation.record(
                .fixtureFailure, generation: 0, deviceGeneration: 0, frameNumber: 0,
                nativeSequence: 0, revision: 0, value: Int64.max, auxiliary: 0))
        let zero = try XCTUnwrap(observation.snapshot().last(.fixtureFailure))
        let expected =
            expectedFullLine(ordinal: 1, uptimeNanoseconds: full.uptimeNanoseconds, threadID: full.threadID)
            + "{\"runID\":\"01234567-89AB-CDEF-0123-456789ABCDEF\",\"ordinal\":2,\"kind\":1,"
            + "\"uptimeNanoseconds\":\(zero.uptimeNanoseconds),\"threadID\":\(zero.threadID),"
            + "\"generation\":0,\"deviceGeneration\":0,\"frameNumber\":0,\"nativeSequence\":0,"
            + "\"revision\":0,\"value\":9223372036854775807,\"auxiliary\":0,\"flags\":0}\n"
        let capture = observation.capture()
        XCTAssertEqual(capture.trace, Data(expected.utf8))
        XCTAssertEqual(capture.snapshot.recordCount, 2)
        XCTAssertEqual(capture.snapshot.encodedBytes, expected.utf8.count)
        XCTAssertFalse(capture.snapshot.overflowed)
    }

    func testEarlierSnapshotAndCaptureStayImmutableAfterLaterRecords() async throws {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertTrue(observation.record(.fixtureStarted, value: 7))
        let snapshot = observation.snapshot()
        let capture = observation.capture()
        let first = try XCTUnwrap(snapshot.last(.fixtureStarted))
        let expected =
            "{\"runID\":\"01234567-89AB-CDEF-0123-456789ABCDEF\",\"ordinal\":1,\"kind\":0,"
            + "\"uptimeNanoseconds\":\(first.uptimeNanoseconds),\"threadID\":\(first.threadID),"
            + "\"value\":7,\"flags\":0}\n"

        XCTAssertTrue(observation.record(.fixtureStarted, value: 8))
        XCTAssertTrue(observation.record(.hostReady))
        let later = observation.capture()
        XCTAssertEqual(later.snapshot.recordCount, 3)
        XCTAssertEqual(later.snapshot.count(.fixtureStarted), 2)
        XCTAssertEqual(later.snapshot.last(.fixtureStarted)?.value, 8)
        XCTAssertEqual(later.snapshot.last(.hostReady)?.ordinal, 3)
        XCTAssertGreaterThan(later.snapshot.encodedBytes, expected.utf8.count)
        XCTAssertTrue(later.trace.starts(with: Data(expected.utf8)))

        for earlier in [snapshot, capture.snapshot] {
            XCTAssertEqual(earlier.runID, runID)
            XCTAssertEqual(earlier.recordCount, 1)
            XCTAssertEqual(earlier.encodedBytes, expected.utf8.count)
            XCTAssertFalse(earlier.overflowed)
            XCTAssertEqual(earlier.count(.fixtureStarted), 1)
            XCTAssertEqual(earlier.last(.fixtureStarted), first)
            XCTAssertEqual(earlier.count(.hostReady), 0)
            XCTAssertNil(earlier.last(.hostReady))
        }
        XCTAssertEqual(capture.trace, Data(expected.utf8))
    }

    func testEncodedBytesIncludeEveryUTF8RowAndItsNewline() async throws {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertEqual(Win32NativeSmokeObservation.maximumEncodedBytes, 1_048_576)
        var previousBytes = 0
        for index in 0..<17 {
            XCTAssertTrue(
                observation.record(
                    .nativeQueueSnapshot, generation: index.isMultiple(of: 2) ? UInt64.max : nil,
                    nativeSequence: UInt64(index), value: -Int64(index), flags: UInt32(index)))
            let capture = observation.capture()
            let rows = capture.trace.split(separator: UInt8(0x0A), omittingEmptySubsequences: false)
            let lastRow = try XCTUnwrap(rows.dropLast().last)
            XCTAssertEqual(rows.count, index + 2)
            XCTAssertEqual(rows.last?.isEmpty, true)
            XCTAssertFalse(lastRow.isEmpty)
            XCTAssertEqual(capture.snapshot.recordCount, index + 1)
            XCTAssertEqual(capture.snapshot.encodedBytes, previousBytes + lastRow.count + 1)
            XCTAssertEqual(capture.snapshot.encodedBytes, capture.trace.count)
            XCTAssertLessThanOrEqual(capture.trace.count, 1_048_576)
            XCTAssertFalse(capture.snapshot.overflowed)
            previousBytes = capture.trace.count
        }
    }

    func testMinimalRowsReachTheFixed4096RecordLimitBeforeTheByteLimit() async {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertEqual(Win32NativeSmokeObservation.maximumRecords, 4_096)
        for _ in 0..<4_096 { XCTAssertTrue(observation.record(.fixtureStarted)) }

        let full = observation.snapshot()
        XCTAssertEqual(full.recordCount, 4_096)
        XCTAssertEqual(full.count(.fixtureStarted), 4_096)
        XCTAssertEqual(full.last(.fixtureStarted)?.ordinal, 4_096)
        XCTAssertLessThan(full.encodedBytes, 1_048_576)
        XCTAssertFalse(full.overflowed)
        XCTAssertFalse(observation.record(.fixtureFailure))

        let rejected = observation.capture()
        XCTAssertTrue(rejected.snapshot.overflowed)
        XCTAssertEqual(rejected.snapshot.recordCount, 4_096)
        XCTAssertEqual(rejected.snapshot.encodedBytes, full.encodedBytes)
        XCTAssertEqual(rejected.trace.count, full.encodedBytes)
        XCTAssertEqual(rejected.trace.split(separator: UInt8(0x0A)).count, 4_096)
        XCTAssertEqual(rejected.snapshot.count(.fixtureFailure), 0)
        XCTAssertNil(rejected.snapshot.last(.fixtureFailure))
    }

    func testFullRowsReachTheByteLimitBefore4096Records() async {
        let observation = Win32NativeSmokeObservation(runID: runID)
        var accepted = 0
        var rejected = false
        for _ in 0..<4_096 {
            guard recordFullRow(observation) else {
                rejected = true
                break
            }
            accepted += 1
        }

        let capture = observation.capture()
        XCTAssertTrue(rejected)
        XCTAssertTrue(capture.snapshot.overflowed)
        XCTAssertGreaterThan(accepted, 0)
        XCTAssertLessThan(accepted, 4_096)
        XCTAssertEqual(capture.snapshot.recordCount, accepted)
        XCTAssertEqual(capture.snapshot.count(.fixtureStarted), UInt64(accepted))
        XCTAssertEqual(capture.snapshot.last(.fixtureStarted)?.ordinal, UInt64(accepted))
        XCTAssertEqual(capture.snapshot.encodedBytes, capture.trace.count)
        XCTAssertLessThanOrEqual(capture.trace.count, 1_048_576)
        XCTAssertEqual(capture.trace.split(separator: UInt8(0x0A)).count, accepted)
        // The next row cannot have more digits than these metadata maxima. A
        // rejection far below the byte cap therefore fails this independent bound.
        let largestNextRow = expectedFullLine(
            ordinal: UInt64(accepted) + 1, uptimeNanoseconds: UInt64.max, threadID: UInt32.max)
        XCTAssertGreaterThan(capture.trace.count + largestNextRow.utf8.count, 1_048_576)
    }

    func testOverflowIsStickySignalsOnceAndNeverGrowsRecordsOrCounters() async {
        let observation = Win32NativeSmokeObservation(runID: runID)
        for _ in 0..<4_096 {
            XCTAssertTrue(observation.record(.fixtureStarted))
            XCTAssertTrue(observation.waitForActivity(until: .now()))
        }
        XCTAssertFalse(observation.waitForActivity(until: .now()))
        let before = observation.capture()
        XCTAssertFalse(before.snapshot.overflowed)

        XCTAssertFalse(observation.record(.fixtureFailure))
        XCTAssertTrue(observation.waitForActivity(until: .now()))
        XCTAssertFalse(observation.waitForActivity(until: .now()))
        for kind in [Win32NativeSmokeEventKind.fixtureStarted, .frameSubmitted, .ingressQueued] {
            XCTAssertFalse(observation.record(kind, value: Int64.max))
            XCTAssertFalse(observation.waitForActivity(until: .now()))
        }

        let after = observation.capture()
        XCTAssertTrue(after.snapshot.overflowed)
        XCTAssertEqual(after.snapshot.recordCount, before.snapshot.recordCount)
        XCTAssertEqual(after.snapshot.encodedBytes, before.snapshot.encodedBytes)
        XCTAssertEqual(after.trace, before.trace)
        for kind in Win32NativeSmokeEventKind.allCases {
            XCTAssertEqual(after.snapshot.count(kind), before.snapshot.count(kind))
            XCTAssertEqual(after.snapshot.last(kind), before.snapshot.last(kind))
        }
    }

    func testImmediateActivityWaitConsumesExactlyTheRecordedSignals() async {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertFalse(observation.waitForActivity(until: .now()))
        XCTAssertTrue(observation.record(.fixtureStarted))
        XCTAssertTrue(observation.record(.hostReady))
        _ = observation.snapshot()
        _ = observation.capture()
        XCTAssertTrue(observation.waitForActivity(until: .now()))
        XCTAssertTrue(observation.waitForActivity(until: .now()))
        XCTAssertFalse(observation.waitForActivity(until: .now()))

        XCTAssertTrue(observation.record(.fixtureFinished))
        XCTAssertTrue(observation.waitForActivity(until: .now()))
        XCTAssertFalse(observation.waitForActivity(until: .now()))
        XCTAssertEqual(observation.snapshot().recordCount, 3)
    }

    func testFiniteTimingAndAttachmentIdentityRoundTripExactlyWithoutEpochArithmetic() async throws {
        let observation = Win32NativeSmokeObservation(runID: runID)
        let attachmentID = NativeWindowAttachmentID(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!)
        let samples: [(started: Double, completed: Double)] = [
            (-1.25, 2.5),
            (Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude),
            (Double.leastNonzeroMagnitude, -Double.leastNonzeroMagnitude),
            (-0.0, 0.0),
        ]

        for (index, sample) in samples.enumerated() {
            XCTAssertTrue(
                observation.record(
                    .fixtureStarted, requestID: requestID, attachmentID: attachmentID,
                    generation: 11, deviceGeneration: 22, frameNumber: 7,
                    nativeStartedAtSeconds: sample.started, nativeCompletedAtSeconds: sample.completed,
                    queueDepth: 3))
            let capture = observation.capture()
            let stored = try XCTUnwrap(capture.snapshot.last(.fixtureStarted))
            XCTAssertEqual(stored.requestID, requestID)
            XCTAssertEqual(stored.attachmentID, attachmentID)
            XCTAssertEqual(try XCTUnwrap(stored.nativeStartedAtSeconds).bitPattern, sample.started.bitPattern)
            XCTAssertEqual(try XCTUnwrap(stored.nativeCompletedAtSeconds).bitPattern, sample.completed.bitPattern)
            let lines = capture.trace.split(separator: UInt8(0x0A))
            XCTAssertEqual(lines.count, index + 1)
            let line = try XCTUnwrap(lines.last)
            let decoded = try JSONDecoder().decode(SmokeObservationTimingFields.self, from: Data(line))
            XCTAssertEqual(decoded.attachmentID, attachmentID.rawValue)
            XCTAssertEqual(try XCTUnwrap(decoded.nativeStartedAtSeconds).bitPattern, sample.started.bitPattern)
            XCTAssertEqual(try XCTUnwrap(decoded.nativeCompletedAtSeconds).bitPattern, sample.completed.bitPattern)
            XCTAssertEqual(capture.snapshot.recordCount, index + 1)
            XCTAssertEqual(capture.snapshot.encodedBytes, capture.trace.count)
            XCTAssertFalse(capture.snapshot.hasNonfiniteTiming)
            XCTAssertFalse(capture.snapshot.overflowed)
            XCTAssertFalse(capture.snapshot.isInvalid)

            if index == 0 {
                let expected =
                    "{\"runID\":\"01234567-89AB-CDEF-0123-456789ABCDEF\",\"ordinal\":1,\"kind\":0,"
                    + "\"uptimeNanoseconds\":\(stored.uptimeNanoseconds),\"threadID\":\(stored.threadID),"
                    + "\"requestID\":\"FEDCBA98-7654-3210-FEDC-BA9876543210\","
                    + "\"attachmentID\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\","
                    + "\"generation\":11,\"deviceGeneration\":22,\"frameNumber\":7,"
                    + "\"nativeStartedAtSeconds\":-1.25,\"nativeCompletedAtSeconds\":2.5,"
                    + "\"queueDepth\":3,\"flags\":0}\n"
                XCTAssertEqual(capture.trace, Data(expected.utf8))
            }
        }
    }

    func testNilTimingFieldsAreOmittedIndependently() async throws {
        let observation = Win32NativeSmokeObservation(runID: runID)
        let samples: [(started: Double?, completed: Double?, fields: String)] = [
            (nil, nil, ""),
            (-0.25, nil, ",\"nativeStartedAtSeconds\":-0.25"),
            (nil, 4.5, ",\"nativeCompletedAtSeconds\":4.5"),
        ]
        var expected = ""
        for (index, sample) in samples.enumerated() {
            XCTAssertTrue(
                observation.record(
                    .fixtureStarted, nativeStartedAtSeconds: sample.started,
                    nativeCompletedAtSeconds: sample.completed))
            let capture = observation.capture()
            let stored = try XCTUnwrap(capture.snapshot.last(.fixtureStarted))
            XCTAssertEqual(stored.nativeStartedAtSeconds, sample.started)
            XCTAssertEqual(stored.nativeCompletedAtSeconds, sample.completed)
            XCTAssertNil(stored.attachmentID)
            expected +=
                "{\"runID\":\"01234567-89AB-CDEF-0123-456789ABCDEF\",\"ordinal\":\(index + 1),\"kind\":0,"
                + "\"uptimeNanoseconds\":\(stored.uptimeNanoseconds),\"threadID\":\(stored.threadID)"
                + sample.fields + ",\"flags\":0}\n"
            XCTAssertEqual(capture.trace, Data(expected.utf8))
            XCTAssertEqual(capture.snapshot.encodedBytes, expected.utf8.count)
            XCTAssertFalse(capture.snapshot.hasNonfiniteTiming)
            XCTAssertFalse(capture.snapshot.isInvalid)
        }
    }

    func testNonfiniteTimingInEitherFieldProducesNoRowAndOneTerminalSignal() async {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            for invalidatesStart in [true, false] {
                let observation = Win32NativeSmokeObservation(runID: runID)
                XCTAssertFalse(observation.waitForActivity(until: .now()))
                XCTAssertFalse(
                    observation.record(
                        .fixtureStarted, nativeStartedAtSeconds: invalidatesStart ? invalid : nil,
                        nativeCompletedAtSeconds: invalidatesStart ? nil : invalid))
                XCTAssertTrue(observation.waitForActivity(until: .now()))
                XCTAssertFalse(observation.waitForActivity(until: .now()))
                XCTAssertFalse(
                    observation.record(
                        .hostReady, nativeStartedAtSeconds: 0, nativeCompletedAtSeconds: 1))
                XCTAssertFalse(
                    observation.record(
                        .fixtureFailure, nativeStartedAtSeconds: Double.nan,
                        nativeCompletedAtSeconds: Double.infinity))
                XCTAssertFalse(observation.waitForActivity(until: .now()))

                let capture = observation.capture()
                XCTAssertTrue(capture.snapshot.hasNonfiniteTiming)
                XCTAssertTrue(capture.snapshot.isInvalid)
                XCTAssertFalse(capture.snapshot.overflowed)
                XCTAssertEqual(capture.snapshot.runID, runID)
                XCTAssertEqual(capture.snapshot.recordCount, 0)
                XCTAssertEqual(capture.snapshot.encodedBytes, 0)
                XCTAssertEqual(capture.trace, Data())
                for kind in Win32NativeSmokeEventKind.allCases {
                    XCTAssertEqual(capture.snapshot.count(kind), 0)
                    XCTAssertNil(capture.snapshot.last(kind))
                }
            }
        }
    }

    func testNonfiniteTimingPreservesAcceptedTraceCountersAndEarlierSnapshots() async {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            for invalidatesStart in [true, false] {
                let observation = Win32NativeSmokeObservation(runID: runID)
                XCTAssertTrue(recordFullRow(observation))
                XCTAssertTrue(
                    observation.record(
                        .frameReplyConsumed, nativeStartedAtSeconds: -0.5, nativeCompletedAtSeconds: 1.25))
                XCTAssertTrue(observation.waitForActivity(until: .now()))
                XCTAssertTrue(observation.waitForActivity(until: .now()))
                XCTAssertFalse(observation.waitForActivity(until: .now()))
                let beforeSnapshot = observation.snapshot()
                let before = observation.capture()

                XCTAssertFalse(
                    observation.record(
                        .fixtureStarted, nativeStartedAtSeconds: invalidatesStart ? invalid : 0.125,
                        nativeCompletedAtSeconds: invalidatesStart ? 0.5 : invalid))
                XCTAssertTrue(observation.waitForActivity(until: .now()))
                XCTAssertFalse(observation.waitForActivity(until: .now()))
                XCTAssertFalse(observation.record(.fixtureFinished))
                XCTAssertFalse(
                    observation.record(
                        .fixtureStarted, nativeStartedAtSeconds: 2, nativeCompletedAtSeconds: 3))
                XCTAssertFalse(observation.waitForActivity(until: .now()))

                let afterSnapshot = observation.snapshot()
                let after = observation.capture()
                for snapshot in [afterSnapshot, after.snapshot] {
                    XCTAssertTrue(snapshot.hasNonfiniteTiming)
                    XCTAssertTrue(snapshot.isInvalid)
                    XCTAssertFalse(snapshot.overflowed)
                    XCTAssertEqual(snapshot.recordCount, 2)
                    XCTAssertEqual(snapshot.encodedBytes, before.snapshot.encodedBytes)
                    for kind in Win32NativeSmokeEventKind.allCases {
                        XCTAssertEqual(snapshot.count(kind), before.snapshot.count(kind))
                        XCTAssertEqual(snapshot.last(kind), before.snapshot.last(kind))
                    }
                }
                XCTAssertEqual(after.trace, before.trace)
                XCTAssertEqual(after.trace.count, after.snapshot.encodedBytes)
                for earlier in [beforeSnapshot, before.snapshot] {
                    XCTAssertFalse(earlier.hasNonfiniteTiming)
                    XCTAssertFalse(earlier.isInvalid)
                    XCTAssertFalse(earlier.overflowed)
                    XCTAssertEqual(earlier.recordCount, 2)
                }
            }
        }
    }

    func testRecordOverflowIsInvalidWithoutClaimingNonfiniteTiming() async {
        let observation = Win32NativeSmokeObservation(runID: runID)
        for _ in 0..<4_096 { XCTAssertTrue(observation.record(.fixtureStarted)) }
        let before = observation.snapshot()
        XCTAssertFalse(before.overflowed)
        XCTAssertFalse(before.hasNonfiniteTiming)
        XCTAssertFalse(before.isInvalid)

        XCTAssertFalse(observation.record(.fixtureFinished))
        let after = observation.snapshot()
        XCTAssertTrue(after.overflowed)
        XCTAssertFalse(after.hasNonfiniteTiming)
        XCTAssertTrue(after.isInvalid)
        XCTAssertEqual(after.recordCount, before.recordCount)
        XCTAssertEqual(after.encodedBytes, before.encodedBytes)
    }
}

private struct SmokeObservationTimingFields: Decodable, Sendable {
    let attachmentID: UUID?
    let nativeStartedAtSeconds: Double?
    let nativeCompletedAtSeconds: Double?
}
