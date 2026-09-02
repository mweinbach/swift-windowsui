import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Real managed List callbacks, with the ordinary four-round/128-element budget.
/// Late cancellation cannot undo the row table that was already accepted.
/// This diagnostic records scalar observations around the same cleanup
/// boundaries. It does not qualify replacement owners or rows.
@MainActor
final class ManagedListTargetCleanupPhaseDiagnosticsTests: XCTestCase {
    func testInitialOnChangeCancellationRefusesCompletionAndFinishesOriginalBuild() async throws {
        try exerciseLateCancellation(at: .initialAction)
    }

    func testOnChangeActionPayloadReleaseRefusesCompletionAndFinishesOriginalBuild() async throws {
        try exerciseLateCancellation(at: .actionPayloadRelease)
    }

    private func exerciseLateCancellation(at point: TargetCleanupPhaseDiagnosticCancellationPoint) throws {
        let fixture = try TargetCleanupPhaseDiagnosticFixture()
        defer { fixture.close() }
        let probe = fixture.probe
        let cancelOriginal = { [weak fixture] in
            guard let fixture else { return XCTFail("The original fixture must remain alive") }
            probe.diagnosticAtCallbackEntry = fixture.diagnosticSnapshot()
            probe.cancellations += 1
            XCTAssertTrue(fixture.runtime.hasActiveRetainedBuild)
            XCTAssertEqual(probe.originalEpoch?.didCommit, true)
            XCTAssertEqual(probe.factories, [899, 898])
            XCTAssertEqual(probe.initialActions, [899])
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(fixture.item))
            let acceptedRoots = fixture.adapter.mountedNodes(for: fixture.item.token)
            probe.diagnosticRootCount = acceptedRoots?.count ?? -1
            if let acceptedRoots {
                if !acceptedRoots.isEmpty {
                    probe.diagnosticFirstRoot = fixture.diagnosticRootSnapshot(acceptedRoots[0])
                }
                if acceptedRoots.count > 1 {
                    probe.diagnosticSecondRoot = fixture.diagnosticRootSnapshot(acceptedRoots[1])
                }
            }
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
            XCTAssertNotNil(fixture.host.find(targetCleanupPhaseDiagnosticIdentifier(899)))
            if point == .initialAction {
                XCTAssertEqual(probe.payloadReleases, 0)
                XCTAssertNotNil(probe.bodyPayload)
            } else {
                XCTAssertEqual(probe.payloadReleases, 1)
            }
            let originalResolutions = fixture.runtime.lazyListResolveCount
            fixture.runtime.releaseLazyListTarget(fixture.item)
            probe.diagnosticAfterRelease = fixture.diagnosticSnapshot()

            // This read-only observer queues behind the completion that is
            // already draining. It does not query layout or request another
            // target. Later layout passes may legitimately build the viewport.
            fixture.runtime.afterRetainedCallbacks { [weak fixture] in
                guard let fixture else { return XCTFail("The original fixture must remain alive") }
                probe.diagnosticAfterBuild = fixture.diagnosticSnapshot()
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
        probe.diagnosticAfterResolve = fixture.diagnosticSnapshot()

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
        XCTAssertNil(fixture.host.find(targetCleanupPhaseDiagnosticIdentifier(900)))
        // No assertion removes an already accepted row or claims that this
        // completion callback occurred before physical adoption.
        probe.printDiagnostic(point: point)
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

private enum TargetCleanupPhaseDiagnosticCancellationPoint { case initialAction, actionPayloadRelease }

@MainActor
private final class TargetCleanupPhaseDiagnosticFixture {
    let probe: TargetCleanupPhaseDiagnosticProbe
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
        let probe = TargetCleanupPhaseDiagnosticProbe()
        self.probe = probe
        let binding = Binding<Int?>(get: { probe.selection }, set: { probe.selection = $0 })
        let host = MountedLazyListTestHost(size: Size(width: 260, height: 200)) {
            List(0..<1_000, id: \.self, selection: binding) { index in
                let _ = probe.recordFactory(index)
                TargetCleanupPhaseDiagnosticRow(index: index, probe: probe)
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
            let source = try host.rowRoot(targetCleanupPhaseDiagnosticIdentifier(0))
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
            XCTAssertNil(host.find(targetCleanupPhaseDiagnosticIdentifier(898)))
            XCTAssertNil(host.find(targetCleanupPhaseDiagnosticIdentifier(899)))
            XCTAssertNil(host.find(targetCleanupPhaseDiagnosticIdentifier(900)))
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

    // Read the original references only. These native getters do not query
    // layout, materialize a row, or prepare a replacement navigation action.
    func diagnosticSnapshot() -> TargetCleanupPhaseDiagnosticSnapshot {
        TargetCleanupPhaseDiagnosticSnapshot(
            reached: true,
            ownerPresent: source.listNavigationOwner != nil,
            sameOwner: source.listNavigationOwner === sourceOwner,
            bindingPermitted: receipt.permitsBindingWrite,
            continuationPermitted: receipt.permitsContinuation,
            sameParent: source.parent === content,
            sameRuntime: source.retainedLazyListRuntime === runtime,
            remainsInContent: content.children.contains { $0 === source },
            factories: probe.factories.count,
            sourceFactories: probe.diagnosticSourceFactoryCount,
            resolutions: runtime.lazyListResolveCount)
    }

    // The caller already holds this root in its original acceptedRoots array.
    // Only native gap flags and the fixed fixture's Int navigation fields leave
    // this helper; no node, declaration, tag, or authority is retained.
    func diagnosticRootSnapshot(_ node: ViewNode) -> TargetCleanupPhaseDiagnosticRootSnapshot {
        TargetCleanupPhaseDiagnosticRootSnapshot(
            reached: true,
            separator: node.isSeparatorRule,
            gap: node.retainedLazyListGap != nil,
            ownerPresent: node.listNavigationOwner != nil,
            sameParent: node.parent === content,
            sameRuntime: node.retainedLazyListRuntime === runtime,
            ordinal: DeferredListRowNavigation.attached(to: node)?.ordinal ?? -1,
            leaf: DeferredListRowNavigation.attached(to: node)?.leaf ?? -1)
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
private final class TargetCleanupPhaseDiagnosticProbe {
    var selection: Int? = 0
    var isRecording = false
    var factories: [Int] = []
    var initialActions: [Int] = []
    var bodyCalls = 0
    var payloadCreations = 0
    var payloadReleases = 0
    var cancellations = 0
    var completedBuildObservations = 0
    var diagnosticSourceFactoryCount = 0
    var diagnosticAtCallbackEntry = TargetCleanupPhaseDiagnosticSnapshot()
    var diagnosticAfterRelease = TargetCleanupPhaseDiagnosticSnapshot()
    var diagnosticAfterBuild = TargetCleanupPhaseDiagnosticSnapshot()
    var diagnosticAfterResolve = TargetCleanupPhaseDiagnosticSnapshot()
    var diagnosticRootCount = -1
    var diagnosticFirstRoot = TargetCleanupPhaseDiagnosticRootSnapshot()
    var diagnosticSecondRoot = TargetCleanupPhaseDiagnosticRootSnapshot()
    weak var originalEpoch: StateMountEpoch?
    weak var bodyPayload: TargetCleanupPhaseDiagnosticPayload?
    var onBody: (() -> Void)?
    var onInitialAction: (() -> Void)?
    var onPayloadRelease: (() -> Void)?

    func recordFactory(_ index: Int) {
        if isRecording {
            factories.append(index)
            if index == 0 { diagnosticSourceFactoryCount += 1 }
        }
    }

    func printDiagnostic(point: TargetCleanupPhaseDiagnosticCancellationPoint) {
        let name = point == .initialAction ? "initialAction" : "actionPayloadRelease"
        // Four fixed phase records and at most two roots: <= 741 ASCII bytes
        // including LF, even with every Int formatted at its signed 64-bit max
        // width. This runs after all original oracles, never inside callbacks.
        print(
            "ManagedListTargetCleanupPhase case=\(name) "
                + "phaseFields=reached,owner,sameOwner,binding,continuation,parent,runtime,member,factories,sourceFactories,resolutions "
                + "entry=\(diagnosticAtCallbackEntry.encoded) released=\(diagnosticAfterRelease.encoded) "
                + "completed=\(diagnosticAfterBuild.encoded) returned=\(diagnosticAfterResolve.encoded) "
                + "rootFields=reached,separator,gap,owner,parent,runtime,ordinal,leaf "
                + "rootCount=\(diagnosticRootCount) root0=\(diagnosticFirstRoot.encoded) root1=\(diagnosticSecondRoot.encoded)"
        )
    }

    func makePayload(_ index: Int) -> TargetCleanupPhaseDiagnosticPayload? {
        guard isRecording, index == 899 else { return nil }
        payloadCreations += 1
        let payload = TargetCleanupPhaseDiagnosticPayload(probe: self)
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
private final class TargetCleanupPhaseDiagnosticPayload {
    let probe: TargetCleanupPhaseDiagnosticProbe
    init(probe: TargetCleanupPhaseDiagnosticProbe) { self.probe = probe }
    isolated deinit { probe.recordPayloadRelease() }
}

@MainActor
private struct TargetCleanupPhaseDiagnosticRow: View {
    let index: Int
    let probe: TargetCleanupPhaseDiagnosticProbe

    var body: some View {
        // The staged onChange action owns this payload. Neither its scalar
        // baseline nor the retained row stores it after update cleanup.
        let payload = probe.makePayload(index)
        probe.recordBody(index)
        return Text("ROW \(index)")
            .frame(width: 220, height: 24)
            .accessibilityIdentifier(targetCleanupPhaseDiagnosticIdentifier(index))
            .onChange(of: index, initial: true) { _, _ in
                withExtendedLifetime(payload) { probe.recordInitialAction(index) }
            }
    }
}

private func targetCleanupPhaseDiagnosticIdentifier(_ index: Int) -> String { "target.cleanup.\(index)" }

// Defaults explicitly identify an unreached boundary. The stored fields are
// Int and Bool only; interpolation happens after the original assertions.
private struct TargetCleanupPhaseDiagnosticSnapshot {
    var reached = false
    var ownerPresent = false
    var sameOwner = false
    var bindingPermitted = false
    var continuationPermitted = false
    var sameParent = false
    var sameRuntime = false
    var remainsInContent = false
    var factories = -1
    var sourceFactories = -1
    var resolutions = -1

    var encoded: String {
        "\(reached ? 1 : 0),\(ownerPresent ? 1 : 0),\(sameOwner ? 1 : 0),\(bindingPermitted ? 1 : 0),"
            + "\(continuationPermitted ? 1 : 0),\(sameParent ? 1 : 0),\(sameRuntime ? 1 : 0),\(remainsInContent ? 1 : 0),"
            + "\(factories),\(sourceFactories),\(resolutions)"
    }
}

private struct TargetCleanupPhaseDiagnosticRootSnapshot {
    var reached = false
    var separator = false
    var gap = false
    var ownerPresent = false
    var sameParent = false
    var sameRuntime = false
    var ordinal = -1
    var leaf = -1

    var encoded: String {
        "\(reached ? 1 : 0),\(separator ? 1 : 0),\(gap ? 1 : 0),\(ownerPresent ? 1 : 0),"
            + "\(sameParent ? 1 : 0),\(sameRuntime ? 1 : 0),\(ordinal),\(leaf)"
    }
}
