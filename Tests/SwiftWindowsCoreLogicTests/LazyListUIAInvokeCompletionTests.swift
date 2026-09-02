import CUIAInterop
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public List/Button construction and real retained UIA providers, without an
/// HWND or input injection. The first visible logical row isolates Invoke from
/// Realize; PublicLazyListAccessibilityTests covers the far-row combination.
@MainActor
final class LazyListUIAInvokeCompletionTests: XCTestCase {
    func testPublicButtonInvokePreparesItsSuccessorAndImmediatelyFocusesTheOriginalNode() async throws {
        let fixture = try InvokeCompletionFixture()
        defer { fixture.close() }
        try fixture.arm()

        XCTAssertEqual(SWU_UIAProviderInvokeResult(fixture.invokePattern), 0)
        let originalButton = try XCTUnwrap(fixture.originalButton)

        let trace = fixture.trace
        let rounds = fixture.runtime.lastLazyListConsumedRounds
        let elements = fixture.runtime.lastLazyListConsumedElements
        XCTAssertEqual(fixture.probe.activations, [0])
        XCTAssertFalse(fixture.postFactories.isEmpty, "The accepted successor must actually prepare its rows")
        XCTAssertFalse(fixture.runtime.isLazyListAccessibilityItemCurrent(fixture.originalItem))
        XCTAssertNotNil(fixture.runtime.lazyListAccessibilityGeneration(for: fixture.originalItem))
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: fixture.element), .ordinary)
        try assertSettled(fixture.runtime)
        assertSharedBudget(trace, rounds: rounds, elements: elements, queries: 2)

        // Only passive checks precede this call. No external layout or snapshot
        // projection may repair the provider before its first focus request.
        XCTAssertEqual(SWU_UIAProviderSetFocusResult(fixture.row), 0)
        XCTAssertTrue(fixture.runtime.focusedNode === originalButton)
        XCTAssertEqual(try fixture.currentRuntimeID(), fixture.initialRuntimeID)
        let snapshot = try XCTUnwrap(fixture.source.uiaElementSnapshots().first { $0.id == fixture.element })
        XCTAssertEqual(snapshot.name, "Invoke 0")
        XCTAssertFalse(snapshot.isVirtualizedPlaceholder)
        XCTAssertEqual(snapshot.isOffscreen, false)
        XCTAssertGreaterThan(snapshot.bounds.width, 0)
        XCTAssertGreaterThan(snapshot.bounds.height, 0)
        XCTAssertEqual(fixture.probe.activations, [0])
    }

    func testOneElementOneRoundAllowanceDoesNotStartAPostEffectLayoutPass() async throws {
        let fixture = try InvokeCompletionFixture()
        defer { fixture.close() }
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        try fixture.arm()

        XCTAssertEqual(SWU_UIAProviderInvokeResult(fixture.invokePattern), invokeCompletionUnavailable)

        let boundary = try XCTUnwrap(fixture.effectBoundary)
        XCTAssertEqual(fixture.probe.activations, [0])
        XCTAssertEqual(fixture.runtime.layoutPassID, boundary.pass)
        XCTAssertTrue(fixture.postPasses.isEmpty)
        XCTAssertTrue(fixture.postFactories.isEmpty)
        XCTAssertEqual(fixture.probe.factories.count, boundary.factories)
        XCTAssertNil(fixture.runtime.lazyListAccessibilityGeneration(for: fixture.originalItem))
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: fixture.element), .placeholder)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        assertSharedBudget(fixture.trace, rounds: 1, elements: 0, queries: 1, roundLimit: 1, elementLimit: 1)
        XCTAssertNil(fixture.runtime.focusedNode)
    }

    func testActionQueuedLayoutWorkRemainsPendingAfterTheCompletionReload() async throws {
        let fixture = try InvokeCompletionFixture()
        defer { fixture.close() }
        var callbacks = 0
        fixture.onAction = { fixture in
            fixture.runtime.scheduleAfterLayout(key: "invoke-completion-later") { callbacks += 1 }
        }
        try fixture.arm()

        XCTAssertEqual(SWU_UIAProviderInvokeResult(fixture.invokePattern), invokeCompletionUnavailable)

        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(fixture.probe.activations, [0])
        XCTAssertTrue(fixture.postPasses.isEmpty)
        XCTAssertTrue(fixture.postFactories.isEmpty)
        XCTAssertNil(fixture.runtime.lazyListAccessibilityGeneration(for: fixture.originalItem))
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: fixture.element), .placeholder)
        assertRejectedTrace(fixture, queries: 1)

        XCTAssertNotNil(fixture.host.layout(), "The queued callback belongs to a later independent query")
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(fixture.probe.activations, [0])
    }

    func testActionDeletionAndAcceptedSameKeyReinsertionDoNotReviveTheOriginalProvider() async throws {
        let fixture = try InvokeCompletionFixture()
        defer { fixture.close() }
        var acceptedAbsences = 0
        fixture.onAction = { fixture in
            fixture.probe.rows.removeAll { $0 == 0 }
            fixture.host.reload()
            XCTAssertFalse(
                fixture.runtime.isLazyListAccessibilityTokenCurrent(
                    fixture.originalItem.token, in: fixture.originalItem))
            acceptedAbsences += 1
            fixture.probe.rows.insert(0, at: 0)
            fixture.host.reload()
        }
        try fixture.arm()

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: fixture.element))

        XCTAssertEqual(acceptedAbsences, 1)
        XCTAssertEqual(fixture.probe.rows.first, 0)
        XCTAssertEqual(fixture.probe.activations, [0])
        XCTAssertFalse(
            fixture.runtime.isLazyListAccessibilityTokenCurrent(
                fixture.originalItem.token, in: fixture.originalItem))
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: fixture.element), .unavailable)
        XCTAssertTrue(fixture.postPasses.isEmpty)
        XCTAssertTrue(fixture.postFactories.isEmpty)
        assertRejectedTrace(fixture, queries: 1)
    }

    func testActionDetachmentAndReattachmentCannotRenewAnOriginalPhysicalAttachment() async throws {
        for change in InvokeCompletionAttachmentChange.allCases {
            let fixture = try InvokeCompletionFixture()
            defer { fixture.close() }
            var interventions = 0
            fixture.onAction = { fixture in
                interventions += 1
                fixture.detachAndReattach(change)
                // Departure can retire Button's automatic completion. Request
                // the accepted successor explicitly so this is not a no-reload case.
                fixture.host.reload()
            }
            try fixture.arm()

            XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: fixture.element), "\(change)")

            XCTAssertEqual(interventions, 1, "\(change)")
            XCTAssertEqual(fixture.probe.activations, [0], "\(change)")
            XCTAssertTrue(fixture.postPasses.isEmpty, "\(change)")
            XCTAssertTrue(fixture.postFactories.isEmpty, "\(change)")
            try fixture.assertOriginalAttachment(isCurrent: false)
            assertRejectedTrace(fixture, queries: 1)
        }
    }

    func testPostQueryAttachmentAndTokenChangesStopBeforeTheFirstRowFactory() async throws {
        for change in InvokeCompletionPostLayoutChange.allCases {
            let fixture = try InvokeCompletionFixture()
            defer { fixture.close() }
            var interventions = 0
            fixture.onFirstPostLayout = { fixture in
                interventions += 1
                XCTAssertTrue(fixture.runtime.isLazyListAccessibilityContainerCurrent(fixture.originalItem))
                XCTAssertTrue(
                    fixture.runtime.isLazyListAccessibilityTokenCurrent(
                        fixture.originalItem.token, in: fixture.originalItem))
                XCTAssertNil(fixture.runtime.lazyListAccessibilityGeneration(for: fixture.originalItem))
                switch change {
                case .button: fixture.detachAndReattach(.button)
                case .container: fixture.detachAndReattach(.container)
                case .token:
                    fixture.probe.rows.removeAll { $0 == 0 }
                    fixture.host.reload()
                    XCTAssertFalse(
                        fixture.runtime.isLazyListAccessibilityTokenCurrent(
                            fixture.originalItem.token, in: fixture.originalItem))
                    fixture.probe.rows.insert(0, at: 0)
                    fixture.host.reload()
                }
            }
            try fixture.arm()

            XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: fixture.element), "\(change)")

            XCTAssertEqual(interventions, 1, "The original post-effect query must reach its actual pass: \(change)")
            XCTAssertEqual(fixture.probe.activations, [0], "\(change)")
            XCTAssertFalse(fixture.postPasses.isEmpty, "\(change)")
            XCTAssertTrue(fixture.postFactories.isEmpty, "\(change)")
            if change == .token {
                XCTAssertFalse(
                    fixture.runtime.isLazyListAccessibilityTokenCurrent(
                        fixture.originalItem.token, in: fixture.originalItem))
            } else {
                try fixture.assertOriginalAttachment(isCurrent: false)
            }
            assertRejectedTrace(fixture, queries: 2)
        }
    }

    func testFirstPostQueryFactoryCannotTransferCompletionToAnotherAcceptedAdapter() async throws {
        let fixture = try InvokeCompletionFixture()
        defer { fixture.close() }
        var interventions = 0
        var enteredAdapter: ObjectIdentifier?
        fixture.onFirstPostFactory = { fixture in
            interventions += 1
            enteredAdapter = fixture.list.retainedLazyListAdapter.map(ObjectIdentifier.init)
            fixture.host.reload()
        }
        try fixture.arm()

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: fixture.element))

        XCTAssertEqual(interventions, 1)
        XCTAssertEqual(fixture.probe.activations, [0])
        // The first factory supersedes the build. Neither its remaining cohort
        // nor the later accepted adapter may enter another factory in this call.
        XCTAssertEqual(fixture.postFactories.count, 1)
        XCTAssertNotNil(enteredAdapter)
        XCTAssertNotEqual(fixture.list.retainedLazyListAdapter.map(ObjectIdentifier.init), enteredAdapter)
        assertRejectedTrace(fixture, queries: 2)
    }

    func testFirstPostQueryFactoryScrollABAStopsLaterFactoriesWithoutAReveal() async throws {
        let fixture = try InvokeCompletionFixture()
        defer { fixture.close() }
        let offset = fixture.scroll.scrollOffset
        var interventions = 0
        fixture.onFirstPostFactory = { fixture in
            interventions += 1
            fixture.scroll.scrollOffset = offset + 1
            fixture.scroll.scrollOffset = offset
        }
        try fixture.arm()

        // A failed source result need not be a COM failure: the existing native
        // Void callback checks logical availability, not this source Boolean.
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: fixture.element))

        XCTAssertEqual(interventions, 1)
        XCTAssertEqual(fixture.probe.activations, [0])
        XCTAssertEqual(fixture.postFactories.count, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, offset)
        try fixture.assertOriginalAttachment(isCurrent: true)
        assertRejectedTrace(fixture, queries: 2)
    }

    func testHostStopInsideTheFirstPostQueryFactoryStopsTheRemainingWork() async throws {
        let fixture = try InvokeCompletionFixture()
        defer { fixture.close() }
        var interventions = 0
        fixture.onFirstPostFactory = { fixture in
            interventions += 1
            fixture.runtime.stopRenderLifecycleCallbacks()
        }
        try fixture.arm()

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: fixture.element))

        XCTAssertEqual(interventions, 1)
        XCTAssertEqual(fixture.probe.activations, [0])
        XCTAssertEqual(fixture.postFactories.count, 1)
        XCTAssertFalse(fixture.runtime.permitsRetainedActionInvocation)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: fixture.element), .unavailable)
        assertRejectedTrace(fixture, queries: 2)
    }

    func testPostQueryFactoryKeepsAdmissionClosedAcrossSourcesAndCannotRechargeTheBudget() async throws {
        let fixture = try InvokeCompletionFixture()
        defer { fixture.close() }
        let other = RuntimeUIAElementTreeSource(runtime: fixture.runtime)
        let otherID = try XCTUnwrap(other.uiaElementSnapshots().first { $0.name == "Invoke 0" }?.id)
        var interventions = 0
        var nestedResults: [Bool] = []
        var budgetChanges: [Bool] = []
        fixture.onFirstPostFactory = { fixture in
            interventions += 1
            let pass = fixture.runtime.layoutPassID
            let traceCount = fixture.trace.count
            nestedResults.append(other.uiaInvokeDefaultAction(elementID: otherID))
            nestedResults.append(other.uiaSetFocusResult(elementID: otherID))
            budgetChanges.append(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 256, roundLimit: 8))
            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
            XCTAssertEqual(fixture.trace.count, traceCount)
        }
        try fixture.arm()

        XCTAssertEqual(SWU_UIAProviderInvokeResult(fixture.invokePattern), 0)

        XCTAssertEqual(interventions, 1)
        XCTAssertEqual(nestedResults, [false, false])
        XCTAssertEqual(budgetChanges, [false])
        XCTAssertEqual(fixture.probe.activations, [0])
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: fixture.element), .ordinary)
        try assertSettled(fixture.runtime)
        assertSharedBudget(
            fixture.trace, rounds: fixture.runtime.lastLazyListConsumedRounds,
            elements: fixture.runtime.lastLazyListConsumedElements, queries: 2)
    }

    func testEndingTheOwnedMutationInsideACompletionFactoryStopsTheNextFactory() async throws {
        let fixture = try InvokeCompletionFixture()
        defer { fixture.close() }
        try fixture.arm()
        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation())
        defer { fixture.runtime.endAccessibilityMutation(mutation) }
        var interventions = 0
        fixture.onFirstPostFactory = { fixture in
            interventions += 1
            fixture.runtime.endAccessibilityMutation(mutation)
        }

        // Exercise the package completion route with an explicitly owned real
        // mutation. The source keeps its active mutation private; no test seam
        // is introduced merely to terminate it from an application callback.
        let result = fixture.runtime.withLazyListResolutionBudget {
            XCTAssertTrue(fixture.invokeRetainedAction())
            XCTAssertTrue(fixture.runtime.isAccessibilityTargetCurrent(fixture.originalTarget, during: mutation))
            XCTAssertTrue(
                fixture.runtime.isLazyListAccessibilityTokenCurrent(
                    fixture.originalItem.token, in: fixture.originalItem))
            XCTAssertFalse(fixture.runtime.isLazyListAccessibilityItemCurrent(fixture.originalItem))
            XCTAssertNil(fixture.runtime.lazyListAccessibilityGeneration(for: fixture.originalItem))
            return fixture.runtime.prepareLazyListAccessibilityInvocationCompletion(
                token: fixture.originalItem.token, in: fixture.originalItem, replacing: fixture.originalItem,
                target: fixture.originalTarget, during: mutation)
        }

        XCTAssertNil(result)
        XCTAssertEqual(interventions, 1)
        XCTAssertEqual(fixture.probe.activations, [0])
        XCTAssertEqual(fixture.postFactories.count, 1)
        XCTAssertFalse(fixture.runtime.isAccessibilityMutationCurrent(mutation))
        assertRejectedTrace(fixture, queries: 2)
    }

    private func assertSettled(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            return XCTFail("Expected a completed actual layout receipt", file: file, line: line)
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
    }

    private func assertRejectedTrace(
        _ fixture: InvokeCompletionFixture, queries: Int, file: StaticString = #filePath, line: UInt = #line
    ) {
        assertSharedBudget(
            fixture.trace, rounds: fixture.runtime.lastLazyListConsumedRounds,
            elements: fixture.runtime.lastLazyListConsumedElements, queries: queries, file: file, line: line)
        XCTAssertNil(fixture.runtime.focusedNode, file: file, line: line)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.initialOffset, file: file, line: line)
    }

    private func assertSharedBudget(
        _ trace: [RetainedViewRuntime.LazyListUIAPhaseTrace], rounds: Int, elements: Int, queries: Int,
        roundLimit: Int = 4, elementLimit: Int = 128, file: StaticString = #filePath, line: UInt = #line
    ) {
        let debits = trace.filter { $0.kind == .roundDebit }
        XCTAssertGreaterThan(rounds, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(rounds, roundLimit, file: file, line: line)
        XCTAssertGreaterThanOrEqual(elements, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(elements, elementLimit, file: file, line: line)
        XCTAssertEqual(debits.map(\.consumedRounds), Array(1..<(rounds + 1)), file: file, line: line)
        XCTAssertEqual(
            Set(trace.filter { $0.kind == .layoutPass }.map(\.resolutionSequence)).count,
            queries, "There must be no third query or per-query budget reset", file: file, line: line)
        XCTAssertFalse(trace.contains { $0.kind == .ownedScroll }, file: file, line: line)
        for (previous, current) in zip(trace, trace.dropFirst()) {
            XCTAssertGreaterThanOrEqual(current.consumedRounds, previous.consumedRounds, file: file, line: line)
            XCTAssertLessThanOrEqual(current.remainingElements, previous.remainingElements, file: file, line: line)
        }
    }
}

private let invokeCompletionUnavailable: Int32 = -2_147_220_991
private enum InvokeCompletionAttachmentChange: CaseIterable, Equatable { case button, container }
private enum InvokeCompletionPostLayoutChange: CaseIterable, Equatable { case button, container, token }

@MainActor
private final class InvokeCompletionProbe {
    var rows = Array(0..<80)
    var factories: [Int] = []
    var activations: [Int] = []
    var onAction: ((Int) -> Void)?
    var onFactory: ((Int) -> Void)?

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        onFactory?(id)
        return [
            AnyView(
                Button("Invoke \(id)") { [weak self] in
                    guard let self else { return }
                    self.activations.append(id)
                    self.onAction?(id)
                }
                .accessibilityIdentifier("invoke.completion.\(id)")
                .frame(height: 24))
        ]
    }
}

