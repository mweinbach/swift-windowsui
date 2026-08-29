import Foundation
import SwiftWindowsCore
import Synchronization
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

private final class NativeOwnerTestValues<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) { storage.withLock { $0.append(value) } }
    var all: [Value] { storage.withLock { $0 } }
}

@MainActor
private final class NativeOwnerTestReceiver {
    var delivered: [UInt64] = []
    var duringDelivery: ((Win32NativeWindowEventRecord) -> Void)?

    func receive(_ record: Win32NativeWindowEventRecord) {
        delivered.append(record.observation.surface.geometry.nativeSequence)
        duringDelivery?(record)
    }
}

private struct NativeOwnerRejectedTestCommand: NativeWindowOwnerCommand {
    let windowKey = NativeWindowKey()
    let requestID = NativeWindowRequestID()
    let failures: NativeOwnerTestValues<NativeWindowOwnerFailure>
    let reply: NativeWindowReply<Void>
    var commandReply: NativeWindowCommandReply { reply.commandReply }

    init(failures: NativeOwnerTestValues<NativeWindowOwnerFailure>) {
        self.failures = failures
        reply = NativeWindowReply { result in
            if case .failure(let failure) = result { failures.append(failure) }
        }
    }

    func execute(in context: any NativeWindowOwnerContext) throws {
        throw NativeWindowOwnerFailure.execution("An unstarted pump must not execute this command")
    }

    func reject(_ failure: NativeWindowOwnerFailure) { reply.complete(.failure(failure)) }
}

/// These fixtures exercise only copied values and actor/locked bookkeeping.
/// They never start a native pump, create an HWND, or query a live OS service.
@MainActor
final class Win32NativeOwnerTransportTests: XCTestCase {

