import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These are ordinary frames of the original action, not replacement queries.
/// The original 1/1, 64-frame regression remains a separate unchanged gate.
@MainActor
final class LazyListKeyboardOrdinaryMeasurementTests: XCTestCase {
    func testOrdinaryCorrectionUsesTheSamePaidRoundWhileSuccessorRowsRemainStale() async throws {
        let fixture = try OrdinaryKeyboardMeasurementFixture()
        defer { fixture.close() }
        let original = try fixture.start()
        var correctedPasses: [UInt64] = []
        var correctedWhileRowsWereStale = false
        var providerUsedCorrectedPass = false
        fixture.runtime.root.onLayout = { [weak fixture] _ in
            guard let fixture, fixture.isCorrectingOrdinaryMeasurement else { return }
            XCTAssertTrue(fixture.adapter.keyboardPreparation === original)
            XCTAssertEqual(fixture.probe.writes, [60])
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.focusedOrdinals.contains(60))
            correctedPasses.append(fixture.runtime.lazyListUIAPhasesForTesting.last!.layoutPassID)
            correctedWhileRowsWereStale =
                correctedWhileRowsWereStale || fixture.adapter.captureUIAActualRecordsProof() == nil
        }
        for _ in 0..<64 where !fixture.hasFocusedDestination {
            let first = correctedPasses.count
            let calls = fixture.probe.factories.count
            fixture.renderFrame()
            fixture.assertSingleRound()
            XCTAssertLessThanOrEqual(fixture.probe.factories.count - calls, 1)
            XCTAssertLessThanOrEqual(correctedPasses.count - first, 1)
            if let pending = fixture.adapter.keyboardPreparation { XCTAssertTrue(pending === original) }
            if let pass = correctedPasses.dropFirst(first).first {
                let phases = fixture.runtime.lazyListUIAPhasesForTesting
                let reader = phases.firstIndex(where: { $0.kind == .readerPhase && $0.layoutPassID == pass })
                let provider = phases.firstIndex(where: { $0.kind == .providerPhase && $0.layoutPassID == pass })
                XCTAssertNotNil(reader)
                XCTAssertNotNil(provider)
                if let reader, let provider {
                    XCTAssertLessThan(reader, provider)
                    XCTAssertEqual(phases[reader].consumedRounds, 1)
                    XCTAssertEqual(phases[provider].consumedRounds, 1)
                    XCTAssertEqual(phases[provider].remainingRounds, 0)
                    if fixture.probe.factories.count == calls + 1 { providerUsedCorrectedPass = true }
                }
            }
        }
        XCTAssertFalse(correctedPasses.isEmpty)
        XCTAssertTrue(correctedWhileRowsWereStale)
        XCTAssertTrue(providerUsedCorrectedPass)
        try fixture.assertCompleted()
    }

    func testFocusRevocationAndInputABABlockTheRemainingOrdinaryPhases() async throws {
        for changeFocus in [true, false] {
            let fixture = try OrdinaryKeyboardMeasurementFixture()
            defer { fixture.close() }
            let original = try fixture.start()
            var changes = 0
            var callsAtChange = 0
            var phaseCountAtChange = 0
            var readerCalls = 0
            fixture.runtime.root.onLayout = { [weak fixture] _ in
                guard let fixture, changes == 0, fixture.isCorrectingOrdinaryMeasurement else { return }
                changes += 1
                callsAtChange = fixture.probe.factories.count
                phaseCountAtChange = fixture.runtime.lazyListUIAPhasesForTesting.count
                XCTAssertTrue(fixture.adapter.keyboardPreparation === original)
                XCTAssertNotNil(fixture.findRow(60))
                if changeFocus {
                    fixture.runtime.requestFocus(fixture.alternate)
                } else {
                    XCTAssertNil(fixture.runtime.root.geometryReaderBuild)
                    fixture.runtime.root.geometryReaderBuild = { _, _ in
                        readerCalls += 1
                        return []
                    }
                    fixture.runtime.root.geometryReaderBuild = nil
                }
            }
            for _ in 0..<64 where changes == 0 {
                fixture.renderFrame()
                fixture.assertSingleRound()
            }
            XCTAssertEqual(changes, 1)
            XCTAssertEqual(readerCalls, 0)
            XCTAssertEqual(fixture.probe.factories.count, callsAtChange)
            fixture.assertNoRemainingPhases(after: phaseCountAtChange)
            XCTAssertEqual(fixture.probe.writes, [60])
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.focusedOrdinals.contains(60))
            XCTAssertFalse(fixture.hasFocusedDestination)
            XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
            if changeFocus { XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate) }
        }
    }

    func testQueuedCallbackInvalidationStopsOnlyTheCorrectionAndRunsInTheOrdinaryEpilogue() async throws {
        for replacesSource in [false, true] {
            let fixture = try OrdinaryKeyboardMeasurementFixture()
            defer { fixture.close() }
            let original = try fixture.start()
            var scheduled = 0
            var delivered = 0
            var callsAtSchedule = 0
            var phaseCountAtSchedule = 0
            fixture.runtime.root.onLayout = { [weak fixture] _ in
                guard let fixture, scheduled == 0, fixture.isCorrectingOrdinaryMeasurement else { return }
                scheduled += 1
                callsAtSchedule = fixture.probe.factories.count
                phaseCountAtSchedule = fixture.runtime.lazyListUIAPhasesForTesting.count
                fixture.runtime.scheduleAfterLayout(key: "keyboard.ordinary.measurement.callback") { [weak fixture] in
                    guard let fixture else { return }
                    delivered += 1
                    XCTAssertEqual(fixture.probe.factories.count, callsAtSchedule)
                    XCTAssertEqual(fixture.probe.writes, [60])
                    XCTAssertEqual(fixture.scroll.scrollOffset, 0)
                    XCTAssertFalse(fixture.focusedOrdinals.contains(60))
                    XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
                    if replacesSource { fixture.host.reload() }
                }
                // Enqueueing is not delivery and cannot publish a completed action.
                XCTAssertEqual(delivered, 0)
            }
            var frames = 0
            while frames < 64 && delivered == 0 {
                frames += 1
                fixture.renderFrame()
                fixture.assertSingleRound()
            }
            XCTAssertEqual(scheduled, 1)
            XCTAssertEqual(delivered, 1)
            XCTAssertEqual(fixture.probe.factories.count, callsAtSchedule)
            fixture.assertNoRemainingPhases(after: phaseCountAtSchedule)
            XCTAssertEqual(fixture.probe.writes, [60])
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.hasFocusedDestination)
            if replacesSource {
                // This reload is a new declaration, not successor permission for
                // the old action. Its accepted binding write is not rolled back.
                XCTAssertFalse(original.isCurrent)
                XCTAssertFalse(fixture.focusedOrdinals.contains(60))
            } else {
                XCTAssertTrue(original.isCurrent)
                XCTAssertTrue(fixture.adapter.keyboardPreparation === original)
                while frames < 64 && !fixture.hasFocusedDestination {
                    frames += 1
                    let calls = fixture.probe.factories.count
                    fixture.renderFrame()
                    fixture.assertSingleRound()
                    XCTAssertLessThanOrEqual(fixture.probe.factories.count - calls, 1)
                    if let pending = fixture.adapter.keyboardPreparation { XCTAssertTrue(pending === original) }
                }
                XCTAssertEqual(delivered, 1)
                try fixture.assertCompleted()
            }
        }
    }
}

