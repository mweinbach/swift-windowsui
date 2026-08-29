import SwiftWindowsCore
import SwiftWindowsUI
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class MountedObserverAnchorGuardTests: XCTestCase {
    func testAnchoredCoordinatorEntryRejectsCloseAndSupersessionBeforeEitherFactory() async throws {
        for api in AnchorGuardAPI.allCases {
            let trace = try exerciseStage(api: api, point: .entry)
            let firstAnchorHash = try XCTUnwrap(trace.sites.firstIndex(of: .anchor)) + 1
            for mutation in [AnchorGuardMutation.close, .supersede] {
                _ = try exerciseStage(api: api, point: .entry, mutation: mutation, atHash: firstAnchorHash)
            }
        }
    }

    func testAnchoredFinalOwnerAndCellValidationRejectsEveryAuthoredHashReentry() async throws {
        for api in AnchorGuardAPI.allCases {
            let trace = try exerciseStage(api: api, point: .finalAdmission)
            try requireBoundedHashes(trace)
            for ordinal in 1...trace.sites.count {
                for mutation in AnchorGuardMutation.allCases {
                    _ = try exerciseStage(api: api, point: .finalAdmission, mutation: mutation, atHash: ordinal)
                }
            }
        }
    }

    func testAnchoredPreservationFallbackRechecksCancellationAndKeepsNestedOrdinaryState() async throws {
        let trace = try exerciseStage(api: .seeded, point: .fallback)
        try requireBoundedHashes(trace)
        for ordinal in 1...trace.sites.count {
            for mutation in AnchorGuardMutation.allCases {
                _ = try exerciseStage(api: .seeded, point: .fallback, mutation: mutation, atHash: ordinal)
            }
        }
    }

    func testAnchoredGuardSnapshotCleanupRechecksCloseSupersessionAndOrdinaryMutation() async throws {
        for api in AnchorGuardAPI.allCases {
            let trace = try exerciseStage(api: api, point: .finalAdmission)
            let firstOwnerHash = try XCTUnwrap(trace.sites.firstIndex(of: .observer)) + 1
            // The compatibility guard reads candidate owners, while the typed
            // cell guard also reads provisional cells. Each victim matches a
            // map the selected guard must keep alive during its authored hash.
            let victims: [AnchorGuardVictim]
            if api == .legacy {
                victims = [.ownerIdentity]
            } else {
                victims = [.ownerIdentity, .cellPayload]
            }
            for victim in victims {
                for mutation in AnchorGuardMutation.allCases {
                    try exerciseSnapshotCleanup(api: api, victim: victim, mutation: mutation, atHash: firstOwnerHash)
                }
            }
        }
    }

    private func requireBoundedHashes(_ trace: AnchorGuardTrace) throws {
        XCTAssertGreaterThan(trace.sites.count, 0, "The real anchored guard must reach an authored hash")
        XCTAssertLessThanOrEqual(trace.sites.count, 128, "Keep the phase-local sweep bounded")
        guard !trace.sites.isEmpty, trace.sites.count <= 128 else { throw AnchorGuardFailure.unboundedTrace }
    }

    @discardableResult
    private func exerciseStage(
        api: AnchorGuardAPI, point: AnchorGuardPoint, mutation: AnchorGuardMutation? = nil, atHash ordinal: Int? = nil
    ) throws -> AnchorGuardTrace {
        let fixture = try AnchorGuardFixture()
        defer { fixture.close() }
        var reentries = 0
        var nested: (owner: StateMountOwner, cell: MountedStateCell<Int>)?
        let action: (@MainActor () -> Void)?
        if let mutation {
            action = {
                reentries += 1
                switch mutation {
                case .close: fixture.coordinator.close()
                case .supersede: fixture.build.supersede()
                case .ordinaryMapMutation: nested = fixture.resolveNestedOrdinaryState()
                }
            }
        } else {
            action = nil
        }
        let arm: @MainActor () -> Void = {
            fixture.hashing.startRecording(at: ordinal, action: action)
        }
        let afterFactory: (@MainActor () -> Void)?
        if point == .entry {
            arm()
            afterFactory = nil
        } else {
            afterFactory = arm
        }
        fixture.stage(api: api, afterFactory: afterFactory, declinesUpdate: point == .fallback)
        // A missed ordinal must not stay armed through ordinary canAdopt,
        // lease creation, adoption, abandonment, or registry teardown.
        let trace = fixture.hashing.finishRecording()
        let label = "\(api), \(point), \(String(describing: mutation)), hash \(String(describing: ordinal))"

        XCTAssertEqual(fixture.events.seeds, 0, "The committed observation is reused: \(label)")
        XCTAssertEqual(fixture.events.factories, point == .entry && mutation != nil ? 0 : 1, label)
        fixture.events.assertNoObserverCallbacks()
        if let mutation {
            XCTAssertEqual(reentries, 1, label)
            XCTAssertEqual(trace.invocations, 1, label)
            XCTAssertEqual(trace.firedAt, ordinal, label)
            try finishRejectedStage(in: fixture, mutation: mutation, nested: nested, label: label)
        } else {
            XCTAssertEqual(reentries, 0, label)
            XCTAssertEqual(trace.invocations, 0, label)
            XCTAssertTrue(fixture.build.canAdopt)
            try fixture.acceptBuild()
            if point == .fallback {
                XCTAssertEqual(fixture.events.cell?.readValue().baseline?.number, 10)
                fixture.events.assertNoObserverCallbacks()
            } else {
                XCTAssertEqual(fixture.events.cell?.readValue().baseline?.number, 20)
                XCTAssertEqual(fixture.events.commits, 1)
                XCTAssertEqual(fixture.events.deliveries, 1)
                XCTAssertEqual(fixture.events.comparisons, [[10, 20]])
                XCTAssertEqual(fixture.events.actions, [20])
            }
            fixture.close()
            XCTAssertNil(fixture.events.update)
            XCTAssertEqual(fixture.coordinator.registry.liveOwnerCount, 0)
            XCTAssertEqual(fixture.coordinator.registry.retiringOwnerCount, 0)
        }
        return trace
    }

    private func finishRejectedStage(
        in fixture: AnchorGuardFixture, mutation: AnchorGuardMutation,
        nested: (owner: StateMountOwner, cell: MountedStateCell<Int>)?, label: String
    ) throws {
        let originalCell = try XCTUnwrap(fixture.events.cell)
        XCTAssertEqual(originalCell.readValue().baseline?.number, 10, label)
        fixture.events.assertNoObserverCallbacks()
        if mutation == .ordinaryMapMutation {
            XCTAssertTrue(fixture.build.canAdopt, "Ordinary map mutation does not cancel the subtree: \(label)")
            let nested = try XCTUnwrap(nested)
            try fixture.acceptBuild()
            fixture.events.assertNoObserverCallbacks()
            XCTAssertTrue(fixture.coordinator.registry.owner(at: fixture.nestedIdentity) === nested.owner, label)
            XCTAssertTrue(nested.owner.isLive, label)
            XCTAssertTrue(nested.cell.isWritable, label)
            XCTAssertEqual(nested.cell.readValue(), 47, label)
            XCTAssertTrue(nested.cell.write(48), label)
            XCTAssertEqual(fixture.events.invalidations, 1, "The adopted nested cell must invalidate its real host")
            XCTAssertTrue(originalCell.isWritable, label)
            XCTAssertEqual(originalCell.readValue().baseline?.number, 10, label)
            XCTAssertNil(fixture.events.update, "The rejected proposal must not remain in the finished batch")

            try fixture.beginSubtree()
            fixture.events.resetCounters()
            fixture.stage(api: .seeded, value: 30)
            try fixture.acceptBuild()
            XCTAssertTrue(fixture.events.cell === originalCell, label)
            XCTAssertEqual(originalCell.readValue().baseline?.number, 30, label)
            XCTAssertEqual(fixture.events.commits, 1, label)
            XCTAssertEqual(fixture.events.deliveries, 1, label)
            XCTAssertEqual(fixture.events.comparisons, [[10, 30]], label)
            XCTAssertEqual(fixture.events.actions, [30], label)
        } else {
            XCTAssertFalse(fixture.build.canAdopt, label)
            XCTAssertEqual(fixture.coordinator.registry.isClosed, mutation == .close, label)
            fixture.abandonBuild()
            fixture.events.assertNoObserverCallbacks()
            XCTAssertEqual(originalCell.readValue().baseline?.number, 10, label)
            XCTAssertEqual(originalCell.isWritable, mutation == .supersede, label)
            XCTAssertEqual(fixture.coordinator.registry.retiringOwnerCount, 0, label)
            if mutation == .supersede {
                XCTAssertTrue(fixture.anchor.isLive, label)
                XCTAssertTrue(fixture.lease.canBuild, label)
            }
        }
        fixture.close()
        XCTAssertNil(fixture.events.update, label)
        XCTAssertEqual(fixture.coordinator.registry.liveOwnerCount, 0, label)
        XCTAssertEqual(fixture.coordinator.registry.retiringOwnerCount, 0, label)
    }

    private func exerciseSnapshotCleanup(
        api: AnchorGuardAPI, victim kind: AnchorGuardVictim, mutation: AnchorGuardMutation, atHash ordinal: Int
    ) throws {
        let fixture = try AnchorGuardFixture()
        let cleanup = AnchorGuardCleanupHook()
        defer {
            fixture.hashing.disarm()
            cleanup.disarm()
            fixture.close()
        }
        let victim = try installVictim(kind, in: fixture, cleanup: cleanup)
        var order: [AnchorGuardCleanupStep] = []
        var pinnedAfterDiscard = false
        var nested: (owner: StateMountOwner, cell: MountedStateCell<Int>)?
        var lateSeeds = 0
        var lateFactories = 0
        var lateResolutionRejected: Bool?
        cleanup.arm {
            order.append(.cleanup)
            switch mutation {
            case .close: fixture.coordinator.close()
            case .supersede: fixture.build.supersede()
            case .ordinaryMapMutation: nested = fixture.resolveNestedOrdinaryState()
            }
            if mutation != .ordinaryMapMutation {
                let late = fixture.epoch.resolveSyntheticObservation(at: fixture.lateIdentity) {
                    lateSeeds += 1
                    return AnchorGuardObservation()
                }
                lateResolutionRejected = late == nil
                fixture.coordinator.stageOnChange(
                    at: fixture.lateIdentity,
                    seedObservation: {
                        lateSeeds += 1
                        return AnchorGuardObservation()
                    },
                    makeUpdate: { _, _ in
                        lateFactories += 1
                        return nil
                    })
            }
        }
        fixture.stage(
            api: api,
            afterFactory: {
                fixture.hashing.startRecording(at: ordinal) {
                    order.append(.hash)
                    fixture.epoch.discardUnadoptedSubtree(at: fixture.victimPrefix, preserveCommitted: false)
                    // Only the guard's outgoing dictionary snapshots may keep
                    // these weakly held objects alive after ordinary discard.
                    if kind == .ownerIdentity {
                        pinnedAfterDiscard = victim.owner != nil && victim.payload != nil
                    } else {
                        pinnedAfterDiscard = victim.cell != nil && victim.payload != nil
                    }
                    order.append(.discardReturned)
                }
            })
        let trace = fixture.hashing.finishRecording()
        cleanup.disarm()
        order.append(.stageReturned)
        let label = "\(api), \(kind), \(mutation)"

        XCTAssertEqual(trace.firedAt, ordinal, label)
        XCTAssertEqual(trace.invocations, 1, label)
        XCTAssertTrue(pinnedAfterDiscard, "Exercise snapshot release after discard, not release inside it: \(label)")
        XCTAssertEqual(cleanup.invocations, 1, label)
        XCTAssertEqual(order, [.hash, .discardReturned, .cleanup, .stageReturned], label)
        XCTAssertNil(victim.owner, label)
        XCTAssertNil(victim.cell, label)
        XCTAssertNil(victim.payload, label)
        XCTAssertEqual(fixture.events.seeds, 0, label)
        XCTAssertEqual(fixture.events.factories, 1, label)
        XCTAssertEqual(lateSeeds, 0, label)
        XCTAssertEqual(lateFactories, 0, label)
        if mutation != .ordinaryMapMutation { XCTAssertEqual(lateResolutionRejected, true, label) }
        fixture.events.assertNoObserverCallbacks()
        let visited = fixture.epoch.visitedOwnerIdentities
        XCTAssertFalse(visited.contains { $0.segments.starts(with: fixture.victimPrefix.segments) }, label)
        XCTAssertFalse(visited.contains(fixture.lateIdentity), label)
        try finishRejectedStage(in: fixture, mutation: mutation, nested: nested, label: label)
    }

    private func installVictim(
        _ kind: AnchorGuardVictim, in fixture: AnchorGuardFixture, cleanup: AnchorGuardCleanupHook
    ) throws -> AnchorGuardWeakVictim {
        let payload = AnchorGuardReleaseProbe { cleanup.fire() }
        let identity: RetainedViewIdentity
        if kind == .ownerIdentity {
            identity = fixture.victimPrefix.appending(
                .explicit(.init(AnchorGuardLifetimeKey(value: 7, payload: payload))))
        } else {
            identity = fixture.victimPrefix
        }
        let owner = try XCTUnwrap(fixture.epoch.owner(at: identity))
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(AnchorGuardVictimSlot.self)])
        if kind == .cellPayload {
            let cell = owner.resolve(at: slot) { payload }
            return AnchorGuardWeakVictim(owner: owner, cell: cell, payload: payload)
        }
        let cell = owner.resolve(at: slot) { 29 }
        return AnchorGuardWeakVictim(owner: owner, cell: cell, payload: payload)
    }
}

