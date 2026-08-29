import SwiftWindowsCore
import SwiftWindowsUI
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class MountedObserverAdmissionTests: XCTestCase {
    func testFreshObserverRejectsCloseAndSupersessionAtEveryAuthoredHash() async throws {
        try sweepAdmissionHashes(in: .fresh)
    }

    func testProvisionalCellReuseRejectsCloseAndSupersessionAtEveryAuthoredHash() async throws {
        try sweepAdmissionHashes(in: .provisional)
    }

    func testCommittedCellReuseRejectsCloseAndSupersessionAtEveryAuthoredHash() async throws {
        try sweepAdmissionHashes(in: .committed)
    }

    func testFinalPostFactoryHashRejectsAnAlreadyConstructedUpdate() async throws {
        for scenario in ObserverAdmissionScenario.allCases {
            let trace = try runAdmission(in: scenario)
            let factoryExit = try XCTUnwrap(trace.factoryExitHash)
            XCTAssertGreaterThan(
                trace.hashes.count, factoryExit,
                "The fixture must reach a real admission hash after its factory returns")
            guard trace.hashes.count > factoryExit else { continue }
            for cancellation in ObserverAdmissionCancellation.allCases {
                _ = try runAdmission(
                    in: scenario, cancellation: cancellation, point: .hash(trace.hashes.count),
                    expectedSeeds: scenario == .fresh ? 1 : 0, expectedFactories: 1)
            }
        }
    }

    func testSeedCloseAndSupersessionRejectTheFactoryAndRetainCleanupPayloads() async throws {
        for cancellation in ObserverAdmissionCancellation.allCases {
            _ = try runAdmission(
                in: .fresh, cancellation: cancellation, point: .seed,
                expectedSeeds: 1, expectedFactories: 0)
        }
    }

    func testFactoryCloseAndSupersessionDoNotPublishItsProvisionalValue() async throws {
        for scenario in ObserverAdmissionScenario.allCases {
            for cancellation in ObserverAdmissionCancellation.allCases {
                _ = try runAdmission(
                    in: scenario, cancellation: cancellation, point: .factory,
                    expectedSeeds: scenario == .fresh ? 1 : 0, expectedFactories: 1)
            }
        }
    }

    func testOptionalFactoryCanDeclineWithoutMovingTheCommittedBaseline() async throws {
        let fixture = try ObserverAdmissionFixture(scenario: .committed)
        defer { fixture.close() }
        let oldCell = try XCTUnwrap(fixture.baselineCell)
        fixture.stage(value: 20, declinesUpdate: true)
        XCTAssertEqual(fixture.events.seeds, 0)
        XCTAssertEqual(fixture.events.factories, 1)
        try fixture.acceptBuild()

        XCTAssertEqual(oldCell.readValue().baseline?.number, 10)
        XCTAssertTrue(oldCell.isWritable)
        fixture.events.assertNoObserverCallbacks()
        XCTAssertEqual(fixture.coordinator.registry.liveOwnerCount, 1)
    }

    func testSubtreeAnchorHashesRejectCloseAndSupersessionWithoutReplacingCommittedStorage() async throws {
        let trace = try runSubtreeResolution()
        XCTAssertGreaterThan(trace.count, 0, "The anchored epoch must actually hash its authored identity")
        XCTAssertLessThanOrEqual(trace.count, 64, "Keep the exhaustive authored-hash sweep bounded")
        guard (1...64).contains(trace.count) else { return }
        for cancellation in ObserverAdmissionCancellation.allCases {
            for ordinal in 1...trace.count {
                _ = try runSubtreeResolution(cancellation: cancellation, atHash: ordinal)
            }
        }
    }

    func testSubtreeScopeDoesNotAdmitItsAnchorOrASibling() async throws {
        let fixture = try ObserverAdmissionSubtreeFixture()
        defer { fixture.close() }
        let subtree = try XCTUnwrap(
            fixture.registry.beginSubtreeBuild(owner: fixture.anchor, contentPrefix: fixture.contentPrefix))
        defer {
            subtree.abort()
            fixture.registry.finishPendingRetirements()
        }
        let sibling = fixture.anchor.identity.appending(.role(.detail))
        var seeds = 0
        for identity in [fixture.anchor.identity, sibling] {
            let result = subtree.resolveSyntheticObservation(at: identity) {
                seeds += 1
                return ObserverAdmissionObservation()
            }
            XCTAssertNil(result)
        }
        XCTAssertEqual(seeds, 0)
        XCTAssertTrue(subtree.canAdopt)
        XCTAssertNil(fixture.registry.owner(at: sibling))
        XCTAssertEqual(fixture.registry.liveOwnerCount, 2)

        let admitted = try XCTUnwrap(
            subtree.resolveSyntheticObservation(at: fixture.childIdentity) {
                seeds += 1
                return ObserverAdmissionObservation()
            })
        XCTAssertTrue(admitted.cell === fixture.baselineCell)
        XCTAssertEqual(admitted.cell.readValue().baseline?.number, 10)
        XCTAssertEqual(seeds, 0, "A valid descendant must reuse its committed observation")
    }

    func testFinishedAndAbandonedEpochsCannotBorrowTheNewCurrentBuild() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let hashing = ObserverAdmissionHashHook()
        let identity = observerAdmissionIdentity(value: 301, hashing: hashing)
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let original = try XCTUnwrap(
            initial.resolveSyntheticObservation(at: identity) { ObserverAdmissionObservation() })
        try acceptRegistryEpoch(initial)
        let abandoned = try XCTUnwrap(registry.beginRootBuild())
        abandoned.abort()
        registry.finishPendingRetirements()
        let current = try XCTUnwrap(registry.beginRootBuild())
        defer {
            hashing.disarm()
            current.abort()
            registry.finishPendingRetirements()
        }

        var rejectedSeeds = 0
        hashing.startRecording()
        let finishedResult = initial.resolveSyntheticObservation(at: identity) {
            rejectedSeeds += 1
            return ObserverAdmissionObservation()
        }
        let abandonedResult = abandoned.resolveSyntheticObservation(at: identity) {
            rejectedSeeds += 1
            return ObserverAdmissionObservation()
        }
        let hashes = hashing.finishRecording()
        XCTAssertNil(finishedResult)
        XCTAssertNil(abandonedResult)
        XCTAssertEqual(rejectedSeeds, 0)
        XCTAssertEqual(hashes.count, 0, "An obsolete epoch must reject before calling authored identity code")
        XCTAssertTrue(current.canAdopt)

        let admitted = try XCTUnwrap(
            current.resolveSyntheticObservation(at: identity) {
                rejectedSeeds += 1
                return ObserverAdmissionObservation()
            })
        XCTAssertTrue(admitted.owner === original.owner)
        XCTAssertTrue(admitted.cell === original.cell)
        XCTAssertEqual(rejectedSeeds, 0)
    }

    func testRetiredAnchorCannotAuthorizeTheSamePathReplacement() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let hashing = ObserverAdmissionHashHook()
        let anchorIdentity = observerAdmissionIdentity(value: 401, hashing: hashing)
        let contentPrefix = anchorIdentity.appending(.role(.geometryContent))
        let childIdentity = contentPrefix.appending(.slot(0))
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let retiredAnchor = try XCTUnwrap(initial.owner(at: anchorIdentity))
        let retiredObservation = try XCTUnwrap(
            initial.resolveSyntheticObservation(at: childIdentity) { ObserverAdmissionObservation() })
        try acceptRegistryEpoch(initial)

        let removal = try XCTUnwrap(registry.beginRootBuild())
        try acceptRegistryEpoch(removal)
        registry.finishPendingRetirements()
        XCTAssertFalse(retiredAnchor.isLive)
        XCTAssertFalse(retiredObservation.owner.isLive)
        XCTAssertFalse(retiredObservation.cell.isWritable)
        XCTAssertNil(registry.beginSubtreeBuild(owner: retiredAnchor, contentPrefix: contentPrefix))

        let replacement = try XCTUnwrap(registry.beginRootBuild())
        let replacementAnchor = try XCTUnwrap(replacement.owner(at: anchorIdentity))
        let replacementObservation = try XCTUnwrap(
            replacement.resolveSyntheticObservation(at: childIdentity) { ObserverAdmissionObservation() })
        try acceptRegistryEpoch(replacement)
        XCTAssertNotEqual(retiredAnchor.generation, replacementAnchor.generation)
        XCTAssertFalse(retiredObservation.cell === replacementObservation.cell)
        XCTAssertNil(registry.beginSubtreeBuild(owner: retiredAnchor, contentPrefix: contentPrefix))

        let current = try XCTUnwrap(
            registry.beginSubtreeBuild(owner: replacementAnchor, contentPrefix: contentPrefix))
        defer {
            current.abort()
            registry.finishPendingRetirements()
        }
        var seeds = 0
        let admitted = try XCTUnwrap(
            current.resolveSyntheticObservation(at: childIdentity) {
                seeds += 1
                return ObserverAdmissionObservation()
            })
        XCTAssertTrue(admitted.owner === replacementObservation.owner)
        XCTAssertTrue(admitted.cell === replacementObservation.cell)
        XCTAssertFalse(admitted.owner === retiredObservation.owner)
        XCTAssertEqual(seeds, 0)
    }

    private func sweepAdmissionHashes(in scenario: ObserverAdmissionScenario) throws {
        // Measure this exact fresh fixture rather than baking in Dictionary's
        // hash count. Each injection then gets a new registry with the same
        // single authored identity and the same ownership/cell history.
        let trace = try runAdmission(in: scenario)
        let factoryEntry = try XCTUnwrap(trace.factoryEntryHash)
        XCTAssertGreaterThan(trace.hashes.count, 0)
        XCTAssertLessThanOrEqual(trace.hashes.count, 64, "Keep the exhaustive authored-hash sweep bounded")
        guard (1...64).contains(trace.hashes.count) else { return }
        for cancellation in ObserverAdmissionCancellation.allCases {
            for ordinal in 1...trace.hashes.count {
                let expectedSeeds = trace.seedEntryHash.map { ordinal > $0 ? 1 : 0 } ?? 0
                _ = try runAdmission(
                    in: scenario, cancellation: cancellation, point: .hash(ordinal),
                    expectedSeeds: expectedSeeds, expectedFactories: ordinal > factoryEntry ? 1 : 0)
            }
        }
    }

    @discardableResult
    private func runAdmission(
        in scenario: ObserverAdmissionScenario, cancellation: ObserverAdmissionCancellation? = nil,
        point: ObserverAdmissionPoint? = nil, expectedSeeds: Int? = nil, expectedFactories: Int? = nil
    ) throws -> ObserverAdmissionTrace {
        let fixture = try ObserverAdmissionFixture(scenario: scenario)
        defer { fixture.close() }
        let build = try XCTUnwrap(fixture.build)
        let cancel: @MainActor () -> Void = {
            fixture.events.cancellations += 1
            switch cancellation {
            case .some(.close): fixture.coordinator.close()
            case .some(.supersede): build.supersede()
            case nil: XCTFail("The fixture reached an unconfigured cancellation")
            }
        }
        let ordinal: Int?
        if case .hash(let value)? = point { ordinal = value } else { ordinal = nil }
        fixture.hashing.startRecording(at: ordinal, action: ordinal == nil ? nil : cancel)
        fixture.stage(
            value: 20, duringSeed: point == .seed ? cancel : nil,
            duringFactory: point == .factory ? cancel : nil)
        // Disarm before every assertion and shared epoch cleanup. Even a
        // failed ordinal expectation must never move its hook into teardown.
        let hashes = fixture.hashing.finishRecording()
        let trace = ObserverAdmissionTrace(
            hashes: hashes, seedEntryHash: fixture.events.seedEntryHash,
            factoryEntryHash: fixture.events.factoryEntryHash, factoryExitHash: fixture.events.factoryExitHash)
        let label = "\(scenario), \(String(describing: cancellation)), \(String(describing: point))"

        if let cancellation {
            XCTAssertEqual(fixture.events.cancellations, 1, label)
            if let ordinal {
                XCTAssertEqual(hashes.firedAt, ordinal, label)
                XCTAssertEqual(hashes.invocations, 1, label)
            }
            XCTAssertFalse(build.canAdopt, label)
            XCTAssertFalse(build.canComplete, label)
            XCTAssertEqual(fixture.coordinator.registry.isClosed, cancellation == .close, label)
        } else {
            XCTAssertEqual(fixture.events.cancellations, 0, label)
            XCTAssertTrue(build.canAdopt, label)
            XCTAssertEqual(fixture.events.seeds, scenario == .fresh ? 1 : 0, label)
            XCTAssertEqual(fixture.events.factories, 1, label)
        }
        if let expectedSeeds { XCTAssertEqual(fixture.events.seeds, expectedSeeds, label) }
        if let expectedFactories { XCTAssertEqual(fixture.events.factories, expectedFactories, label) }
        XCTAssertEqual(fixture.events.reductions, fixture.events.factories, label)
        fixture.events.assertNoObserverCallbacks()
        if scenario == .committed {
            XCTAssertEqual(fixture.baselineCell?.readValue().baseline?.number, 10, label)
        } else {
            XCTAssertNil(fixture.baselineCell?.readValue().baseline, label)
        }
        XCTAssertEqual(
            fixture.events.liveObservations, scenario == .fresh ? fixture.events.seeds : 1,
            "Seed storage must remain pinned through rejected construction until its normal cleanup: \(label)")

        fixture.abandonBuild()
        fixture.events.assertNoObserverCallbacks()
        XCTAssertEqual(fixture.coordinator.registry.retiringOwnerCount, 0, label)
        XCTAssertEqual(
            fixture.coordinator.registry.liveOwnerCount,
            scenario == .committed && cancellation != .close ? 1 : 0, label)
        XCTAssertEqual(
            fixture.events.liveObservations,
            scenario == .committed && cancellation != .close ? 1 : 0,
            "Normal abort/finish must release rejected seed payloads without an extra host close: \(label)")
        XCTAssertEqual(fixture.events.liveUpdates, 0, "Finished rejected batches must release their updates: \(label)")

        if scenario == .committed, cancellation == .supersede {
            // Prove the next accepted build compares against the last accepted
            // value, not just that an escaped snapshot still reads an old value.
            XCTAssertTrue(fixture.baselineCell?.isWritable == true)
            try fixture.beginBuild()
            fixture.stage(value: 20)
            try fixture.acceptBuild()
            XCTAssertEqual(fixture.events.commits, 1, label)
            XCTAssertEqual(fixture.events.deliveries, 1, label)
            XCTAssertEqual(fixture.events.comparisonInputs, [[10, 20]], label)
            XCTAssertEqual(fixture.events.actions, [20], label)
        }

        fixture.close()
        XCTAssertEqual(fixture.coordinator.registry.liveOwnerCount, 0, label)
        XCTAssertEqual(fixture.coordinator.registry.retiringOwnerCount, 0, label)
        XCTAssertEqual(fixture.events.liveObservations, 0, "The host and finished epoch must release storage: \(label)")
        XCTAssertEqual(fixture.events.liveUpdates, 0, label)
        XCTAssertEqual(fixture.events.liveOwners, 0, "Finished epochs must not keep admitted owners alive: \(label)")
        withExtendedLifetime(build) {}
        return trace
    }

    @discardableResult
    private func runSubtreeResolution(
        cancellation: ObserverAdmissionCancellation? = nil, atHash ordinal: Int? = nil
    ) throws -> ObserverAdmissionHashTrace {
        let fixture = try ObserverAdmissionSubtreeFixture()
        defer { fixture.close() }
        let subtree = try XCTUnwrap(
            fixture.registry.beginSubtreeBuild(owner: fixture.anchor, contentPrefix: fixture.contentPrefix))
        defer {
            fixture.hashing.disarm()
            subtree.abort()
            fixture.registry.finishPendingRetirements()
        }
        var cancellations = 0
        var seeds = 0
        fixture.hashing.startRecording(at: ordinal) {
            cancellations += 1
            switch cancellation {
            case .some(.close): fixture.registry.close()
            case .some(.supersede): subtree.supersede()
            case nil: XCTFail("The fixture reached an unconfigured cancellation")
            }
        }
        var result = subtree.resolveSyntheticObservation(at: fixture.childIdentity) {
            seeds += 1
            return ObserverAdmissionObservation()
        }
        let hashes = fixture.hashing.finishRecording()
        let label = "subtree \(String(describing: cancellation)), hash \(String(describing: ordinal))"
        if let cancellation, let ordinal {
            XCTAssertEqual(cancellations, 1, label)
            XCTAssertEqual(hashes.firedAt, ordinal, label)
            XCTAssertEqual(hashes.invocations, 1, label)
            XCTAssertNil(result, label)
            XCTAssertFalse(subtree.canAdopt, label)
            XCTAssertEqual(fixture.registry.isClosed, cancellation == .close, label)
        } else {
            XCTAssertNotNil(result)
            XCTAssertTrue(result?.cell === fixture.baselineCell)
            XCTAssertTrue(subtree.canAdopt)
        }
        XCTAssertEqual(seeds, 0, "Existing committed storage must not run another seed: \(label)")
        XCTAssertEqual(fixture.baselineCell?.readValue().baseline?.number, 10, label)
        fixture.events.assertNoObserverCallbacks()
        result = nil
        subtree.abort()
        fixture.registry.finishPendingRetirements()
        XCTAssertEqual(fixture.registry.retiringOwnerCount, 0, label)
        XCTAssertEqual(fixture.registry.liveOwnerCount, cancellation == .close ? 0 : 2, label)
        if cancellation == .supersede {
            XCTAssertTrue(fixture.anchor.isLive)
            XCTAssertTrue(fixture.baselineCell?.isWritable == true)
            XCTAssertEqual(fixture.baselineCell?.readValue().baseline?.number, 10)
        }
        fixture.close()
        XCTAssertEqual(fixture.events.liveObservations, 0, "An aborted subtree must not retain its storage: \(label)")
        XCTAssertEqual(fixture.registry.liveOwnerCount, 0)
        XCTAssertEqual(fixture.registry.retiringOwnerCount, 0)
        withExtendedLifetime(subtree) {}
        return hashes
    }

    private func acceptRegistryEpoch(_ epoch: StateMountEpoch) throws {
        let prepared = epoch.prepareForAdoption()
        XCTAssertTrue(prepared)
        guard prepared else { throw ObserverAdmissionFailure.rejectedPreparation }
        epoch.commitAdoption()
        XCTAssertTrue(epoch.didCommit)
    }
}

