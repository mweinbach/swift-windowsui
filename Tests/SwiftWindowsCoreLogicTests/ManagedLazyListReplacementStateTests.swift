import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Pins the descriptor-to-viewport gap without rendering or native scheduling.
@MainActor
final class ManagedLazyListReplacementStateTests: XCTestCase {
    func testDescriptorReplacementKeepsMountedRowsBeforeAnyViewportWork() async throws {
        let probe = ManagedListReplacementStateProbe()
        let host = MountedLazyListTestHost { managedListReplacementStateContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let captured = try probe.capture(0, in: host)
        let list = try host.list()
        let oldAdapter = try XCTUnwrap(list.retainedLazyListAdapter)
        let oldBinding = try XCTUnwrap(oldAdapter.managedLogicalDescriptorBinding)
        let row = try host.rowRoot("replacement.state.0")
        let attachment = row.captureLazyListAttachmentProof()
        let factoryCalls = probe.rowFactoryCalls

        host.reload()

        let successorList = try host.list()
        let successor = try XCTUnwrap(successorList.retainedLazyListAdapter)
        let binding = try XCTUnwrap(successor.managedLogicalDescriptorBinding)
        XCTAssertTrue(successorList === list)
        XCTAssertFalse(successor === oldAdapter)
        XCTAssertFalse(binding.descriptor === oldBinding.descriptor)
        XCTAssertTrue(binding.scope === oldBinding.scope)
        XCTAssertTrue(binding.isCurrent)
        XCTAssertTrue(try host.rowRoot("replacement.state.0") === row)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertTrue(captured.owner.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: captured.owner.identity) === captured.owner)
        XCTAssertEqual(probe.rowFactoryCalls, factoryCalls, "A descriptor rebuild must not evaluate row factories")
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
        XCTAssertEqual(host.events.rootCompletions, 2)
    }

    func testSynchronousStateInvalidationKeepsOriginalCellsBeforeLayout() async throws {
        let probe = ManagedListReplacementStateProbe()
        let host = MountedLazyListTestHost { managedListReplacementStateContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let captured = try probe.capture(0, in: host)
        let row = try host.rowRoot("replacement.state.0")
        let factoryCalls = probe.rowFactoryCalls
        let invalidations = host.events.stateInvalidations
        let completions = host.events.rootCompletions

        captured.counter.wrappedValue = 41

        XCTAssertEqual(host.events.stateInvalidations, invalidations + 1)
        XCTAssertEqual(host.events.rootCompletions, completions + 1)
        XCTAssertTrue(captured.owner.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: captured.owner.identity) === captured.owner)
        XCTAssertTrue(try host.rowRoot("replacement.state.0") === row)
        XCTAssertEqual(probe.rowFactoryCalls, factoryCalls)
        captured.objectValue.wrappedValue = 17
        XCTAssertEqual(captured.counter.wrappedValue, 41)
        XCTAssertEqual(captured.model.value, 17)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)

        XCTAssertNotNil(host.layout())

        let current = try probe.capture(0, in: host)
        XCTAssertTrue(current.owner === captured.owner)
        XCTAssertTrue(current.model === captured.model)
        XCTAssertTrue(try host.rowRoot("replacement.state.0") === row)
        XCTAssertEqual(current.counter.wrappedValue, 41)
        XCTAssertEqual(current.model.value, 17)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
    }

    func testAcceptedDeletionRetiresOnlyRemovedOwnershipBeforeViewportWork() async throws {
        let probe = ManagedListReplacementStateProbe()
        let host = MountedLazyListTestHost { managedListReplacementStateContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let removed = try probe.capture(0, in: host)
        let retained = try probe.capture(1, in: host)
        let factoryCalls = probe.rowFactoryCalls

        probe.rows.removeAll { $0.id == 0 }
        host.reload()

        XCTAssertFalse(removed.owner.isLive)
        XCTAssertNil(host.coordinator.registry.owner(at: removed.owner.identity))
        XCTAssertTrue(retained.owner.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: retained.owner.identity) === retained.owner)
        XCTAssertEqual(probe.rowFactoryCalls, factoryCalls)
        let invalidations = host.events.stateInvalidations
        removed.counter.wrappedValue = 500
        removed.objectValue.wrappedValue = 600
        XCTAssertEqual(removed.counter.wrappedValue, 100)
        XCTAssertEqual(removed.model.value, 100)
        XCTAssertEqual(host.events.stateInvalidations, invalidations)

        XCTAssertNotNil(host.layout())

        let current = try probe.capture(1, in: host)
        XCTAssertTrue(current.owner === retained.owner)
        XCTAssertTrue(current.model === retained.model)
        XCTAssertEqual(probe.objectFactoryCalls[1], 1)
        XCTAssertNil(host.find("replacement.state.0"), probe.diagnostic(in: host))
    }

    func testAcceptedAbsenceThenReinsertionCannotReviveCellsBeforeViewportWork() async throws {
        let probe = ManagedListReplacementStateProbe()
        let host = MountedLazyListTestHost { managedListReplacementStateContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let removed = try probe.capture(0, in: host)
        let retained = try probe.capture(1, in: host)

        probe.rows.removeAll { $0.id == 0 }
        host.reload()
        XCTAssertFalse(removed.owner.isLive)
        probe.rows.insert(ManagedListReplacementStateData(id: 0, seed: 900), at: 0)
        host.reload()

        XCTAssertFalse(removed.owner.isLive)
        XCTAssertTrue(retained.owner.isLive)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
        removed.counter.wrappedValue = 500
        removed.objectValue.wrappedValue = 600
        XCTAssertEqual(removed.counter.wrappedValue, 100)
        XCTAssertEqual(removed.model.value, 100)

        XCTAssertNotNil(host.layout())

        let replacement = try probe.capture(0, in: host)
        XCTAssertFalse(replacement.owner === removed.owner)
        XCTAssertNotEqual(replacement.owner.generation, removed.owner.generation)
        XCTAssertFalse(replacement.model === removed.model)
        XCTAssertEqual(replacement.counter.wrappedValue, 900)
        XCTAssertEqual(replacement.model.value, 900)
        XCTAssertEqual(probe.objectFactoryCalls[0], 2)
        XCTAssertTrue(try probe.capture(1, in: host).owner === retained.owner)
        XCTAssertEqual(probe.objectFactoryCalls[1], 1)
    }
}