private enum AnchorGuardAPI: CaseIterable, Equatable {
    case legacy
    case seeded
}

private enum AnchorGuardPoint: Equatable {
    case entry
    case finalAdmission
    case fallback
}

private enum AnchorGuardMutation: CaseIterable, Equatable {
    case close
    case supersede
    case ordinaryMapMutation
}

private enum AnchorGuardHashSite: Hashable {
    case anchor
    case observer
}

private enum AnchorGuardVictim: Equatable {
    case ownerIdentity
    case cellPayload
}

private enum AnchorGuardCleanupStep: Equatable {
    case hash
    case discardReturned
    case cleanup
    case stageReturned
}

private enum AnchorGuardFailure: Error {
    case rejectedPreparation
    case unfinishedBuild
    case unboundedTrace
}

private enum AnchorGuardRoot {}
private enum AnchorGuardNestedSlot {}
private enum AnchorGuardVictimSlot {}

private struct AnchorGuardTrace {
    let sites: [AnchorGuardHashSite]
    let firedAt: Int?
    let invocations: Int
}

@MainActor
private final class AnchorGuardFixture {
    let events: AnchorGuardEvents
    let hashing: AnchorGuardHashHook
    let coordinator: StateMountCoordinator
    let anchor: StateMountOwner
    private(set) var lease: any RetainedSubtreeBuildLease
    let contentPrefix: RetainedViewIdentity
    let observerIdentity: RetainedViewIdentity
    let nestedIdentity: RetainedViewIdentity
    let victimPrefix: RetainedViewIdentity
    let lateIdentity: RetainedViewIdentity
    private(set) var build: any RetainedBuildEpoch
    private(set) var epoch: StateMountEpoch
    private var pendingLease: (any RetainedSubtreeBuildLease)?
    private var didFinish = false

