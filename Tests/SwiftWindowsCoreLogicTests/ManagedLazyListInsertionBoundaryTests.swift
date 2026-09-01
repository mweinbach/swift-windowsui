import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The ordinary managed factory, journal and attachment driver must own these
/// effects. No fixture grants an insertion plan a fabricated completion proof.
@MainActor
final class ManagedLazyListInsertionBoundaryTests: XCTestCase {
    func testRejectedPreparationLeavesItsIntroductionAvailableForTheNextAdmittedAttempt() async throws {
        let fixture = ManagedInsertionBoundaryFixture()
        defer { fixture.close() }
        fixture.probe.rejectPreparation = true
        try fixture.introduce([1])

        _ = fixture.host.layout()

        let event = try XCTUnwrap(fixture.probe.events[1])
        XCTAssertTrue(event.isPending, "Source preparation is not actual row acceptance")
        XCTAssertGreaterThan(fixture.probe.modifierCalls, 0)
        XCTAssertEqual(fixture.probe.attachCalls, [])
        XCTAssertNil(fixture.host.find(managedInsertionBoundaryIdentifier(1, 0)))
        XCTAssertEqual(fixture.clockReads, 0)

        fixture.probe.rejectPreparation = false
        XCTAssertNotNil(fixture.host.layout())

        let first = try fixture.actual(row: 1, leaf: 0)
        let second = try fixture.actual(row: 1, leaf: 1)
        XCTAssertFalse(event.isPending)
        XCTAssertEqual(first.animationStates[.opacity]?.duration, 2)
        XCTAssertEqual(second.animationStates[.opacity]?.duration, 2)
        XCTAssertEqual(fixture.clockReads, 1)
    }

