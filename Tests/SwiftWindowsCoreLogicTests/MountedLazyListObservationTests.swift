import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Uses the production managed row context and real ObservableObjectCenter
/// subscriptions. It does not qualify the native window host's async scheduler.
@MainActor
final class MountedLazyListObservationTests: XCTestCase {
    func testColdOwnedObjectDropsItsLastSubscriptionWithoutEvaluatingTheRow() async throws {
        let probe = MountedLazyListObjectProbe()
        let host = MountedLazyListTestHost { mountedLazyListOwnedObjectContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        try host.assertCommittedDescriptor()
        XCTAssertTrue(host.observations.activeObjectIDs.isEmpty)
        XCTAssertTrue(probe.factoryCalls.isEmpty)
        XCTAssertNotNil(host.layout())
        let model = try XCTUnwrap(probe.models[0]?.value)
        let binding = try XCTUnwrap(probe.bindings[0])
        let identifier = ObjectIdentifier(model)
        XCTAssertTrue(host.observations.committed.contains(identifier))
        XCTAssertTrue(host.observations.activeObjectIDs.contains(identifier))
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)

        try host.scroll(to: 200)
        XCTAssertNil(host.find("lazy.object.0"))
        XCTAssertFalse(host.observations.committed.contains(identifier))
        XCTAssertFalse(host.observations.retained.contains(identifier))
        XCTAssertFalse(host.observations.activeObjectIDs.contains(identifier))
        let notifications = host.observations.notificationCount(for: identifier)
        let observedInvalidations = host.events.observedInvalidations
        let stateInvalidations = host.events.stateInvalidations
        let factories = probe.factoryCalls[0]

        binding.wrappedValue = 77

        XCTAssertEqual(model.value, 77)
        XCTAssertEqual(host.observations.notificationCount(for: identifier), notifications)
        XCTAssertEqual(host.events.observedInvalidations, observedInvalidations)
        XCTAssertEqual(host.events.stateInvalidations, stateInvalidations)
        XCTAssertEqual(probe.factoryCalls[0], factories)
        XCTAssertNil(host.find("lazy.object.0"))

        try host.scroll(to: 0)
        XCTAssertTrue(probe.models[0]?.value === model)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
        XCTAssertTrue(host.observations.committed.contains(identifier))
        XCTAssertTrue(host.observations.activeObjectIDs.contains(identifier))
        binding.wrappedValue = 78
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(model.value, 78)
        XCTAssertEqual(host.observations.notificationCount(for: identifier), notifications + 1)
        XCTAssertEqual(host.events.observedInvalidations, observedInvalidations + 1)
        XCTAssertEqual(host.events.stateInvalidations, stateInvalidations)
    }

    func testColdObjectKeepsAnActiveBorrowersSubscriptionUntilThatConsumerIsRemoved() async throws {
        let probe = MountedLazyListObjectProbe()
        let host = MountedLazyListTestHost(size: Size(width: 160, height: 40)) {
            mountedLazyListSharedObjectContent(probe)
        }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let model = try XCTUnwrap(probe.models[0]?.value)
        let binding = try XCTUnwrap(probe.bindings[0])
        let identifier = ObjectIdentifier(model)
        // This is an intentional strong borrowed handle, not a release test.
        probe.borrowedModel = model
        probe.showsBorrower = true
        host.reload()
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.borrowedValues.last, 100)

        try host.scroll(to: 200)
        XCTAssertNil(host.find("lazy.object.0"))
        XCTAssertTrue(host.observations.committed.contains(identifier))
        XCTAssertTrue(host.observations.activeObjectIDs.contains(identifier))
        let notifications = host.observations.notificationCount(for: identifier)
        let observedInvalidations = host.events.observedInvalidations
        let coldFactoryCalls = probe.factoryCalls[0]

        binding.wrappedValue = 17
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(probe.borrowedValues.last, 17)
        XCTAssertEqual(model.value, 17)
        XCTAssertEqual(host.observations.notificationCount(for: identifier), notifications + 1)
        XCTAssertEqual(host.events.observedInvalidations, observedInvalidations + 1)
        XCTAssertEqual(probe.factoryCalls[0], coldFactoryCalls)
        XCTAssertNil(host.find("lazy.object.0"))

        probe.showsBorrower = false
        host.reload()
        XCTAssertNotNil(host.layout())
        XCTAssertFalse(host.observations.committed.contains(identifier))
        XCTAssertFalse(host.observations.retained.contains(identifier))
        XCTAssertFalse(host.observations.activeObjectIDs.contains(identifier))
        let afterRemovalNotifications = host.observations.notificationCount(for: identifier)
        let afterRemovalInvalidations = host.events.observedInvalidations

        binding.wrappedValue = 18

