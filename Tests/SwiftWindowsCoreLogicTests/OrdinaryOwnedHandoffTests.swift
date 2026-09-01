import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class OrdinaryOwnedHandoffTests: XCTestCase {
    func testMixedReplacementSuspendsContinuingSlotsAndRetiresDepartingDescendantsBeforeCallbacks() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let oldLeaf = handoffNode(11)
        let oldRoot = handoffNode(1, children: [oldLeaf])
        let retained = RetainedOwnedSlotGenerationID()
        let dropped = RetainedOwnedSlotGenerationID()
        let departing = RetainedOwnedSlotGenerationID()
        let first = OrdinaryOwnedHandoffEpoch(runtime)
        let ancestor = try first.component(nodes: [], slots: [retained, dropped])
        let descendant = try first.component(
            nodes: [oldRoot, oldLeaf], slots: [departing], parent: ancestor.attribution)
        XCTAssertTrue(first.journal.beginOrdinaryAdoption())
        runtime.root.setChildren([oldRoot], lazyJournal: first.journal)
        XCTAssertTrue(ancestor.owned.hasAcceptedOwnership(for: retained))
        XCTAssertTrue(descendant.owned.hasAcceptedOwnership(for: departing))
        _ = first.finish()

        let incomingLeaf = handoffNode(22)
        let incomingRoot = handoffNode(2, children: [incomingLeaf])
        let next = OrdinaryOwnedHandoffEpoch(runtime)
        let continued = try next.component(nodes: [], slots: [retained], continuing: ancestor.owned)
        let introduced = try next.component(
            nodes: [incomingRoot, incomingLeaf], slots: [RetainedOwnedSlotGenerationID()],
            parent: continued.attribution)
        var callbacks = 0
        oldRoot.onDismantlePlatformView = { _ in
            callbacks += 1
            XCTAssertFalse(ancestor.owned.permitsOwnedWrite(for: retained))
            XCTAssertFalse(ancestor.owned.permitsOwnedWrite(for: dropped))
            XCTAssertFalse(descendant.owned.permitsOwnedWrite(for: departing))
            XCTAssertFalse(descendant.owned.hasDeclaredComponent)
            XCTAssertTrue(ancestor.owned.hasDeclaredComponent)
            XCTAssertFalse(continued.owned.hasAcceptedDeclaration)
        }
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [incomingRoot], lazyJournal: next.journal)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(callbacks, 1)
        XCTAssertTrue(runtime.root.children.first === incomingRoot)
        XCTAssertTrue(continued.owned.hasAcceptedOwnership(for: retained))
        XCTAssertTrue(ancestor.owned.permitsOwnedWrite(for: retained))
        XCTAssertTrue(introduced.contribution.isActive)
        XCTAssertFalse(ancestor.owned.permitsOwnedWrite(for: dropped))
        XCTAssertFalse(descendant.owned.hasDeclaredComponent)
        let disposition = next.finish()
        XCTAssertEqual(disposition.retiredOwnedSlots.filter { $0 === dropped }.count, 1)
        XCTAssertEqual(disposition.retiredOwnedSlots.filter { $0 === departing }.count, 1)
        XCTAssertFalse(disposition.retiredOwnedSlots.contains { $0 === retained })
        XCTAssertFalse(disposition.retiredOwnedComponents.contains { $0 === ancestor.owned.owner })
    }

    func testAComponentWithNoSlotsSurvivesItsExactPhysicalReplacement() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let old = handoffNode(1)
        let first = OrdinaryOwnedHandoffEpoch(runtime)
        let prior = try first.component(nodes: [old], slots: [])
        XCTAssertTrue(first.journal.beginOrdinaryAdoption())
        runtime.root.setChildren([old], lazyJournal: first.journal)
        XCTAssertTrue(prior.owned.hasDeclaredComponent)
        _ = first.finish()
        let incoming = handoffNode(2)
        let next = OrdinaryOwnedHandoffEpoch(runtime)
        let continued = try next.component(nodes: [incoming], slots: [], continuing: prior.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())

        runtime.root.setChildren([incoming], lazyJournal: next.journal)

        XCTAssertTrue(prior.owned.hasDeclaredComponent)
        XCTAssertTrue(continued.owned.hasAcceptedDeclaration)
        XCTAssertTrue(continued.contribution.isActive)
        XCTAssertTrue(continued.owned.owner === prior.owned.owner)
        XCTAssertTrue(next.finish().retiredOwnedComponents.isEmpty)
    }

    func testUnpublishedContinuationCannotWriteAndAbandonRetiresItsOriginalTicketOnce() async throws {
        let fixture = try OrdinaryOwnedHandoffFixture()
        let next = OrdinaryOwnedHandoffEpoch(fixture.runtime)
        let incoming = handoffNode(2)
        let continued = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))

        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(continued.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertTrue(continued.owned.hasDeclaredComponent)
        next.journal.finishOrdinaryOwnedDeparture(ticket)
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(continued.owned.hasAcceptedDeclaration)
        next.journal.revokeBeforeAbandon()
        next.journal.finishOrdinaryOwnedDeparture(ticket)
        next.journal.revokeBeforeAbandon()

        let disposition = next.finish()
        XCTAssertFalse(continued.owned.hasDeclaredComponent)
        XCTAssertEqual(disposition.retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
        XCTAssertEqual(disposition.retiredOwnedComponents.filter { $0 === fixture.owned.owner }.count, 1)
        XCTAssertFalse(next.journal.prepareInsertedNode(from: incoming))
    }

    func testSealingAnUnpublishedContinuationDrainsTheSameCapturedDepartureOnce() async throws {
        let fixture = try OrdinaryOwnedHandoffFixture()
        let incoming = handoffNode(2)
        let next = OrdinaryOwnedHandoffEpoch(fixture.runtime)
        _ = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))

        let disposition = next.journal.seal()
        next.journal.finishOrdinaryOwnedDeparture(ticket)
        let repeated = next.journal.seal()

        XCTAssertTrue(disposition === repeated)
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(fixture.owned.hasDeclaredComponent)
        XCTAssertEqual(disposition.retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
        XCTAssertEqual(disposition.retiredOwnedComponents.filter { $0 === fixture.owned.owner }.count, 1)
        _ = next.finish()
    }

    func testAnotherAttemptCannotConsumeTheOriginalDepartureTicket() async throws {
        let fixture = try OrdinaryOwnedHandoffFixture()
        let incoming = handoffNode(2)
        let next = OrdinaryOwnedHandoffEpoch(fixture.runtime)
        _ = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))
        let foreign = OrdinaryOwnedHandoffEpoch(fixture.runtime)
        XCTAssertTrue(foreign.journal.beginOrdinaryAdoption())

        foreign.journal.finishOrdinaryOwnedDeparture(ticket)

        XCTAssertTrue(fixture.owned.hasDeclaredComponent)
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertTrue(foreign.finish().retiredOwnedSlots.isEmpty)
        XCTAssertEqual(next.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
    }

    func testPendingCleanupDoesNotClearLaterOwnershipOnTheSamePhysicalStorage() async throws {
        let fixture = try OrdinaryOwnedHandoffFixture()
        let incoming = handoffNode(2)
        let next = OrdinaryOwnedHandoffEpoch(fixture.runtime)
        let continued = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))
        let intervening = OrdinaryOwnedHandoffEpoch(fixture.runtime)
        let otherSlot = RetainedOwnedSlotGenerationID()
        let other = try intervening.component(nodes: [fixture.old], slots: [otherSlot])
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        XCTAssertTrue(intervening.journal.prepareInsertedNode(from: fixture.old))
        _ = intervening.journal.recordAcceptedInsertedNode(on: fixture.old)
        _ = intervening.journal.recordCompletedNode(from: fixture.old, to: fixture.old)
        XCTAssertTrue(other.owned.hasAcceptedOwnership(for: otherSlot))
        XCTAssertTrue(next.journal.prepareInsertedNode(from: incoming))
        fixture.runtime.root.addChild(incoming)
        _ = next.journal.recordAcceptedInsertedNode(on: incoming)
        _ = next.journal.recordCompletedNode(from: incoming, to: incoming)

        next.journal.finishOrdinaryOwnedDeparture(ticket)
        next.journal.finishOrdinaryOwnedDeparture(ticket)
        XCTAssertTrue(continued.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(other.owned.hasAcceptedOwnership(for: otherSlot))
        _ = intervening.journal.recordPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement)

        XCTAssertFalse(other.owned.permitsOwnedWrite(for: otherSlot))
        XCTAssertFalse(other.owned.hasDeclaredComponent)
        XCTAssertTrue(continued.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertEqual(intervening.finish().retiredOwnedSlots.filter { $0 === otherSlot }.count, 1)
        XCTAssertFalse(next.finish().retiredOwnedSlots.contains { $0 === fixture.slot })
    }

    func testDeclarationOnlyAndZeroSourcePlansDoNotPostponePhysicalRetirement() async throws {
        for (declarationOnly, hasSource) in [(false, false), (true, false), (true, true)] {
            let fixture = try OrdinaryOwnedHandoffFixture()
            let incoming = handoffNode(2)
            let next = OrdinaryOwnedHandoffEpoch(fixture.runtime)
            let continued = try next.component(
                nodes: hasSource ? [incoming] : [], slots: [fixture.slot], continuing: fixture.owned,
                declarationOnly: declarationOnly)
            XCTAssertTrue(next.journal.beginOrdinaryAdoption())

            XCTAssertNil(next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))

            XCTAssertFalse(continued.owned.permitsOwnedWrite(for: fixture.slot))
            XCTAssertFalse(continued.owned.hasDeclaredComponent)
            XCTAssertEqual(next.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
        }
    }

    func testDefaultPhysicalDepartureStillRetiresWithoutAnOrdinaryHandoff() async throws {
        let fixture = try OrdinaryOwnedHandoffFixture()
        let incoming = handoffNode(2)
        let next = OrdinaryOwnedHandoffEpoch(fixture.runtime)
        let continued = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())

        _ = next.journal.recordPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement)

        XCTAssertFalse(continued.owned.hasDeclaredComponent)
        XCTAssertFalse(continued.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(next.journal.prepareInsertedNode(from: incoming))
        XCTAssertEqual(next.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
    }

    func testAnIndependentAcceptedFootprintDoesNotNeedAPendingDeparture() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let left = handoffNode(1)
        let right = handoffNode(2)
        let slot = RetainedOwnedSlotGenerationID()
        let first = OrdinaryOwnedHandoffEpoch(runtime)
        let prior = try first.component(nodes: [left, right], slots: [slot])
        XCTAssertTrue(first.journal.beginOrdinaryAdoption())
        runtime.root.setChildren([left, right], lazyJournal: first.journal)
        _ = first.finish()
        let incoming = handoffNode(3)
        let next = OrdinaryOwnedHandoffEpoch(runtime)
        _ = try next.component(nodes: [incoming], slots: [slot], continuing: prior.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())

        XCTAssertNil(next.journal.recordOrdinaryPhysicalDeparture(of: left, cause: .acceptedReplacement))
        XCTAssertTrue(prior.owned.permitsOwnedWrite(for: slot))
        let final = try XCTUnwrap(next.journal.recordOrdinaryPhysicalDeparture(of: right, cause: .acceptedReplacement))
        XCTAssertFalse(prior.owned.permitsOwnedWrite(for: slot))
        XCTAssertTrue(prior.owned.hasDeclaredComponent)
        next.journal.revokeBeforeAbandon()
        next.journal.finishOrdinaryOwnedDeparture(final)

        XCTAssertEqual(next.finish().retiredOwnedSlots.filter { $0 === slot }.count, 1)
        XCTAssertFalse(prior.owned.hasDeclaredComponent)
    }

    func testAClosingDepartureCallbackCannotPublishThePreparedContinuation() async throws {
        let fixture = try OrdinaryOwnedHandoffFixture()
        let incoming = handoffNode(2)
        let next = OrdinaryOwnedHandoffEpoch(fixture.runtime)
        let continued = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        var callbacks = 0
        fixture.old.onDismantlePlatformView = { _ in
            callbacks += 1
            XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
            fixture.runtime.lazyListLogicalHostLifetime.revoke()
        }
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())

        fixture.runtime.root.setChildren([incoming], lazyJournal: next.journal)

        XCTAssertEqual(callbacks, 1)
        XCTAssertFalse(continued.owned.hasAcceptedDeclaration)
        XCTAssertFalse(continued.owned.hasDeclaredComponent)
        XCTAssertFalse(continued.contribution.isActive)
        XCTAssertFalse(continued.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertEqual(next.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
        fixture.old.onDismantlePlatformView = nil
    }

    func testPendingNativeTicketDoesNotRetainTheDepartedNodeOrAuthoredPayload() async throws {
        let probe = OrdinaryHandoffReleaseProbe()
        let (epoch, ticket, owned, slot) = try handoffWithReleasedSource(probe)

        XCTAssertNil(probe.node)
        XCTAssertNil(probe.payload)
        XCTAssertEqual(probe.releases, 1)
        XCTAssertFalse(owned.permitsOwnedWrite(for: slot))
        epoch.journal.revokeBeforeAbandon()
        epoch.journal.finishOrdinaryOwnedDeparture(ticket)
        XCTAssertEqual(epoch.finish().retiredOwnedSlots.filter { $0 === slot }.count, 1)
    }

    func testStableGroupPublishesTheFirstInsertedKeyframeFactory() async throws {
        let probe = KeyframeTestProbe()
        probe.show = false
        let host = KeyframeAnimatorTestHost {
            AnyView(Group { if probe.show { keyframeTestRepeatingView(probe) } })
        }
        defer { host.close() }
        XCTAssertTrue(probe.factoryInputs.isEmpty)
        probe.show = true

        host.reload()
        host.tick(0.3)

        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertEqual(try host.sample(), 0.3, accuracy: 0.000_001)
    }

    func testStableModifierStartsTheNewExplicitIdentityRunAtItsOwnClock() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframeTestRepeatingView(probe).id(probe.identity)) }
        defer { host.close() }
        host.tick(0.4)
        XCTAssertEqual(try host.sample(), 0.4, accuracy: 0.000_001)
        probe.identity = 1

        host.reload()
        host.tick(0.6)

        XCTAssertEqual(try host.sample(), 0.2, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 0])
    }

    func testAnInsertedFactoryCanCloseItsOwnerWithoutPublishingOrRearming() async throws {
        let probe = KeyframeTestProbe()
        probe.show = false
        let host = KeyframeAnimatorTestHost {
            AnyView(Group { if probe.show { keyframeTestRepeatingView(probe) } })
        }
        defer { host.close() }
        probe.onFactory = { [weak host] in host?.close() }
        probe.show = true

        host.reload()
        host.runtime.tickAnimations(at: 2)

        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        probe.onFactory = nil
    }

    func testInsertedFactoryCaptureReleaseCannotPublishAfterClosingItsOwner() async throws {
        let probe = KeyframeTestProbe()
        let release = OrdinaryHandoffReleaseProbe()
        probe.show = false
        let host = KeyframeAnimatorTestHost {
            AnyView(
                Group {
                    if probe.show {
                        KeyframeAnimator(initialValue: 0.0) { value in
                            keyframeTestContent(probe, value: value)
                        } keyframes: { _ in
                            let payload = OrdinaryHandoffPayload { [weak release] in
                                release?.releases += 1
                                release?.host?.close()
                            }
                            release.payload = payload
                            return OrdinaryHandoffReleasingFrames(payload: payload)
                        }
                    }
                })
        }
        defer { host.close() }
        release.host = host
        probe.show = true

        host.reload()
        host.runtime.tickAnimations(at: 2)

        XCTAssertEqual(release.releases, 1)
        XCTAssertNil(release.payload)
        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        XCTAssertTrue(probe.contentValues.allSatisfy { $0 == 0 })
    }
}

