import Foundation
import SwiftWindowsCore
import Synchronization
import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

private final class SmokeIngressSetupDriver: Sendable {
    private let operations = Mutex<[Win32NativeEventIngress.Operation]>([])

    func enqueue(_ operation: @escaping Win32NativeEventIngress.Operation) {
        operations.withLock { $0.append(operation) }
    }

    var count: Int { operations.withLock { $0.count } }

    private func take(last: Bool) -> Win32NativeEventIngress.Operation? {
        operations.withLock { values in
            guard !values.isEmpty else { return nil }
            return last ? values.removeLast() : values.removeFirst()
        }
    }

    @MainActor @discardableResult
    func run(last: Bool = false) -> Bool {
        guard let operation = take(last: last) else { return false }
        operation()
        return true
    }
}

private final class SmokeIngressSetupFailures: Sendable {
    private let values = Mutex<[Win32NativeSmokeIngressSetup.Failure]>([])

    func append(_ failure: Win32NativeSmokeIngressSetup.Failure) { values.withLock { $0.append(failure) } }
    var snapshot: [Win32NativeSmokeIngressSetup.Failure] { values.withLock { $0 } }
}

private final class SmokeIngressSetupReleaseProbe: Sendable {
    let onRelease: @Sendable () -> Void

    init(_ onRelease: @escaping @Sendable () -> Void) { self.onRelease = onRelease }
    deinit { onRelease() }
}

private final class SmokeIngressSetupCounter: Sendable {
    private let value = Mutex(0)

    func increment() { value.withLock { $0 += 1 } }
    var count: Int { value.withLock { $0 } }
}

@MainActor
private final class SmokeIngressSetupReceiver {
    var delivered: [UInt32] = []
    var failures: [Win32NativeIngressFailure] = []
    var calls = 0
    var duringDelivery: ((Win32NativeWindowEventRecord) -> Void)?

    func receive(_ record: Win32NativeWindowEventRecord) {
        if case .smokeProbe(let probe) = record.event { delivered.append(probe.ordinal) }
        duringDelivery?(record)
    }
}

@MainActor
private final class SmokeIngressSetupFacade {
    var ingress: Win32NativeEventIngress?
    var state: Win32NativeSmokeIngressBindingState
    var reads = 0

    init(ingress: Win32NativeEventIngress, key: NativeWindowKey) {
        self.ingress = ingress
        state = Win32NativeSmokeIngressBindingState(
            windowKey: key, surfaceKey: key, closeLifetimeID: key.lifetimeID, hasNativeOwner: true)
    }

    func snapshot(expectedIngress: Win32NativeEventIngress, key: NativeWindowKey) -> Win32NativeSmokeIngressSnapshot? {
        reads += 1
        return win32NativeSmokeCurrentIngressSnapshot(
            expectedIngress: expectedIngress, currentIngress: ingress, expectedKey: key, state: state)
    }
}

/// This manual actor job models readiness, not Swift executor ordering or an
/// actual mounted task. Its progress record exists only when the driver runs it.
@MainActor
private final class SmokeIngressSetupModel {
    let driver: SmokeIngressSetupDriver
    let observation: Win32NativeSmokeObservation
    var releases = 0
    var runnable = false
    var resumed = false

    init(driver: SmokeIngressSetupDriver, observation: Win32NativeSmokeObservation) {
        self.driver = driver
        self.observation = observation
    }

    func release() -> Win32NativeSmokeIngressSetup.FirstReleaseResult {
        releases += 1
        runnable = true
        observation.record(.modelFirstReleased)
        driver.enqueue { [self] in
            resumed = true
            observation.record(.modelFirstResumed)
        }
        return .invoked
    }
}

@MainActor
private final class SmokeIngressSetupHarness {
    let key: NativeWindowKey
    let requests: [NativeWindowRequestID]
    let driver: SmokeIngressSetupDriver
    let observation: Win32NativeSmokeObservation
    let failures: SmokeIngressSetupFailures
    let setup: Win32NativeSmokeIngressSetup
    let ingress: Win32NativeEventIngress
    let receiver: SmokeIngressSetupReceiver
    var facade: SmokeIngressSetupFacade?
    var model: SmokeIngressSetupModel?