        XCTAssertEqual(model.value, 18)
        XCTAssertEqual(host.observations.notificationCount(for: identifier), afterRemovalNotifications)
        XCTAssertEqual(host.events.observedInvalidations, afterRemovalInvalidations)
        XCTAssertEqual(probe.factoryCalls[0], coldFactoryCalls)
        XCTAssertNil(host.find("lazy.object.0"))
    }

    func testColdReturnReseedsNoninitialOnChangeWithoutReplayingColdValues() async throws {
        let probe = MountedLazyListValueProbe(value: 0)
        let host = MountedLazyListTestHost {
            mountedLazyListValueContent(probe, kind: .change(initial: false))
        }
        defer {
            host.close()
            probe.clear()
        }
        try host.assertCommittedDescriptor()
        XCTAssertTrue(probe.changes.isEmpty)
        XCTAssertNotNil(host.layout())
        let binding = try XCTUnwrap(probe.stateBindings[0])
        let owner = try XCTUnwrap(probe.owners[0])
        XCTAssertEqual(probe.changes[0, default: []], [])

        probe.value = 1
        host.reload()
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.changes[0], [MountedLazyListChange(old: 0, new: 1)])
        binding.wrappedValue = 41
        XCTAssertNotNil(host.layout())
        try host.scroll(to: 200)
        let coldFactories = probe.factoryCalls[0]

        probe.value = 2
        host.reload()
        XCTAssertNotNil(host.layout())
        probe.value = 3
        host.reload()
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(probe.factoryCalls[0], coldFactories)
        XCTAssertNil(host.find("lazy.observation.0"))
        XCTAssertEqual(probe.changes[0], [MountedLazyListChange(old: 0, new: 1)])
        XCTAssertTrue(owner.isLive)
        XCTAssertEqual(binding.wrappedValue, 41)
        try host.scroll(to: 0)
        XCTAssertTrue(probe.owners[0] === owner)
        XCTAssertEqual(probe.stateBindings[0]?.wrappedValue, 41)
        XCTAssertEqual(probe.changes[0], [MountedLazyListChange(old: 0, new: 1)])

        probe.value = 4
        host.reload()
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(
            probe.changes[0],
            [MountedLazyListChange(old: 0, new: 1), MountedLazyListChange(old: 3, new: 4)])
    }

    func testColdReturnDeliversInitialOnChangeOnceForTheNewAcceptedActivity() async throws {
        let probe = MountedLazyListValueProbe(value: 7)
        let host = MountedLazyListTestHost {
            mountedLazyListValueContent(probe, kind: .change(initial: true))
        }
        defer {
            host.close()
            probe.clear()
        }
        try host.assertCommittedDescriptor()
        XCTAssertTrue(probe.changes.isEmpty)
        XCTAssertNotNil(host.layout())
        let binding = try XCTUnwrap(probe.stateBindings[0])
        let owner = try XCTUnwrap(probe.owners[0])
        XCTAssertEqual(probe.changes[0], [MountedLazyListChange(old: 7, new: 7)])
        binding.wrappedValue = 41
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.changes[0], [MountedLazyListChange(old: 7, new: 7)])
        try host.scroll(to: 200)
        let coldFactories = probe.factoryCalls[0]

        probe.value = 8
        host.reload()
        XCTAssertNotNil(host.layout())
        probe.value = 9
        host.reload()
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(probe.factoryCalls[0], coldFactories)
        XCTAssertEqual(probe.changes[0], [MountedLazyListChange(old: 7, new: 7)])
        try host.scroll(to: 0)
        XCTAssertTrue(probe.owners[0] === owner)
        XCTAssertEqual(binding.wrappedValue, 41)
        XCTAssertEqual(
            probe.changes[0],
            [MountedLazyListChange(old: 7, new: 7), MountedLazyListChange(old: 9, new: 9)])
        host.reload()
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(
            probe.changes[0],
            [MountedLazyListChange(old: 7, new: 7), MountedLazyListChange(old: 9, new: 9)])
    }

    func testPreferenceObserverUsesAcceptedReturnValueWhileOrdinaryStateStaysCold() async throws {
        let probe = MountedLazyListValueProbe(value: 7)
        let host = MountedLazyListTestHost { mountedLazyListValueContent(probe, kind: .preference) }
        defer {
            host.close()
            probe.clear()
        }
        try host.assertCommittedDescriptor()
        XCTAssertTrue(probe.preferences.isEmpty)
        XCTAssertNotNil(host.layout())
        let binding = try XCTUnwrap(probe.stateBindings[0])
        let owner = try XCTUnwrap(probe.owners[0])
        XCTAssertEqual(probe.preferences[0], [7])
        binding.wrappedValue = 41
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.preferences[0], [7])
        try host.scroll(to: 200)
        let coldFactories = probe.factoryCalls[0]

        probe.value = 8
        host.reload()
        XCTAssertNotNil(host.layout())
        probe.value = 9
        host.reload()
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(probe.factoryCalls[0], coldFactories)
        XCTAssertEqual(probe.preferences[0], [7])
        XCTAssertTrue(owner.isLive)
        try host.scroll(to: 0)
        XCTAssertTrue(probe.owners[0] === owner)
        XCTAssertEqual(binding.wrappedValue, 41)
        XCTAssertEqual(probe.preferences[0], [7, 9])
        probe.value = 10
        host.reload()
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.preferences[0], [7, 9, 10])
        // Only accepted observer actions are asserted. Preference reduction
        // during a materialized rejected candidate is not promised to roll back.
    }
}

