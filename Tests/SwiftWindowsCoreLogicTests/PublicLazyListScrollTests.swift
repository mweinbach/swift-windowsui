import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class PublicLazyListScrollProbe {
    var rows: [Int]
    var proxy: ScrollViewProxy?
    var innerProxy: ScrollViewProxy?
    var factories: [Int] = []
    var cancelAtRow: Int?
    var recordTargetTransaction = false
    var targetTransactionDurations: [Double?] = []
    var now = 0.0

    init(count: Int) { rows = Array(0..<count) }

    func built(_ row: Int, transactionTarget: Int? = nil) {
        factories.append(row)
        if recordTargetTransaction, row == transactionTarget {
            targetTransactionDurations.append(currentTransaction?.animation?.duration)
        }
        if cancelAtRow == row {
            cancelAtRow = nil
            proxy?.scrollTo("top", anchor: .top)
        }
    }
}

final class PublicLazyListScrollTests: XCTestCase {
    @MainActor
    private static func opaqueHost(
        _ probe: PublicLazyListScrollProbe, transactionTarget: Int? = nil
    ) -> MountedLazyListTestHost {
        let host = MountedLazyListTestHost(size: Size(width: 240, height: 120)) {
            ScrollViewReader { proxy in
                probe.proxy = proxy
                List(probe.rows, id: \.self) { row in
                    let _ = probe.built(row, transactionTarget: transactionTarget)
                    Text("ROW \(row)")
                        .frame(width: 200, height: 24)
                        .accessibilityIdentifier("public-scroll-\(row)")
                        .id(row == 0 ? "top" : "opaque-\(row)")
                }
                .frame(width: 240, height: 120)
            }
        }
        host.runtime.clock = { probe.now }
        return host
    }

    @MainActor
    private static func renderBounded(
        _ host: MountedLazyListTestHost, probe: PublicLazyListScrollProbe, elementLimit: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let before = probe.factories.count
        host.render()
        XCTAssertLessThanOrEqual(
            probe.factories.count - before, elementLimit,
            "One render must share its row-factory allowance with opaque search", file: file, line: line)
    }

    @MainActor
    private static func drain(
        _ host: MountedLazyListTestHost, probe: PublicLazyListScrollProbe, elementLimit: Int = 128,
        maximumTurns: Int = 256, file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<maximumTurns {
            renderBounded(host, probe: probe, elementLimit: elementLimit, file: file, line: line)
            if !host.runtime.isDirty { return }
        }
        XCTFail("The bounded scroll continuation did not settle", file: file, line: line)
    }