    init() {
        let key = NativeWindowKey()
        self.key = key
        requests = (0..<64).map { _ in NativeWindowRequestID() }
        let driver = SmokeIngressSetupDriver()
        self.driver = driver
        let observation = Win32NativeSmokeObservation(runID: Foundation.UUID())
        self.observation = observation
        let failures = SmokeIngressSetupFailures()
        self.failures = failures
        let setup = Win32NativeSmokeIngressSetup(scheduleActor: { driver.enqueue($0) })
        self.setup = setup
        setup.installFailureReporter { failures.append($0) }
        let receiver = SmokeIngressSetupReceiver()
        self.receiver = receiver
        let ingress = Win32NativeEventIngress(
            observation: observation, schedule: setup.makeScheduler(),
            receiveFailure: { receiver.failures.append($0) }, receive: { receiver.receive($0) })
        self.ingress = ingress
        let facade = SmokeIngressSetupFacade(ingress: ingress, key: key)
        self.facade = facade
        setup.bind(windowKey: key) { [weak facade, weak ingress] in
            guard let facade, let ingress else { return nil }
            return facade.snapshot(expectedIngress: ingress, key: key)
        }
        model = SmokeIngressSetupModel(driver: driver, observation: observation)
    }

    func armAndRegister() {
        XCTAssertTrue(setup.arm(windowKey: key))
        for ordinal in UInt32(0)..<UInt32(64) {
            setup.register(ordinal: ordinal, requestID: requests[Int(ordinal)], windowKey: key)
        }
    }

    func record(
        _ ordinal: UInt32, request: NativeWindowRequestID? = nil,
        key: NativeWindowKey? = nil, sequence: UInt64? = nil, generation: UInt64 = 1
    ) -> Win32NativeWindowEventRecord {
        let sequence = sequence ?? UInt64(ordinal) + 1
        let geometry = NativeWindowGeometry(
            revision: sequence, nativeSequence: sequence, clientSize: IntSize(width: 80, height: 60),
            clientScreenOrigin: .zero, scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: false)
        return Win32NativeWindowEventRecord(
            observation: Win32NativeWindowObservation(
                surface: NativeWindowSurface(
                    key: key ?? self.key, generation: generation,
                    descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize), geometry: geometry),
                systemAppearance: .unavailable, displayIdentity: "", isInLiveResize: false, isFullscreen: false),
            event: .smokeProbe(Win32NativeSmokeProbe(requestID: request ?? requests[Int(ordinal)], ordinal: ordinal)))
    }

    func admit(_ ordinal: UInt32, generation: UInt64 = 1) throws {
        let record = record(ordinal, generation: generation)
        try ingress.enqueue(record).get()
        setup.noteSuccessfulReply(
            ordinal: ordinal, requestID: requests[Int(ordinal)], surface: record.observation.surface)
    }

    func prefix(holdOperation: Bool = true) throws {
        for ordinal in UInt32(0)..<UInt32(31) { try admit(ordinal) }
        if holdOperation {
            XCTAssertTrue(driver.run())
            XCTAssertTrue(receiver.delivered.isEmpty)
            XCTAssertTrue(setup.snapshot.hasHeldOperation)
        }
        // The actual production ingress flush bypasses the setup scheduler.
        // No C provider or native query is executed by this pure test.
        try ingress.flush(through: 31).get()
        XCTAssertEqual(receiver.delivered, Array(UInt32(0)..<UInt32(31)))
        XCTAssertTrue(ingress.snapshot.hasScheduledTurn)
    }

    func suffix() throws {
        for ordinal in UInt32(31)..<UInt32(64) { try admit(ordinal) }
    }

    func requestRelease() {
        setup.requestFirstRelease { [weak model] in
            guard let model else { return .unavailable }
            return model.release()
        }
    }

    func drainDriver() {
        for _ in 0..<8 {
            if !driver.run() { break }
        }
        XCTAssertEqual(driver.count, 0)
    }

    func verdict() throws -> NativeOwnedSmokeVerdict {
        let capture = observation.capture()
        var state = NativeOwnedSmokeSharedState.Snapshot()
        state.windowKey = key
        return try NativeOwnedSmokeValidation.evaluate(
            NativeOwnedSmokeValidation.decode(capture.trace), observation: capture.snapshot, state: state)
    }
}

