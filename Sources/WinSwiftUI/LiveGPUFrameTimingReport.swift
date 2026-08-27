import Foundation
import SwiftWindowsGraphics

/// Joins asynchronous query results to the CPU frame that issued them. Query
/// arrival time never determines warmup or supplies a later frame's GPU time.
@MainActor
struct LiveGPUFrameTimingReport {
    var json: [String: Any]
    var hasHardwareMeasurements: Bool

    static func build(
        samples: [LiveFrameSample],
        results: [GPUFrameTimingResult],
        diagnostics: GPUFrameTimingDiagnostics?,
        requested: Bool,
        initiallySupported: Bool,
        capturesMotion: Bool,
        sessionStartedAt: Double,
        warmupSeconds: Double
    ) -> LiveGPUFrameTimingReport {
        var sampleIndices: [BackendFrameID: [Int]] = [:]
        for (index, sample) in samples.enumerated() {
            if let id = sample.backendFrameSubmission?.id {
                sampleIndices[id, default: []].append(index)
            }
        }
        let resultsByID = Dictionary(grouping: results, by: \.frameID)
        let validWindow =
            sessionStartedAt.isFinite && warmupSeconds.isFinite && warmupSeconds >= 0

        func elapsed(for sample: LiveFrameSample) -> Double? {
            guard validWindow else { return nil }
            let value = sample.presentedAt - sessionStartedAt
            return value.isFinite ? value : nil
        }

        var matchedResults = 0
        var matchedPreWarmupResults = 0
        var matchedPostWarmupResults = 0
        var matchedInvalidTimeResults = 0
        for (id, values) in resultsByID {
            guard values.count == 1, let indices = sampleIndices[id], indices.count == 1 else {
                continue
            }
            matchedResults += 1
            guard let time = elapsed(for: samples[indices[0]]) else {
                matchedInvalidTimeResults += 1
                continue
            }
            if time >= warmupSeconds {
                matchedPostWarmupResults += 1
            } else {
                matchedPreWarmupResults += 1
            }
        }

        var outcomeCounts = zeroCounts([
            "submitted", "offscreen", "skipped", "occluded", "aborted", "failed", "missing",
        ])
        var submissionStatusCounts = zeroCounts(statusNames + ["missing"])
        var timingStatusCounts = zeroCounts(
            statusNames + ["missingSubmission", "missingResult", "duplicateSampleID", "duplicateResultID"])
        var eligibilityCounts = zeroCounts([
            "eligible", "notRequested", "motionCapture", "missingSubmission", "notSubmitted", "softwareAdapter",
            "unknownAdapter",
        ])
        var preWarmupSamples = 0
        var invalidTimeSamples = 0
        var postWarmupSamples = 0
        var unidentifiedSubmissions = 0
        var invalidElapsedResults = 0
        var inconsistentSubmissionResults = 0
        var hardwareEligibleWithoutValidTiming = 0
        var queryIntervals: [Double] = []
        var hardwareIntervals: [MeasuredFrame] = []

        for sample in samples {
            guard let time = elapsed(for: sample) else {
                invalidTimeSamples += 1
                continue
            }
            guard time >= warmupSeconds else {
                preWarmupSamples += 1
                continue
            }
            postWarmupSamples += 1
            let submission = sample.backendFrameSubmission
            outcomeCounts[submission?.outcome.rawValue ?? "missing", default: 0] += 1
            submissionStatusCounts[submission?.gpuTimingStatus.rawValue ?? "missing", default: 0] += 1
            if let submission, submission.id == nil { unidentifiedSubmissions += 1 }

            // These mutually exclusive reasons classify the CPU sample, before
            // considering whether a usable query result ever became available.
            let eligibility: String
            if !requested {
                eligibility = "notRequested"
            } else if capturesMotion {
                eligibility = "motionCapture"
            } else if submission == nil {
                eligibility = "missingSubmission"
            } else if submission?.outcome != .submitted {
                eligibility = "notSubmitted"
            } else if sample.gpuTimingAdapterIsSoftware == true {
                eligibility = "softwareAdapter"
            } else if sample.gpuTimingAdapterIsSoftware == nil {
                eligibility = "unknownAdapter"
            } else {
                eligibility = "eligible"
            }
            eligibilityCounts[eligibility, default: 0] += 1

            let status: String
            var intervalMs: Double?
            if let submission {
                if let id = submission.id, (sampleIndices[id]?.count ?? 0) > 1 {
                    status = "duplicateSampleID"
                } else if let id = submission.id, (resultsByID[id]?.count ?? 0) > 1 {
                    status = "duplicateResultID"
                } else if let id = submission.id, let result = resultsByID[id]?.first {
                    if result.status == .valid {
                        if submission.gpuTimingStatus == .pending || submission.gpuTimingStatus == .valid {
                            intervalMs = milliseconds(result.elapsedSeconds)
                            if intervalMs == nil { invalidElapsedResults += 1 }
                            status =
                                intervalMs == nil ? GPUFrameTimingStatus.invalidResult.rawValue : result.status.rawValue
                        } else {
                            // Explicitly unissued or failed work cannot acquire
                            // a valid interval from a contradictory late result.
                            inconsistentSubmissionResults += 1
                            status = GPUFrameTimingStatus.invalidResult.rawValue
                        }
                    } else {
                        status = result.status.rawValue
                    }
                } else {
                    // A submission that claims validity without its result has
                    // no measurable interval; zero is not a substitute.
                    status =
                        submission.gpuTimingStatus == .valid ? "missingResult" : submission.gpuTimingStatus.rawValue
                }
            } else {
                status = "missingSubmission"
            }
            timingStatusCounts[status, default: 0] += 1

            if let intervalMs {
                queryIntervals.append(intervalMs)
                if eligibility == "eligible", let id = submission?.id {
                    hardwareIntervals.append(
                        MeasuredFrame(
                            id: id, issuingFrameElapsedSeconds: time, elapsedMs: intervalMs,
                            hadActiveAnimations: sample.hadActiveAnimations))
                }
            }
            if eligibility == "eligible", intervalMs == nil {
                hardwareEligibleWithoutValidTiming += 1
            }
        }

        let slowFrames = hardwareIntervals.sorted { lhs, rhs in
            if lhs.elapsedMs != rhs.elapsedMs { return lhs.elapsedMs > rhs.elapsedMs }
            if lhs.issuingFrameElapsedSeconds != rhs.issuingFrameElapsedSeconds {
                return lhs.issuingFrameElapsedSeconds < rhs.issuingFrameElapsedSeconds
            }
            if lhs.id.deviceGeneration != rhs.id.deviceGeneration {
                return lhs.id.deviceGeneration < rhs.id.deviceGeneration
            }
            return lhs.id.frameNumber < rhs.id.frameNumber
        }.prefix(8).map { value -> [String: Any] in
            [
                "frameID": [
                    "deviceGeneration": String(value.id.deviceGeneration),
                    "frameNumber": String(value.id.frameNumber),
                ],
                "issuingFrameElapsedSeconds": value.issuingFrameElapsedSeconds,
                "elapsedMs": value.elapsedMs,
                "hadActiveAnimations": value.hadActiveAnimations,
            ]
        }
        let duplicateSamples = sampleIndices.values.filter { $0.count > 1 }
        let duplicateResults = resultsByID.values.filter { $0.count > 1 }
        let hasHardwareMeasurements = !hardwareIntervals.isEmpty
        let json: [String: Any] = [
            "source": "gpuElapsedCommandInterval",
            "requested": requested,
            "initiallySupported": initiallySupported,
            "capturesMotion": capturesMotion,
            "hasHardwareMeasurements": hasHardwareMeasurements,
            "hardwareQualified": false,
            "inputToPresentMeasured": false,
            "presentationDeadlinesMeasured": false,
            "exclusiveGPUUtilizationMeasured": false,
            "frameIDEncoding": "uint64DecimalStrings",
            "issuingFrameTimeReference": "cpuPresentedAtMinusSessionStart",
            "frameElapsedMsPopulation": "allPostWarmupSubmittedHardwareFramesWithoutMotionCapture",
            "frameElapsedMs": summary(hardwareIntervals.map(\.elapsedMs)),
            "frameElapsedMsWhileAnimating": summary(hardwareIntervals.filter(\.hadActiveAnimations).map(\.elapsedMs)),
            "frameElapsedMsWhileIdle": summary(hardwareIntervals.filter { !$0.hadActiveAnimations }.map(\.elapsedMs)),
            "animationSplitReference": "issuingCPUFrameHadActiveAnimations",
            "queryIntervalMsPopulation":
                "postWarmupAllUniquelyJoinedValidQueriesIncludingSoftwareUnknownOffscreenAndCapture",
            "queryIntervalMs": summary(queryIntervals),
            "collectorLifetime": [
                "available": diagnostics != nil,
                "isEnabledAtFinish": nullable(diagnostics?.isEnabled),
                "isSupportedAtFinish": nullable(diagnostics?.isSupported),
                "slotCapacity": nullable(diagnostics?.slotCapacity),
                "resultCapacity": nullable(diagnostics?.resultCapacity),
                "maximumGetDataCallsPerPoll": nullable(diagnostics?.maximumGetDataCallsPerPoll),
                "pendingAtFinish": nullable(diagnostics?.pendingCount),
                "droppedResults": nullable(diagnostics?.droppedResultCount),
                "failureCode": nullable(diagnostics?.failureCode),
            ],
            "sessionJoin": [
                "hasValidSamplingWindow": validWindow,
                "cpuSampleCount": samples.count,
                "resultCount": results.count,
                "matchedResultCount": matchedResults,
                "unmatchedResultCount": results.count - matchedResults,
                "matchedPreWarmupResultCount": matchedPreWarmupResults,
                "matchedPostWarmupResultCount": matchedPostWarmupResults,
                "matchedInvalidTimeResultCount": matchedInvalidTimeResults,
                "preWarmupSampleCount": preWarmupSamples,
                "invalidTimestampSampleCount": invalidTimeSamples,
                "duplicateSampleIDCount": duplicateSamples.count,
                "duplicateSampleEntryCount": duplicateSamples.reduce(0) { $0 + $1.count },
                "duplicateResultIDCount": duplicateResults.count,
                "duplicateResultEntryCount": duplicateResults.reduce(0) { $0 + $1.count },
                "orphanResultCount": results.filter { sampleIndices[$0.frameID] == nil }.count,
            ],
            "postWarmup": [
                "sampleCount": postWarmupSamples,
                "submissionOutcomeCounts": outcomeCounts,
                "submissionTimingStatusCounts": submissionStatusCounts,
                "timingStatusCounts": timingStatusCounts,
                "hardwareEligibilityCounts": eligibilityCounts,
                "hardwareEligibleWithoutValidTimingCount": hardwareEligibleWithoutValidTiming,
                "unidentifiedSubmissionCount": unidentifiedSubmissions,
                "invalidElapsedResultCount": invalidElapsedResults,
                "inconsistentSubmissionResultCount": inconsistentSubmissionResults,
            ],
            "slowGPUFrames": slowFrames,
        ]
        return LiveGPUFrameTimingReport(json: json, hasHardwareMeasurements: hasHardwareMeasurements)
    }

