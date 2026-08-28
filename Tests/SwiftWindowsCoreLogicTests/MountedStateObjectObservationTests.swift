import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedStateObjectObservationTests: XCTestCase {
    func testProjectionOnlyOwnerSubscribesWithoutAReadOrAControlInvalidation() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(ObjectObservationProjectionOnlyView(probe: probe), probe: probe)
        defer { harness.close() }
        let binding = try XCTUnwrap(probe.valueBindings["projection"])
        let initialBodyCount = probe.bodyKeys.count

        // The body stores a projection but never reads the object or the
        // binding. This write has no control invalidate() to conceal a missing
        // subscription, and must not take the direct State invalidation path.
        binding.wrappedValue = 7

        XCTAssertEqual(harness.host.scheduledReloadCount, 1)
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        await harness.drain()

        XCTAssertEqual(binding.wrappedValue, 7)
        XCTAssertEqual(probe.bodyKeys.count, initialBodyCount + 1)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        XCTAssertEqual(probe.factoryKeys, ["projection"])
        XCTAssertEqual(harness.text("projection.value"), "Projection only")
    }

    func testNestedExistentialDynamicPropertyUpdatesReadTheInstalledObjectBeforeBody() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(ObjectObservationNestedRoot(probe: probe), probe: probe)
        defer { harness.close() }
        let model = try XCTUnwrap(probe.models["nested"])
        XCTAssertEqual(harness.text("nested.value"), "nested=0")

        model.value = 8
        await harness.drain()

        XCTAssertEqual(harness.text("nested.value"), "nested=8")
        XCTAssertTrue(probe.models["nested"] === model)
        XCTAssertEqual(probe.factoryKeys, ["nested"])
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertFalse(probe.updateObjectIDs.isEmpty)
        XCTAssertTrue(probe.updateObjectIDs.allSatisfy { $0 == ObjectIdentifier(model) })
        XCTAssertFalse(probe.updateEvents.isEmpty)
        XCTAssertEqual(probe.updateEvents.count % 3, 0)
        for index in stride(from: 0, to: probe.updateEvents.count, by: 3) {
            XCTAssertEqual(
                Array(probe.updateEvents[index..<min(index + 3, probe.updateEvents.count)]),
                ["inner", "outer", "body"])
        }
    }

    func testAnimatedObjectToggleFlushesOneObservedBatchWithoutAStateFallbackReload() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(
            ObjectObservationControls(style: .animated, probe: probe), probe: probe)
        defer { harness.close() }
        let model = try XCTUnwrap(probe.models["controls"])
        let target = try harness.node("object.opacity")
        let startedAt = harness.clock.now

        try harness.activate("object.toggle")

        XCTAssertTrue(model.isOn)
        XCTAssertEqual(harness.host.scheduledReloadCount, 1)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        XCTAssertEqual(probe.completions.count, 1)
        XCTAssertEqual(probe.completions.first?.transaction?.animation?.duration, 1)
        try assertAnimation(target, startTime: startedAt, duration: 1)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)

        await harness.drain(advanceClock: false)

        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(probe.completions.count, 1)
        try assertAnimation(target, startTime: startedAt, duration: 1)
        harness.present(at: startedAt + 0.5)
        XCTAssertEqual(target.opacity, 0.6, accuracy: 0.0001)
        harness.present(at: startedAt + 1)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }

    func testProjectedObjectTransactionPreservesAllFieldsAndRestoresTheOuterTransaction() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(
            ObjectObservationControls(style: .transaction, probe: probe), probe: probe)
        defer { harness.close() }
        let target = try harness.node("object.opacity")
        let startedAt = harness.clock.now

        try withTransaction(ObjectObservationTransactions.outer) {
            try harness.activate("object.toggle")
            XCTAssertEqual(currentTransaction?.animation?.duration, 4)
            XCTAssertEqual(currentTransaction?.scrollTargetAnchor, .top)
            XCTAssertEqual(currentAnimationTransaction?.duration, 4)
        }

        XCTAssertEqual(probe.completions.count, 1)
        try assertTransaction(
            XCTUnwrap(probe.completions.first), matches: ObjectObservationTransactions.projected)
        try assertAnimation(target, startTime: startedAt, duration: 1.25)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
        await harness.drain(advanceClock: false)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        harness.present(at: startedAt + 0.625)
        XCTAssertEqual(target.opacity, 0.6, accuracy: 0.0001)
        harness.present(at: startedAt + 1.25)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }

    func testExplicitNilObjectTransactionOverridesTheControlsRestoredOuterAnimation() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(
            ObjectObservationControls(style: .explicitNil, probe: probe), probe: probe)
        defer { harness.close() }
        let target = try harness.node("object.opacity")

        try withTransaction(ObjectObservationTransactions.outer) {
            try harness.activate("object.toggle")
            XCTAssertEqual(currentTransaction?.animation?.duration, 4)
            XCTAssertEqual(currentAnimationTransaction?.duration, 4)
        }

        XCTAssertEqual(probe.completions.count, 1)
        try assertTransaction(
            XCTUnwrap(probe.completions.first), matches: ObjectObservationTransactions.explicitNil)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
        XCTAssertEqual(harness.host.scheduledReloadCount, 1)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        await harness.drain()
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(probe.completions.count, 1)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
    }

    func testRawPublishedChangesCoalesceAndPreserveTheLatestLegacyOnlyAnimation() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(
            ObjectObservationControls(style: .plain, probe: probe), probe: probe)
        defer { harness.close() }
        let model = try XCTUnwrap(probe.models["controls"])
        let target = try harness.node("object.opacity")
        let startedAt = harness.clock.now
        withTransaction(ObjectObservationTransactions.projected) { model.value = 3 }

        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = nil
        currentAnimationTransaction = (duration: 0.8, easing: .linear)
        model.isOn = true
        currentTransaction = previousTransaction
        currentAnimationTransaction = previousAnimation

        XCTAssertEqual(probe.scheduledObjectIDs, [ObjectIdentifier(model), ObjectIdentifier(model)])
        XCTAssertEqual(probe.coalescedNotifications, [false, true])
        XCTAssertEqual(harness.host.scheduledReloadCount, 1)
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        harness.present(at: startedAt)

        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(probe.completions.count, 1)
        let completion = try XCTUnwrap(probe.completions.first)
        XCTAssertNil(completion.transaction, "The legacy tuple must not become a fabricated full transaction")
        XCTAssertEqual(completion.legacyAnimationDuration, 0.8)
        XCTAssertEqual(harness.text("object.value"), "value=3")
        try assertAnimation(target, startTime: startedAt, duration: 0.8)
        await harness.drain(advanceClock: false)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        harness.present(at: startedAt + 0.4)
        XCTAssertEqual(target.opacity, 0.6, accuracy: 0.0001)
        harness.present(at: startedAt + 0.8)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
    }

    func testBorrowedObservedAndEnvironmentObjectsKeepTheirOtherHostSubscriptionAfterOwnerClose() async throws {
        let ownerProbe = ObjectObservationProbe()
        let owner = ObjectObservationHarness(
            ObjectObservationControls(style: .plain, probe: ownerProbe), probe: ownerProbe)
        defer { owner.close() }
        let model = try XCTUnwrap(ownerProbe.models["controls"])
        let ownedBinding = try XCTUnwrap(ownerProbe.valueBindings["controls"])
        let borrowerProbe = ObjectObservationProbe()
        let borrower = ObjectObservationHarness(
            ObjectObservationBorrowedRoot(model: model, probe: borrowerProbe), probe: borrowerProbe)
        defer { borrower.close() }
        let observedBinding = try XCTUnwrap(borrowerProbe.valueBindings["observed"])
        let environmentBinding = try XCTUnwrap(borrowerProbe.valueBindings["environment"])
        XCTAssertTrue(borrowerProbe.models["observed"] === model)
        XCTAssertTrue(borrowerProbe.models["environment"] === model)
        let ownerReloads = owner.host.executedReloadCount

        owner.close()
        ownedBinding.wrappedValue = 99

        XCTAssertEqual(model.value, 0, "The retired owner's projection cannot write through its borrowed aliases")
        XCTAssertEqual(borrower.host.scheduledReloadCount, 0)
        observedBinding.wrappedValue = 7
        await borrower.drain()
        await owner.drain()

        XCTAssertEqual(borrower.text("observed.value"), "observed=7")
        XCTAssertEqual(borrower.text("environment.value"), "environment=7")
        XCTAssertEqual(borrower.host.executedReloadCount, 1)
        XCTAssertEqual(borrowerProbe.scheduledObjectIDs, [ObjectIdentifier(model)])
        XCTAssertEqual(owner.host.executedReloadCount, ownerReloads)
        XCTAssertEqual(owner.host.scheduledReloadCount, 0)

        environmentBinding.wrappedValue = 8
        await borrower.drain()

        XCTAssertEqual(model.value, 8)
        XCTAssertEqual(borrower.text("observed.value"), "observed=8")
        XCTAssertEqual(borrower.text("environment.value"), "environment=8")
        XCTAssertTrue(borrowerProbe.models["observed"] === model)
        XCTAssertTrue(borrowerProbe.models["environment"] === model)
        XCTAssertEqual(borrower.host.executedReloadCount, 2)
    }

    func testFactorySupersessionReleasesItsCandidateAndKeepsTheCommittedObjectObserved() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(ObjectObservationReplacementRoot(probe: probe), probe: probe)
        defer { harness.close() }
        let phase = try XCTUnwrap(probe.phase)
        let committed = try XCTUnwrap(probe.models["phase0"])
        probe.onFactory = { [weak probe] key, _ in
            guard let probe, key == "phase1" else { return }
            probe.onFactory = nil
            committed.value = 7
            phase.wrappedValue = 2
        }

        phase.wrappedValue = 1
        await harness.drain()

        XCTAssertEqual(probe.factoryKeys, ["phase0", "phase1"])
        XCTAssertFalse(probe.bodyKeys.contains("phase1"))
        XCTAssertFalse(probe.appearedPhases.contains(1))
        XCTAssertFalse(probe.completions.contains { $0.texts.contains("phase=1 value=0") })
        XCTAssertNil(probe.factoryModels["phase1"]?.value)
        XCTAssertTrue(probe.models["phase2"] === committed)
        XCTAssertEqual(harness.text("phase.value"), "phase=2 value=7")
        XCTAssertTrue(probe.scheduledObjectIDs.contains(ObjectIdentifier(committed)))
        let reloads = harness.host.executedReloadCount

        committed.value = 9
        await harness.drain()

        XCTAssertEqual(harness.text("phase.value"), "phase=2 value=9")
        XCTAssertEqual(harness.host.executedReloadCount, reloads + 1)
        XCTAssertEqual(probe.scheduledObjectIDs.last, ObjectIdentifier(committed))
    }

    func testFactoryCloseCannotAdoptOrRetainTheObjectUnderConstruction() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(ObjectObservationReplacementRoot(probe: probe), probe: probe)
        defer { harness.close() }
        let phase = try XCTUnwrap(probe.phase)
        let committed = try XCTUnwrap(probe.models["phase0"])
        probe.onFactory = { [weak probe] key, _ in
            guard let probe, key == "phase1" else { return }
            probe.onFactory = nil
            if let host = probe.host { host.windowWillClose(host.platformWindow) }
        }

        phase.wrappedValue = 1
        await harness.drain()

        XCTAssertTrue(probe.factoryKeys.contains("phase1"))
        XCTAssertFalse(probe.bodyKeys.contains("phase1"))
        XCTAssertFalse(probe.appearedPhases.contains(1))
        XCTAssertTrue(probe.completions.isEmpty)
        XCTAssertNil(probe.factoryModels["phase1"]?.value)
        XCTAssertEqual(probe.closeCount, 1)
        XCTAssertEqual(harness.renderer.detachCount, 1)
        XCTAssertFalse(harness.host.currentTimerState.isEnabled)
        let reloads = harness.host.executedReloadCount
        let schedules = harness.host.scheduledReloadCount

        committed.value = 5
        phase.wrappedValue = 2
        await harness.drain()

        XCTAssertEqual(harness.host.executedReloadCount, reloads)
        XCTAssertEqual(harness.host.scheduledReloadCount, schedules)
        XCTAssertEqual(probe.closeCount, 1)
        XCTAssertFalse(probe.factoryKeys.contains("phase2"))
    }

    func testRegistrationSupersessionDropsCandidateNotificationsWithoutDisconnectingTheCommittedObject()
        async throws
    {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(ObjectObservationReplacementRoot(probe: probe), probe: probe)
        defer { harness.close() }
        let phase = try XCTUnwrap(probe.phase)
        let committed = try XCTUnwrap(probe.models["phase0"])
        var abandoned: ObjectObservationModel?
        probe.onRegistered = { [weak probe] identifier in
            guard let probe, let candidate = probe.factoryModels["phase1"]?.value,
                identifier == ObjectIdentifier(candidate)
            else { return }
            probe.onRegistered = nil
            abandoned = candidate
            candidate.value = 8
            committed.value = 7
            phase.wrappedValue = 2
        }

        phase.wrappedValue = 1
        await harness.drain()

        let candidateID = try XCTUnwrap(abandoned.map { ObjectIdentifier($0) })
        XCTAssertTrue(probe.registeredObjectIDs.contains(candidateID))
        XCTAssertTrue(probe.scheduledObjectIDs.contains(candidateID))
        XCTAssertFalse(probe.bodyKeys.contains("phase1"))
        XCTAssertFalse(probe.appearedPhases.contains(1))
        XCTAssertFalse(probe.completions.contains { $0.texts.contains { $0.hasPrefix("phase=1 ") } })
        XCTAssertTrue(probe.models["phase2"] === committed)
        XCTAssertEqual(harness.text("phase.value"), "phase=2 value=7")
        let reloads = harness.host.executedReloadCount
        let schedules = harness.host.scheduledReloadCount
        let notifications = probe.scheduledObjectIDs.count

        abandoned?.value = 99
        await harness.drain()

        XCTAssertEqual(abandoned?.value, 99, "A deliberately retained raw reference keeps ordinary object semantics")
        XCTAssertEqual(harness.host.executedReloadCount, reloads)
        XCTAssertEqual(harness.host.scheduledReloadCount, schedules)
        XCTAssertEqual(probe.scheduledObjectIDs.count, notifications)
        abandoned = nil
        XCTAssertNil(probe.factoryModels["phase1"]?.value)

        committed.value = 9
        await harness.drain()

        XCTAssertEqual(harness.text("phase.value"), "phase=2 value=9")
        XCTAssertEqual(harness.host.executedReloadCount, reloads + 1)
        XCTAssertEqual(probe.scheduledObjectIDs.last, ObjectIdentifier(committed))
    }

    func testClosingFromObjectRegistrationCancelsItsPendingNotificationAndReleasesTheCandidate() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(ObjectObservationReplacementRoot(probe: probe), probe: probe)
        defer { harness.close() }
        let phase = try XCTUnwrap(probe.phase)
        let committed = try XCTUnwrap(probe.models["phase0"])
        var candidateID: ObjectIdentifier?
        probe.onRegistered = { [weak probe] identifier in
            guard let probe, let candidate = probe.factoryModels["phase1"]?.value,
                identifier == ObjectIdentifier(candidate)
            else { return }
            probe.onRegistered = nil
            candidateID = identifier
            candidate.value = 3
            if let host = probe.host { host.windowWillClose(host.platformWindow) }
        }

        phase.wrappedValue = 1
        await harness.drain()

        let registeredID = try XCTUnwrap(candidateID)
        XCTAssertTrue(probe.registeredObjectIDs.contains(registeredID))
        XCTAssertTrue(probe.scheduledObjectIDs.contains(registeredID))
        XCTAssertFalse(probe.bodyKeys.contains("phase1"))
        XCTAssertFalse(probe.appearedPhases.contains(1))
        XCTAssertTrue(probe.completions.isEmpty)
        XCTAssertNil(probe.factoryModels["phase1"]?.value)
        XCTAssertEqual(probe.closeCount, 1)
        XCTAssertEqual(harness.renderer.detachCount, 1)
        XCTAssertFalse(harness.host.currentTimerState.isEnabled)
        let reloads = harness.host.executedReloadCount
        let schedules = harness.host.scheduledReloadCount

        committed.value = 6
        phase.wrappedValue = 2
        await harness.drain()

        XCTAssertEqual(harness.host.executedReloadCount, reloads)
        XCTAssertEqual(harness.host.scheduledReloadCount, schedules)
        XCTAssertEqual(probe.closeCount, 1)
    }

    func testGeometrySubtreeRebuildPreservesItsObjectAndItsSiblingsObservation() async throws {
        let probe = ObjectObservationProbe()
        let harness = ObjectObservationHarness(ObjectObservationGeometryRoot(probe: probe), probe: probe)
        defer { harness.close() }
        let geometryModel = try XCTUnwrap(probe.models["geometry"])
        let siblingModel = try XCTUnwrap(probe.models["sibling"])
        let geometryNode = try harness.node("geometry.value")
        let siblingNode = try harness.node("sibling.value")
        let resolves = harness.runtime.geometryReaderResolveCount

        harness.runtime.setRootSize(IntSize(width: 640, height: 480))
        _ = harness.runtime.renderFrame()

        XCTAssertGreaterThan(harness.runtime.geometryReaderResolveCount, resolves)
        XCTAssertTrue(probe.models["geometry"] === geometryModel)
        XCTAssertTrue(probe.models["sibling"] === siblingModel)
        XCTAssertTrue(try harness.node("geometry.value") === geometryNode)
        XCTAssertTrue(try harness.node("sibling.value") === siblingNode)
        XCTAssertEqual(probe.factoryKeys.filter { $0 == "geometry" }.count, 1)
        XCTAssertEqual(probe.factoryKeys.filter { $0 == "sibling" }.count, 1)
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        XCTAssertEqual(harness.host.observedObjectRegistrationCount, 0)

        geometryModel.value = 5
        await harness.drain()
        XCTAssertEqual(harness.text("geometry.value"), "geometry=5")
        XCTAssertEqual(harness.text("sibling.value"), "sibling=0")
        siblingModel.value = 8
        await harness.drain()

        XCTAssertEqual(harness.text("geometry.value"), "geometry=5")
        XCTAssertEqual(harness.text("sibling.value"), "sibling=8")
        XCTAssertTrue(probe.models["geometry"] === geometryModel)
        XCTAssertTrue(probe.models["sibling"] === siblingModel)
        XCTAssertEqual(probe.scheduledObjectIDs, [ObjectIdentifier(geometryModel), ObjectIdentifier(siblingModel)])
        XCTAssertEqual(harness.host.executedReloadCount, 2)
    }

    private func assertTransaction(
        _ completion: ObjectObservationCompletion, matches expected: Transaction,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let transaction = try XCTUnwrap(completion.transaction, file: file, line: line)
        XCTAssertEqual(transaction.animation?.duration, expected.animation?.duration, file: file, line: line)
        XCTAssertEqual(transaction.animation?.easing, expected.animation?.easing, file: file, line: line)
        XCTAssertEqual(transaction.isContinuous, expected.isContinuous, file: file, line: line)
        XCTAssertEqual(transaction.scrollTargetAnchor, expected.scrollTargetAnchor, file: file, line: line)
        XCTAssertEqual(transaction.tracksVelocity, expected.tracksVelocity, file: file, line: line)
        XCTAssertEqual(transaction.disablesAnimations, expected.disablesAnimations, file: file, line: line)
        XCTAssertEqual(completion.legacyAnimationDuration, expected.animation?.duration, file: file, line: line)
    }

    private func assertAnimation(
        _ target: ViewNode, startTime: Double, duration: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let animation = try XCTUnwrap(target.animationStates[.opacity], file: file, line: line)
        XCTAssertEqual(target.opacity, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.startValue, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.endValue, 0.2, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.startTime, startTime, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.duration, duration, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.easing, .linear, file: file, line: line)
    }
}