/// Only copied values, production ingress/helper calls and a manually selected
/// actor driver. No HWND, native thread, query, process, timer or wall-clock wait.
/// These cases are not evidence that the actual native fixture qualifies.
@MainActor
final class Win32NativeSmokeIngressSetupTests: XCTestCase {
    func testDormantDeliveryUsesOneActorHopWithoutHolding() async {
        let fixture = SmokeIngressSetupHarness()
        let scheduler = fixture.setup.makeScheduler()
        scheduler { fixture.receiver.calls += 1 }
        XCTAssertEqual(fixture.driver.count, 1)
        XCTAssertEqual(fixture.receiver.calls, 0)
        XCTAssertTrue(fixture.driver.run())
        XCTAssertEqual(fixture.receiver.calls, 1)
        XCTAssertEqual(fixture.driver.count, 0)
        XCTAssertFalse(fixture.setup.snapshot.hasHeldOperation)
        XCTAssertEqual(fixture.setup.snapshot.phase, .dormant)
    }

    func testPreviouslyQueuedWrapperChecksHoldWhenItExecutes() async throws {
        let fixture = SmokeIngressSetupHarness()
        let record = fixture.record(0)
        try fixture.ingress.enqueue(record).get()
        fixture.armAndRegister()
        fixture.setup.noteSuccessfulReply(
            ordinal: 0, requestID: fixture.requests[0], surface: record.observation.surface)
        XCTAssertTrue(fixture.driver.run())
        XCTAssertTrue(fixture.receiver.delivered.isEmpty)
        XCTAssertTrue(fixture.setup.snapshot.hasHeldOperation)
        fixture.setup.abort()
        fixture.drainDriver()
        XCTAssertEqual(fixture.receiver.delivered, [0])
    }

    func testMissingSetupAtSchedulerEntryUsesTheOriginalSingleHop() async {
        let driver = SmokeIngressSetupDriver()
        let receiver = SmokeIngressSetupReceiver()
        var setup: Win32NativeSmokeIngressSetup? = Win32NativeSmokeIngressSetup(
            scheduleActor: { driver.enqueue($0) })
        weak var releasedSetup = setup
        let scheduler = setup!.makeScheduler()
        setup = nil
        XCTAssertNil(releasedSetup)
        scheduler { receiver.calls += 1 }
        XCTAssertEqual(receiver.calls, 0)
        XCTAssertEqual(driver.count, 1)
        XCTAssertTrue(driver.run())
        XCTAssertEqual(receiver.calls, 1)
        XCTAssertEqual(driver.count, 0)
    }

    func testMissingSetupInPostedActorWrapperInvokesRawOperationDirectly() async {
        let driver = SmokeIngressSetupDriver()
        let receiver = SmokeIngressSetupReceiver()
        var setup: Win32NativeSmokeIngressSetup? = Win32NativeSmokeIngressSetup(
            scheduleActor: { driver.enqueue($0) })
        weak var releasedSetup = setup
        let scheduler = setup!.makeScheduler()
        scheduler { receiver.calls += 1 }
        setup = nil
        XCTAssertNil(releasedSetup)
        XCTAssertTrue(driver.run())
        XCTAssertEqual(receiver.calls, 1)
        XCTAssertEqual(driver.count, 0, "A nil weak setup must not post a second actor hop")
    }