    private func record(
        sequence: UInt64, event: Win32NativeWindowEvent = .textInput("input"), key: NativeWindowKey = NativeWindowKey()
    ) -> Win32NativeWindowEventRecord {
        let geometry = NativeWindowGeometry(
            revision: sequence, nativeSequence: sequence, clientSize: IntSize(width: 640, height: 480),
            clientScreenOrigin: Point(x: 10, y: 20), scaleFactor: 2, effectiveScaleFactor: 2,
            monitorRefreshRate: 60, isMinimized: false, isVisible: false, isActive: true)
        let surface = NativeWindowSurface(
            key: key, generation: 1,
            descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize, scaleFactor: 2),
            geometry: geometry)
        return Win32NativeWindowEventRecord(
            observation: Win32NativeWindowObservation(
                surface: surface, systemAppearance: .unavailable, displayIdentity: "fixture",
                isInLiveResize: false, isFullscreen: false),
            event: event)
    }

    func testIngressFlushesOnlyThroughRequestedSequence() async throws {
        let receiver = NativeOwnerTestReceiver()
        let ingress = Win32NativeEventIngress { receiver.receive($0) }
        let key = NativeWindowKey()
        ingress.enqueue(record(sequence: 1, key: key))
        ingress.enqueue(record(sequence: 2, key: key))
        ingress.enqueue(record(sequence: 3, key: key))
        try ingress.flush(through: 2).get()
        XCTAssertEqual(receiver.delivered, [1, 2])
        try ingress.flush(through: 3).get()
        XCTAssertEqual(receiver.delivered, [1, 2, 3])
        try ingress.flush(through: 3).get()
        XCTAssertEqual(receiver.delivered, [1, 2, 3])
    }

    func testIngressDoesNotPretendAnUnpublishedSequenceWasDelivered() async throws {
        let receiver = NativeOwnerTestReceiver()
        let ingress = Win32NativeEventIngress { receiver.receive($0) }
        ingress.enqueue(record(sequence: 1))
        try ingress.flush(through: 1).get()
        switch ingress.flush(through: 2) {
        case .success: XCTFail("A newer native sequence was never published")
        case .failure(let failure): XCTAssertEqual(failure, .unavailable)
        }
        XCTAssertEqual(receiver.delivered, [1])
    }

    func testInputReentryCannotFlushTheNextEvent() async throws {
        let receiver = NativeOwnerTestReceiver()
        let ingress = Win32NativeEventIngress { receiver.receive($0) }
        var nestedFailure: NativeWindowOwnerFailure?
        receiver.duringDelivery = { record in
            guard record.observation.surface.geometry.nativeSequence == 1 else { return }
            if case .failure(let failure) = ingress.flush(through: 2) { nestedFailure = failure }
            XCTAssertEqual(receiver.delivered, [1])
        }
        defer { receiver.duringDelivery = nil }
        ingress.enqueue(record(sequence: 1))
        ingress.enqueue(record(sequence: 2))
        try ingress.flush(through: 2).get()
        XCTAssertNotNil(nestedFailure)
        XCTAssertEqual(receiver.delivered, [1, 2])
    }

    func testCrossWindowReentryRejectsEvenAnOlderCommittedSequence() async throws {
        let firstReceiver = NativeOwnerTestReceiver()
        let secondReceiver = NativeOwnerTestReceiver()
        let first = Win32NativeEventIngress { firstReceiver.receive($0) }
        let second = Win32NativeEventIngress { secondReceiver.receive($0) }
        second.enqueue(record(sequence: 1))
        try second.flush(through: 1).get()
        second.enqueue(record(sequence: 2))
        var refused = false
        firstReceiver.duringDelivery = { _ in
            if case .failure = second.flush(through: 1) { refused = true }
            XCTAssertEqual(secondReceiver.delivered, [1])
        }
        defer { firstReceiver.duringDelivery = nil }
        first.enqueue(record(sequence: 1))
        try first.flush(through: 1).get()
        XCTAssertTrue(refused)
        try second.flush(through: 2).get()
        XCTAssertEqual(secondReceiver.delivered, [1, 2])
    }

    func testCoalescingNeverDropsInputBetweenFrameAndPaintRequests() async throws {
        let receiver = NativeOwnerTestReceiver()
        let ingress = Win32NativeEventIngress { receiver.receive($0) }
        ingress.enqueue(record(sequence: 1, event: .animationFrame(100)))
        ingress.enqueue(record(sequence: 2, event: .animationFrame(101)))
        ingress.enqueue(record(sequence: 3, event: .textInput("a")))
        ingress.enqueue(record(sequence: 4, event: .needsDisplay))
        ingress.enqueue(record(sequence: 5, event: .needsDisplay))
        ingress.enqueue(record(sequence: 6, event: .textInput("b")))
        try ingress.flush(through: 6).get()
        XCTAssertEqual(receiver.delivered, [1, 3, 4, 6])
        ingress.enqueue(record(sequence: 7, event: .animationFrame(102)))
        ingress.enqueue(record(sequence: 8, event: .needsDisplay))
        try ingress.flush(through: 8).get()
        XCTAssertEqual(receiver.delivered, [1, 3, 4, 6, 7, 8])
    }

    func testCoalescedTailHasAnHonestPublishedSequenceBoundary() async throws {
        let receiver = NativeOwnerTestReceiver()
        let ingress = Win32NativeEventIngress { receiver.receive($0) }
        ingress.enqueue(record(sequence: 1, event: .animationFrame(1)))
        ingress.enqueue(record(sequence: 2, event: .animationFrame(2)))
        try ingress.flush(through: 2).get()
        XCTAssertEqual(receiver.delivered, [1])
        if case .success = ingress.flush(through: 3) { XCTFail("Coalescing cannot invent future publication") }
    }

    func testUnstartedPumpRejectsRatherThanExecutingOrReportingSuccess() async throws {
        let pump = Win32NativePump()
        let failures = NativeOwnerTestValues<NativeWindowOwnerFailure>()
        let command = NativeOwnerRejectedTestCommand(failures: failures)
        XCTAssertEqual(pump.submit(command), .rejected(.ownerStopped))
        XCTAssertEqual(failures.all, [.ownerStopped])
    }

    func testSnapshotSourceCopiesGeometryAndRevokesWithoutNativeCalls() async throws {
        let source = Win32NativeSnapshotSource()
        if case .success = source.snapshot() { XCTFail("An uncreated surface is unavailable") }
        let original = record(sequence: 3).observation.surface
        source.publish(original)
        var changed = original.geometry
        changed.clientSize = IntSize(width: 1, height: 1)
        XCTAssertEqual(try source.snapshot().get().geometry.clientSize, IntSize(width: 640, height: 480))
        XCTAssertNotEqual(changed.clientSize, original.geometry.clientSize)
        source.revoke(.closing)
        XCTAssertEqual(source.snapshot(), .failure(.closing))
    }

    func testCreationFailureRetainsAnUndestroyedHandleOrNativeResource() async throws {
        XCTAssertEqual(
            Win32NativeCreationCleanup.afterFailure(
                didBindHandle: true, didObserveNonClientDestruction: false, hasLiveNativeResources: false),
            .retainOwner)
        XCTAssertEqual(
            Win32NativeCreationCleanup.afterFailure(
                didBindHandle: true, didObserveNonClientDestruction: true, hasLiveNativeResources: true),
            .retainOwner)
    }

    func testCreationFailureReleasesOnlyBeforeBindingOrAfterObservedCleanup() async throws {
        XCTAssertEqual(
            Win32NativeCreationCleanup.afterFailure(
                didBindHandle: false, didObserveNonClientDestruction: false, hasLiveNativeResources: false),
            .releaseOwner)
        XCTAssertEqual(
            Win32NativeCreationCleanup.afterFailure(
                didBindHandle: true, didObserveNonClientDestruction: true, hasLiveNativeResources: false),
            .releaseOwner)
    }

    func testFailedDrainWakePreventsTheNativeCommitClaim() async throws {
        let replies = NativeOwnerTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let request = Win32NativeDestructionRequest(
            key: NativeWindowKey(), reply: NativeWindowReply { replies.append($0) })
        XCTAssertTrue(request.complete(.failure(.postFailed(code: 1816))))
        XCTAssertTrue(request.isTerminal)
        XCTAssertFalse(request.claimDestruction())
        XCTAssertFalse(
            request.complete(
                .success(
                    Win32NativeCloseDestruction(
                        nativeResult: .succeeded, didObserveNonClientDestruction: true, didUnwindNativeDispatch: true)))
        )
        XCTAssertEqual(replies.all, [.failure(.postFailed(code: 1816))])
    }

    func testNativeCommitClaimKeepsTheActualResultWhenLaterWakeFails() async throws {
        let replies = NativeOwnerTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let request = Win32NativeDestructionRequest(
            key: NativeWindowKey(), reply: NativeWindowReply { replies.append($0) })
        XCTAssertTrue(request.claimDestruction())
        XCTAssertFalse(request.complete(.failure(.postFailed(code: 1816))))
        XCTAssertFalse(request.isTerminal)
        let actual = Win32NativeCloseDestruction(
            nativeResult: .failed(5), didObserveNonClientDestruction: false, didUnwindNativeDispatch: true)
        XCTAssertTrue(request.complete(.success(actual)))
        XCTAssertEqual(replies.all, [.success(actual)])
        XCTAssertFalse(request.claimDestruction())
    }
}