    init() throws {
        let events = AnchorGuardEvents()
        self.events = events
        let hashing = AnchorGuardHashHook()
        self.hashing = hashing
        let coordinator = StateMountCoordinator(
            invalidate: { events.invalidations += 1 }, observeObject: { _ in },
            updateObservedObjects: { _, _, _ in })
        self.coordinator = coordinator
        let anchorIdentity = RetainedViewIdentity(segments: [
            .view(ObjectIdentifier(AnchorGuardRoot.self)),
            .explicit(.init(AnchorGuardHashKey(value: 1, site: .anchor, hashing: hashing))),
        ])
        let contentPrefix = anchorIdentity.appending(.role(.geometryContent))
        self.contentPrefix = contentPrefix
        observerIdentity = contentPrefix.appending(.slot(0)).appending(
            .explicit(.init(AnchorGuardHashKey(value: 2, site: .observer, hashing: hashing))))
        nestedIdentity = contentPrefix.appending(.slot(2))
        victimPrefix = contentPrefix.appending(.slot(3))
        lateIdentity = contentPrefix.appending(.slot(4))
        build = try XCTUnwrap(coordinator.beginBuild())
        var capturedOwner: StateMountOwner?
        var capturedEpoch: StateMountEpoch?
        var capturedLease: (any RetainedSubtreeBuildLease)?
        // All ordinary installation, lease creation, and root adoption happen
        // unarmed. The test callback belongs only to observer construction.
        coordinator.stageOnChange(at: anchorIdentity) { owner in
            capturedOwner = owner
            capturedEpoch = owner.installationEpoch
            let lease = coordinator.subtreeLease(owner: owner, contentPrefix: contentPrefix)
            coordinator.materializeSubtreeLease(lease)
            capturedLease = lease
            return AnchorGuardNoopUpdate(owner: owner)
        }
        anchor = try XCTUnwrap(capturedOwner)
        epoch = try XCTUnwrap(capturedEpoch)
        lease = try XCTUnwrap(capturedLease)
        stage(api: .seeded, value: 10)
        try acceptBuild()
        XCTAssertTrue(anchor.isLive)
        XCTAssertTrue(lease.canBuild)
        XCTAssertEqual(events.cell?.readValue().baseline?.number, 10)
        try beginSubtree()
        events.resetCounters()
    }

