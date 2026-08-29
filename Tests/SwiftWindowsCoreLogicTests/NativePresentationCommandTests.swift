import Synchronization
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsGraphics

private struct PresentationCommandTestError: Error, ClassifiedPresentationFailure, Equatable, Sendable {
    let operation: String
    let code: Int32
    let presentationFailureKind: PresentationFailureKind
}

private struct PresentationCommandTestPlan: Sendable {
    var sceneAttachError: PresentationCommandTestError?
    var resizeErrors: [PresentationCommandTestError?] = []
    var detachResults: [NativeWindowAttachmentDetachResult] = []
    var renderOutcomes: [BackendFrameSubmissionOutcome] = [.submitted]
    var recordsPendingTiming = false
    var configurationAcceptance = NativePresentationConfigurationResult(
        presentsWithVSyncAccepted: true,
        capturesPresentedFramesAccepted: true,
        gpuFrameTimingEnabledAccepted: true)
}

private struct PresentationCommandTestRecord: Sendable {
    var registered: Set<NativeWindowAttachmentID> = []
    var events: [String] = []
    var backendObservedRegistration: [Bool] = []
    var configurations: [NativePresentationConfiguration] = []
    var detachedResourceStates: [Bool] = []
    var resizedSurfaces: [SurfaceDescriptor] = []
    var renderedFrames = 0
    var wakes = 0
    var replies: [Result<NativePresentationReceipt, NativeWindowOwnerFailure>] = []
}

/// Only copied values cross the factory/reply boundary. Neither this recorder
/// nor the checked-Sendable factory holds an owner, attachment, or backend.
private final class PresentationCommandTestRecorder: Sendable {
    let state = Mutex(PresentationCommandTestRecord())

    func read() -> PresentationCommandTestRecord {
        state.withLock { $0 }
    }

    func observe(_ event: String, attachmentID: NativeWindowAttachmentID) {
        state.withLock {
            $0.events.append(event)
            $0.backendObservedRegistration.append($0.registered.contains(attachmentID))
        }
    }

    func makeReply() -> NativeWindowReply<NativePresentationReceipt> {
        NativeWindowReply { [self] result in
            state.withLock { $0.replies.append(result) }
        }
    }
}

private struct PresentationCommandTestFactory: NativePresentationBackendFactory {
    let attachmentID: NativeWindowAttachmentID
    let recorder: PresentationCommandTestRecorder
    let plan: PresentationCommandTestPlan

    var factoryName: String { "HEADLESS TEST" }
    var capabilities: RenderBackendCapabilities { .cpuOffscreen }

    func makeBackend() -> any NativePresentationBackend {
        recorder.observe("construct", attachmentID: attachmentID)
        return PresentationCommandTestBackend(attachmentID: attachmentID, recorder: recorder, plan: plan)
    }
}

/// A local, nonactor owner of fake state. No operation creates a native handle,
/// COM object, graphics device, timer, or renderer from the D3D11 module.
private final class PresentationCommandTestBackend: NativePresentationBackend {
    private let attachmentID: NativeWindowAttachmentID
    private let recorder: PresentationCommandTestRecorder
    private var plan: PresentationCommandTestPlan
    private var path: NativePresentationPath?
    private var isAttached = false
    private var hasResources = false
    private var frameNumber: UInt64 = 0
    private var submission: BackendFrameSubmission?
    private var pendingTimingIDs: [BackendFrameID] = []
    private var completedTimings: [GPUFrameTimingResult] = []
    private var configurationResult = NativePresentationConfigurationResult()

    init(
        attachmentID: NativeWindowAttachmentID, recorder: PresentationCommandTestRecorder,
        plan: PresentationCommandTestPlan
    ) {
        self.attachmentID = attachmentID
        self.recorder = recorder
        self.plan = plan
    }

    func attach(to surface: SurfaceDescriptor, path: NativePresentationPath) throws {
        recorder.observe("attach.\(path.rawValue)", attachmentID: attachmentID)
        hasResources = true
        if path == .scene, let error = plan.sceneAttachError { throw error }
        self.path = path
        isAttached = true
    }

    func resize(to surface: SurfaceDescriptor) throws {
        recorder.observe("resize", attachmentID: attachmentID)
        recorder.state.withLock { $0.resizedSurfaces.append(surface) }
        if !plan.resizeErrors.isEmpty, let error = plan.resizeErrors.removeFirst() { throw error }
    }