    func testAllPublishedLeavesConsumeArrivalBeforeTheFirstControllerCanRejectCompletion() async throws {
        let fixture = ManagedInsertionBoundaryFixture(nestedChild: true)
        defer { fixture.close() }
        // Inspect one admitted attempt; a normal query permits four fresh
        // attempts when an attachment callback keeps invalidating completion.
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 1))
        var observedClaim = false
        var observedConsumedLeaves = false
        fixture.probe.onAttach = { row, leaf, node in
            guard row == 1, leaf == 0 else { return }
            observedClaim = fixture.probe.events[1]?.isPending == false
            let published = fixture.host.nodes.filter {
                $0.accessibilityIdentifier?.hasPrefix("managed.insertion.boundary.1.") == true
            }
            observedConsumedLeaves =
                published.count == 2
                && published.allSatisfy { $0.didPlayInsertionTransition && $0.animationStates[.opacity] == nil }
            let identity = node.retainedViewIdentity
            node.retainedViewIdentity = identity
        }
        try fixture.introduce([1])

        _ = fixture.host.layout()

        XCTAssertTrue(observedClaim)
        XCTAssertTrue(observedConsumedLeaves)
        XCTAssertEqual(fixture.probe.attachCalls, [0], "A stale candidate cannot invoke the second controller")
        let first = try fixture.actual(row: 1, leaf: 0)
        let second = try fixture.actual(row: 1, leaf: 1)
        assertUnanimated(first)
        assertUnanimated(second)
        XCTAssertEqual(fixture.clockReads, 0)
        XCTAssertFalse(try XCTUnwrap(fixture.probe.events[1]).isPending)

        fixture.probe.onAttach = nil
        withAnimation(.linear(duration: 9)) { fixture.host.reload() }
        XCTAssertNotNil(fixture.host.layout())

        XCTAssertTrue(try fixture.actual(row: 1, leaf: 0) === first)
        XCTAssertTrue(try fixture.actual(row: 1, leaf: 1) === second)
        assertUnanimated(first)
        assertUnanimated(second)
        XCTAssertEqual(fixture.clockReads, 0, "Neither a retry nor the generic root pass can replay accepted arrival")
    }

    func testOneClockStartsEveryReturnedDescendantAndPreservesUnrelatedChannels() async throws {
        let fixture = ManagedInsertionBoundaryFixture(nestedChild: true)
        defer { fixture.close() }
        fixture.probe.seedOutlineAnimation = true
        try fixture.introduce([1])

        XCTAssertNotNil(fixture.host.layout())

        let root = try fixture.actual(row: 1, leaf: 0)
        let descendant = try fixture.actual(row: 1, leaf: 1)
        XCTAssertTrue(descendant.parent === root)
        XCTAssertEqual(try fixture.host.list().children.count, 1)
        XCTAssertEqual(fixture.clockReads, 1, "One shared clock covers the complete accepted source forest")
        for node in [root, descendant] {
            let insertion = try XCTUnwrap(node.animationStates[.opacity])
            XCTAssertEqual(insertion.startTime, 12)
            XCTAssertEqual(insertion.duration, 2)
            XCTAssertEqual(insertion.startValue, 0)
            XCTAssertEqual(insertion.endValue, 0.8)
            XCTAssertEqual(node.animationStates[.outlineWidth]?.startTime, 1)
            XCTAssertEqual(node.animationStates[.outlineWidth]?.endValue, 6)
            XCTAssertEqual(node.opacity, 0)
            XCTAssertTrue(node.didPlayInsertionTransition)
        }
        try fixture.host.assertCommittedDescriptor()
    }

    func testAcceptedFirstRootConsumesTheUnpublishedSiblingArrivalOnRetry() async throws {
        let fixture = ManagedInsertionBoundaryFixture()
        defer { fixture.close() }
        // This assertion sequence observes one rejected attempt, then the
        // explicitly requested successor, without changing the shared default.
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 1))
        fixture.probe.onAttach = { row, leaf, node in
            guard row == 1, leaf == 0 else { return }
            let identity = node.retainedViewIdentity
            node.retainedViewIdentity = identity
        }
        try fixture.introduce([1])

        _ = fixture.host.layout()

        let first = try fixture.actual(row: 1, leaf: 0)
        XCTAssertNil(fixture.host.find(managedInsertionBoundaryIdentifier(1, 1)))
        XCTAssertEqual(fixture.probe.attachCalls, [0])
        XCTAssertFalse(try XCTUnwrap(fixture.probe.events[1]).isPending)
        assertUnanimated(first)
        XCTAssertEqual(fixture.clockReads, 0)

        fixture.probe.onAttach = nil
        withAnimation(.linear(duration: 9)) { fixture.host.reload() }
        XCTAssertNotNil(fixture.host.layout())

        XCTAssertTrue(try fixture.actual(row: 1, leaf: 0) === first)
        let sibling = try fixture.actual(row: 1, leaf: 1)
        assertUnanimated(first)
        assertUnanimated(sibling)
        // The retained first node accepts its new controller before the fresh
        // sibling attaches. Neither controller attachment is a row arrival.
        XCTAssertEqual(fixture.probe.attachCalls, [0, 0, 1])
        XCTAssertEqual(fixture.clockReads, 0, "A new candidate cannot replay an accepted part of the logical event")
    }

    func testDefaultBudgetRetriesUseFreshAttemptsWithoutReplayingConsumedArrival() async throws {
        let fixture = ManagedInsertionBoundaryFixture()
        defer { fixture.close() }
        fixture.probe.onAttach = { row, leaf, node in
            XCTAssertTrue(fixture.host.runtime.hasActiveRetainedBuild)
            XCTAssertEqual(row, 1)
            XCTAssertEqual(leaf, 0, "A rejected attempt cannot continue to the second controller")
            XCTAssertEqual(fixture.probe.events[1]?.isPending, false)
            XCTAssertTrue(node.didPlayInsertionTransition)
            XCTAssertNil(node.animationStates[.opacity])
            let identity = node.retainedViewIdentity
            node.retainedViewIdentity = identity
        }
        try fixture.introduce([1])

        _ = fixture.host.layout()

        let event = try XCTUnwrap(fixture.probe.events[1])
        let first = try fixture.actual(row: 1, leaf: 0)
        let attempts = fixture.probe.attachAttempts.compactMap { $0 }
        let descriptorAttempts = fixture.probe.attachDescriptorAttempts.compactMap { $0 }
        XCTAssertEqual(fixture.host.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertEqual(fixture.host.runtime.lastLazyListConsumedElements, 4)
        XCTAssertEqual(fixture.probe.attachCalls, [0, 0, 0, 0])
        XCTAssertEqual(attempts.count, 4)
        XCTAssertEqual(descriptorAttempts.count, 4)
        XCTAssertEqual(Set(attempts.map(ObjectIdentifier.init)).count, 4)
        XCTAssertEqual(Set(descriptorAttempts.map(ObjectIdentifier.init)).count, 4)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
        XCTAssertFalse(event.isPending)
        XCTAssertEqual(fixture.probe.events.count, 1)
        XCTAssertNil(fixture.host.find(managedInsertionBoundaryIdentifier(1, 1)))
        assertUnanimated(first)
        XCTAssertEqual(fixture.clockReads, 0)

        fixture.probe.onAttach = nil
        withAnimation(.linear(duration: 9)) { fixture.host.reload() }
        XCTAssertNotNil(fixture.host.layout())

        XCTAssertEqual(fixture.probe.attachCalls, [0, 0, 0, 0, 0, 1])
        let completedAttempts = fixture.probe.attachAttempts.compactMap { $0 }
        let completedDescriptorAttempts = fixture.probe.attachDescriptorAttempts.compactMap { $0 }
        XCTAssertEqual(completedAttempts.count, 6)
        XCTAssertEqual(completedDescriptorAttempts.count, 6)
        XCTAssertEqual(Set(completedAttempts.map(ObjectIdentifier.init)).count, 5)
        XCTAssertEqual(Set(completedDescriptorAttempts.map(ObjectIdentifier.init)).count, 5)
        XCTAssertEqual(
            completedAttempts.suffix(2).map(ObjectIdentifier.init).first,
            completedAttempts.suffix(2).map(ObjectIdentifier.init).last)
        XCTAssertEqual(
            completedDescriptorAttempts.suffix(2).map(ObjectIdentifier.init).first,
            completedDescriptorAttempts.suffix(2).map(ObjectIdentifier.init).last)
        XCTAssertTrue(try fixture.actual(row: 1, leaf: 0) === first)
        assertUnanimated(first)
        assertUnanimated(try fixture.actual(row: 1, leaf: 1))
        XCTAssertTrue(fixture.probe.events[1] === event)
        XCTAssertFalse(event.isPending)
        XCTAssertEqual(fixture.clockReads, 0)
        XCTAssertEqual(try fixture.host.list().retainedLazyListAdapter?.mountedRecordCount, 1)
        try fixture.host.assertCommittedDescriptor()
    }

    func testMatchedPropertyPublicationClaimsBeforeItsOutgoingModifierCaptureIsDestroyed() async throws {
        let fixture = ManagedInsertionBoundaryFixture()
        defer { fixture.close() }
        try fixture.introduce([1])
        XCTAssertNotNil(fixture.host.layout())
        let original = try fixture.actual(row: 1, leaf: 0)
        let firstEvent = try XCTUnwrap(fixture.probe.events[1])
        _ = fixture.host.runtime.tickAnimations(at: 14.01)
        assertUnanimated(original)
        let originalClockReads = fixture.clockReads
        var destructions = 0
        var sawClaimedReplacement = false
        installManagedInsertionBoundaryModifier(on: original) {
            destructions += 1
            if let replacement = fixture.probe.events[1] {
                sawClaimedReplacement = replacement !== firstEvent && !replacement.isPending
            }
            let identity = original.retainedViewIdentity
            original.retainedViewIdentity = identity
        }

        fixture.probe.rows = []
        fixture.host.reload()
        XCTAssertTrue(try fixture.actual(row: 1, leaf: 0) === original)
        fixture.probe.events.removeAll()
        try fixture.introduce([1])

        _ = fixture.host.layout()

        XCTAssertEqual(destructions, 1)
        XCTAssertTrue(sawClaimedReplacement, "The accepted field must claim before its old payload unwinds")
        XCTAssertTrue(try fixture.actual(row: 1, leaf: 0) === original)
        assertUnanimated(original)
        XCTAssertFalse(try XCTUnwrap(fixture.probe.events[1]).isPending)
        XCTAssertEqual(fixture.clockReads, originalClockReads, "Rejected completion cannot sample insertion time")

        fixture.host.reload()
        XCTAssertNotNil(fixture.host.layout())
        XCTAssertTrue(try fixture.actual(row: 1, leaf: 0) === original)
        assertUnanimated(original)
        XCTAssertEqual(fixture.clockReads, originalClockReads)
    }

    func testClockConfigurationABARejectsAllPresentationWritesWithoutReturningTheClaim() async throws {
        let fixture = ManagedInsertionBoundaryFixture()
        defer { fixture.close() }
        try fixture.introduce([1])
        var sampled = 0
        fixture.host.runtime.clock = {
            sampled += 1
            if let first = fixture.host.find(managedInsertionBoundaryIdentifier(1, 0)) {
                let transition = first.transition
                first.transition = transition
            }
            return 12
        }

        _ = fixture.host.layout()

        XCTAssertEqual(sampled, 1)
        let first = try fixture.actual(row: 1, leaf: 0)
        let second = try fixture.actual(row: 1, leaf: 1)
        assertUnanimated(first)
        assertUnanimated(second)
        XCTAssertFalse(try XCTUnwrap(fixture.probe.events[1]).isPending)
        XCTAssertTrue(first.didPlayInsertionTransition)
        XCTAssertTrue(second.didPlayInsertionTransition)

        fixture.installCountingClock()
        fixture.host.reload()
        XCTAssertNotNil(fixture.host.layout())
        XCTAssertTrue(try fixture.actual(row: 1, leaf: 0) === first)
        assertUnanimated(first)
        assertUnanimated(try fixture.actual(row: 1, leaf: 1))
        XCTAssertEqual(fixture.clockReads, 0)
    }

    func testClockCaptureDestructionIsCheckedBeforeTheFirstPresentationWrite() async throws {
        let fixture = ManagedInsertionBoundaryFixture()
        defer { fixture.close() }
        try fixture.introduce([1])
        let cleanup = ManagedInsertionBoundaryCleanupProbe()
        installManagedInsertionBoundaryClock(on: fixture.host.runtime, fixture: fixture, cleanup: cleanup)

        _ = fixture.host.layout()

        XCTAssertEqual(cleanup.clockCalls, 1)
        XCTAssertEqual(cleanup.destructorCalls, 1, "The last captured payload must unwind before post-clock proof")
        XCTAssertTrue(cleanup.sawUnanimatedLeaves)
        assertUnanimated(try fixture.actual(row: 1, leaf: 0))
        assertUnanimated(try fixture.actual(row: 1, leaf: 1))
        XCTAssertFalse(try XCTUnwrap(fixture.probe.events[1]).isPending)
    }

    func testNonfiniteClockConsumesTheAcceptedArrivalWithoutPublishingATween() async throws {
        for timestamp in [Double.nan, Double.infinity, -Double.infinity] {
            let fixture = ManagedInsertionBoundaryFixture()
            defer { fixture.close() }
            try fixture.introduce([1])
            var sampled = 0
            fixture.host.runtime.clock = {
                sampled += 1
                return timestamp
            }

            _ = fixture.host.layout()

            XCTAssertEqual(sampled, 1)
            assertUnanimated(try fixture.actual(row: 1, leaf: 0))
            assertUnanimated(try fixture.actual(row: 1, leaf: 1))
            XCTAssertFalse(try XCTUnwrap(fixture.probe.events[1]).isPending)
            fixture.installCountingClock()
            fixture.host.reload()
            XCTAssertNotNil(fixture.host.layout())
            assertUnanimated(try fixture.actual(row: 1, leaf: 0))
            assertUnanimated(try fixture.actual(row: 1, leaf: 1))
            XCTAssertEqual(fixture.clockReads, 0)
        }
    }

    func testClockAuthoredAnimationChangeIsNotOverwrittenByAnObsoletePlan() async throws {
        let fixture = ManagedInsertionBoundaryFixture()
        defer { fixture.close() }
        fixture.probe.seedOutlineAnimation = true
        try fixture.introduce([1])
        var sampled = 0
        fixture.host.runtime.clock = {
            sampled += 1
            fixture.host.find(managedInsertionBoundaryIdentifier(1, 0))?.animationStates[.outlineWidth] =
                AnimationState(startValue: 4, endValue: 99, startTime: 12, duration: 8, easing: .linear)
            return 12
        }

        _ = fixture.host.layout()

        XCTAssertEqual(sampled, 1)
        let first = try fixture.actual(row: 1, leaf: 0)
        let second = try fixture.actual(row: 1, leaf: 1)
        XCTAssertEqual(first.animationStates[.outlineWidth]?.endValue, 99)
        XCTAssertEqual(first.animationStates[.outlineWidth]?.duration, 8)
        XCTAssertEqual(second.animationStates[.outlineWidth]?.endValue, 6)
        assertUnanimated(first)
        assertUnanimated(second)
        XCTAssertFalse(try XCTUnwrap(fixture.probe.events[1]).isPending)
    }

    func testReorderingAcceptedRowsDoesNotCreateAnotherArrival() async throws {
        let fixture = ManagedInsertionBoundaryFixture()
        defer { fixture.close() }
        try fixture.introduce([1, 2])
        XCTAssertNotNil(fixture.host.layout())
        let first = try fixture.actual(row: 1, leaf: 0)
        let second = try fixture.actual(row: 2, leaf: 0)
        let firstInsertion = try XCTUnwrap(first.animationStates[.opacity])
        let secondInsertion = try XCTUnwrap(second.animationStates[.opacity])
        _ = fixture.host.runtime.tickAnimations(at: 13)
        let sampled = fixture.clockReads

        fixture.probe.rows = [2, 1]
        withAnimation(.linear(duration: 9)) { fixture.host.reload() }
        XCTAssertNotNil(fixture.host.layout())

        XCTAssertTrue(try fixture.actual(row: 1, leaf: 0) === first)
        XCTAssertTrue(try fixture.actual(row: 2, leaf: 0) === second)
        XCTAssertEqual(first.animationStates[.opacity]?.startTime, firstInsertion.startTime)
        XCTAssertEqual(second.animationStates[.opacity]?.startTime, secondInsertion.startTime)
        XCTAssertEqual(first.animationStates[.opacity]?.duration, 2)
        XCTAssertEqual(second.animationStates[.opacity]?.duration, 2)
        XCTAssertEqual(fixture.clockReads, sampled)
        XCTAssertEqual(first.opacity, 0.4, accuracy: 0.0001)
        XCTAssertEqual(second.opacity, 0.4, accuracy: 0.0001)
    }

    private func assertUnanimated(_ node: ViewNode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(node.animationStates[.opacity], file: file, line: line)
        XCTAssertEqual(node.opacity, 0.8, accuracy: 0.0001, file: file, line: line)
    }
}

