import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import Synchronization
@preconcurrency import XCTest

@testable import WinSwiftUI

private final class NativeHostQueueTestSink: NativeWindowCommandSink {
    private struct State {
        var commands: [any NativeWindowOwnerCommand] = []
        var rejectNext: NativeWindowOwnerFailure?
    }

    private let state = Mutex(State())

    var count: Int { state.withLock { $0.commands.count } }

    func command(at index: Int) -> (any NativeWindowOwnerCommand)? {
        state.withLock { $0.commands.indices.contains(index) ? $0.commands[index] : nil }
    }

    func failNextPost(with failure: NativeWindowOwnerFailure) {
        state.withLock { $0.rejectNext = failure }
    }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        let failure = state.withLock { stored in
            stored.commands.append(command)
            let failure = stored.rejectNext
            stored.rejectNext = nil
            return failure
        }
        if let failure {
            // Just as in the production sink, no lock spans rejection or the
            // reply callback. Returning .rejected alone is not a completion.
            command.reject(failure)
            return .rejected(failure)
        }
        return .accepted
    }
}

private final class NativeHostQueueTestValues<Value: Sendable>: Sendable {
    private let values = Mutex<[Value]>([])

    func append(_ value: Value) { values.withLock { $0.append(value) } }
    var snapshot: [Value] { values.withLock { $0 } }
}

private func nativeHostQueueTestSurface(generation: UInt64 = 47) -> NativeWindowSurface {
    NativeWindowSurface(
        key: NativeWindowKey(), generation: generation,
        descriptor: SurfaceDescriptor(offscreenPixelSize: IntSize(width: 320, height: 240)),
        geometry: NativeWindowGeometry(
            revision: 3, nativeSequence: 9, clientSize: IntSize(width: 320, height: 240),
            clientScreenOrigin: Point(x: 0, y: 0), scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true))
}

final class NativeHostPresentationQueueTests: XCTestCase {
    func testDrainBarrierWaitsForExecutingReplyAndAllRejectedCallbacks() async throws {
        let sink = NativeHostQueueTestSink()
        let events = NativeHostQueueTestValues<String>()
        let drained = expectation(description: "actor consumed all admitted results")
        let surface = nativeHostQueueTestSurface()
        let queue = await MainActor.run {
            let queue = NativeHostPresentationQueue(
                sink: sink, attachmentID: NativeWindowAttachmentID(), teardownStore: NativePresentationTeardownStore())
            queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { result in
                if case .success = result {} else { XCTFail("The admitted request lost its real late reply") }
                events.append("active-begin")
                XCTAssertFalse(events.snapshot.contains("drained"))
                events.append("active-end")
            }
            queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { result in
                if case .failure(.closing) = result {} else { XCTFail("Expected unsent close rejection") }
                events.append("pending-rejected")
            }
            queue.whenDrained {
                events.append("drained")
                drained.fulfill()
            }
            queue.invalidate()
            XCTAssertEqual(events.snapshot, ["pending-rejected"])
            XCTAssertEqual(sink.count, 1)
            return queue
        }
        let command = try XCTUnwrap(sink.command(at: 0) as? NativePresentationCommand)
        command.reply.complete(
            .success(
                NativePresentationReceipt(
                    requestID: command.requestID, attachmentID: command.attachmentID,
                    surface: surface, operation: .poll, isAttachmentInstalled: true,
                    snapshot: NativePresentationSnapshot(
                        isAttached: true, backendDisplayName: "VALUE TEST",
                        backendStatusDescription: "Late native reply"),
                    startedAtSeconds: 1, completedAtSeconds: 2)))
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(events.snapshot, ["pending-rejected", "active-begin", "active-end", "drained"])
        await MainActor.run { queue.invalidate() }
    }