@MainActor
private final class ObjectObservationModel: ObservableObject {
    @Published var value = 0
    @Published var isOn = false
}

@MainActor
private final class ObjectObservationWeakModel {
    weak var value: ObjectObservationModel?

    init(_ value: ObjectObservationModel) {
        self.value = value
    }
}

private struct ObjectObservationCompletion {
    let transaction: Transaction?
    let legacyAnimationDuration: Double?
    let texts: [String]
}

@MainActor
private final class ObjectObservationProbe {
    weak var host: WinSwiftUIWindowHost?
    var phase: Binding<Int>?
    var valueBindings: [String: Binding<Int>] = [:]
    var models: [String: ObjectObservationModel] = [:]
    var factoryModels: [String: ObjectObservationWeakModel] = [:]
    var factoryKeys: [String] = []
    var bodyKeys: [String] = []
    var appearedPhases: [Int] = []
    var updateObjectIDs: [ObjectIdentifier] = []
    var updateEvents: [String] = []
    var registeredObjectIDs: [ObjectIdentifier] = []
    var scheduledObjectIDs: [ObjectIdentifier] = []
    var coalescedNotifications: [Bool] = []
    var completions: [ObjectObservationCompletion] = []
    var onFactory: ((String, ObjectObservationModel) -> Void)?
    var onRegistered: ((ObjectIdentifier) -> Void)?
    var closeCount = 0