    func testRealPrefixFlushAndSuffixAdmissionPrepareOneFullTurn() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        fixture.requestRelease()
        XCTAssertEqual(fixture.driver.count, 1)
        XCTAssertTrue(fixture.driver.run())
        XCTAssertTrue(fixture.setup.snapshot.prepared)
        XCTAssertEqual(fixture.ingress.snapshot.queuedRecords, 1)
        XCTAssertEqual(fixture.receiver.delivered, Array(UInt32(0)..<UInt32(63)))
        XCTAssertEqual(fixture.model?.releases, 1)
        XCTAssertEqual(fixture.model?.runnable, true)
        XCTAssertEqual(fixture.model?.resumed, false)
        XCTAssertEqual(fixture.driver.count, 2, "Only the original model job and one ingress successor are queued")
        XCTAssertTrue(fixture.driver.run())
        XCTAssertEqual(fixture.model?.resumed, true)
        XCTAssertTrue(fixture.driver.run())
        XCTAssertEqual(fixture.receiver.delivered, Array(UInt32(0)..<UInt32(64)))
        let verdict = try fixture.verdict()
        XCTAssertEqual(verdict.predicates.count, 27)
        XCTAssertEqual(verdict.predicates["backlogged-32-record-turn-and-continuation"], true)
        XCTAssertEqual(verdict.predicates["actor-progress-between-backlogged-turns"], true)
        XCTAssertFalse(verdict.insufficientFairnessExercise)
        XCTAssertTrue(fixture.setup.isIdleReady)
        XCTAssertTrue(fixture.failures.snapshot.isEmpty)
    }

    func testSetupDestructionTransfersHeldOriginalOperationWithoutRetainingItself() async {
        let driver = SmokeIngressSetupDriver()
        let receiver = SmokeIngressSetupReceiver()
        let failures = SmokeIngressSetupFailures()
        let key = NativeWindowKey()
        var setup: Win32NativeSmokeIngressSetup? = Win32NativeSmokeIngressSetup(
            scheduleActor: { driver.enqueue($0) })
        setup!.installFailureReporter { failures.append($0) }
        setup!.bind(windowKey: key) { nil }
        XCTAssertTrue(setup!.arm(windowKey: key))
        weak var releasedSetup = setup
        let scheduler = setup!.makeScheduler()
        scheduler { receiver.calls += 1 }
        XCTAssertTrue(driver.run())
        XCTAssertEqual(driver.count, 0)
        XCTAssertEqual(receiver.calls, 0)
        setup = nil
        XCTAssertNil(releasedSetup)
        XCTAssertEqual(driver.count, 1)
        XCTAssertTrue(driver.run())
        XCTAssertEqual(receiver.calls, 1)
        XCTAssertEqual(driver.count, 0)
    }

    func testSuccessorChosenBeforeRunnableModelRemainsUnqualified() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        fixture.requestRelease()
        XCTAssertTrue(fixture.driver.run())
        XCTAssertEqual(fixture.model?.runnable, true)
        XCTAssertTrue(fixture.driver.run(last: true), "The executor need not choose the earlier model job")
        XCTAssertEqual(fixture.model?.resumed, false)
        XCTAssertEqual(fixture.receiver.delivered.count, 64)
        XCTAssertTrue(fixture.driver.run())
        let verdict = try fixture.verdict()
        XCTAssertEqual(verdict.predicates.count, 27)
        XCTAssertEqual(verdict.predicates["backlogged-32-record-turn-and-continuation"], true)
        XCTAssertEqual(verdict.predicates["actor-progress-between-backlogged-turns"], false)
        XCTAssertTrue(verdict.insufficientFairnessExercise)
        XCTAssertFalse(verdict.qualifyingPredicatesSatisfied)
        XCTAssertTrue(fixture.setup.snapshot.prepared, "Preparation does not promise actor fairness")
    }

    func testAllThirtyThreeActualSuccessfulSuffixReceiptsAreRequired() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        fixture.requestRelease()
        for ordinal in UInt32(31)..<UInt32(63) { try fixture.admit(ordinal) }
        XCTAssertEqual(fixture.setup.snapshot.suffixReceiptCount, 32)
        XCTAssertTrue(fixture.setup.snapshot.hasHeldOperation)
        XCTAssertEqual(fixture.driver.count, 0)
        XCTAssertEqual(fixture.model?.releases, 0)
        try fixture.admit(63)
        XCTAssertEqual(fixture.driver.count, 1)
        fixture.drainDriver()
        XCTAssertEqual(fixture.receiver.delivered.count, 64)
    }

    func testRegistrationCannotSubstituteForActualAdmissionReceipts() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.ingress.enqueue(fixture.record(0)).get()
        XCTAssertTrue(fixture.driver.run())
        fixture.requestRelease()
        XCTAssertEqual(fixture.setup.snapshot.registeredCount, 64)
        XCTAssertEqual(fixture.setup.snapshot.suffixReceiptCount, 0)
        XCTAssertFalse(fixture.setup.snapshot.candidatePending)
        XCTAssertEqual(fixture.model?.releases, 0)
        fixture.setup.abort()
        fixture.drainDriver()
        XCTAssertEqual(fixture.receiver.delivered, [0])
    }

    func testInterveningSuffixFlushOpensWithoutRefillOrPreparation() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        try fixture.ingress.flush(through: 64).get()
        fixture.requestRelease()
        fixture.drainDriver()
        XCTAssertFalse(fixture.setup.snapshot.prepared)
        XCTAssertEqual(fixture.setup.snapshot.phase, .aborted)
        XCTAssertEqual(fixture.receiver.delivered, Array(UInt32(0)..<UInt32(64)))
        XCTAssertEqual(fixture.ingress.snapshot.queuedRecords, 0)
        XCTAssertFalse(fixture.setup.arm(windowKey: fixture.key), "An aborted setup cannot rearm")
        XCTAssertEqual(try fixture.verdict().predicates["backlogged-32-record-turn-and-continuation"], false)
    }

    func testAbsentOriginalReleaseRequestDoesNotInventModelProgress() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        XCTAssertEqual(fixture.driver.count, 0)
        XCTAssertEqual(fixture.model?.releases, 0)
        fixture.setup.abort()
        fixture.drainDriver()
        XCTAssertEqual(fixture.model?.releases, 0)
        XCTAssertFalse(fixture.setup.snapshot.firstReleaseRequested)
        XCTAssertEqual(fixture.receiver.delivered.count, 64)
    }

    func testReadyEarlierPostedOperationRunsCandidateWithoutAnotherHop() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix(holdOperation: false)
        try fixture.suffix()
        fixture.requestRelease()
        XCTAssertEqual(fixture.driver.count, 1, "The original reservation already has a queued wrapper")
        XCTAssertFalse(fixture.setup.snapshot.hasHeldOperation)
        XCTAssertTrue(fixture.driver.run())
        XCTAssertEqual(fixture.receiver.delivered.count, 63)
        XCTAssertEqual(fixture.driver.count, 2, "No second candidate dispatch precedes the real first turn")
        fixture.drainDriver()
    }

    func testOpeningPreviouslyPostedWrapperDoesNotPostItAgain() async {
        let fixture = SmokeIngressSetupHarness()
        let scheduler = fixture.setup.makeScheduler()
        scheduler { fixture.receiver.calls += 1 }
        fixture.setup.abort()
        XCTAssertTrue(fixture.driver.run())
        XCTAssertEqual(fixture.receiver.calls, 1)
        XCTAssertEqual(fixture.driver.count, 0)
        scheduler { fixture.receiver.calls += 1 }
        XCTAssertEqual(fixture.receiver.calls, 1, "A new successor is never invoked inline by schedule")
        XCTAssertEqual(fixture.driver.count, 1)
        XCTAssertTrue(fixture.driver.run())
        XCTAssertEqual(fixture.receiver.calls, 2)
        XCTAssertEqual(fixture.driver.count, 0)
    }

    func testRepeatedAbortReleasesHeldOperationOnlyOnce() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.admit(0)
        XCTAssertTrue(fixture.driver.run())
        fixture.setup.abort()
        fixture.setup.abort()
        fixture.setup.noteSuccessfulReply(
            ordinal: 31, requestID: fixture.requests[31], surface: fixture.record(31).observation.surface)
        XCTAssertEqual(fixture.driver.count, 1)
        fixture.drainDriver()
        XCTAssertEqual(fixture.receiver.delivered, [0])
        XCTAssertTrue(fixture.setup.isIdleReady)
    }

    func testAbortAfterSelectionLeavesCandidateOwnershipAndOriginalReleaseIntact() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        fixture.requestRelease()
        fixture.setup.abort()
        fixture.setup.abort()
        XCTAssertEqual(fixture.driver.count, 1)
        XCTAssertTrue(fixture.setup.snapshot.candidatePending)
        XCTAssertFalse(fixture.setup.isIdleReady)
        fixture.drainDriver()
        XCTAssertFalse(fixture.setup.snapshot.prepared)
        XCTAssertEqual(fixture.model?.releases, 1)
        XCTAssertEqual(fixture.receiver.delivered, Array(UInt32(0)..<UInt32(64)))
        XCTAssertTrue(fixture.setup.isIdleReady)
    }

    func testReentrantAbortFromReleaseCannotReclaimCandidateOperation() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        fixture.setup.requestFirstRelease { [weak setup = fixture.setup] in
            setup?.abort()
            return .invoked
        }
        fixture.drainDriver()
        XCTAssertFalse(fixture.setup.snapshot.prepared)
        XCTAssertEqual(fixture.facade?.reads, 0, "A cancellation/failure abort wins before final preparation")
        XCTAssertEqual(fixture.receiver.delivered, Array(UInt32(0)..<UInt32(64)))
        XCTAssertTrue(fixture.setup.isIdleReady)
    }

    func testMissingWeakModelDoesNotCountAsRunnableOrPrepared() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        fixture.requestRelease()
        fixture.model = nil
        fixture.drainDriver()
        XCTAssertEqual(fixture.failures.snapshot, [.modelUnavailable])
        XCTAssertFalse(fixture.setup.snapshot.prepared)
        XCTAssertEqual(fixture.observation.snapshot().count(.modelFirstResumed), 0)
        XCTAssertEqual(fixture.receiver.delivered.count, 64)
        XCTAssertTrue(fixture.setup.isIdleReady)
    }

    func testMissingWeakFacadeDoesNotQualifyRetainedOldIngress() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        fixture.requestRelease()
        fixture.facade = nil
        fixture.drainDriver()
        XCTAssertEqual(fixture.failures.snapshot, [.currentBindingUnavailable])
        XCTAssertFalse(fixture.setup.snapshot.prepared)
        XCTAssertEqual(fixture.receiver.delivered.count, 64)
    }

    func testReplacementIngressInvalidatesAnOldStillAliveOperation() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        fixture.requestRelease()
        let driver = fixture.driver
        let replacement = Win32NativeEventIngress(schedule: { driver.enqueue($0) }, receive: { _ in })
        fixture.facade?.ingress = replacement
        XCTAssertEqual(fixture.ingress.snapshot.queuedRecords, 33)
        fixture.drainDriver()
        XCTAssertEqual(fixture.failures.snapshot, [.currentBindingUnavailable])
        XCTAssertFalse(fixture.setup.snapshot.prepared)
        XCTAssertEqual(fixture.receiver.delivered.count, 64)
    }

    func testCloseBegunDuringPrefixFlushFailsCurrentBindingCheck() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        fixture.receiver.duringDelivery = { [weak facade = fixture.facade] record in
            if case .smokeProbe(let probe) = record.event, probe.ordinal == 30 {
                facade?.state.closeInProgress = true
            }
        }
        try fixture.prefix()
        try fixture.suffix()
        fixture.requestRelease()
        fixture.drainDriver()
        XCTAssertEqual(fixture.failures.snapshot, [.currentBindingUnavailable])
        XCTAssertFalse(fixture.setup.snapshot.prepared)
        XCTAssertEqual(fixture.receiver.delivered.count, 64)
    }

    func testEveryCurrentLifecycleFlagAndMissingOwnerRejectSnapshot() async throws {
        let fixture = SmokeIngressSetupHarness()
        let facade = try XCTUnwrap(fixture.facade)
        let healthy = facade.state
        XCTAssertNotNil(facade.snapshot(expectedIngress: fixture.ingress, key: fixture.key))
        let flags: [WritableKeyPath<Win32NativeSmokeIngressBindingState, Bool>] = [
            \.startInProgress, \.closeInProgress, \.closePrepared, \.willCloseDelivered,
            \.destructionObserved, \.terminalCloseDelivered, \.ownerFailed, \.creationFailed,
            \.destructionStarted, \.destructionCompleted,
        ]
        for flag in flags {
            facade.state = healthy
            facade.state[keyPath: flag] = true
            XCTAssertNil(facade.snapshot(expectedIngress: fixture.ingress, key: fixture.key))
        }
        facade.state = healthy
        facade.state.hasNativeOwner = false
        XCTAssertNil(facade.snapshot(expectedIngress: fixture.ingress, key: fixture.key))
    }

    func testCurrentWindowSurfaceAndCloseLifetimeMustAllMatch() async throws {
        let fixture = SmokeIngressSetupHarness()
        let facade = try XCTUnwrap(fixture.facade)
        let healthy = facade.state
        let other = NativeWindowKey(windowID: fixture.key.windowID)
        facade.state.windowKey = other
        XCTAssertNil(facade.snapshot(expectedIngress: fixture.ingress, key: fixture.key))
        facade.state = healthy
        facade.state.surfaceKey = other
        XCTAssertNil(facade.snapshot(expectedIngress: fixture.ingress, key: fixture.key))
        facade.state = healthy
        facade.state.closeLifetimeID = other.lifetimeID
        XCTAssertNil(facade.snapshot(expectedIngress: fixture.ingress, key: fixture.key))
        facade.state = healthy
        facade.state.surfaceKey = nil
        XCTAssertNil(facade.snapshot(expectedIngress: fixture.ingress, key: fixture.key))
        facade.state = healthy
        facade.state.closeLifetimeID = nil
        XCTAssertNil(facade.snapshot(expectedIngress: fixture.ingress, key: fixture.key))
        facade.state = healthy
        facade.ingress = nil
        XCTAssertNil(facade.snapshot(expectedIngress: fixture.ingress, key: fixture.key))
    }

    func testInvalidOrDuplicatedRegistrationAbortsWithoutReplacementWork() async {
        let invalid = SmokeIngressSetupHarness()
        XCTAssertTrue(invalid.setup.arm(windowKey: invalid.key))
        invalid.setup.register(ordinal: 64, requestID: NativeWindowRequestID(), windowKey: invalid.key)
        XCTAssertEqual(invalid.failures.snapshot, [.invalidRequest])
        let duplicated = SmokeIngressSetupHarness()
        duplicated.armAndRegister()
        duplicated.setup.register(ordinal: 0, requestID: duplicated.requests[0], windowKey: duplicated.key)
        XCTAssertEqual(duplicated.failures.snapshot, [.duplicateRequest])
        XCTAssertEqual(duplicated.setup.snapshot.registeredCount, 64)
        XCTAssertEqual(duplicated.driver.count, 0)
        let reused = SmokeIngressSetupHarness()
        XCTAssertTrue(reused.setup.arm(windowKey: reused.key))
        reused.setup.register(ordinal: 0, requestID: reused.requests[0], windowKey: reused.key)
        reused.setup.register(ordinal: 1, requestID: reused.requests[0], windowKey: reused.key)
        XCTAssertEqual(reused.failures.snapshot, [.duplicateRequest])
    }

    func testWrongReplyIdentityOrLifetimeCannotCountAsAdmission() async {
        for wrongLifetime in [false, true] {
            let fixture = SmokeIngressSetupHarness()
            fixture.armAndRegister()
            let record = fixture.record(31, key: wrongLifetime ? NativeWindowKey() : fixture.key)
            fixture.setup.noteSuccessfulReply(
                ordinal: 31, requestID: wrongLifetime ? fixture.requests[31] : NativeWindowRequestID(),
                surface: record.observation.surface)
            XCTAssertEqual(fixture.failures.snapshot, [.invalidReceipt])
            XCTAssertEqual(fixture.setup.snapshot.suffixReceiptCount, 0)
            XCTAssertEqual(fixture.driver.count, 0)
        }
    }

    func testDuplicateAndUnorderedReceiptsAbortInsteadOfCompletingTheMask() async throws {
        let duplicated = SmokeIngressSetupHarness()
        duplicated.armAndRegister()
        try duplicated.admit(0)
        duplicated.setup.noteSuccessfulReply(
            ordinal: 0, requestID: duplicated.requests[0], surface: duplicated.record(0).observation.surface)
        XCTAssertEqual(duplicated.failures.snapshot, [.duplicateReceipt])
        duplicated.drainDriver()
        let unordered = SmokeIngressSetupHarness()
        unordered.armAndRegister()
        try unordered.admit(0)
        unordered.setup.noteSuccessfulReply(
            ordinal: 1, requestID: unordered.requests[1],
            surface: unordered.record(1, sequence: 1).observation.surface)
        XCTAssertEqual(unordered.failures.snapshot, [.unorderedReceipt])
        unordered.drainDriver()
    }

    func testSurfaceGenerationChangesDoNotInventAWindowLifetimeChange() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        for ordinal in UInt32(31)..<UInt32(64) {
            try fixture.admit(ordinal, generation: UInt64(ordinal / 16 + 1))
        }
        fixture.requestRelease()
        fixture.drainDriver()
        XCTAssertTrue(fixture.setup.snapshot.prepared)
        XCTAssertTrue(fixture.failures.snapshot.isEmpty)
        XCTAssertEqual(fixture.receiver.delivered.count, 64)
    }

    func testFailureReporterCanReenterAndAbortOutsideTheMutex() async {
        let driver = SmokeIngressSetupDriver()
        let setup = Win32NativeSmokeIngressSetup(scheduleActor: { driver.enqueue($0) })
        let failures = SmokeIngressSetupFailures()
        setup.installFailureReporter { [weak setup] failure in
            _ = setup?.snapshot
            setup?.abort()
            failures.append(failure)
        }
        setup.register(ordinal: 64, requestID: NativeWindowRequestID(), windowKey: NativeWindowKey())
        XCTAssertEqual(failures.snapshot, [.invalidRequest])
        XCTAssertEqual(setup.snapshot.phase, .aborted)
    }

    func testCapturedOperationValueReleasesOutsideTheSetupMutex() async {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        let releases = SmokeIngressSetupCounter()
        let scheduler = fixture.setup.makeScheduler()
        do {
            let probe = SmokeIngressSetupReleaseProbe { [weak setup = fixture.setup] in
                _ = setup?.snapshot
                releases.increment()
            }
            scheduler { [probe] in withExtendedLifetime(probe) {} }
        }
        XCTAssertTrue(fixture.driver.run())
        XCTAssertEqual(releases.count, 0)
        fixture.setup.abort()
        XCTAssertEqual(releases.count, 0)
        fixture.drainDriver()
        XCTAssertEqual(releases.count, 1)
    }

    func testSharedFailureReplyCannotCountAsSuccessfulSuffixReadiness() async {
        let observation = Win32NativeSmokeObservation(runID: Foundation.UUID())
        let shared = NativeOwnedSmokeSharedState(observation: observation, expectedBackendNames: [])
        let key = NativeWindowKey()
        let request = NativeWindowRequestID()
        shared.ingressSetup.bind(windowKey: key) { nil }
        XCTAssertTrue(shared.ingressSetup.arm(windowKey: key))
        shared.ingressSetup.register(ordinal: 31, requestID: request, windowKey: key)
        shared.recordReply(ordinal: 31, requestID: request, result: .failure(.closed))
        XCTAssertEqual(shared.snapshot().replyMask, UInt64(1) << 31, "The existing reply mask includes failures")
        XCTAssertEqual(shared.ingressSetup.snapshot.suffixReceiptCount, 0)
        XCTAssertEqual(shared.ingressSetup.snapshot.phase, .aborted)
        XCTAssertEqual(observation.snapshot().count(.ownedCommandReply), 1)
        XCTAssertEqual(observation.snapshot().last(.ownedCommandReply)?.flags, 0)
    }

    func testSharedSuccessReplyPreservesOriginalRecordAndExactReceipt() async {
        let fixture = SmokeIngressSetupHarness()
        let observation = Win32NativeSmokeObservation(runID: Foundation.UUID())
        let shared = NativeOwnedSmokeSharedState(observation: observation, expectedBackendNames: [])
        shared.ingressSetup.bind(windowKey: fixture.key) { nil }
        XCTAssertTrue(shared.ingressSetup.arm(windowKey: fixture.key))
        shared.ingressSetup.register(ordinal: 31, requestID: fixture.requests[31], windowKey: fixture.key)
        let surface = fixture.record(31, generation: 9).observation.surface
        shared.recordReply(ordinal: 31, requestID: fixture.requests[31], result: .success(surface))
        XCTAssertEqual(shared.ingressSetup.snapshot.suffixReceiptCount, 1)
        let reply = observation.snapshot().last(.ownedCommandReply)
        XCTAssertEqual(reply?.flags, 1)
        XCTAssertEqual(reply?.requestID, fixture.requests[31])
        XCTAssertEqual(reply?.nativeSequence, surface.geometry.nativeSequence)
        XCTAssertEqual(reply?.generation, 9)
        XCTAssertFalse(shared.ingressSetup.snapshot.candidatePending)
        shared.releaseExternalResources()
        XCTAssertEqual(shared.ingressSetup.snapshot.phase, .aborted)
    }

    func testLateOriginalFirstReleaseAfterAbortForwardsOnlyOnce() async {
        let fixture = SmokeIngressSetupHarness()
        fixture.setup.abort()
        fixture.requestRelease()
        XCTAssertEqual(fixture.model?.releases, 1)
        fixture.requestRelease()
        XCTAssertEqual(fixture.model?.releases, 1)
        XCTAssertEqual(fixture.failures.snapshot, [.duplicateFirstRelease])
        fixture.drainDriver()
    }

    func testIdleReadinessIncludesSelectedCandidateAndPendingReleaseCleanup() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.admit(0)
        XCTAssertTrue(fixture.driver.run())
        fixture.requestRelease()
        fixture.setup.abort()
        XCTAssertFalse(fixture.setup.isIdleReady)
        XCTAssertEqual(fixture.driver.count, 2)
        XCTAssertTrue(fixture.driver.run())
        XCTAssertFalse(fixture.setup.isIdleReady, "The original first release still has to be forwarded")
        XCTAssertTrue(fixture.driver.run())
        XCTAssertTrue(fixture.setup.isIdleReady)
        fixture.drainDriver()
    }

    func testTerminalIngressFailureCannotBecomePreparedAndStillDrainsAcceptedInput() async throws {
        let fixture = SmokeIngressSetupHarness()
        fixture.armAndRegister()
        try fixture.prefix()
        try fixture.suffix()
        fixture.ingress.fail(.closed, windowKey: fixture.key)
        fixture.requestRelease()
        fixture.drainDriver()
        XCTAssertFalse(fixture.setup.snapshot.prepared)
        XCTAssertEqual(fixture.failures.snapshot, [.ingressUnavailable])
        XCTAssertEqual(fixture.receiver.delivered, Array(UInt32(0)..<UInt32(64)))
        XCTAssertEqual(fixture.receiver.failures.map(\.failure), [.closed])
    }
}