    func testLateAttachmentKeepsNewActorGeometryAndOldNativeBufferGeneration() throws {
        let attached = nativeHostQueueTestSurface(generation: 47)
        var geometry = attached.geometry
        geometry.revision = 4
        geometry.nativeSequence = 10
        geometry.clientSize = IntSize(width: 640, height: 480)
        geometry.scaleFactor = 2
        geometry.effectiveScaleFactor = 2
        let current = NativeWindowSurface(
            key: attached.key, generation: 48,
            descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize, scaleFactor: 2), geometry: geometry)
        let surfaces = try XCTUnwrap(NativeHostAttachmentSurfaces(attachedSurface: attached, currentSurface: current))
        XCTAssertEqual(surfaces.actorSurface, current)
        XCTAssertEqual(surfaces.attachedSurface, attached)
        XCTAssertTrue(surfaces.requiresNativeResize)
    }

    func testAttachmentCannotApplyGeometryToAnAbsentOrDifferentLifetime() {
        let attached = nativeHostQueueTestSurface()
        XCTAssertNil(NativeHostAttachmentSurfaces(attachedSurface: attached, currentSurface: nil))
        XCTAssertNil(
            NativeHostAttachmentSurfaces(attachedSurface: attached, currentSurface: nativeHostQueueTestSurface()))
    }

    func testStartupCanReuseOnlyAcknowledgedCurrentSubmissionEvidence() {
        XCTAssertTrue(
            NativeHostFrameDisposition.hasCurrentSubmission(
                submittedRevision: 12, currentRevision: 12, attachedSurfaceGeneration: 47,
                currentSurfaceGeneration: 47, isAttached: true, needsImmediateRepaint: false,
                hasUnpreparedContent: false))
        XCTAssertFalse(
            NativeHostFrameDisposition.hasCurrentSubmission(
                submittedRevision: nil, currentRevision: 12, attachedSurfaceGeneration: 47,
                currentSurfaceGeneration: 47, isAttached: true, needsImmediateRepaint: false,
                hasUnpreparedContent: false))
        XCTAssertFalse(
            NativeHostFrameDisposition.hasCurrentSubmission(
                submittedRevision: 12, currentRevision: 13, attachedSurfaceGeneration: 47,
                currentSurfaceGeneration: 47, isAttached: true, needsImmediateRepaint: false,
                hasUnpreparedContent: false))
        XCTAssertFalse(
            NativeHostFrameDisposition.hasCurrentSubmission(
                submittedRevision: 12, currentRevision: 12, attachedSurfaceGeneration: 47,
                currentSurfaceGeneration: 48, isAttached: true, needsImmediateRepaint: false,
                hasUnpreparedContent: false))
        XCTAssertFalse(
            NativeHostFrameDisposition.hasCurrentSubmission(
                submittedRevision: 12, currentRevision: 12, attachedSurfaceGeneration: 47,
                currentSurfaceGeneration: 47, isAttached: true, needsImmediateRepaint: true, hasUnpreparedContent: false
            ))
        XCTAssertFalse(
            NativeHostFrameDisposition.hasCurrentSubmission(
                submittedRevision: 12, currentRevision: 12, attachedSurfaceGeneration: nil,
                currentSurfaceGeneration: nil, isAttached: false, needsImmediateRepaint: false,
                hasUnpreparedContent: false))
        XCTAssertFalse(
            NativeHostFrameDisposition.hasCurrentSubmission(
                submittedRevision: 12, currentRevision: 12, attachedSurfaceGeneration: 47,
                currentSurfaceGeneration: 47, isAttached: true, needsImmediateRepaint: false, hasUnpreparedContent: true
            ))
    }

    func testForeignReceiptCannotCompleteARequestAsSuccessful() async throws {
        let sink = NativeHostQueueTestSink()
        let rejected = expectation(description: "foreign receipt rejected")
        let surface = nativeHostQueueTestSurface()
        let queue = await MainActor.run {
            let queue = NativeHostPresentationQueue(
                sink: sink, attachmentID: NativeWindowAttachmentID(), teardownStore: NativePresentationTeardownStore())
            queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { result in
                if case .failure(.execution) = result {
                } else {
                    XCTFail("A foreign reply crossed the request identity guard")
                }
                rejected.fulfill()
            }
            return queue
        }
        let command = try XCTUnwrap(sink.command(at: 0) as? NativePresentationCommand)
        command.reply.complete(
            .success(
                NativePresentationReceipt(
                    requestID: NativeWindowRequestID(), attachmentID: command.attachmentID,
                    surface: surface, operation: .poll, isAttachmentInstalled: true,
                    snapshot: NativePresentationSnapshot(
                        isAttached: false, backendDisplayName: "VALUE TEST", backendStatusDescription: "No native work"),
                    startedAtSeconds: 1, completedAtSeconds: 2)))
        await fulfillment(of: [rejected], timeout: 2)
        await MainActor.run { queue.invalidate() }
    }

    func testResizeReplyMustMatchItsPreparedSurfaceGeneration() async throws {
        let sink = NativeHostQueueTestSink()
        let rejected = expectation(description: "wrong generation rejected")
        let surface = nativeHostQueueTestSurface(generation: 81)
        let queue = await MainActor.run {
            let queue = NativeHostPresentationQueue(
                sink: sink, attachmentID: NativeWindowAttachmentID(), teardownStore: NativePresentationTeardownStore())
            queue.submit(.resize, surface: surface) { result in
                if case .failure(.staleSurface(expected: 81, actual: 82)) = result {
                } else {
                    XCTFail("A different surface generation was reported as this resize")
                }
                rejected.fulfill()
            }
            return queue
        }
        let command = try XCTUnwrap(sink.command(at: 0) as? NativePresentationCommand)
        let newerSurface = NativeWindowSurface(
            key: surface.key, generation: 82, descriptor: surface.descriptor, geometry: surface.geometry)
        command.reply.complete(
            .success(
                NativePresentationReceipt(
                    requestID: command.requestID, attachmentID: command.attachmentID,
                    surface: newerSurface, operation: .resize, isAttachmentInstalled: true,
                    snapshot: NativePresentationSnapshot(
                        isAttached: false, backendDisplayName: "VALUE TEST", backendStatusDescription: "No native work"),
                    startedAtSeconds: 1, completedAtSeconds: 2)))
        await fulfillment(of: [rejected], timeout: 2)
        await MainActor.run { queue.invalidate() }
    }

    func testUnstartedNativeRollbackCleansActorStateWithoutInventingDestruction() async throws {
        let closed = NativeHostQueueTestValues<String>()
        let (host, frame, batch) = try await MainActor.run {
            let frame = FakeRenderBackend()
            let batch = FakeBatchRenderBackend()
            let factory = try XCTUnwrap(SoftwareWindowRenderBackendFactory().makeNativePresentationFactory())
            let host = WinSwiftUIWindowHost(
                configuration: WindowGroupConfiguration(
                    title: "Unstarted native host", size: IntSize(width: 320, height: 240),
                    clearColor: .black, content: []),
                renderer: frame, batchRenderer: batch, nativePresentationFactory: factory,
                startupProbeConfiguration: nil)
            host.onWindowClosed = { _ in closed.append("closed") }
            XCTAssertTrue(host.usesNativePresentation)
            XCTAssertNil(host.platformWindow.nativeHandle)
            return (host, frame, batch)
        }
        try await host.discardNativeFailedStartup()
        try await host.discardNativeFailedStartup()
        let destroyed = await host.waitForNativeTeardown()
        XCTAssertFalse(destroyed)
        XCTAssertTrue(closed.snapshot.isEmpty)
        await MainActor.run {
            XCTAssertTrue(host.isClosed)
            XCTAssertNil(host.platformWindow.nativeHandle)
            XCTAssertEqual(frame.detachCount, 0)
            XCTAssertEqual(batch.detachCount, 0)
        }
    }

    func testNativeHostRejectsLegacyRunBeforeCreatingAnyWindow() async throws {
        let host = try await MainActor.run {
            let factory = try XCTUnwrap(SoftwareWindowRenderBackendFactory().makeNativePresentationFactory())
            let host = WinSwiftUIWindowHost(
                configuration: WindowGroupConfiguration(
                    title: "Native preflight", size: IntSize(width: 320, height: 240), clearColor: .black, content: []),
                nativePresentationFactory: factory, startupProbeConfiguration: nil)
            XCTAssertThrowsError(try host.run())
            XCTAssertNil(host.platformWindow.nativeHandle)
            return host
        }
        try await host.discardNativeFailedStartup()
    }

    private func frameDisposition(
        outcome: BackendFrameSubmissionOutcome?, currentGeneration: UInt64? = 47,
        currentRevision: UInt64 = 12, needsImmediateRepaint: Bool = false
    ) -> NativeHostFrameDisposition {
        NativeHostFrameDisposition(
            snapshot: NativePresentationSnapshot(
                path: .scene, isAttached: true, backendDisplayName: "HEADLESS VALUE TEST",
                backendStatusDescription: "No renderer was executed",
                presentationState: PresentationState(needsImmediateRepaint: needsImmediateRepaint),
                lastFrameSubmission: outcome.map { BackendFrameSubmission(outcome: $0) }),
            preparedSurfaceGeneration: 47, returnedSurfaceGeneration: 47,
            currentSurfaceGeneration: currentGeneration,
            preparedContentRevision: 12, currentContentRevision: currentRevision)
    }

    func testOnlyActualWindowSubmissionCanAdvanceContentTracking() {
        for outcome in [
            BackendFrameSubmissionOutcome.submitted, .offscreen, .skipped, .occluded, .aborted, .failed,
        ] {
            XCTAssertEqual(frameDisposition(outcome: outcome).canTrackSubmittedContent, outcome == .submitted)
        }
        XCTAssertFalse(frameDisposition(outcome: nil).canTrackSubmittedContent)
    }

    func testLateReceiptCannotClaimTheNewSurfaceAndRequestsRepaint() {
        let changed = frameDisposition(outcome: .submitted, currentGeneration: 48)
        XCTAssertFalse(changed.canTrackSubmittedContent)
        XCTAssertTrue(changed.needsRepaint)
        let destroyed = frameDisposition(outcome: .submitted, currentGeneration: nil)
        XCTAssertFalse(destroyed.canTrackSubmittedContent)
        XCTAssertTrue(destroyed.needsRepaint)
    }

    func testNewRetainedRevisionAndDeviceRecoveryKeepTheirRepaintDebt() {
        let newerContent = frameDisposition(outcome: .submitted, currentRevision: 13)
        XCTAssertTrue(newerContent.canTrackSubmittedContent)
        XCTAssertTrue(newerContent.needsRepaint)
        let rebuiltDevice = frameDisposition(outcome: .skipped, needsImmediateRepaint: true)
        XCTAssertFalse(rebuiltDevice.canTrackSubmittedContent)
        XCTAssertTrue(rebuiltDevice.needsRepaint)
        XCTAssertFalse(frameDisposition(outcome: .submitted).needsRepaint)
    }

    func testAdmissionDoesNotReleaseNextCommandBeforeRealReply() async throws {
        let sink = NativeHostQueueTestSink()
        let first = expectation(description: "first terminal reply")
        let second = expectation(description: "second terminal reply")
        let queue = await MainActor.run {
            let queue = NativeHostPresentationQueue(
                sink: sink, attachmentID: NativeWindowAttachmentID(), teardownStore: NativePresentationTeardownStore())
            let surface = nativeHostQueueTestSurface()
            queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { result in
                if case .failure(.unavailable) = result {} else { XCTFail("Expected actual first rejection") }
                first.fulfill()
            }
            queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { result in
                if case .failure(.closed) = result {} else { XCTFail("Expected actual second rejection") }
                second.fulfill()
            }
            XCTAssertEqual(sink.count, 1)
            return queue
        }
        try XCTUnwrap(sink.command(at: 0)).reject(.unavailable)
        await fulfillment(of: [first], timeout: 2)
        await MainActor.run { XCTAssertEqual(sink.count, 2) }
        try XCTUnwrap(sink.command(at: 1)).reject(.closed)
        await fulfillment(of: [second], timeout: 2)
        await MainActor.run { queue.invalidate() }
    }

    func testCloseRejectsWaitingWorkButKeepsExecutingRequestAlive() async throws {
        let sink = NativeHostQueueTestSink()
        let active = expectation(description: "native operation actually ended")
        let waiting = expectation(description: "unsubmitted operation rejected")
        let replies = NativeHostQueueTestValues<String>()
        let queue = await MainActor.run {
            let queue = NativeHostPresentationQueue(
                sink: sink, attachmentID: NativeWindowAttachmentID(), teardownStore: NativePresentationTeardownStore())
            let surface = nativeHostQueueTestSurface()
            queue.submit(.resize, surface: surface) { result in
                if case .failure(.ownerStopped) = result {} else { XCTFail("Active reply was fabricated by close") }
                replies.append("active")
                active.fulfill()
            }
            queue.submit(.resize, surface: surface) { result in
                if case .failure(.closing) = result {} else { XCTFail("Queued work must be rejected before execution") }
                replies.append("waiting")
                waiting.fulfill()
            }
            queue.invalidate()
            XCTAssertEqual(replies.snapshot, ["waiting"])
            XCTAssertEqual(sink.count, 1)
            return queue
        }
        await fulfillment(of: [waiting], timeout: 2)
        try XCTUnwrap(sink.command(at: 0)).reject(.ownerStopped)
        await fulfillment(of: [active], timeout: 2)
        XCTAssertEqual(replies.snapshot, ["waiting", "active"])
        await MainActor.run { queue.invalidate() }
    }

    func testCompletionReentryCannotStartTheNextCommandInsideTheCallback() async throws {
        let sink = NativeHostQueueTestSink()
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let third = expectation(description: "third")
        let counts = NativeHostQueueTestValues<Int>()
        let queue = await MainActor.run {
            let queue = NativeHostPresentationQueue(
                sink: sink, attachmentID: NativeWindowAttachmentID(), teardownStore: NativePresentationTeardownStore())
            let surface = nativeHostQueueTestSurface()
            queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { _ in
                counts.append(sink.count)
                queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { _ in third.fulfill() }
                counts.append(sink.count)
                first.fulfill()
            }
            queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { _ in second.fulfill() }
            return queue
        }
        try XCTUnwrap(sink.command(at: 0)).reject(.unavailable)
        await fulfillment(of: [first], timeout: 2)
        await MainActor.run { XCTAssertEqual(sink.count, 2) }
        XCTAssertEqual(counts.snapshot, [1, 1])
        try XCTUnwrap(sink.command(at: 1)).reject(.unavailable)
        await fulfillment(of: [second], timeout: 2)
        await MainActor.run { XCTAssertEqual(sink.count, 3) }
        try XCTUnwrap(sink.command(at: 2)).reject(.unavailable)
        await fulfillment(of: [third], timeout: 2)
        await MainActor.run { queue.invalidate() }
    }

    func testImmediatePostFailureIsAnActualReplyAndDoesNotStickTheQueue() async throws {
        let sink = NativeHostQueueTestSink()
        sink.failNextPost(with: .postFailed(code: 1816))
        let failed = expectation(description: "post failure delivered")
        let next = expectation(description: "next command completed")
        let queue = await MainActor.run {
            let queue = NativeHostPresentationQueue(
                sink: sink, attachmentID: NativeWindowAttachmentID(), teardownStore: NativePresentationTeardownStore())
            let surface = nativeHostQueueTestSurface()
            queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { result in
                if case .failure(.postFailed(code: 1816)) = result {} else { XCTFail("Native error code was lost") }
                failed.fulfill()
            }
            queue.submit(.poll, surface: surface, requiresSurfaceGeneration: false) { _ in next.fulfill() }
            XCTAssertEqual(sink.count, 1)
            return queue
        }
        await fulfillment(of: [failed], timeout: 2)
        await MainActor.run { XCTAssertEqual(sink.count, 2) }
        try XCTUnwrap(sink.command(at: 1)).reject(.unavailable)
        await fulfillment(of: [next], timeout: 2)
        await MainActor.run { queue.invalidate() }
    }

    func testDuplicateTerminalSignalsDeliverTheReplyExactlyOnce() async throws {
        let sink = NativeHostQueueTestSink()
        let completed = expectation(description: "single reply")
        let replies = NativeHostQueueTestValues<Int>()
        let queue = await MainActor.run {
            let queue = NativeHostPresentationQueue(
                sink: sink, attachmentID: NativeWindowAttachmentID(), teardownStore: NativePresentationTeardownStore())
            queue.submit(.poll, surface: nativeHostQueueTestSurface(), requiresSurfaceGeneration: false) { _ in
                replies.append(1)
                completed.fulfill()
            }
            return queue
        }
        let command = try XCTUnwrap(sink.command(at: 0))
        command.reject(.ownerStopped)
        command.reject(.closed)
        await fulfillment(of: [completed], timeout: 2)
        await MainActor.run { queue.invalidate() }
        XCTAssertEqual(replies.snapshot, [1])
    }

    func testSurfaceDependentCommandsKeepCapturedGenerationAndLifetime() async throws {
        let sink = NativeHostQueueTestSink()
        let resized = expectation(description: "resize reply")
        let configured = expectation(description: "configure reply")
        let surface = nativeHostQueueTestSurface(generation: 81)
        let queue = await MainActor.run {
            let queue = NativeHostPresentationQueue(
                sink: sink, attachmentID: NativeWindowAttachmentID(), teardownStore: NativePresentationTeardownStore())
            queue.submit(.resize, surface: surface) { _ in resized.fulfill() }
            queue.submit(
                .configure(NativePresentationConfiguration()), surface: surface, requiresSurfaceGeneration: false
            ) {
                _ in configured.fulfill()
            }
            return queue
        }
        let resize = try XCTUnwrap(sink.command(at: 0))
        XCTAssertEqual(resize.windowKey, surface.key)
        XCTAssertEqual(resize.expectedSurfaceGeneration, 81)
        resize.reject(.staleSurface(expected: 81, actual: 82))
        await fulfillment(of: [resized], timeout: 2)
        await MainActor.run { XCTAssertEqual(sink.count, 2) }
        let configure = try XCTUnwrap(sink.command(at: 1))
        XCTAssertEqual(configure.windowKey, surface.key)
        XCTAssertNil(configure.expectedSurfaceGeneration)
        configure.reject(.closed)
        await fulfillment(of: [configured], timeout: 2)
        await MainActor.run { queue.invalidate() }
    }
}