@MainActor
private final class ManagedInsertionBoundaryProbe {
    var rows: [Int] = []
    let nestedChild: Bool
    var rejectPreparation = false
    var seedOutlineAnimation = false
    var modifierCalls = 0
    var attachCalls: [Int] = []
    var attachAttempts: [RetainedLazyListAttemptID?] = []
    var attachDescriptorAttempts: [RetainedLazyListAttemptID?] = []
    weak var adapter: RetainedLazyListRuntimeAdapter?
    var events: [Int: RetainedLazyListInsertionEvent] = [:]
    var onAttach: ((Int, Int, ViewNode) -> Void)?

    init(nestedChild: Bool) { self.nestedChild = nestedChild }

    func makeNode(row: Int, leaf: Int, context: ViewBuildContext) -> ViewNode {
        if let token = context.viewIdentity.lazyList?.native.rowRequest.token,
            events[row] == nil, let event = adapter?.pendingInsertionEvent(for: token)
        {
            events[row] = event
        }
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20))
        node.opacity = 0.8
        node.accessibilityIdentifier = managedInsertionBoundaryIdentifier(row, leaf)
        node.transition = RetainedTransition(
            kind: .asymmetric(insertion: .init(kind: .opacity), removal: .identity))
        node.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: { [weak self, weak node] _ in
                guard let self, let node else { return }
                modifierCalls += 1
                if rejectPreparation {
                    let transition = node.transition
                    node.transition = transition
                }
            })
        ]
        if seedOutlineAnimation {
            node.animationStates[.outlineWidth] = AnimationState(
                startValue: 2, endValue: 6, startTime: 1, duration: 100, easing: .linear)
        }
        node.textInputController = ManagedInsertionBoundaryController(
            probe: self, row: row, leaf: leaf, attempt: context.viewIdentity.lazyList?.native.attempt,
            descriptorAttempt: context.viewIdentity.lazyList?.native.descriptorBuildAttemptID)
        if nestedChild, leaf == 0 {
            node.frame.size.height = 40
            node.addChild(makeNode(row: row, leaf: 1, context: context))
        }
        return node
    }
}