@MainActor
private func handoffNode(_ identity: Int, children: [ViewNode] = []) -> ViewNode {
    let node = ViewNode(children: children)
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private final class OrdinaryOwnedHandoffEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal

    init(_ runtime: RetainedViewRuntime) {
        self.runtime = runtime
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
    }

    func component(
        nodes: [ViewNode], slots: [RetainedOwnedSlotGenerationID], continuing: RetainedOwnedComponentReceipt? = nil,
        parent: RetainedDescriptorComponentAttribution? = nil, declarationOnly: Bool = false
    ) throws -> OrdinaryOwnedHandoffComponent {
        let attribution: RetainedDescriptorComponentAttribution
        if let parent {
            attribution = try XCTUnwrap(parent.registerChildComponent())
        } else {
            attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        }
        let owned = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: slots,
                continuing: continuing, declarationOnly: declarationOnly))
        let group = try XCTUnwrap(attribution.registerGroup(kind: .observation))
        for node in nodes { XCTAssertTrue(attribution.recordSourceOutput(node, group: group)) }
        _ = try XCTUnwrap(attribution.closeGroup(group))
        let contribution = try XCTUnwrap(attribution.contribution(for: group))
        return OrdinaryOwnedHandoffComponent(attribution: attribution, owned: owned, contribution: contribution)
    }

    @discardableResult
    func finish() -> RetainedLazyListAdoptionDisposition {
        let disposition = journal.seal(completedCheckedAdoption: true)
        journal.releaseUnadoptedTransport()
        scope.finish()
        return disposition
    }
}

