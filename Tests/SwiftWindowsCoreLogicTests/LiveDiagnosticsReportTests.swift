import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

@MainActor
final class LiveDiagnosticsReportTests: XCTestCase {
    private static let epoch = 1_000.0

    @MainActor
    private final class Clock {
        var now = LiveDiagnosticsReportTests.epoch
    }

    @MainActor
    private final class AtlasBackend: BatchRenderBackend {
        private let base = FakeBatchRenderBackend()
        let backendDiagnostics: BatchBackendDiagnostics?
        var backendDisplayName: String { "SYNTHETIC ATLAS COUNTERS" }

        init(totalBytes: UInt64) {
            backendDiagnostics = BatchBackendDiagnostics(
                adapterDescription: "Test backend", adapterIsSoftware: true,
                adapterDedicatedVideoMemoryBytes: 0, featureLevel: "test",
                atlasUploadedByteCount: totalBytes)
        }

        func attach(to surface: SurfaceDescriptor) throws { try base.attach(to: surface) }
        func resize(to size: IntSize) throws { try base.resize(to: size) }
        func bindResources(for scene: GPUIScene) { base.bindResources(for: scene) }
        func render(scene: GPUIScene) throws { try base.render(scene: scene) }
        func detach() { base.detach() }
    }

    private func sample(
        at elapsed: Double,
        totalMs: Double = 10,
        rebuildCount: Int = 0,
        rebuildMs: Double = 0,
        outsideRebuildMs: Double = 0,
        bodyMs: Double = 0,
        constructionMs: Double = 0,
        reconcileMs: Double = 0,
        phaseTimingsAvailable: Bool = false,
        backendTimingsAvailable: Bool = false,
        animating: Bool = false
    ) -> LiveFrameSample {
        var value = LiveFrameSample(
            presentedAt: Self.epoch + elapsed,
            totalSeconds: totalMs / 1_000,
            sceneBuildSeconds: 0.001,
            bindSeconds: 0.0002,
            backendSubmitSeconds: 0.0003,
            backendPresentSeconds: 0.0004,
            submitAndPresentSeconds: 0.0007,
            didRebuildScene: rebuildCount > 0,
            nodeReplayCount: 0,
            primitiveCount: 1,
            hadActiveAnimations: animating,
            backend: .scene,
            atlasUploadedByteCount: 0,
            drawCallCount: 1,
            drawnInstanceCount: 1,
            visitedNodeCount: rebuildCount > 0 ? 1 : 0)
        value.rebuildCount = rebuildCount
        value.rebuildSeconds = rebuildMs / 1_000
        value.outsideFrameRebuildSeconds = outsideRebuildMs / 1_000
        value.composeSeconds = bodyMs / 1_000
        value.nodeConstructionSeconds = constructionMs / 1_000
        value.reconcileSeconds = reconcileMs / 1_000
        value.rebuildPhaseTimingsAvailable = phaseTimingsAvailable
        value.backendTimingsAvailable = backendTimingsAvailable
        return value
    }