@MainActor
private final class OrdinaryKeyboardMeasurementFixture {
    let probe: OrdinaryKeyboardMeasurementProbe
    let host: MountedLazyListTestHost
    let content: ViewNode
    let scroll: ViewNode
    let alternate: ViewNode
    private(set) var isInOrdinaryFrame = false
    private(set) var focusedOrdinals: [Int] = []
    var runtime: RetainedViewRuntime { host.runtime }
    var adapter: RetainedLazyListRuntimeAdapter { content.retainedLazyListAdapter! }
    var hasFocusedDestination: Bool {
        guard let target = findRow(60) else { return false }
        return runtime.focusedNode === target
    }
    var isCorrectingOrdinaryMeasurement: Bool {
        isInOrdinaryFrame && probe.writes == [60]
            && runtime.lazyListUIAPhasesForTesting.suffix(2).map(\.kind) == [.measurementPhase, .layoutPass]
    }

    init() throws {
        let probe = OrdinaryKeyboardMeasurementProbe()
        self.probe = probe
        let binding = Binding<Int?>(
            get: { probe.selected },
            set: {
                probe.selected = $0
                probe.writes.append($0)
            })
        host = MountedLazyListTestHost(size: Size(width: 260, height: 230)) {
            VStack(spacing: 0) {
                List(Array(0..<80), id: \.self, selection: binding) { probe.row($0) }
                    .frame(width: 260, height: 200)
                Button("Alternate") {}.accessibilityIdentifier("keyboard.ordinary.alternate")
                    .frame(width: 260, height: 30)
            }
        }
        for _ in 0..<16 {
            host.render()
            if !host.runtime.isDirty { break }
        }
        XCTAssertFalse(host.runtime.isDirty)
        content = try host.list()
        scroll = try host.scrollContainer()
        alternate = try XCTUnwrap(host.find("keyboard.ordinary.alternate"))
        XCTAssertEqual(scroll.scrollOffset, 0)
        XCTAssertFalse(try XCTUnwrap(content.retainedLazyListAdapter).hasUnresolvedWork)
        guard case .settled(let receipt) = host.runtime.layoutSettlementStatus else {
            host.close()
            throw OrdinaryKeyboardMeasurementError.unsettled
        }
        XCTAssertTrue(host.runtime.isLayoutSettlementReceiptCurrent(receipt))
        host.runtime.onAccessibilityFocusChanged = { [weak self] node in
            guard let self, let node, let row = DeferredListRowNavigation.attached(to: node) else { return }
            self.focusedOrdinals.append(row.ordinal)
        }
    }

