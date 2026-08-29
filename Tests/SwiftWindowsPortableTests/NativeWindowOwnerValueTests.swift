import Foundation
import SwiftWindowsCore
import Synchronization
@preconcurrency import XCTest

private final class NativeReplyTestState: Sendable {
    let values = Mutex<[Int]>([])
    let failures = Mutex<[NativeWindowOwnerFailure]>([])
    let releases = Mutex<Int>(0)
    let reentrantCompletions = Mutex<[Bool]>([])
    let reply = Mutex<NativeWindowReply<Int>?>(nil)
}

private final class NativeReplyReleaseToken: Sendable {
    private let release: @Sendable () -> Void

    init(_ release: @escaping @Sendable () -> Void) { self.release = release }

    deinit { release() }
}

@MainActor
final class NativeWindowOwnerValueTests: XCTestCase {
    private func geometry() -> NativeWindowGeometry {
        NativeWindowGeometry(
            revision: 7, nativeSequence: 13, clientSize: IntSize(width: 900, height: 600),
            clientScreenOrigin: Point(x: -100, y: 30), scaleFactor: 1.5,
            effectiveScaleFactor: 1.5, monitorRefreshRate: 60, isMinimized: false,
            isVisible: true, isActive: true
        )
    }

    func testWindowLifetimeAndSurfaceGenerationHaveSeparateIdentity() async {
        let windowID = UUID()
        let first = NativeWindowKey(windowID: windowID)
        let reused = NativeWindowKey(windowID: windowID)
        XCTAssertNotEqual(first, reused)
        let surface = NativeWindowSurface(
            key: first, generation: 2,
            descriptor: SurfaceDescriptor(offscreenPixelSize: IntSize(width: 900, height: 600)),
            geometry: geometry()
        )
        let resized = NativeWindowSurface(
            key: first, generation: 3, descriptor: surface.descriptor, geometry: surface.geometry
        )
        XCTAssertEqual(surface.key, resized.key)
        XCTAssertNotEqual(surface, resized)
    }

    func testCopiedGeometryDoesNotObserveLaterOwnerUpdates() async {
        let captured = geometry()
        var current = captured
        current.revision += 1
        current.nativeSequence += 1
        current.clientScreenOrigin = Point(x: 80, y: -20)
        XCTAssertEqual(captured.revision, 7)
        XCTAssertEqual(captured.nativeSequence, 13)
        XCTAssertEqual(captured.clientScreenOrigin, Point(x: -100, y: 30))
        XCTAssertNotEqual(current, captured)
    }

    func testGeometryRoundsBothLogicalEndpointsBeforeScreenTranslation() async {
        let mapped = geometry().clientRectToScreen(Rect(x: 0.4, y: -0.4, width: 2, height: 2))
        XCTAssertEqual(mapped, Rect(x: -99, y: 29, width: 3, height: 3))
        var clamped = geometry()
        clamped.scaleFactor = 0.5
        clamped.effectiveScaleFactor = 1
        XCTAssertEqual(
            clamped.clientRectToScreen(Rect(x: 0.4, y: 0.4, width: 2, height: 2)),
            Rect(x: -100, y: 30, width: 2, height: 2)
        )
    }

    func testGeometryRejectsInvalidOrOverflowingCoordinates() async {
        let captured = geometry()
        XCTAssertNil(captured.clientRectToScreen(Rect(x: .nan, y: 0, width: 1, height: 1)))
        XCTAssertNil(captured.clientRectToScreen(Rect(x: .infinity, y: 0, width: 1, height: 1)))
        XCTAssertNil(captured.clientRectToScreen(Rect(x: Double(Int32.max), y: 0, width: 1, height: 1)))
        var invalid = captured
        invalid.effectiveScaleFactor = 0
        XCTAssertNil(invalid.clientRectToScreen(.zero))
        invalid = captured
        invalid.clientScreenOrigin.x = Double(Int32.min)
        XCTAssertNil(invalid.clientRectToScreen(Rect(x: -1, y: 0, width: 1, height: 1)))
    }

    func testReplyCompletesOnceAndInvokesOutsideItsLock() async {
        let state = NativeReplyTestState()
        let reply = NativeWindowReply<Int> { result in
            if case .success(let value) = result { state.values.withLock { $0.append(value) } }
            let nested = state.reply.withLock { $0 }
            let accepted = nested?.complete(.success(99)) ?? true
            state.reentrantCompletions.withLock { $0.append(accepted) }
        }
        state.reply.withLock { $0 = reply }
        XCTAssertTrue(reply.complete(.success(7)))
        XCTAssertFalse(reply.complete(.failure(.ownerStopped)))
        XCTAssertEqual(state.values.withLock { $0 }, [7])
        XCTAssertEqual(state.reentrantCompletions.withLock { $0 }, [false])
        state.reply.withLock { $0 = nil }
    }