private enum ObserverAdmissionScenario: CaseIterable, Equatable {
    case fresh
    case provisional
    case committed
}

private enum ObserverAdmissionCancellation: CaseIterable, Equatable {
    case close
    case supersede
}

private enum ObserverAdmissionPoint: Equatable {
    case hash(Int)
    case seed
    case factory
}

private enum ObserverAdmissionFailure: Error {
    case rejectedPreparation
}

private struct ObserverAdmissionTrace {
    let hashes: ObserverAdmissionHashTrace
    let seedEntryHash: Int?
    let factoryEntryHash: Int?
    let factoryExitHash: Int?
}

private struct ObserverAdmissionHashTrace {
    let count: Int
    let firedAt: Int?
    let invocations: Int
}

@MainActor
private final class ObserverAdmissionFixture {
    let events = ObserverAdmissionEvents()
    let hashing = ObserverAdmissionHashHook()
    let coordinator: StateMountCoordinator
    let identity: RetainedViewIdentity
    private(set) var build: (any RetainedBuildEpoch)?
    private(set) weak var baselineCell: MountedStateCell<ObserverAdmissionObservation>?

    init(scenario: ObserverAdmissionScenario) throws {
        coordinator = StateMountCoordinator(
            invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        identity = observerAdmissionIdentity(value: 101, hashing: hashing)
        try beginBuild()
        if scenario != .fresh {
            stage(value: 10)
            baselineCell = events.cells.last?.value
            XCTAssertNotNil(baselineCell)
        }
        if scenario == .committed {
            try acceptBuild()
            try beginBuild()
        }
        events.resetCounters()
    }

    func beginBuild() throws {
        XCTAssertNil(build)
        build = try XCTUnwrap(coordinator.beginBuild())
    }

    func stage(
        value: Int, duringSeed: (@MainActor () -> Void)? = nil,
        duringFactory: (@MainActor () -> Void)? = nil, declinesUpdate: Bool = false
    ) {
        coordinator.stageOnChange(
            at: identity,
            seedObservation: {
                self.events.seeds += 1
                self.events.seedEntryHash = self.hashing.count
                let observation = ObserverAdmissionObservation()
                self.events.observations.append(ObserverAdmissionWeak(observation))
                duringSeed?()
                return observation
            },
            makeUpdate: { owner, cell in
                self.events.factories += 1
                self.events.factoryEntryHash = self.hashing.count
                self.events.owners.append(ObserverAdmissionWeak(owner))
                self.events.cells.append(ObserverAdmissionWeak(cell))
                // This factory stands in for provisional preference reduction.
                // Observer equality/action live only in the update below.
                self.events.reductions += 1
                duringFactory?()
                self.events.factoryExitHash = self.hashing.count
                guard !declinesUpdate else { return nil }
                let update = ObserverAdmissionUpdate(
                    owner: owner, cell: cell, value: .init(number: value, events: self.events), events: self.events)
                self.events.updates.append(ObserverAdmissionWeak(update))
                return update
            })
    }

    func acceptBuild() throws {
        let build = try XCTUnwrap(build)
        let prepared = build.willAdopt()
        XCTAssertTrue(prepared)
        guard prepared else { throw ObserverAdmissionFailure.rejectedPreparation }
        build.commit()
        XCTAssertTrue(build.canComplete)
        build.finishAfterCallbacks()
        self.build = nil
    }

    func abandonBuild() {
        guard let build else { return }
        build.abandon()
        build.finishAfterCallbacks()
        self.build = nil
    }

    func close() {
        hashing.disarm()
        coordinator.close()
        abandonBuild()
    }
}

@MainActor
private final class ObserverAdmissionSubtreeFixture {
    let registry = StateMountRegistry()
    let hashing = ObserverAdmissionHashHook()
    let events = ObserverAdmissionEvents()
    let anchor: StateMountOwner
    let contentPrefix: RetainedViewIdentity
    let childIdentity: RetainedViewIdentity
    private(set) weak var baselineCell: MountedStateCell<ObserverAdmissionObservation>?