@MainActor
private struct OrdinaryOwnedHandoffComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let owned: RetainedOwnedComponentReceipt
    let contribution: RetainedDescriptorContributionReceipt
}

@MainActor
private final class OrdinaryOwnedHandoffFixture {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let old = handoffNode(1)
    let slot = RetainedOwnedSlotGenerationID()
    let owned: RetainedOwnedComponentReceipt

    init() throws {
        let first = OrdinaryOwnedHandoffEpoch(runtime)
        owned = try first.component(nodes: [old], slots: [slot]).owned
        XCTAssertTrue(first.journal.beginOrdinaryAdoption())
        runtime.root.setChildren([old], lazyJournal: first.journal)
        XCTAssertTrue(owned.hasAcceptedOwnership(for: slot))
        _ = first.finish()
    }
}

@MainActor
private final class OrdinaryHandoffReleaseProbe {
    weak var node: ViewNode?
    weak var payload: OrdinaryHandoffPayload?
    weak var host: KeyframeAnimatorTestHost?
    var releases = 0
}

@MainActor
private final class OrdinaryHandoffPayload {
    let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

private struct OrdinaryHandoffReleasingFrames: Keyframes {
    typealias Value = Double
    let payload: OrdinaryHandoffPayload

    var body: some Keyframes<Double> {
        MoveKeyframe(2.0)
        LinearKeyframe(1.0, duration: 1)
    }
}

@MainActor
@inline(never)
private func handoffWithReleasedSource(
    _ probe: OrdinaryHandoffReleaseProbe
) throws -> (
    OrdinaryOwnedHandoffEpoch, RetainedOrdinaryOwnedDeparture, RetainedOwnedComponentReceipt,
    RetainedOwnedSlotGenerationID
) {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let source = handoffNode(1)
    let payload = OrdinaryHandoffPayload { [weak probe] in probe?.releases += 1 }
    probe.node = source
    probe.payload = payload
    source.onAppear = { withExtendedLifetime(payload) {} }
    let slot = RetainedOwnedSlotGenerationID()
    let first = OrdinaryOwnedHandoffEpoch(runtime)
    let prior = try first.component(nodes: [source], slots: [slot])
    XCTAssertTrue(first.journal.beginOrdinaryAdoption())
    runtime.root.setChildren([source], lazyJournal: first.journal)
    _ = first.finish()
    let incoming = handoffNode(2)
    let next = OrdinaryOwnedHandoffEpoch(runtime)
    _ = try next.component(nodes: [incoming], slots: [slot], continuing: prior.owned)
    XCTAssertTrue(next.journal.beginOrdinaryAdoption())
    let ticket = try XCTUnwrap(next.journal.recordOrdinaryPhysicalDeparture(of: source, cause: .acceptedReplacement))
    runtime.root.removeChild(source)
    return (next, ticket, prior.owned, slot)
}
