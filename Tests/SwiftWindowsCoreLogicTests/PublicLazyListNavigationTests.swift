import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class PublicLazyListNavigationTests: XCTestCase {
    func testUnconstructedFarDestinationIsRealizedBeforeFocusPublication() async throws {
        for builder in [false, true] {
            let fixture = try PublicListNavigationFixture(builder: builder)
            defer { fixture.close() }
            fixture.probe.selected = 899
            let source = try fixture.row(0)
            XCTAssertNil(fixture.findRow(900))
            let callsBefore = fixture.probe.factoryCalls.count
            var focused: [Int] = []
            var deferredAtEntry: [Bool] = []
            fixture.host.runtime.onAccessibilityFocusChanged = { node in
                guard let node, let row = DeferredListRowNavigation.attached(to: node) else { return }
                focused.append(row.ordinal)
                var ancestor: ViewNode? = node
                var wasDeferred = false
                while let current = ancestor {
                    wasDeferred = wasDeferred || current.isLayoutDeferredByVirtualization
                    ancestor = current.parent
                }
                deferredAtEntry.append(wasDeferred)
            }

            source.onKeyDown?(Self.down)

            // Direct data tags are known metadata. An opaque builder tag
            // belonging to another row may need bounded deferred searching.
            if builder { fixture.settleNavigation() }

            XCTAssertEqual(fixture.probe.selected, 900)
            XCTAssertEqual(fixture.probe.writes, [900])
            XCTAssertEqual(focused, [900])
            XCTAssertEqual(deferredAtEntry, [false])
            XCTAssertTrue(fixture.host.runtime.focusedNode === fixture.findRow(900))
            XCTAssertGreaterThan(try fixture.host.scrollContainer().scrollOffset, 20_000)
            if !builder { XCTAssertLessThan(fixture.probe.factoryCalls.count - callsBefore, 128) }
            XCTAssertLessThan(try XCTUnwrap(try fixture.host.list().retainedLazyListAdapter).mountedRecordCount, 40)
        }
    }

    func testSynchronousRebuildKeepsPreparedPhysicalTargetAndRetiresOldHandler() async throws {
        let fixture = try PublicListNavigationFixture(builder: true)
        defer { fixture.close() }
        fixture.probe.selected = 899
        let source = try fixture.row(0)
        let oldHandler = try XCTUnwrap(source.onKeyDown)
        var prepared: ViewNode?
        fixture.probe.onSet = { prepared = fixture.findRow(900) }
        let buildsBefore = fixture.host.events.rootCompletions

        oldHandler(Self.down)
        fixture.settleNavigation()

        let destination = try XCTUnwrap(prepared)
        XCTAssertTrue(fixture.findRow(900) === destination)
        XCTAssertTrue(fixture.host.runtime.focusedNode === destination)
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertEqual(fixture.host.events.rootCompletions, buildsBefore + 1)
        let reads = fixture.probe.reads
        let calls = fixture.probe.factoryCalls
        oldHandler(Self.down)
        XCTAssertEqual(fixture.probe.reads, reads)
        XCTAssertEqual(fixture.probe.factoryCalls, calls)
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertTrue(fixture.host.runtime.focusedNode === destination)
    }

    func testNewerFocusFromSetterCancelsPreparedLazyReveal() async throws {
        let fixture = try PublicListNavigationFixture(builder: false)
        defer { fixture.close() }
        fixture.probe.selected = 899
        let source = try fixture.row(0)
        let alternate = try XCTUnwrap(fixture.host.find("public.navigation.alternate"))
        XCTAssertTrue(alternate.isFocusable)
        fixture.host.runtime.requestFocus(source)
        let scroll = try fixture.host.scrollContainer()
        let before = scroll.scrollOffset
        fixture.probe.onSet = { [weak runtime = fixture.host.runtime, weak alternate] in
            runtime?.requestFocus(alternate)
        }

        source.onKeyDown?(Self.down)

        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertTrue(fixture.host.runtime.focusedNode === alternate)
        XCTAssertEqual(scroll.scrollOffset, before)
        XCTAssertFalse(fixture.findRow(900)?.isFocused == true)
    }

    func testOpaqueSelectionTagUsesTheSelectedLogicalRowInsteadOfFocusedSourceOrdinal() async throws {
        let probe = PublicListNavigationProbe()
        probe.tagScale = 10
        let fixture = try PublicListNavigationFixture(builder: true, probe: probe)
        defer { fixture.close() }
        probe.selected = 8990
        let source = try fixture.row(0)
        let callsBefore = probe.factoryCalls.count

        source.onKeyDown?(Self.down)

        XCTAssertTrue(probe.writes.isEmpty, "A partial tag search must not select a provisional neighbor")
        XCTAssertLessThanOrEqual(probe.factoryCalls.count - callsBefore, 128)
        fixture.settleNavigation(checkFactoryBudget: true)
        XCTAssertEqual(probe.writes, [9000])
        XCTAssertEqual(probe.selected, 9000)
        XCTAssertEqual(
            fixture.host.runtime.focusedNode.flatMap { DeferredListRowNavigation.attached(to: $0) }?.ordinal, 900)
        XCTAssertLessThan(try XCTUnwrap(try fixture.host.list().retainedLazyListAdapter).mountedRecordCount, 40)
    }

    func testExhaustedRebuildBudgetDoesNotRepeatBindingOrLosePreparedFocus() async throws {
        let fixture = try PublicListNavigationFixture(builder: false)
        defer { fixture.close() }
        fixture.probe.selected = 899
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 8))
        let source = try fixture.row(0)
        let buildsBefore = fixture.host.events.rootCompletions

        source.onKeyDown?(Self.down)

        for _ in 0..<128 {
            let before = fixture.probe.factoryCalls.count
            fixture.host.render()
            XCTAssertLessThanOrEqual(fixture.probe.factoryCalls.count - before, 1)
            if fixture.host.runtime.focusedNode === fixture.findRow(900), !fixture.host.runtime.hasPendingLayout {
                break
            }
        }
        XCTAssertEqual(fixture.probe.selected, 900)
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertEqual(fixture.host.events.rootCompletions, buildsBefore + 1)
        let destination = try XCTUnwrap(fixture.findRow(900))
        XCTAssertTrue(fixture.host.runtime.focusedNode === destination)
        XCTAssertFalse(destination.isLayoutDeferredByVirtualization)
        XCTAssertFalse(fixture.host.runtime.hasPendingLayout)
    }

    func testReentrantSelectionGetterCannotBuildOrWriteAfterClose() async throws {
        let fixture = try PublicListNavigationFixture(builder: true)
        defer { fixture.close() }
        fixture.probe.selected = 899
        let handler = try XCTUnwrap(try fixture.row(0).onKeyDown)
        let calls = fixture.probe.factoryCalls
        fixture.probe.onGet = { fixture.host.close() }

        handler(Self.down)

        XCTAssertEqual(fixture.probe.factoryCalls, calls)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertNil(fixture.host.runtime.focusedNode)
        let reads = fixture.probe.reads
        handler(Self.down)
        XCTAssertEqual(fixture.probe.reads, reads)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
    }

    func testSameSelectionActivationReleasesAnUnfinishedLogicalDemandWithoutRebuilding() async throws {
        let fixture = try PublicListNavigationFixture(builder: false)
        defer { fixture.close() }
        fixture.probe.selected = 899
        let source = try fixture.row(0)
        let completions = fixture.host.events.rootCompletions
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 0, roundLimit: 8))
        source.onKeyDown?(Self.down)
        XCTAssertTrue(fixture.probe.writes.isEmpty)

        // The externally supplied value changes without a root invalidation.
        // Activating row zero now admits a newer action but no selection write.
        fixture.probe.selected = 0
        source.onActivate?()

        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertEqual(fixture.host.events.rootCompletions, completions)
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 8))
        try fixture.assertIndependentRealization(of: 700)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertEqual(fixture.host.events.rootCompletions, completions)
    }

    func testExternalFocusCancelsAnUnfinishedLogicalDemandWithoutRebuilding() async throws {
        let fixture = try PublicListNavigationFixture(builder: false)
        defer { fixture.close() }
        fixture.probe.selected = 899
        let source = try fixture.row(0)
        let alternate = try XCTUnwrap(fixture.host.find("public.navigation.alternate"))
        let completions = fixture.host.events.rootCompletions
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 0, roundLimit: 8))
        source.onKeyDown?(Self.down)
        XCTAssertTrue(fixture.probe.writes.isEmpty)

        fixture.host.runtime.requestFocus(alternate)
        fixture.host.render()

        XCTAssertTrue(fixture.host.runtime.focusedNode === alternate)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertEqual(fixture.host.events.rootCompletions, completions)
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 8))
        try fixture.assertIndependentRealization(of: 700)
        XCTAssertTrue(fixture.host.runtime.focusedNode === alternate)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
    }

    func testDirectDataSelectionUsesActualSelectableLeavesAndTheUnmatchedBoundary() async throws {
        for disabled in [false, true] {
            for direction in [-1, 1] {
                let probe = PublicListNavigationProbe(count: 12)
                probe.selected = 3
                if disabled { probe.disabledRows = [3] } else { probe.zeroRows = [3] }
                let fixture = try PublicListNavigationFixture(builder: false, probe: probe)
                defer { fixture.close() }

                try fixture.row(0).onKeyDown?(
                    KeyboardEvent(
                        keyCode: direction > 0 ? KeyboardKey.downArrow.rawValue : KeyboardKey.upArrow.rawValue))
                fixture.settleNavigation()

                let expected = direction > 0 ? 0 : 11
                XCTAssertEqual(probe.writes, [expected])
                XCTAssertEqual(probe.selected, expected)
                XCTAssertEqual(
                    fixture.host.runtime.focusedNode.flatMap { DeferredListRowNavigation.attached(to: $0) }?.ordinal,
                    expected)
            }
        }
    }

    func testDirectDataDuplicateLeafTagDoesNotManufactureASelectionChange() async throws {
        let probe = PublicListNavigationProbe(count: 12)
        probe.selected = 3
        probe.multipleRows = [3]
        let fixture = try PublicListNavigationFixture(builder: false, probe: probe)
        defer { fixture.close() }

        try fixture.row(0).onKeyDown?(Self.down)
        fixture.settleNavigation()

        XCTAssertEqual(probe.selected, 3)
        XCTAssertTrue(probe.writes.isEmpty, "The next projected leaf carries the same data selection ID")
        XCTAssertNil(fixture.host.runtime.focusedNode)

        let second = try XCTUnwrap(
            fixture.host.nodes.first {
                let metadata = DeferredListRowNavigation.attached(to: $0)
                return metadata?.ordinal == 3 && metadata?.leaf == 1
            })
        fixture.host.runtime.requestFocus(second)
        second.onKeyDown?(Self.down)
        fixture.settleNavigation()
        XCTAssertEqual(probe.selected, 3)
        XCTAssertTrue(probe.writes.isEmpty, "A focused later leaf must not replace the first matching selection anchor")
        XCTAssertTrue(fixture.host.runtime.focusedNode === second)
    }

    func testBuilderNavigationSkipsZeroAndDisabledRowsAndVisitsEachActualTaggedLeaf() async throws {
        let probe = PublicListNavigationProbe(count: 12)
        probe.zeroRows = [1]
        probe.disabledRows = [2]
        probe.multipleRows = [3]
        probe.tagScale = 10
        let fixture = try PublicListNavigationFixture(builder: true, probe: probe)
        defer { fixture.close() }
        try fixture.row(0).onKeyDown?(Self.down)
        XCTAssertEqual(probe.selected, 30)
        let first = try XCTUnwrap(fixture.host.runtime.focusedNode)
        XCTAssertEqual(DeferredListRowNavigation.attached(to: first)?.ordinal, 3)
        XCTAssertEqual(DeferredListRowNavigation.attached(to: first)?.leaf, 0)
        first.onKeyDown?(Self.down)
        XCTAssertEqual(probe.selected, 31)
        let second = try XCTUnwrap(fixture.host.runtime.focusedNode)
        XCTAssertEqual(DeferredListRowNavigation.attached(to: second)?.ordinal, 3)
        XCTAssertEqual(DeferredListRowNavigation.attached(to: second)?.leaf, 1)
        second.onKeyDown?(Self.down)
        XCTAssertEqual(probe.selected, 40)
        XCTAssertEqual(probe.writes, [30, 31, 40])
    }

    private static var down: KeyboardEvent { KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue) }
}

