import Foundation
import Synchronization
@preconcurrency import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsGraphics
@testable import WinSwiftUI

private typealias Acquisition = NativeDisplayAcquisition

private final class AcquisitionTestClock: Sendable {
    struct State {
        var ticks: UInt64 = 0
        var processID: UInt32 = 71
        var threadID: UInt32 = 19
        var fails = false
        var samples = 0
    }
    let state = Mutex(State())

    func sample() -> Acquisition.Sample? {
        state.withLock {
            $0.samples += 1
            guard !$0.fails else { return nil }
            let result = Acquisition.Sample(ticks: $0.ticks, processID: $0.processID, threadID: $0.threadID)
            $0.ticks &+= 1
            return result
        }
    }
}

// This wrapper intentionally lacks the optional acquisition capability. Its
// inner fake remains local and cannot turn an unsupported backend into evidence.
private struct AcquisitionUninstrumentedFactory: NativePresentationBackendFactory {
    var factoryName: String { "UNINSTRUMENTED PURE TEST" }
    var capabilities: RenderBackendCapabilities { .cpuOffscreen }
    func makeBackend() -> any NativePresentationBackend { AcquisitionUninstrumentedBackend() }
}

private final class AcquisitionUninstrumentedBackend: NativePresentationBackend {
    private let inner = AcquisitionTestBackend(plan: .init(), probe: .init())
    func attach(to surface: SurfaceDescriptor, path: NativePresentationPath) throws {
        try inner.attach(to: surface, path: path)
    }
    func resize(to surface: SurfaceDescriptor) throws { try inner.resize(to: surface) }
    func render(scene: GPUIScene) throws { try inner.render(scene: scene) }
    func render(frame: RenderFrame) throws { try inner.render(frame: frame) }
    func configure(_ value: NativePresentationConfiguration) -> NativePresentationConfigurationResult {
        inner.configure(value)
    }
    func takeSnapshot() -> NativePresentationSnapshot { inner.takeSnapshot() }
    func detach() -> NativeWindowAttachmentDetachResult { inner.detach() }
}

extension NativeDisplayAcquisitionTests {
    func testUninstrumentedBackendCannotPublishACompleteNativeJournal() async throws {
        let fixture = try AcquisitionTestCommandFixture()
        try fixture.send(.install(factory: AcquisitionUninstrumentedFactory(), path: .scene, configuration: .init()))
        try fixture.send(.renderScene(GPUIScene()))
        try fixture.close()
        XCTAssertTrue(fixture.values.recorder.diagnostics.faults.contains(.unsupportedBackend))
        XCTAssertThrowsError(try fixture.values.recorder.finishAfterDrain())
    }

    func testFailedSampleOnSkippedOrRefusedPreparationStillInvalidatesCapture() async throws {
        for refused in [false, true] {
            let fixture = try AcquisitionTestFixture()
            let prepared = Acquisition.Preparation(at: nil, contentRevision: 1, boundary: .scene)
            if refused {
                fixture.recorder.noteRefusedPreparation(prepared)
            } else {
                fixture.recorder.noteSkippedPreparation(prepared)
            }
            XCTAssertTrue(fixture.recorder.diagnostics.faults.contains(.clockUnavailable))
            XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
        }
    }
}

private final class AcquisitionTestValues<Value: Sendable>: Sendable {
    let state: Mutex<[Value]>
    init() { state = Mutex([]) }
    func append(_ value: Value) { state.withLock { $0.append(value) } }
    var values: [Value] { state.withLock { $0 } }
}

// These two weak references are used only by synchronous fake native calls in
// this test file. They never dispatch an owner or renderer onto another thread.
private final class AcquisitionTestWeakRecorder: @unchecked Sendable {
    weak var recorder: Acquisition.Recorder?
}

private final class AcquisitionTestReentry: @unchecked Sendable {
    var action: (() -> Void)?
}

private func acquisitionTestSurface(key: NativeWindowKey = NativeWindowKey(), generation: UInt64 = 4)
    -> NativeWindowSurface
{
    let size = IntSize(width: 80, height: 60)
    return NativeWindowSurface(
        key: key, generation: generation, descriptor: SurfaceDescriptor(offscreenPixelSize: size),
        geometry: NativeWindowGeometry(
            revision: generation, nativeSequence: generation, clientSize: size,
            clientScreenOrigin: Point(x: 0, y: 0), scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true))
}

private func acquisitionTestBinding(
    surface: NativeWindowSurface = acquisitionTestSurface(), attachment: NativeWindowAttachmentID = .init()
) -> Acquisition.Binding {
    Acquisition.Binding(windowKey: surface.key, attachmentID: attachment, surfaceGeneration: surface.generation)
}

private func acquisitionTestReceipt(
    context: Acquisition.Context, surface: NativeWindowSurface? = nil,
    frame: BackendFrameID? = nil, failure: NativePresentationFailure? = nil
) -> NativePresentationReceipt {
    NativePresentationReceipt(
        requestID: context.requestID, attachmentID: context.binding.attachmentID,
        surface: surface
            ?? acquisitionTestSurface(
                key: context.binding.windowKey, generation: context.binding.surfaceGeneration),
        operation: context.operation, isAttachmentInstalled: true,
        snapshot: NativePresentationSnapshot(
            path: .scene, isAttached: true, backendDisplayName: "PURE ACQUISITION TEST",
            backendStatusDescription: "NO NATIVE RESOURCE",
            lastFrameSubmission: frame.map { BackendFrameSubmission(id: $0, outcome: .submitted) }),
        failure: failure, startedAtSeconds: 1, completedAtSeconds: 2)
}