    func makeModel(_ key: String) -> ObjectObservationModel {
        let model = ObjectObservationModel()
        factoryKeys.append(key)
        factoryModels[key] = ObjectObservationWeakModel(model)
        onFactory?(key, model)
        return model
    }
}

@MainActor
private enum ObjectObservationTransactions {
    static var projected: Transaction {
        var transaction = Transaction(animation: .linear(duration: 1.25))
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .bottom
        transaction.tracksVelocity = true
        return transaction
    }

    static var explicitNil: Transaction {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .trailing
        transaction.tracksVelocity = true
        return transaction
    }

    static var outer: Transaction {
        var transaction = Transaction(animation: .linear(duration: 4))
        transaction.scrollTargetAnchor = .top
        return transaction
    }
}

@MainActor
private enum ObjectObservationBindingStyle {
    case plain
    case animated
    case transaction
    case explicitNil

    func apply(to binding: Binding<Bool>) -> Binding<Bool> {
        switch self {
        case .plain: return binding
        case .animated: return binding.animation(.linear(duration: 1))
        case .transaction: return binding.transaction(ObjectObservationTransactions.projected)
        case .explicitNil: return binding.transaction(ObjectObservationTransactions.explicitNil)
        }
    }
}

@MainActor
private struct ObjectObservationProjectionOnlyView: View {
    @StateObject private var model: ObjectObservationModel
    let probe: ObjectObservationProbe