private struct ManagedListReplacementStateData {
    let id: Int
    let seed: Int
}

@MainActor
private struct ManagedListReplacementStateCapture {
    let owner: StateMountOwner
    let counter: Binding<Int>
    let objectValue: Binding<Int>
    let model: MountedLazyListModel
}

@MainActor
private final class ManagedListReplacementStateProbe {
    var rows = [
        ManagedListReplacementStateData(id: 0, seed: 100),
        ManagedListReplacementStateData(id: 1, seed: 101),
    ]
    private(set) var rowFactoryCalls: [Int: Int] = [:]
    private(set) var objectFactoryCalls: [Int: Int] = [:]
    private var captures: [Int: ManagedListReplacementStateCapture] = [:]

    func makeRow(_ data: ManagedListReplacementStateData) -> ManagedListReplacementStateRow {
        rowFactoryCalls[data.id, default: 0] += 1
        return ManagedListReplacementStateRow(data: data, probe: self)
    }

    func makeModel(_ data: ManagedListReplacementStateData) -> MountedLazyListModel {
        objectFactoryCalls[data.id, default: 0] += 1
        return MountedLazyListModel(value: data.seed, serial: objectFactoryCalls[data.id, default: 0])
    }

    func record(
        _ id: Int, owner: StateMountOwner?, counter: Binding<Int>,
        objectValue: Binding<Int>, model: MountedLazyListModel
    ) {
        guard let owner else {
            XCTFail("The actual managed row must install an owner before evaluating its body")
            return
        }
        captures[id] = ManagedListReplacementStateCapture(
            owner: owner, counter: counter, objectValue: objectValue, model: model)
    }

    func capture(
        _ id: Int, in host: MountedLazyListTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ManagedListReplacementStateCapture {
        let captured = try XCTUnwrap(captures[id], file: file, line: line)
        XCTAssertTrue(
            host.coordinator.registry.owner(at: captured.owner.identity) === captured.owner,
            diagnostic(in: host), file: file, line: line)
        return captured
    }

    func diagnostic(in host: MountedLazyListTestHost) -> String {
        let adapters = host.lists.compactMap(\.retainedLazyListAdapter).map { adapter in
            "logicalCurrent=\(adapter.hasCurrentLogicalSnapshot) unresolved=\(adapter.hasUnresolvedWork) "
                + "logical=\(adapter.logicalRecordCount) mounted=\(adapter.mountedRecordCount) "
                + "leaves=\(adapter.mountedLeafCount) bindingCurrent=\(String(describing: adapter.managedLogicalDescriptorBinding?.isCurrent))"
        }
        let offsets = host.nodes.filter { $0.scrollAxis == .vertical }.map(\.scrollOffset)
        return "completion=\(host.runtime.lastLazyListWorkCompletion) "
            + "rounds=\(host.runtime.lastLazyListConsumedRounds) elements=\(host.runtime.lastLazyListConsumedElements) "
            + "resolves=\(host.runtime.lazyListResolveCount) scrollOffsets=\(offsets) "
            + "adapters=\(adapters) rowFactories=\(rowFactoryCalls) objectFactories=\(objectFactoryCalls)"
    }

    func clear() { captures.removeAll() }
}

@MainActor
private struct ManagedListReplacementStateRow: View {
    @State private var counter: Int
    @StateObject private var model: MountedLazyListModel
    let id: Int
    let probe: ManagedListReplacementStateProbe

    init(data: ManagedListReplacementStateData, probe: ManagedListReplacementStateProbe) {
        id = data.id
        self.probe = probe
        _counter = State(initialValue: data.seed)
        _model = StateObject(wrappedValue: probe.makeModel(data))
    }

    var body: some View {
        probe.record(
            id, owner: ViewBuildContextScope.current?.viewIdentity.installedOwner,
            counter: $counter, objectValue: $model.value, model: model)
        return Color.blue.frame(width: 120, height: 20)
            .accessibilityIdentifier("replacement.state.\(id)")
    }
}

@MainActor
private func managedListReplacementStateContent(_ probe: ManagedListReplacementStateProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.id, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { probe.makeRow($0) }
}