private struct AcquisitionTestFixture {
    let clock: AcquisitionTestClock
    let recorder: Acquisition.Recorder
    let binding: Acquisition.Binding

    init(limits: Acquisition.Limits = .init()) throws {
        let clock = AcquisitionTestClock()
        self.clock = clock
        recorder = try Acquisition.Recorder(
            sessionID: UUID(), processID: 71, frequency: 10_000_000, limits: limits,
            sample: { clock.sample() })
        binding = acquisitionTestBinding()
    }

    func prepare(
        operation: NativePresentationOperationKind = .poll, binding: Acquisition.Binding? = nil,
        requestID: NativeWindowRequestID = .init(), preparation: Acquisition.Preparation? = nil
    ) throws -> Acquisition.Context {
        try XCTUnwrap(
            recorder.prepare(
                requestID: requestID, binding: binding ?? self.binding, operation: operation,
                preparation: preparation))
    }

    func finish(_ context: Acquisition.Context, frame: BackendFrameID? = nil) {
        context.endedNative(.returned)
        context.receivedReply(.success(acquisitionTestReceipt(context: context, frame: frame)))
        context.beginActorDelivery(rejected: false)
        context.endActorDelivery()
    }

    func completePoll() throws -> Acquisition.Context {
        let context = try prepare()
        context.enteredNative(actualBinding: context.binding)
        finish(context)
        return context
    }
}

private struct AcquisitionTestBackendError: Error, Sendable {}

private struct AcquisitionTestBackendPlan: Sendable {
    var failAttach = false
    var failBeforeRender = false
    var failAfterPresent = false
    var skipPresent = false
    var detachResults: [Bool] = []
    var reentry: AcquisitionTestReentry?
}

private final class AcquisitionTestBackendProbe: Sendable {
    struct State {
        var begins = 0
        var ends = 0
        var rendered = 0
        var snapshotsWithoutScope: [Bool] = []
        var releaseCount = 0
    }
    let state = Mutex(State())
}

private struct AcquisitionTestBackendFactory: NativePresentationBackendFactory {
    let plan: AcquisitionTestBackendPlan
    let probe: AcquisitionTestBackendProbe
    var factoryName: String { "PURE ACQUISITION TEST" }
    var capabilities: RenderBackendCapabilities { .cpuOffscreen }

    func makeBackend() -> any NativePresentationBackend {
        AcquisitionTestBackend(plan: plan, probe: probe)
    }
}

private final class AcquisitionTestBackend: NativePresentationBackend, NativeDisplayAcquisitionBackend {
    private var plan: AcquisitionTestBackendPlan
    private let probe: AcquisitionTestBackendProbe
    private var active: Acquisition.Context?
    private var epoch: Acquisition.EpochToken?
    private var path: NativePresentationPath?
    private var resources = false
    private var attached = false
    private var invoked = false
    private var frameNumber: UInt64 = 0
    private var submission: BackendFrameSubmission?

    init(plan: AcquisitionTestBackendPlan, probe: AcquisitionTestBackendProbe) {
        self.plan = plan
        self.probe = probe
    }

    func beginDisplayAcquisition(_ context: Acquisition.Context) -> Bool {
        guard active == nil, context.beginScope() else { return false }
        active = context
        invoked = false
        probe.state.withLock { $0.begins += 1 }
        return true
    }

    func endDisplayAcquisition(_ context: Acquisition.Context) {
        guard let active, active.matches(context) else { return }
        if invoked { context.recordSubmission(submission) }
        self.active = nil
        context.endScope()
        probe.state.withLock { $0.ends += 1 }
    }

    func attach(to surface: SurfaceDescriptor, path: NativePresentationPath) throws {
        resources = true
        if path == .scene { epoch = active?.openEpoch(address: 1234, deviceGeneration: 8) }
        if plan.failAttach { throw AcquisitionTestBackendError() }
        self.path = path
        attached = true
    }

    func resize(to surface: SurfaceDescriptor) throws {
        if let active, let epoch { self.epoch = epoch.rebound(to: active) }
    }

    func render(scene: GPUIScene) throws {
        if plan.failBeforeRender { throw AcquisitionTestBackendError() }
        invoked = true
        active?.invokedRenderer()
        probe.state.withLock { $0.rendered += 1 }
        plan.reentry?.action?()
        frameNumber += 1
        let frame = BackendFrameID(deviceGeneration: 8, frameNumber: frameNumber)
        if plan.skipPresent {
            submission = BackendFrameSubmission(outcome: .skipped)
            return
        }
        let ticket = active?.preparePresent(
            epoch: epoch, frame: frame, address: 1234, syncInterval: 1, flags: 0)
        let before = ticket?.sample()
        // A pure fixture supplies this result; no D3D11 or Win32 call is made.
        let result: Int32 = plan.failAfterPresent ? -7 : 0
        let after = ticket?.sample()
        ticket?.returned(result, began: before, ended: after)
        submission = BackendFrameSubmission(id: frame, outcome: plan.failAfterPresent ? .failed : .submitted)
        if plan.failAfterPresent { throw AcquisitionTestBackendError() }
    }

    func render(frame: RenderFrame) throws { active?.invalidate(.unsupportedFramePath) }

    func configure(_ configuration: NativePresentationConfiguration) -> NativePresentationConfigurationResult {
        NativePresentationConfigurationResult()
    }

    func takeSnapshot() -> NativePresentationSnapshot {
        probe.state.withLock { $0.snapshotsWithoutScope.append(active == nil) }
        return NativePresentationSnapshot(
            path: path, isAttached: attached, backendDisplayName: "PURE ACQUISITION TEST",
            backendStatusDescription: "NO NATIVE RESOURCE", lastFrameSubmission: submission)
    }

