import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The source route exercises the same logical realization as native UIA,
/// without a COM provider, native window, or an extra layout after Realize.
@MainActor
final class ManagedListUIARealizationBudgetTests: XCTestCase {
    func testPendingReplacementRealizesWithinDefaultSharedBudget() async throws {
        try assertPendingReplacementRealizes(roundLimit: nil)
    }

    func testPendingReplacementRealizesWithinExplicitSharedBudget() async throws {
        try assertPendingReplacementRealizes(roundLimit: 8)
    }

    func testPendingReplacementRealizesWithinSixteenSharedRounds() async throws {
        try assertPendingReplacementRealizes(roundLimit: 16)
    }

    func testPendingReplacementCannotRechargeAnExhaustedSharedBudget() async throws {
        let fixture = try ManagedListUIARealizationBudgetFixture()
        defer { fixture.host.close() }
        let elementID = try fixture.item(at: 300)
        let identities = fixture.source.logicalItemIdentityCount
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        fixture.host.reload()
        let factories = fixture.probe.factories.count

        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: elementID)

        XCTAssertFalse(completed)
        XCTAssertEqual(fixture.probe.factories.count - factories, 1)
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertEqual(fixture.host.runtime.lastLazyListConsumedElements, 1)
        XCTAssertEqual(fixture.host.runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(fixture.source.logicalItemIdentityCount, identities)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .placeholder)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    private func assertPendingReplacementRealizes(
        roundLimit: Int?, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try ManagedListUIARealizationBudgetFixture()
        defer { fixture.host.close() }
        let elementID = try fixture.item(at: 300)
        let witness = try XCTUnwrap(
            fixture.host.runtime.lazyListAccessibilityItem(in: try fixture.host.list()), file: file, line: line)
        let identities = fixture.source.logicalItemIdentityCount
        if let roundLimit {
            XCTAssertTrue(
                fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: roundLimit),
                file: file, line: line)
        }
        fixture.host.reload()
        XCTAssertNil(fixture.host.runtime.lazyListAccessibilityGeneration(for: witness), file: file, line: line)
        let factories = fixture.probe.factories.count
        XCTAssertEqual(
            fixture.source.uiaLogicalItemState(elementID: elementID), .placeholder, file: file, line: line)
        XCTAssertEqual(fixture.probe.factories.count, factories, file: file, line: line)

        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: elementID)

        // Diagnostics read only the completed call's stored result and tree.
        // In particular, no failure path obtains a fresh settlement or snapshot.
        let detail = fixture.passiveRealizationDetails()
        XCTAssertTrue(completed, detail, file: file, line: line)
        XCTAssertTrue(fixture.probe.factories.contains(300), detail, file: file, line: line)
        XCTAssertLessThan(fixture.probe.factories.count - factories, 128, detail, file: file, line: line)
        XCTAssertLessThanOrEqual(
            fixture.host.runtime.lastLazyListConsumedRounds, roundLimit ?? 4, detail, file: file, line: line)
        XCTAssertEqual(fixture.source.logicalItemIdentityCount, identities, detail, file: file, line: line)
        XCTAssertEqual(
            fixture.source.uiaLogicalItemState(elementID: elementID), .ordinary, detail, file: file, line: line)
        XCTAssertTrue(fixture.probe.activations.isEmpty, file: file, line: line)
    }
}

@MainActor
private final class ManagedListUIARealizationBudgetProbe {
    let rows = Array(0..<1000)
    var factories: [Int] = []
    var activations: [Int] = []

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        return [AnyView(Button("Row \(id)") { [weak self] in self?.activations.append(id) }.frame(height: 24))]
    }
}

@MainActor
private final class ManagedListUIARealizationBudgetFixture {
    let probe = ManagedListUIARealizationBudgetProbe()
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let containerID: UInt64

    init() throws {
        let probe = probe
        host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
        }
        source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        XCTAssertNotNil(host.layout())
        do {
            containerID = try XCTUnwrap(source.uiaElementSnapshots().first(where: \.supportsItemContainer)?.id)
        } catch {
            host.close()
            throw error
        }
    }

    func item(at index: Int) throws -> UInt64 {
        var current: UInt64?
        for _ in 0...index {
            let result = source.uiaFindItem(containerID: containerID, afterElementID: current)
            guard case .item(let id) = result else {
                XCTFail("Expected the next current logical List item, got \(result)")
                return try XCTUnwrap(nil as UInt64?)
            }
            current = id
        }
        return try XCTUnwrap(current)
    }

    func passiveRealizationDetails() -> String {
        let runtime = host.runtime
        let adapters = host.lists.compactMap(\.retainedLazyListAdapter)
        let states = adapters.map {
            "logical=\($0.hasCurrentLogicalSnapshot), unresolved=\($0.hasUnresolvedWork), "
                + "mounted=\($0.mountedRecordCount)"
        }
        return "elements=\(runtime.lastLazyListConsumedElements), rounds=\(runtime.lastLazyListConsumedRounds), "
            + "completion=\(runtime.lastLazyListWorkCompletion), settlement=\(runtime.layoutSettlementStatus), "
            + "adapters=\(states), factories=\(probe.factories)"
    }
}