@MainActor
private final class InvokeCompletionFixture {
    struct EffectBoundary {
        let pass: UInt64
        let factories: Int
    }

    let probe: InvokeCompletionProbe
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let bridge: UIAProviderBridge
    let row: UnsafeMutableRawPointer
    let invokePattern: UnsafeMutableRawPointer
    let element: UInt64
    let initialRuntimeID: [Int32]
    let list: ViewNode
    let scroll: ViewNode
    let initialOffset: Double
    let originalItem: RetainedLazyListAccessibilityItem
    let originalTarget: RetainedAccessibilityTarget
    private(set) weak var originalButton: ViewNode?
    private weak var originalAdapter: RetainedLazyListRuntimeAdapter?
    private let rootProvider: UnsafeMutableRawPointer
    private var isClosed = false
    private(set) var effectBoundary: EffectBoundary?
    private(set) var postPasses: [UInt64] = []
    private(set) var postFactories: [Int] = []
    var onAction: ((InvokeCompletionFixture) -> Void)?
    var onFirstPostLayout: ((InvokeCompletionFixture) -> Void)?
    var onFirstPostFactory: ((InvokeCompletionFixture) -> Void)?

    var runtime: RetainedViewRuntime { host.runtime }
    var trace: [RetainedViewRuntime.LazyListUIAPhaseTrace] { runtime.lazyListUIAPhasesForTesting }