    func detach() -> NativeWindowAttachmentDetachResult {
        if resources, !plan.detachResults.isEmpty, !plan.detachResults.removeFirst() {
            return NativeWindowAttachmentDetachResult(isDetached: false, failures: [.closing])
        }
        let releasedAt = epoch?.sample()
        if resources { probe.state.withLock { $0.releaseCount += 1 } }
        resources = false
        attached = false
        path = nil
        epoch?.didRelease(at: releasedAt)
        epoch = nil
        return NativeWindowAttachmentDetachResult(isDetached: true)
    }
}

private struct AcquisitionTestSnapshotSource: NativeWindowSnapshotSource {
    let surface: NativeWindowSurface
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { .success(surface) }
}

private final class AcquisitionTestOwner: NativeWindowOwnerContext {
    var surface = acquisitionTestSurface()
    private var attachments: [NativeWindowAttachmentID: any NativeWindowOwnerAttachment] = [:]
    var snapshotSource: any NativeWindowSnapshotSource { AcquisitionTestSnapshotSource(surface: surface) }
    var wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure> { { .success(()) } }
    func attachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? { attachments[id] }
    func install(_ attachment: any NativeWindowOwnerAttachment, for id: NativeWindowAttachmentID) throws {
        guard attachments[id] == nil else { throw NativeWindowOwnerFailure.duplicateAttachment(id) }
        attachments[id] = attachment
    }
    func removeAttachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? {
        attachments.removeValue(forKey: id)
    }
    func withNativeModal<Result>(_ body: () throws -> Result) rethrows -> Result { try body() }
}

private struct AcquisitionTestCommandFixture {
    let values: AcquisitionTestFixture
    let owner = AcquisitionTestOwner()
    let attachment = NativeWindowAttachmentID()
    let probe = AcquisitionTestBackendProbe()
    let plan: AcquisitionTestBackendPlan

    init(plan: AcquisitionTestBackendPlan = .init()) throws {
        values = try AcquisitionTestFixture()
        self.plan = plan
    }

    @discardableResult
    func send(_ operation: NativePresentationOperation, enabled: Bool = true)
        throws -> (Acquisition.Context?, Result<NativePresentationReceipt, NativeWindowOwnerFailure>)
    {
        let id = NativeWindowRequestID()
        let binding = acquisitionTestBinding(surface: owner.surface, attachment: attachment)
        let context = enabled ? try values.prepare(operation: operation.kind, binding: binding, requestID: id) : nil
        let replies = AcquisitionTestValues<Result<NativePresentationReceipt, NativeWindowOwnerFailure>>()
        let reply = NativeWindowReply<NativePresentationReceipt> { result in
            context?.receivedReply(result)
            XCTAssertEqual(context?.recorder.diagnostics.activeScopes ?? 0, 0)
            replies.append(result)
        }
        let command = NativePresentationCommand(
            windowKey: owner.surface.key, attachmentID: attachment,
            expectedSurfaceGeneration: owner.surface.generation, requestID: id,
            operation: operation, reply: reply, acquisition: context)
        do { try command.execute(in: owner) } catch let failure as NativeWindowOwnerFailure {
            command.reject(failure)
        } catch { command.reject(.execution(String(describing: error))) }
        let result = try XCTUnwrap(replies.values.last)
        if case .failure = result {
            context?.beginActorDelivery(rejected: true)
        } else {
            context?.beginActorDelivery(rejected: false)
        }
        context?.endActorDelivery()
        return (context, result)
    }

    @discardableResult
    func install(path: NativePresentationPath = .scene, enabled: Bool = true)
        throws -> (Acquisition.Context?, Result<NativePresentationReceipt, NativeWindowOwnerFailure>)
    {
        try send(
            .install(
                factory: AcquisitionTestBackendFactory(plan: plan, probe: probe), path: path,
                configuration: NativePresentationConfiguration()), enabled: enabled)
    }

    func close() throws {
        let nativeAttachment = try XCTUnwrap(owner.attachment(for: attachment))
        nativeAttachment.beginQuiescence()
        XCTAssertTrue(nativeAttachment.detach().isDetached)
        _ = owner.removeAttachment(for: attachment)
    }
}

private final class AcquisitionTestSink: NativeWindowCommandSink {
    let commands = AcquisitionTestValues<any NativeWindowOwnerCommand>()
    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        commands.append(command)
        return .accepted
    }
}

@MainActor
final class NativeDisplayAcquisitionTests: XCTestCase {
    func testDefaultAndSecondarySelectionDoNoSampling() async throws {
        let fixture = try AcquisitionTestFixture()
        XCTAssertNil(NativeDisplayAcquisitionSession.forHost(nil, isPrimary: true, usesNativePresentation: true))
        XCTAssertNil(
            NativeDisplayAcquisitionSession.forHost(fixture.recorder, isPrimary: false, usesNativePresentation: true))
        XCTAssertNil(
            NativeDisplayAcquisitionSession.forHost(fixture.recorder, isPrimary: true, usesNativePresentation: false))
        XCTAssertTrue(
            NativeDisplayAcquisitionSession.forHost(fixture.recorder, isPrimary: true, usesNativePresentation: true)
                === fixture.recorder)
        XCTAssertEqual(fixture.clock.state.withLock { $0.samples }, 0)
        let command = try AcquisitionTestCommandFixture()
        try command.install(enabled: false)
        try command.send(.renderScene(GPUIScene()), enabled: false)
        try command.close()
        XCTAssertEqual(command.probe.state.withLock { $0.begins }, 0)
        XCTAssertEqual(command.values.clock.state.withLock { $0.samples }, 0)
    }