@MainActor
struct MountedLazyListObservationPublication {
    let committed: Set<ObjectIdentifier>
    let retained: Set<ObjectIdentifier>
    let replacesRoot: Bool
}

/// Real token ownership for the coordinator callbacks, deliberately scoped to
/// one fixture. Neither IDs nor weak callback captures retain the observed model.
@MainActor
final class MountedLazyListObservationRecorder {
    private struct Subscription {
        let generation: UInt64
        let token: ObservationToken
    }

    private var subscriptions: [ObjectIdentifier: Subscription] = [:]
    private var generation: UInt64 = 0
    private(set) var committed: Set<ObjectIdentifier> = []
    private(set) var retained: Set<ObjectIdentifier> = []
    private(set) var registrations: [ObjectIdentifier] = []
    private(set) var removals: [ObjectIdentifier] = []
    private(set) var notifications: [ObjectIdentifier] = []
    private(set) var publications: [MountedLazyListObservationPublication] = []
    private(set) var isClosed = false
    var onNotification: (@MainActor (ObjectIdentifier) -> Void)?

    var activeObjectIDs: Set<ObjectIdentifier> { Set(subscriptions.keys) }

    func observe(_ object: any ObservableObject) {
        guard !isClosed else { return }
        let identifier = ObjectIdentifier(object)
        guard subscriptions[identifier] == nil else { return }
        generation += 1
        let subscribedGeneration = generation
        let token = ObservableObjectCenter.shared.addObserver(for: object) { [weak self] in
            guard let self, !self.isClosed,
                self.subscriptions[identifier]?.generation == subscribedGeneration
            else { return }
            self.notifications.append(identifier)
            self.onNotification?(identifier)
        }
        subscriptions[identifier] = Subscription(generation: subscribedGeneration, token: token)
        registrations.append(identifier)
    }

    func update(committed: Set<ObjectIdentifier>, retained: Set<ObjectIdentifier>, replacesRoot: Bool) {
        guard !isClosed else { return }
        self.committed = committed
        self.retained = retained
        publications.append(
            MountedLazyListObservationPublication(
                committed: committed, retained: retained, replacesRoot: replacesRoot))
        let removed = Set(subscriptions.keys).subtracting(retained)
        let tokens = removed.compactMap { subscriptions.removeValue(forKey: $0)?.token }
        removals.append(contentsOf: removed)
        // Publish removal before a cancellation/reentrant notification can run.
        for token in tokens { token.cancel() }
    }

    func notificationCount(for identifier: ObjectIdentifier) -> Int {
        notifications.filter { $0 == identifier }.count
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        let tokens = subscriptions.values.map(\.token)
        subscriptions.removeAll()
        committed.removeAll()
        retained.removeAll()
        onNotification = nil
        for token in tokens { token.cancel() }
    }
}

@MainActor
private final class MountedLazyListWeakModel {
    weak var value: MountedLazyListModel?
    init(_ value: MountedLazyListModel) { self.value = value }
}

@MainActor
private final class MountedLazyListObjectProbe {
    let rows = Array(0..<32)
    private(set) var factoryCalls: [Int: Int] = [:]
    private(set) var objectFactoryCalls: [Int: Int] = [:]
    private(set) var models: [Int: MountedLazyListWeakModel] = [:]
    var bindings: [Int: Binding<Int>] = [:]
    var bodyCalls: [Int: Int] = [:]
    var borrowedModel: MountedLazyListModel?
    var showsBorrower = false
    var borrowedValues: [Int] = []
    private var serial = 0

    func makeRow(_ row: Int) -> MountedLazyListOwnedObjectRow {
        factoryCalls[row, default: 0] += 1
        return MountedLazyListOwnedObjectRow(row: row, probe: self)
    }

