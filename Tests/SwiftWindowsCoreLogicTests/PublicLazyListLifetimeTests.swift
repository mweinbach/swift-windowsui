import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The same managed host used by the internal lifecycle fixtures now enters
/// through public List data and List { ForEach } declarations. No native host,
/// scheduler, or renderer execution is implied by these headless tests.
@MainActor
final class PublicLazyListLifetimeTests: XCTestCase {
    func testDataAndBuilderFactoriesWaitForViewportAndKeepPhysicalRowsBounded() async throws {
        for builder in [false, true] {
            let probe = PublicListLifetimeProbe(count: 10_000)
            let host = MountedLazyListTestHost { publicLifetimeList(probe, builder: builder) }
            defer {
                host.close()
                probe.releaseAllTasks()
            }
            try host.assertCommittedDescriptor()
            XCTAssertTrue(probe.constructed.isEmpty)
            XCTAssertTrue(probe.models.isEmpty)
            let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
            XCTAssertEqual(adapter.logicalRecordCount, 10_000)
            XCTAssertEqual(adapter.mountedRecordCount, 0)

            XCTAssertNotNil(host.layout())

            XCTAssertFalse(probe.constructed.isEmpty)
            XCTAssertLessThan(probe.constructed.count, 128)
            XCTAssertLessThan(adapter.mountedRecordCount, 32)
            XCTAssertLessThan(adapter.mountedLeafCount, 64)
            XCTAssertNil(probe.captures[9000])
            XCTAssertTrue(probe.starts.isEmpty, "Layout cannot start appearance-scoped tasks")
        }
    }

    func testOffscreenStateAndObjectSurviveWithoutRetainingThePhysicalRow() async throws {
        for builder in [false, true] {
            let probe = PublicListLifetimeProbe()
            let host = MountedLazyListTestHost { publicLifetimeList(probe, builder: builder) }
            defer {
                host.close()
                probe.releaseAllTasks()
            }
            XCTAssertNotNil(host.layout())
            let original = try XCTUnwrap(probe.captures[0])
            let lifetime = try physicalLifetime(of: 0, in: host)
            let ownerGeneration = original.owner.generation
            let factoriesBefore = probe.constructed.filter { $0 == 0 }.count

            try host.scroll(to: 4000)
            XCTAssertFalse(lifetime.attachment.isCurrent)
            XCTAssertNil(lifetime.node.value, "Evicted row nodes are not retained with their state cells")
            XCTAssertTrue(original.owner.isLive)
            original.value.wrappedValue = 41
            original.object.value = 17
            XCTAssertNotNil(host.layout())
            XCTAssertNil(host.find("public.lifetime.0"))
            XCTAssertEqual(probe.constructed.filter { $0 == 0 }.count, factoriesBefore)

            try host.scroll(to: 0)
            let returned = try XCTUnwrap(probe.captures[0])
            XCTAssertTrue(returned.owner === original.owner)
            XCTAssertEqual(returned.owner.generation, ownerGeneration)
            XCTAssertEqual(returned.value.wrappedValue, 41)
            XCTAssertTrue(returned.object === original.object)
            XCTAssertEqual(returned.object.value, 17)
            XCTAssertEqual(probe.models[0], 1)
            XCTAssertFalse(lifetime.attachment.isCurrent)
            XCTAssertLessThan(try XCTUnwrap(try host.list().retainedLazyListAdapter).mountedRecordCount, 32)
        }
    }

    func testColdRemovalAndReinsertCreateNewStateWithoutRevivingEscapedBinding() async throws {
        for builder in [false, true] {
            let probe = PublicListLifetimeProbe()
            let host = MountedLazyListTestHost { publicLifetimeList(probe, builder: builder) }
            defer {
                host.close()
                probe.releaseAllTasks()
            }
            XCTAssertNotNil(host.layout())
            let original = try XCTUnwrap(probe.captures[0])
            original.value.wrappedValue = 41
            try host.scroll(to: 4000)
            probe.rows.removeAll { $0.id == 0 }
            host.reload()
            XCTAssertNotNil(host.layout())
            XCTAssertFalse(original.owner.isLive)
            XCTAssertNil(host.coordinator.registry.owner(at: original.owner.identity))

            probe.rows.insert(PublicListLifetimeData(id: 0, seed: 900), at: 0)
            host.reload()
            try host.scroll(to: 0)
            let replacement = try XCTUnwrap(probe.captures[0])
            XCTAssertFalse(replacement.owner === original.owner)
            XCTAssertNotEqual(replacement.owner.generation, original.owner.generation)
            XCTAssertFalse(replacement.object === original.object)
            XCTAssertEqual(replacement.value.wrappedValue, 900)
            let invalidations = host.events.stateInvalidations
            original.value.wrappedValue = 8000
            XCTAssertEqual(original.value.wrappedValue, 41)
            XCTAssertEqual(replacement.value.wrappedValue, 900)
            XCTAssertEqual(host.events.stateInvalidations, invalidations)
        }
    }