    func testConfigurationRequiresSingleExplicitAbsoluteLocalPath() async throws {
        XCTAssertNil(try NativeDisplayAcquisitionConfiguration.parse(arguments: ["app", "--other"]))
        let path = "C:\\capture\\native.json"
        XCTAssertEqual(
            try NativeDisplayAcquisitionConfiguration.parse(arguments: ["app", "--native-display-journal", path])?
                .outputPath, path)
        for arguments in [
            ["--native-display-journal"], ["--native-display-journal", "relative.json"],
            ["--native-display-journal", "C:relative.json"], ["--native-display-journal", "\\\\server\\a.json"],
            ["--native-display-journal", "\\\\?\\C:\\a.json"], ["--native-display-journal", "C:\\a\u{0}.json"],
            ["--native-display-journal", "C:\\a.json", "--native-display-journal", "C:\\b.json"],
            ["--native-display-journal", "C:\\" + String(repeating: "a", count: 4096)],
        ] {
            XCTAssertThrowsError(try NativeDisplayAcquisitionConfiguration.parse(arguments: arguments))
        }
    }

    func testInvalidFrequencyProcessAndOversizedLimitsRejectBeforeSampling() async throws {
        let clock = AcquisitionTestClock()
        for (pid, frequency, limits) in [
            (UInt32(0), UInt64(1), Acquisition.Limits()),
            (UInt32(71), UInt64(0), Acquisition.Limits()),
            (UInt32(71), UInt64(1), Acquisition.Limits(attempts: 8193)),
            (UInt32(71), UInt64(1), Acquisition.Limits(epochs: 65)),
            (UInt32(71), UInt64(1), Acquisition.Limits(receipts: 0)),
        ] {
            XCTAssertThrowsError(
                try Acquisition.Recorder(
                    sessionID: UUID(), processID: pid, frequency: frequency, limits: limits,
                    sample: { clock.sample() }))
        }
        XCTAssertEqual(clock.state.withLock { $0.samples }, 0)
    }

    func testSamplerRunsOutsideRecorderMutex() async throws {
        let clock = AcquisitionTestClock()
        let reference = AcquisitionTestWeakRecorder()
        let recorder = try Acquisition.Recorder(sessionID: UUID(), processID: 71, frequency: 1) {
            _ = reference.recorder?.diagnostics
            return clock.sample()
        }
        reference.recorder = recorder
        XCTAssertNotNil(recorder.prepare(requestID: .init(), binding: acquisitionTestBinding(), operation: .poll))
        XCTAssertEqual(clock.state.withLock { $0.samples }, 1)
    }

    func testPreparationKeepsFailedSampleWithoutResamplingAndRevisionIsNotInputEffect() async throws {
        let fixture = try AcquisitionTestFixture()
        let preparation = Acquisition.Preparation(at: nil, contentRevision: 99, boundary: .scene)
        let context = try fixture.prepare(preparation: preparation)
        XCTAssertEqual(fixture.clock.state.withLock { $0.samples }, 0)
        context.enteredNative(actualBinding: context.binding)
        fixture.finish(context)
        XCTAssertTrue(fixture.recorder.diagnostics.faults.contains(.clockUnavailable))
        XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
    }

    func testActualRawBracketPreservesZeroFrameComponentsFlagsAndFailedHRESULT() async throws {
        let fixture = try AcquisitionTestFixture()
        let context = try fixture.prepare(operation: .renderScene)
        context.enteredNative(actualBinding: context.binding)
        XCTAssertTrue(context.beginScope())
        let epoch = try XCTUnwrap(context.openEpoch(address: 42, deviceGeneration: 0))
        let frame = BackendFrameID(deviceGeneration: 0, frameNumber: 0)
        context.invokedRenderer()
        let ticket = try XCTUnwrap(
            context.preparePresent(epoch: epoch, frame: frame, address: 42, syncInterval: 3, flags: 9))
        let before = ticket.sample()
        let after = ticket.sample()
        ticket.returned(-2_147_000_001, began: before, ended: after)
        context.recordSubmission(BackendFrameSubmission(id: frame, outcome: .failed, adapterIsSoftware: true))
        context.endScope()
        fixture.finish(context, frame: frame)
        epoch.didRelease(at: epoch.sample())
        let record = try XCTUnwrap(try fixture.recorder.finishAfterDrain().requests.first)
        XCTAssertEqual(record.preparation.at?.ticks, 0)
        XCTAssertEqual(record.present?.frame, frame)
        XCTAssertEqual(record.present?.hresult, -2_147_000_001)
        XCTAssertEqual(record.present?.syncInterval, 3)
        XCTAssertEqual(record.present?.flags, 9)
        XCTAssertEqual(record.present?.began, before)
        XCTAssertEqual(record.present?.ended, after)
        XCTAssertEqual(record.submission?.adapterIsSoftware, true)
    }

    func testReplyBeforeActorConsumptionAndCallbackEndIsStillPending() async throws {
        let fixture = try AcquisitionTestFixture()
        let context = try fixture.prepare()
        context.enteredNative(actualBinding: context.binding)
        context.endedNative(.returned)
        context.receivedReply(.success(acquisitionTestReceipt(context: context)))
        XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
        context.beginActorDelivery(rejected: false)
        XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
        context.endActorDelivery()
        let snapshot = try fixture.recorder.finishAfterDrain()
        XCTAssertNotNil(snapshot.requests.first?.replyArrived)
        XCTAssertNotNil(snapshot.requests.first?.actorConsumed)
        XCTAssertTrue(snapshot.requests.first?.actorDeliveryFinished == true)
    }

