import SwiftWindowsCore
import Synchronization
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

private final class NativeTimerPolicyTestSink: NativeWindowCommandSink {
    private struct State {
        var commands: [Win32NativeTimerPolicyCommand] = []
        var nextRejection: NativeWindowOwnerFailure?
    }

    private let state = Mutex(State())
    var count: Int { state.withLock { $0.commands.count } }

    func command(at index: Int) -> Win32NativeTimerPolicyCommand? {
        state.withLock { $0.commands.indices.contains(index) ? $0.commands[index] : nil }
    }

    func rejectNext(_ failure: NativeWindowOwnerFailure) {
        state.withLock { $0.nextRejection = failure }
    }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        guard let timer = command as? Win32NativeTimerPolicyCommand else {
            let failure = NativeWindowOwnerFailure.execution("Unexpected command in native timer fixture")
            command.reject(failure)
            return .rejected(failure)
        }
        let failure = state.withLock { stored in
            stored.commands.append(timer)
            let failure = stored.nextRejection
            stored.nextRejection = nil
            return failure
        }
        if let failure {
            // No fixture lock spans a callback, matching the real sink's
            // immediate-rejection contract. No native body is executed.
            timer.reject(failure)
            return .rejected(failure)
        }
        return .accepted
    }
}

@MainActor
private final class NativeTimerPolicyTestObserver {
    var results: [Result<Win32NativeTimerPolicyReceipt, NativeWindowOwnerFailure>] = []
    var nextCompletion: ((Result<Win32NativeTimerPolicyReceipt, NativeWindowOwnerFailure>) -> Void)?

    func receive(_ result: Result<Win32NativeTimerPolicyReceipt, NativeWindowOwnerFailure>) {
        results.append(result)
        let completion = nextCompletion
        nextCompletion = nil
        completion?(result)
    }
}

@MainActor
private final class NativeTimerPolicyTestFixture {
    let key = NativeWindowKey()
    let sink = NativeTimerPolicyTestSink()
    let observer: NativeTimerPolicyTestObserver
    let coordinator: Win32NativeTimerPolicyCoordinator

    init() {
        let observer = NativeTimerPolicyTestObserver()
        self.observer = observer
        coordinator = Win32NativeTimerPolicyCoordinator { [weak observer] result in observer?.receive(result) }
    }

    func surface(generation: UInt64 = 1, sequence: UInt64 = 1, key: NativeWindowKey? = nil) -> NativeWindowSurface {
        let size = IntSize(width: 320, height: 240)
        return NativeWindowSurface(
            key: key ?? self.key, generation: generation,
            descriptor: SurfaceDescriptor(offscreenPixelSize: size),
            geometry: NativeWindowGeometry(
                revision: sequence, nativeSequence: sequence, clientSize: size,
                clientScreenOrigin: Point(x: Double(sequence), y: 0), scaleFactor: 1, effectiveScaleFactor: 1,
                monitorRefreshRate: 60, isMinimized: false, isVisible: false, isActive: false))
    }

    func bind(generation: UInt64? = 1) {
        coordinator.bind(windowKey: key, commandSink: sink)
        if let generation { coordinator.observeSurface(surface(generation: generation)) }
    }

    func command(_ index: Int) throws -> Win32NativeTimerPolicyCommand {
        try XCTUnwrap(sink.command(at: index))
    }

    func waitForCompletion(
        _ action: () -> Void,
        inspect: @escaping (Result<Win32NativeTimerPolicyReceipt, NativeWindowOwnerFailure>) -> Void = { _ in }
    ) async {
        let completion = XCTestExpectation(description: "actor consumed exact timer reply")
        observer.nextCompletion = { result in
            inspect(result)
            completion.fulfill()
        }
        action()
        let outcome = await XCTWaiter.fulfillment(of: [completion], timeout: 2)
        observer.nextCompletion = nil
        XCTAssertEqual(outcome, .completed)
    }

    func succeed(_ index: Int, actualGeneration: UInt64 = 1) async throws {
        let command = try self.command(index)
        await waitForCompletion {
            command.reply.complete(
                .success(
                    Win32NativeTimerPolicyReceipt(
                        request: command.request, appliedSurfaceGeneration: actualGeneration)))
        }
    }
}

