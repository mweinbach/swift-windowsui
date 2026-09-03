import SwiftWindowsCore
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

/// Dormant retained-runtime integration only. These fixtures inject a build
/// lease and an identified node factory; they do not enable public List,
/// prove StateMountRegistry membership, or exercise a native window/UIA host.
@MainActor
final class RetainedLazyListRuntimeIntegrationTests: XCTestCase {
    func testTenThousandRowsConstructOnlyViewportAndPrefetchLeaves() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<10_000), prefetch: 20)
        defer { fixture.close() }

        XCTAssertEqual(fixture.source.metadata?.rows.count, 10_000)
        XCTAssertTrue(fixture.probe.factoryCalls.isEmpty)
        XCTAssertEqual(nodeCount(in: fixture.scroll), 2)

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3])
        XCTAssertEqual(fixture.rowIDs, [0, 1, 2, 3])
        XCTAssertEqual(fixture.adapter.logicalRecordCount, 10_000)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 4)
        XCTAssertEqual(fixture.adapter.mountedLeafCount, 4)
        XCTAssertEqual(nodeCount(in: fixture.scroll), 6)
        XCTAssertEqual(fixture.adapter.contentExtent, 200_000)
        XCTAssertEqual(fixture.list.resolvedContentSize.height, 200_000)
        XCTAssertEqual(fixture.list.children.map { $0.resolvedFrame.minY }, [0, 20, 40, 60])
        XCTAssertTrue(fixture.list.children.allSatisfy { $0.parent === fixture.list })
        XCTAssertTrue(fixture.list.children.allSatisfy { $0.resolvedFrame.height == 20 })
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 4)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        assertSettled(fixture)
    }

    func testScrollingThroughCleanAncestorsPreservesOverlappingPhysicalRows() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<1000), wrapperCount: 2)
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let departed = try fixture.row(0)
        let overlapOne = try fixture.row(1)
        let overlapTwo = try fixture.row(2)
        let wrapper = try XCTUnwrap(fixture.wrappers.first)
        let factoriesBeforeQuietPass = fixture.probe.factoryCalls
        let epochsBeforeQuietPass = fixture.lease.epochs.count
        let adoptionsBeforeQuietPass = fixture.lease.epochs.map(\.willAdoptCalls)
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(fixture.probe.factoryCalls, factoriesBeforeQuietPass)
        XCTAssertEqual(fixture.lease.epochs.count, epochsBeforeQuietPass)
        XCTAssertEqual(fixture.lease.epochs.map(\.willAdoptCalls), adoptionsBeforeQuietPass)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertTrue(try fixture.row(0) === departed)
        XCTAssertTrue(try fixture.row(1) === overlapOne)
        XCTAssertTrue(try fixture.row(2) === overlapTwo)
        let previousPass = wrapper.lastLayoutVisitPassID
        XCTAssertTrue(wrapper.subtreeDirtyFlags.intersection([.layout, .children]).isEmpty)

        fixture.scroll.scrollOffset = 20
        XCTAssertTrue(wrapper.subtreeDirtyFlags.intersection([.layout, .children]).isEmpty)
        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3])
        XCTAssertEqual(fixture.rowIDs, [1, 2, 3])
        XCTAssertTrue(try fixture.row(1) === overlapOne)
        XCTAssertTrue(try fixture.row(2) === overlapTwo)
        XCTAssertNil(departed.parent)
        XCTAssertGreaterThan(wrapper.lastLayoutVisitPassID, previousPass)
        XCTAssertEqual(try fixture.row(3).resolvedFrame, Rect(x: 0, y: 60, width: 120, height: 20))
        XCTAssertEqual(nodeCount(in: fixture.scroll), 7)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 1)
        assertSettled(fixture)
    }

    func testReorderingTheSnapshotRetainsVisibleTypedIdentities() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<100))
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let zero = try fixture.row(0)
        let one = try fixture.row(1)
        let two = try fixture.row(2)
        let identities = [zero, one, two].map(\.retainedViewIdentity)

        XCTAssertTrue(fixture.replaceValues([0, 2, 1] + Array(3..<100)))
        fixture.list.setRetainedLazyListMeasurementRevisions(content: 1, environment: 0)
        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.rowIDs, [0, 2, 1])
        XCTAssertTrue(fixture.list.children[0] === zero)
        XCTAssertTrue(fixture.list.children[1] === two)
        XCTAssertTrue(fixture.list.children[2] === one)
        XCTAssertEqual([zero, one, two].map(\.retainedViewIdentity), identities)
        XCTAssertEqual(fixture.list.children.map { $0.resolvedFrame.minY }, [0, 20, 40])
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 0, 2, 1])
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        assertSettled(fixture)
    }

    func testZeroAndMultipleLeavesUseActualUnequalHeightPrefixes() async throws {
        let probe = LazyListRuntimeProbe(heights: [0: [], 1: [7, 13], 2: [30]])
        let fixture = try LazyListRuntimeFixture(values: [0, 1, 2], height: 80, probe: probe)
        defer { fixture.close() }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(probe.factoryCalls, [0, 1, 2])
        XCTAssertEqual(fixture.rowIDs, [1, 1, 2])
        XCTAssertEqual(fixture.list.children.map(\.accessibilityIdentifier), ["1.0", "1.1", "2.0"])
        XCTAssertEqual(fixture.list.children.map { $0.resolvedFrame.minY }, [0, 7, 20])
        XCTAssertEqual(fixture.list.children.map { $0.resolvedFrame.height }, [7, 13, 30])
        XCTAssertEqual(
            fixture.list.children.map(\.retainedViewIdentity),
            [
                fixture.identity(for: 1, leaf: 0), fixture.identity(for: 1, leaf: 1),
                fixture.identity(for: 2, leaf: 0),
            ])
        XCTAssertEqual(fixture.adapter.logicalRecordCount, 3)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 2)
        XCTAssertEqual(fixture.adapter.mountedLeafCount, 3)
        XCTAssertEqual(fixture.adapter.contentExtent, 50)
        XCTAssertEqual(fixture.list.resolvedContentSize.height, 50)
        XCTAssertEqual(try XCTUnwrap(fixture.scroll.scrollContainerState?.contentSize).height, 50)
        XCTAssertEqual(nodeCount(in: fixture.scroll), 5, "Flattened leaves acquire no synthetic row wrapper")
        assertSettled(fixture)
    }

    func testLocalHeightChangesRemeasureRowsAndKeepAnAnchorBeforeAFooter() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<5))
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let first = try fixture.row(0)
        let second = try fixture.row(1)
        first.preferredSize = Size(width: 120, height: 50)

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2])
        XCTAssertTrue(try fixture.row(0) === first)
        XCTAssertTrue(try fixture.row(1) === second)
        XCTAssertEqual(first.resolvedFrame.height, 50)
        XCTAssertEqual(second.resolvedFrame.minY, 50)
        XCTAssertEqual(fixture.rowIDs, [0, 1])
        XCTAssertEqual(fixture.adapter.contentExtent, 130)
        assertSettled(fixture)

        // The list does not own its ancestor's whole scroll range. Its last
        // row can still occupy the leading edge while a later footer is shown.
        let footer = ViewNode(preferredSize: Size(width: 120, height: 1000))
        let tail = try LazyListRuntimeFixture(values: Array(0..<5), height: 100, afterList: [footer])
        defer { tail.close() }
        _ = tail.runtime.renderFrame()
        tail.scroll.scrollOffset = 90
        _ = tail.runtime.renderFrame()
        let last = try tail.row(4)
        last.preferredSize = Size(width: 120, height: 40)

        _ = tail.runtime.renderFrame()

        XCTAssertEqual(tail.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertTrue(try tail.row(4) === last)
        XCTAssertEqual(tail.adapter.contentExtent, 120)
        XCTAssertEqual(tail.scroll.scrollOffset, 90, "Do not clamp a local anchor to list height minus viewport")
        XCTAssertEqual(last.resolvedFrame.minY, 80)
        XCTAssertEqual(last.resolvedFrame.height, 40)
        XCTAssertEqual(footer.resolvedFrame.minY, 120)
        XCTAssertEqual(tail.scroll.resolvedContentSize.height, 1120)
        assertSettled(tail)
    }

    func testWidthScaleAndMeasurementRevisionsRebuildOnlyTheCurrentWindow() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<10_000))
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let retained = fixture.list.children

        fixture.runtime.setRootSize(IntSize(width: 200, height: 60))
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(fixture.probe.factoryCalls.count, 6)
        XCTAssertTrue(fixture.list.children.allSatisfy { $0.resolvedFrame.width == 200 })
        XCTAssertFalse(try fixture.plan(width: 200).requiresResolution)

        fixture.runtime.displayScale = 1.5
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(fixture.probe.factoryCalls.count, 9)
        XCTAssertFalse(try fixture.plan(width: 200, scale: 1.5).requiresResolution)

        fixture.list.setRetainedLazyListMeasurementRevisions(content: 3, environment: 7)
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(fixture.probe.factoryCalls.count, 12)
        XCTAssertFalse(try fixture.plan(width: 200, scale: 1.5, content: 3, environment: 7).requiresResolution)
        XCTAssertEqual(fixture.rowIDs, [0, 1, 2])
        XCTAssertTrue(zip(retained, fixture.list.children).allSatisfy { $0 === $1 })
        XCTAssertEqual(fixture.adapter.logicalRecordCount, 10_000)
        XCTAssertEqual(nodeCount(in: fixture.scroll), 5)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 3)
        assertSettled(fixture)
    }

    func testElementExhaustionPreservesPartialProgressWithoutFalseSettlement() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<1000), elementLimit: 1)
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let first = try fixture.row(0)
        XCTAssertEqual(fixture.rowIDs, [0])
        XCTAssertEqual(fixture.probe.factoryCalls, [0])
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 1)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        assertIncomplete(fixture)

        // Evidence reads do not create a new work scope or synchronously retry.
        for _ in 0..<8 { assertIncomplete(fixture) }
        XCTAssertEqual(fixture.probe.factoryCalls, [0])

        fixture.runtime.clearColor = .red
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(fixture.rowIDs, [0, 1])
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1])
        XCTAssertTrue(try fixture.row(0) === first)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 1)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        assertIncomplete(fixture)

        fixture.runtime.clearColor = .blue
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(fixture.rowIDs, [0, 1, 2])
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2])
        XCTAssertTrue(try fixture.row(0) === first)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 1)
        assertSettled(fixture)
    }

    func testNestedQueriesAndAfterLayoutSettlesCannotResetTheActiveBudget() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<1000), elementLimit: 1)
        defer { fixture.close() }
        var deniedBudgetChanges = 0
        var rejectedNestedQueries = 0
        var afterLayoutCalls = 0
        fixture.probe.onFactory = { [weak runtime = fixture.runtime, weak list = fixture.list] _ in
            guard let runtime, let list else { return XCTFail("The fixture must still be attached") }
            if !runtime.configureLazyListResolutionBudget(elementLimit: 1000, roundLimit: 1000) {
                deniedBudgetChanges += 1
            }
            if runtime.resolvedLayoutFrame(of: list) == nil { rejectedNestedQueries += 1 }
        }
        fixture.runtime.scheduleAfterLayout(key: "lazy-fixture-scroll") {
            [weak runtime = fixture.runtime, weak scroll = fixture.scroll, weak list = fixture.list] in
            guard let runtime, let scroll, let list else { return XCTFail("The fixture must still be attached") }
            afterLayoutCalls += 1
            scroll.scrollOffset = 20
            if !runtime.configureLazyListResolutionBudget(elementLimit: 1000, roundLimit: 1000) {
                deniedBudgetChanges += 1
            }
            if runtime.resolvedLayoutFrame(of: list) == nil { rejectedNestedQueries += 1 }
        }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(afterLayoutCalls, 1)
        XCTAssertEqual(deniedBudgetChanges, 2)
        XCTAssertEqual(rejectedNestedQueries, 2)
        XCTAssertEqual(fixture.probe.factoryCalls, [0])
        XCTAssertEqual(fixture.rowIDs, [0])
        XCTAssertEqual(fixture.scroll.scrollOffset, 20)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 1)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        assertIncomplete(fixture)
    }

    func testGeometryReaderAndRowsConsumeOneSharedElementAllowance() async throws {
        let geometry = LazyListRuntimeGeometryProbe()
        let reader = geometry.node(builtSize: .zero)
        let fixture = try LazyListRuntimeFixture(
            values: Array(0..<1000), beforeList: [reader], elementLimit: 2)
        defer { fixture.close() }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(geometry.calls, 1)
        XCTAssertEqual(fixture.runtime.geometryReaderResolveCount, 1)
        XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 20))
        XCTAssertEqual(fixture.probe.factoryCalls, [0])
        XCTAssertEqual(fixture.rowIDs, [0])
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, geometry.calls + fixture.probe.factoryCalls.count)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 2)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        assertIncomplete(fixture)
    }

    func testFirstFactoryClosingItsProviderStopsTheSecondFactoryAndAdoption() async throws {
        let fixture = try LazyListRuntimeFixture(values: [0, 1, 2], maximumEpochs: 1)
        defer { fixture.close() }
        fixture.probe.onFactory = { [weak source = fixture.source] _ in source?.close() }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.probe.factoryCalls, [0])
        XCTAssertTrue(fixture.source.isClosed)
        XCTAssertTrue(fixture.list.children.isEmpty)
        XCTAssertEqual(fixture.adapter.mountedLeafCount, 0)
        XCTAssertEqual(fixture.runtime.lazyListResolveCount, 0)
        assertAbandonedExactlyOnce(fixture.lease)
        assertIncomplete(fixture)
    }

    func testFirstFactoryReplacingItsLeaseCannotAdoptThroughTheNewLease() async throws {
        let fixture = try LazyListRuntimeFixture(values: [0, 1, 2], maximumEpochs: 1)
        defer { fixture.close() }
        let replacement = LazyListRuntimeLease(maximumEpochs: 0)
        fixture.probe.onFactory = { [weak list = fixture.list, replacement] _ in
            list?.retainedSubtreeBuildLease = replacement
        }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.probe.factoryCalls, [0])
        XCTAssertTrue(fixture.list.retainedSubtreeBuildLease === replacement)
        XCTAssertTrue(replacement.epochs.isEmpty)
        XCTAssertTrue(fixture.list.children.isEmpty)
        XCTAssertEqual(fixture.adapter.mountedLeafCount, 0)
        XCTAssertEqual(fixture.runtime.lazyListResolveCount, 0)
        assertAbandonedExactlyOnce(fixture.lease)
        assertIncomplete(fixture)
    }

    func testFirstFactoryResizingTheRootKeepsTheAuthoredSizeButRejectsItsRows() async throws {
        let fixture = try LazyListRuntimeFixture(values: [0, 1, 2], maximumEpochs: 1)
        defer { fixture.close() }
        fixture.probe.onFactory = { [weak runtime = fixture.runtime] _ in
            runtime?.setRootSize(IntSize(width: 200, height: 80))
        }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.probe.factoryCalls, [0])
        XCTAssertEqual(fixture.scroll.frame.size, Size(width: 200, height: 80))
        XCTAssertTrue(fixture.list.children.isEmpty)
        XCTAssertEqual(fixture.adapter.mountedLeafCount, 0)
        XCTAssertEqual(fixture.runtime.lazyListResolveCount, 0)
        assertAbandonedExactlyOnce(fixture.lease)
        assertIncomplete(fixture)
    }

    func testWillAdoptClosingOrSupersedingTheBuildStopsBeforeRetainedMutation() async throws {
        for closesProvider in [true, false] {
            let fixture = try LazyListRuntimeFixture(values: [0, 1, 2], maximumEpochs: 1)
            defer { fixture.close() }
            var reloadCalls = 0
            fixture.lease.onWillAdopt = { [weak source = fixture.source, weak runtime = fixture.runtime] _ in
                if closesProvider {
                    source?.close()
                } else {
                    runtime?.retainedBuildCoordinator.scheduleReload { reloadCalls += 1 }
                }
            }

            _ = fixture.runtime.renderFrame()

            XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2])
            XCTAssertTrue(fixture.list.children.isEmpty)
            XCTAssertEqual(fixture.adapter.mountedLeafCount, 0)
            XCTAssertEqual(fixture.runtime.lazyListResolveCount, 0)
            XCTAssertEqual(reloadCalls, closesProvider ? 0 : 1)
            let epoch = try XCTUnwrap(fixture.lease.epochs.first)
            XCTAssertEqual(epoch.willAdoptCalls, 1)
            XCTAssertEqual(epoch.canAdoptReadsAfterPreparation, 0)
            assertAbandonedExactlyOnce(fixture.lease)
            assertIncomplete(fixture)
        }
    }

    func testOneShotPreparationAndFinishRevocationNeverRollBackPublishedRows() async throws {
        for revokesCompletion in [false, true] {
            let fixture = try LazyListRuntimeFixture(values: [0, 1, 2], maximumEpochs: 1)
            defer { fixture.close() }
            var childrenSeenByCleanup: [ObjectIdentifier] = []
            fixture.lease.onFinish = { [weak list = fixture.list] epoch in
                childrenSeenByCleanup = list?.children.map(ObjectIdentifier.init) ?? []
                if revokesCompletion { epoch.completionAllowed = false }
            }

            _ = fixture.runtime.renderFrame()

            XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2])
            XCTAssertEqual(fixture.rowIDs, [0, 1, 2])
            XCTAssertEqual(fixture.list.children.map(ObjectIdentifier.init), childrenSeenByCleanup)
            XCTAssertEqual(childrenSeenByCleanup.count, 3)
            XCTAssertEqual(fixture.lease.epochs.count, 1)
            let epoch = try XCTUnwrap(fixture.lease.epochs.first)
            XCTAssertEqual(epoch.willAdoptCalls, 1)
            XCTAssertEqual(epoch.canAdoptReadsAfterPreparation, 0)
            XCTAssertEqual(epoch.commitCalls, 1)
            XCTAssertEqual(epoch.abandonCalls, 0)
            XCTAssertEqual(epoch.finishCalls, 1)
            XCTAssertEqual(epoch.canCompleteReads, revokesCompletion ? 1 : 2)
            XCTAssertEqual(fixture.runtime.lazyListResolveCount, revokesCompletion ? 0 : 1)
            XCTAssertEqual(fixture.adapter.mountedLeafCount, revokesCompletion ? 0 : 3)
            XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
            if revokesCompletion {
                assertIncomplete(fixture)
            } else {
                assertSettled(fixture)
            }
        }
    }

    func testRawAndWrongRowPrefixesStayUnsupportedWithoutAdoptingLeaves() async throws {
        for identityMode in [LazyListRuntimeIdentityMode.plain, .wrongRow] {
            let fixture = try LazyListRuntimeFixture(
                values: [0, 1, 2], identityMode: identityMode, maximumEpochs: 1)
            defer { fixture.close() }

            _ = fixture.runtime.renderFrame()

            XCTAssertEqual(fixture.probe.factoryCalls, identityMode == .plain ? [] : [0])
            XCTAssertTrue(fixture.list.children.isEmpty)
            XCTAssertEqual(fixture.adapter.mountedLeafCount, 0)
            XCTAssertEqual(fixture.runtime.lazyListResolveCount, 0)
            XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, identityMode == .plain ? 0 : 1)
            XCTAssertEqual(try XCTUnwrap(fixture.lease.epochs.first).willAdoptCalls, 0)
            assertAbandonedExactlyOnce(fixture.lease)
            assertIncomplete(fixture)
        }
    }

    func testMeasuringAListAfterAHeaderDoesNotScrollTheHeaderAway() async throws {
        let header = ViewNode(preferredSize: Size(width: 120, height: 40))
        let probe = LazyListRuntimeProbe(heights: [0: [40]])
        let fixture = try LazyListRuntimeFixture(
            values: Array(0..<100), beforeList: [header], probe: probe)
        defer { fixture.close() }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(probe.factoryCalls, [0])
        XCTAssertEqual(fixture.rowIDs, [0])
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 0)
        XCTAssertEqual(header.resolvedFrame, Rect(x: 0, y: 0, width: 120, height: 40))
        XCTAssertEqual(fixture.list.resolvedFrame.minY, 40)
        XCTAssertEqual(try fixture.row(0).resolvedFrame, Rect(x: 0, y: 0, width: 120, height: 40))
        XCTAssertEqual(fixture.adapter.contentExtent, 2020)
        XCTAssertEqual(fixture.scroll.resolvedContentSize.height, 2060)
        assertSettled(fixture)
    }

    func testEqualCandidateIdentityCleanupStaysInsideTheBuildAndRevokesCompletion() async throws {
        let probe = LazyListRuntimeProbe()
        probe.identitySuffix = { _, _ in .explicit(.init(LazyListRuntimeEqualIdentityKey(value: 1))) }
        let fixture = try LazyListRuntimeFixture(values: [0], probe: probe, maximumEpochs: 2)
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let retained = try fixture.row(0)
        XCTAssertEqual(fixture.runtime.lazyListResolveCount, 1)
        assertSettled(fixture)

        var cleanupSawActiveBuild: [Bool] = []
        // A fresh class key compares equal to the old retained suffix. Only
        // the discarded factory node owns this new key: the test, provider
        // metadata, and actual retained identity keep no alias to it.
        probe.identitySuffix = { [weak runtime = fixture.runtime, weak source = fixture.source] _, _ in
            let key = LazyListRuntimeEqualIdentityKey(value: 1) { [weak runtime, weak source] in
                cleanupSawActiveBuild.append(runtime?.retainedBuildCoordinator.isBuilding == true)
                source?.close()
            }
            return .explicit(.init(key))
        }
        XCTAssertTrue(fixture.replaceValues([0]))
        fixture.list.setRetainedLazyListMeasurementRevisions(content: 1, environment: 0)

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(probe.factoryCalls, [0, 0])
        XCTAssertEqual(cleanupSawActiveBuild, [true])
        XCTAssertTrue(fixture.source.isClosed)
        XCTAssertTrue(try fixture.row(0) === retained, "Cleanup revocation cannot roll back an adopted physical row")
        XCTAssertEqual(
            fixture.runtime.lazyListResolveCount, 1, "Do not count completion before candidate payload cleanup")
        XCTAssertEqual(fixture.lease.epochs.count, 2)
        for epoch in fixture.lease.epochs {
            XCTAssertEqual(epoch.commitCalls, 1)
            XCTAssertEqual(epoch.abandonCalls, 0)
            XCTAssertEqual(epoch.finishCalls, 1)
            XCTAssertEqual(epoch.canAdoptReadsAfterPreparation, 0)
        }
        assertIncomplete(fixture)
    }

    func testDeferredLeadingAlignmentGuideMatchesOrdinaryPlacementAndStretch() async throws {
        let guide = RetainedAlignmentGuide(axis: .horizontal, guide: "leading", value: 11)
        let ordinaryRow = ViewNode(
            preferredSize: Size(width: 40, height: 20), alignmentGuides: [guide])
        let ordinaryStack = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 60),
            layoutMode: .stack(.vertical(spacing: 0, alignment: .leading)), children: [ordinaryRow])
        let ordinaryRuntime = RetainedViewRuntime(root: ordinaryStack)
        ordinaryRuntime.clock = { 0 }
        let fixture = try LazyListRuntimeFixture(values: [0])
        defer { fixture.close() }
        var factoryCalls: [Int] = []
        XCTAssertTrue(
            fixture.source.replaceData([0], id: \.self, identityRoot: LazyListRuntimeFixture.identityRoot) {
                value, prefix in
                factoryCalls.append(value)
                let node = ViewNode(
                    preferredSize: Size(width: 40, height: 20), alignmentGuides: [guide])
                node.retainedViewIdentity = prefix.appending(.slot(0))
                node.dynamicContentIndex = value
                return [node]
            })
        fixture.list.layoutMode = .lazyStack(.vertical(spacing: 0, alignment: .leading))

        _ = ordinaryRuntime.renderFrame()
        _ = fixture.runtime.renderFrame()

        let retained = try fixture.row(0)
        XCTAssertEqual(ordinaryRow.resolvedFrame, Rect(x: -11, y: 0, width: 40, height: 20))
        XCTAssertEqual(retained.resolvedFrame, ordinaryRow.resolvedFrame)
        XCTAssertEqual(retained.alignmentGuides, [guide])
        XCTAssertEqual(factoryCalls, [0])
        XCTAssertTrue(fixture.probe.factoryCalls.isEmpty, "The replaced metadata factory must not run")
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 1)
        assertSettled(fixture)

        ordinaryStack.layoutMode = .stack(.vertical(spacing: 0, alignment: .stretch))
        fixture.list.layoutMode = .lazyStack(.vertical(spacing: 0, alignment: .stretch))
        _ = ordinaryRuntime.renderFrame()
        _ = fixture.runtime.renderFrame()

        XCTAssertTrue(try fixture.row(0) === retained)
        XCTAssertEqual(ordinaryRow.resolvedFrame, Rect(x: 0, y: 0, width: 120, height: 20))
        XCTAssertEqual(retained.resolvedFrame, ordinaryRow.resolvedFrame)
        XCTAssertEqual(retained.alignmentGuides, [guide], "Stretch ignores the guide without removing it")
        XCTAssertEqual(factoryCalls, [0], "Alignment changes must not reconstruct an already mounted row")
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(fixture.runtime.lazyListResolveCount, 1)
        XCTAssertEqual(nodeCount(in: fixture.scroll), 3)
        assertSettled(fixture)
    }

    func testBottomRowShrinkNormalizesTheStoredOffsetBeforeKeyboardScrolling() async throws {
        // Keep this small cohort mounted across the whole range so the case
        // isolates range correction from otherwise valid row reconstruction.
        let fixture = try LazyListRuntimeFixture(values: Array(0..<5), prefetch: 40)
        defer { fixture.close() }
        fixture.scroll.isFocusable = true
        fixture.scroll.scrollStep = 16
        let generation = try XCTUnwrap(fixture.source.metadata?.generation)
        _ = fixture.runtime.renderFrame()
        let retained = fixture.list.children
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.adapter.contentExtent, 100)

        fixture.scroll.scrollOffset = 40
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(fixture.scroll.scrollOffset, 40)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 40)
        let last = try fixture.row(4)
        last.preferredSize = Size(width: 120, height: 5)

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.adapter.contentExtent, 85)
        XCTAssertEqual(try XCTUnwrap(fixture.scroll.scrollContainerState?.contentSize).height, 85)
        XCTAssertEqual(fixture.scroll.scrollOffset, 25, "Normalize the stored offset against the fresh enclosing range")
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 25)
        XCTAssertEqual(last.resolvedFrame, Rect(x: 0, y: 80, width: 120, height: 5))
        XCTAssertEqual(fixture.rowIDs, [0, 1, 2, 3, 4])
        XCTAssertTrue(zip(retained, fixture.list.children).allSatisfy { $0 === $1 })
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        assertSettled(fixture)

        fixture.runtime.pointerMoved(to: Point(x: 30, y: 30))
        fixture.runtime.requestFocus(fixture.scroll)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.scroll)
        XCTAssertEqual(fixture.scroll.scrollOffset, 25)
        fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))

        // The key changes the logical offset immediately. Its existing visual
        // tween is not a reason to reuse the stale pre-shrink value of 40.
        XCTAssertEqual(fixture.scroll.scrollOffset, 9)
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
    }

    func testAnchorNormalizationWaitsForAnotherOrdinaryFrameWhenItsRoundBudgetEnds() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<5), prefetch: 40)
        defer { fixture.close() }
        let generation = try XCTUnwrap(fixture.source.metadata?.generation)
        _ = fixture.runtime.renderFrame()
        fixture.scroll.scrollOffset = 40
        _ = fixture.runtime.renderFrame()
        let retained = fixture.list.children
        let last = try fixture.row(4)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 40)
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 1))
        last.preferredSize = Size(width: 120, height: 5)

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.adapter.contentExtent, 85)
        XCTAssertEqual(fixture.scroll.scrollOffset, 25)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 25)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        // The adapter has measured its rows, but Runtime still owes a pass
        // which visits the corrected viewport. Adapter readiness is not enough.
        if case .settled = fixture.runtime.layoutSettlementStatus {
            XCTFail("Normalizing the offset does not replace the bounded pass that proves its viewport")
        }
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)
        XCTAssertEqual(fixture.list.children.count, retained.count)
        XCTAssertTrue(zip(retained, fixture.list.children).allSatisfy { $0 === $1 })

        // Keep the same one-round allowance. An independent ordinary repaint,
        // not an inline retry or expanded budget, supplies the remaining pass.
        fixture.runtime.clearColor = .red
        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.scroll.scrollOffset, 25)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 25)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)
        XCTAssertEqual(fixture.list.children.count, retained.count)
        XCTAssertTrue(zip(retained, fixture.list.children).allSatisfy { $0 === $1 })
        assertSettled(fixture)
    }

    func testAnEqualAuthoredScrollAssignmentRevokesPendingAnchorNormalization() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<5), prefetch: 40)
        defer {
            fixture.scroll.onLayout = nil
            fixture.close()
        }
        let generation = try XCTUnwrap(fixture.source.metadata?.generation)
        _ = fixture.runtime.renderFrame()
        fixture.scroll.scrollOffset = 40
        _ = fixture.runtime.renderFrame()
        let retained = fixture.list.children
        var authoredAssignments = 0
        var offsetsSeenByLayout: [Double] = []
        fixture.scroll.onLayout = { [weak scroll = fixture.scroll, weak adapter = fixture.adapter] _ in
            guard let scroll, let adapter, adapter.contentExtent == 85, authoredAssignments == 0 else { return }
            authoredAssignments += 1
            offsetsSeenByLayout.append(scroll.scrollOffset)
            // This intent arrives after the measured shrink registered its
            // pending correction. Value equality must not revive that correction.
            scroll.scrollOffset = 40
        }
        let last = try fixture.row(4)
        last.preferredSize = Size(width: 120, height: 5)

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(authoredAssignments, 1)
        XCTAssertEqual(offsetsSeenByLayout, [40])
        XCTAssertEqual(fixture.adapter.contentExtent, 85)
        XCTAssertEqual(fixture.scroll.scrollOffset, 40, "The old anchor cannot overwrite a newer equal-valued intent")
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 25)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .workRemaining)
        if case .settled = fixture.runtime.layoutSettlementStatus {
            XCTFail("A viewport changed during the pass cannot establish settlement")
        }
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)
        XCTAssertEqual(fixture.list.children.count, retained.count)
        XCTAssertTrue(zip(retained, fixture.list.children).allSatisfy { $0 === $1 })

        fixture.runtime.clearColor = .blue
        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(authoredAssignments, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, 40, "A later ordinary pass cannot restore the revoked correction")
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 25)
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        assertSettled(fixture)
    }

    func testFractionalHeaderOriginSurvivesBottomShrinkAndKeyboardScrolling() async throws {
        let header = ViewNode(preferredSize: Size(width: 120, height: 0.3))
        let fixture = try LazyListRuntimeFixture(
            values: Array(0..<5), prefetch: 40, beforeList: [header])
        defer { fixture.close() }
        fixture.scroll.isFocusable = true
        fixture.scroll.scrollStep = 16
        let generation = try XCTUnwrap(fixture.source.metadata?.generation)
        _ = fixture.runtime.renderFrame()
        let retained = fixture.list.children.map(ObjectIdentifier.init)
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        fixture.scroll.scrollOffset = 40.3
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(fixture.scroll.scrollOffset, 40.3, accuracy: 0.000_000_001)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 40.3, accuracy: 0.000_000_001)
        let last = try fixture.row(4)
        last.preferredSize = Size(width: 120, height: 5)

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.adapter.contentExtent, 85)
        XCTAssertEqual(fixture.scroll.resolvedContentSize.height, 85.3, accuracy: 0.000_000_001)
        XCTAssertEqual(fixture.list.resolvedFrame.minY, 0.3, accuracy: 0.000_000_001)
        XCTAssertEqual(fixture.scroll.scrollOffset, 25.3, accuracy: 0.000_000_001)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 25.3, accuracy: 0.000_000_001)
        XCTAssertEqual(last.resolvedFrame.height, 5)
        XCTAssertEqual(fixture.list.children.map(ObjectIdentifier.init), retained)
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        assertSettled(fixture)

        fixture.runtime.pointerMoved(to: Point(x: 30, y: 30))
        fixture.runtime.requestFocus(fixture.scroll)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.scroll)
        fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))

        XCTAssertEqual(fixture.scroll.scrollOffset, 9.3, accuracy: 0.000_000_001)
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
    }

    func testAnInvalidatedZeroRoundPassCannotErasePendingAnchorLayout() async throws {
        let fixture = try LazyListRuntimeFixture(values: Array(0..<5), prefetch: 40)
        defer {
            fixture.scroll.onLayout = nil
            fixture.close()
        }
        let generation = try XCTUnwrap(fixture.source.metadata?.generation)
        _ = fixture.runtime.renderFrame()
        fixture.scroll.scrollOffset = 40
        _ = fixture.runtime.renderFrame()
        let retained = fixture.list.children.map(ObjectIdentifier.init)
        let first = try fixture.row(0)
        let last = try fixture.row(4)
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 1))
        last.preferredSize = Size(width: 120, height: 5)
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(fixture.scroll.scrollOffset, 25)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 25)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)

        var geometryMutationCalls = 0
        fixture.scroll.onLayout = { [weak first] _ in
            guard let first, geometryMutationCalls == 0 else { return }
            geometryMutationCalls += 1
            first.preferredSize = Size(width: 80, height: 20)
        }
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 0))
        // Budget configuration invalidates runtime evidence, not individual
        // node caches. Invalidate the root's unchanged layout mode so its
        // callback definitely enters and changes geometry during this pass.
        fixture.scroll.layoutMode = .stack(.vertical(spacing: 0, alignment: .stretch))

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(geometryMutationCalls, 1)
        XCTAssertEqual(first.preferredSize, Size(width: 80, height: 20))
        XCTAssertEqual(fixture.adapter.contentExtent, 85)
        XCTAssertEqual(fixture.scroll.scrollOffset, 25)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 25)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 0)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        if case .settled = fixture.runtime.layoutSettlementStatus {
            XCTFail("A failed pass cannot clear the pending requirement to lay out the normalized viewport")
        }
        XCTAssertEqual(fixture.list.children.map(ObjectIdentifier.init), retained)
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)

        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 4))
        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(geometryMutationCalls, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, 25)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 25)
        XCTAssertEqual(fixture.list.children.map(ObjectIdentifier.init), retained)
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.source.metadata?.generation, generation)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        assertSettled(fixture)
    }

    private func assertSettled(
        _ fixture: LazyListRuntimeFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork, file: file, line: line)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .complete, file: file, line: line)
        guard case .settled(let receipt) = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("A measured, complete current window must establish settlement", file: file, line: line)
        }
        XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
    }

    private func assertIncomplete(
        _ fixture: LazyListRuntimeFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork, file: file, line: line)
        if case .settled = fixture.runtime.layoutSettlementStatus {
            XCTFail("Pending or obsolete rows cannot produce a settled receipt", file: file, line: line)
        }
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild, file: file, line: line)
    }

    private func assertAbandonedExactlyOnce(
        _ lease: LazyListRuntimeLease, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(lease.epochs.count, 1, file: file, line: line)
        guard let epoch = lease.epochs.first else { return }
        XCTAssertEqual(epoch.commitCalls, 0, file: file, line: line)
        XCTAssertEqual(epoch.abandonCalls, 1, file: file, line: line)
        XCTAssertEqual(epoch.finishCalls, 1, file: file, line: line)
    }

    private func nodeCount(in root: ViewNode) -> Int {
        var pending = [root]
        var visited: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            if visited.insert(ObjectIdentifier(node)).inserted { pending.append(contentsOf: node.children) }
        }
        return visited.count
    }
}