    func testUnfinishedCallAndOpenEpochCannotBecomeCompletePrefix() async throws {
        let fixture = try AcquisitionTestFixture()
        let context = try fixture.prepare(operation: .renderScene)
        context.enteredNative(actualBinding: context.binding)
        XCTAssertTrue(context.beginScope())
        let epoch = try XCTUnwrap(context.openEpoch(address: 1, deviceGeneration: 1))
        context.invokedRenderer()
        let ticket = try XCTUnwrap(
            context.preparePresent(
                epoch: epoch, frame: BackendFrameID(deviceGeneration: 1, frameNumber: 1), address: 1, syncInterval: 1,
                flags: 0))
        XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
        ticket.returned(0, began: ticket.sample(), ended: ticket.sample())
        context.endScope()
        fixture.finish(context, frame: BackendFrameID(deviceGeneration: 1, frameNumber: 1))
        XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
        epoch.didRelease(at: epoch.sample())
        XCTAssertEqual(try fixture.recorder.finishAfterDrain().epochs.count, 1)
    }

    func testDuplicateRequestAndAttemptCapacityInvalidateWholeCapture() async throws {
        for duplicate in [false, true] {
            let fixture = try AcquisitionTestFixture(limits: .init(attempts: 1))
            let first = try fixture.completePoll()
            XCTAssertNil(
                fixture.recorder.prepare(
                    requestID: duplicate ? first.requestID : .init(), binding: fixture.binding, operation: .poll))
            XCTAssertTrue(fixture.recorder.diagnostics.faults.contains(duplicate ? .duplicateRequest : .capacity))
            XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
        }
    }

    func testEpochAndReceiptCapacityDoNotSilentlyDropTail() async throws {
        let epochs = try AcquisitionTestFixture(limits: .init(epochs: 1))
        let context = try epochs.prepare()
        context.enteredNative(actualBinding: context.binding)
        XCTAssertTrue(context.beginScope())
        let first = try XCTUnwrap(context.openEpoch(address: 1, deviceGeneration: 1))
        first.didRelease(at: first.sample())
        XCTAssertNil(context.openEpoch(address: 1, deviceGeneration: 2))
        context.endScope()
        epochs.finish(context)
        XCTAssertThrowsError(try epochs.recorder.finishAfterDrain())

        let receipts = try AcquisitionTestFixture(limits: .init(receipts: 1))
        try receipts.completePoll()
        try receipts.completePoll()
        XCTAssertTrue(receipts.recorder.diagnostics.faults.contains(.capacity))
        XCTAssertThrowsError(try receipts.recorder.finishAfterDrain())
    }

    func testClockProcessAndNativeThreadFailureDoNotFallbackToOtherTime() async throws {
        for failure in 0..<3 {
            let fixture = try AcquisitionTestFixture()
            let context = try fixture.prepare()
            context.enteredNative(actualBinding: context.binding)
            fixture.clock.state.withLock {
                if failure == 0 { $0.fails = true }
                if failure == 1 { $0.processID = 72 }
                if failure == 2 { $0.threadID = 20 }
            }
            fixture.finish(context)
            XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
            XCTAssertTrue(
                fixture.recorder.diagnostics.faults.contains(
                    failure == 0 ? .clockUnavailable : failure == 1 ? .processChanged : .nativeThreadChanged))
        }
    }

    func testActorMayConsumeOnDifferentThreadWithoutRebindingNativeIssuer() async throws {
        let fixture = try AcquisitionTestFixture()
        let context = try fixture.prepare()
        context.enteredNative(actualBinding: context.binding)
        context.endedNative(.returned)
        context.receivedReply(.success(acquisitionTestReceipt(context: context)))
        fixture.clock.state.withLock { $0.threadID = 400 }
        context.beginActorDelivery(rejected: false)
        context.endActorDelivery()
        let record = try XCTUnwrap(try fixture.recorder.finishAfterDrain().requests.first)
        XCTAssertEqual(record.nativeEntered?.threadID, 19)
        XCTAssertEqual(record.actorConsumed?.threadID, 400)
    }

    func testDuplicateAndForeignScopeCannotClearAnActiveRequest() async throws {
        let fixture = try AcquisitionTestFixture()
        let first = try fixture.prepare()
        let second = try fixture.prepare()
        first.enteredNative(actualBinding: first.binding)
        second.enteredNative(actualBinding: second.binding)
        XCTAssertTrue(first.beginScope())
        XCTAssertFalse(first.beginScope())
        second.endScope()
        XCTAssertEqual(fixture.recorder.diagnostics.activeScopes, 1)
        first.endScope()
        XCTAssertEqual(fixture.recorder.diagnostics.activeScopes, 0)
        XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
    }

    func testResizeUsesExplicitEpochBoundaryWithoutInventingSwapChainCreation() async throws {
        let fixture = try AcquisitionTestFixture()
        let first = try fixture.prepare()
        first.enteredNative(actualBinding: first.binding)
        XCTAssertTrue(first.beginScope())
        let old = try XCTUnwrap(first.openEpoch(address: 12, deviceGeneration: 8))
        first.endScope()
        fixture.finish(first)
        let newer = Acquisition.Binding(
            windowKey: first.binding.windowKey, attachmentID: first.binding.attachmentID,
            surfaceGeneration: first.binding.surfaceGeneration + 1)
        let resize = try fixture.prepare(operation: .resize, binding: newer)
        resize.enteredNative(actualBinding: newer)
        XCTAssertTrue(resize.beginScope())
        let rebound = try XCTUnwrap(old.rebound(to: resize))
        resize.endScope()
        fixture.finish(resize)
        rebound.didRelease(at: rebound.sample())
        let epochs = try fixture.recorder.finishAfterDrain().epochs
        XCTAssertEqual(epochs.map(\.openedBy), [.created, .surfaceChanged])
        XCTAssertEqual(epochs.map(\.closedBy), [.surfaceChanged, .released])
        XCTAssertEqual(epochs.map(\.address), [12, 12])
        XCTAssertNotEqual(epochs[0].id, epochs[1].id)
        XCTAssertEqual(epochs[0].closed, epochs[1].opened)
    }