@MainActor
private struct ManagedInsertionBoundaryLeaf: View {
    typealias Body = Never
    let probe: ManagedInsertionBoundaryProbe
    let row: Int
    let leaf: Int
    var body: Never { fatalError("Primitive") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in probe.makeNode(row: row, leaf: leaf, context: context) }
    }
}

@MainActor
private final class ManagedInsertionBoundaryController: RetainedTextInputController {
    private weak var probe: ManagedInsertionBoundaryProbe?
    private let row: Int
    private let leaf: Int
    private let attempt: RetainedLazyListAttemptID?
    private let descriptorAttempt: RetainedLazyListAttemptID?

    init(
        probe: ManagedInsertionBoundaryProbe, row: Int, leaf: Int,
        attempt: RetainedLazyListAttemptID?, descriptorAttempt: RetainedLazyListAttemptID?
    ) {
        self.probe = probe
        self.row = row
        self.leaf = leaf
        self.attempt = attempt
        self.descriptorAttempt = descriptorAttempt
    }

    func attach(to node: ViewNode) {
        probe?.attachCalls.append(leaf)
        probe?.attachAttempts.append(attempt)
        probe?.attachDescriptorAttempts.append(descriptorAttempt)
        probe?.onAttach?(row, leaf, node)
    }
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func detach(from node: ViewNode) {}
}