    init() throws {
        let probe = InvokeCompletionProbe()
        self.probe = probe
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
        }
        self.host = host
        let source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        self.source = source
        let bridge = UIAProviderBridge(source: source)
        self.bridge = bridge
        var ownedRoot: UnsafeMutableRawPointer?
        var ownedRow: UnsafeMutableRawPointer?
        var ownedAction: UnsafeMutableRawPointer?
        do {
            XCTAssertNotNil(host.layout())
            let root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
            ownedRoot = root
            let itemContainer = try XCTUnwrap(Self.findItemContainer(in: root))
            defer { SWU_UIAReleaseProvider(itemContainer) }
            XCTAssertEqual(
                SWU_UIAItemContainerProviderFindItemResult(
                    itemContainer, nil, Int32(SWU_UIA_ITEM_PROPERTY_ANY), nil, 0, &ownedRow), 0)
            let row = try XCTUnwrap(ownedRow)
            let identity = try Self.readRuntimeID(row)
            let low = UInt64(UInt32(bitPattern: try XCTUnwrap(identity.dropFirst().first)))
            let high = identity.count > 2 ? UInt64(UInt32(bitPattern: identity[2])) << 32 : 0
            let action = try XCTUnwrap(SWU_UIAProviderGetInvokePattern(row))
            ownedAction = action
            let list = try host.list()
            let scroll = try host.scrollContainer()
            let button = try XCTUnwrap(
                host.nodes.first {
                    $0.accessibilityIdentifier == "invoke.completion.0" && $0.onActivate != nil
                })
            let item = try XCTUnwrap(host.runtime.lazyListAccessibilityItem(in: list, containing: button))
            let target = try XCTUnwrap(host.runtime.accessibilityTarget(for: button))
            self.rootProvider = root
            self.row = row
            self.invokePattern = action
            self.initialRuntimeID = identity
            self.element = low | high
            self.list = list
            self.scroll = scroll
            self.initialOffset = scroll.scrollOffset
            self.originalButton = button
            self.originalAdapter = list.retainedLazyListAdapter
            self.originalItem = item
            self.originalTarget = target
        } catch {
            SWU_UIAReleaseProvider(ownedAction)
            SWU_UIAReleaseProvider(ownedRow)
            SWU_UIAReleaseProvider(ownedRoot)
            host.close()
            throw error
        }
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            close()
            throw InvokeCompletionFixtureError.unsettledWarmViewport
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint)
        probe.onAction = { [weak self] id in
            guard let self else { return }
            XCTAssertEqual(id, 0)
            XCTAssertNil(self.effectBoundary, "An invocation may enter the original action only once")
            self.effectBoundary = EffectBoundary(pass: self.runtime.layoutPassID, factories: self.probe.factories.count)
            self.onAction?(self)
        }
        probe.onFactory = { [weak self] id in
            guard let self, let boundary = self.effectBoundary else { return }
            self.postFactories.append(id)
            if self.postFactories.count == 1 {
                XCTAssertGreaterThan(self.runtime.layoutPassID, boundary.pass)
                XCTAssertFalse(self.list.retainedLazyListAdapter === self.originalAdapter)
                self.onFirstPostFactory?(self)
            }
        }
        runtime.root.onLayout = { [weak self] _ in
            guard let self, let boundary = self.effectBoundary, self.runtime.layoutPassID > boundary.pass,
                !self.postPasses.contains(self.runtime.layoutPassID)
            else { return }
            self.postPasses.append(self.runtime.layoutPassID)
            if self.postPasses.count == 1 { self.onFirstPostLayout?(self) }
        }
    }

    func arm(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(probe.activations.isEmpty, file: file, line: line)
        XCTAssertNotNil(originalButton?.onActivate, file: file, line: line)
        XCTAssertTrue(runtime.isLazyListAccessibilityItemCurrent(originalItem), file: file, line: line)
        XCTAssertNotNil(runtime.lazyListAccessibilityGeneration(for: originalItem), file: file, line: line)
        XCTAssertEqual(source.uiaLogicalItemState(elementID: element), .ordinary, file: file, line: line)
        try assertOriginalAttachment(isCurrent: true, file: file, line: line)
        runtime.recordsLazyListUIAPhasesForTesting = true
    }

    func assertOriginalAttachment(
        isCurrent expected: Bool, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation(), file: file, line: line)
        defer { runtime.endAccessibilityMutation(mutation) }
        XCTAssertEqual(
            runtime.isAccessibilityTargetCurrent(originalTarget, during: mutation), expected,
            file: file, line: line)
    }

    func detachAndReattach(
        _ change: InvokeCompletionAttachmentChange, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let node = change == .button ? originalButton : list, let parent = node.parent else {
            return XCTFail(
                "The original physical attachment must exist at the hostile boundary", file: file, line: line)
        }
        let children = parent.children
        XCTAssertTrue(children.contains { $0 === node }, file: file, line: line)
        parent.setChildren([])
        parent.setChildren(children)
        XCTAssertTrue(node.parent === parent, file: file, line: line)
        XCTAssertTrue(parent.children.contains { $0 === node }, file: file, line: line)
    }

    func currentRuntimeID() throws -> [Int32] { try Self.readRuntimeID(row) }

    @inline(never)
    func invokeRetainedAction() -> Bool {
        guard let node = originalButton else { return false }
        return AccessibilityProjection.invokeDefaultAction(on: node, in: runtime, intent: .invoke)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        onAction = nil
        onFirstPostLayout = nil
        onFirstPostFactory = nil
        probe.onAction = nil
        probe.onFactory = nil
        runtime.root.onLayout = nil
        host.close()
        SWU_UIAReleaseProvider(invokePattern)
        SWU_UIAReleaseProvider(row)
        SWU_UIAReleaseProvider(rootProvider)
    }

    private static func readRuntimeID(_ provider: UnsafeMutableRawPointer) throws -> [Int32] {
        var values = [Int32](repeating: 0, count: 8)
        var count: Int32 = 0
        let result = values.withUnsafeMutableBufferPointer {
            SWU_UIAProviderGetRuntimeIdResult(provider, $0.baseAddress, Int32($0.count), &count)
        }
        XCTAssertEqual(result, 0)
        XCTAssertGreaterThanOrEqual(count, 2)
        return Array(values.prefix(Int(max(0, count))))
    }

    private static func findItemContainer(in provider: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
        if let pattern = SWU_UIAProviderGetItemContainerPattern(provider) { return pattern }
        var next = SWU_UIAProviderNavigate(provider, Int32(SWU_UIA_NAV_FIRST_CHILD))
        while let child = next {
            let pattern = findItemContainer(in: child)
            next = pattern == nil ? SWU_UIAProviderNavigate(child, Int32(SWU_UIA_NAV_NEXT_SIBLING)) : nil
            SWU_UIAReleaseProvider(child)
            if let pattern { return pattern }
        }
        return nil
    }
}

private enum InvokeCompletionFixtureError: Error { case unsettledWarmViewport }