    func testActualReleaseThenAddressReuseKeepsTwoOriginalEpochs() async throws {
        let fixture = try AcquisitionTestFixture()
        let context = try fixture.prepare()
        context.enteredNative(actualBinding: context.binding)
        XCTAssertTrue(context.beginScope())
        for generation in [UInt64(8), UInt64(9)] {
            let epoch = try XCTUnwrap(context.openEpoch(address: 11, deviceGeneration: generation))
            epoch.didRelease(at: epoch.sample())
        }
        context.endScope()
        fixture.finish(context)
        let epochs = try fixture.recorder.finishAfterDrain().epochs
        XCTAssertEqual(epochs.map(\.openedBy), [.created, .created])
        XCTAssertEqual(epochs.map(\.deviceGeneration), [8, 9])
        XCTAssertNotEqual(epochs[0].id, epochs[1].id)
    }

    func testMissingWrongEpochAndSecondPresentInvalidateRatherThanRepairIdentity() async throws {
        for condition in 0..<3 {
            let fixture = try AcquisitionTestFixture()
            let context = try fixture.prepare(operation: .renderScene)
            context.enteredNative(actualBinding: context.binding)
            XCTAssertTrue(context.beginScope())
            let epoch = try XCTUnwrap(context.openEpoch(address: 2, deviceGeneration: 8))
            context.invokedRenderer()
            let frame = BackendFrameID(deviceGeneration: condition == 1 ? 9 : 8, frameNumber: 1)
            let ticket = context.preparePresent(
                epoch: condition == 0 ? nil : epoch, frame: frame, address: 2, syncInterval: 1, flags: 0)
            if condition < 2 {
                XCTAssertNil(ticket)
            } else {
                let accepted = try XCTUnwrap(ticket)
                accepted.returned(0, began: accepted.sample(), ended: accepted.sample())
                XCTAssertNil(context.preparePresent(epoch: epoch, frame: frame, address: 2, syncInterval: 1, flags: 0))
            }
            context.endScope()
            fixture.finish(context)
            epoch.didRelease(at: epoch.sample())
            XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
        }
    }

    func testSkipCountersHaveNoInventedRequestOrInputEffect() async throws {
        let fixture = try AcquisitionTestFixture()
        fixture.recorder.noteSkippedPreparation()
        fixture.recorder.noteRefusedPreparation()
        let snapshot = try fixture.recorder.finishAfterDrain()
        XCTAssertEqual(snapshot.skippedPreparations, 1)
        XCTAssertEqual(snapshot.refusedPreparations, 1)
        XCTAssertTrue(snapshot.requests.isEmpty)
        let text = try XCTUnwrap(String(data: snapshot.encoded(), encoding: .utf8))
        XCTAssertTrue(text.contains("\"containsDisplayFacts\":false"))
        XCTAssertTrue(text.contains("\"containsInputEffects\":false"))
        XCTAssertFalse(text.contains("hardwareQualified"))
    }

