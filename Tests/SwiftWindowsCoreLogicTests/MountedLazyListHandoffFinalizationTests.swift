import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Implicit source groups close during journal preparation, after the adapter
/// reserves a row replacement and before its physical handoff can activate.
@MainActor
final class MountedLazyListHandoffFinalizationTests: XCTestCase {
    func testStateObjectReplacementPublishesNewContentAndKeepsOwnedCells() async throws {
        let probe = LazyHandoffFinalizationProbe()
        let host = MountedLazyListTestHost { lazyHandoffObjectContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let list = try host.list()
        let row = try host.rowRoot("lazy.handoff.object.0.0")
        let attachment = row.captureLazyListAttachmentProof()
        let owner = try XCTUnwrap(probe.owners[0])
        let binding = try XCTUnwrap(probe.bindings[0])
        let model = try XCTUnwrap(probe.models[0])
        let resolves = host.runtime.lazyListResolveCount
        XCTAssertEqual(probe.rowFactories, [0: 1, 1: 1])

        binding.wrappedValue = 87
        probe.revision = 1
        host.reload()
        XCTAssertEqual(probe.rowFactories, [0: 1, 1: 1])
        XCTAssertNotNil(host.layout())

        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertTrue(adapter.hasCurrentLogicalSnapshot)
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertGreaterThan(host.runtime.lazyListResolveCount, resolves)
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        XCTAssertEqual(probe.rowFactories, [0: 2, 1: 2])
        XCTAssertEqual(probe.objectFactories, [0: 1, 1: 1])
        XCTAssertNil(host.find("lazy.handoff.object.0.0"))
        XCTAssertNil(host.find("lazy.handoff.object.1.0"))
        XCTAssertNotNil(host.find("lazy.handoff.object.1.1"))
        XCTAssertTrue(try host.rowRoot("lazy.handoff.object.0.1") === row)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertTrue(probe.owners[0] === owner)
        XCTAssertTrue(host.coordinator.registry.owner(at: owner.identity) === owner)
        XCTAssertTrue(probe.models[0] === model)
        XCTAssertEqual(probe.bindings[0]?.wrappedValue, 87)
        XCTAssertEqual(binding.wrappedValue, 87)
    }

    func testDeferredReaderReplacementFinishesBeforeAWidthOnlyRefresh() async throws {
        let probe = LazyHandoffFinalizationProbe()
        let host = MountedLazyListTestHost { lazyHandoffReaderContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let list = try host.list()
        let row = try host.rowRoot("lazy.handoff.reader.0")
        let attachment = row.captureLazyListAttachmentProof()
        let owner = try XCTUnwrap(probe.owners[0])
        let binding = try XCTUnwrap(probe.bindings[0])
        XCTAssertEqual(probe.rowFactories, [0: 1])

        binding.wrappedValue = 87
        probe.revision = 1
        host.reload()
        XCTAssertEqual(probe.rowFactories, [0: 1])
        XCTAssertNotNil(host.layout())

        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertTrue(adapter.hasCurrentLogicalSnapshot)
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertEqual(probe.rowFactories, [0: 2])
        XCTAssertNil(host.find("lazy.handoff.reader.0"))
        XCTAssertTrue(try host.rowRoot("lazy.handoff.reader.1") === row)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertTrue(probe.owners[0] === owner)
        XCTAssertTrue(host.coordinator.registry.owner(at: owner.identity) === owner)
        XCTAssertEqual(probe.bindings[0]?.wrappedValue, 87)

        let readerBuilds = probe.readerBuilds
        host.runtime.setRootSize(IntSize(width: 180, height: 40))
        XCTAssertNotNil(host.layout())

        XCTAssertTrue(adapter.hasCurrentLogicalSnapshot)
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertEqual(probe.rowFactories, [0: 2])
        XCTAssertGreaterThan(probe.readerBuilds, readerBuilds)
        XCTAssertEqual(probe.readerWidth, 180)
        XCTAssertTrue(try host.rowRoot("lazy.handoff.reader.1") === row)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertTrue(probe.owners[0] === owner)
        XCTAssertEqual(binding.wrappedValue, 87)
    }
}

@MainActor
private final class LazyHandoffFinalizationProbe {
    var revision = 0
    var rowFactories: [Int: Int] = [:]
    var objectFactories: [Int: Int] = [:]
    var owners: [Int: StateMountOwner] = [:]
    var bindings: [Int: Binding<Int>] = [:]
    var models: [Int: MountedLazyListModel] = [:]
    var readerBuilds = 0
    var readerWidth = 0.0

    func makeObjectRow(_ id: Int) -> LazyHandoffObjectRow {
        rowFactories[id, default: 0] += 1
        return LazyHandoffObjectRow(id: id, revision: revision, probe: self)
    }

    func makeReaderRow() -> LazyHandoffReaderRow {
        rowFactories[0, default: 0] += 1
        return LazyHandoffReaderRow(revision: revision, probe: self)
    }

    func makeModel(_ id: Int) -> MountedLazyListModel {
        objectFactories[id, default: 0] += 1
        return MountedLazyListModel(value: 100 + id, serial: objectFactories[id, default: 0])
    }

    func record(_ id: Int, binding: Binding<Int>, model: MountedLazyListModel? = nil) {
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            XCTFail("A managed row must install its owner before evaluating its body")
            return
        }
        owners[id] = owner
        bindings[id] = binding
        if let model { models[id] = model }
    }

    func recordReader(width: Double) {
        readerBuilds += 1
        readerWidth = width
    }

    func clear() {
        owners.removeAll()
        bindings.removeAll()
        models.removeAll()
    }
}

@MainActor
private struct LazyHandoffObjectRow: View {
    @State private var value = 41
    @StateObject private var model: MountedLazyListModel
    let id: Int
    let revision: Int
    let probe: LazyHandoffFinalizationProbe

    init(id: Int, revision: Int, probe: LazyHandoffFinalizationProbe) {
        self.id = id
        self.revision = revision
        self.probe = probe
        _model = StateObject(wrappedValue: probe.makeModel(id))
    }

    var body: some View {
        probe.record(id, binding: $value, model: model)
        return Color.blue.frame(height: 20)
            .accessibilityIdentifier("lazy.handoff.object.\(id).\(revision)")
    }
}

@MainActor
private struct LazyHandoffReaderRow: View {
    @State private var value = 41
    let revision: Int
    let probe: LazyHandoffFinalizationProbe

    var body: some View {
        probe.record(0, binding: $value)
        return GeometryReader { geometry in
            let _ = probe.recordReader(width: geometry.size.width)
            Color.blue.accessibilityIdentifier("lazy.handoff.reader.\(revision)")
        }
        .frame(height: 20)
    }
}

@MainActor
private func lazyHandoffObjectContent(_ probe: LazyHandoffFinalizationProbe) -> some View {
    ManagedLazyListContent(
        [0, 1], id: \.self, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { probe.makeObjectRow($0) }
}

@MainActor
private func lazyHandoffReaderContent(_ probe: LazyHandoffFinalizationProbe) -> some View {
    ManagedLazyListContent(
        [0], id: \.self, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { _ in probe.makeReaderRow() }
}
