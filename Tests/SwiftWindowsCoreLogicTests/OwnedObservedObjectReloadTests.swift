import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private struct OwnedObservedReloadContent: View {
    @ObservedObject var model: TestObservableObject

    var body: some View {
        Text("Value \(model.value)")
            .accessibilityLabel("Value \(model.value)")
            .accessibilityIdentifier("observed-reload-value")
    }
}

/// Selects the real owned presentation path without starting a pump or creating
/// an HWND. These tests do not claim live-owner or native command-count evidence.
@MainActor
private final class OwnedObservedReloadFixture {
    let model = TestObservableObject()
    let frame = FakeRenderBackend()
    let batch = FakeBatchRenderBackend()
    let host: WinSwiftUIWindowHost
    let initialSceneRebuildCount: UInt64
    var coalesced: [Bool] = []
    var decisions: [Bool] = []
    var adoptedValues: [String] = []
    var transactions: [Transaction?] = []
    var animationDurations: [Double?] = []
    var timerCalls = 0
    var didReload: (() -> Void)?
    var didConsumeBatch: (() -> Void)?

    var window: Win32Window { host.platformWindow }

    init(nativePresentation: Bool = true) throws {
        let factory: (any NativePresentationBackendFactory)?
        if nativePresentation {
            factory = try XCTUnwrap(SoftwareWindowRenderBackendFactory().makeNativePresentationFactory())
        } else {
            factory = nil
        }
        host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Observed reload delivery", size: IntSize(width: 320, height: 240), clearColor: .black,
                content: [AnyView(OwnedObservedReloadContent(model: model))]),
            renderer: frame, batchRenderer: batch, nativePresentationFactory: factory,
            startupProbeConfiguration: nil)
        initialSceneRebuildCount = host.hostedRuntime.sceneRebuildCount
        host.onObservedObjectReloadScheduled = { [weak self] _, coalesced in self?.coalesced.append(coalesced) }
        host.onObservedObjectReloadTaskCompleted = { [weak self] didReload in
            guard let self else { return }
            decisions.append(didReload)
            didConsumeBatch?()
        }
        host.onReloadContentCompleted = { [weak self] in
            guard let self else { return }
            adoptedValues.append(retainedValue ?? "missing retained value")
            transactions.append(currentTransaction)
            animationDurations.append(currentAnimationTransaction?.duration)
            didReload?()
        }
        host.onTimerStateChanged = { [weak self] _ in self?.timerCalls += 1 }
        resetCounters()
    }

    var retainedValue: String? {
        var pending = [host.hostedRuntime.root]
        while let node = pending.popLast() {
            if node.accessibilityIdentifier == "observed-reload-value" { return node.accessibilityLabel }
            pending.append(contentsOf: node.children)
        }
        return nil
    }

    func resetCounters() {
        host.resetObservabilityCounters()
        coalesced.removeAll()
        decisions.removeAll()
        adoptedValues.removeAll()
        transactions.removeAll()
        animationDurations.removeAll()
        timerCalls = 0
    }

    func close() {
        didReload = nil
        didConsumeBatch = nil
        host.onObservedObjectReloadScheduled = nil
        host.onObservedObjectReloadTaskCompleted = nil
        host.onReloadContentCompleted = nil
        host.onTimerStateChanged = nil
        host.windowWillClose(window)
    }
}

@MainActor
final class OwnedObservedObjectReloadTests: XCTestCase {
    func testTaskPolicyDistinguishesOwnedPresentationFromLegacyHandlePresence() async {
        XCTAssertEqual(
            WinSwiftUIWindowHost.observedObjectReloadTaskRequestsFrame(
                usesNativePresentation: true, hasNativeHandle: true), false)
        XCTAssertEqual(
            WinSwiftUIWindowHost.observedObjectReloadTaskRequestsFrame(
                usesNativePresentation: true, hasNativeHandle: false), false)
        XCTAssertNil(
            WinSwiftUIWindowHost.observedObjectReloadTaskRequestsFrame(
                usesNativePresentation: false, hasNativeHandle: true))
        XCTAssertEqual(
            WinSwiftUIWindowHost.observedObjectReloadTaskRequestsFrame(
                usesNativePresentation: false, hasNativeHandle: false), true)
    }