    func testEncodingPreservesFullWidthIntegerAndRejectsByteLimitWithoutPrefix() async throws {
        let fixture = try AcquisitionTestFixture()
        fixture.clock.state.withLock { $0.ticks = UInt64.max - 20 }
        try fixture.completePoll()
        let snapshot = try fixture.recorder.finishAfterDrain()
        let data = try snapshot.encoded()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"ticks\":\"18446744073709551595\""))
        XCTAssertThrowsError(try snapshot.encoded(maximumBytes: data.count - 1))
        XCTAssertThrowsError(try snapshot.encoded(maximumBytes: Acquisition.maximumEncodedBytes + 1))
        XCTAssertEqual(try snapshot.encoded(maximumBytes: data.count), data)
    }

    func testEveryUnsuccessfulRunRetiresWithoutWritingOrInferringJoin() async throws {
        for _ in ["startup", "rollback", "fatal", "join"] {
            let fixture = try AcquisitionTestFixture()
            try fixture.completePoll()
            let session = NativeDisplayAcquisitionSession(recorder: fixture.recorder, outputPath: "C:\\unused.json")
            var writes = 0
            session.retire(successfullyJoined: false) { _, _ in writes += 1 }
            session.retire(successfullyJoined: true) { _, _ in writes += 1 }
            XCTAssertEqual(writes, 0)
            XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
        }
    }

    func testPendingReceiptAndUnclosedResourceSuppressWriter() async throws {
        for openResource in [false, true] {
            let fixture = try AcquisitionTestFixture()
            let context = try fixture.prepare()
            context.enteredNative(actualBinding: context.binding)
            if openResource {
                XCTAssertTrue(context.beginScope())
                XCTAssertNotNil(context.openEpoch(address: 1, deviceGeneration: 1))
                context.endScope()
                fixture.finish(context)
            } else {
                context.endedNative(.returned)
            }
            var writes = 0
            let session = NativeDisplayAcquisitionSession(recorder: fixture.recorder, outputPath: "C:\\unused.json")
            session.retire(successfullyJoined: true) { _, _ in writes += 1 }
            XCTAssertEqual(writes, 0)
        }
    }

    func testSuccessfulRetirementWritesOnceAndWriterFailureDoesNotRetry() async throws {
        for failWrite in [false, true] {
            let fixture = try AcquisitionTestFixture()
            try fixture.completePoll()
            let session = NativeDisplayAcquisitionSession(recorder: fixture.recorder, outputPath: "C:\\unused.json")
            var paths: [String] = []
            let issue = session.retire(successfullyJoined: true) { path, data in
                paths.append(path)
                XCTAssertFalse(data.isEmpty)
                if failWrite { throw AcquisitionTestBackendError() }
            }
            if failWrite { XCTAssertNotNil(issue) } else { XCTAssertNil(issue) }
            session.retire(successfullyJoined: true) { path, _ in paths.append(path) }
            XCTAssertEqual(paths, ["C:\\unused.json"])
        }
    }

    func testNestedCommandRejectionCannotReplaceOrClearOuterScope() async throws {
        let reentry = AcquisitionTestReentry()
        let fixture = try AcquisitionTestCommandFixture(plan: .init(reentry: reentry))
        try fixture.install()
        reentry.action = {
            [weak owner = fixture.owner, recorder = fixture.values.recorder, attachment = fixture.attachment] in
            guard let owner else { return XCTFail("Original test owner vanished") }
            let binding = acquisitionTestBinding(surface: owner.surface, attachment: attachment)
            let id = NativeWindowRequestID()
            guard let nested = recorder.prepare(requestID: id, binding: binding, operation: .poll) else {
                return XCTFail("Missing nested context")
            }
            let command = NativePresentationCommand(
                windowKey: owner.surface.key, attachmentID: attachment,
                expectedSurfaceGeneration: nil, requestID: id, operation: .poll,
                reply: NativeWindowReply { result in nested.receivedReply(result) }, acquisition: nested)
            do {
                try XCTAssertThrowsError(try command.execute(in: owner))
            } catch {
                XCTFail("Nested rejection assertion unexpectedly threw: \(error)")
            }
            command.reject(.execution("Expected fake reentry rejection"))
            nested.beginActorDelivery(rejected: true)
            nested.endActorDelivery()
            XCTAssertEqual(recorder.diagnostics.activeScopes, 1)
        }
        try fixture.send(.renderScene(GPUIScene()))
        reentry.action = nil
        XCTAssertEqual(fixture.probe.state.withLock { $0.begins }, 2)
        XCTAssertEqual(fixture.probe.state.withLock { $0.ends }, 2)
        XCTAssertEqual(fixture.values.recorder.diagnostics.activeScopes, 0)
        try fixture.close()
        XCTAssertThrowsError(try fixture.values.recorder.finishAfterDrain())
    }

    func testCommandScopeClearsBeforeSnapshotAndSynchronousReply() async throws {
        let fixture = try AcquisitionTestCommandFixture()
        try fixture.install()
        try fixture.send(.renderScene(GPUIScene()))
        XCTAssertTrue(fixture.probe.state.withLock { $0.snapshotsWithoutScope.allSatisfy { $0 } })
        try fixture.close()
        let snapshot = try fixture.values.recorder.finishAfterDrain()
        XCTAssertEqual(snapshot.requests.filter { $0.present != nil }.count, 1)
        XCTAssertEqual(snapshot.epochs.count, 1)
        XCTAssertEqual(fixture.probe.state.withLock { $0.releaseCount }, 1)
    }

    func testRenderThrowAndSkipKeepOnlyCurrentCallEvidence() async throws {
        for plan in [
            AcquisitionTestBackendPlan(failBeforeRender: true),
            AcquisitionTestBackendPlan(failAfterPresent: true),
            AcquisitionTestBackendPlan(skipPresent: true),
        ] {
            let fixture = try AcquisitionTestCommandFixture(plan: plan)
            try fixture.install()
            let (_, reply) = try fixture.send(.renderScene(GPUIScene()))
            let receipt = try reply.get()
            if plan.skipPresent { XCTAssertNil(receipt.failure) } else { XCTAssertNotNil(receipt.failure) }
            try fixture.close()
            let record = try XCTUnwrap(try fixture.values.recorder.finishAfterDrain().requests.last)
            XCTAssertEqual(record.present != nil, plan.failAfterPresent)
            XCTAssertEqual(record.rendererInvoked, !plan.failBeforeRender)
            if plan.failBeforeRender { XCTAssertNil(record.submission) }
            if plan.failAfterPresent { XCTAssertEqual(record.present?.hresult, -7) }
        }
    }

    func testMissingAttachmentAndPathMismatchCannotInheritPriorFrame() async throws {
        let missing = try AcquisitionTestCommandFixture()
        let (_, rejection) = try missing.send(.renderScene(GPUIScene()))
        if case .failure(.missingAttachment) = rejection {} else { XCTFail("Expected original transport rejection") }
        XCTAssertEqual(missing.probe.state.withLock { $0.begins }, 0)
        XCTAssertThrowsError(try missing.values.recorder.finishAfterDrain())

        let mismatch = try AcquisitionTestCommandFixture()
        try mismatch.install()
        try mismatch.send(.renderScene(GPUIScene()))
        let (_, result) = try mismatch.send(.renderFrame(RenderFrame()))
        let receipt = try result.get()
        XCTAssertNotNil(receipt.failure)
        XCTAssertEqual(receipt.snapshot.lastFrameSubmission?.outcome, .skipped)
        XCTAssertNil(receipt.snapshot.lastFrameSubmission?.id)
        try mismatch.close()
        let records = try mismatch.values.recorder.finishAfterDrain().requests
        XCTAssertNil(records.last?.present)
        XCTAssertNil(records.last?.submission)
        XCTAssertEqual(records.filter { $0.present != nil }.count, 1)
    }

    func testPartialAttachCleanupRecordsActualReleaseAndFailedDetachStaysOpen() async throws {
        let cleaned = try AcquisitionTestCommandFixture(plan: .init(failAttach: true))
        let (_, cleanResult) = try cleaned.install()
        XCTAssertNotNil(try cleanResult.get().failure)
        let clean = try cleaned.values.recorder.finishAfterDrain()
        XCTAssertTrue(clean.epochs.first?.isClosed == true)
        XCTAssertEqual(cleaned.probe.state.withLock { $0.releaseCount }, 1)

        let retained = try AcquisitionTestCommandFixture(plan: .init(failAttach: true, detachResults: [false, true]))
        let (_, retainedResult) = try retained.install()
        XCTAssertNotNil(try retainedResult.get().failure?.cleanupResult)
        XCTAssertEqual(retained.values.recorder.diagnostics.openEpochs, 1)
        XCTAssertThrowsError(try retained.values.recorder.finishAfterDrain())
        try retained.close()
        XCTAssertEqual(try retained.values.recorder.finishAfterDrain().epochs.count, 1)
    }

    func testOwnerDetachWithoutRequestClosesLifetimeAfterScopeHasGone() async throws {
        let fixture = try AcquisitionTestCommandFixture()
        try fixture.install()
        XCTAssertEqual(fixture.values.recorder.diagnostics.activeScopes, 0)
        XCTAssertEqual(fixture.values.recorder.diagnostics.openEpochs, 1)
        try fixture.close()
        let snapshot = try fixture.values.recorder.finishAfterDrain()
        XCTAssertEqual(snapshot.requests.count, 1)
        XCTAssertEqual(snapshot.epochs.first?.closedBy, .released)
    }

    func testForeignReceiptAndDuplicateReplyAreNotRepaired() async throws {
        let fixture = try AcquisitionTestFixture()
        let context = try fixture.prepare()
        context.enteredNative(actualBinding: context.binding)
        context.endedNative(.returned)
        context.receivedReply(.success(acquisitionTestReceipt(context: context, surface: acquisitionTestSurface())))
        context.receivedReply(.success(acquisitionTestReceipt(context: context)))
        context.beginActorDelivery(rejected: true)
        context.endActorDelivery()
        XCTAssertTrue(fixture.recorder.diagnostics.faults.contains(.receiptIdentity))
        XCTAssertTrue(fixture.recorder.diagnostics.faults.contains(.duplicateReply))
        XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
    }

    func testCoreReplyRejectionWithoutCommandRejectStillReachesJournal() async throws {
        let fixture = try AcquisitionTestFixture()
        let sink = AcquisitionTestSink()
        let queue = NativeHostPresentationQueue(
            sink: sink, attachmentID: .init(), teardownStore: .init(), acquisition: fixture.recorder)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.submit(.poll, surface: acquisitionTestSurface(), requiresSurfaceGeneration: false) { result in
                if case .failure(.closing) = result {} else { XCTFail("Expected Core terminal reply") }
                XCTAssertEqual(fixture.recorder.diagnostics.pendingActorDeliveries, 1)
                do {
                    try XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
                } catch {
                    XCTFail("Pending delivery assertion unexpectedly threw: \(error)")
                }
            }
            queue.whenDrained { done.resume() }
            guard let command = sink.commands.values.first else {
                XCTFail("No original command")
                done.resume()
                return
            }
            _ = command.commandReply.reject(.closing)
            XCTAssertEqual(fixture.recorder.diagnostics.receipts, 1)
            XCTAssertEqual(fixture.recorder.diagnostics.pendingActorDeliveries, 1)
        }
        XCTAssertEqual(fixture.recorder.diagnostics.pendingActorDeliveries, 0)
        XCTAssertTrue(fixture.recorder.diagnostics.faults.contains(.requestRejected))
        XCTAssertThrowsError(try fixture.recorder.finishAfterDrain())
    }

    func testPendingLocalRejectionFinishesCallbackBeforeDrainWithoutNativeReceipt() async throws {
        let fixture = try AcquisitionTestFixture()
        let sink = AcquisitionTestSink()
        let queue = NativeHostPresentationQueue(
            sink: sink, attachmentID: .init(), teardownStore: .init(), acquisition: fixture.recorder)
        let events = AcquisitionTestValues<String>()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.submit(.poll, surface: acquisitionTestSurface(), requiresSurfaceGeneration: false) { _ in
                events.append("first")
            }
            queue.submit(.poll, surface: acquisitionTestSurface(), requiresSurfaceGeneration: false) { _ in
                events.append("local")
                XCTAssertEqual(fixture.recorder.diagnostics.pendingActorDeliveries, 2)
            }
            queue.whenDrained {
                events.append("drained")
                done.resume()
            }
            queue.invalidate()
            XCTAssertEqual(events.values, ["local"])
            XCTAssertEqual(fixture.recorder.diagnostics.localRejections, 1)
            XCTAssertEqual(fixture.recorder.diagnostics.receipts, 0)
            guard let command = sink.commands.values.first else {
                XCTFail("No original command")
                done.resume()
                return
            }
            _ = command.commandReply.reject(.closing)
        }
        XCTAssertEqual(events.values, ["local", "first", "drained"])
        XCTAssertEqual(fixture.recorder.diagnostics.pendingActorDeliveries, 0)
        XCTAssertEqual(fixture.recorder.diagnostics.receipts, 1)
    }

    func testUnsupportedFrameBackendDoesNotPretendToAcquireScenePresent() async throws {
        let fixture = try AcquisitionTestCommandFixture()
        try fixture.install(path: .frame)
        try fixture.send(.renderFrame(RenderFrame()))
        try fixture.close()
        XCTAssertTrue(fixture.values.recorder.diagnostics.faults.contains(.unsupportedFramePath))
        XCTAssertThrowsError(try fixture.values.recorder.finishAfterDrain())
    }
}