    func render(scene: GPUIScene) throws { renderAttempt() }
    func render(frame: RenderFrame) throws { renderAttempt() }

    private func renderAttempt() {
        recorder.observe("render", attachmentID: attachmentID)
        recorder.state.withLock { $0.renderedFrames += 1 }
        let outcome = plan.renderOutcomes.isEmpty ? .submitted : plan.renderOutcomes.removeFirst()
        frameNumber += 1
        let id = BackendFrameID(deviceGeneration: 42, frameNumber: frameNumber)
        let recordsTiming = plan.recordsPendingTiming && outcome != .skipped
        submission = BackendFrameSubmission(
            id: outcome == .skipped ? nil : id, outcome: outcome,
            gpuTimingStatus: recordsTiming ? .pending : .disabled)
        if recordsTiming { pendingTimingIDs.append(id) }
    }

    @discardableResult
    func configure(_ configuration: NativePresentationConfiguration) -> NativePresentationConfigurationResult {
        recorder.observe("configure", attachmentID: attachmentID)
        recorder.state.withLock { $0.configurations.append(configuration) }
        configurationResult = NativePresentationConfigurationResult(
            presentsWithVSyncAccepted:
                configuration.presentsWithVSync == nil ? nil : plan.configurationAcceptance.presentsWithVSyncAccepted,
            capturesPresentedFramesAccepted:
                configuration.capturesPresentedFrames == nil
                ? nil : plan.configurationAcceptance.capturesPresentedFramesAccepted,
            gpuFrameTimingEnabledAccepted:
                configuration.gpuFrameTimingEnabled == nil
                ? nil : plan.configurationAcceptance.gpuFrameTimingEnabledAccepted)
        return configurationResult
    }

    func takeSnapshot() -> NativePresentationSnapshot {
        recorder.observe("snapshot", attachmentID: attachmentID)
        let timings = completedTimings
        completedTimings.removeAll()
        return NativePresentationSnapshot(
            path: path, isAttached: isAttached,
            backendDisplayName: "HEADLESS TEST", backendStatusDescription: "VALUE STATE ONLY",
            presentationState: PresentationState(isOccluded: submission?.outcome == .occluded),
            lastFrameSubmission: submission, completedGPUFrameTimings: timings,
            configurationResult: configurationResult)
    }

    func detach() -> NativeWindowAttachmentDetachResult {
        recorder.observe("detach", attachmentID: attachmentID)
        recorder.state.withLock { $0.detachedResourceStates.append(hasResources) }
        let result =
            plan.detachResults.isEmpty
            ? NativeWindowAttachmentDetachResult(isDetached: true) : plan.detachResults.removeFirst()
        if result.isDetached {
            hasResources = false
            isAttached = false
            path = nil
            submission = nil
            completedTimings += pendingTimingIDs.map { GPUFrameTimingResult(frameID: $0, status: .cancelled) }
            pendingTimingIDs.removeAll()
        }
        return result
    }
}

private struct PresentationCommandTestSnapshotSource: NativeWindowSnapshotSource {
    let surface: NativeWindowSurface

    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { .success(surface) }
}

private final class PresentationCommandTestContext: NativeWindowOwnerContext {
    var surface: NativeWindowSurface
    private let recorder: PresentationCommandTestRecorder
    private var attachments: [NativeWindowAttachmentID: any NativeWindowOwnerAttachment] = [:]

    init(surface: NativeWindowSurface, recorder: PresentationCommandTestRecorder) {
        self.surface = surface
        self.recorder = recorder
    }

    var snapshotSource: any NativeWindowSnapshotSource { PresentationCommandTestSnapshotSource(surface: surface) }

    var wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure> {
        let recorder = recorder
        return {
            recorder.state.withLock { $0.wakes += 1 }
            return .success(())
        }
    }

    func attachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? { attachments[id] }

    func install(_ attachment: any NativeWindowOwnerAttachment, for id: NativeWindowAttachmentID) throws {
        guard attachments[id] == nil else { throw NativeWindowOwnerFailure.duplicateAttachment(id) }
        attachments[id] = attachment
        recorder.state.withLock {
            $0.registered.insert(id)
            $0.events.append("install")
        }
    }

    func removeAttachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? {
        let removed = attachments.removeValue(forKey: id)
        recorder.state.withLock {
            $0.registered.remove(id)
            $0.events.append("remove")
        }
        return removed
    }