    func makeModel(_ row: Int) -> MountedLazyListModel {
        serial += 1
        objectFactoryCalls[row, default: 0] += 1
        let model = MountedLazyListModel(value: 100 + row, serial: serial)
        models[row] = MountedLazyListWeakModel(model)
        return model
    }

    func clear() {
        bindings.removeAll()
        models.removeAll()
        borrowedModel = nil
    }
}

@MainActor
private struct MountedLazyListOwnedObjectRow: View {
    @StateObject private var model: MountedLazyListModel
    let row: Int
    let probe: MountedLazyListObjectProbe

    init(row: Int, probe: MountedLazyListObjectProbe) {
        self.row = row
        self.probe = probe
        _model = StateObject(wrappedValue: probe.makeModel(row))
    }

    var body: some View {
        // Do not read model or this binding here. Installation, not a body
        // getter or a control invalidation, must establish the dependency.
        probe.bindings[row] = $model.value
        probe.bodyCalls[row, default: 0] += 1
        return Color.green.frame(width: 120, height: 20)
            .accessibilityIdentifier("lazy.object.\(row)")
    }
}

@MainActor
private struct MountedLazyListBorrowedObjectRow: View {
    @ObservedObject private var model: MountedLazyListModel
    let probe: MountedLazyListObjectProbe

    init(model: MountedLazyListModel, probe: MountedLazyListObjectProbe) {
        _model = ObservedObject(wrappedValue: model)
        self.probe = probe
    }

    var body: some View {
        probe.borrowedValues.append(model.value)
        return Color.blue.frame(width: 40, height: 40)
            .accessibilityIdentifier("lazy.object.borrower")
    }
}

@MainActor
private func mountedLazyListOwnedObjectContent(_ probe: MountedLazyListObjectProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.self, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { row in probe.makeRow(row) }
}

@MainActor
private func mountedLazyListSharedObjectContent(_ probe: MountedLazyListObjectProbe) -> some View {
    HStack(spacing: 0) {
        mountedLazyListOwnedObjectContent(probe)
        if probe.showsBorrower, let model = probe.borrowedModel {
            MountedLazyListBorrowedObjectRow(model: model, probe: probe)
        } else {
            Color.clear.frame(width: 40, height: 40)
        }
    }
    .frame(width: 160, height: 40)
}

private struct MountedLazyListChange: Equatable {
    let old: Int
    let new: Int
}

private enum MountedLazyListValueKind {
    case change(initial: Bool)
    case preference
}

@MainActor
private final class MountedLazyListValueProbe {
    let rows = Array(0..<32)
    var value: Int
    private(set) var factoryCalls: [Int: Int] = [:]
    var stateBindings: [Int: Binding<Int>] = [:]
    var owners: [Int: StateMountOwner] = [:]
    var changes: [Int: [MountedLazyListChange]] = [:]
    var preferences: [Int: [Int]] = [:]

    init(value: Int) { self.value = value }

    func makeRow(_ row: Int, kind: MountedLazyListValueKind) -> MountedLazyListValueRow {
        factoryCalls[row, default: 0] += 1
        return MountedLazyListValueRow(row: row, kind: kind, probe: self)
    }

    func changed(row: Int, old: Int, new: Int) {
        changes[row, default: []].append(MountedLazyListChange(old: old, new: new))
    }

    func preferred(row: Int, value: Int) { preferences[row, default: []].append(value) }

    func clear() {
        stateBindings.removeAll()
        owners.removeAll()
    }
}

@MainActor
private struct MountedLazyListValueRow: View {
    @State private var counter = 100
    let row: Int
    let kind: MountedLazyListValueKind
    let probe: MountedLazyListValueProbe

    var body: some View {
        let row = self.row
        let probe = self.probe
        probe.stateBindings[row] = $counter
        probe.owners[row] = ViewBuildContextScope.current?.viewIdentity.installedOwner
        let leaf = Color.blue.frame(width: 120, height: 20)
            .accessibilityIdentifier("lazy.observation.\(row)")
        switch kind {
        case .change(let initial):
            return AnyView(
                leaf.onChange(of: probe.value, initial: initial) { [weak probe] old, new in
                    probe?.changed(row: row, old: old, new: new)
                })
        case .preference:
            return AnyView(
                leaf.preference(key: MountedLazyListPreferenceKey.self, value: probe.value)
                    .onPreferenceChange(MountedLazyListPreferenceKey.self) { [weak probe] value in
                        probe?.preferred(row: row, value: value)
                    })
        }
    }
}

private struct MountedLazyListPreferenceKey: PreferenceKey {
    static var defaultValue: Int { 0 }
    static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
}

@MainActor
private func mountedLazyListValueContent(
    _ probe: MountedLazyListValueProbe, kind: MountedLazyListValueKind
) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.self, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { row in probe.makeRow(row, kind: kind) }
}