    init(probe: ObjectObservationProbe) {
        self.probe = probe
        _model = StateObject(wrappedValue: probe.makeModel("projection"))
    }

    var body: some View {
        probe.bodyKeys.append("projection")
        probe.valueBindings["projection"] = $model.value
        return Text("Projection only").accessibilityIdentifier("projection.value")
    }
}

@MainActor
private struct ObjectObservationOwnedProperty: DynamicProperty {
    @StateObject private var model: ObjectObservationModel
    private let probe: ObjectObservationProbe

    init(probe: ObjectObservationProbe) {
        self.probe = probe
        _model = StateObject(wrappedValue: probe.makeModel("nested"))
    }

    nonisolated mutating func update() {
        MainActor.assumeIsolated {
            let installed = model
            probe.updateEvents.append("inner")
            probe.updateObjectIDs.append(ObjectIdentifier(installed))
            probe.models["nested"] = installed
        }
    }
}

@MainActor
private struct ObjectObservationNestedProperty: DynamicProperty {
    private var erased: any DynamicProperty
    private let probe: ObjectObservationProbe

    init(probe: ObjectObservationProbe) {
        self.probe = probe
        erased = ObjectObservationOwnedProperty(probe: probe)
    }

    nonisolated mutating func update() {
        MainActor.assumeIsolated { probe.updateEvents.append("outer") }
    }
}