    func testConcurrentReplyFailureAndSuccessStillHaveOneWinner() async {
        let state = NativeReplyTestState()
        let reply = NativeWindowReply<Int> { result in
            let value: Int
            switch result {
            case .success(let accepted): value = accepted
            case .failure: value = -1
            }
            state.values.withLock { $0.append(value) }
        }
        let winners = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for value in 0..<32 {
                group.addTask { reply.complete(value.isMultiple(of: 2) ? .success(value) : .failure(.closing)) }
            }
            var count = 0
            for await accepted in group where accepted { count += 1 }
            return count
        }
        XCTAssertEqual(winners, 1)
        XCTAssertEqual(state.values.withLock { $0.count }, 1)
    }

    func testPreparedReplyClaimsBeforeCallbackDeliveryAndDeliversOnlyOnce() async {
        let state = NativeReplyTestState()
        let reply = NativeWindowReply<Int> { result in
            if case .success(let value) = result { state.values.withLock { $0.append(value) } }
        }
        let delivery = reply.prepareCompletion(.success(7))
        XCTAssertNotNil(delivery)
        XCTAssertTrue(reply.isCompleted)
        XCTAssertTrue(reply.commandReply.isCompleted)
        XCTAssertFalse(reply.complete(.success(99)))
        XCTAssertNil(reply.commandReply.prepareFailure(.closing))
        XCTAssertTrue(state.values.withLock { $0.isEmpty })
        XCTAssertTrue(delivery?.deliver() ?? false)
        XCTAssertFalse(delivery?.deliver() ?? true)
        XCTAssertEqual(state.values.withLock { $0 }, [7])
    }

    func testCommandReplyCapabilitiesShareTheRealReplyIdentityAndTerminalResult() async {
        let state = NativeReplyTestState()
        let reply = NativeWindowReply<Int> { result in
            if case .failure(let failure) = result { state.failures.withLock { $0.append(failure) } }
        }
        let first = reply.commandReply
        let second = NativeWindowCommandReply(reply)
        let unrelated = NativeWindowReply<String> { _ in }.commandReply
        XCTAssertEqual(first.identity, second.identity)
        XCTAssertNotEqual(first.identity, unrelated.identity)
        let actualFailure = NativeWindowOwnerFailure.postFailed(code: 37)
        let delivery = first.prepareFailure(actualFailure)
        XCTAssertNotNil(delivery)
        XCTAssertTrue(second.isCompleted)
        XCTAssertNil(second.prepareFailure(.ownerStopped))
        XCTAssertFalse(reply.complete(.success(9)))
        XCTAssertTrue(state.failures.withLock { $0.isEmpty })
        XCTAssertTrue(delivery?.deliver() ?? false)
        XCTAssertEqual(state.failures.withLock { $0 }, [actualFailure])
        XCTAssertFalse(first.reject(.closing))
    }

    func testPreparedDeliveryRetainsCapturesUntilTheirOutsideLockRelease() async {
        let state = NativeReplyTestState()
        var token: NativeReplyReleaseToken? = NativeReplyReleaseToken {
            let reply = state.reply.withLock { $0 }
            let accepted = reply?.complete(.success(99)) ?? true
            state.reentrantCompletions.withLock { $0.append(accepted) }
            state.releases.withLock { $0 += 1 }
        }
        let reply = NativeWindowReply<Int> { [token] result in
            if case .success(let value) = result { state.values.withLock { $0.append(value) } }
            withExtendedLifetime(token) {}
        }
        state.reply.withLock { $0 = reply }
        token = nil
        let delivery = reply.prepareCompletion(.success(7))
        XCTAssertNotNil(delivery)
        XCTAssertEqual(state.releases.withLock { $0 }, 0)
        XCTAssertTrue(state.values.withLock { $0.isEmpty })
        XCTAssertTrue(delivery?.deliver() ?? false)
        XCTAssertEqual(state.values.withLock { $0 }, [7])
        XCTAssertEqual(state.releases.withLock { $0 }, 1)
        XCTAssertEqual(state.reentrantCompletions.withLock { $0 }, [false])
        state.reply.withLock { $0 = nil }
    }

    func testConcurrentCapabilityClaimsChooseOneUndeliveredFailure() async {
        let state = NativeReplyTestState()
        let reply = NativeWindowReply<Int> { result in
            if case .failure(let failure) = result { state.failures.withLock { $0.append(failure) } }
        }
        let capability = reply.commandReply
        let winners = await withTaskGroup(
            of: (Int, NativeWindowReplyDelivery?).self,
            returning: [(Int, NativeWindowReplyDelivery)].self
        ) { group in
            for index in 0..<32 {
                group.addTask { (index, capability.prepareFailure(.postFailed(code: UInt32(index)))) }
            }
            var deliveries: [(Int, NativeWindowReplyDelivery)] = []
            for await (index, delivery) in group {
                if let delivery { deliveries.append((index, delivery)) }
            }
            return deliveries
        }
        XCTAssertEqual(winners.count, 1)
        XCTAssertTrue(state.failures.withLock { $0.isEmpty })
        XCTAssertTrue(reply.isCompleted)
        guard let winner = winners.first else { return }
        XCTAssertTrue(winner.1.deliver())
        XCTAssertFalse(winner.1.deliver())
        XCTAssertEqual(state.failures.withLock { $0 }, [.postFailed(code: UInt32(winner.0))])
    }
}
