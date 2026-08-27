import Foundation
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class LiveGPUFrameTimingReportTests: XCTestCase {
    private static let epoch = 1_000.0

    private func id(_ frame: UInt64, generation: UInt64 = 7) -> BackendFrameID {
        BackendFrameID(deviceGeneration: generation, frameNumber: frame)
    }

    private func sample(
        _ frameID: BackendFrameID?,
        at elapsed: Double = 2,
        outcome: BackendFrameSubmissionOutcome? = .submitted,
        status: GPUFrameTimingStatus = .pending,
        software: Bool? = false,
        animating: Bool = false
    ) -> LiveFrameSample {
        var value = LiveFrameSample(
            presentedAt: Self.epoch + elapsed,
            totalSeconds: 0.01,
            sceneBuildSeconds: 0.001,
            bindSeconds: 0.0002,
            backendSubmitSeconds: 0.0003,
            backendPresentSeconds: 0.0004,
            submitAndPresentSeconds: 0.0007,
            didRebuildScene: false,
            nodeReplayCount: 0,
            primitiveCount: 1,
            hadActiveAnimations: animating,
            backend: .scene,
            atlasUploadedByteCount: 0,
            drawCallCount: 1,
            drawnInstanceCount: 1,
            visitedNodeCount: 0)
        value.backendFrameSubmission = outcome.map {
            BackendFrameSubmission(id: frameID, outcome: $0, gpuTimingStatus: status)
        }
        value.gpuTimingAdapterIsSoftware = software
        return value
    }

    private func valid(_ frameID: BackendFrameID, ms: Double) -> GPUFrameTimingResult {
        GPUFrameTimingResult(frameID: frameID, status: .valid, elapsedSeconds: ms / 1_000)
    }

    private func report(
        _ samples: [LiveFrameSample] = [],
        results: [GPUFrameTimingResult] = [],
        diagnostics: GPUFrameTimingDiagnostics? = nil,
        requested: Bool = true,
        initiallySupported: Bool = true,
        capturesMotion: Bool = false,
        warmupSeconds: Double = 1.5
    ) -> LiveGPUFrameTimingReport {
        LiveGPUFrameTimingReport.build(
            samples: samples,
            results: results,
            diagnostics: diagnostics,
            requested: requested,
            initiallySupported: initiallySupported,
            capturesMotion: capturesMotion,
            sessionStartedAt: Self.epoch,
            warmupSeconds: warmupSeconds)
    }

    private func object(_ parent: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(parent[key] as? [String: Any], "Missing object: \(key)")
    }

    private func count(_ parent: [String: Any], _ key: String) throws -> Int {
        try XCTUnwrap(parent[key] as? Int, "Missing count: \(key)")
    }

    private func number(_ parent: [String: Any], _ key: String) throws -> Double {
        try XCTUnwrap(parent[key] as? Double, "Missing number: \(key)")
    }

    private func assertEmpty(_ value: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value["sampleCount"] as? Int, 0, file: file, line: line)
        XCTAssertEqual(value["hasSamples"] as? Bool, false, file: file, line: line)
        for field in ["p50", "p95", "p99", "max", "mean"] {
            XCTAssertTrue(value[field] is NSNull, "\(field) must be null without samples.", file: file, line: line)
        }
    }

    func testDelayedResultsUseIssuingFramesAndIncludeExactWarmupBoundary() async throws {
        let value = report(
            [
                sample(id(1), at: 1, animating: true),
                sample(id(2), at: 1.5, animating: true),
                sample(id(3), at: 2.5),
                sample(id(4), at: 9, animating: true),
            ],
            results: [valid(id(3), ms: 4), valid(id(1), ms: 90), valid(id(2), ms: 2)])

        let frames = try object(value.json, "frameElapsedMs")
        XCTAssertTrue(value.hasHardwareMeasurements)
        XCTAssertEqual(try count(frames, "sampleCount"), 2)
        XCTAssertEqual(try number(frames, "mean"), 3, accuracy: 0.000_001)
        XCTAssertEqual(try number(frames, "max"), 4, accuracy: 0.000_001)
        XCTAssertEqual(try number(object(value.json, "frameElapsedMsWhileAnimating"), "mean"), 2)
        XCTAssertEqual(try number(object(value.json, "frameElapsedMsWhileIdle"), "mean"), 4)
        let join = try object(value.json, "sessionJoin")
        XCTAssertEqual(try count(join, "matchedPreWarmupResultCount"), 1)
        XCTAssertEqual(try count(join, "matchedPostWarmupResultCount"), 2)
        let postWarmup = try object(value.json, "postWarmup")
        XCTAssertEqual(try count(postWarmup, "sampleCount"), 3)
        let statuses = try object(postWarmup, "timingStatusCounts")
        XCTAssertEqual(try count(statuses, "valid"), 2)
        XCTAssertEqual(try count(statuses, "pending"), 1, "No last GPU time is carried into frame 4.")
        let slow = try XCTUnwrap(value.json["slowGPUFrames"] as? [[String: Any]])
        XCTAssertEqual(slow.count, 2)
        XCTAssertEqual(try object(slow[0], "frameID")["frameNumber"] as? String, "3")
        XCTAssertEqual(try number(slow[0], "issuingFrameElapsedSeconds"), 2.5)
        XCTAssertEqual(try number(slow[1], "issuingFrameElapsedSeconds"), 1.5)
        XCTAssertEqual(slow[1]["hadActiveAnimations"] as? Bool, true)
    }

    func testOnlySubmittedKnownHardwareContributesToPrimaryPercentiles() async throws {
        let value = report(
            [
                sample(id(1)),
                sample(id(2), software: true),
                sample(id(3), software: nil),
                sample(id(4), outcome: .offscreen),
                sample(id(5), outcome: .failed),
                sample(id(6), outcome: .skipped),
                sample(id(7), outcome: .occluded),
                sample(id(8), outcome: .aborted),
                sample(nil, outcome: nil),
            ],
            results: (1...8).map { valid(id(UInt64($0)), ms: Double($0)) })

        let primary = try object(value.json, "frameElapsedMs")
        XCTAssertEqual(try count(primary, "sampleCount"), 1)
        XCTAssertEqual(try number(primary, "max"), 1)
        XCTAssertEqual(try count(object(value.json, "queryIntervalMs"), "sampleCount"), 8)
        XCTAssertEqual(
            value.json["queryIntervalMsPopulation"] as? String,
            "postWarmupAllUniquelyJoinedValidQueriesIncludingSoftwareUnknownOffscreenAndCapture")
        let postWarmup = try object(value.json, "postWarmup")
        let eligibility = try object(postWarmup, "hardwareEligibilityCounts")
        XCTAssertEqual(try count(eligibility, "eligible"), 1)
        XCTAssertEqual(try count(eligibility, "softwareAdapter"), 1)
        XCTAssertEqual(try count(eligibility, "unknownAdapter"), 1)
        XCTAssertEqual(try count(eligibility, "notSubmitted"), 5)
        XCTAssertEqual(try count(eligibility, "missingSubmission"), 1)
        let outcomes = try object(postWarmup, "submissionOutcomeCounts")
        XCTAssertEqual(try count(outcomes, "submitted"), 3)
        for outcome in ["offscreen", "failed", "skipped", "occluded", "aborted", "missing"] {
            XCTAssertEqual(try count(outcomes, outcome), 1)
        }
        let statuses = try object(postWarmup, "timingStatusCounts")
        XCTAssertEqual(try count(statuses, "valid"), 8)
        XCTAssertEqual(try count(statuses, "missingSubmission"), 1)
        XCTAssertEqual(value.json["hardwareQualified"] as? Bool, false)
        XCTAssertEqual(value.json["inputToPresentMeasured"] as? Bool, false)
        XCTAssertEqual(value.json["presentationDeadlinesMeasured"] as? Bool, false)
        XCTAssertEqual(value.json["exclusiveGPUUtilizationMeasured"] as? Bool, false)
    }

    func testMotionCaptureNeverPublishesHardwareFrameMeasurements() async throws {
        let value = report(
            [sample(id(1), animating: true), sample(id(2), software: true)],
            results: [valid(id(1), ms: 2), valid(id(2), ms: 4)],
            capturesMotion: true)

        XCTAssertFalse(value.hasHardwareMeasurements)
        XCTAssertEqual(value.json["hasHardwareMeasurements"] as? Bool, false)
        assertEmpty(try object(value.json, "frameElapsedMs"))
        assertEmpty(try object(value.json, "frameElapsedMsWhileAnimating"))
        assertEmpty(try object(value.json, "frameElapsedMsWhileIdle"))
        XCTAssertEqual(try count(object(value.json, "queryIntervalMs"), "sampleCount"), 2)
        let eligibility = try object(object(value.json, "postWarmup"), "hardwareEligibilityCounts")
        XCTAssertEqual(try count(eligibility, "motionCapture"), 2)
        XCTAssertEqual(try count(eligibility, "eligible"), 0)
        XCTAssertEqual((value.json["slowGPUFrames"] as? [[String: Any]])?.count, 0)
    }

    func testEmptyOrUnsupportedReportsKeepMissingMeasurementsNull() async throws {
        let empty = report(requested: false, initiallySupported: false)
        XCTAssertFalse(empty.hasHardwareMeasurements)
        XCTAssertEqual(empty.json["source"] as? String, "gpuElapsedCommandInterval")
        XCTAssertEqual(empty.json["requested"] as? Bool, false)
        XCTAssertEqual(empty.json["initiallySupported"] as? Bool, false)
        assertEmpty(try object(empty.json, "frameElapsedMs"))
        assertEmpty(try object(empty.json, "queryIntervalMs"))
        let collector = try object(empty.json, "collectorLifetime")
        XCTAssertEqual(collector["available"] as? Bool, false)
        for field in [
            "isEnabledAtFinish", "isSupportedAtFinish", "slotCapacity", "resultCapacity",
            "maximumGetDataCallsPerPoll", "pendingAtFinish", "droppedResults", "failureCode",
        ] {
            XCTAssertTrue(collector[field] is NSNull, "Unavailable collector field \(field) must be null.")
        }

        let unsupported = report(
            [sample(nil, outcome: .skipped, status: .unsupported)],
            diagnostics: GPUFrameTimingDiagnostics(isEnabled: false, isSupported: false),
            initiallySupported: false)
        XCTAssertFalse(unsupported.hasHardwareMeasurements)
        assertEmpty(try object(unsupported.json, "frameElapsedMs"))
        let postWarmup = try object(unsupported.json, "postWarmup")
        XCTAssertEqual(try count(object(postWarmup, "timingStatusCounts"), "unsupported"), 1)
        XCTAssertEqual(try count(postWarmup, "unidentifiedSubmissionCount"), 1)
        XCTAssertEqual(try object(unsupported.json, "collectorLifetime")["isSupportedAtFinish"] as? Bool, false)
    }

    func testPreWarmupOnlyResultsAreNotUsedAsFallbackMeasurements() async throws {
        let value = report(
            [sample(id(1), at: 0.5), sample(id(2), at: 1.49)],
            results: [valid(id(2), ms: 6), valid(id(1), ms: 8)])

        XCTAssertFalse(value.hasHardwareMeasurements)
        assertEmpty(try object(value.json, "frameElapsedMs"))
        assertEmpty(try object(value.json, "queryIntervalMs"))
        XCTAssertEqual(try count(object(value.json, "postWarmup"), "sampleCount"), 0)
        let join = try object(value.json, "sessionJoin")
        XCTAssertEqual(try count(join, "preWarmupSampleCount"), 2)
        XCTAssertEqual(try count(join, "matchedPreWarmupResultCount"), 2)
        XCTAssertEqual(try count(join, "matchedPostWarmupResultCount"), 0)
    }

    func testCollectorLifetimeSnapshotRemainsDistinctFromTerminalPostWarmupStatuses() async throws {
        let diagnostics = GPUFrameTimingDiagnostics(
            isEnabled: true, isSupported: true,
            slotCapacity: 3, resultCapacity: 7, maximumGetDataCallsPerPoll: 9,
            pendingCount: 2, droppedResultCount: 5, failureCode: -42)
        let value = report(
            [
                sample(id(99), at: 0.5, status: .ringFull),
                sample(id(1)), sample(id(2), status: .ringFull),
                sample(id(3)), sample(id(4)), sample(id(5)),
            ],
            results: [
                GPUFrameTimingResult(frameID: id(3), status: .cancelled),
                GPUFrameTimingResult(frameID: id(4), status: .disjoint),
                GPUFrameTimingResult(frameID: id(5), status: .deviceLost, failureCode: -42),
            ],
            diagnostics: diagnostics)

        XCTAssertFalse(value.hasHardwareMeasurements)
        assertEmpty(try object(value.json, "frameElapsedMs"))
        let collector = try object(value.json, "collectorLifetime")
        XCTAssertEqual(collector["isEnabledAtFinish"] as? Bool, true)
        XCTAssertEqual(try count(collector, "slotCapacity"), 3)
        XCTAssertEqual(try count(collector, "resultCapacity"), 7)
        XCTAssertEqual(try count(collector, "maximumGetDataCallsPerPoll"), 9)
        XCTAssertEqual(try count(collector, "pendingAtFinish"), 2)
        XCTAssertEqual(collector["droppedResults"] as? UInt64, 5)
        XCTAssertEqual(collector["failureCode"] as? Int32, -42)
        let postWarmup = try object(value.json, "postWarmup")
        let statuses = try object(postWarmup, "timingStatusCounts")
        for status in ["pending", "ringFull", "cancelled", "disjoint", "deviceLost"] {
            XCTAssertEqual(try count(statuses, status), 1)
        }
        XCTAssertEqual(try count(postWarmup, "sampleCount"), 5)
        XCTAssertEqual(try count(postWarmup, "hardwareEligibleWithoutValidTimingCount"), 5)
        let issued = try object(postWarmup, "submissionTimingStatusCounts")
        XCTAssertEqual(try count(issued, "pending"), 4)
        XCTAssertEqual(try count(issued, "ringFull"), 1, "Warmup ring exhaustion is not a post-warmup event.")
    }

    func testOnlyFiniteNonnegativeValidIntervalsAreMeasured() async throws {
        let invalidSeconds: [Double?] = [nil, -0.001, .nan, .infinity, -.infinity, .greatestFiniteMagnitude]
        var samples: [LiveFrameSample] = []
        var results: [GPUFrameTimingResult] = []
        for (index, seconds) in invalidSeconds.enumerated() {
            let frameID = id(UInt64(index))
            samples.append(sample(frameID))
            results.append(GPUFrameTimingResult(frameID: frameID, status: .valid, elapsedSeconds: seconds))
        }
        samples += [sample(id(20)), sample(id(21)), sample(id(22), status: .valid)]
        results += [
            valid(id(20), ms: 0),
            GPUFrameTimingResult(frameID: id(21), status: .disjoint, elapsedSeconds: 0.5),
        ]
        let value = report(samples, results: results)

        let frames = try object(value.json, "frameElapsedMs")
        XCTAssertEqual(try count(frames, "sampleCount"), 1)
        XCTAssertEqual(frames["hasSamples"] as? Bool, true)
        XCTAssertEqual(try number(frames, "mean"), 0, "A measured zero remains distinct from no measurement.")
        let postWarmup = try object(value.json, "postWarmup")
        XCTAssertEqual(try count(postWarmup, "invalidElapsedResultCount"), invalidSeconds.count)
        let statuses = try object(postWarmup, "timingStatusCounts")
        XCTAssertEqual(try count(statuses, "invalidResult"), invalidSeconds.count)
        XCTAssertEqual(try count(statuses, "disjoint"), 1)
        XCTAssertEqual(try count(statuses, "missingResult"), 1)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: value.json))
    }

    func testDuplicateIDsAndOrphanResultsAreNeverAttachedToAnotherFrame() async throws {
        let value = report(
            [
                sample(id(1), at: 0.5), sample(id(1), at: 2),
                sample(id(2), at: 2.5), sample(id(3), at: 3), sample(id(4), at: 4),
            ],
            results: [
                valid(id(1), ms: 10), valid(id(2), ms: 20), valid(id(2), ms: 20),
                valid(id(99), ms: 99), valid(id(3), ms: 3),
            ])

        let primary = try object(value.json, "frameElapsedMs")
        XCTAssertEqual(try count(primary, "sampleCount"), 1)
        XCTAssertEqual(try number(primary, "mean"), 3)
        let join = try object(value.json, "sessionJoin")
        XCTAssertEqual(try count(join, "duplicateSampleIDCount"), 1)
        XCTAssertEqual(try count(join, "duplicateSampleEntryCount"), 2)
        XCTAssertEqual(try count(join, "duplicateResultIDCount"), 1)
        XCTAssertEqual(try count(join, "duplicateResultEntryCount"), 2)
        XCTAssertEqual(try count(join, "orphanResultCount"), 1)
        XCTAssertEqual(try count(join, "matchedResultCount"), 1)
        XCTAssertEqual(try count(join, "unmatchedResultCount"), 4)
        let statuses = try object(object(value.json, "postWarmup"), "timingStatusCounts")
        for status in ["duplicateSampleID", "duplicateResultID", "valid", "pending"] {
            XCTAssertEqual(try count(statuses, status), 1)
        }
    }

    func testNoQueryIssuanceAndUnrequestedDataCannotQualifyAsHardware() async throws {
        let noValidQuery: [GPUFrameTimingStatus] = [
            .disabled, .unsupported, .notIssued, .ringFull, .aborted,
            .deviceLost, .failed, .cancelled, .disjoint, .invalidResult,
        ]
        var samples = noValidQuery.enumerated().map { sample(id(UInt64($0.offset)), status: $0.element) }
        var results = noValidQuery.enumerated().map { valid(id(UInt64($0.offset)), ms: 10) }
        samples += [sample(id(100)), sample(id(101), status: .valid)]
        results += [valid(id(100), ms: 2), valid(id(101), ms: 4)]
        let value = report(samples, results: results, initiallySupported: false)

        XCTAssertTrue(value.hasHardwareMeasurements, "Initial support failure cannot exclude later recovered work.")
        XCTAssertEqual(try count(object(value.json, "frameElapsedMs"), "sampleCount"), 2)
        XCTAssertEqual(try count(object(value.json, "queryIntervalMs"), "sampleCount"), 2)
        let postWarmup = try object(value.json, "postWarmup")
        XCTAssertEqual(try count(postWarmup, "inconsistentSubmissionResultCount"), noValidQuery.count)
        XCTAssertEqual(try count(object(postWarmup, "timingStatusCounts"), "invalidResult"), noValidQuery.count)

        let unrequested = report([sample(id(100))], results: [valid(id(100), ms: 2)], requested: false)
        XCTAssertFalse(unrequested.hasHardwareMeasurements)
        assertEmpty(try object(unrequested.json, "frameElapsedMs"))
        XCTAssertEqual(try count(object(unrequested.json, "queryIntervalMs"), "sampleCount"), 1)
        let eligibility = try object(object(unrequested.json, "postWarmup"), "hardwareEligibilityCounts")
        XCTAssertEqual(try count(eligibility, "notRequested"), 1)
    }

    func testDeviceGenerationsAndLargeFrameIDsSurviveJSONWithoutPrecisionLoss() async throws {
        let first = id(.max, generation: .max)
        let second = id(.max, generation: .max - 1)
        let value = report(
            [sample(first, at: 2), sample(second, at: 3)],
            results: [valid(second, ms: 2.5), valid(first, ms: 1.25)],
            diagnostics: GPUFrameTimingDiagnostics(isEnabled: false, isSupported: false))

        XCTAssertTrue(value.hasHardwareMeasurements, "Device loss at finish cannot erase earlier valid hardware work.")
        XCTAssertEqual(try count(object(value.json, "frameElapsedMs"), "sampleCount"), 2)
        let data = try JSONSerialization.data(withJSONObject: value.json)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(decoded["frameIDEncoding"] as? String, "uint64DecimalStrings")
        let slow = try XCTUnwrap(decoded["slowGPUFrames"] as? [[String: Any]])
        XCTAssertEqual(slow.count, 2)
        let firstID = try object(slow[0], "frameID")
        XCTAssertEqual(firstID["deviceGeneration"] as? String, "18446744073709551614")
        XCTAssertEqual(firstID["frameNumber"] as? String, "18446744073709551615")
        let secondID = try object(slow[1], "frameID")
        XCTAssertEqual(secondID["deviceGeneration"] as? String, "18446744073709551615")
        XCTAssertEqual(secondID["frameNumber"] as? String, "18446744073709551615")
    }

    func testSlowDetailsAreBoundedWhilePercentilesIncludeAllEligibleFrames() async throws {
        let samples = (0..<12).map {
            sample(id(UInt64($0)), at: Double($0) + 2, animating: $0.isMultiple(of: 2))
        }
        let results = (0..<12).map { valid(id(UInt64($0)), ms: Double($0) + 1) }
        let value = report(samples, results: Array(results.reversed()))

        let frames = try object(value.json, "frameElapsedMs")
        XCTAssertEqual(try count(frames, "sampleCount"), 12)
        XCTAssertEqual(try number(frames, "p50"), 7, accuracy: 0.000_001)
        XCTAssertEqual(try number(frames, "p95"), 11, accuracy: 0.000_001)
        XCTAssertEqual(try number(frames, "p99"), 12, accuracy: 0.000_001)
        XCTAssertEqual(try number(frames, "mean"), 6.5, accuracy: 0.000_001)
        let animating = try object(value.json, "frameElapsedMsWhileAnimating")
        let idle = try object(value.json, "frameElapsedMsWhileIdle")
        XCTAssertEqual(try count(animating, "sampleCount"), 6)
        XCTAssertEqual(try number(animating, "mean"), 6, accuracy: 0.000_001)
        XCTAssertEqual(try count(idle, "sampleCount"), 6)
        XCTAssertEqual(try number(idle, "mean"), 7, accuracy: 0.000_001)
        let slow = try XCTUnwrap(value.json["slowGPUFrames"] as? [[String: Any]])
        XCTAssertEqual(slow.count, 8)
        XCTAssertEqual(try number(slow[0], "elapsedMs"), 12, accuracy: 0.000_001)
        XCTAssertEqual(try number(slow[0], "issuingFrameElapsedSeconds"), 13)
        XCTAssertEqual(try number(slow[7], "elapsedMs"), 5, accuracy: 0.000_001)
    }

    func testInvalidIssuingTimesOrSamplingWindowCannotProduceMeasurements() async throws {
        let samples = [sample(id(1), at: .nan), sample(id(2), at: .infinity), sample(id(3), at: 2)]
        let results = [valid(id(1), ms: 1), valid(id(2), ms: 2), valid(id(3), ms: 3)]
        let value = report(samples, results: results)
        XCTAssertEqual(try count(object(value.json, "frameElapsedMs"), "sampleCount"), 1)
        let join = try object(value.json, "sessionJoin")
        XCTAssertEqual(try count(join, "invalidTimestampSampleCount"), 2)
        XCTAssertEqual(try count(join, "matchedInvalidTimeResultCount"), 2)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: value.json))

        let invalidWindow = report(samples, results: results, warmupSeconds: .nan)
        XCTAssertFalse(invalidWindow.hasHardwareMeasurements)
        assertEmpty(try object(invalidWindow.json, "frameElapsedMs"))
        let invalidJoin = try object(invalidWindow.json, "sessionJoin")
        XCTAssertEqual(invalidJoin["hasValidSamplingWindow"] as? Bool, false)
        XCTAssertEqual(try count(invalidJoin, "invalidTimestampSampleCount"), 3)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: invalidWindow.json))
    }
}