@MainActor
private struct ObjectObservationNestedRoot: View {
    let probe: ObjectObservationProbe

    var body: some View {
        ObjectObservationNestedView(probe: probe)
    }
}

@MainActor
private struct ObjectObservationNestedView: View {
    private var property: ObjectObservationNestedProperty
    private let probe: ObjectObservationProbe

    init(probe: ObjectObservationProbe) {
        self.probe = probe
        property = ObjectObservationNestedProperty(probe: probe)
    }

    var body: some View {
        probe.updateEvents.append("body")
        return Text("nested=\(probe.models["nested"]?.value ?? -1)")
            .accessibilityIdentifier("nested.value")
    }
}

@MainActor
private struct ObjectObservationControls: View {
    @StateObject private var model: ObjectObservationModel
    let style: ObjectObservationBindingStyle
    let probe: ObjectObservationProbe

    init(style: ObjectObservationBindingStyle, probe: ObjectObservationProbe) {
        self.style = style
        self.probe = probe
        _model = StateObject(wrappedValue: probe.makeModel("controls"))
    }

    var body: some View {
        probe.models["controls"] = model
        probe.valueBindings["controls"] = $model.value
        return VStack(alignment: .leading, spacing: 8) {
            Toggle("Object binding", isOn: style.apply(to: $model.isOn))
                .labelsHidden()
                .accessibilityIdentifier("object.toggle")
            Rectangle()
                .fill(WinSwiftUI.Color.blue)
                .frame(width: 80, height: 24)
                .opacity(model.isOn ? 0.2 : 1)
                .accessibilityIdentifier("object.opacity")
            Text("value=\(model.value)")
                .accessibilityIdentifier("object.value")
        }
        .padding(12)
    }
}