@MainActor
private final class PublicListNavigationFixture {
    let host: MountedLazyListTestHost
    let probe: PublicListNavigationProbe

    init(builder: Bool, probe: PublicListNavigationProbe = PublicListNavigationProbe()) throws {
        self.probe = probe
        host = MountedLazyListTestHost(size: Size(width: 260, height: 200)) {
            VStack(spacing: 0) {
                publicNavigationList(probe, builder: builder)
                Button("Alternate", action: {}).accessibilityIdentifier("public.navigation.alternate")
            }
        }
        XCTAssertNotNil(host.layout())
    }

    func findRow(_ ordinal: Int) -> ViewNode? {
        host.nodes.first { DeferredListRowNavigation.attached(to: $0)?.ordinal == ordinal }
    }

    func row(_ ordinal: Int) throws -> ViewNode { try XCTUnwrap(findRow(ordinal)) }

    func assertIndependentRealization(of ordinal: Int) throws {
        let container = try host.list()
        let source = try XCTUnwrap(DeferredListScrollSource.attached(to: container))
        let row = try XCTUnwrap(source.row(at: ordinal))
        let item = try XCTUnwrap(host.runtime.lazyListTarget(in: container, key: row.providerKey))
        defer { host.runtime.releaseLazyListTarget(item) }
        for _ in 0..<24 {
            switch host.runtime.resolveLazyListTarget(item) {
            case .ready(let nodes):
                XCTAssertTrue(nodes.contains { DeferredListRowNavigation.attached(to: $0)?.ordinal == ordinal })
                return
            case .pending:
                host.render()
            case .empty, .obsolete, .unsupported:
                return XCTFail("The cancelled request must not keep exclusive logical realization ownership")
            }
        }
        XCTFail("A different logical request must acquire the released demand")
    }