    func testAcceptedReorderKeepsKeyedStateAndSurvivingPhysicalRow() async throws {
        let probe = PublicListLifetimeProbe()
        let host = MountedLazyListTestHost { publicLifetimeList(probe, builder: true) }
        defer {
            host.close()
            probe.releaseAllTasks()
        }
        XCTAssertNotNil(host.layout())
        let original = try XCTUnwrap(probe.captures[0])
        let originalRoot = try host.rowRoot("public.lifetime.0")
        original.value.wrappedValue = 41
        XCTAssertNotNil(host.layout())
        probe.rows.swapAt(0, 1)
        host.reload()
        XCTAssertNotNil(host.layout())
        let reordered = try XCTUnwrap(probe.captures[0])
        XCTAssertTrue(reordered.owner === original.owner)
        XCTAssertTrue(reordered.object === original.object)
        XCTAssertEqual(reordered.value.wrappedValue, 41)
        XCTAssertTrue(try host.rowRoot("public.lifetime.0") === originalRoot)
        XCTAssertEqual(probe.models[0], 1)
    }

    func testEvictionCancelsTaskAndReturnStartsOnlyANewPhysicalTask() async throws {
        let probe = PublicListLifetimeProbe()
        let host = MountedLazyListTestHost { publicLifetimeList(probe, builder: true) }
        defer {
            host.close()
            probe.releaseAllTasks()
        }
        let started = expectation(description: "First visible row task started")
        probe.onStart = { if $0 == 0 { started.fulfill() } }
        host.render()
        await fulfillment(of: [started], timeout: 5)
        probe.onStart = nil
        let original = try XCTUnwrap(probe.captures[0])
        let cancelled = expectation(description: "Evicted physical task cancelled")
        probe.onCancel = { if $0 == 0 { cancelled.fulfill() } }
        try host.scroll(to: 4000)
        await fulfillment(of: [cancelled], timeout: 5)
        probe.onCancel = nil
        XCTAssertEqual(probe.starts.filter { $0 == 0 }.count, 1)
        XCTAssertEqual(probe.cancellations.filter { $0 == 0 }.count, 1)
        XCTAssertTrue(original.owner.isLive)
        XCTAssertNil(host.find("public.lifetime.0"))

        let returned = expectation(description: "Returned physical row starts its new task")
        probe.onStart = { if $0 == 0 { returned.fulfill() } }
        try host.scroll(to: 0)
        host.render()
        await fulfillment(of: [returned], timeout: 5)
        probe.onStart = nil
        XCTAssertEqual(probe.starts.filter { $0 == 0 }.count, 2)
        XCTAssertTrue(try XCTUnwrap(probe.captures[0]).owner === original.owner)
        XCTAssertEqual(probe.models[0], 1)
    }

    func testStableTaskIDDoesNotRestartOnAcceptedPublicListRebuild() async throws {
        let probe = PublicListLifetimeProbe()
        let host = MountedLazyListTestHost { publicLifetimeList(probe, builder: false) }
        defer {
            host.close()
            probe.releaseAllTasks()
        }
        let started = expectation(description: "Initial public row task")
        probe.onStart = { if $0 == 0 { started.fulfill() } }
        host.render()
        await fulfillment(of: [started], timeout: 5)
        probe.onStart = nil
        let root = try host.rowRoot("public.lifetime.0")
        let capture = try XCTUnwrap(probe.captures[0])
        capture.value.wrappedValue = 42
        host.render()
        XCTAssertTrue(try host.rowRoot("public.lifetime.0") === root)
        XCTAssertEqual(probe.starts.filter { $0 == 0 }.count, 1)
        XCTAssertTrue(probe.cancellations.filter { $0 == 0 }.isEmpty)
        XCTAssertTrue(try XCTUnwrap(probe.captures[0]).object === capture.object)
    }

    func testOversizedRecordIsRejectedBeforeConstructingItsPhysicalSiblings() async throws {
        let probe = PublicListSiblingBudgetProbe()
        let host = MountedLazyListTestHost {
            List([0], id: \.self) { _ in
                probe.rowFactories += 1
                return (0..<2050).map { _ in AnyView(PublicListSiblingBudgetLeaf(probe: probe)) }
            }
        }
        defer { host.close() }
        XCTAssertEqual(probe.rowFactories, 0)
        _ = host.layout()
        XCTAssertEqual(probe.rowFactories, 1)
        XCTAssertEqual(probe.nodeFactories, 0, "Sibling count admission precedes component and node factories")
        XCTAssertEqual(try XCTUnwrap(try host.list().retainedLazyListAdapter).mountedLeafCount, 0)
        for _ in 0..<8 { host.render() }
        XCTAssertEqual(probe.rowFactories, 1, "A terminal unsupported shape must not retry on every frame")
        XCTAssertEqual(probe.nodeFactories, 0)
    }