    private struct MeasuredFrame {
        var id: BackendFrameID
        var issuingFrameElapsedSeconds: Double
        var elapsedMs: Double
        var hadActiveAnimations: Bool
    }

    private static let statusNames = [
        "disabled", "unsupported", "notIssued", "pending", "valid", "ringFull", "disjoint",
        "invalidResult", "aborted", "deviceLost", "failed", "cancelled",
    ]

    private static func zeroCounts(_ names: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: names.map { ($0, 0) })
    }

    private static func nullable<Value>(_ value: Value?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    private static func milliseconds(_ seconds: Double?) -> Double? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let value = seconds * 1_000
        return value.isFinite ? value : nil
    }

    private static func summary(_ values: [Double]) -> [String: Any] {
        let sorted = values.sorted()
        guard let maximum = sorted.last else {
            return [
                "p50": NSNull(), "p95": NSNull(), "p99": NSNull(), "max": NSNull(), "mean": NSNull(),
                "sampleCount": 0, "hasSamples": false,
            ]
        }
        func percentile(_ fraction: Double) -> Double {
            sorted[Int((Double(sorted.count - 1) * fraction).rounded())]
        }
        // All values are finite and nonnegative. An incremental mean avoids
        // overflowing the sum even when each individual interval is valid.
        var mean = 0.0
        for (index, value) in sorted.enumerated() {
            mean += (value - mean) / Double(index + 1)
        }
        return [
            "p50": percentile(0.50), "p95": percentile(0.95), "p99": percentile(0.99),
            "max": maximum, "mean": mean, "sampleCount": sorted.count, "hasSamples": true,
        ]
    }
}
