import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public List readers use the same typed UIA route as the platform bridge.
/// The explicit allowance isolates reader ownership from the default-budget
/// regression; it does not replace or relax that separate four-round oracle.
@MainActor
final class ManagedListUIAReaderAuthorityTests: XCTestCase {
    func testFarManagedReaderResolvesBeforeTheUIACallReturns() async throws {
        let fixture = try ManagedListUIAReaderFixture()
        defer { fixture.close() }
        let element = try fixture.item(at: 300)
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertNil(fixture.probe.readerSizes[300])
        let factories = fixture.probe.factories.count

        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: element)

        XCTAssertTrue(completed)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: element), .ordinary)
        XCTAssertTrue(fixture.probe.factories.contains(300))
        XCTAssertLessThan(fixture.probe.factories.count - factories, 128)
        XCTAssertLessThanOrEqual(fixture.host.runtime.lastLazyListConsumedElements, 128)
        XCTAssertLessThanOrEqual(fixture.host.runtime.lastLazyListConsumedRounds, 16)
        let row = try fixture.host.rowRoot(fixture.identifier(300))
        let reader = try fixture.reader(in: row)
        let sizes = try XCTUnwrap(fixture.probe.readerSizes[300])
        XCTAssertGreaterThanOrEqual(sizes.count, 2, "The far row must complete its deferred reader body")
        XCTAssertNotEqual(sizes.first, sizes.last)
        XCTAssertEqual(sizes.last, reader.geometryReaderBuiltSize)
        XCTAssertEqual(reader.geometryReaderBuiltSize, reader.resolvedFrame.size)
        XCTAssertGreaterThan(reader.resolvedFrame.width, 0)
        XCTAssertGreaterThan(reader.resolvedFrame.height, 0)
        XCTAssertNotNil(reader.retainedSubtreeBuildLease)
        XCTAssertTrue(row.retainedLazyListRuntime === fixture.host.runtime)
        XCTAssertFalse(row.isLayoutDeferredByVirtualization)
        XCTAssertTrue(fixture.host.runtime.hasCurrentAccessibilityPrepaint)
        try fixture.assertSettledWithoutQuery()
    }

    func testFinishedUIARequestDoesNotExpireAcceptedReaderState() async throws {
        let fixture = try ManagedListUIAReaderFixture()
        defer { fixture.close() }
        let element = try fixture.item(at: 300)
        XCTAssertTrue(fixture.source.uiaRealizeVirtualizedItem(elementID: element))
        try fixture.assertSettledWithoutQuery()
        let row = try fixture.host.rowRoot(fixture.identifier(300))
        let attachment = row.captureLazyListAttachmentProof()
        let reader = try fixture.reader(in: row)
        let previousWidth = reader.resolvedFrame.width
        let previousCalls = fixture.probe.readerSizes[300, default: []].count
        let owner = try XCTUnwrap(fixture.probe.owners[300])
        let binding = try XCTUnwrap(fixture.probe.bindings[300])
        XCTAssertTrue(owner.isLive)

        // The synchronous platform operation has finished. This new ordinary
        // width refresh must use the accepted row, not its old UIA authority.
        fixture.host.runtime.setRootSize(IntSize(width: 400, height: 80))
        XCTAssertNotNil(fixture.host.layout())

        XCTAssertTrue(try fixture.host.rowRoot(fixture.identifier(300)) === row)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertTrue(fixture.probe.owners[300] === owner)
        XCTAssertTrue(fixture.host.coordinator.registry.owner(at: owner.identity) === owner)
        XCTAssertTrue(owner.isLive)
        XCTAssertEqual(binding.wrappedValue, 41)
        XCTAssertGreaterThan(fixture.probe.readerSizes[300, default: []].count, previousCalls)
        XCTAssertEqual(reader.resolvedFrame.width, previousWidth + 80, accuracy: 0.001)
        XCTAssertEqual(fixture.probe.readerSizes[300]?.last, reader.geometryReaderBuiltSize)
        XCTAssertEqual(reader.geometryReaderBuiltSize, reader.resolvedFrame.size)

        binding.wrappedValue = 87
        XCTAssertNotNil(fixture.host.layout())

        XCTAssertTrue(fixture.probe.owners[300] === owner)
        XCTAssertEqual(fixture.probe.bindings[300]?.wrappedValue, 87)
        XCTAssertEqual(binding.wrappedValue, 87)
    }

    func testManagedDeferredBodyRejectsRestoredScrollIntentAndAllowsANewRequest() async throws {
        let fixture = try ManagedListUIAReaderFixture()
        defer { fixture.close() }
        let element = try fixture.item(at: 300)
        let scroll = try fixture.host.scrollContainer()
        fixture.probe.onReader = { [weak fixture, weak scroll] id, _ in
            guard let fixture, let scroll, id == 300,
                fixture.probe.readerSizes[id, default: []].count == 2
            else { return }
            fixture.probe.interventions += 1
            let offset = scroll.scrollOffset
            scroll.scrollOffset = offset + 1
            scroll.scrollOffset = offset
        }

        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: element)

        XCTAssertFalse(completed)
        XCTAssertEqual(fixture.probe.interventions, 1)
        XCTAssertEqual(fixture.probe.readerSizes[300]?.count, 2)
        XCTAssertEqual(scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)

        fixture.probe.onReader = nil
        XCTAssertNotNil(fixture.host.layout())
        XCTAssertTrue(fixture.source.uiaRealizeVirtualizedItem(elementID: element))

        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: element), .ordinary)
        try fixture.assertSettledWithoutQuery()
        let reader = try fixture.reader(in: fixture.host.rowRoot(fixture.identifier(300)))
        XCTAssertEqual(reader.geometryReaderBuiltSize, reader.resolvedFrame.size)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
    }

    func testManagedReaderHostCloseFinishesTheAlreadyStartedBuild() async throws {
        let fixture = try ManagedListUIAReaderFixture()
        defer { fixture.close() }
        let element = try fixture.item(at: 300)
        fixture.probe.onReader = { [weak fixture] id, _ in
            guard let fixture, id == 300, fixture.probe.readerSizes[id, default: []].count == 2 else { return }
            fixture.probe.interventions += 1
            fixture.probe.closingReaderEpoch = ViewBuildContextScope.current?.viewIdentity.installedEpoch
            XCTAssertNotNil(fixture.probe.closingReaderEpoch)
            XCTAssertTrue(fixture.host.runtime.hasActiveRetainedBuild)
            fixture.host.close()
        }

        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: element)

        XCTAssertFalse(completed)
        XCTAssertEqual(fixture.probe.interventions, 1)
        XCTAssertTrue(fixture.host.isClosed)
        XCTAssertTrue(fixture.host.coordinator.registry.isClosed)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
        XCTAssertTrue(fixture.probe.owners.values.allSatisfy { !$0.isLive })
        XCTAssertEqual(fixture.host.coordinator.registry.liveOwnerCount, 0)
        XCTAssertEqual(fixture.host.coordinator.registry.retiringOwnerCount, 0)
        // The closed host remains strongly owned by this fixture. Its managed
        // coordinator keeps the started build and epoch until the ordinary
        // finishAfterCallbacks boundary runs, even after abandon drains State.
        XCTAssertNil(fixture.probe.closingReaderEpoch)
    }
}