    func settleNavigation(checkFactoryBudget: Bool = false) {
        for _ in 0..<24 {
            let before = probe.factoryCalls.count
            host.render()
            if checkFactoryBudget { XCTAssertLessThanOrEqual(probe.factoryCalls.count - before, 128) }
            let focusedTag = host.runtime.focusedNode.flatMap { DeferredListRowNavigation.attached(to: $0)?.tag }
            let completedSelection = probe.writes.isEmpty || focusedTag == probe.selected.map(AnyHashable.init)
            if !host.runtime.hasPendingLayout, completedSelection { return }
        }
        XCTFail("A bounded logical keyboard request must eventually settle")
    }

    func close() {
        probe.onSet = nil
        probe.onGet = nil
        host.runtime.onAccessibilityFocusChanged = nil
        host.close()
    }
}

@MainActor
private final class PublicListNavigationProbe {
    let rows: [Int]
    var selected: Int? = 0
    var reads = 0
    var writes: [Int?] = []
    var factoryCalls: [Int] = []
    var onSet: (() -> Void)?
    var onGet: (() -> Void)?
    var zeroRows: Set<Int> = []
    var disabledRows: Set<Int> = []
    var multipleRows: Set<Int> = []
    var tagScale = 1

    init(count: Int = 1000) { rows = Array(0..<count) }

    var selection: Binding<Int?> {
        Binding(
            get: {
                self.reads += 1
                self.onGet?()
                return self.selected
            },
            set: {
                self.selected = $0
                self.writes.append($0)
                self.onSet?()
            })
    }

    func content(for row: Int) -> [AnyView] {
        factoryCalls.append(row)
        guard !zeroRows.contains(row) else { return [] }
        var result = [
            AnyView(
                Text("Row \(row)").frame(width: 220, height: 24).tag(row * tagScale)
                    .selectionDisabled(disabledRows.contains(row)))
        ]
        if multipleRows.contains(row) {
            result.append(AnyView(Text("Tail \(row)").frame(width: 220, height: 24).tag(row * tagScale + 1)))
        }
        return result
    }
}

@MainActor
@ViewBuilder
private func publicNavigationList(_ probe: PublicListNavigationProbe, builder: Bool) -> some View {
    if builder {
        List(selection: probe.selection) { ForEach(probe.rows, id: \.self) { probe.content(for: $0) } }
    } else {
        List(probe.rows, id: \.self, selection: probe.selection) { probe.content(for: $0) }
    }
}