    func beginSubtree() throws {
        hashing.disarm()
        guard didFinish else { throw AnchorGuardFailure.unfinishedBuild }
        build = try XCTUnwrap(lease.beginBuild())
        didFinish = false
        // Adoption replaces a materialized boundary lease. Keep the accepted
        // lease authoritative until commit, so an abandoned subtree can retry.
        let pendingLease = coordinator.subtreeLease(owner: anchor, contentPrefix: contentPrefix)
        coordinator.materializeSubtreeLease(pendingLease)
        self.pendingLease = pendingLease
        var capturedEpoch: StateMountEpoch?
        coordinator.stageOnChange(at: contentPrefix.appending(.slot(1))) { owner in
            capturedEpoch = owner.installationEpoch
            return AnchorGuardNoopUpdate(owner: owner)
        }
        epoch = try XCTUnwrap(capturedEpoch)
    }

    func stage(
        api: AnchorGuardAPI, value: Int = 20, afterFactory: (@MainActor () -> Void)? = nil,
        declinesUpdate: Bool = false
    ) {
        switch api {
        case .legacy:
            coordinator.stageOnChange(at: observerIdentity) { owner in
                self.events.factories += 1
                let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(AnchorGuardObservation.self)])
                let cell = owner.resolve(at: slot) {
                    self.events.seeds += 1
                    return AnchorGuardObservation()
                }
                self.events.cell = cell
                let update = AnchorGuardUpdate(owner: owner, cell: cell, value: value, events: self.events)
                self.events.update = update
                afterFactory?()
                return update
            }
        case .seeded:
            coordinator.stageOnChange(
                at: observerIdentity,
                seedObservation: {
                    self.events.seeds += 1
                    return AnchorGuardObservation()
                },
                makeUpdate: { owner, cell in
                    self.events.factories += 1
                    self.events.cell = cell
                    if declinesUpdate {
                        afterFactory?()
                        return nil
                    }
                    let update = AnchorGuardUpdate(owner: owner, cell: cell, value: value, events: self.events)
                    self.events.update = update
                    afterFactory?()
                    return update
                })
        }
    }

    func resolveNestedOrdinaryState() -> (owner: StateMountOwner, cell: MountedStateCell<Int>)? {
        guard let owner = epoch.owner(at: nestedIdentity) else {
            XCTFail("The still-current anchored epoch must admit its nested ordinary owner")
            return nil
        }
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(AnchorGuardNestedSlot.self)])
        return (owner, owner.resolve(at: slot) { 47 })
    }

    func acceptBuild() throws {
        hashing.disarm()
        let prepared = build.willAdopt()
        XCTAssertTrue(prepared)
        guard prepared else { throw AnchorGuardFailure.rejectedPreparation }
        build.commit()
        XCTAssertTrue(build.canComplete)
        build.finishAfterCallbacks()
        if let pendingLease { lease = pendingLease }
        pendingLease = nil
        didFinish = true
    }

    func abandonBuild() {
        hashing.disarm()
        guard !didFinish else { return }
        build.abandon()
        build.finishAfterCallbacks()
        pendingLease = nil
        didFinish = true
    }

    func close() {
        hashing.disarm()
        coordinator.close()
        abandonBuild()
    }
}