@MainActor
private struct ObjectObservationBorrowedRoot: View {
    let model: ObjectObservationModel
    let probe: ObjectObservationProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ObjectObservationObservedChild(model: model, probe: probe)
            ObjectObservationEnvironmentChild(probe: probe)
        }
        .environmentObject(model)
    }
}

@MainActor
private struct ObjectObservationObservedChild: View {
    @ObservedObject var model: ObjectObservationModel
    let probe: ObjectObservationProbe

    var body: some View {
        probe.models["observed"] = model
        probe.valueBindings["observed"] = $model.value
        return Text("observed=\(model.value)").accessibilityIdentifier("observed.value")
    }
}

@MainActor
private struct ObjectObservationEnvironmentChild: View {
    @EnvironmentObject private var model: ObjectObservationModel
    let probe: ObjectObservationProbe

    var body: some View {
        probe.models["environment"] = model
        probe.valueBindings["environment"] = $model.value
        return Text("environment=\(model.value)").accessibilityIdentifier("environment.value")
    }
}

@MainActor
private struct ObjectObservationReplacementRoot: View {
    @State private var phase = 0
    let probe: ObjectObservationProbe

    var body: some View {
        probe.phase = $phase
        return VStack(alignment: .leading, spacing: 8) {
            if phase == 1 {
                ObjectObservationCandidate(phase: phase, probe: probe)
            } else {
                ObjectObservationCandidate(phase: phase, probe: probe)
            }
        }
    }
}