    func withNativeModal<Result>(_ body: () throws -> Result) rethrows -> Result { try body() }
}

private func presentationCommandTestSurface(
    key: NativeWindowKey = NativeWindowKey(), generation: UInt64 = 1,
    size: IntSize = IntSize(width: 80, height: 60)
) -> NativeWindowSurface {
    NativeWindowSurface(
        key: key, generation: generation, descriptor: SurfaceDescriptor(offscreenPixelSize: size),
        geometry: NativeWindowGeometry(
            revision: generation, nativeSequence: generation, clientSize: size,
            clientScreenOrigin: Point(x: 0, y: 0), scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true))
}

/// Mirrors the sink's failure boundary: execute throws transport errors, and
/// the sink must reject them. A returned backend failure stays inside a receipt.
private func executePresentationTestCommand(
    _ command: NativePresentationCommand, in context: PresentationCommandTestContext
) {
    do {
        try command.execute(in: context)
    } catch let failure as NativeWindowOwnerFailure {
        command.reject(failure)
    } catch {
        command.reject(.execution(String(describing: error)))
    }
}

private struct PresentationCommandTestFixture {
    let attachmentID: NativeWindowAttachmentID
    let recorder: PresentationCommandTestRecorder
    let context: PresentationCommandTestContext
    let factory: PresentationCommandTestFactory

    init(plan: PresentationCommandTestPlan = PresentationCommandTestPlan()) {
        let attachmentID = NativeWindowAttachmentID()
        let recorder = PresentationCommandTestRecorder()
        self.attachmentID = attachmentID
        self.recorder = recorder
        context = PresentationCommandTestContext(surface: presentationCommandTestSurface(), recorder: recorder)
        factory = PresentationCommandTestFactory(attachmentID: attachmentID, recorder: recorder, plan: plan)
    }

    @discardableResult
    func send(
        _ operation: NativePresentationOperation, generation: UInt64?, key: NativeWindowKey? = nil,
        teardownStore: NativePresentationTeardownStore? = nil
    ) -> NativePresentationCommand {
        let command = NativePresentationCommand(
            windowKey: key ?? context.surface.key, attachmentID: attachmentID,
            expectedSurfaceGeneration: generation, operation: operation, reply: recorder.makeReply(),
            teardownStore: teardownStore)
        executePresentationTestCommand(command, in: context)
        return command
    }

    @discardableResult
    func install(
        path: NativePresentationPath = .frame, teardownStore: NativePresentationTeardownStore? = nil
    ) -> NativePresentationCommand {
        send(
            .install(factory: factory, path: path, configuration: NativePresentationConfiguration()),
            generation: context.surface.generation, teardownStore: teardownStore)
    }

    func receipt(file: StaticString = #filePath, line: UInt = #line) throws -> NativePresentationReceipt {
        try XCTUnwrap(recorder.read().replies.last, file: file, line: line).get()
    }

    func rejection(file: StaticString = #filePath, line: UInt = #line) throws -> NativeWindowOwnerFailure {
        let result = try XCTUnwrap(recorder.read().replies.last, file: file, line: line)
        guard case .failure(let failure) = result else {
            XCTFail("Expected a transport rejection, not a backend receipt.", file: file, line: line)
            throw NativeWindowOwnerFailure.execution("Expected transport rejection")
        }
        return failure
    }
}

final class NativePresentationCommandTests: XCTestCase {
    func testStaleWindowAndSurfaceRejectBeforeBackendConstruction() async throws {
        let staleWindow = PresentationCommandTestFixture()
        staleWindow.send(
            .install(factory: staleWindow.factory, path: .frame, configuration: NativePresentationConfiguration()),
            generation: 1, key: NativeWindowKey(windowID: staleWindow.context.surface.key.windowID))
        XCTAssertEqual(try staleWindow.rejection(), .staleWindow)
        XCTAssertTrue(staleWindow.recorder.read().events.isEmpty)
        XCTAssertNil(staleWindow.context.attachment(for: staleWindow.attachmentID))

        let staleSurface = PresentationCommandTestFixture()
        staleSurface.send(
            .install(factory: staleSurface.factory, path: .frame, configuration: NativePresentationConfiguration()),
            generation: 0)
        XCTAssertEqual(try staleSurface.rejection(), .staleSurface(expected: 0, actual: 1))
        XCTAssertTrue(staleSurface.recorder.read().events.isEmpty)
        XCTAssertNil(staleSurface.context.attachment(for: staleSurface.attachmentID))
    }