/// Controlled value replies exercise the production coordinator and command
/// envelope. These tests never create a window, start a pump, or install a timer.
@MainActor
final class Win32NativeTimerPolicyTests: XCTestCase {
    private let policyA = Win32NativeTimerPolicy(enabled: true, intervalMilliseconds: 16, highResolution: true)
    private let policyB = Win32NativeTimerPolicy(enabled: false, intervalMilliseconds: 16, highResolution: true)
    private let policyC = Win32NativeTimerPolicy(enabled: true, intervalMilliseconds: 8, highResolution: false)

    func testWindowSetterRetainsPrecreationIntentWithoutClaimingNativeApplication() async {
        let window = Win32Window(title: "Uncreated timer fixture", clientSize: IntSize(width: 320, height: 240))
        defer { window.nativeAnimationTimerPolicy.revoke() }
        window.useHighResolutionTimer = true
        window.setAnimationTimerEnabled(true, intervalMilliseconds: 0)
        XCTAssertFalse(window.usesNativeOwner)
        XCTAssertNil(window.nativeHandle)
        XCTAssertEqual(
            window.nativeAnimationTimerPolicy.desiredPolicy,
            Win32NativeTimerPolicy(enabled: true, intervalMilliseconds: 1, highResolution: true))
        XCTAssertNil(window.nativeAnimationTimerPolicy.inFlightRequest)
        XCTAssertNil(window.nativeAnimationTimerPolicy.appliedPolicy)
        window.setAnimationTimerEnabled(false, intervalMilliseconds: 12)
        XCTAssertEqual(
            window.nativeAnimationTimerPolicy.desiredPolicy,
            Win32NativeTimerPolicy(enabled: false, intervalMilliseconds: 12, highResolution: true))
        XCTAssertNil(window.nativeAnimationTimerPolicy.lastSuccessfulReceipt)
    }

    func testRepeatedIdenticalUpdatesShareOneFlightAndOneAppliedPolicy() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        for _ in 0..<100 { fixture.coordinator.setDesired(policyA) }
        XCTAssertEqual(fixture.sink.count, 1)
        XCTAssertNil(fixture.coordinator.appliedPolicy, "Command admission is not application.")
        XCTAssertEqual(fixture.coordinator.inFlightRequest?.policy, policyA)