private enum LazyListRuntimeIdentityMode: Equatable { case identified, plain, wrongRow }
private enum LazyListRuntimeFixtureError: Error { case source, budget }

@MainActor
private final class LazyListRuntimeFixture {
    static let identityRoot = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let list: ViewNode
    let wrappers: [ViewNode]
    let scroll: ViewNode
    let runtime: RetainedViewRuntime
    let lease: LazyListRuntimeLease
    let probe: LazyListRuntimeProbe
    private let identityMode: LazyListRuntimeIdentityMode

    init(
        values: [Int], width: Double = 120, height: Double = 60, estimate: Double = 20,
        prefetch: Double = 0, wrapperCount: Int = 0, beforeList: [ViewNode] = [], afterList: [ViewNode] = [],
        probe: LazyListRuntimeProbe = LazyListRuntimeProbe(),
        identityMode: LazyListRuntimeIdentityMode = .identified,
        elementLimit: Int = 32, roundLimit: Int = 4, maximumEpochs: Int? = nil
    ) throws {
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        guard Self.replace(values, in: source, probe: probe, identityMode: identityMode) else {
            throw LazyListRuntimeFixtureError.source
        }
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: estimate, prefetchExtent: prefetch,
                maximumMountedRecords: 16, maximumMountedLeaves: 32, maximumProtectedRecords: 2))
        let lease = LazyListRuntimeLease(maximumEpochs: maximumEpochs)
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        list.retainedLazyListAdapter = adapter
        list.retainedSubtreeBuildLease = lease
        var ancestor = list
        var wrappers: [ViewNode] = []
        for _ in 0..<wrapperCount {
            let wrapper = ViewNode(layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), children: [ancestor])
            wrappers.append(wrapper)
            ancestor = wrapper
        }
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: width, height: height), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical,
            children: beforeList + [ancestor] + afterList)
        let runtime = RetainedViewRuntime(root: scroll)
        runtime.clock = { 0 }
        guard runtime.configureLazyListResolutionBudget(elementLimit: elementLimit, roundLimit: roundLimit) else {
            throw LazyListRuntimeFixtureError.budget
        }
        self.source = source
        self.adapter = adapter
        self.list = list
        self.wrappers = wrappers
        self.scroll = scroll
        self.runtime = runtime
        self.lease = lease
        self.probe = probe
        self.identityMode = identityMode
    }

    var rowIDs: [Int] { list.children.compactMap(\.dynamicContentIndex) }

    func row(_ id: Int) throws -> ViewNode {
        try XCTUnwrap(list.children.first { $0.dynamicContentIndex == id })
    }

    func identity(for value: Int, leaf: Int) -> RetainedViewIdentity {
        Self.identityRoot.appending(contentsOf: [.role(.row), .keyed(.init(value)), .occurrence(0), .slot(leaf)])
    }

    func replaceValues(_ values: [Int]) -> Bool {
        Self.replace(values, in: source, probe: probe, identityMode: identityMode)
    }

    func plan(
        width: Double = 120, scale: Double = 1, content: UInt64 = 0, environment: UInt64 = 0
    ) throws -> RetainedLazyListRuntimeAdapter.LayoutPlan {
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: width, displayScale: scale, contentRevision: content, environmentRevision: environment))
        let viewport = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter.Viewport(
                context: context, offset: scroll.resolvedScrollOffset, extent: scroll.resolvedFrame.height))
        return adapter.layoutPlan(viewport: viewport)
    }

    func close() {
        probe.onFactory = nil
        probe.identitySuffix = nil
        lease.onWillAdopt = nil
        lease.onFinish = nil
        source.close()
    }

    private static func replace(
        _ values: [Int], in source: RetainedLazyListDataSource<Int, [ViewNode]>,
        probe: LazyListRuntimeProbe, identityMode: LazyListRuntimeIdentityMode
    ) -> Bool {
        if identityMode == .plain {
            return source.replaceData(values, id: \.self) { [probe] value in
                probe.makeNodes(value, prefix: nil)
            }
        }
        return source.replaceData(values, id: \.self, identityRoot: identityRoot) { [probe] value, prefix in
            let usedPrefix =
                identityMode == .wrongRow
                ? Self.identityRoot.appending(contentsOf: [.role(.row), .keyed(.init(value + 100_000)), .occurrence(0)])
                : prefix
            return probe.makeNodes(value, prefix: usedPrefix)
        }
    }
}