    private func makeReport(
        samples: [LiveFrameSample],
        finishAt elapsed: Double = 4,
        exercisesInput: Bool = false,
        atlasTotalBytes: UInt64? = nil
    ) throws -> [String: Any] {
        let clock = Clock()
        let size = IntSize(width: 32, height: 32)
        let window = Win32Window(title: "Diagnostics report test", clientSize: size)
        window.testScaleFactorOverride = 1
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: size,
            scaleFactor: 1)
        let batchRenderer: any BatchRenderBackend
        if let atlasTotalBytes {
            batchRenderer = AtlasBackend(totalBytes: atlasTotalBytes)
        } else {
            batchRenderer = FakeBatchRenderBackend()
        }
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Diagnostics report test", size: size, clearColor: .black, content: []),
            platformWindow: window,
            renderer: FakeRenderBackend(),
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface },
            startupPresentationMode: .automatic,
            startupProbeConfiguration: nil)
        host.windowDidCreate(window)
        defer { withExtendedLifetime(host) {} }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-windowsui-live-report-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        var closeRequests = 0
        let session = LiveDiagnosticsSession(
            configuration: LiveDiagnosticsConfiguration(
                durationSeconds: 60,
                outputPath: output.path,
                exercisesInput: exercisesInput),
            host: host,
            clock: { clock.now },
            requestClose: { closeRequests += 1 },
            report: { _ in })
        session.start()
        XCTAssertNotNil(host.onFramePresented)
        for frame in samples {
            clock.now = frame.presentedAt
            host.onFramePresented?(frame)
        }
        clock.now = Self.epoch + elapsed
        session.finish()
        XCTAssertNil(host.onFramePresented)
        XCTAssertEqual(closeRequests, 1)
        session.finish()
        XCTAssertEqual(closeRequests, 1, "Finishing twice must not request a second close.")
        let data = try Data(contentsOf: output)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func object(_ parent: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(parent[key] as? [String: Any], "Missing object \(key)")
    }

    private func assertEmptySummary(
        _ summary: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(summary["sampleCount"] as? Int, 0, file: file, line: line)
        XCTAssertEqual(summary["hasSamples"] as? Bool, false, file: file, line: line)
        for key in ["p50", "p95", "p99", "max", "mean"] {
            XCTAssertTrue(summary[key] is NSNull, "\(key) must be null without samples", file: file, line: line)
        }
    }

    private func assertThreeSampleSummary(
        _ summary: [String: Any],
        median: Double,
        maximum: Double,
        mean: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(summary["sampleCount"] as? Int, 3, file: file, line: line)
        XCTAssertEqual(summary["hasSamples"] as? Bool, true, file: file, line: line)
        XCTAssertEqual(summary["p50"] as? Double ?? -1, median, accuracy: 0.0001, file: file, line: line)
        for key in ["p95", "p99", "max"] {
            XCTAssertEqual(summary[key] as? Double ?? -1, maximum, accuracy: 0.0001, file: file, line: line)
        }
        XCTAssertEqual(summary["mean"] as? Double ?? -1, mean, accuracy: 0.0001, file: file, line: line)
    }

    func testNoSamplesProduceNullSummariesAndExplicitMeasurementLimits() async throws {
        for exercisesInput in [false, true] {
            let report = try makeReport(samples: [], exercisesInput: exercisesInput)
            XCTAssertEqual(report["schema"] as? String, "swift-windowsui.live-diagnostics/2")
            let frames = try object(report, "frames")
            XCTAssertEqual(frames["presentedTotal"] as? Int, 0)
            XCTAssertEqual(frames["presentedAfterWarmup"] as? Int, 0)
            let sampling = try object(report, "sampling")
            XCTAssertEqual(sampling["status"] as? String, "noPostWarmupSamples")
            XCTAssertEqual(sampling["postWarmupSampleCount"] as? Int, 0)
            XCTAssertTrue(sampling["postWarmupSampleSpanSeconds"] is NSNull)
            XCTAssertTrue(frames["framesOverRefreshBudgetFraction"] is NSNull)
            for key in [
                "frameTimeMs", "sceneBuildMs", "treeRebuildMs", "bodyEvaluationMs",
                "nodeConstructionMs", "reconcileMs", "bindResourcesMs", "submitAndPresentMs",
                "backendSubmitMs", "backendPresentMs", "presentGapMs",
            ] {
                assertEmptySummary(try object(frames, key))
            }
            let measurement = try object(report, "measurement")
            for key in [
                "inputToPresentMeasured", "gpuExecutionMeasured", "presentationDeadlinesMeasured", "hardwareQualified",
            ] {
                XCTAssertEqual(measurement[key] as? Bool, false, key)
            }
            XCTAssertEqual(measurement["presentTiming"] as? String, "cpuCallDuration")
            XCTAssertEqual(measurement["forcedFrameRequests"] as? Bool, true)
            XCTAssertEqual(try object(report, "syntheticWorkload")["enabled"] as? Bool, exercisesInput)
            if exercisesInput {
                XCTAssertEqual(measurement["inputDelivery"] as? String, "syntheticRetainedRuntime")
            }
        }
    }

    func testWarmupOnlySamplesNeverBecomeFallbackSteadyStateMeasurements() async throws {
        let report = try makeReport(
            samples: [
                sample(at: 0.2, totalMs: 200, rebuildCount: 1, rebuildMs: 100),
                sample(at: 0.9, totalMs: 300, rebuildCount: 1, rebuildMs: 100),
                sample(at: 1.49, totalMs: 400, rebuildCount: 1, rebuildMs: 100),
            ],
            finishAt: 2)
        let frames = try object(report, "frames")
        XCTAssertEqual(frames["presentedTotal"] as? Int, 3)
        XCTAssertEqual(frames["presentedAfterWarmup"] as? Int, 0)
        XCTAssertEqual(frames["warmupSeconds"] as? Double, 1.5)
        let sampling = try object(report, "sampling")
        XCTAssertEqual(sampling["status"] as? String, "noPostWarmupSamples")
        XCTAssertEqual(sampling["warmupExcludedSampleCount"] as? Int, 3)
        assertEmptySummary(try object(frames, "frameTimeMs"))
        assertEmptySummary(try object(frames, "treeRebuildMs"))
        XCTAssertEqual((report["worstFrames"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((report["costliestUpdates"] as? [[String: Any]])?.count, 0)
    }

    func testExactWarmupBoundaryUsesTheSessionEpochRatherThanTheFirstFrame() async throws {
        let report = try makeReport(samples: [
            sample(at: 0.5, totalMs: 500),
            sample(at: 1.499, totalMs: 600),
            sample(at: 1.5, totalMs: 20),
            sample(at: 1.6, totalMs: 40),
        ])
        let frames = try object(report, "frames")
        XCTAssertEqual(frames["presentedTotal"] as? Int, 4)
        XCTAssertEqual(frames["presentedAfterWarmup"] as? Int, 2)
        let sampling = try object(report, "sampling")
        XCTAssertEqual(sampling["status"] as? String, "samplesAvailable")
        XCTAssertEqual(sampling["postWarmupSampleCount"] as? Int, 2)
        XCTAssertEqual(sampling["postWarmupSampleSpanSeconds"] as? Double ?? -1, 0.1, accuracy: 0.0001)
        XCTAssertEqual(sampling["availableSamplesEstablishQualification"] as? Bool, false)
        let summary = try object(frames, "frameTimeMs")
        XCTAssertEqual(summary["sampleCount"] as? Int, 2)
        XCTAssertEqual(summary["hasSamples"] as? Bool, true)
        XCTAssertEqual(summary["mean"] as? Double ?? -1, 30, accuracy: 0.0001)
        XCTAssertEqual(summary["max"] as? Double ?? -1, 40, accuracy: 0.0001)
        let worst = try XCTUnwrap(report["worstFrames"] as? [[String: Any]])
        XCTAssertEqual(worst.count, 2)
        XCTAssertEqual(worst.first?["atSeconds"] as? Double ?? -1, 1.6, accuracy: 0.0001)
        XCTAssertEqual(worst.last?["atSeconds"] as? Double ?? -1, 1.5, accuracy: 0.0001)
    }

    func testPhasePercentilesUseOnlyAvailablePostWarmupRebuildMeasurements() async throws {
        let report = try makeReport(samples: [
            sample(
                at: 0.5, rebuildCount: 1, rebuildMs: 999,
                bodyMs: 999, constructionMs: 999, reconcileMs: 999, phaseTimingsAvailable: true),
            sample(
                at: 1.5, rebuildCount: 1, rebuildMs: 6,
                bodyMs: 1, constructionMs: 2, reconcileMs: 3, phaseTimingsAvailable: true),
            sample(
                at: 1.75, bodyMs: 100, constructionMs: 200, reconcileMs: 300, phaseTimingsAvailable: true),
            sample(
                at: 2, rebuildCount: 1, rebuildMs: 9,
                bodyMs: 999, constructionMs: 999, reconcileMs: 999),
            sample(
                at: 2.25, totalMs: 20, rebuildCount: 2, rebuildMs: 18,
                bodyMs: 3, constructionMs: 6, reconcileMs: 9, phaseTimingsAvailable: true),
            sample(
                at: 2.5, totalMs: 40, rebuildCount: 1, rebuildMs: 30,
                bodyMs: 5, constructionMs: 10, reconcileMs: 15, phaseTimingsAvailable: true),
        ])
        let frames = try object(report, "frames")
        assertThreeSampleSummary(try object(frames, "bodyEvaluationMs"), median: 3, maximum: 5, mean: 3)
        assertThreeSampleSummary(try object(frames, "nodeConstructionMs"), median: 6, maximum: 10, mean: 6)
        assertThreeSampleSummary(try object(frames, "reconcileMs"), median: 9, maximum: 15, mean: 9)
        // The nonzero backend fields above are placeholders, not measurements.
        assertEmptySummary(try object(frames, "backendSubmitMs"))
        assertEmptySummary(try object(frames, "backendPresentMs"))
    }

    func testCostliestUpdatesAddOnlyRebuildWorkOutsideTheFrame() async throws {
        let inFrame = sample(at: 1.5, totalMs: 20, rebuildCount: 1, rebuildMs: 18)
        let outsideFrame = sample(at: 1.6, totalMs: 12, rebuildCount: 1, rebuildMs: 20, outsideRebuildMs: 10)
        let cheaper = sample(at: 1.7, totalMs: 14, rebuildCount: 1, rebuildMs: 4, outsideRebuildMs: 1)
        XCTAssertEqual(inFrame.userVisibleCostSeconds, 0.020, accuracy: 0.000001)
        XCTAssertEqual(outsideFrame.userVisibleCostSeconds, 0.022, accuracy: 0.000001)
        let report = try makeReport(samples: [inFrame, outsideFrame, cheaper])
        let updates = try XCTUnwrap(report["costliestUpdates"] as? [[String: Any]])
        XCTAssertEqual(updates.count, 3)
        for (detail, expected) in zip(updates, [(1.6, 22.0, 10.0), (1.5, 20.0, 0.0), (1.7, 15.0, 1.0)]) {
            XCTAssertEqual(detail["atSeconds"] as? Double ?? -1, expected.0, accuracy: 0.0001)
            XCTAssertEqual(detail["userVisibleCostMs"] as? Double ?? -1, expected.1, accuracy: 0.0001)
            XCTAssertEqual(detail["outsideFrameRebuildMs"] as? Double ?? -1, expected.2, accuracy: 0.0001)
        }
        XCTAssertEqual(updates.first?["treeRebuildMs"] as? Double ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(updates.first?["frameTimeMs"] as? Double ?? -1, 12, accuracy: 0.0001)
        let worstFrames = try XCTUnwrap(report["worstFrames"] as? [[String: Any]])
        XCTAssertEqual(worstFrames.first?["atSeconds"] as? Double ?? -1, 1.5, accuracy: 0.0001)
    }

    func testIdleOnlyPopulationLeavesAnimatorFractionsAndPercentilesNull() async throws {
        let report = try makeReport(samples: [sample(at: 1.5, totalMs: 2)])
        let frames = try object(report, "frames")
        let animating = try object(frames, "whileAnimating")
        let idle = try object(frames, "whileIdle")
        XCTAssertEqual(animating["frameCount"] as? Int, 0)
        XCTAssertEqual(idle["frameCount"] as? Int, 1)
        assertEmptySummary(try object(animating, "frameTimeMs"))
        assertEmptySummary(try object(animating, "sceneBuildMs"))
        XCTAssertTrue(animating["framesOverRefreshBudgetFraction"] is NSNull)
        XCTAssertEqual(idle["framesOverRefreshBudgetFraction"] as? Double, 0)
        let scene = try object(report, "scene")
        XCTAssertTrue(scene["animatingReplayRate"] is NSNull)
    }

    func testAtlasWithoutAPrewarmupBaselineReportsUnknownPostWarmupCosts() async throws {
        var boundary = sample(at: 1.5, backendTimingsAvailable: true)
        boundary.atlasUploadedByteCount = 150
        let report = try makeReport(samples: [boundary], atlasTotalBytes: 150)
        let atlas = try object(report, "atlas")
        XCTAssertEqual(atlas["uploadedByteCountTotal"] as? Int, 150)
        XCTAssertEqual(atlas["postWarmupCountersAvailable"] as? Bool, false)
        for key in [
            "uploadedByteCountAfterWarmup", "uploadedBytesPerFrameAfterWarmup", "framesThatUploadedAfterWarmup",
        ] {
            XCTAssertTrue(atlas[key] is NSNull, "\(key) needs a known counter baseline")
        }
    }

    func testAtlasCountsTheFirstEligibleFramesUploadAgainstThePrewarmupBaseline() async throws {
        var prewarmup = sample(at: 1.4, backendTimingsAvailable: true)
        prewarmup.atlasUploadedByteCount = 100
        var boundary = sample(at: 1.5, backendTimingsAvailable: true)
        boundary.atlasUploadedByteCount = 150
        let report = try makeReport(samples: [prewarmup, boundary], atlasTotalBytes: 150)
        let atlas = try object(report, "atlas")
        XCTAssertEqual(atlas["postWarmupCountersAvailable"] as? Bool, true)
        XCTAssertEqual(atlas["uploadedByteCountAfterWarmup"] as? Int, 50)
        XCTAssertEqual(atlas["uploadedBytesPerFrameAfterWarmup"] as? Double ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(atlas["framesThatUploadedAfterWarmup"] as? Int, 1)
    }

    func testAtlasCounterResetOrMissingBackendSampleInvalidatesTheMeasuredInterval() async throws {
        var prewarmup = sample(at: 1.4, backendTimingsAvailable: true)
        prewarmup.atlasUploadedByteCount = 100
        var boundary = sample(at: 1.5, backendTimingsAvailable: true)
        boundary.atlasUploadedByteCount = 150
        var reset = sample(at: 1.6, backendTimingsAvailable: true)
        reset.atlasUploadedByteCount = 40
        let unavailable = sample(at: 1.6)
        for interrupted in [reset, unavailable] {
            let report = try makeReport(samples: [prewarmup, boundary, interrupted], atlasTotalBytes: 200)
            let atlas = try object(report, "atlas")
            XCTAssertEqual(atlas["postWarmupCountersAvailable"] as? Bool, false)
            for key in [
                "uploadedByteCountAfterWarmup", "uploadedBytesPerFrameAfterWarmup", "framesThatUploadedAfterWarmup",
            ] {
                XCTAssertTrue(atlas[key] is NSNull, "\(key) needs continuous backend counters")
            }
        }
    }

    func testAtlasAverageUsesNumericBytesAcrossAllEligibleFrames() async throws {
        var prewarmup = sample(at: 1.4, backendTimingsAvailable: true)
        prewarmup.atlasUploadedByteCount = 100
        var first = sample(at: 1.5, backendTimingsAvailable: true)
        first.atlasUploadedByteCount = 150
        var unchanged = sample(at: 1.6, backendTimingsAvailable: true)
        unchanged.atlasUploadedByteCount = 150
        var last = sample(at: 1.7, backendTimingsAvailable: true)
        last.atlasUploadedByteCount = 201
        let report = try makeReport(samples: [prewarmup, first, unchanged, last], atlasTotalBytes: 201)
        let atlas = try object(report, "atlas")
        XCTAssertEqual(atlas["uploadedByteCountAfterWarmup"] as? Int, 101)
        XCTAssertEqual(atlas["uploadedBytesPerFrameAfterWarmup"] as? Double ?? -1, 101.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(atlas["framesThatUploadedAfterWarmup"] as? Int, 2)
    }
}