@MainActor
private final class ManagedListUIAReaderFixture {
    let probe = ManagedListUIAReaderProbe()
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let containerID: UInt64

    init() throws {
        let probe = probe
        host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(probe.rows, id: \.self) { probe.makeRow($0) }.listStyle(.plain)
        }
        source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 16))
        do {
            XCTAssertNotNil(host.layout())
            containerID = try XCTUnwrap(source.uiaElementSnapshots().first(where: \.supportsItemContainer)?.id)
        } catch {
            host.close()
            throw error
        }
    }

    func identifier(_ id: Int) -> String { "uia.managed.reader.\(id)" }

    func item(at index: Int) throws -> UInt64 {
        var current: UInt64?
        for _ in 0...index {
            let result = source.uiaFindItem(containerID: containerID, afterElementID: current)
            guard case .item(let id) = result else {
                XCTFail("Expected a current logical List item, got \(result)")
                return try XCTUnwrap(nil as UInt64?)
            }
            current = id
        }
        return try XCTUnwrap(current)
    }

    func reader(in root: ViewNode) throws -> ViewNode {
        try XCTUnwrap(MountedLazyListTestHost.descendants(in: root).first { $0.geometryReaderBuild != nil })
    }

    func assertSettledWithoutQuery(file: StaticString = #filePath, line: UInt = #line) throws {
        guard case .settled(let receipt) = host.runtime.layoutSettlementStatus else {
            XCTFail("The completed UIA operation must already be settled", file: file, line: line)
            return
        }
        XCTAssertTrue(host.runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        XCTAssertTrue(host.runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
    }

    func close() {
        probe.onReader = nil
        host.close()
        probe.owners.removeAll()
        probe.bindings.removeAll()
    }
}

@MainActor
private final class ManagedListUIAReaderProbe {
    let rows = Array(0..<400)
    var factories: [Int] = []
    var readerSizes: [Int: [Size]] = [:]
    var owners: [Int: StateMountOwner] = [:]
    var bindings: [Int: Binding<Int>] = [:]
    weak var closingReaderEpoch: StateMountEpoch?
    var interventions = 0
    var onReader: (@MainActor (Int, Size) -> Void)?

    func makeRow(_ id: Int) -> ManagedListUIAReaderRow {
        factories.append(id)
        return ManagedListUIAReaderRow(id: id, probe: self)
    }

    func recordOwner(_ id: Int, binding: Binding<Int>) {
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            XCTFail("The managed row must own its installed State before reader construction")
            return
        }
        owners[id] = owner
        bindings[id] = binding
    }

    func recordReader(_ id: Int, size: Size) {
        readerSizes[id, default: []].append(size)
        onReader?(id, size)
    }
}

@MainActor
private struct ManagedListUIAReaderRow: View {
    @State private var value = 41
    let id: Int
    let probe: ManagedListUIAReaderProbe

    var body: some View {
        probe.recordOwner(id, binding: $value)
        return HStack(spacing: 0) {
            Color.clear.frame(width: 17)
            GeometryReader { geometry in
                ManagedListUIAReaderContent(id: id, value: value, size: geometry.size, probe: probe)
            }
        }
        .frame(height: 24)
    }
}

@MainActor
private struct ManagedListUIAReaderContent: View {
    let id: Int
    let value: Int
    let size: Size
    let probe: ManagedListUIAReaderProbe

    var body: some View {
        probe.recordReader(id, size: size)
        return Text("Row \(id): \(value)").accessibilityIdentifier("uia.managed.reader.\(id)")
    }
}