@MainActor
private final class LazyListRuntimeProbe {
    let heights: [Int: [Double]]
    var onFactory: (@MainActor (Int) -> Void)?
    var identitySuffix: (@MainActor (Int, Int) -> RetainedViewIdentity.Segment)?
    private(set) var factoryCalls: [Int] = []

    init(heights: [Int: [Double]] = [:]) { self.heights = heights }

    func makeNodes(_ value: Int, prefix: RetainedViewIdentity?) -> [ViewNode] {
        factoryCalls.append(value)
        onFactory?(value)
        return (heights[value] ?? [20]).enumerated().map { leaf, height in
            let node = ViewNode(preferredSize: Size(width: 120, height: height))
            let leafIdentity = prefix?.appending(.slot(leaf))
            if let suffix = identitySuffix?(value, leaf) {
                node.retainedViewIdentity = leafIdentity?.appending(suffix)
            } else {
                node.retainedViewIdentity = leafIdentity
            }
            node.dynamicContentIndex = value
            node.accessibilityIdentifier = "\(value).\(leaf)"
            return node
        }
    }
}

private final class LazyListRuntimeEqualIdentityKey: Hashable {
    let value: Int
    let onDestroy: (@MainActor () -> Void)?

    init(value: Int, onDestroy: (@MainActor () -> Void)? = nil) {
        self.value = value
        self.onDestroy = onDestroy
    }

