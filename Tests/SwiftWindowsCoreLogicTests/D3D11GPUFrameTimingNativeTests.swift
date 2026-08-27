import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Exercises the native query transport through the owned offscreen renderer.
/// Readback supplies the existing test completion boundary; the collector
/// itself only performs its bounded DONOTFLUSH poll. These are correctness
/// checks, not GPU performance budgets or presentation measurements.
@MainActor
final class D3D11GPUFrameTimingNativeTests: XCTestCase {
    func testOffscreenQueriesResolveAndReleaseTheirNativeCOMObjects() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeOwnedRenderer(size: size)
        defer { renderer.detach() }
        let scene = makeScene(size: size)

        // Warm the ordinary draw resources before counting query ownership.
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        let unprofiledPixels = try renderer.readOffscreenPixels()
        XCTAssertEqual(unprofiledPixels.width, size.width)
        XCTAssertEqual(unprofiledPixels.height, size.height)
        let center = (Int(size.height) / 2) * Int(unprofiledPixels.bytesPerRow) + (Int(size.width) / 2) * 4
        let blue = try XCTUnwrap(unprofiledPixels.pixels.dropFirst(center).first)
        let alpha = try XCTUnwrap(unprofiledPixels.pixels.dropFirst(center + 3).first)
        XCTAssertEqual(Int(blue), 204, accuracy: 2)
        XCTAssertEqual(Int(alpha), 255)
        XCTAssertEqual(renderer.lastFrameSubmission?.outcome, .offscreen)
        XCTAssertEqual(renderer.lastFrameSubmission?.gpuTimingStatus, .disabled)
        XCTAssertTrue(renderer.takeCompletedGPUFrameTimings().isEmpty)
        let unprofiledObjectCount = renderer.liveCOMObjectCountForTesting
        XCTAssertGreaterThan(unprofiledObjectCount, 0)
        let warmedAdapter = renderer.backendDiagnostics

