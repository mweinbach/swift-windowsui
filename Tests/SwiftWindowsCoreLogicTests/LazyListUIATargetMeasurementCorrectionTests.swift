import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Real public requests exercise the original target query's owed correction.
/// No test supplies a phase, target certificate, new query or replacement budget.
@MainActor
final class LazyListUIATargetMeasurementCorrectionTests: XCTestCase {
    func testPendingReplacementUsesItsThirdRoundForCorrectionAndProviderCleanup() async throws {
        let fixture = try TargetMeasurementFixture()
        defer { fixture.close() }
        fixture.probe.onCorrection = { _ in }

        XCTAssertTrue(fixture.realize())

        XCTAssertEqual(fixture.probe.corrections, 1)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: fixture.target), .ordinary)
        XCTAssertEqual(fixture.source.logicalItemIdentityCount, fixture.identityCount)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .complete)
        let trace = fixture.runtime.lazyListUIAPhasesForTesting
        XCTAssertEqual(trace.filter { $0.kind == .roundDebit }.map(\.consumedRounds), [1, 2, 3, 4])
        let third = trace.filter { $0.consumedRounds == 3 }
        XCTAssertEqual(third.filter { $0.kind == .measurementPhase }.count, 1)
        XCTAssertEqual(third.filter { $0.kind == .readerPhase }.count, 1)
        XCTAssertEqual(third.filter { $0.kind == .providerPhase }.count, 1)
        XCTAssertEqual(third.filter { $0.kind == .layoutPass }.count, 2)
        let measurement = try XCTUnwrap(third.firstIndex { $0.kind == .measurementPhase })
        let correction = try XCTUnwrap(third.firstIndex { $0.kind == .layoutPass })
        let reader = try XCTUnwrap(third.firstIndex { $0.kind == .readerPhase })
        let provider = try XCTUnwrap(third.firstIndex { $0.kind == .providerPhase })
        let postProvider = try XCTUnwrap(third.lastIndex { $0.kind == .layoutPass })
        XCTAssertLessThan(measurement, correction)
        XCTAssertLessThan(correction, reader)
        XCTAssertLessThan(reader, provider)
        XCTAssertLessThan(provider, postProvider)
        XCTAssertEqual(trace.filter { $0.kind == .ownedScroll }.map(\.consumedRounds), [3])
        XCTAssertTrue(trace.contains { $0.kind == .measurementPhase && $0.consumedRounds == 4 })
        XCTAssertTrue(fixture.probe.factoriesAfterScroll.isEmpty)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
        guard case .settled(let receipt) = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("The same public request must finish its own measured settlement")
        }
        XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertTrue(fixture.runtime.hasCurrentAccessibilityPrepaint)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.scroll.resolvedScrollOffset)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
    }

    func testSameValueScrollDuringTargetCorrectionCannotEnterTheRemainingProvider() async throws {
        let fixture = try TargetMeasurementFixture()
        defer { fixture.close() }
        fixture.probe.onCorrection = { fixture in
            fixture.scroll.scrollOffset = fixture.scroll.scrollOffset
        }

        assertRejected(fixture)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
    }

    func testRestoredAttachmentDuringTargetCorrectionCannotEnterTheRemainingProvider() async throws {
        let fixture = try TargetMeasurementFixture()
        defer { fixture.close() }
        let parent = try XCTUnwrap(fixture.list.parent)
        fixture.probe.onCorrection = { fixture in
            parent.removeChild(fixture.list)
            parent.addChild(fixture.list)
        }

        assertRejected(fixture)
        XCTAssertTrue(fixture.list.parent === parent)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
    }

    func testRestoredReaderBodyDuringTargetCorrectionCannotEnterTheRemainingProvider() async throws {
        let fixture = try TargetMeasurementFixture()
        defer { fixture.close() }
        XCTAssertNil(fixture.list.geometryReaderBuild)
        fixture.probe.onCorrection = { fixture in
            fixture.list.geometryReaderBuild = { _, _ in
                XCTFail("The revoked reader body must never run")
                return []
            }
            fixture.list.geometryReaderBuild = nil
        }

        assertRejected(fixture)
        XCTAssertNil(fixture.list.geometryReaderBuild)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
    }

    private func assertRejected(
        _ fixture: TargetMeasurementFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(fixture.realize(), file: file, line: line)
        XCTAssertEqual(fixture.probe.corrections, 1, file: file, line: line)
        XCTAssertEqual(fixture.probe.factories.count, fixture.probe.factoriesAtCorrection, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 3, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128, file: file, line: line)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild, file: file, line: line)
        XCTAssertFalse(
            fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll }, file: file, line: line)
        XCTAssertTrue(fixture.probe.factoriesAfterScroll.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.probe.activations.isEmpty, file: file, line: line)
    }
}

@MainActor
private final class TargetMeasurementFixture {
    let probe: TargetMeasurementProbe
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let target: UInt64
    let identityCount: Int
    let list: ViewNode
    let scroll: ViewNode
    var runtime: RetainedViewRuntime { host.runtime }

    init() throws {
        let probe = TargetMeasurementProbe()
        self.probe = probe
        host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(Array(0..<1000), id: \.self) { probe.makeRows($0) }.listStyle(.plain)
        }
        probe.runtime = host.runtime
        source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        do {
            XCTAssertNotNil(host.layout())
            let container = try XCTUnwrap(source.uiaElementSnapshots().first(where: \.supportsItemContainer)?.id)
            var element: UInt64?
            for _ in 0...300 {
                guard case .item(let id) = source.uiaFindItem(containerID: container, afterElementID: element) else {
                    throw TargetMeasurementFixtureError.missingLogicalTarget
                }
                element = id
            }
            target = try XCTUnwrap(element)
            identityCount = source.logicalItemIdentityCount
            list = try host.list()
            scroll = try host.scrollContainer()
        } catch {
            host.close()
            throw error
        }
        host.reload()
        host.runtime.recordsLazyListUIAPhasesForTesting = true
        host.runtime.root.onLayout = { [weak self] _ in
            guard let self, self.probe.corrections == 0, self.probe.factories.contains(300) else { return }
            let trace = self.runtime.lazyListUIAPhasesForTesting
            guard let last = trace.last, last.kind == .layoutPass, last.consumedRounds == 3,
                let measurement = trace.lastIndex(where: { $0.kind == .measurementPhase }),
                trace[measurement].consumedRounds == 3,
                !trace[(measurement + 1)...].contains(where: { $0.kind == .readerPhase || $0.kind == .providerPhase })
            else { return }
            self.probe.corrections += 1
            self.probe.factoriesAtCorrection = self.probe.factories.count
            self.probe.onCorrection?(self)
        }
    }

    func realize() -> Bool { source.uiaRealizeVirtualizedItem(elementID: target) }

    func close() {
        runtime.root.onLayout = nil
        probe.onCorrection = nil
        host.close()
    }
}

private enum TargetMeasurementFixtureError: Error { case missingLogicalTarget }

@MainActor
private final class TargetMeasurementProbe {
    weak var runtime: RetainedViewRuntime?
    var factories: [Int] = []
    var factoriesAfterScroll: [Int] = []
    var activations: [Int] = []
    var corrections = 0
    var factoriesAtCorrection = 0
    var onCorrection: (@MainActor (TargetMeasurementFixture) -> Void)?

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        if runtime?.lazyListUIAPhasesForTesting.contains(where: { $0.kind == .ownedScroll }) == true {
            factoriesAfterScroll.append(id)
        }
        return [AnyView(Button("Row \(id)") { [weak self] in self?.activations.append(id) }.frame(height: 24))]
    }
}