    init() throws {
        let identity = observerAdmissionIdentity(value: 201, hashing: hashing)
        contentPrefix = identity.appending(.role(.geometryContent))
        childIdentity = contentPrefix.appending(.slot(0))
        let initial = try XCTUnwrap(registry.beginRootBuild())
        anchor = try XCTUnwrap(initial.owner(at: identity))
        let observation = try XCTUnwrap(
            initial.resolveSyntheticObservation(at: childIdentity) {
                let value = ObserverAdmissionObservation()
                value.baseline = ObserverAdmissionValue(number: 10, events: self.events)
                self.events.observations.append(ObserverAdmissionWeak(value))
                return value
            })
        baselineCell = observation.cell
        let prepared = initial.prepareForAdoption()
        XCTAssertTrue(prepared)
        guard prepared else { throw ObserverAdmissionFailure.rejectedPreparation }
        initial.commitAdoption()
        XCTAssertTrue(initial.didCommit)
        XCTAssertTrue(anchor.isLive)
        XCTAssertTrue(observation.cell.isWritable)
    }

    func close() {
        hashing.disarm()
        registry.close()
        registry.finishPendingRetirements()
    }
}

@MainActor
private final class ObserverAdmissionEvents {
    var seeds = 0
    var factories = 0
    var reductions = 0
    var cancellations = 0
    var commits = 0
    var deliveries = 0
    var comparisonInputs: [[Int]] = []
    var actions: [Int] = []
    var seedEntryHash: Int?
    var factoryEntryHash: Int?
    var factoryExitHash: Int?
    var observations: [ObserverAdmissionWeak<ObserverAdmissionObservation>] = []
    var owners: [ObserverAdmissionWeak<StateMountOwner>] = []
    var cells: [ObserverAdmissionWeak<MountedStateCell<ObserverAdmissionObservation>>] = []
    var updates: [ObserverAdmissionWeak<ObserverAdmissionUpdate>] = []