@MainActor
private final class ManagedInsertionBoundaryFixture {
    let probe: ManagedInsertionBoundaryProbe
    let host: MountedLazyListTestHost
    private(set) var clockReads = 0

    init(nestedChild: Bool = false) {
        let probe = ManagedInsertionBoundaryProbe(nestedChild: nestedChild)
        self.probe = probe
        host = MountedLazyListTestHost(size: Size(width: 140, height: 80)) {
            ManagedLazyListContent(
                probe.rows, id: \.self, estimatedExtent: 40, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
            ) { row in
                ManagedInsertionBoundaryLeaf(probe: probe, row: row, leaf: 0)
                if !probe.nestedChild { ManagedInsertionBoundaryLeaf(probe: probe, row: row, leaf: 1) }
            }
        }
        installCountingClock()
        XCTAssertNotNil(host.layout())
    }

    func introduce(_ rows: [Int]) throws {
        probe.rows = rows
        withAnimation(.linear(duration: 2)) { host.reload() }
        probe.adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        XCTAssertTrue(probe.events.isEmpty, "Accepting the descriptor must not call the row factory")
    }

    func installCountingClock() {
        host.runtime.clock = { [weak self] in
            self?.clockReads += 1
            return 12
        }
    }

    func actual(row: Int, leaf: Int, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        try XCTUnwrap(host.find(managedInsertionBoundaryIdentifier(row, leaf)), file: file, line: line)
    }