        try await fixture.succeed(0)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyA)
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        for sequence in UInt64(2)...101 {
            fixture.coordinator.observeSurface(fixture.surface(sequence: sequence))
            fixture.coordinator.setDesired(policyA)
        }
        XCTAssertEqual(fixture.sink.count, 1)
        XCTAssertEqual(fixture.observer.results.count, 1)
    }

    func testInFlightAToBToAElidesTheUnsentB() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        fixture.coordinator.setDesired(policyB)
        fixture.coordinator.setDesired(policyA)
        XCTAssertEqual(fixture.sink.count, 1)
        try await fixture.succeed(0)
        XCTAssertEqual(fixture.coordinator.desiredPolicy, policyA)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyA)
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertEqual(fixture.sink.count, 1)
    }

    func testSuccessSubmitsOnlyTheLatestUnsentDesiredPolicy() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        fixture.coordinator.setDesired(policyB)
        fixture.coordinator.setDesired(policyC)
        XCTAssertEqual(fixture.sink.count, 1)

        try await fixture.succeed(0)
        XCTAssertEqual(fixture.sink.count, 2)
        XCTAssertEqual(try fixture.command(1).request.policy, policyC)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyA)
        XCTAssertEqual(fixture.coordinator.inFlightRequest?.policy, policyC)
        try await fixture.succeed(1)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyC)
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertEqual(fixture.sink.count, 2)
    }

    func testSuccessCalloutChangesOnlyUnsentDesiredWhileTheNextFlightIsReserved() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        fixture.coordinator.setDesired(policyB)
        let first = try fixture.command(0)
        await fixture.waitForCompletion(
            {
                first.reply.complete(
                    .success(Win32NativeTimerPolicyReceipt(request: first.request, appliedSurfaceGeneration: 1)))
            },
            inspect: { _ in
                XCTAssertEqual(fixture.coordinator.inFlightRequest?.policy, self.policyB)
                fixture.coordinator.setDesired(self.policyC)
                XCTAssertEqual(fixture.sink.count, 2)
            })
        XCTAssertEqual(try fixture.command(1).request.policy, policyB)
        XCTAssertEqual(fixture.coordinator.desiredPolicy, policyC)
        try await fixture.succeed(1)
        XCTAssertEqual(fixture.sink.count, 3)
        XCTAssertEqual(try fixture.command(2).request.policy, policyC)
        try await fixture.succeed(2)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyC)
        XCTAssertNil(fixture.coordinator.inFlightRequest)
    }

    func testImmediateRejectionClearsItsReservationWithoutAutomaticRetry() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        let failure = NativeWindowOwnerFailure.postFailed(code: 1816)
        fixture.sink.rejectNext(failure)
        await fixture.waitForCompletion {
            fixture.coordinator.setDesired(policyA)
            XCTAssertNotNil(fixture.coordinator.inFlightRequest)
            XCTAssertNil(fixture.coordinator.appliedPolicy)
        }
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertEqual(fixture.coordinator.lastFailure, failure)
        XCTAssertEqual(fixture.observer.results.last, .some(.failure(failure)))
        for sequence in UInt64(2)...100 {
            fixture.coordinator.setDesired(policyA)
            fixture.coordinator.observeSurface(fixture.surface(sequence: sequence))
        }
        XCTAssertEqual(fixture.sink.count, 1, "Equal declarations and passive observations must not retry failure.")
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertNil(fixture.coordinator.appliedPolicy)

        fixture.coordinator.setDesired(policyB)
        XCTAssertEqual(fixture.sink.count, 2, "An actual change in desired policy can admit a new request.")
        try await fixture.succeed(1)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyB)
    }

    func testExecutionFailureInvalidatesPriorAppliedStateAndDoesNotSendLaterDesired() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        try await fixture.succeed(0)
        fixture.coordinator.setDesired(policyB)
        fixture.coordinator.setDesired(policyC)
        let command = try fixture.command(1)
        let failure = NativeWindowOwnerFailure.native(operation: "SetTimer(animation)", code: 8)
        await fixture.waitForCompletion { command.reject(failure) }

        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertNil(fixture.coordinator.appliedPolicy, "A failed change may already have stopped/replaced A.")
        XCTAssertEqual(fixture.coordinator.desiredPolicy, policyC)
        XCTAssertEqual(fixture.coordinator.lastFailure, failure)
        XCTAssertEqual(fixture.sink.count, 2)
        for sequence in UInt64(2)...100 {
            fixture.coordinator.setDesired(policyC)
            fixture.coordinator.observeSurface(fixture.surface(sequence: sequence))
        }
        XCTAssertEqual(fixture.sink.count, 2)
        fixture.coordinator.setDesired(policyA)
        XCTAssertEqual(fixture.sink.count, 3, "Historical success for A cannot suppress its explicit reapplication.")
        try await fixture.succeed(2)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyA)
    }

    func testExecutionFailureIgnoresEqualDesiredUpdatesUntilANewSurfaceIsAdopted() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        let command = try fixture.command(0)
        let failure = NativeWindowOwnerFailure.native(operation: "timeBeginPeriod", code: 97)
        await fixture.waitForCompletion { command.reject(failure) }
        for sequence in UInt64(2)...100 {
            fixture.coordinator.setDesired(policyA)
            fixture.coordinator.observeSurface(fixture.surface(sequence: sequence))
        }
        XCTAssertEqual(fixture.sink.count, 1)
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertEqual(fixture.coordinator.lastFailure, failure)
        XCTAssertEqual(fixture.observer.results, [.failure(failure)])

        // Scope adoption is a distinct input; it is not a repeated policy
        // declaration from syncAnimationDriver for the failed surface.
        fixture.coordinator.observeSurface(fixture.surface(generation: 2, sequence: 101))
        XCTAssertEqual(fixture.sink.count, 2)
        XCTAssertEqual(try fixture.command(1).request.capturedSurfaceGeneration, 2)
        try await fixture.succeed(1, actualGeneration: 2)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyA)
    }

    func testMissingSurfaceRetainsOnlyDesiredAndReplaysAfterRealScopeAdoption() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.coordinator.setDesired(policyA)
        fixture.bind(generation: nil)
        fixture.coordinator.setDesired(policyA)
        fixture.coordinator.observeSurface(nil)
        fixture.coordinator.observeSurface(fixture.surface(key: NativeWindowKey()))
        XCTAssertEqual(fixture.coordinator.desiredPolicy, policyA)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertNil(fixture.coordinator.lastSuccessfulReceipt)
        XCTAssertEqual(fixture.sink.count, 0)

        fixture.coordinator.observeSurface(fixture.surface(generation: 3))
        XCTAssertEqual(fixture.sink.count, 1)
        let command = try fixture.command(0)
        XCTAssertEqual(command.request.windowKey, fixture.key)
        XCTAssertEqual(command.request.capturedSurfaceGeneration, 3)
        XCTAssertNil(command.expectedSurfaceGeneration, "Resize cannot invalidate a nongeometric timer policy.")
        try await fixture.succeed(0, actualGeneration: 3)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyA)
    }

    func testSurfaceChangeKeepsTheOneFlightAndReappliesAnOldActualReceiptOnce() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        let original = try fixture.command(0).request
        fixture.coordinator.observeSurface(fixture.surface(generation: 2))
        fixture.coordinator.setDesired(policyA)
        XCTAssertEqual(fixture.sink.count, 1)
        XCTAssertEqual(fixture.coordinator.inFlightRequest, original)

        try await fixture.succeed(0, actualGeneration: 1)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertEqual(fixture.sink.count, 2)
        let replacement = try fixture.command(1).request
        XCTAssertEqual(replacement.capturedSurfaceGeneration, 2)
        fixture.coordinator.receive(original, result: .failure(.closed))
        fixture.coordinator.receive(
            original,
            result: .success(Win32NativeTimerPolicyReceipt(request: original, appliedSurfaceGeneration: 2)))
        XCTAssertEqual(fixture.coordinator.inFlightRequest, replacement)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertNil(fixture.coordinator.lastFailure)
        XCTAssertEqual(fixture.observer.results.count, 1)
        try await fixture.succeed(1, actualGeneration: 2)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyA)
        XCTAssertEqual(fixture.sink.count, 2)
    }

    func testReceiptUsesActualNativeGenerationNotTheRequestsCapturedGeneration() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        fixture.coordinator.observeSurface(fixture.surface(generation: 2))
        XCTAssertEqual(try fixture.command(0).request.capturedSurfaceGeneration, 1)

        try await fixture.succeed(0, actualGeneration: 2)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyA)
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertEqual(fixture.sink.count, 1)
    }

    func testAheadNativeReceiptWaitsForActorGeometryWithoutCommandChurn() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        try await fixture.succeed(0, actualGeneration: 2)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertEqual(fixture.coordinator.lastSuccessfulReceipt?.appliedSurfaceGeneration, 2)
        for sequence in UInt64(2)...100 {
            fixture.coordinator.observeSurface(fixture.surface(sequence: sequence))
            fixture.coordinator.setDesired(policyA)
        }
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertEqual(fixture.sink.count, 1)

        fixture.coordinator.observeSurface(fixture.surface(generation: 2, sequence: 101))
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyA)
        XCTAssertEqual(fixture.sink.count, 1)
    }

    func testNewDesiredPolicyCanAdvanceWhileAnAheadReceiptWaitsForActorAdoption() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        try await fixture.succeed(0, actualGeneration: 2)
        fixture.coordinator.setDesired(policyB)
        XCTAssertEqual(fixture.sink.count, 2)
        XCTAssertEqual(try fixture.command(1).request.policy, policyB)
        try await fixture.succeed(1, actualGeneration: 2)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        fixture.coordinator.observeSurface(fixture.surface(generation: 2))
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyB)
        XCTAssertEqual(fixture.sink.count, 2)
    }

    func testRepeatedOldGenerationReceiptCannotCreateASuccessResubmitLoop() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        fixture.coordinator.observeSurface(fixture.surface(generation: 2))
        try await fixture.succeed(0, actualGeneration: 1)
        XCTAssertEqual(fixture.sink.count, 2)
        try await fixture.succeed(1, actualGeneration: 1)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertEqual(fixture.sink.count, 2)
        fixture.coordinator.observeSurface(fixture.surface(generation: 2, sequence: 100))
        XCTAssertEqual(fixture.sink.count, 2)
    }

    func testCloseAndNewLifetimeIgnoreOldSuccessAndFailureWithoutClearingNewFlight() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        let old = try fixture.command(0).request
        fixture.coordinator.revoke()
        fixture.coordinator.setDesired(policyC)
        XCTAssertNil(fixture.coordinator.desiredPolicy)
        fixture.coordinator.receive(
            old, result: .success(Win32NativeTimerPolicyReceipt(request: old, appliedSurfaceGeneration: 1)))
        fixture.coordinator.receive(old, result: .failure(.closed))
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertTrue(fixture.observer.results.isEmpty)
        let successor = NativeWindowKey(windowID: fixture.key.windowID)
        fixture.coordinator.bind(windowKey: successor, commandSink: fixture.sink)
        fixture.coordinator.setDesired(policyB)
        fixture.coordinator.observeSurface(fixture.surface(key: successor))
        let current = try fixture.command(1)

        // Deliver already-copied stale values at the actor receiver boundary;
        // this asserts rejection without relying on task FIFO scheduling.
        fixture.coordinator.receive(
            old, result: .success(Win32NativeTimerPolicyReceipt(request: old, appliedSurfaceGeneration: 1)))
        fixture.coordinator.receive(old, result: .failure(.postFailed(code: 5)))
        XCTAssertEqual(fixture.coordinator.inFlightRequest, current.request)
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertNil(fixture.coordinator.lastFailure)
        XCTAssertTrue(fixture.observer.results.isEmpty)
        XCTAssertEqual(fixture.sink.count, 2)
        try await fixture.succeed(1)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyB)
    }

    func testFailureCalloutCanBindANewLifetimeWithoutOldCompletionOverwritingIt() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        let successor = NativeWindowKey(windowID: fixture.key.windowID)
        let failure = NativeWindowOwnerFailure.postFailed(code: 1816)
        fixture.sink.rejectNext(failure)
        await fixture.waitForCompletion(
            { fixture.coordinator.setDesired(policyA) },
            inspect: { result in
                XCTAssertEqual(result, .failure(failure))
                XCTAssertNil(fixture.coordinator.inFlightRequest)
                XCTAssertNil(fixture.coordinator.appliedPolicy)
                fixture.coordinator.revoke()
                fixture.coordinator.bind(windowKey: successor, commandSink: fixture.sink)
                fixture.coordinator.setDesired(self.policyB)
                fixture.coordinator.observeSurface(fixture.surface(generation: 2, key: successor))
            })
        XCTAssertEqual(fixture.sink.count, 2)
        XCTAssertEqual(fixture.coordinator.inFlightRequest?.windowKey, successor)
        XCTAssertEqual(fixture.coordinator.inFlightRequest?.policy, policyB)
        XCTAssertNil(fixture.coordinator.lastFailure)
        try await fixture.succeed(1, actualGeneration: 2)
        XCTAssertEqual(fixture.coordinator.appliedPolicy, policyB)
    }

    func testForeignReceiptIsRejectedWithoutAppliedStateOrAutomaticRetry() async throws {
        let fixture = NativeTimerPolicyTestFixture()
        defer { fixture.coordinator.revoke() }
        fixture.bind()
        fixture.coordinator.setDesired(policyA)
        let command = try fixture.command(0)
        let foreign = Win32NativeTimerPolicyRequest(
            requestID: NativeWindowRequestID(), windowKey: fixture.key,
            capturedSurfaceGeneration: 1, policy: policyA)
        await fixture.waitForCompletion {
            command.reply.complete(
                .success(Win32NativeTimerPolicyReceipt(request: foreign, appliedSurfaceGeneration: 1)))
        }
        guard case .some(.execution) = fixture.coordinator.lastFailure else {
            return XCTFail("A mismatched native reply must not establish applied timer state.")
        }
        XCTAssertNil(fixture.coordinator.appliedPolicy)
        XCTAssertNil(fixture.coordinator.inFlightRequest)
        XCTAssertEqual(fixture.sink.count, 1)
    }
}