@MainActor
private final class AnchorGuardNoopUpdate: MountedOnChangeUpdate {
    let owner: StateMountOwner

    init(owner: StateMountOwner) { self.owner = owner }

    func commit() {}
    func deliver() {}
}

@MainActor
private final class AnchorGuardEvents {
    var seeds = 0
    var factories = 0
    var commits = 0
    var deliveries = 0
    var invalidations = 0
    var comparisons: [[Int]] = []
    var actions: [Int] = []
    weak var cell: MountedStateCell<AnchorGuardObservation>?
    weak var update: AnchorGuardUpdate?

    func assertNoObserverCallbacks(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(commits, 0, file: file, line: line)
        XCTAssertEqual(deliveries, 0, file: file, line: line)
        XCTAssertEqual(comparisons, [], file: file, line: line)
        XCTAssertEqual(actions, [], file: file, line: line)
    }

    func resetCounters() {
        seeds = 0
        factories = 0
        commits = 0
        deliveries = 0
        invalidations = 0
        comparisons = []
        actions = []
    }
}

@MainActor
private final class AnchorGuardObservation {
    var baseline: AnchorGuardValue?
}

@MainActor
private final class AnchorGuardUpdate: MountedOnChangeUpdate {
    let owner: StateMountOwner
    private let cell: MountedStateCell<AnchorGuardObservation>
    private let value: AnchorGuardValue
    private let events: AnchorGuardEvents
    private var previous: AnchorGuardValue?