    @inline(never)
    private func physicalLifetime(of row: Int, in host: MountedLazyListTestHost) throws -> PublicListPhysicalLifetime {
        let node = try host.rowRoot("public.lifetime.\(row)")
        return PublicListPhysicalLifetime(
            node: PublicListWeakNode(node), attachment: node.captureLazyListAttachmentProof())
    }
}

@MainActor
private final class PublicListSiblingBudgetProbe {
    var rowFactories = 0
    var nodeFactories = 0
}

@MainActor
private struct PublicListSiblingBudgetLeaf: View {
    typealias Body = Never
    let probe: PublicListSiblingBudgetProbe
    var body: Never { fatalError("Primitive") }
    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            probe.nodeFactories += 1
            return Controls.label("Leaf")
        }
    }
}

@MainActor
private struct PublicListPhysicalLifetime {
    let node: PublicListWeakNode
    let attachment: RetainedLazyListAttachmentProof
}

@MainActor
private final class PublicListWeakNode {
    weak var value: ViewNode?
    init(_ value: ViewNode) { self.value = value }
}

private struct PublicListLifetimeData: Identifiable {
    let id: Int
    let seed: Int
}

@MainActor
private final class PublicListLifetimeModel: ObservableObject {
    @Published var value: Int
    init(value: Int) { self.value = value }
}

@MainActor
private struct PublicListLifetimeCapture {
    let owner: StateMountOwner
    let value: Binding<Int>
    let object: PublicListLifetimeModel
}

@MainActor
private final class PublicListLifetimeProbe {
    var rows: [PublicListLifetimeData]
    var constructed: [Int] = []
    var models: [Int: Int] = [:]
    var captures: [Int: PublicListLifetimeCapture] = [:]
    var starts: [Int] = []
    var cancellations: [Int] = []
    var onStart: ((Int) -> Void)?
    var onCancel: ((Int) -> Void)?
    private var nextRun = 0
    private var running: [Int: (row: Int, continuation: CheckedContinuation<Void, Never>)] = [:]

    init(count: Int = 1000) { rows = (0..<count).map { PublicListLifetimeData(id: $0, seed: $0 + 100) } }

    func model(for data: PublicListLifetimeData) -> PublicListLifetimeModel {
        models[data.id, default: 0] += 1
        return PublicListLifetimeModel(value: data.seed)
    }

    func capture(row: Int, value: Binding<Int>, object: PublicListLifetimeModel) {
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            XCTFail("Public row State must have a mounted owner")
            return
        }
        captures[row] = PublicListLifetimeCapture(owner: owner, value: value, object: object)
    }

    func run(row: Int) async {
        nextRun += 1
        let run = nextRun
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                running[run] = (row, continuation)
                starts.append(row)
                onStart?(row)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(run: run) }
        }
    }

    private func cancel(run: Int) {
        guard let task = running.removeValue(forKey: run) else { return }
        cancellations.append(task.row)
        task.continuation.resume()
        onCancel?(task.row)
    }

    func releaseAllTasks() {
        onStart = nil
        onCancel = nil
        let tasks = running.values.map(\.continuation)
        running.removeAll()
        for task in tasks { task.resume() }
    }
}

@MainActor
private struct PublicListLifetimeRow: View {
    @State private var value: Int
    @StateObject private var object: PublicListLifetimeModel
    let row: Int
    let probe: PublicListLifetimeProbe

    init(data: PublicListLifetimeData, probe: PublicListLifetimeProbe) {
        self.row = data.id
        self.probe = probe
        probe.constructed.append(data.id)
        _value = State(initialValue: data.seed)
        _object = StateObject(wrappedValue: probe.model(for: data))
    }

    var body: some View {
        probe.capture(row: row, value: $value, object: object)
        let row = row
        let probe = probe
        return Text("Row \(row): \(value)").frame(width: 100, height: 24)
            .accessibilityIdentifier("public.lifetime.\(row)")
            .task(id: row) { await probe.run(row: row) }
    }
}

@MainActor
@ViewBuilder
private func publicLifetimeList(_ probe: PublicListLifetimeProbe, builder: Bool) -> some View {
    if builder {
        List { ForEach(probe.rows) { PublicListLifetimeRow(data: $0, probe: probe) } }
    } else {
        List(probe.rows) { PublicListLifetimeRow(data: $0, probe: probe) }
    }
}
