import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Descriptor acceptance and viewport construction happen in separate scopes.
/// These tests keep them separate and observe the actual retained row nodes.
@MainActor
final class ManagedLazyListInsertionEventTests: XCTestCase {
    func testInitialPublicListRowsDoNotBorrowTheirDeclarationAnimation() async throws {
        for builder in [false, true] {
            let probe = ManagedInsertionEventProbe(rows: [ManagedInsertionEventData(id: 0)])
            let harness = withAnimation(.linear(duration: 4)) {
                ManagedInsertionEventHarness {
                    managedInsertionEventPublicList(probe, builder: builder)
                }
            }
            defer {
                harness.host.close()
                probe.captures.removeAll()
            }
            XCTAssertTrue(probe.factoryCalls.isEmpty, "Accepting a descriptor must not build its rows")

            harness.layout()

            let row = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
            assertNoInsertion(on: row)
            XCTAssertEqual(harness.clock.reads, 0, "Initial viewport materialization needs no insertion clock")
            try harness.host.assertCommittedDescriptor()
        }
    }

    func testColdRowsAndViewportRemountsDoNotBecomeLogicalInsertions() async throws {
        let probe = ManagedInsertionEventProbe(
            rows: (0..<100).map { ManagedInsertionEventData(id: $0) })
        let harness = ManagedInsertionEventHarness { managedInsertionEventBoundedList(probe) }
        defer {
            harness.host.close()
            probe.captures.removeAll()
        }
        harness.layout()
        let original = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
        let originalOwner = try XCTUnwrap(probe.captures[0]).owner
        let attachment = original.captureLazyListAttachmentProof()
        XCTAssertNil(probe.bodyCalls[50])
        assertNoInsertion(on: original)

        // This accepts another complete logical roster while row 50 is cold.
        // It must not classify that row from the absence of mounted State.
        withAnimation(.linear(duration: 3)) { harness.host.reload() }
        harness.layout()
        XCTAssertNil(probe.bodyCalls[50])
        assertNoInsertion(on: original)

        try harness.host.scroll(to: 1_000)

        let cold = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(50)))
        XCTAssertNotNil(probe.bodyCalls[50], "The cold row must actually have been constructed")
        XCTAssertFalse(harness.host.contains(original))
        XCTAssertFalse(attachment.isCurrent)
        assertNoInsertion(on: cold)

        try harness.host.scroll(to: 0)

        let returned = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
        XCTAssertFalse(returned === original, "The row must have a new physical incarnation")
        XCTAssertTrue(try XCTUnwrap(probe.captures[0]).owner === originalOwner)
        assertNoInsertion(on: returned)
        XCTAssertEqual(harness.clock.reads, 0, "Scrolling cold rows does not start insertion tweens")
        try harness.host.assertCommittedDescriptor()
    }

    func testNestedFirstSourceDoesNotAnimateItsInitialRows() async throws {
        let probe = ManagedInsertionEventProbe()
        let harness = ManagedInsertionEventHarness { managedInsertionEventNestedList(probe) }
        defer {
            harness.host.close()
            probe.captures.removeAll()
        }
        harness.layout()
        XCTAssertTrue(probe.bodyCalls.isEmpty)

        probe.rows = [ManagedInsertionEventData(id: 0)]
        withAnimation(.linear(duration: 1.5)) { harness.host.reload() }
        XCTAssertTrue(probe.factoryCalls.isEmpty, "The nested source is still deferred")

        harness.layout()

        let outer = try XCTUnwrap(harness.host.find("managed.insertion.event.outer.0"))
        let outerFade = try XCTUnwrap(outer.animationStates[.opacity])
        XCTAssertEqual(outerFade.duration, 1.5, accuracy: 0.0001)
        let inner = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
        assertNoInsertion(on: inner)
        XCTAssertEqual(harness.host.lists.count, 2)
        try harness.host.assertCommittedDescriptor(index: 0)
        try harness.host.assertCommittedDescriptor(index: 1)
    }

    func testAcceptedEmptyListStartsOneInsertionAndUnchangedReloadDoesNotRestartIt() async throws {
        let probe = ManagedInsertionEventProbe()
        let harness = ManagedInsertionEventHarness { managedInsertionEventBoundedList(probe) }
        defer {
            harness.host.close()
            probe.captures.removeAll()
        }
        harness.layout()
        XCTAssertTrue(try harness.host.list().children.isEmpty)

        probe.rows = [ManagedInsertionEventData(id: 0)]
        withAnimation(.linear(duration: 2)) { harness.host.reload() }
        XCTAssertTrue(probe.factoryCalls.isEmpty)
        XCTAssertNil(harness.host.find(managedInsertionEventIdentifier(0)))
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)

        harness.layout()

        let row = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
        let owner = try XCTUnwrap(probe.captures[0]).owner
        let insertion = try assertOneInsertion(on: row, in: harness, duration: 2, destination: 1)
        harness.present(at: insertion.startTime + 0.5)
        XCTAssertEqual(row.opacity, 0.25, accuracy: 0.0001)
        XCTAssertTrue(row.hasAppeared)

        // A different newly accepted transaction cannot restart a claimed row.
        withAnimation(.linear(duration: 7)) { harness.host.reload() }
        harness.layout()
        harness.present(at: insertion.startTime + 0.5)

        XCTAssertTrue(harness.host.find(managedInsertionEventIdentifier(0)) === row)
        XCTAssertTrue(try XCTUnwrap(probe.captures[0]).owner === owner)
        let continued = try XCTUnwrap(row.animationStates[.opacity])
        XCTAssertEqual(continued.startTime, insertion.startTime)
        XCTAssertEqual(continued.duration, insertion.duration)
        XCTAssertEqual(continued.endValue, insertion.endValue)
        XCTAssertEqual(row.opacity, 0.25, accuracy: 0.0001)

        harness.present(at: insertion.startTime + insertion.duration + 0.01)
        XCTAssertNil(row.animationStates[.opacity])
        XCTAssertEqual(row.opacity, 1, accuracy: 0.0001)
        harness.host.reload()
        harness.layout()
        assertNoInsertion(on: row)
    }

    func testAcceptedZeroRootRowCanInsertItsFirstPhysicalDescendant() async throws {
        let probe = ManagedInsertionEventProbe(rows: [ManagedInsertionEventData(id: 0)])
        probe.showsRows = false
        let harness = ManagedInsertionEventHarness { managedInsertionEventBoundedList(probe) }
        defer {
            harness.host.close()
            probe.captures.removeAll()
        }
        harness.layout()
        let list = try harness.host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertEqual(adapter.mountedRecordCount, 1, "An accepted empty row still has a native row table")
        XCTAssertTrue(list.children.isEmpty)
        XCTAssertTrue(probe.bodyCalls.isEmpty)

        probe.showsRows = true
        withAnimation(.linear(duration: 0.8)) { harness.host.reload() }
        XCTAssertTrue(probe.bodyCalls.isEmpty)

        harness.layout()

        let row = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
        _ = try assertOneInsertion(on: row, in: harness, duration: 0.8, destination: 1)
        try harness.host.assertCommittedDescriptor()
    }

    func testLatestAcceptedExplicitNilSuppressesAnUnclaimedIntroduction() async throws {
        try assertLatestAcceptedTransaction(Transaction(animation: nil), expectedDuration: nil)
    }

    func testLatestAcceptedDisabledTransactionSuppressesAnUnclaimedIntroduction() async throws {
        var transaction = Transaction(animation: .linear(duration: 0.75))
        transaction.disablesAnimations = true
        try assertLatestAcceptedTransaction(transaction, expectedDuration: nil)
    }

    func testLatestAcceptedAbsentTransactionUsesTheDefaultForAnUnclaimedIntroduction() async throws {
        try assertLatestAcceptedTransaction(nil, expectedDuration: 0.35)
    }

    func testLatestAcceptedAnimationControlsAnUnclaimedIntroduction() async throws {
        try assertLatestAcceptedTransaction(
            Transaction(animation: .linear(duration: 0.75)), expectedDuration: 0.75)
    }

    func testDeleteAndReinsertBeforeLayoutReusesNodeButNotStateOrPresentedDestination() async throws {
        let probe = ManagedInsertionEventProbe()
        let harness = ManagedInsertionEventHarness { managedInsertionEventBoundedList(probe) }
        defer {
            harness.host.close()
            probe.captures.removeAll()
        }
        harness.layout()
        probe.rows = [ManagedInsertionEventData(id: 0, seed: 100, opacity: 0.8)]
        withAnimation(.linear(duration: 2)) { harness.host.reload() }
        harness.layout()
        let original = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
        let originalCapture = try XCTUnwrap(probe.captures[0])
        let first = try assertOneInsertion(on: original, in: harness, duration: 2, destination: 0.8)
        harness.present(at: first.startTime + 0.5)
        XCTAssertEqual(original.opacity, 0.2, accuracy: 0.0001)
        XCTAssertTrue(original.hasAppeared)
        let attachment = original.captureLazyListAttachmentProof()
        let factoryCalls = probe.factoryCalls[0]

        // Both logical changes are accepted before a viewport can retire the
        // old node. The new row's State and transition still belong to G3.
        probe.rows = []
        withAnimation(.linear(duration: 4)) { harness.host.reload() }
        XCTAssertFalse(originalCapture.owner.isLive)
        XCTAssertTrue(harness.host.find(managedInsertionEventIdentifier(0)) === original)
        XCTAssertTrue(attachment.isCurrent)
        probe.rows = [ManagedInsertionEventData(id: 0, seed: 900, opacity: 0.9)]
        withAnimation(.linear(duration: 1.25)) { harness.host.reload() }
        XCTAssertEqual(probe.factoryCalls[0], factoryCalls, "Neither descriptor rebuild may execute a row factory")

        harness.layout()

        let replacement = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
        let replacementCapture = try XCTUnwrap(probe.captures[0])
        XCTAssertTrue(replacement === original)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertTrue(replacement.hasAppeared, "Logical insertion does not reset physical appearance")
        XCTAssertFalse(replacementCapture.owner === originalCapture.owner)
        XCTAssertNotEqual(replacementCapture.owner.generation, originalCapture.owner.generation)
        XCTAssertTrue(replacementCapture.owner.isLive)
        XCTAssertEqual(replacementCapture.value.wrappedValue, 900)
        let second = try assertOneInsertion(on: replacement, in: harness, duration: 1.25, destination: 0.9)
        XCTAssertEqual(second.startTime, first.startTime + 0.5, accuracy: 0.0001)
        XCTAssertNotEqual(second.startTime, first.startTime)

        let invalidations = harness.host.events.stateInvalidations
        originalCapture.value.wrappedValue = -1
        XCTAssertEqual(originalCapture.value.wrappedValue, 100)
        XCTAssertEqual(replacementCapture.value.wrappedValue, 900)
        XCTAssertEqual(harness.host.events.stateInvalidations, invalidations)
        harness.present(at: second.startTime + second.duration + 0.01)
        XCTAssertEqual(replacement.opacity, 0.9, accuracy: 0.0001)
        XCTAssertNil(replacement.animationStates[.opacity])
    }

    func testReintroducedRowEstablishesAFreshValueAnimationBaseline() async throws {
        let probe = ManagedInsertionEventProbe(
            rows: [ManagedInsertionEventData(id: 0, trigger: 0)])
        probe.valueAnimation = .linear(duration: 9)
        let harness = ManagedInsertionEventHarness { managedInsertionEventBoundedList(probe) }
        defer {
            harness.host.close()
            probe.captures.removeAll()
        }
        harness.layout()
        harness.present(at: 10)
        let original = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
        assertNoInsertion(on: original)

        probe.rows = []
        harness.host.reload()
        probe.rows = [ManagedInsertionEventData(id: 0, seed: 900, trigger: 1)]
        withAnimation(.linear(duration: 0.6)) { harness.host.reload() }

        harness.layout()

        let replacement = try XCTUnwrap(harness.host.find(managedInsertionEventIdentifier(0)))
        XCTAssertTrue(replacement === original)
        let insertion = try assertOneInsertion(on: replacement, in: harness, duration: 0.6, destination: 1)
        XCTAssertEqual(insertion.easing, .linear)
        harness.present(at: insertion.startTime + insertion.duration + 0.01)

        // Once that logical row exists, a real trigger change must still use
        // the value modifier. The repair cannot simply skip all modifiers.
        probe.rows = [ManagedInsertionEventData(id: 0, seed: 900, opacity: 0.5, trigger: 2)]
        harness.host.reload()
        harness.layout()

        XCTAssertTrue(harness.host.find(managedInsertionEventIdentifier(0)) === replacement)
        let change = try XCTUnwrap(replacement.animationStates[.opacity])
        XCTAssertEqual(change.duration, 9, accuracy: 0.0001)
        XCTAssertEqual(change.startValue, 1, accuracy: 0.0001)
        XCTAssertEqual(change.endValue, 0.5, accuracy: 0.0001)
    }

    private func assertLatestAcceptedTransaction(
        _ transaction: Transaction?, expectedDuration: Double?,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let probe = ManagedInsertionEventProbe()
        let harness = ManagedInsertionEventHarness { managedInsertionEventBoundedList(probe) }
        defer {
            harness.host.close()
            probe.captures.removeAll()
        }
        harness.layout()

        probe.rows = [ManagedInsertionEventData(id: 0, seed: 100)]
        withAnimation(.linear(duration: 4)) { harness.host.reload() }
        XCTAssertTrue(probe.factoryCalls.isEmpty, file: file, line: line)
        XCTAssertNil(harness.host.find(managedInsertionEventIdentifier(0)), file: file, line: line)

        probe.rows = [ManagedInsertionEventData(id: 0, seed: 900, opacity: 0.75)]
        if let transaction {
            withTransaction(transaction) { harness.host.reload() }
        } else {
            harness.host.reload()
        }
        XCTAssertTrue(probe.factoryCalls.isEmpty, file: file, line: line)
        XCTAssertNil(currentTransaction, file: file, line: line)
        XCTAssertNil(currentAnimationTransaction, file: file, line: line)

        harness.layout(file: file, line: line)

        let row = try XCTUnwrap(
            harness.host.find(managedInsertionEventIdentifier(0)), file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(probe.captures[0], file: file, line: line).value.wrappedValue, 900)
        if let expectedDuration {
            let insertion = try assertOneInsertion(
                on: row, in: harness, duration: expectedDuration, destination: 0.75, file: file, line: line)
            XCTAssertEqual(insertion.easing, transaction?.animation?.easing ?? .easeInOut, file: file, line: line)
        } else {
            assertNoInsertion(on: row, opacity: 0.75, file: file, line: line)
            XCTAssertEqual(harness.clock.reads, 0, file: file, line: line)
        }
        try harness.host.assertCommittedDescriptor(file: file, line: line)
    }

    private func assertNoInsertion(
        on node: ViewNode, opacity: Double = 1, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            node.animationStates.isEmpty, "The actual row must not have an insertion tween", file: file, line: line)
        XCTAssertEqual(node.opacity, opacity, accuracy: 0.0001, file: file, line: line)
    }

    @discardableResult
    private func assertOneInsertion(
        on node: ViewNode, in harness: ManagedInsertionEventHarness, duration: Double, destination: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> AnimationState {
        let insertion = try XCTUnwrap(node.animationStates[.opacity], file: file, line: line)
        let recipients = harness.host.nodes.filter { $0.animationStates[.opacity] != nil }
        XCTAssertEqual(
            recipients.count, 1, "A single row insertion must not start duplicate ancestor fades", file: file,
            line: line)
        XCTAssertTrue(recipients.first === node, file: file, line: line)
        XCTAssertEqual(insertion.startTime, harness.clock.now, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(insertion.duration, duration, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(insertion.startValue, 0, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(insertion.endValue, destination, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(node.opacity, 0, accuracy: 0.0001, file: file, line: line)
        return insertion
    }
}

private struct ManagedInsertionEventData: Identifiable {
    let id: Int
    var seed = 100
    var opacity = 1.0
    var trigger = 0
}

@MainActor
private struct ManagedInsertionEventCapture {
    let owner: StateMountOwner
    let value: Binding<Int>
}

@MainActor
private final class ManagedInsertionEventProbe {
    var rows: [ManagedInsertionEventData]
    var showsRows = true
    var valueAnimation: Animation?
    var factoryCalls: [Int: Int] = [:]
    var bodyCalls: [Int: Int] = [:]
    var captures: [Int: ManagedInsertionEventCapture] = [:]

    init(rows: [ManagedInsertionEventData] = []) { self.rows = rows }

    func makeRow(_ data: ManagedInsertionEventData) -> ManagedInsertionEventRow {
        factoryCalls[data.id, default: 0] += 1
        return ManagedInsertionEventRow(data, probe: self)
    }

    func record(row: Int, value: Binding<Int>) {
        bodyCalls[row, default: 0] += 1
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            XCTFail("The managed row must install its State owner")
            return
        }
        captures[row] = ManagedInsertionEventCapture(owner: owner, value: value)
    }
}

@MainActor
private struct ManagedInsertionEventRow: View {
    @State private var value: Int
    let data: ManagedInsertionEventData
    let probe: ManagedInsertionEventProbe

    init(_ data: ManagedInsertionEventData, probe: ManagedInsertionEventProbe) {
        self.data = data
        self.probe = probe
        _value = State(initialValue: data.seed)
    }

    var body: some View {
        probe.record(row: data.id, value: $value)
        let content = Color.blue
            .frame(width: 120, height: 20)
            .opacity(data.opacity)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .accessibilityIdentifier(managedInsertionEventIdentifier(data.id))
        if let animation = probe.valueAnimation {
            return AnyView(content.animation(animation, value: data.trigger))
        }
        return AnyView(content)
    }
}

@MainActor
@ViewBuilder
private func managedInsertionEventPublicList(_ probe: ManagedInsertionEventProbe, builder: Bool) -> some View {
    if builder {
        List { ForEach(probe.rows) { probe.makeRow($0) } }
            .listStyle(.plain)
    } else {
        List(probe.rows) { probe.makeRow($0) }
            .listStyle(.plain)
    }
}

@MainActor
private func managedInsertionEventBoundedList(_ probe: ManagedInsertionEventProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.id, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { data in
        if probe.showsRows { probe.makeRow(data) }
    }
}

@MainActor
private func managedInsertionEventNestedList(_ probe: ManagedInsertionEventProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.id, estimatedExtent: 40, prefetchExtent: 0,
        maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1
    ) { data in
        ManagedLazyListContent(
            [data], id: \.id, estimatedExtent: 20, prefetchExtent: 0,
            maximumMountedRecords: 4, maximumMountedLeaves: 8, maximumProtectedRecords: 1
        ) { probe.makeRow($0) }
        .frame(width: 120, height: 40)
        .transition(.asymmetric(insertion: .opacity, removal: .identity))
        .accessibilityIdentifier("managed.insertion.event.outer.\(data.id)")
    }
}

private func managedInsertionEventIdentifier(_ row: Int) -> String { "managed.insertion.event.\(row)" }

@MainActor
private final class ManagedInsertionEventClock {
    var now = 10.0
    private(set) var reads = 0

    func sample() -> Double {
        reads += 1
        return now
    }
}

@MainActor
private final class ManagedInsertionEventHarness {
    let host: MountedLazyListTestHost
    let clock = ManagedInsertionEventClock()

    init<Content: View>(content: @escaping @MainActor () -> Content) {
        host = MountedLazyListTestHost(size: Size(width: 160, height: 40), content: content)
        let clock = clock
        host.runtime.clock = { clock.sample() }
    }

    func layout(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(host.layout(), file: file, line: line)
    }

    func present(at timestamp: Double, file: StaticString = #filePath, line: UInt = #line) {
        clock.now = timestamp
        _ = host.runtime.tickAnimations(at: timestamp)
        let scene = host.runtime.renderScene(at: timestamp)
        XCTAssertTrue(scene.validate().isEmpty, file: file, line: line)
    }
}