    init(owner: StateMountOwner, cell: MountedStateCell<AnchorGuardObservation>, value: Int, events: AnchorGuardEvents)
    {
        self.owner = owner
        self.cell = cell
        self.value = AnchorGuardValue(number: value, events: events)
        self.events = events
    }

    func commit() {
        events.commits += 1
        previous = cell.readValue().baseline
        cell.readValue().baseline = value
    }

    func deliver() {
        events.deliveries += 1
        if let previous, previous != value { events.actions.append(value.number) }
    }
}

private struct AnchorGuardValue: Equatable {
    let number: Int
    let events: AnchorGuardEvents

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.events.comparisons.append([lhs.number, rhs.number]) }
        return lhs.number == rhs.number
    }
}

@MainActor
private final class AnchorGuardHashHook {
    private var isRecording = false
    private var target: Int?
    private var action: (@MainActor () -> Void)?
    private var sites: [AnchorGuardHashSite] = []
    private var firedAt: Int?
    private var invocations = 0

    func startRecording(at target: Int? = nil, action: (@MainActor () -> Void)? = nil) {
        self.target = target
        self.action = action
        sites = []
        firedAt = nil
        invocations = 0
        isRecording = true
    }

    func finishRecording() -> AnchorGuardTrace {
        let trace = AnchorGuardTrace(sites: sites, firedAt: firedAt, invocations: invocations)
        disarm()
        return trace
    }

    func disarm() {
        isRecording = false
        target = nil
        action = nil
    }

    func record(_ site: AnchorGuardHashSite) {
        guard isRecording else { return }
        sites.append(site)
        guard sites.count == target, let action else { return }
        firedAt = sites.count
        invocations += 1
        // Disarm before reentry so nested ordinary operations cannot trigger
        // the hook while they use their unchanged installation paths.
        disarm()
        action()
    }
}

private struct AnchorGuardHashKey: Hashable {
    let value: Int
    let site: AnchorGuardHashSite
    let hashing: AnchorGuardHashHook

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value && lhs.site == rhs.site }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(site)
        MainActor.assumeIsolated { hashing.record(site) }
    }
}

@MainActor
private final class AnchorGuardCleanupHook {
    private var action: (@MainActor () -> Void)?
    private(set) var invocations = 0

    func arm(_ action: @escaping @MainActor () -> Void) { self.action = action }
    func disarm() { action = nil }

    func fire() {
        guard let action else { return }
        self.action = nil
        invocations += 1
        action()
    }
}

@MainActor
private final class AnchorGuardReleaseProbe {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

@MainActor
private final class AnchorGuardWeakVictim {
    weak var owner: StateMountOwner?
    weak var cell: AnyObject?
    weak var payload: AnchorGuardReleaseProbe?

    init(owner: StateMountOwner, cell: AnyObject, payload: AnchorGuardReleaseProbe) {
        self.owner = owner
        self.cell = cell
        self.payload = payload
    }
}

private struct AnchorGuardLifetimeKey: Hashable {
    let value: Int
    let payload: AnchorGuardReleaseProbe

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}