    static func == (lhs: LazyListRuntimeEqualIdentityKey, rhs: LazyListRuntimeEqualIdentityKey) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }

    deinit {
        MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
    }
}

@MainActor
private final class LazyListRuntimeGeometryProbe {
    private(set) var calls = 0

    func node(builtSize: Size) -> ViewNode {
        let node = ViewNode(preferredSize: Size(width: 120, height: 20))
        node.geometryReaderBuiltSize = builtSize
        node.geometryReaderBuild = { [self] _, slot in
            calls += 1
            return [self.node(builtSize: slot)]
        }
        return node
    }
}

/// Every issued epoch remains observable. These counters intentionally do not
/// coalesce duplicate commit/abandon/finish calls into an apparently good run.
@MainActor
private final class LazyListRuntimeLease: RetainedSubtreeBuildLease {
    let maximumEpochs: Int?
    var onWillAdopt: (@MainActor (LazyListRuntimeEpoch) -> Void)?
    var onFinish: (@MainActor (LazyListRuntimeEpoch) -> Void)?
    private(set) var epochs: [LazyListRuntimeEpoch] = []

    init(maximumEpochs: Int? = nil) { self.maximumEpochs = maximumEpochs }

    var canBuild: Bool { maximumEpochs.map { epochs.count < $0 } ?? true }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        guard canBuild else { return nil }
        let epoch = LazyListRuntimeEpoch(onWillAdopt: onWillAdopt, onFinish: onFinish)
        epochs.append(epoch)
        return epoch
    }
}