    func testMissingSurfaceGenerationRejectsInstallAndEverySurfaceOperation() async throws {
        let fixture = PresentationCommandTestFixture()
        let missing = NativeWindowOwnerFailure.execution("Presentation work requires a captured surface generation.")
        fixture.send(
            .install(factory: fixture.factory, path: .frame, configuration: NativePresentationConfiguration()),
            generation: nil)
        XCTAssertEqual(try fixture.rejection(), missing)
        XCTAssertTrue(fixture.recorder.read().events.isEmpty)

        fixture.install()
        XCTAssertNil(try fixture.receipt().failure)
        let events = fixture.recorder.read().events
        let operations: [NativePresentationOperation] = [
            .attach(path: .frame), .resize, .renderScene(GPUIScene()), .renderFrame(RenderFrame()),
        ]
        for operation in operations {
            fixture.send(operation, generation: nil)
            XCTAssertEqual(try fixture.rejection(), missing)
            XCTAssertEqual(fixture.recorder.read().events, events)
        }
    }

    func testRegistrationPrecedesConstructionAndSnapshotFollowsAttachment() async throws {
        let fixture = PresentationCommandTestFixture()
        let command = fixture.install(path: .scene)
        let receipt = try fixture.receipt()
        XCTAssertEqual(
            fixture.recorder.read().events, ["install", "construct", "configure", "detach", "attach.scene", "snapshot"])
        XCTAssertTrue(fixture.recorder.read().backendObservedRegistration.allSatisfy { $0 })
        XCTAssertEqual(receipt.requestID, command.requestID)
        XCTAssertEqual(receipt.attachmentID, fixture.attachmentID)
        XCTAssertEqual(receipt.surface, fixture.context.surface)
        XCTAssertTrue(receipt.isAttachmentInstalled)
        XCTAssertTrue(receipt.snapshot.isAttached)
        XCTAssertEqual(receipt.snapshot.path, .scene)
        XCTAssertNil(receipt.failure)
        let attachment = try XCTUnwrap(fixture.context.attachment(for: fixture.attachmentID))
        XCTAssertTrue(attachment.isQuiescent)
        // These are call-order and post-completion assertions. They do not
        // inspect the private active-operation gate inside a constructor.
    }

    func testFailedAttachCleansPartialStateAndRetainsAttachmentForFrameFallback() async throws {
        let primary = PresentationCommandTestError(
            operation: "scene attach", code: -23, presentationFailureKind: .permanent)
        var plan = PresentationCommandTestPlan()
        plan.sceneAttachError = primary
        let fixture = PresentationCommandTestFixture(plan: plan)
        fixture.install(path: .scene)
        let failed = try fixture.receipt()
        XCTAssertEqual(failed.failure?.underlyingError as? PresentationCommandTestError, primary)
        XCTAssertTrue(failed.isAttachmentInstalled)
        XCTAssertFalse(failed.snapshot.isAttached)
        XCTAssertEqual(fixture.recorder.read().detachedResourceStates, [false, true])
        let installed = try XCTUnwrap(fixture.context.attachment(for: fixture.attachmentID))

        fixture.send(.attach(path: .frame), generation: 1)
        let recovered = try fixture.receipt()
        XCTAssertNil(recovered.failure)
        XCTAssertTrue(recovered.snapshot.isAttached)
        XCTAssertEqual(recovered.snapshot.path, .frame)
        XCTAssertTrue(fixture.context.attachment(for: fixture.attachmentID) === installed)
        XCTAssertEqual(fixture.recorder.read().events.filter { $0 == "construct" }.count, 1)
        XCTAssertEqual(fixture.recorder.read().detachedResourceStates, [false, true, false])
    }

