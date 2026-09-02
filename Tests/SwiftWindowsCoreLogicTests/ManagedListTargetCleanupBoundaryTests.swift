import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Real managed List callbacks, with the ordinary four-round/128-element budget.
/// Late cancellation cannot undo the row table that was already accepted.
@MainActor
final class ManagedListTargetCleanupBoundaryTests: XCTestCase {
    func testInitialOnChangeCancellationRefusesCompletionAndFinishesOriginalBuild() async throws {
        try exerciseLateCancellation(at: .initialAction)
    }

    func testOnChangeActionPayloadReleaseRefusesCompletionAndFinishesOriginalBuild() async throws {
        try exerciseLateCancellation(at: .actionPayloadRelease)
    }

    func testHostCloseInRequiredBodyDisposesProposalAndFinishesOriginalBuild() async throws {
        let fixture = try TargetCleanupFixture()
        defer { fixture.close() }
        let probe = fixture.probe
        let originalResolutions = fixture.runtime.lazyListResolveCount
        probe.onBody = { [weak fixture] in
            guard let fixture else { return XCTFail("The original fixture must remain alive") }
            XCTAssertTrue(fixture.runtime.hasActiveRetainedBuild)
            XCTAssertNotNil(probe.originalEpoch)
            XCTAssertNotNil(probe.bodyPayload)
            XCTAssertEqual(probe.factories, [899])
            XCTAssertNil(fixture.adapter.mountedNodes(for: fixture.item.token))
            fixture.host.close()
            XCTAssertTrue(fixture.host.isClosed)
        }

        let result = fixture.resolveOriginalTarget()

        assertDefaultBudget(fixture.runtime)
        guard case .obsolete = result else {
            return XCTFail("A closed host cannot complete its original ordinary target")
        }
        XCTAssertEqual(probe.bodyCalls, 1)
        XCTAssertEqual(probe.factories, [899])
        XCTAssertTrue(probe.initialActions.isEmpty)
        XCTAssertEqual(probe.payloadCreations, 1)
        XCTAssertEqual(probe.payloadReleases, 1)
        XCTAssertNil(probe.bodyPayload)
        XCTAssertTrue(fixture.host.isClosed)
        XCTAssertTrue(fixture.host.coordinator.registry.isClosed)
        XCTAssertEqual(fixture.host.coordinator.registry.liveOwnerCount, 0)
        XCTAssertEqual(fixture.host.coordinator.registry.retiringOwnerCount, 0)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.hasPendingNativeWork)
        XCTAssertNil(probe.originalEpoch)
        XCTAssertEqual(fixture.runtime.lazyListResolveCount, originalResolutions)
        XCTAssertFalse(fixture.runtime.isLazyListAccessibilityItemCurrent(fixture.item))
        XCTAssertFalse(fixture.receipt.permitsBindingWrite)
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertNil(fixture.adapter.mountedNodes(for: fixture.item.token))
        XCTAssertNil(fixture.host.find(targetCleanupIdentifier(899)))
        XCTAssertNil(fixture.host.find(targetCleanupIdentifier(898)))
        XCTAssertNil(fixture.host.find(targetCleanupIdentifier(900)))
        XCTAssertEqual(probe.selection, 899)
    }

    private func exerciseLateCancellation(at point: TargetCleanupCancellationPoint) throws {
        let fixture = try TargetCleanupFixture()
        defer { fixture.close() }
        let probe = fixture.probe
        let cancelOriginal = { [weak fixture] in
            guard let fixture else { return XCTFail("The original fixture must remain alive") }
            probe.cancellations += 1
            XCTAssertTrue(fixture.runtime.hasActiveRetainedBuild)
            XCTAssertEqual(probe.originalEpoch?.didCommit, true)
            XCTAssertEqual(probe.factories, [899, 898])
            XCTAssertEqual(probe.initialActions, [899])
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(fixture.item))
            let acceptedRoots = fixture.adapter.mountedNodes(for: fixture.item.token)
            // One authored row contributes its presentation gap and actual row.
            XCTAssertEqual(acceptedRoots?.count, 2)
            XCTAssertTrue(acceptedRoots?.first?.parent === fixture.content)
            XCTAssertEqual(acceptedRoots?.first?.isSeparatorRule, true)
            XCTAssertNotNil(acceptedRoots?.first?.retainedLazyListGap)
            XCTAssertNil(acceptedRoots?.first?.listNavigationOwner)
            if let row = acceptedRoots?.last {
                XCTAssertFalse(row.isSeparatorRule)
                XCTAssertNil(row.retainedLazyListGap)
                XCTAssertNotNil(row.listNavigationOwner)
                XCTAssertTrue(row.parent === fixture.content)
                XCTAssertTrue(row.retainedLazyListRuntime === fixture.runtime)
                XCTAssertEqual(DeferredListRowNavigation.attached(to: row)?.ordinal, 899)
                XCTAssertEqual(DeferredListRowNavigation.attached(to: row)?.leaf, 0)
            }
            XCTAssertNotNil(fixture.host.find(targetCleanupIdentifier(899)))
            if point == .initialAction {
                XCTAssertEqual(probe.payloadReleases, 0)
                XCTAssertNotNil(probe.bodyPayload)
            } else {
                XCTAssertEqual(probe.payloadReleases, 1)
            }
            let originalResolutions = fixture.runtime.lazyListResolveCount
            fixture.runtime.releaseLazyListTarget(fixture.item)

            // This read-only observer queues behind the completion that is
            // already draining. It does not query layout or request another
            // target. Later layout passes may legitimately build the viewport.
            fixture.runtime.afterRetainedCallbacks { [weak fixture] in
                guard let fixture else { return XCTFail("The original fixture must remain alive") }
                probe.completedBuildObservations += 1
                XCTAssertEqual(fixture.runtime.lazyListResolveCount, originalResolutions)
                XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
                XCTAssertFalse(fixture.adapter.hasCurrentLogicalSnapshot)
                XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
                XCTAssertEqual(probe.payloadReleases, 1)
                XCTAssertNil(probe.bodyPayload)
                // Cancellation does not retire the source during this cleanup.
                XCTAssertTrue(fixture.receipt.permitsBindingWrite)
                XCTAssertTrue(fixture.source.listNavigationOwner === fixture.sourceOwner)
            }
        }
        switch point {
        case .initialAction: probe.onInitialAction = cancelOriginal
        case .actionPayloadRelease: probe.onPayloadRelease = cancelOriginal
        }

        let result = fixture.resolveOriginalTarget()

        assertDefaultBudget(fixture.runtime)
        switch result {
        case .pending, .obsolete: break
        case .ready, .empty, .unsupported:
            XCTFail("The cancelled original demand must not complete readiness")
        }
        XCTAssertEqual(probe.cancellations, 1)
        XCTAssertEqual(probe.completedBuildObservations, 1)
        XCTAssertEqual(probe.initialActions, [899])
        XCTAssertEqual(probe.payloadCreations, 1)
        XCTAssertEqual(probe.payloadReleases, 1)
        XCTAssertNil(probe.bodyPayload)
        XCTAssertFalse(fixture.host.isClosed)
        XCTAssertFalse(fixture.host.coordinator.registry.isClosed)
        XCTAssertEqual(fixture.host.coordinator.registry.retiringOwnerCount, 0)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.hasPendingNativeWork)
        // The later viewport rebuild replaces declarations on the same source.
        // Its original receipt can continue physically, but cannot write again.
        XCTAssertFalse(fixture.receipt.permitsBindingWrite)
        XCTAssertNotNil(fixture.source.listNavigationOwner)
        XCTAssertFalse(fixture.source.listNavigationOwner === fixture.sourceOwner)
        XCTAssertTrue(fixture.receipt.permitsContinuation)
        XCTAssertTrue(fixture.source.parent === fixture.content)
        XCTAssertTrue(fixture.source.retainedLazyListRuntime === fixture.runtime)
        XCTAssertTrue(fixture.content.children.contains { $0 === fixture.source })
        XCTAssertEqual(probe.selection, 899)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.originalOffset)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.originalFocus)
        XCTAssertFalse(probe.factories.contains(900))
        XCTAssertNil(fixture.host.find(targetCleanupIdentifier(900)))
        // No assertion removes an already accepted row or claims that this
        // completion callback occurred before physical adoption.
    }

    private func assertDefaultBudget(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(runtime.lastLazyListConsumedRounds, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
        XCTAssertGreaterThanOrEqual(runtime.lastLazyListConsumedElements, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128, file: file, line: line)
    }
}