@MainActor
private final class LazyListRuntimeEpoch: RetainedBuildEpoch {
    private let onWillAdopt: (@MainActor (LazyListRuntimeEpoch) -> Void)?
    private let onFinish: (@MainActor (LazyListRuntimeEpoch) -> Void)?
    private var leftConstruction = false
    private var wasSuperseded = false
    var completionAllowed = true
    private(set) var willAdoptCalls = 0
    private(set) var canAdoptReadsAfterPreparation = 0
    private(set) var canCompleteReads = 0
    private(set) var commitCalls = 0
    private(set) var abandonCalls = 0
    private(set) var finishCalls = 0

    init(
        onWillAdopt: (@MainActor (LazyListRuntimeEpoch) -> Void)?,
        onFinish: (@MainActor (LazyListRuntimeEpoch) -> Void)?
    ) {
        self.onWillAdopt = onWillAdopt
        self.onFinish = onFinish
    }

    var canAdopt: Bool {
        if leftConstruction { canAdoptReadsAfterPreparation += 1 }
        return !leftConstruction && !wasSuperseded
    }

    var canComplete: Bool {
        canCompleteReads += 1
        return completionAllowed
    }

    func supersede() {
        if !leftConstruction { wasSuperseded = true }
    }

    func willAdopt() -> Bool {
        willAdoptCalls += 1
        guard !leftConstruction, !wasSuperseded else { return false }
        leftConstruction = true
        onWillAdopt?(self)
        return true
    }

