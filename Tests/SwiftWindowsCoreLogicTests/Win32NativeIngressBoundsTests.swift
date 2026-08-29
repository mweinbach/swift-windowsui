import Foundation
import SwiftWindowsCore
import Synchronization
import XCTest

@testable import SwiftWindowsPlatform

private final class IngressBoundsScheduler: Sendable {
    private let operations = Mutex<[Win32NativeEventIngress.Operation]>([])

    func enqueue(_ operation: @escaping Win32NativeEventIngress.Operation) {
        operations.withLock { $0.append(operation) }
    }

    var count: Int { operations.withLock { $0.count } }

    func takeFirst() -> Win32NativeEventIngress.Operation? {
        operations.withLock { values in
            guard !values.isEmpty else { return nil }
            return values.removeFirst()
        }
    }

    @MainActor @discardableResult
    func runNext() -> Bool {
        guard let operation = takeFirst() else { return false }
        operation()
        return true
    }
}

@MainActor
private final class IngressBoundsReceiver {
    var delivered: [UInt64] = []
    var failures: [Win32NativeIngressFailure] = []
    var unrelatedWorkObservations: [[UInt64]] = []
    var duringDelivery: ((Win32NativeWindowEventRecord) -> Void)?

    func receive(_ record: Win32NativeWindowEventRecord) {
        delivered.append(record.observation.surface.geometry.nativeSequence)
        duringDelivery?(record)
    }
}