    func testPrimaryTypedFailureAndClassificationSurviveFailedCleanup() async throws {
        let primary = PresentationCommandTestError(
            operation: "scene upload", code: -47, presentationFailureKind: .sceneContent)
        let cleanup = NativeWindowAttachmentDetachResult(
            isDetached: false, failures: [.native(operation: "fake detach", code: -71)])
        var plan = PresentationCommandTestPlan()
        plan.sceneAttachError = primary
        plan.detachResults = [NativeWindowAttachmentDetachResult(isDetached: true), cleanup]
        let fixture = PresentationCommandTestFixture(plan: plan)
        fixture.install(path: .scene)

        let receipt = try fixture.receipt()
        let failure = try XCTUnwrap(receipt.failure)
        XCTAssertEqual(failure.underlyingError as? PresentationCommandTestError, primary)
        XCTAssertEqual(failure.presentationFailureKind, .sceneContent)
        XCTAssertEqual(PresentationFailureKind.classifying(failure), .sceneContent)
        XCTAssertEqual(failure.cleanupResult, cleanup)
        XCTAssertTrue(receipt.isAttachmentInstalled)
        XCTAssertNotNil(fixture.context.attachment(for: fixture.attachmentID))
        XCTAssertEqual(fixture.recorder.read().detachedResourceStates, [false, true])
    }

    func testReplyRemainsTerminalAfterDuplicateSuccessAndRejection() async throws {
        let fixture = PresentationCommandTestFixture()
        let command = fixture.install()
        let completed = try fixture.receipt()
        command.reject(.closed)
        XCTAssertFalse(command.reply.complete(.failure(.ownerStopped)))
        XCTAssertFalse(command.reply.complete(.success(completed)))
        XCTAssertEqual(fixture.recorder.read().replies.count, 1)
        XCTAssertEqual(try fixture.receipt().requestID, command.requestID)

        let recorder = PresentationCommandTestRecorder()
        let reply = recorder.makeReply()
        XCTAssertTrue(reply.complete(.failure(.closing)))
        XCTAssertFalse(reply.complete(.success(completed)))
        XCTAssertFalse(reply.complete(.failure(.closed)))
        XCTAssertEqual(recorder.read().replies.count, 1)
        guard case .failure(let failure) = try XCTUnwrap(recorder.read().replies.first) else {
            return XCTFail("The first failure must remain the terminal result.")
        }
        XCTAssertEqual(failure, .closing)
    }

    func testCompletedCommandDoesNotPromoteSkippedFailedOrOccludedSubmission() async throws {
        let outcomes: [BackendFrameSubmissionOutcome] = [.submitted, .skipped, .failed, .occluded, .aborted]
        var plan = PresentationCommandTestPlan()
        plan.renderOutcomes = outcomes
        let fixture = PresentationCommandTestFixture(plan: plan)
        fixture.install()

        for outcome in outcomes {
            fixture.send(.renderFrame(RenderFrame()), generation: 1)
            let receipt = try fixture.receipt()
            let submission = try XCTUnwrap(receipt.snapshot.lastFrameSubmission)
            XCTAssertNil(receipt.failure, "A completed command is distinct from the backend's submission outcome.")
            XCTAssertEqual(submission.outcome, outcome)
            XCTAssertEqual(submission.gpuTimingStatus, .disabled)
            XCTAssertEqual(receipt.snapshot.presentationState.isOccluded, outcome == .occluded)
            if outcome == .skipped {
                XCTAssertNil(submission.id)
            } else {
                XCTAssertNotNil(submission.id)
            }
            if outcome != .submitted { XCTAssertNotEqual(submission.outcome, .submitted) }
        }
        XCTAssertEqual(fixture.recorder.read().renderedFrames, outcomes.count)
    }

    func testResizeRequiresCurrentGenerationAndRenewsTheRenderingLease() async throws {
        let fixture = PresentationCommandTestFixture()
        fixture.install()
        fixture.context.surface = presentationCommandTestSurface(
            key: fixture.context.surface.key, generation: 2, size: IntSize(width: 120, height: 90))

        fixture.send(.resize, generation: 1)
        XCTAssertEqual(try fixture.rejection(), .staleSurface(expected: 1, actual: 2))
        XCTAssertTrue(fixture.recorder.read().resizedSurfaces.isEmpty)
        fixture.send(.renderFrame(RenderFrame()), generation: 2)
        XCTAssertEqual(try fixture.rejection(), .staleSurface(expected: 1, actual: 2))
        XCTAssertEqual(fixture.recorder.read().renderedFrames, 0)

        fixture.send(.resize, generation: 2)
        XCTAssertNil(try fixture.receipt().failure)
        XCTAssertEqual(fixture.recorder.read().resizedSurfaces, [fixture.context.surface.descriptor])
        fixture.send(.renderFrame(RenderFrame()), generation: 2)
        XCTAssertEqual(try fixture.receipt().snapshot.lastFrameSubmission?.outcome, .submitted)
        fixture.send(.renderFrame(RenderFrame()), generation: 1)
        XCTAssertEqual(try fixture.rejection(), .staleSurface(expected: 1, actual: 2))
        XCTAssertEqual(fixture.recorder.read().renderedFrames, 1)
    }