private enum TargetCleanupCancellationPoint { case initialAction, actionPayloadRelease }

@MainActor
private final class TargetCleanupFixture {
    let probe: TargetCleanupProbe
    let host: MountedLazyListTestHost
    let content: ViewNode
    let scroll: ViewNode
    let source: ViewNode
    let sourceOwner: RetainedListNavigationOwner
    let sourceKeyDown: (KeyboardEvent) -> Void
    let receipt: RetainedListNavigationReceipt
    let adapter: RetainedLazyListRuntimeAdapter
    let item: RetainedLazyListAccessibilityItem
    let originalOffset: Double
    let originalFocus: ViewNode?
    var runtime: RetainedViewRuntime { host.runtime }

    init() throws {
        let probe = TargetCleanupProbe()
        self.probe = probe
        let binding = Binding<Int?>(get: { probe.selection }, set: { probe.selection = $0 })
        let host = MountedLazyListTestHost(size: Size(width: 260, height: 200)) {
            List(0..<1_000, id: \.self, selection: binding) { index in
                let _ = probe.recordFactory(index)
                TargetCleanupRow(index: index, probe: probe)
            }
            .frame(width: 260, height: 200)
        }
        self.host = host
        do {
            var settled = false
            for _ in 0..<16 {
                _ = host.runtime.renderScene(at: 1)
                if !host.runtime.isDirty {
                    settled = true
                    break
                }
            }
            _ = try XCTUnwrap(settled ? true : nil, "Expected the unchanged initial viewport to settle")
            let source = try host.rowRoot(targetCleanupIdentifier(0))
            self.source = source
            sourceKeyDown = try XCTUnwrap(source.onKeyDown)
            let content = try host.list()
            self.content = content
            let scroll = try host.scrollContainer()
            self.scroll = scroll
            adapter = try XCTUnwrap(content.retainedLazyListAdapter)
            let sourceOwner = try XCTUnwrap(source.listNavigationOwner)
            self.sourceOwner = sourceOwner
            let scope = try XCTUnwrap(scroll.listNavigationOwner)
            receipt = try XCTUnwrap(scope.prepareAction(from: sourceOwner))
            let table = try XCTUnwrap(DeferredListScrollSource.attached(to: content))
            let row = try XCTUnwrap(table.row(at: 899))
            item = try XCTUnwrap(host.runtime.lazyListTarget(in: content, key: row.providerKey))
            originalOffset = scroll.scrollOffset
            originalFocus = host.runtime.focusedNode
            probe.selection = 899
            XCTAssertEqual(adapter.logicalRecordCount, 1_000)
            XCTAssertNil(item.knownLeafCount)
            XCTAssertFalse(adapter.hasUnresolvedWork)
            XCTAssertTrue(receipt.permitsBindingWrite)
            XCTAssertNil(host.find(targetCleanupIdentifier(898)))
            XCTAssertNil(host.find(targetCleanupIdentifier(899)))
            XCTAssertNil(host.find(targetCleanupIdentifier(900)))
        } catch {
            host.close()
            throw error
        }
    }