    func testOwnedReloadCoalescesWhenFramesAreUnavailableWithoutRequestingAnotherFrame() async throws {
        let fixture = try OwnedObservedReloadFixture()
        defer { fixture.close() }
        XCTAssertTrue(fixture.host.usesNativePresentation)
        XCTAssertFalse(fixture.window.usesNativeOwner)
        XCTAssertNil(fixture.window.nativeHandle)
        XCTAssertEqual(fixture.retainedValue, "Value 0")
        let consumed = expectation(description: "owned actor consumed the observed batch")
        fixture.didConsumeBatch = { consumed.fulfill() }
        let invalidationsBefore = fixture.window.invalidateRequestCount

        fixture.model.value = 1
        fixture.model.secondaryValue = "same turn"
        fixture.model.value = 2
        XCTAssertEqual(fixture.coalesced, [false, true, true])
        XCTAssertEqual(fixture.host.scheduledReloadCount, 1)
        XCTAssertEqual(fixture.window.invalidateRequestCount, invalidationsBefore + 1)
        XCTAssertEqual(fixture.timerCalls, 1)
        let invalidationsAfterWake = fixture.window.invalidateRequestCount
        let timerCallsAfterWake = fixture.timerCalls

        // The ordinary display entry cannot flush through an unavailable native
        // presenter. No await has yet allowed the cooperative Task to execute.
        fixture.host.windowNeedsDisplay(fixture.window)
        XCTAssertEqual(fixture.host.executedReloadCount, 0)
        XCTAssertEqual(fixture.host.completedObservedObjectReloadTaskCount, 0)
        XCTAssertEqual(fixture.retainedValue, "Value 0")

        await requireCompletion(consumed)
        XCTAssertEqual(fixture.decisions, [true])
        XCTAssertEqual(fixture.adoptedValues, ["Value 2"])
        XCTAssertEqual(fixture.host.executedReloadCount, 1)
        XCTAssertEqual(fixture.host.completedObservedObjectReloadTaskCount, 1)
        XCTAssertEqual(fixture.window.invalidateRequestCount, invalidationsAfterWake)
        XCTAssertEqual(fixture.timerCalls, timerCallsAfterWake)
        assertNoBackendWork(fixture)

        fixture.host.windowNeedsDisplay(fixture.window)
        XCTAssertEqual(fixture.host.executedReloadCount, 1)
        XCTAssertEqual(fixture.host.completedObservedObjectReloadTaskCount, 1)
        assertNoBackendWork(fixture)
    }

    func testOwnedReloadUsesLatestRelevantTransactionDespiteLaterUnrelatedMutation() async throws {
        let fixture = try OwnedObservedReloadFixture()
        defer { fixture.close() }
        await establishDependencies(fixture)
        let unrelated = TestObservableObject()
        fixture.host.observe(unrelated)
        let consumed = expectation(description: "latest relevant transaction consumed")
        fixture.didConsumeBatch = { consumed.fulfill() }

        withAnimation(.linear(duration: 0.2)) { fixture.model.value = 2 }
        withAnimation(.linear(duration: 0.6)) { fixture.model.value = 3 }
        withTransaction(Transaction(animation: nil)) { unrelated.value = 1 }
        XCTAssertNil(currentAnimationTransaction)
        XCTAssertNil(currentTransaction)

        await requireCompletion(consumed)
        XCTAssertEqual(fixture.coalesced, [false, true, true])
        XCTAssertEqual(fixture.decisions, [true])
        XCTAssertEqual(fixture.adoptedValues, ["Value 3"])
        XCTAssertEqual(fixture.animationDurations, [0.6])
        XCTAssertEqual(fixture.host.executedReloadCount, 1)
        XCTAssertNil(currentAnimationTransaction)
        XCTAssertNil(currentTransaction)
        assertNoBackendWork(fixture)
    }