    func testFailedResizeDoesNotRenewTheRenderingLease() async throws {
        let primary = PresentationCommandTestError(operation: "resize", code: -61, presentationFailureKind: .transient)
        var plan = PresentationCommandTestPlan()
        plan.resizeErrors = [primary, nil]
        let fixture = PresentationCommandTestFixture(plan: plan)
        fixture.install()
        fixture.context.surface = presentationCommandTestSurface(key: fixture.context.surface.key, generation: 2)

        fixture.send(.resize, generation: 2)
        XCTAssertEqual(try fixture.receipt().failure?.underlyingError as? PresentationCommandTestError, primary)
        fixture.send(.renderFrame(RenderFrame()), generation: 2)
        XCTAssertEqual(try fixture.rejection(), .staleSurface(expected: 1, actual: 2))
        XCTAssertEqual(fixture.recorder.read().renderedFrames, 0)
        fixture.send(.resize, generation: 2)
        XCTAssertNil(try fixture.receipt().failure)
        fixture.send(.renderFrame(RenderFrame()), generation: 2)
        XCTAssertEqual(try fixture.receipt().snapshot.lastFrameSubmission?.outcome, .submitted)
    }

    func testDetachTakesSnapshotWhileRegisteredBeforeRemovingAttachment() async throws {
        let fixture = PresentationCommandTestFixture()
        fixture.install()
        let previousEventCount = fixture.recorder.read().events.count
        fixture.send(.detach(removeAttachment: true), generation: nil)

        let receipt = try fixture.receipt()
        XCTAssertNil(receipt.failure)
        XCTAssertFalse(receipt.isAttachmentInstalled)
        XCTAssertFalse(receipt.snapshot.isAttached)
        XCTAssertNil(fixture.context.attachment(for: fixture.attachmentID))
        XCTAssertEqual(
            Array(fixture.recorder.read().events.dropFirst(previousEventCount)), ["detach", "snapshot", "remove"])
        XCTAssertTrue(fixture.recorder.read().backendObservedRegistration.allSatisfy { $0 })
    }

    func testFailedDetachKeepsAttachmentRegisteredForRetry() async throws {
        let failure = NativeWindowAttachmentDetachResult(isDetached: false, failures: [.closing])
        var plan = PresentationCommandTestPlan()
        plan.detachResults = [NativeWindowAttachmentDetachResult(isDetached: true), failure]
        let fixture = PresentationCommandTestFixture(plan: plan)
        fixture.install()
        fixture.send(.detach(removeAttachment: true), generation: nil)

        let receipt = try fixture.receipt()
        XCTAssertNotNil(receipt.failure)
        XCTAssertTrue(receipt.isAttachmentInstalled)
        XCTAssertTrue(receipt.snapshot.isAttached)
        XCTAssertNotNil(fixture.context.attachment(for: fixture.attachmentID))
        XCTAssertFalse(fixture.recorder.read().events.contains("remove"))
    }