        XCTAssertTrue(renderer.setGPUFrameTimingEnabled(true), "Native timestamp query allocation must succeed")
        let enabled = try XCTUnwrap(renderer.gpuFrameTimingDiagnostics)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertTrue(enabled.isSupported)
        XCTAssertNil(enabled.failureCode)
        XCTAssertEqual(enabled.slotCapacity, 8)
        XCTAssertEqual(enabled.resultCapacity, 16)
        XCTAssertEqual(enabled.maximumGetDataCallsPerPoll, 24)
        XCTAssertEqual(enabled.pendingCount, 0)
        XCTAssertEqual(enabled.droppedResultCount, 0)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, unprofiledObjectCount + 24)

        try renderer.render(scene: scene)
        let submitted = try XCTUnwrap(renderer.lastFrameSubmission)
        let firstID = try XCTUnwrap(submitted.id)
        XCTAssertEqual(submitted.outcome, .offscreen)
        XCTAssertEqual(submitted.gpuTimingStatus, .pending)
        XCTAssertEqual(submitted.adapterIsSoftware, warmedAdapter?.adapterIsSoftware)
        XCTAssertEqual(firstID.deviceGeneration, renderer.deviceGeneration)
        XCTAssertEqual(renderer.gpuFrameTimingDiagnostics?.pendingCount, 1)

        // This is the existing offscreen copy/map completion path, not a
        // timing-collector flush or retry loop. After it completes, exactly
        // one bounded poll must return the interval that preceded the copy.
        let timedPixels = try renderer.readOffscreenPixels()
        XCTAssertEqual(timedPixels.pixels, unprofiledPixels.pixels)
        let completed = renderer.takeCompletedGPUFrameTimings()
        XCTAssertEqual(completed.count, 1, "Completed native queries must not remain unavailable or unready")
        let interval = try XCTUnwrap(completed.first)
        XCTAssertEqual(interval.frameID, firstID)
        XCTAssertEqual(interval.status, .valid)
        XCTAssertNil(interval.failureCode)
        let seconds = try XCTUnwrap(interval.elapsedSeconds)
        XCTAssertTrue(seconds.isFinite)
        XCTAssertGreaterThanOrEqual(seconds, 0)
        XCTAssertEqual(renderer.gpuFrameTimingDiagnostics?.pendingCount, 0)
        XCTAssertEqual(renderer.gpuFrameTimingDiagnostics?.droppedResultCount, 0)
        XCTAssertTrue(renderer.takeCompletedGPUFrameTimings().isEmpty, "A native result is delivered only once")
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, unprofiledObjectCount + 24)

        XCTAssertTrue(renderer.setGPUFrameTimingEnabled(false))
        XCTAssertEqual(renderer.gpuFrameTimingDiagnostics?.isEnabled, false)
        XCTAssertEqual(renderer.gpuFrameTimingDiagnostics?.pendingCount, 0)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, unprofiledObjectCount)
        XCTAssertTrue(renderer.takeCompletedGPUFrameTimings().isEmpty)

        // Also tear down with an undrained interval. Its terminal record must
        // survive, while every native query and the context are released.
        XCTAssertTrue(renderer.setGPUFrameTimingEnabled(true))
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, unprofiledObjectCount + 24)
        try renderer.render(scene: scene)
        let undrainedSubmission = try XCTUnwrap(renderer.lastFrameSubmission)
        let undrainedID = try XCTUnwrap(undrainedSubmission.id)
        XCTAssertNotEqual(undrainedID, firstID)
        XCTAssertEqual(undrainedSubmission.outcome, .offscreen)
        XCTAssertEqual(undrainedSubmission.gpuTimingStatus, .pending)
        _ = try renderer.readOffscreenPixels()
        renderer.detach()

        XCTAssertFalse(renderer.isAttached)
        XCTAssertNil(renderer.lastFrameSubmission)
        XCTAssertEqual(renderer.deviceGeneration, 0)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, 0)
        let detached = try XCTUnwrap(renderer.gpuFrameTimingDiagnostics)
        XCTAssertTrue(detached.isEnabled, "Detach preserves the request for a future device")
        XCTAssertFalse(detached.isSupported)
        XCTAssertNil(detached.failureCode)
        XCTAssertEqual(detached.pendingCount, 0)
        XCTAssertEqual(detached.droppedResultCount, 0)
        XCTAssertEqual(
            renderer.takeCompletedGPUFrameTimings(),
            [GPUFrameTimingResult(frameID: undrainedID, status: .cancelled)])
        XCTAssertTrue(renderer.takeCompletedGPUFrameTimings().isEmpty)
        XCTAssertTrue(renderer.setGPUFrameTimingEnabled(false))
        renderer.detach()
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, 0)
    }

    func testRecoverySkipClearsFrameMetricsBeforeTheNextActualDraw() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeOwnedRenderer(size: size)
        defer { renderer.detach() }
        renderer.deviceLostBackoffHandler = { _ in }
        XCTAssertTrue(renderer.setGPUFrameTimingEnabled(true))
        let scene = makeScene(size: size)
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        let originalPixels = try renderer.readOffscreenPixels()
        let originalSubmission = try XCTUnwrap(renderer.lastFrameSubmission)
        let originalID = try XCTUnwrap(originalSubmission.id)
        let originalMetrics = try XCTUnwrap(renderer.backendDiagnostics)
        XCTAssertEqual(originalSubmission.outcome, .offscreen)
        XCTAssertEqual(originalSubmission.gpuTimingStatus, .pending)
        XCTAssertEqual(originalMetrics.lastDrawCallCount, 1)
        XCTAssertEqual(originalMetrics.lastDrawnInstanceCount, 1)
        XCTAssertTrue(originalMetrics.lastSubmitSeconds.isFinite)
        XCTAssertTrue(originalMetrics.lastPresentSeconds.isFinite)

        try renderer.simulateDeviceLossForTesting()
        XCTAssertTrue(renderer.isAttached)
        XCTAssertGreaterThan(renderer.deviceGeneration, originalID.deviceGeneration)
        XCTAssertTrue(renderer.presentationState.needsImmediateRepaint)
        XCTAssertEqual(
            renderer.takeCompletedGPUFrameTimings(),
            [GPUFrameTimingResult(frameID: originalID, status: .deviceLost)])

        // Recovery deliberately consumes one attempt without drawing. None
        // of the preceding device's completed-frame metrics belong to it.
        try renderer.render(scene: scene)
        let skippedSubmission = try XCTUnwrap(renderer.lastFrameSubmission)
        let skippedMetrics = try XCTUnwrap(renderer.backendDiagnostics)
        XCTAssertEqual(skippedSubmission.outcome, .skipped)
        XCTAssertNil(skippedSubmission.id)
        XCTAssertEqual(skippedMetrics.lastSubmitSeconds, 0)
        XCTAssertEqual(skippedMetrics.lastPresentSeconds, 0)
        XCTAssertEqual(skippedMetrics.lastDrawCallCount, 0)
        XCTAssertEqual(skippedMetrics.lastDrawnInstanceCount, 0)
        XCTAssertEqual(renderer.gpuFrameTimingDiagnostics?.pendingCount, 0)
        XCTAssertTrue(renderer.takeCompletedGPUFrameTimings().isEmpty)

        try renderer.render(scene: scene)
        let freshSubmission = try XCTUnwrap(renderer.lastFrameSubmission)
        let freshID = try XCTUnwrap(freshSubmission.id)
        let freshMetrics = try XCTUnwrap(renderer.backendDiagnostics)
        XCTAssertEqual(freshSubmission.outcome, .offscreen)
        XCTAssertEqual(freshSubmission.gpuTimingStatus, .pending)
        XCTAssertNotEqual(freshID, originalID)
        XCTAssertEqual(freshID.deviceGeneration, renderer.deviceGeneration)
        XCTAssertEqual(freshMetrics.lastDrawCallCount, 1)
        XCTAssertEqual(freshMetrics.lastDrawnInstanceCount, 1)
        XCTAssertEqual(try renderer.readOffscreenPixels().pixels, originalPixels.pixels)
        let freshResults = renderer.takeCompletedGPUFrameTimings()
        XCTAssertEqual(freshResults.count, 1)
        XCTAssertEqual(freshResults.first?.frameID, freshID)
        XCTAssertEqual(freshResults.first?.status, .valid)
        XCTAssertNotNil(freshResults.first?.elapsedSeconds)
        XCTAssertTrue(renderer.takeCompletedGPUFrameTimings().isEmpty)
    }

    private func makeOwnedRenderer(size: IntSize) throws -> D3D11BatchRenderer {
        // The shared probe skips only when neither WARP nor hardware can
        // create a D3D11 device. Later attach/query/readback failures must fail
        // this test rather than turn missing instrumentation into a skip.
        let probe = try makeWARPDevice()
        probe.release()
        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            renderer.detach()
            throw error
        }
        // The harness prefers WARP but can fall back to hardware. Record the
        // device actually selected and preserve unknown classification as nil.
        let adapter = renderer.backendDiagnostics
        let software = adapter?.adapterIsSoftware
        print(
            "[D3D11GPUFrameTimingNativeTests] adapter=\(adapter?.adapterDescription ?? "<unavailable>") "
                + "isSoftware=\(software.map { String($0) } ?? "<unavailable>")")
        return renderer
    }

    private func makeScene(size: IntSize) -> GPUIScene {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: Float(size.width), height: Float(size.height),
                startR: 0.2, startG: 0.4, startB: 0.8, startA: 1,
                endR: 0.2, endG: 0.4, endB: 0.8, endA: 1))
        return scene
    }
}