    func testOwnedReloadPreservesExplicitNilAnimationAndFullTransaction() async throws {
        let fixture = try OwnedObservedReloadFixture()
        defer { fixture.close() }
        let consumed = expectation(description: "explicit nil transaction consumed")
        fixture.didConsumeBatch = { consumed.fulfill() }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        transaction.isContinuous = true
        transaction.tracksVelocity = true
        transaction.scrollTargetAnchor = .bottomTrailing

        withTransaction(transaction) { fixture.model.value = 1 }
        XCTAssertNil(currentTransaction)
        await requireCompletion(consumed)

        let captured = try XCTUnwrap(fixture.transactions.first ?? nil)
        XCTAssertNil(captured.animation)
        XCTAssertTrue(captured.disablesAnimations)
        XCTAssertTrue(captured.isContinuous)
        XCTAssertTrue(captured.tracksVelocity)
        XCTAssertEqual(captured.scrollTargetAnchor?.x, 1)
        XCTAssertEqual(captured.scrollTargetAnchor?.y, 1)
        XCTAssertEqual(fixture.animationDurations, [nil])
        XCTAssertEqual(fixture.adoptedValues, ["Value 1"])
        XCTAssertEqual(fixture.decisions, [true])
        XCTAssertNil(currentAnimationTransaction)
        XCTAssertNil(currentTransaction)
    }

    func testOwnedReloadKeepsReentrantMutationInItsOwnAcceptedBatch() async throws {
        let fixture = try OwnedObservedReloadFixture()
        defer { fixture.close() }
        let consumed = expectation(description: "both observed batches consumed")
        consumed.expectedFulfillmentCount = 2
        fixture.didConsumeBatch = { consumed.fulfill() }
        fixture.didReload = {
            if fixture.adoptedValues.count == 1 {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { fixture.model.value = 2 }
            }
        }

        withAnimation(.linear(duration: 0.25)) { fixture.model.value = 1 }
        await requireCompletion(consumed)

        XCTAssertEqual(fixture.coalesced, [false, false])
        XCTAssertEqual(fixture.adoptedValues, ["Value 1", "Value 2"])
        XCTAssertEqual(fixture.decisions, [true, true])
        XCTAssertEqual(fixture.animationDurations, [0.25, nil])
        XCTAssertEqual((fixture.transactions.last ?? nil)?.disablesAnimations, true)
        XCTAssertEqual(fixture.host.scheduledReloadCount, 2)
        XCTAssertEqual(fixture.host.executedReloadCount, 2)
        XCTAssertEqual(fixture.host.completedObservedObjectReloadTaskCount, 2)
        XCTAssertEqual(fixture.timerCalls, 2)
        XCTAssertNil(currentAnimationTransaction)
        XCTAssertNil(currentTransaction)
        assertNoBackendWork(fixture)
    }

    func testOwnedReloadSkipsAnUnrelatedObservedObject() async throws {
        let fixture = try OwnedObservedReloadFixture()
        defer { fixture.close() }
        await establishDependencies(fixture)
        let unrelated = TestObservableObject()
        fixture.host.observe(unrelated)
        let consumed = expectation(description: "unrelated batch filtered")
        fixture.didConsumeBatch = { consumed.fulfill() }

        unrelated.value = 1
        let invalidationsAfterWake = fixture.window.invalidateRequestCount
        await requireCompletion(consumed)

        XCTAssertEqual(fixture.decisions, [false])
        XCTAssertTrue(fixture.adoptedValues.isEmpty)
        XCTAssertEqual(fixture.retainedValue, "Value 1")
        XCTAssertEqual(fixture.host.executedReloadCount, 0)
        XCTAssertEqual(fixture.host.skippedObservedObjectReloadCount, 1)
        XCTAssertEqual(fixture.host.completedObservedObjectReloadTaskCount, 1)
        XCTAssertEqual(fixture.window.invalidateRequestCount, invalidationsAfterWake)
        // The unchanged irrelevant-batch branch intentionally resynchronizes
        // the timer. It is not a second presentation request.
        XCTAssertEqual(fixture.timerCalls, 2)
        assertNoBackendWork(fixture)
    }