    @MainActor
    private static func assertVisible(
        _ row: Int, in host: MountedLazyListTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let target = try XCTUnwrap(host.find("public-scroll-\(row)"), file: file, line: line)
        let frame = try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: target), file: file, line: line)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization, file: file, line: line)
        XCTAssertGreaterThan(frame.origin.y + frame.size.height, 0, file: file, line: line)
        XCTAssertLessThan(frame.origin.y, host.runtime.root.frame.size.height, file: file, line: line)
    }

    func testLargeImplicitJumpUsesBoundedSlicesAndMountsOnlyItsViewport() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 2_048)
            let host = MountedLazyListTestHost(size: Size(width: 240, height: 120)) {
                ScrollViewReader { proxy in
                    probe.proxy = proxy
                    List(probe.rows, id: \.self) { row in
                        let _ = probe.built(row)
                        Text("ROW \(row)")
                            .frame(width: 200, height: 24)
                            .accessibilityIdentifier("public-scroll-\(row)")
                    }
                    .frame(width: 240, height: 120)
                }
            }
            defer { host.close() }
            Self.drain(host, probe: probe)
            XCTAssertLessThan(probe.factories.count, 128, "Initial construction must follow the viewport")
            XCTAssertNil(host.find("public-scroll-1900"))
            let before = probe.factories.count
            try XCTUnwrap(probe.proxy).scrollTo(1_900, anchor: .top)
            XCTAssertLessThanOrEqual(probe.factories.count - before, 128)

            // Opaque row bodies can hide an explicit ID equal to this data
            // key. The reader preserves priority without publishing a guessed
            // target, even though proving absence can take O(data) slices.
            Self.drain(host, probe: probe)

            try Self.assertVisible(1_900, in: host)
            XCTAssertGreaterThan(try host.scrollContainer().scrollOffset, 10_000)
            let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
            XCTAssertLessThan(adapter.mountedRecordCount, 128)
            XCTAssertLessThan(host.nodes.count, 1_024, "Search candidates must not become retained offscreen rows")
        }
    }

    func testOpaqueFarIDMakesBoundedProgressWithoutMountingScannedRows() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 700)
            let host = Self.opaqueHost(probe)
            defer { host.close() }
            Self.drain(host, probe: probe)
            XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 16, roundLimit: 4))
            let scroll = try host.scrollContainer()
            let before = probe.factories.count
            try XCTUnwrap(probe.proxy).scrollTo("opaque-650", anchor: .top)
            XCTAssertLessThanOrEqual(probe.factories.count - before, 16)
            XCTAssertEqual(scroll.scrollOffset, 0)

            for _ in 0..<8 {
                Self.renderBounded(host, probe: probe, elementLimit: 16)
                XCTAssertEqual(scroll.scrollOffset, 0, "Probe work must not move the viewport")
                XCTAssertNil(host.find("public-scroll-650"))
            }
            XCTAssertGreaterThan(probe.factories.count, before + 16, "A pending search must advance across turns")
            Self.drain(host, probe: probe, elementLimit: 16)

            try Self.assertVisible(650, in: host)
            XCTAssertGreaterThan(scroll.scrollOffset, 10_000)
            XCTAssertLessThan(try host.list().children.count, 128)
        }
    }

    func testPreAttachmentRequestUsesOneFactoryAllowanceThroughFirstAppearance() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 640)
            let host = MountedLazyListTestHost(size: Size(width: 240, height: 120)) {
                ScrollViewReader { proxy in
                    probe.proxy = proxy
                    proxy.scrollTo("opaque-600", anchor: .top)
                    List(probe.rows, id: \.self) { row in
                        let _ = probe.built(row)
                        Text("ROW \(row)")
                            .frame(width: 200, height: 24)
                            .accessibilityIdentifier("public-scroll-\(row)")
                            .id("opaque-\(row)")
                    }
                    .frame(width: 240, height: 120)
                }
            }
            defer { host.close() }
            Self.drain(host, probe: probe)

            try Self.assertVisible(600, in: host)
            XCTAssertEqual(try XCTUnwrap(probe.proxy).retainedScrollResolution, .complete)
        }
    }

    func testUnbuiltExplicitIDWinsOverAnExistingImplicitKeyWithoutAProvisionalJump() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 512)
            let host = MountedLazyListTestHost(size: Size(width: 240, height: 120)) {
                ScrollViewReader { proxy in
                    probe.proxy = proxy
                    List(probe.rows, id: \.self) { row in
                        let _ = probe.built(row)
                        Text("ROW \(row)")
                            .frame(width: 200, height: 24)
                            .accessibilityIdentifier("public-scroll-\(row)")
                            .id(row == 480 ? 17 : row + 10_000)
                    }
                    .frame(width: 240, height: 120)
                }
            }
            defer { host.close() }
            Self.drain(host, probe: probe)
            XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 16, roundLimit: 4))
            let scroll = try host.scrollContainer()
            try XCTUnwrap(probe.proxy).scrollTo(17, anchor: .top)
            for _ in 0..<10 {
                Self.renderBounded(host, probe: probe, elementLimit: 16)
                XCTAssertEqual(
                    scroll.scrollOffset, 0, "Implicit row 17 must not be published while priority is unknown")
            }
            Self.drain(host, probe: probe, elementLimit: 16)

            try Self.assertVisible(480, in: host)
            XCTAssertGreaterThan(scroll.scrollOffset, 10_000)
        }
    }

    func testTypedExplicitIDsDoNotMatchTheirStringDescriptions() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 280)
            let host = MountedLazyListTestHost(size: Size(width: 240, height: 120)) {
                ScrollViewReader { proxy in
                    probe.proxy = proxy
                    List(probe.rows, id: \.self) { row in
                        let _ = probe.built(row)
                        Text("ROW \(row)")
                            .frame(width: 200, height: 24)
                            .accessibilityIdentifier("public-scroll-\(row)")
                            .id(PublicLazyListOpaqueID(value: row))
                    }
                    .frame(width: 240, height: 120)
                }
            }
            defer { host.close() }
            Self.drain(host, probe: probe)
            let proxy = try XCTUnwrap(probe.proxy)
            let scroll = try host.scrollContainer()
            proxy.scrollTo("240", anchor: .top)
            Self.drain(host, probe: probe)
            XCTAssertEqual(scroll.scrollOffset, 0, "A textual description is not a typed scroll ID")

            proxy.scrollTo(PublicLazyListOpaqueID(value: 240), anchor: .top)
            Self.drain(host, probe: probe)
            try Self.assertVisible(240, in: host)
        }
    }

    func testNewRequestCancelsAnOpaqueContinuationDuringAFactory() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 1_000)
            let host = Self.opaqueHost(probe)
            defer { host.close() }
            Self.drain(host, probe: probe)
            XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 4))
            probe.cancelAtRow = 50
            try XCTUnwrap(probe.proxy).scrollTo("opaque-950", anchor: .top)
            Self.drain(host, probe: probe, elementLimit: 8)

            XCTAssertNil(probe.cancelAtRow, "The callback must cancel from inside an admitted probe factory")
            XCTAssertFalse(probe.factories.contains(950), "A superseded cursor must never finish the old search")
            XCTAssertEqual(try host.scrollContainer().scrollOffset, 0)
            let count = probe.factories.count
            host.render()
            host.render()
            XCTAssertEqual(probe.factories.count, count, "Cancellation must stop future factory slices")
        }
    }

    func testSourceReplacementAndDeletionCancelTheOldCursorAndProxy() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 400)
            let host = Self.opaqueHost(probe)
            defer { host.close() }
            Self.drain(host, probe: probe)
            XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 4))
            let obsoleteProxy = try XCTUnwrap(probe.proxy)
            obsoleteProxy.scrollTo("opaque-380", anchor: .top)
            Self.renderBounded(host, probe: probe, elementLimit: 8)

            probe.rows = probe.rows.reversed().filter { $0 != 380 }
            host.reload()
            Self.drain(host, probe: probe, elementLimit: 8)
            let replacementOffset = try host.scrollContainer().scrollOffset
            XCTAssertNil(host.find("public-scroll-380"))
            let count = probe.factories.count
            obsoleteProxy.scrollTo("opaque-380", anchor: .top)
            host.render()
            XCTAssertEqual(probe.factories.count, count)
            XCTAssertEqual(try host.scrollContainer().scrollOffset, replacementOffset)

            try XCTUnwrap(probe.proxy).scrollTo(250, anchor: .top)
            Self.drain(host, probe: probe, elementLimit: 8)
            try Self.assertVisible(250, in: host)
        }
    }

    func testClosedHostRevokesPendingSearchBeforeAnotherFactory() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 600)
            let host = Self.opaqueHost(probe)
            Self.drain(host, probe: probe)
            XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 4))
            let proxy = try XCTUnwrap(probe.proxy)
            proxy.scrollTo("opaque-580", anchor: .top)
            host.close()
            let count = probe.factories.count

            proxy.scrollTo("opaque-590", anchor: .top)
            _ = host.runtime.renderScene()
            _ = host.runtime.renderScene()

            XCTAssertEqual(probe.factories.count, count)
            XCTAssertTrue(host.runtime.root.children.isEmpty)
        }
    }

    func testDetachedReaderStopsReplayingWithoutADisappearanceHook() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 600)
            let host = Self.opaqueHost(probe)
            defer { host.close() }
            Self.drain(host, probe: probe)
            XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 4))
            let proxy = try XCTUnwrap(probe.proxy)
            let reader = try XCTUnwrap(host.nodes.first { $0.scrollReaderID == proxy.retainedIdentifier })
            reader.onDisappearWithNode = nil
            proxy.scrollTo("opaque-580", anchor: .top)
            host.runtime.root.removeAllChildren()
            let count = probe.factories.count

            _ = host.runtime.renderScene()
            _ = host.runtime.renderScene()

            XCTAssertEqual(probe.factories.count, count)
            XCTAssertFalse(
                host.runtime.isDirty, "A missing reader must not requeue solely because its old search was pending")
        }
    }

    func testImplicitTargetWithoutAScrollAncestorCompletesAfterUnrelatedListSearch() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 256)
            let host = MountedLazyListTestHost(size: Size(width: 240, height: 160)) {
                ScrollViewReader { proxy in
                    probe.proxy = proxy
                    VStack(spacing: 0) {
                        ForEach([999], id: \.self) { row in
                            Text("OUTSIDE \(row)").frame(height: 30)
                        }
                        List(probe.rows, id: \.self) { row in
                            let _ = probe.built(row)
                            Text("ROW \(row)").frame(height: 24)
                        }
                        .frame(width: 240, height: 120)
                    }
                }
            }
            defer { host.close() }
            Self.drain(host, probe: probe)
            let proxy = try XCTUnwrap(probe.proxy)
            proxy.scrollTo(999, anchor: .top)
            Self.drain(host, probe: probe, maximumTurns: 32)

            XCTAssertEqual(proxy.retainedScrollResolution, .complete)
            XCTAssertEqual(try host.scrollContainer().scrollOffset, 0)
            XCTAssertFalse(host.runtime.isDirty)
        }
    }

    func testUndiscoveredNestedLazySourceReportsUnsupportedInsteadOfPublishingImplicitFallback() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 384)
            let host = MountedLazyListTestHost(size: Size(width: 240, height: 120)) {
                ScrollViewReader { proxy in
                    probe.proxy = proxy
                    List(probe.rows, id: \.self) { row in
                        let _ = probe.built(row)
                        if row == 300 {
                            List(0..<32, id: \.self) { nested in
                                Text("NESTED \(nested)")
                                    .frame(height: 24)
                                    .accessibilityIdentifier("nested-hidden-\(nested)")
                                    .id(nested == 25 ? 17 : nested + 10_000)
                            }
                            .frame(width: 200, height: 80)
                        } else {
                            Text("ROW \(row)")
                                .frame(width: 200, height: 24)
                                .accessibilityIdentifier("public-scroll-\(row)")
                        }
                    }
                    .frame(width: 240, height: 120)
                }
            }
            defer { host.close() }
            Self.drain(host, probe: probe)
            let proxy = try XCTUnwrap(probe.proxy)
            proxy.scrollTo(17, anchor: .top)
            Self.drain(host, probe: probe)

            XCTAssertEqual(proxy.retainedScrollResolution, .unsupported)
            XCTAssertEqual(try host.scrollContainer().scrollOffset, 0)
            XCTAssertNil(host.find("nested-hidden-25"), "Unsupported search must not publish speculative nested rows")
        }
    }

    func testNestedReaderSearchNeverBuildsOrScrollsTheOtherReadersRows() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 192)
            let host = MountedLazyListTestHost(size: Size(width: 240, height: 200)) {
                ScrollViewReader { proxy in
                    probe.proxy = proxy
                    VStack(spacing: 0) {
                        List(probe.rows, id: \.self) { row in
                            let _ = probe.built(row)
                            Text("OUTER \(row)")
                                .frame(width: 200, height: 24)
                                .accessibilityIdentifier("public-scroll-\(row)")
                                .id(row == 160 ? "shared" : "outer-\(row)")
                        }
                        .frame(width: 240, height: 100)
                        ScrollViewReader { inner in
                            probe.innerProxy = inner
                            List(probe.rows, id: \.self) { row in
                                let _ = probe.built(-row - 1)
                                Text("INNER \(row)")
                                    .frame(width: 200, height: 24)
                                    .accessibilityIdentifier("inner-scroll-\(row)")
                                    .id(row == 170 ? "shared" : "inner-\(row)")
                            }
                            .frame(width: 240, height: 100)
                        }
                    }
                }
            }
            defer { host.close() }
            Self.drain(host, probe: probe)
            let outer = try host.scrollContainer(index: 0)
            let inner = try host.scrollContainer(index: 1)
            let initialInnerFactories = probe.factories.filter { $0 < 0 }.count
            try XCTUnwrap(probe.proxy).scrollTo("inner-180", anchor: .top)
            Self.drain(host, probe: probe)
            XCTAssertEqual(outer.scrollOffset, 0)
            XCTAssertEqual(inner.scrollOffset, 0)
            XCTAssertEqual(probe.factories.filter { $0 < 0 }.count, initialInnerFactories)

            try XCTUnwrap(probe.proxy).scrollTo("shared", anchor: .top)
            Self.drain(host, probe: probe)
            XCTAssertGreaterThan(outer.scrollOffset, 0)
            XCTAssertEqual(inner.scrollOffset, 0)
            XCTAssertNotNil(host.find("public-scroll-160"))

            try XCTUnwrap(probe.innerProxy).scrollTo("shared", anchor: .top)
            Self.drain(host, probe: probe)
            XCTAssertGreaterThan(inner.scrollOffset, 0)
            XCTAssertNotNil(host.find("inner-scroll-170"))
        }
    }

    func testDeferredSearchAndRevealKeepTheAuthoredAnimationTransaction() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 360)
            let host = Self.opaqueHost(probe, transactionTarget: 320)
            defer { host.close() }
            Self.drain(host, probe: probe)
            XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 16, roundLimit: 4))
            probe.recordTargetTransaction = true
            let proxy = try XCTUnwrap(probe.proxy)
            withAnimation(.linear(duration: 0.75)) {
                proxy.scrollTo("opaque-320", anchor: .top)
            }
            withAnimation(.linear(duration: 9)) {
                Self.drain(host, probe: probe, elementLimit: 16)
            }

            let scroll = try host.scrollContainer()
            let destination = scroll.scrollOffset
            XCTAssertGreaterThan(destination, 0)
            XCTAssertFalse(probe.targetTransactionDurations.isEmpty)
            XCTAssertTrue(probe.targetTransactionDurations.allSatisfy { $0 == 0.75 })
            XCTAssertEqual(scroll.resolvedScrollOffset, 0, accuracy: 0.5)
            probe.now = 0.375
            _ = host.runtime.tickAnimations(at: probe.now)
            host.render()
            XCTAssertEqual(scroll.resolvedScrollOffset, destination * 0.5, accuracy: 1)
            probe.now = 0.75
            _ = host.runtime.tickAnimations(at: probe.now)
            host.render()
            XCTAssertEqual(scroll.resolvedScrollOffset, destination, accuracy: 1)
        }
    }

    func testDeferredExplicitNilAnimationDoesNotInheritTheReplayTransaction() async throws {
        try await MainActor.run {
            let probe = PublicLazyListScrollProbe(count: 280)
            let host = Self.opaqueHost(probe, transactionTarget: 240)
            defer { host.close() }
            Self.drain(host, probe: probe)
            XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 16, roundLimit: 4))
            probe.recordTargetTransaction = true
            let proxy = try XCTUnwrap(probe.proxy)
            withAnimation(nil) { proxy.scrollTo("opaque-240", anchor: .top) }
            withAnimation(.linear(duration: 9)) {
                Self.drain(host, probe: probe, elementLimit: 16)
            }

            let scroll = try host.scrollContainer()
            XCTAssertGreaterThan(scroll.scrollOffset, 0)
            XCTAssertEqual(scroll.resolvedScrollOffset, scroll.scrollOffset, accuracy: 0.5)
            XCTAssertFalse(probe.targetTransactionDurations.isEmpty)
            XCTAssertTrue(probe.targetTransactionDurations.allSatisfy { $0 == nil })
        }
    }
}

private struct PublicLazyListOpaqueID: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { String(value) }
}