    func resolveOriginalTarget() -> RetainedLazyListTargetResolution {
        probe.isRecording = true
        defer { probe.isRecording = false }
        return runtime.withLazyListResolutionBudget { runtime.resolveLazyListTarget(item) }
    }

    func close() {
        probe.onBody = nil
        probe.onInitialAction = nil
        probe.onPayloadRelease = nil
        runtime.releaseLazyListTarget(item)
        receipt.cancelPreparedNavigation()
        host.close()
        withExtendedLifetime(sourceKeyDown) {}
    }
}

@MainActor
private final class TargetCleanupProbe {
    var selection: Int? = 0
    var isRecording = false
    var factories: [Int] = []
    var initialActions: [Int] = []
    var bodyCalls = 0
    var payloadCreations = 0
    var payloadReleases = 0
    var cancellations = 0
    var completedBuildObservations = 0
    weak var originalEpoch: StateMountEpoch?
    weak var bodyPayload: TargetCleanupPayload?
    var onBody: (() -> Void)?
    var onInitialAction: (() -> Void)?
    var onPayloadRelease: (() -> Void)?

    func recordFactory(_ index: Int) {
        if isRecording { factories.append(index) }
    }

    func makePayload(_ index: Int) -> TargetCleanupPayload? {
        guard isRecording, index == 899 else { return nil }
        payloadCreations += 1
        let payload = TargetCleanupPayload(probe: self)
        bodyPayload = payload
        return payload
    }

    func recordBody(_ index: Int) {
        guard isRecording, index == 899 else { return }
        bodyCalls += 1
        originalEpoch = ViewBuildContextScope.current?.viewIdentity.installedEpoch
        let callback = onBody
        onBody = nil
        callback?()
    }

    func recordInitialAction(_ index: Int) {
        guard isRecording, index == 899 else { return }
        initialActions.append(index)
        let callback = onInitialAction
        onInitialAction = nil
        callback?()
    }

    func recordPayloadRelease() {
        payloadReleases += 1
        let callback = onPayloadRelease
        onPayloadRelease = nil
        callback?()
    }
}

@MainActor
private final class TargetCleanupPayload {
    let probe: TargetCleanupProbe
    init(probe: TargetCleanupProbe) { self.probe = probe }
    isolated deinit { probe.recordPayloadRelease() }
}

@MainActor
private struct TargetCleanupRow: View {
    let index: Int
    let probe: TargetCleanupProbe

    var body: some View {
        // The staged onChange action owns this payload. Neither its scalar
        // baseline nor the retained row stores it after update cleanup.
        let payload = probe.makePayload(index)
        probe.recordBody(index)
        return Text("ROW \(index)")
            .frame(width: 220, height: 24)
            .accessibilityIdentifier(targetCleanupIdentifier(index))
            .onChange(of: index, initial: true) { _, _ in
                withExtendedLifetime(payload) { probe.recordInitialAction(index) }
            }
    }
}

private func targetCleanupIdentifier(_ index: Int) -> String { "target.cleanup.\(index)" }