    func testOwnedPendingReloadIsRevokedBySameTurnTeardown() async throws {
        let fixture = try OwnedObservedReloadFixture()
        defer { fixture.close() }
        var closedNotifications = 0
        fixture.host.onWindowClosed = { _ in closedNotifications += 1 }
        fixture.model.value = 1
        XCTAssertEqual(fixture.host.scheduledReloadCount, 1)

        // Synchronous teardown wins before the queued Task can execute. The
        // unstarted native path reports no native destruction acknowledgement.
        fixture.host.windowWillClose(fixture.window)
        XCTAssertTrue(fixture.host.isClosed)
        let invalidationsAfterClose = fixture.window.invalidateRequestCount
        let timerCallsAfterClose = fixture.timerCalls
        fixture.model.value = 2
        fixture.host.windowNeedsDisplay(fixture.window)
        let destroyed = await fixture.host.waitForNativeTeardown()
        await Task.yield()

        XCTAssertFalse(destroyed)
        XCTAssertEqual(closedNotifications, 0)
        XCTAssertTrue(fixture.decisions.isEmpty)
        XCTAssertTrue(fixture.adoptedValues.isEmpty)
        XCTAssertEqual(fixture.host.scheduledReloadCount, 1)
        XCTAssertEqual(fixture.host.executedReloadCount, 0)
        XCTAssertEqual(fixture.host.completedObservedObjectReloadTaskCount, 0)
        XCTAssertEqual(fixture.window.invalidateRequestCount, invalidationsAfterClose)
        XCTAssertEqual(fixture.timerCalls, timerCallsAfterClose)
        assertNoBackendWork(fixture)
    }

    func testLegacyHeadlessReloadStillRequestsItsFollowUpFrame() async throws {
        let fixture = try OwnedObservedReloadFixture(nativePresentation: false)
        defer { fixture.close() }
        XCTAssertFalse(fixture.host.usesNativePresentation)
        XCTAssertNil(fixture.window.nativeHandle)
        let consumed = expectation(description: "legacy headless batch consumed")
        fixture.didConsumeBatch = { consumed.fulfill() }

        fixture.model.value = 1
        let invalidationsAfterWake = fixture.window.invalidateRequestCount
        let timerCallsAfterWake = fixture.timerCalls
        await requireCompletion(consumed)

        XCTAssertEqual(fixture.decisions, [true])
        XCTAssertEqual(fixture.adoptedValues, ["Value 1"])
        XCTAssertEqual(fixture.host.executedReloadCount, 1)
        XCTAssertEqual(fixture.window.invalidateRequestCount, invalidationsAfterWake + 1)
        XCTAssertEqual(fixture.timerCalls, timerCallsAfterWake + 1)
        assertNoBackendWork(fixture)
    }

    private func establishDependencies(_ fixture: OwnedObservedReloadFixture) async {
        let consumed = expectation(description: "real retained rebuild established dependencies")
        fixture.didConsumeBatch = { consumed.fulfill() }
        fixture.model.value = 1
        await requireCompletion(consumed)
        XCTAssertEqual(fixture.decisions, [true])
        XCTAssertEqual(fixture.retainedValue, "Value 1")
        fixture.didConsumeBatch = nil
        fixture.resetCounters()
    }

    private func requireCompletion(_ expectation: XCTestExpectation) async {
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .completed)
    }

    private func assertNoBackendWork(
        _ fixture: OwnedObservedReloadFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            fixture.host.hostedRuntime.sceneRebuildCount, fixture.initialSceneRebuildCount, file: file, line: line)
        XCTAssertTrue(fixture.frame.attachedSurfaces.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.frame.resizedSizes.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.frame.renderedFrames.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.batch.attachedSurfaces.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.batch.resizedSizes.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.batch.boundScenes.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.batch.renderedScenes.isEmpty, file: file, line: line)
    }
}