    func commit() { commitCalls += 1 }
    func abandon() { abandonCalls += 1 }
    func finishAfterCallbacks() {
        finishCalls += 1
        onFinish?(self)
    }
}

/// Lookup regression controls use the existing retained-runtime fixture. The
/// immutable layout scope still supplies every physical operand and proof.
@MainActor
final class LazyListOperandLookupTests: XCTestCase {
    func testWideMultiLeafRosterKeepsPhysicalPlacementOrderAndSizes() async throws {
        let values = Array(0..<16)
        let probe = LazyListRuntimeProbe(heights: Dictionary(uniqueKeysWithValues: values.map { ($0, [13.0, 27.0]) }))
        let fixture = try LazyListRuntimeFixture(
            values: values, height: 640, estimate: 40, probe: probe, elementLimit: 32)
        defer { fixture.close() }

        _ = fixture.runtime.renderFrame()

        let plan = try fixture.plan()
        XCTAssertEqual(probe.factoryCalls, values)
        XCTAssertEqual(plan.placements.count, 32)
        XCTAssertEqual(fixture.list.children.count, 32)
        XCTAssertEqual(plan.contentExtent, 640)
        XCTAssertFalse(plan.requiresResolution)
        for (index, placement) in plan.placements.enumerated() {
            let row = index / 2
            let leaf = index % 2
            let expected = Rect(
                x: 0, y: Double(row * 40 + (leaf == 0 ? 0 : 13)),
                width: 120, height: leaf == 0 ? 13 : 27)
            XCTAssertTrue(placement.node === fixture.list.children[index])
            XCTAssertTrue(placement.node.parent === fixture.list)
            XCTAssertEqual(placement.node.resolvedFrame, expected)
            XCTAssertEqual(placement.originY, expected.origin.y)
            XCTAssertEqual(placement.extent, expected.height)
        }
        let originalNodes = fixture.list.children
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(probe.factoryCalls, values)
        XCTAssertTrue(zip(originalNodes, fixture.list.children).allSatisfy { $0 === $1 })
        XCTAssertEqual(try fixture.plan().placements.count, 32)
    }

