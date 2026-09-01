import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Diagnostic duplicate of the original managed transport oracle. The original
/// test remains unchanged; the same 8-element/8-round budget and 24-pass bound
/// report where its existing request stops without granting new authority.
@MainActor
final class ManagedDeferredNavigationTrajectoryTests: XCTestCase {
    func testManagedNavigationTrajectoryAcrossTheExactOpaqueSearchBudgetBoundary() async throws {
        let probe = ManagedDeferredNavigationTrajectoryProbe(count: 32)
        let host = MountedLazyListTestHost(size: Size(width: 260, height: 200)) {
            List(selection: probe.binding) {
                ForEach(probe.rows, id: \.self) { probe.row($0, prefix: "Managed") }
            }
            .listStyle(.plain)
            .frame(width: 260, height: 200)
        }
        defer {
            probe.onSet = nil
            host.close()
        }
        XCTAssertNotNil(host.layout())
        XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 8))
        let targetList = try host.list()
        let oldKey = try XCTUnwrap(try managedRow(0, in: host).onKeyDown)
        XCTAssertNil(findManagedRow(24, in: host))
        probe.selected = 23
        var prepared: ViewNode?
        probe.onSet = { [weak host] in
            prepared = host?.nodes.first { DeferredListRowNavigation.attached(to: $0)?.ordinal == 24 }
        }
        let buildsBefore = host.events.rootCompletions
        let callsBefore = probe.factories.count

        var trajectory = [snapshot("before-key-1", in: host, list: targetList, probe: probe, since: 0)]

        oldKey(Self.down)
        trajectory.append(snapshot("after-key-1", in: host, list: targetList, probe: probe, since: callsBefore))
        XCTAssertLessThanOrEqual(probe.factories.count - callsBefore, 8, trajectory.joined(separator: "\n"))
        settleManagedNavigation(in: host, list: targetList, probe: probe, expected: 24, trajectory: &trajectory)

        let destination = try XCTUnwrap(prepared, trajectory.joined(separator: "\n"))
        XCTAssertTrue(try managedRow(24, in: host) === destination)
        XCTAssertTrue(host.runtime.focusedNode === destination)
        XCTAssertEqual(probe.writes, [24])
        XCTAssertEqual(host.events.rootCompletions, buildsBefore + 1)
        XCTAssertTrue(try host.list() === targetList)
        let incoming = try XCTUnwrap(targetList.retainedLazyListAdapter)
        XCTAssertTrue(incoming.ownsAttachment(targetList))
        let freshKey = try XCTUnwrap(destination.onKeyDown)
        probe.onSet = nil
        probe.resetTrace(selection: 24)
        oldKey(Self.down)
        assertNoEffects(probe)
        XCTAssertTrue(host.runtime.focusedNode === destination)

        trajectory.append(snapshot("before-key-2", in: host, list: targetList, probe: probe, since: 0))
        freshKey(Self.down)
        trajectory.append(snapshot("after-key-2", in: host, list: targetList, probe: probe, since: 0))
        XCTAssertLessThanOrEqual(probe.factories.count, 8, trajectory.joined(separator: "\n"))
        settleManagedNavigation(in: host, list: targetList, probe: probe, expected: 25, trajectory: &trajectory)

        XCTAssertEqual(probe.selected, 25)
        XCTAssertEqual(probe.writes, [25])
        XCTAssertTrue(host.runtime.focusedNode === (try managedRow(25, in: host)))
        XCTAssertEqual(host.events.rootCompletions, buildsBefore + 2)
        XCTAssertLessThan(try XCTUnwrap(try host.list().retainedLazyListAdapter).mountedRecordCount, 32)
    }

    private static var down: KeyboardEvent { KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue) }

    private func assertNoEffects(
        _ probe: ManagedDeferredNavigationTrajectoryProbe, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(probe.reads, 0, file: file, line: line)
        XCTAssertTrue(probe.writes.isEmpty, file: file, line: line)
        XCTAssertEqual(probe.invalidations, 0, file: file, line: line)
        XCTAssertTrue(probe.factories.isEmpty, file: file, line: line)
    }

    private func findManagedRow(_ ordinal: Int, in host: MountedLazyListTestHost) -> ViewNode? {
        host.nodes.first { DeferredListRowNavigation.attached(to: $0)?.ordinal == ordinal }
    }

    private func managedRow(_ ordinal: Int, in host: MountedLazyListTestHost) throws -> ViewNode {
        try XCTUnwrap(findManagedRow(ordinal, in: host))
    }

    private func settleManagedNavigation(
        in host: MountedLazyListTestHost, list: ViewNode, probe: ManagedDeferredNavigationTrajectoryProbe,
        expected: Int, trajectory: inout [String],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for pass in 0..<24 {
            let callsBefore = probe.factories.count
            host.render()
            trajectory.append(
                snapshot(
                    "selection-\(expected)-pass-\(pass + 1)", in: host, list: list, probe: probe, since: callsBefore))
            XCTAssertLessThanOrEqual(
                probe.factories.count - callsBefore, 8, trajectory.joined(separator: "\n"), file: file, line: line)
            let ordinal = host.runtime.focusedNode.flatMap { DeferredListRowNavigation.attached(to: $0)?.ordinal }
            if !host.runtime.hasPendingLayout, probe.selected == expected, ordinal == expected { return }
        }
        XCTFail(
            "The prepared focus must settle within the bounded passes\n" + trajectory.joined(separator: "\n"),
            file: file, line: line)
    }

    /// Read only native facts and the probe's existing primitive trace. No
    /// layout, realization, binding getter, action preparation or observer is
    /// added. Temporary node references end before the next original action.
    private func snapshot(
        _ boundary: String, in host: MountedLazyListTestHost, list: ViewNode,
        probe: ManagedDeferredNavigationTrajectoryProbe, since factoryIndex: Int
    ) -> String {
        let runtime = host.runtime
        let adapter = list.retainedLazyListAdapter
        let owner = list.parent?.listNavigationOwner
        let protected = owner?.currentActionProtectedNodes(in: runtime).count ?? 0
        let mounted = list.children.compactMap { DeferredListRowNavigation.attached(to: $0)?.ordinal }
        let focused = runtime.focusedNode.flatMap { DeferredListRowNavigation.attached(to: $0)?.ordinal }
        let sourceOwner = list.children.first {
            DeferredListRowNavigation.attached(to: $0)?.ordinal == 0
        }?.listNavigationOwner
        let settlement: String
        switch runtime.layoutSettlementStatus {
        case .settled: settlement = "settled"
        case .unsettled: settlement = "unsettled"
        case .unavailable: settlement = "unavailable"
        }
        let completion: String
        switch runtime.lastLazyListWorkCompletion {
        case .complete: completion = "complete"
        case .workRemaining: completion = "workRemaining"
        case .budgetExhausted: completion = "budgetExhausted"
        }
        let factories = Array(probe.factories.dropFirst(factoryIndex))
        return "\(boundary): selected=\(String(describing: probe.selected)) writes=\(probe.writes)"
            + " reads=\(probe.reads) factories=\(factories) mounted=\(mounted) focused=\(String(describing: focused))"
            + " pendingLayout=\(runtime.hasPendingLayout) settlement=\(settlement)"
            + " budget=\(runtime.lastLazyListConsumedElements)/\(runtime.lastLazyListConsumedRounds)/\(completion)"
            + " rootCompletions=\(host.events.rootCompletions) protected=\(protected)"
            + " scope=\(String(describing: owner.map(ObjectIdentifier.init)))"
            + " source=\(String(describing: sourceOwner.map(ObjectIdentifier.init)))"
            + " adapter=\(String(describing: adapter.map(ObjectIdentifier.init)))"
            + " claim=\(adapter?.ownsAttachment(list) == true)"
            + " snapshot=\(adapter?.hasCurrentLogicalSnapshot == true)"
            + " unresolved=\(adapter?.hasUnresolvedWork == true)"
            + " descriptor=\(adapter?.managedLogicalDescriptorBinding?.isCurrent == true)"
    }
}

@MainActor
private final class ManagedDeferredNavigationTrajectoryProbe {
    let rows: [Int]
    var selected: Int? = 0
    var reads = 0
    var writes: [Int?] = []
    var invalidations = 0
    var factories: [String] = []
    var geometrySizes: [Size] = []
    var onSet: (() -> Void)?

    init(count: Int = 4) { rows = Array(0..<count) }

    var binding: Binding<Int?> {
        Binding(
            get: {
                self.reads += 1
                return self.selected
            },
            set: {
                self.selected = $0
                self.writes.append($0)
                self.onSet?()
            })
    }

    func resetTrace(selection: Int? = 0) {
        selected = selection
        reads = 0
        writes = []
        invalidations = 0
        factories = []
    }

    func row(_ index: Int, prefix: String) -> some View {
        let label = "\(prefix) \(index)"
        factories.append(label)
        return Text(label).font(.system(size: 13)).frame(height: 32)
            .accessibilityIdentifier("transport-row-\(index)").tag(index)
    }

}