@MainActor
private struct ObjectObservationCandidate: View {
    @StateObject private var model: ObjectObservationModel
    let phase: Int
    let probe: ObjectObservationProbe

    init(phase: Int, probe: ObjectObservationProbe) {
        self.phase = phase
        self.probe = probe
        _model = StateObject(wrappedValue: probe.makeModel("phase\(phase)"))
    }

    var body: some View {
        let key = "phase\(phase)"
        probe.bodyKeys.append(key)
        probe.models[key] = model
        return Text("phase=\(phase) value=\(model.value)")
            .accessibilityIdentifier("phase.value")
            .onAppear { probe.appearedPhases.append(phase) }
    }
}

@MainActor
private struct ObjectObservationGeometryRoot: View {
    let probe: ObjectObservationProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in
                ObjectObservationNamedOwnedView(name: "geometry", probe: probe)
                    .frame(width: proxy.size.width)
            }
            .frame(height: 180)
            ObjectObservationNamedOwnedView(name: "sibling", probe: probe)
                .frame(height: 60)
        }
    }
}

@MainActor
private struct ObjectObservationNamedOwnedView: View {
    @StateObject private var model: ObjectObservationModel
    let name: String
    let probe: ObjectObservationProbe

    init(name: String, probe: ObjectObservationProbe) {
        self.name = name
        self.probe = probe
        _model = StateObject(wrappedValue: probe.makeModel(name))
    }