    var liveObservations: Int { observations.filter { $0.value != nil }.count }
    var liveOwners: Int { owners.filter { $0.value != nil }.count }
    var liveUpdates: Int { updates.filter { $0.value != nil }.count }

    func assertNoObserverCallbacks(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(commits, 0, file: file, line: line)
        XCTAssertEqual(deliveries, 0, file: file, line: line)
        XCTAssertEqual(comparisonInputs, [], file: file, line: line)
        XCTAssertEqual(actions, [], file: file, line: line)
    }

    func resetCounters() {
        seeds = 0
        factories = 0
        reductions = 0
        cancellations = 0
        commits = 0
        deliveries = 0
        comparisonInputs = []
        actions = []
        seedEntryHash = nil
        factoryEntryHash = nil
        factoryExitHash = nil
    }
}

@MainActor
private final class ObserverAdmissionObservation {
    var baseline: ObserverAdmissionValue?
}

@MainActor
private final class ObserverAdmissionUpdate: MountedOnChangeUpdate {
    let owner: StateMountOwner
    private let cell: MountedStateCell<ObserverAdmissionObservation>
    private let value: ObserverAdmissionValue
    private let events: ObserverAdmissionEvents
    private var previous: ObserverAdmissionValue?

    init(
        owner: StateMountOwner, cell: MountedStateCell<ObserverAdmissionObservation>,
        value: ObserverAdmissionValue, events: ObserverAdmissionEvents
    ) {
        self.owner = owner
        self.cell = cell
        self.value = value
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

private struct ObserverAdmissionValue: Equatable {
    let number: Int
    let events: ObserverAdmissionEvents

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.events.comparisonInputs.append([lhs.number, rhs.number])
        }
        return lhs.number == rhs.number
    }
}

@MainActor
private final class ObserverAdmissionWeak<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) { self.value = value }
}