    func close() {
        probe.onAttach = nil
        host.runtime.clock = { 0 }
        host.close()
        probe.events.removeAll()
    }
}

private func managedInsertionBoundaryIdentifier(_ row: Int, _ leaf: Int) -> String {
    "managed.insertion.boundary.\(row).\(leaf)"
}

@MainActor
private final class ManagedInsertionBoundaryCleanupProbe {
    var clockCalls = 0
    var destructorCalls = 0
    var sawUnanimatedLeaves = false
}

private final class ManagedInsertionBoundaryDeinitAction {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    deinit { MainActor.assumeIsolated { [action] in action() } }
}

@MainActor
@inline(never)
private func installManagedInsertionBoundaryModifier(on node: ViewNode, action: @escaping @MainActor () -> Void) {
    let payload = ManagedInsertionBoundaryDeinitAction(action)
    node.reconcileAnimationModifiers = [
        RetainedAnimationModifier(transaction: { [payload] _ in withExtendedLifetime(payload) {} })
    ]
}

@MainActor
@inline(never)
private func installManagedInsertionBoundaryClock(
    on runtime: RetainedViewRuntime, fixture: ManagedInsertionBoundaryFixture,
    cleanup: ManagedInsertionBoundaryCleanupProbe
) {
    let payload = ManagedInsertionBoundaryDeinitAction { [weak fixture] in
        cleanup.destructorCalls += 1
        guard let fixture,
            let first = fixture.host.find(managedInsertionBoundaryIdentifier(1, 0)),
            let second = fixture.host.find(managedInsertionBoundaryIdentifier(1, 1))
        else { return }
        cleanup.sawUnanimatedLeaves = first.animationStates[.opacity] == nil && second.animationStates[.opacity] == nil
        let transition = first.transition
        first.transition = transition
    }
    runtime.clock = { [weak runtime, payload] in
        cleanup.clockCalls += 1
        runtime?.clock = { 12 }
        withExtendedLifetime(payload) {}
        return 12
    }
}