    var body: some View {
        probe.models[name] = model
        return Text("\(name)=\(model.value)").accessibilityIdentifier("\(name).value")
    }
}

@MainActor
private final class ObjectObservationHarness {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let renderer: FakeRenderBackend
    let clock: RuntimeTestClock

    init<Content: View>(_ content: Content, probe: ObjectObservationProbe) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let renderer = FakeRenderBackend()
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 400, height: 400), scaleFactor: 1)
        let window = Win32Window(title: "Mounted StateObject observation", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Mounted StateObject observation", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window, renderer: renderer, batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.host = host
        self.window = window
        self.renderer = renderer
        self.clock = clock
        probe.host = host
        host.onWindowClosed = { [weak probe] _ in probe?.closeCount += 1 }
        host.onObservedObjectRegistered = { [weak probe] identifier in
            probe?.registeredObjectIDs.append(identifier)
            probe?.onRegistered?(identifier)
        }
        host.onObservedObjectReloadScheduled = { [weak probe] identifier, wasCoalesced in
            probe?.scheduledObjectIDs.append(identifier)
            probe?.coalescedNotifications.append(wasCoalesced)
        }
        host.onReloadContentCompleted = { [weak host, weak probe] in
            guard let host, let probe else { return }
            probe.completions.append(
                ObjectObservationCompletion(
                    transaction: currentTransaction,
                    legacyAnimationDuration: currentAnimationTransaction?.duration,
                    texts: objectObservationNodes(in: host.hostedRuntime.root).compactMap(\.text)))
        }
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        host.resetObservabilityCounters()
        probe.registeredObjectIDs.removeAll()
        probe.scheduledObjectIDs.removeAll()
        probe.coalescedNotifications.removeAll()
        probe.completions.removeAll()
    }

    var runtime: RetainedViewRuntime { host.hostedRuntime }
    var nodes: [ViewNode] { objectObservationNodes(in: runtime.root) }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func text(_ identifier: String) -> String? {
        nodes.first { $0.accessibilityIdentifier == identifier }?.text
    }

    func activate(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let control = try node(identifier, file: file, line: line)
        XCTAssertNotNil(control.onActivate, file: file, line: line)
        runtime.requestFocus(control)
        host.window(window, keyDown: KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    func present(at timestamp: Double) {
        clock.now = timestamp
        host.windowNeedsDisplay(window)
    }

    func drain(advanceClock: Bool = true) async {
        for _ in 0..<3 {
            if advanceClock { clock.now += 0.02 }
            host.windowNeedsDisplay(window)
            await Task.yield()
        }
    }

    func close() {
        host.windowWillClose(window)
    }
}

@MainActor
private func objectObservationNodes(in node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap { objectObservationNodes(in: $0) }
}