@MainActor
private final class ObserverAdmissionHashHook {
    private var isRecording = false
    private var target: Int?
    private var action: (@MainActor () -> Void)?
    private(set) var count = 0
    private var firedAt: Int?
    private var invocations = 0

    func startRecording(at target: Int? = nil, action: (@MainActor () -> Void)? = nil) {
        count = 0
        firedAt = nil
        invocations = 0
        self.target = target
        self.action = action
        isRecording = true
    }

    func finishRecording() -> ObserverAdmissionHashTrace {
        let result = ObserverAdmissionHashTrace(count: count, firedAt: firedAt, invocations: invocations)
        disarm()
        return result
    }

    func disarm() {
        isRecording = false
        target = nil
        action = nil
    }

    func recordHash() {
        guard isRecording else { return }
        count += 1
        guard count == target, let action else { return }
        self.action = nil
        target = nil
        firedAt = count
        invocations += 1
        action()
    }
}

// Stable Hashable witnesses, with reentry confined to the synchronous
// main-actor fixture. Neither hashing nor key equality compares observer data.
private struct ObserverAdmissionKey: Hashable {
    let value: Int
    let hashing: ObserverAdmissionHashHook

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        MainActor.assumeIsolated { hashing.recordHash() }
    }
}

@MainActor
private func observerAdmissionIdentity(value: Int, hashing: ObserverAdmissionHashHook) -> RetainedViewIdentity {
    RetainedViewIdentity(segments: [.explicit(.init(ObserverAdmissionKey(value: value, hashing: hashing)))])
}