    func testQuiescenceRejectsRenderingAndFinalDetachPublishesConsumableTimingCancellation() async throws {
        var plan = PresentationCommandTestPlan()
        plan.recordsPendingTiming = true
        let fixture = PresentationCommandTestFixture(plan: plan)
        let store = NativePresentationTeardownStore()
        fixture.install(path: .scene, teardownStore: store)
        fixture.send(.renderScene(GPUIScene()), generation: 1)
        let rendered = try fixture.receipt()
        let frameID = try XCTUnwrap(rendered.snapshot.lastFrameSubmission?.id)
        XCTAssertEqual(rendered.snapshot.lastFrameSubmission?.gpuTimingStatus, .pending)
        XCTAssertNil(store.takeReceipt())

        let attachment = try XCTUnwrap(fixture.context.attachment(for: fixture.attachmentID))
        attachment.beginQuiescence()
        XCTAssertTrue(attachment.isQuiescent)
        fixture.send(.renderScene(GPUIScene()), generation: 1)
        XCTAssertEqual(try fixture.rejection(), .closing)
        XCTAssertEqual(fixture.recorder.read().renderedFrames, 1)

        let detached = attachment.detach()
        XCTAssertEqual(detached, NativeWindowAttachmentDetachResult(isDetached: true))
        XCTAssertTrue(attachment.isQuiescent)
        let teardown = try XCTUnwrap(store.takeReceipt())
        XCTAssertEqual(teardown.windowKey, fixture.context.surface.key)
        XCTAssertEqual(teardown.attachmentID, fixture.attachmentID)
        XCTAssertEqual(teardown.result, detached)
        XCTAssertFalse(teardown.snapshot.isAttached)
        XCTAssertNil(teardown.snapshot.path)
        XCTAssertEqual(
            teardown.snapshot.completedGPUFrameTimings,
            [GPUFrameTimingResult(frameID: frameID, status: .cancelled)])
        XCTAssertNil(store.takeReceipt())
        XCTAssertTrue(fixture.recorder.read().backendObservedRegistration.allSatisfy { $0 })
        XCTAssertEqual(fixture.recorder.read().wakes, 1)
        XCTAssertNotNil(fixture.context.removeAttachment(for: fixture.attachmentID))
    }

    func testConfigurationPreservesFalseRequestsAndActualAcceptanceBooleans() async throws {
        var plan = PresentationCommandTestPlan()
        plan.configurationAcceptance = NativePresentationConfigurationResult(
            presentsWithVSyncAccepted: false, capturesPresentedFramesAccepted: true,
            gpuFrameTimingEnabledAccepted: false)
        let fixture = PresentationCommandTestFixture(plan: plan)
        fixture.install()
        let update = NativePresentationConfiguration(
            displayFrameInterval: 1.0 / 120, presentsWithVSync: false,
            capturesPresentedFrames: true, gpuFrameTimingEnabled: false, adoptRememberedSelfPacing: true)
        fixture.send(.configure(update), generation: nil)
        let configured = try fixture.receipt()
        XCTAssertNil(configured.failure)
        XCTAssertEqual(fixture.recorder.read().configurations.last, update)
        XCTAssertEqual(configured.snapshot.configurationResult, plan.configurationAcceptance)

        fixture.send(.configure(NativePresentationConfiguration(displayFrameInterval: 1.0 / 60)), generation: nil)
        XCTAssertEqual(try fixture.receipt().snapshot.configurationResult, NativePresentationConfigurationResult())
    }

    func testConfigurationMergeKeepsExplicitFalseAndLeavesUnrequestedFieldsUnchanged() async {
        var configuration = NativePresentationConfiguration(
            displayFrameInterval: 1.0 / 60, presentsWithVSync: true,
            capturesPresentedFrames: true, gpuFrameTimingEnabled: true, adoptRememberedSelfPacing: true)
        configuration.merge(
            NativePresentationConfiguration(
                presentsWithVSync: false, capturesPresentedFrames: false,
                gpuFrameTimingEnabled: false, adoptRememberedSelfPacing: false))
        let expected = NativePresentationConfiguration(
            displayFrameInterval: 1.0 / 60, presentsWithVSync: false,
            capturesPresentedFrames: false, gpuFrameTimingEnabled: false, adoptRememberedSelfPacing: true)
        XCTAssertEqual(configuration, expected)
        configuration.merge(NativePresentationConfiguration())
        XCTAssertEqual(configuration, expected)
    }

    func testRejectedRenderPathDoesNotInheritThePreviousSubmission() async throws {
        let fixture = PresentationCommandTestFixture()
        fixture.install(path: .scene)
        fixture.send(.renderScene(GPUIScene()), generation: 1)
        XCTAssertEqual(try fixture.receipt().snapshot.lastFrameSubmission?.outcome, .submitted)

        fixture.send(.renderFrame(RenderFrame()), generation: 1)

        let rejected = try fixture.receipt()
        XCTAssertNotNil(rejected.failure)
        XCTAssertEqual(rejected.snapshot.lastFrameSubmission?.outcome, .skipped)
        XCTAssertEqual(rejected.snapshot.lastFrameSubmission?.gpuTimingStatus, .notIssued)
        XCTAssertNil(rejected.snapshot.lastFrameSubmission?.id)
        XCTAssertNil(rejected.snapshot.capturedPresentedFrame)
        XCTAssertEqual(fixture.recorder.read().renderedFrames, 1)
    }
}