    func testNestedSelectedLeavesUseTheirPhysicalOperandKeys() async throws {
        let values = Array(0..<8)
        let fixture = try LazyListRuntimeFixture(values: values, height: 160)
        defer { fixture.close() }
        var factories: [Int] = []
        XCTAssertTrue(
            fixture.source.replaceData(
                values, id: \.self, identityRoot: LazyListRuntimeFixture.identityRoot
            ) { value, prefix in
                factories.append(value)
                let selected = ViewNode(preferredSize: Size(width: 80, height: 20))
                let inner = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
                let physical = ViewNode.selectedContentBoundary(role: .viewThatFits, child: inner)
                physical.retainedViewIdentity = prefix.appending(.slot(0))
                physical.dynamicContentIndex = value
                return [physical]
            })

        _ = fixture.runtime.renderFrame()

        let plan = try fixture.plan()
        XCTAssertEqual(factories, values)
        XCTAssertTrue(fixture.probe.factoryCalls.isEmpty)
        XCTAssertEqual(plan.placements.count, 8)
        XCTAssertFalse(plan.requiresResolution)
        for (index, placement) in plan.placements.enumerated() {
            let physical = try fixture.row(index)
            let inner = try XCTUnwrap(physical.children.first)
            let selected = try XCTUnwrap(inner.children.first)
            XCTAssertTrue(placement.node === physical)
            XCTAssertFalse(placement.node === selected)
            XCTAssertTrue(fixture.adapter.mountedNodes(for: placement.token)?.first === physical)
            XCTAssertEqual(physical.resolvedFrame, .zero)
            XCTAssertEqual(inner.resolvedFrame, .zero)
            XCTAssertEqual(selected.resolvedFrame, Rect(x: 0, y: Double(index * 20), width: 120, height: 20))
            XCTAssertTrue(physical.parent === fixture.list)
            XCTAssertTrue(selected.parent === inner)
        }
    }

    func testEmptyPlanKeepsZeroPlacementsAndDoesNotBuildRows() async throws {
        let fixture = try LazyListRuntimeFixture(values: [])
        defer { fixture.close() }

        _ = fixture.runtime.renderFrame()

        let plan = try fixture.plan()
        XCTAssertTrue(plan.placements.isEmpty)
        XCTAssertTrue(fixture.list.children.isEmpty)
        XCTAssertTrue(fixture.probe.factoryCalls.isEmpty)
        XCTAssertEqual(plan.contentExtent, 0)
        XCTAssertFalse(plan.requiresResolution)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 0)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
    }
}