/// A manually advanced actor scheduler and copied values only. No native
/// thread, window, native posting, input injection or wall-clock wait occurs.
@MainActor
final class Win32NativeIngressBoundsTests: XCTestCase {
    private func record(
        _ sequence: UInt64, key: NativeWindowKey,
        event: Win32NativeWindowEvent = .textInput("x"), displayIdentity: String = ""
    ) -> Win32NativeWindowEventRecord {
        let geometry = NativeWindowGeometry(
            revision: sequence, nativeSequence: sequence, clientSize: IntSize(width: 80, height: 60),
            clientScreenOrigin: .zero, scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: false, isActive: false)
        return Win32NativeWindowEventRecord(
            observation: Win32NativeWindowObservation(
                surface: NativeWindowSurface(
                    key: key, generation: 1, descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize),
                    geometry: geometry),
                systemAppearance: .unavailable, displayIdentity: displayIdentity,
                isInLiveResize: false, isFullscreen: false),
            event: event)
    }

    private func makeIngress(
        _ scheduler: IngressBoundsScheduler, _ receiver: IngressBoundsReceiver,
        limits: Win32NativeIngressLimits = Win32NativeIngressLimits()
    ) -> Win32NativeEventIngress {
        Win32NativeEventIngress(
            limits: limits, schedule: { scheduler.enqueue($0) },
            receiveFailure: { receiver.failures.append($0) }, receive: { receiver.receive($0) })
    }

    private func assertFailure(
        _ result: Result<Void, NativeWindowOwnerFailure>, _ expected: NativeWindowOwnerFailure,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch result {
        case .success: XCTFail("Expected explicit transport failure", file: file, line: line)
        case .failure(let failure): XCTAssertEqual(failure, expected, file: file, line: line)
        }
    }

    private func assertSuccess(
        _ result: Result<Void, NativeWindowOwnerFailure>, file: StaticString = #filePath, line: UInt = #line
    ) {
        if case .failure(let failure) = result {
            XCTFail("Expected native input admission to succeed, got \(failure)", file: file, line: line)
        }
    }

    func testConservativeDefaultsBoundSlotsPayloadAndAutomaticTurn() async {
        let limits = Win32NativeIngressLimits()
        XCTAssertEqual(limits.maximumRecords, 1_024)
        XCTAssertEqual(limits.maximumPayloadBytes, 16 * 1_024 * 1_024)
        XCTAssertEqual(limits.maximumRecordsPerTurn, 32)
    }

    func testRecordOverflowRetainsAcceptedFIFOAndPublishesOneReservedFailure() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(
            scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 2, maximumRecordsPerTurn: 1))
        try ingress.enqueue(record(1, key: key)).get()
        try ingress.enqueue(record(2, key: key)).get()
        let failure = NativeWindowOwnerFailure.capacityExceeded(resource: "nativeInputRecords", limit: 2)
        assertFailure(ingress.enqueue(record(3, key: key)), failure)
        XCTAssertEqual(ingress.snapshot.queuedRecords, 2)
        XCTAssertEqual(ingress.snapshot.lastAcceptedSequence, 2)
        XCTAssertEqual(ingress.snapshot.backingSlots, 2)
        XCTAssertEqual(scheduler.count, 1)
        ingress.fail(failure, windowKey: key)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1])
        XCTAssertTrue(receiver.failures.isEmpty)
        XCTAssertEqual(scheduler.count, 1)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1, 2])
        XCTAssertEqual(
            receiver.failures,
            [Win32NativeIngressFailure(windowKey: key, lastAcceptedSequence: 2, failure: failure)])
        XCTAssertEqual(ingress.snapshot.accountedPayloadBytes, 0)
        XCTAssertEqual(ingress.snapshot.queuedRecords, 0)
        XCTAssertEqual(scheduler.count, 0)
        ingress.fail(.closed, windowKey: key)
        assertFailure(ingress.enqueue(record(4, key: key)), failure)
        assertFailure(ingress.flush(through: 1), failure)
        XCTAssertEqual(receiver.failures.count, 1)
        XCTAssertEqual(ingress.snapshot.lastAcceptedSequence, 2)
        XCTAssertEqual(scheduler.count, 0)
    }

    func testPayloadOverflowDoesNotPublishItsRejectedSequence() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(
            scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 8, maximumPayloadBytes: 7))
        try ingress.enqueue(record(1, key: key, event: .textInput("abc"), displayIdentity: "id")).get()
        XCTAssertEqual(ingress.snapshot.accountedPayloadBytes, 5)
        let failure = NativeWindowOwnerFailure.capacityExceeded(resource: "nativeInputPayloadBytes", limit: 7)
        assertFailure(ingress.enqueue(record(2, key: key, event: .textInput("xyz"))), failure)
        XCTAssertEqual(ingress.snapshot.lastAcceptedSequence, 1)
        XCTAssertEqual(ingress.snapshot.accountedPayloadBytes, 5)
        ingress.fail(failure, windowKey: key)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1])
        XCTAssertEqual(receiver.failures.first?.lastAcceptedSequence, 1)
    }

    func testOversizedFirstRecordHasAnIndependentTerminalWake() async {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(
            scheduler, receiver, limits: Win32NativeIngressLimits(maximumPayloadBytes: 3))
        let failure = NativeWindowOwnerFailure.capacityExceeded(resource: "nativeInputPayloadBytes", limit: 3)
        assertFailure(ingress.enqueue(record(1, key: key, event: .textInput("four"))), failure)
        XCTAssertEqual(ingress.snapshot.queuedRecords, 0)
        XCTAssertEqual(ingress.snapshot.lastAcceptedSequence, 0)
        XCTAssertEqual(scheduler.count, 0, "Native code first observes refusal and revokes its surface")
        ingress.fail(failure, windowKey: key)
        XCTAssertEqual(scheduler.count, 1)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertTrue(receiver.delivered.isEmpty)
        XCTAssertEqual(receiver.failures.first?.failure, failure)
        XCTAssertEqual(receiver.failures.first?.lastAcceptedSequence, 0)
    }

    func testAcceptedTailCanDrainBeforeNativePublishesTheReservedFailure() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 1))
        try ingress.enqueue(record(1, key: key)).get()
        let failure = NativeWindowOwnerFailure.capacityExceeded(resource: "nativeInputRecords", limit: 1)
        assertFailure(ingress.enqueue(record(2, key: key)), failure)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1])
        XCTAssertTrue(receiver.failures.isEmpty)
        XCTAssertEqual(scheduler.count, 0, "An unpublished terminal slot cannot spin automatic turns")
        ingress.fail(failure, windowKey: key)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.failures.count, 1)
        XCTAssertEqual(scheduler.count, 0)
    }

    func testUnicodeIMEAndTouchPayloadsUseTheirCopiedValueSizes() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(scheduler, receiver)
        let text = "A😀"
        try ingress.enqueue(record(1, key: key, event: .imeComposition(IMECompositionEvent(phase: .updated(text)))))
            .get()
        try ingress.enqueue(record(2, key: key, event: .touch(.moved, [.zero, Point(x: 1, y: 2)]))).get()
        XCTAssertEqual(ingress.snapshot.accountedPayloadBytes, text.utf8.count + 2 * MemoryLayout<Point>.stride)
        try ingress.flush(through: 2).get()
        XCTAssertEqual(ingress.snapshot.accountedPayloadBytes, 0)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(scheduler.count, 0)
    }

    func testDroppedURLsAccountArrayEntriesAndActualURLSpellings() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(scheduler, receiver)
        let urls = [URL(fileURLWithPath: "C:/owned/a b.txt"), URL(fileURLWithPath: "C:/owned/é.txt")]
        try ingress.enqueue(
            record(1, key: key, event: .filesDropped(FileDropPayload(fileURLs: urls, clientPoint: .zero)))
        )
        .get()
        XCTAssertEqual(
            ingress.snapshot.accountedPayloadBytes,
            urls.count * MemoryLayout<URL>.stride + urls.reduce(0) { $0 + $1.absoluteString.utf8.count })
        try ingress.flush().get()
        XCTAssertEqual(ingress.snapshot.accountedPayloadBytes, 0)
    }

    func testFixedRingReusesSlotsAndReleasedPayloadBudget() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(
            scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 3, maximumPayloadBytes: 3))
        for sequence in UInt64(1)...UInt64(30) {
            try ingress.enqueue(record(sequence, key: key)).get()
            try ingress.flush(through: sequence).get()
            XCTAssertEqual(ingress.snapshot.backingSlots, 3)
            XCTAssertEqual(ingress.snapshot.accountedPayloadBytes, 0)
            XCTAssertEqual(scheduler.count, 1)
        }
        XCTAssertEqual(receiver.delivered, Array(UInt64(1)...UInt64(30)))
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(scheduler.count, 0)
    }

    func testManualFlushThenRefillKeepsTheOriginalAutomaticReservation() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(scheduler, receiver)
        try ingress.enqueue(record(1, key: key)).get()
        try ingress.flush(through: 1).get()
        XCTAssertTrue(ingress.snapshot.hasScheduledTurn)
        try ingress.enqueue(record(2, key: key)).get()
        XCTAssertEqual(scheduler.count, 1)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1, 2])
        XCTAssertFalse(ingress.snapshot.hasScheduledTurn)
        try ingress.enqueue(record(3, key: key)).get()
        XCTAssertEqual(scheduler.count, 1)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1, 2, 3])
    }

    func testAutomaticTurnStopsAtItsBudgetWithAReplenishingProducer() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(
            scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 8, maximumRecordsPerTurn: 2))
        for sequence in UInt64(1)...UInt64(3) { try ingress.enqueue(record(sequence, key: key)).get() }
        receiver.duringDelivery = { [self] value in
            let sequence = value.observation.surface.geometry.nativeSequence
            guard sequence <= 6 else { return }
            assertSuccess(ingress.enqueue(record(sequence + 3, key: key)))
        }
        defer { receiver.duringDelivery = nil }
        scheduler.enqueue { receiver.unrelatedWorkObservations.append(receiver.delivered) }
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1, 2])
        XCTAssertEqual(scheduler.count, 2)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.unrelatedWorkObservations, [[1, 2]])
        XCTAssertEqual(receiver.delivered, [1, 2])
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1, 2, 3, 4])
        for _ in 0..<3 { XCTAssertTrue(scheduler.runNext()) }
        XCTAssertEqual(receiver.delivered, Array(UInt64(1)...UInt64(9)))
        XCTAssertEqual(scheduler.count, 0)
    }

    func testDefaultSynchronousFlushCapturesItsTailInsteadOfChasingNewInput() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 4))
        for sequence in UInt64(1)...UInt64(3) { try ingress.enqueue(record(sequence, key: key)).get() }
        receiver.duringDelivery = { [self] value in
            let sequence = value.observation.surface.geometry.nativeSequence
            guard sequence <= 3 else { return }
            assertSuccess(ingress.enqueue(record(sequence + 3, key: key)))
        }
        defer { receiver.duringDelivery = nil }
        try ingress.flush().get()
        XCTAssertEqual(receiver.delivered, [1, 2, 3])
        XCTAssertEqual(ingress.snapshot.queuedRecords, 3)
        XCTAssertEqual(ingress.snapshot.lastAcceptedSequence, 6)
        XCTAssertEqual(scheduler.count, 1)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1, 2, 3, 4, 5, 6])
    }

    func testCoalescedTailFitsWithoutAdmittingTheNextEssentialInput() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 1))
        try ingress.enqueue(record(1, key: key, event: .animationFrame(1))).get()
        try ingress.enqueue(record(2, key: key, event: .animationFrame(2))).get()
        XCTAssertEqual(ingress.snapshot.queuedRecords, 1)
        XCTAssertEqual(ingress.snapshot.lastAcceptedSequence, 2)
        let failure = NativeWindowOwnerFailure.capacityExceeded(resource: "nativeInputRecords", limit: 1)
        assertFailure(ingress.enqueue(record(3, key: key)), failure)
        ingress.fail(failure, windowKey: key)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1])
        XCTAssertEqual(receiver.failures.first?.lastAcceptedSequence, 2)
        assertFailure(ingress.flush(through: 2), failure)
    }

    func testTerminalFailureRejectsEvenAnAlreadyCommittedQueryBoundary() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 1))
        try ingress.enqueue(record(1, key: key)).get()
        try ingress.flush(through: 1).get()
        try ingress.enqueue(record(2, key: key)).get()
        let failure = NativeWindowOwnerFailure.capacityExceeded(resource: "nativeInputRecords", limit: 1)
        assertFailure(ingress.enqueue(record(3, key: key)), failure)
        assertFailure(ingress.flush(through: 1), failure)
        assertFailure(ingress.flush(through: 0), failure)
        XCTAssertEqual(receiver.delivered, [1])
    }

    func testObsoleteAutomaticTokenCannotDrainOrRescheduleANewerReservation() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(scheduler, receiver)
        try ingress.enqueue(record(1, key: key)).get()
        let old = try XCTUnwrap(scheduler.takeFirst())
        old()
        try ingress.enqueue(record(2, key: key)).get()
        old()
        XCTAssertEqual(receiver.delivered, [1])
        XCTAssertEqual(scheduler.count, 1)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1, 2])
        XCTAssertEqual(scheduler.count, 0)
    }

    func testRefillFromLastCallbackGetsExactlyOneFollowingTurn() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(
            scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 2, maximumRecordsPerTurn: 1))
        receiver.duringDelivery = { [self] value in
            XCTAssertEqual(ingress.snapshot.queuedRecords, 0)
            if value.observation.surface.geometry.nativeSequence == 1 {
                assertSuccess(ingress.enqueue(record(2, key: key)))
                XCTAssertEqual(scheduler.count, 0, "The current automatic turn still owns its reservation")
            }
        }
        defer { receiver.duringDelivery = nil }
        try ingress.enqueue(record(1, key: key)).get()
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1])
        XCTAssertEqual(scheduler.count, 1)
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1, 2])
        XCTAssertEqual(scheduler.count, 0)
    }

    func testSaturationInsideCallbackRejectsReentrantProjectionAndKeepsFIFO() async throws {
        let key = NativeWindowKey()
        let scheduler = IngressBoundsScheduler()
        let receiver = IngressBoundsReceiver()
        let ingress = makeIngress(
            scheduler, receiver, limits: Win32NativeIngressLimits(maximumRecords: 1, maximumRecordsPerTurn: 1))
        let failure = NativeWindowOwnerFailure.capacityExceeded(resource: "nativeInputRecords", limit: 1)
        receiver.duringDelivery = { [self] value in
            guard value.observation.surface.geometry.nativeSequence == 1 else { return }
            assertSuccess(ingress.enqueue(record(2, key: key)))
            assertFailure(ingress.enqueue(record(3, key: key)), failure)
            assertFailure(ingress.flush(through: 1), failure)
            ingress.fail(failure, windowKey: key)
            XCTAssertEqual(receiver.delivered, [1])
            XCTAssertTrue(receiver.failures.isEmpty)
        }
        defer { receiver.duringDelivery = nil }
        try ingress.enqueue(record(1, key: key)).get()
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1])
        XCTAssertTrue(scheduler.runNext())
        XCTAssertEqual(receiver.delivered, [1, 2])
        XCTAssertEqual(receiver.failures.first?.lastAcceptedSequence, 2)
        XCTAssertEqual(scheduler.count, 0)
    }
}