    func findRow(_ ordinal: Int) -> ViewNode? {
        content.children.first {
            !$0.isHidden && !$0.isSeparatorRule && $0.isFocusEnabled && $0.listNavigationOwner != nil
                && DeferredListRowNavigation.attached(to: $0)?.ordinal == ordinal
        }
    }

    func start() throws -> RetainedLazyListKeyboardPreparation {
        probe.selected = 59
        XCTAssertNil(findRow(59))
        XCTAssertNil(findRow(60))
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        let handler = try XCTUnwrap(try XCTUnwrap(findRow(0)).onKeyDown)
        handler(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
        XCTAssertTrue(probe.writes.isEmpty)
        XCTAssertEqual(scroll.scrollOffset, 0)
        return try XCTUnwrap(adapter.keyboardPreparation)
    }

    func renderFrame() {
        isInOrdinaryFrame = true
        runtime.recordsLazyListUIAPhasesForTesting = true
        host.render()
        runtime.recordsLazyListUIAPhasesForTesting = false
        isInOrdinaryFrame = false
    }

    func assertSingleRound(file: StaticString = #filePath, line: UInt = #line) {
        let phases = runtime.lazyListUIAPhasesForTesting
        let kinds: [RetainedViewRuntime.LazyListUIAPhaseTrace.Kind] = [
            .roundDebit, .measurementPhase, .readerPhase, .providerPhase,
        ]
        for kind in kinds {
            XCTAssertLessThanOrEqual(phases.filter { $0.kind == kind }.count, 1, file: file, line: line)
        }
        XCTAssertTrue(
            phases.allSatisfy { $0.consumedRounds <= 1 && $0.remainingElements >= 0 && $0.remainingRounds >= 0 },
            file: file, line: line)
        XCTAssertEqual(runtime.lazyListResolutionBudgetConfiguration.elementLimit, 1, file: file, line: line)
        XCTAssertEqual(runtime.lazyListResolutionBudgetConfiguration.roundLimit, 1, file: file, line: line)
        XCTAssertLessThanOrEqual(probe.writes.count, 1, file: file, line: line)
    }

    func assertNoRemainingPhases(after count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let remainder = runtime.lazyListUIAPhasesForTesting.dropFirst(count)
        XCTAssertFalse(
            remainder.contains { $0.kind == .readerPhase || $0.kind == .providerPhase }, file: file, line: line)
    }

    func assertCompleted(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(probe.writes, [60], file: file, line: line)
        let target = try XCTUnwrap(findRow(60), file: file, line: line)
        XCTAssertTrue(runtime.focusedNode === target, file: file, line: line)
        XCTAssertTrue(target.parent === content, file: file, line: line)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization, file: file, line: line)
        XCTAssertEqual(focusedOrdinals, [60], file: file, line: line)
        XCTAssertGreaterThan(scroll.scrollOffset, 0, file: file, line: line)
        XCTAssertLessThan(
            target.resolvedFrame.minY - scroll.scrollOffset, scroll.resolvedFrame.height, file: file, line: line)
        XCTAssertGreaterThan(target.resolvedFrame.maxY - scroll.scrollOffset, 0, file: file, line: line)
        XCTAssertNil(adapter.keyboardPreparation, file: file, line: line)
        XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
    }

    func close() {
        runtime.root.onLayout = nil
        runtime.root.geometryReaderBuild = nil
        runtime.onAccessibilityFocusChanged = nil
        runtime.recordsLazyListUIAPhasesForTesting = false
        host.close()
    }
}

@MainActor
private final class OrdinaryKeyboardMeasurementProbe {
    var selected: Int? = 0
    var writes: [Int?] = []
    var factories: [Int] = []
    func row(_ ordinal: Int) -> [AnyView] {
        factories.append(ordinal)
        return [AnyView(Text("Row \(ordinal)").frame(width: 220, height: 24))]
    }
}

private enum OrdinaryKeyboardMeasurementError: Error { case unsettled }
