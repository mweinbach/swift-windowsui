import XCTest

@testable import SwiftWindowsUI

/// Planning/ownership fixtures only. They create no runtime or native window,
/// and simulated complete() calls do not prove Runtime's checked adoption,
/// actual layout, retained state, input, or accessibility integration.
@MainActor
final class RetainedLazyListRuntimeAdapterTests: XCTestCase {
    private typealias Adapter = RetainedLazyListRuntimeAdapter
    private typealias Source = RetainedLazyListDataSource<Int, [ViewNode]>

    func testConfigurationRequiresFiniteEstimatesAndPositiveCaps() async throws {
        let source = try makeSource([0])
        for estimate in [0, -1, Double.infinity, Double.nan] {
            XCTAssertNil(
                Adapter(
                    provider: source, estimatedExtent: estimate, prefetchExtent: 0,
                    maximumMountedRecords: 1, maximumMountedLeaves: 1, maximumProtectedRecords: 1))
        }
        for prefetch in [-1, Double.infinity, Double.nan] {
            XCTAssertNil(
                Adapter(
                    provider: source, estimatedExtent: 1, prefetchExtent: prefetch,
                    maximumMountedRecords: 1, maximumMountedLeaves: 1, maximumProtectedRecords: 1))
        }
        for caps in [(0, 1, 1), (1, 0, 1), (1, 1, 0), (-1, 1, 1)] {
            XCTAssertNil(
                Adapter(
                    provider: source, estimatedExtent: 1, prefetchExtent: 0,
                    maximumMountedRecords: caps.0, maximumMountedLeaves: caps.1,
                    maximumProtectedRecords: caps.2))
        }
        XCTAssertNotNil(
            Adapter(
                provider: source, estimatedExtent: 1, prefetchExtent: 0,
                maximumMountedRecords: 1, maximumMountedLeaves: 1, maximumProtectedRecords: 1))
    }

    func testViewportRejectsNonfiniteInputsAndAllowsEmptyOverscroll() async throws {
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        XCTAssertNotNil(Adapter.Viewport(context: context, offset: -10, extent: 0))
        for offset in [Double.infinity, -.infinity, .nan] {
            XCTAssertNil(Adapter.Viewport(context: context, offset: offset, extent: 20))
        }
        for extent in [-1, Double.infinity, Double.nan] {
            XCTAssertNil(Adapter.Viewport(context: context, offset: 0, extent: extent))
        }
    }

    func testConstructionAndLayoutPlanningDoNotReadProviderOrCallFactories() async throws {
        var calls = 0
        let source = try makeSource(Array(0..<1000)) { _ in
            calls += 1
            return [ViewNode()]
        }
        let probe = AdapterProviderProbe(source)
        let adapter = try makeAdapter(probe)
        let viewport = try viewport()
        for _ in 0..<5 {
            let plan = adapter.layoutPlan(viewport: viewport)
            XCTAssertTrue(plan.requiresResolution)
            XCTAssertTrue(plan.placements.isEmpty)
        }
        XCTAssertEqual(probe.metadataReads, 0)
        XCTAssertEqual(probe.requestReads, 0)
        XCTAssertEqual(probe.currentReads, 0)
        XCTAssertEqual(probe.materializations, 0)
        XCTAssertEqual(calls, 0)
    }

    func testLargeMetadataSetsBuildOnlyViewportAndPrefetchRecords() async throws {
        for count in [100, 1000, 10_000] {
            var calls: [Int] = []
            let source = try makeSource(Array(0..<count)) { value in
                calls.append(value)
                return [ViewNode()]
            }
            let adapter = try makeAdapter(source, prefetch: 20)
            let viewport = try viewport(extent: 40)
            let candidate = try ready(adapter, viewport: viewport)
            XCTAssertEqual(calls, [0, 1, 2])
            XCTAssertEqual(candidate.recordLeafCounts, [1, 1, 1])
            XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
            _ = try measure(adapter, viewport: viewport) { _ in 20 }
            let plan = adapter.layoutPlan(viewport: viewport)
            XCTAssertEqual(adapter.logicalRecordCount, count)
            XCTAssertEqual(adapter.mountedRecordCount, 3)
            XCTAssertEqual(adapter.mountedLeafCount, 3)
            XCTAssertEqual(plan.contentExtent, Double(count) * 20)
            XCTAssertEqual(plan.placements.count, 3)
            XCTAssertTrue(plan.hasLogicalOmissions)
            XCTAssertFalse(plan.requiresResolution, "Unknown offscreen heights are allowed")
            XCTAssertFalse(adapter.hasUnresolvedWork)
        }
    }

    func testCachedPlansNeverMaterializeAfterViewportChanges() async throws {
        var calls = 0
        let source = try makeSource(Array(0..<100)) { _ in
            calls += 1
            return [ViewNode()]
        }
        let probe = AdapterProviderProbe(source)
        let adapter = try makeAdapter(probe)
        let initial = try viewport(extent: 40)
        try adoptAndMeasure(adapter, viewport: initial)
        let readCount = probe.metadataReads
        let currentCount = probe.currentReads
        let materializations = probe.materializations
        for offset in [0.0, 20, 200, 600, 1500] {
            _ = adapter.layoutPlan(viewport: try viewport(offset: offset, extent: 40))
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(probe.metadataReads, readCount)
        XCTAssertEqual(probe.currentReads, currentCount)
        XCTAssertEqual(probe.materializations, materializations)
        XCTAssertTrue(adapter.hasUnresolvedWork)
    }

    func testZeroAndMultipleLeavesKeepTheirCardinalityWithoutGrouping() async throws {
        let source = try makeSource([0, 2]) { value in (0..<value).map { _ in ViewNode() } }
        let adapter = try makeAdapter(source)
        let viewport = try viewport(extent: 40)
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertEqual(candidate.recordLeafCounts, [0, 2])
        XCTAssertEqual(candidate.children.count, 2)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let unknown = adapter.layoutPlan(viewport: viewport)
        XCTAssertEqual(unknown.contentExtent, 20)
        XCTAssertEqual(unknown.placements.map(\.originY), [0, 0])
        XCTAssertTrue(unknown.placements.allSatisfy { $0.extent == nil })
        XCTAssertTrue(unknown.requiresResolution)
        _ = try measure(adapter, viewport: viewport) { $0.leafIndex == 0 ? 10 : 30 }
        let measured = adapter.layoutPlan(viewport: viewport)
        XCTAssertEqual(adapter.logicalRecordCount, 2)
        XCTAssertEqual(adapter.mountedRecordCount, 1)
        XCTAssertEqual(adapter.mountedLeafCount, 2)
        XCTAssertEqual(measured.contentExtent, 40)
        XCTAssertEqual(measured.placements.map(\.originY), [0, 10])
        XCTAssertEqual(measured.placements.compactMap(\.extent), [10, 30])
        XCTAssertFalse(measured.requiresResolution)
    }

    func testObsoleteEmptyFactoryDoesNotCertifyZeroExtent() async throws {
        let source = Source()
        weak var weakSource: Source? = source
        var calls = 0
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { _ in
                calls += 1
                weakSource?.close()
                return []
            })
        let adapter = try makeAdapter(source)
        let viewport = try viewport(extent: 20)
        guard
            case .obsolete = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: try budget(1))
        else { return XCTFail("A closed source cannot certify an empty output") }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(adapter.mountedRecordCount, 0)
        XCTAssertEqual(adapter.layoutPlan(viewport: viewport).contentExtent, 20)
        XCTAssertTrue(adapter.hasUnresolvedWork)
    }

    func testSmallElementBudgetsMakePartialProgressAcrossAdoptions() async throws {
        var calls: [Int] = []
        let source = try makeSource([0, 1, 2]) { value in
            calls.append(value)
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source)
        let viewport = try viewport(extent: 60)
        for expectedCount in 1...3 {
            let candidate = try ready(adapter, viewport: viewport, elements: 1)
            XCTAssertEqual(candidate.children.count, expectedCount)
            XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
            _ = try measure(adapter, viewport: viewport) { _ in 20 }
            XCTAssertEqual(adapter.mountedRecordCount, expectedCount)
            XCTAssertEqual(adapter.hasUnresolvedWork, expectedCount != 3)
        }
        XCTAssertEqual(calls, [0, 1, 2])
    }

    func testTwoAdaptersShareElementBudgetWithoutConsumingRuntimeRounds() async throws {
        var firstCalls = 0
        var secondCalls = 0
        let first = try makeSource([0, 1]) { _ in
            firstCalls += 1
            return [ViewNode()]
        }
        let second = try makeSource([0, 1]) { _ in
            secondCalls += 1
            return [ViewNode()]
        }
        let firstAdapter = try makeAdapter(first)
        let secondAdapter = try makeAdapter(second)
        let shared = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 3, roundLimit: 2))
        let viewport = try viewport(extent: 40)
        guard
            case .ready(let firstCandidate) = firstAdapter.prepare(
                viewport: viewport, protectedRoots: [], budget: shared),
            case .ready(let secondCandidate) = secondAdapter.prepare(
                viewport: viewport, protectedRoots: [], budget: shared)
        else { return XCTFail("Both adapters should return their bounded completed candidates") }
        XCTAssertEqual(firstCandidate.children.count, 2)
        XCTAssertEqual(secondCandidate.children.count, 1)
        XCTAssertEqual(firstCalls, 2)
        XCTAssertEqual(secondCalls, 1)
        XCTAssertEqual(shared.remainingElements, 0)
        XCTAssertEqual(shared.remainingRounds, 2)
    }

    func testExhaustedBudgetKeepsUnknownRowsPendingWithoutFactories() async throws {
        var calls = 0
        let source = try makeSource([0]) { _ in
            calls += 1
            return []
        }
        let adapter = try makeAdapter(source)
        let viewport = try viewport(extent: 20)
        guard
            case .workRemaining = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: try budget(0))
        else { return XCTFail("No element may be examined with an exhausted budget") }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(adapter.layoutPlan(viewport: viewport).contentExtent, 20)
        XCTAssertTrue(adapter.hasUnresolvedWork)
    }

    func testEmptyDataCanCompleteWithoutSpendingElementBudget() async throws {
        let adapter = try makeAdapter(makeSource([]))
        let viewport = try viewport(extent: 40)
        let candidate = try ready(adapter, viewport: viewport, elements: 0)
        XCTAssertEqual(candidate.recordLeafCounts, [])
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: []))
        let plan = adapter.layoutPlan(viewport: viewport)
        XCTAssertEqual(plan.contentExtent, 0)
        XCTAssertEqual(plan.placements.count, 0)
        XCTAssertFalse(plan.requiresResolution)
        XCTAssertFalse(plan.hasLogicalOmissions)
    }

    func testCandidateCompletesAtMostOnceAndNextPreparationRevokesIt() async throws {
        let adapter = try makeAdapter(makeSource([0]))
        let viewport = try viewport(extent: 20)
        let first = try ready(adapter, viewport: viewport)
        XCTAssertTrue(first.isCurrent)
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        XCTAssertFalse(adapter.complete(candidate: first, adoptedChildren: first.children))
        _ = try measure(adapter, viewport: viewport) { _ in 20 }
        guard
            case .unchanged = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: try budget(0))
        else { return XCTFail("The already measured current window needs no adoption") }
        XCTAssertFalse(first.isCurrent)
        XCTAssertFalse(adapter.hasUnresolvedWork)
    }

    func testASecondUnadoptedCandidateRevokesTheFirstNativeProof() async throws {
        let adapter = try makeAdapter(makeSource([0]))
        let viewport = try viewport(extent: 20)
        let first = try ready(adapter, viewport: viewport)
        let second = try ready(adapter, viewport: viewport)
        XCTAssertFalse(first.isCurrent)
        XCTAssertTrue(second.isCurrent)
        XCTAssertFalse(adapter.complete(candidate: first, adoptedChildren: first.children))
    }

    func testClosingTheSourceRevokesCandidateWithoutAProviderCall() async throws {
        let source = try makeSource([0])
        let probe = AdapterProviderProbe(source)
        let adapter = try makeAdapter(probe)
        let candidate = try ready(adapter, viewport: viewport(extent: 20))
        let reads = probe.currentReads
        source.close()
        XCTAssertFalse(candidate.isCurrent)
        XCTAssertFalse(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(probe.currentReads, reads)
        XCTAssertEqual(adapter.mountedLeafCount, 0)
    }

    func testCompletionRejectsWrongCountOrDuplicateRetainedLeaves() async throws {
        let adapter = try makeAdapter(makeSource([0]) { _ in [ViewNode(), ViewNode()] })
        let candidate = try ready(adapter, viewport: viewport(extent: 20))
        XCTAssertFalse(adapter.complete(candidate: candidate, adoptedChildren: []))
        let repeated = ViewNode()
        XCTAssertFalse(adapter.complete(candidate: candidate, adoptedChildren: [repeated, repeated]))
        XCTAssertTrue(candidate.isCurrent)
        XCTAssertEqual(adapter.mountedLeafCount, 0)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
    }

    func testOneAdapterCannotCompleteOrConsumeAnotherAdaptersCandidate() async throws {
        let source = try makeSource([0, 1])
        let first = try makeAdapter(source, records: 2, leaves: 2)
        let second = try makeAdapter(source, records: 1, leaves: 1)
        let candidate = try ready(first, viewport: viewport(extent: 40))
        XCTAssertFalse(second.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(second.mountedRecordCount, 0)
        XCTAssertTrue(candidate.isCurrent)
        XCTAssertTrue(first.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(first.mountedRecordCount, 2)
    }

    func testNativeRevocationDoesNotReadProviderOrReleaseMountedNodes() async throws {
        let source = try makeSource([0])
        let probe = AdapterProviderProbe(source)
        let adapter = try makeAdapter(probe)
        let viewport = try viewport(extent: 20)
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let metadataReads = probe.metadataReads
        let requestReads = probe.requestReads
        let currentReads = probe.currentReads
        adapter.revokePendingCandidate()
        XCTAssertFalse(candidate.isCurrent)
        XCTAssertEqual(adapter.mountedRecordCount, 1)
        XCTAssertEqual(adapter.mountedLeafCount, 1)
        XCTAssertEqual(probe.metadataReads, metadataReads)
        XCTAssertEqual(probe.requestReads, requestReads)
        XCTAssertEqual(probe.currentReads, currentReads)
        XCTAssertTrue(adapter.hasUnresolvedWork)
    }

    func testReleaseMountedRecordsDropsItsNodeOwnership() async throws {
        weak var leaf: ViewNode?
        let source = try makeSource([0]) { _ in
            let node = ViewNode()
            leaf = node
            return [node]
        }
        let adapter = try makeAdapter(source)
        try adoptAndMeasure(adapter, viewport: viewport(extent: 20))
        XCTAssertNotNil(leaf)
        adapter.releaseMountedRecords()
        XCTAssertEqual(adapter.mountedRecordCount, 0)
        XCTAssertEqual(adapter.mountedLeafCount, 0)
        XCTAssertNil(leaf)
        XCTAssertTrue(adapter.hasUnresolvedWork)
    }

    func testCandidateDoesNotKeepAdapterOrProviderAlive() async throws {
        var source: Source? = try makeSource([0])
        weak var weakSource: Source? = source
        var adapter: Adapter? = try makeAdapter(XCTUnwrap(source))
        weak var weakAdapter: Adapter? = adapter
        let candidate = try ready(XCTUnwrap(adapter), viewport: viewport(extent: 20))
        source = nil
        adapter = nil
        XCTAssertNil(weakAdapter)
        XCTAssertNil(weakSource)
        XCTAssertFalse(candidate.isCurrent)
    }

    func testAttachmentClaimRejectsAnotherLiveContainerAndForeignRelease() async throws {
        let adapter = try makeAdapter(makeSource([0]))
        let first = ViewNode()
        let second = ViewNode()
        XCTAssertTrue(adapter.claimAttachment(to: first))
        XCTAssertTrue(adapter.claimAttachment(to: first))
        let candidate = try ready(adapter, viewport: viewport(extent: 20))
        XCTAssertFalse(adapter.claimAttachment(to: second))
        XCTAssertFalse(adapter.releaseAttachment(from: second))
        XCTAssertTrue(candidate.isCurrent)
        XCTAssertTrue(adapter.ownsAttachment(first))
        XCTAssertFalse(adapter.ownsAttachment(second))
        XCTAssertTrue(adapter.releaseAttachment(from: first))
        XCTAssertFalse(candidate.isCurrent)
        XCTAssertTrue(adapter.claimAttachment(to: second))
        XCTAssertTrue(adapter.ownsAttachment(second))
    }

    func testAttachmentClaimIsWeakAndAReplacementRevokesPendingWork() async throws {
        let adapter = try makeAdapter(makeSource([0]))
        var first: ViewNode? = ViewNode()
        weak var observedFirst: ViewNode? = first
        XCTAssertTrue(adapter.claimAttachment(to: try XCTUnwrap(first)))
        let candidate = try ready(adapter, viewport: viewport(extent: 20))
        first = nil
        XCTAssertNil(observedFirst)
        let replacement = ViewNode()
        XCTAssertTrue(adapter.claimAttachment(to: replacement))
        XCTAssertFalse(candidate.isCurrent)
        XCTAssertTrue(adapter.ownsAttachment(replacement))
    }

    func testAttachmentReleaseDoesNotPerformMountedPayloadCleanup() async throws {
        let adapter = try makeAdapter(makeSource([0]))
        let container = ViewNode()
        XCTAssertTrue(adapter.claimAttachment(to: container))
        try adoptAndMeasure(adapter, viewport: viewport(extent: 20))
        XCTAssertTrue(adapter.releaseAttachment(from: container))
        XCTAssertEqual(adapter.mountedLeafCount, 1)
        adapter.releaseMountedRecords()
        XCTAssertEqual(adapter.mountedLeafCount, 0)
    }

    func testNewSourceGenerationRebuildsTheSameVisibleKeys() async throws {
        var calls = 0
        let source = try makeSource([0, 1]) { _ in
            calls += 1
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source)
        let viewport = try viewport(extent: 40)
        let first = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        _ = try measure(adapter, viewport: viewport) { _ in 20 }
        XCTAssertTrue(
            source.replaceData([0, 1], id: \.self) { _ in
                calls += 1
                return [ViewNode()]
            })
        XCTAssertFalse(first.isCurrent)
        XCTAssertTrue(adapter.hasUnresolvedWork)
        let second = try ready(adapter, viewport: viewport)
        XCTAssertEqual(calls, 4)
        XCTAssertFalse(second.children[0] === first.children[0])
        // A checked reconciler can reuse the old retained nodes.
        XCTAssertTrue(adapter.complete(candidate: second, adoptedChildren: first.children))
        XCTAssertTrue(adapter.layoutPlan(viewport: viewport).placements.allSatisfy { $0.extent == nil })
        _ = try measure(adapter, viewport: viewport) { _ in 30 }
        XCTAssertTrue(adapter.layoutPlan(viewport: viewport).placements[0].node === first.children[0])
        XCTAssertEqual(adapter.layoutPlan(viewport: viewport).contentExtent, 60)
    }

    func testAnchorWrappersPreserveTypedTokenAcrossReorder() async throws {
        let source = try makeSource([0, 1, 2, 3])
        let adapter = try makeAdapter(source, prefetch: 100)
        let viewport = try viewport(offset: 15, extent: 10)
        let rows = try XCTUnwrap(source.metadata).rows
        let heights = Dictionary(
            uniqueKeysWithValues: rows.enumerated().map { ($0.element.token, Double($0.offset + 1) * 10) })
        let first = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        _ = try measure(adapter, viewport: viewport) { heights[$0.token, default: 0] }
        let anchor = try XCTUnwrap(adapter.captureAnchor(at: 15))
        XCTAssertEqual(anchor.token, rows[1].token)
        XCTAssertTrue(source.replaceData([2, 0, 1, 3], id: \.self) { _ in [ViewNode()] })
        let second = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: second, adoptedChildren: second.children))
        _ = try measure(adapter, viewport: viewport) { heights[$0.token, default: 0] }
        XCTAssertEqual(adapter.resolveAnchor(anchor, viewportExtent: 10), 45)
        XCTAssertTrue(source.replaceData([2, 0, 3], id: \.self) { _ in [ViewNode()] })
        let third = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: third, adoptedChildren: third.children))
        XCTAssertNil(adapter.resolveAnchor(anchor, viewportExtent: 10))
    }

    func testContextChangeCannotReuseOldLeafMeasurements() async throws {
        var calls = 0
        let source = try makeSource([0]) { _ in
            calls += 1
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source)
        let oldViewport = try viewport(extent: 20, width: 100)
        try adoptAndMeasure(adapter, viewport: oldViewport)
        let changed = try viewport(extent: 20, width: 80)
        XCTAssertTrue(adapter.layoutPlan(viewport: changed).requiresResolution)
        XCTAssertEqual(calls, 1)
        let candidate = try ready(adapter, viewport: changed)
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let placement = try XCTUnwrap(adapter.layoutPlan(viewport: changed).placements.first)
        XCTAssertNil(placement.extent)
        XCTAssertNil(
            adapter.recordMeasurements(
                [.init(token: placement.token, leafIndex: 0, node: placement.node, extent: 10)],
                viewport: oldViewport))
        _ = try measure(adapter, viewport: changed) { _ in 10 }
        XCTAssertEqual(adapter.layoutPlan(viewport: changed).contentExtent, 10)
    }

    func testMetadataGetterReentryRevokesPreparationBeforeFactories() async throws {
        var calls = 0
        let source = try makeSource([0]) { _ in
            calls += 1
            return [ViewNode()]
        }
        let probe = AdapterProviderProbe(source)
        let adapter = try makeAdapter(probe)
        probe.onMetadata = { [weak adapter] in adapter?.revokePendingCandidate() }
        guard
            case .obsolete = adapter.prepare(
                viewport: try viewport(extent: 20), protectedRoots: [], budget: try budget(1))
        else { return XCTFail("Metadata cleanup/callouts must precede native admission checks") }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(adapter.mountedLeafCount, 0)
    }

    func testRequestGetterReplacementCannotBuildTheOldRequest() async throws {
        var calls = 0
        let source = try makeSource([0]) { _ in
            calls += 1
            return [ViewNode()]
        }
        let probe = AdapterProviderProbe(source)
        let adapter = try makeAdapter(probe)
        probe.onRequest = { [weak source] in
            _ = source?.replaceData([1], id: \.self) { _ in [ViewNode()] }
        }
        guard
            case .obsolete = adapter.prepare(
                viewport: try viewport(extent: 20), protectedRoots: [], budget: try budget(1))
        else { return XCTFail("A request callback cannot preserve a revoked source generation") }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(probe.materializations, 0)
    }

    func testProviderCurrentnessCalloutCannotBypassNativeAdapterRevocation() async throws {
        let source = try makeSource([0])
        let probe = AdapterProviderProbe(source)
        let adapter = try makeAdapter(probe)
        probe.onCurrent = { [weak adapter] in adapter?.revokePendingCandidate() }
        guard
            case .obsolete = adapter.prepare(
                viewport: try viewport(extent: 20), protectedRoots: [], budget: try budget(1))
        else { return XCTFail("The true protocol answer is not the final admission proof") }
        XCTAssertEqual(probe.materializations, 0)
        XCTAssertTrue(adapter.hasUnresolvedWork)
    }

    func testMaterializationCalloutDiscardsAnObsoleteCandidate() async throws {
        weak var produced: ViewNode?
        let source = try makeSource([0]) { _ in
            let node = ViewNode()
            produced = node
            return [node]
        }
        let probe = AdapterProviderProbe(source)
        let adapter = try makeAdapter(probe)
        probe.onMaterialize = { [weak adapter] in adapter?.revokePendingCandidate() }
        guard
            case .obsolete = adapter.prepare(
                viewport: try viewport(extent: 20), protectedRoots: [], budget: try budget(1))
        else { return XCTFail("A factory result can lose authority before returning to Runtime") }
        XCTAssertNil(produced)
        XCTAssertEqual(adapter.mountedLeafCount, 0)
    }

    func testFactoryReentryStopsTheOuterAttemptWithoutRecursiveConstruction() async throws {
        let source = Source()
        var calls = 0
        var nestedWasObsolete = false
        weak var weakAdapter: Adapter?
        let viewport = try viewport(extent: 20)
        let nestedBudget = try budget(1)
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { _ in
                calls += 1
                if let adapter = weakAdapter,
                    case .obsolete = adapter.prepare(
                        viewport: viewport, protectedRoots: [], budget: nestedBudget)
                {
                    nestedWasObsolete = true
                }
                return [ViewNode()]
            })
        let adapter = try makeAdapter(source)
        weakAdapter = adapter
        guard
            case .obsolete = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: try budget(1))
        else { return XCTFail("Reentrant preparation must revoke the outer native attempt") }
        XCTAssertTrue(nestedWasObsolete)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(nestedBudget.remainingElements, 1)
        XCTAssertEqual(adapter.mountedLeafCount, 0)
    }

    func testOversizedFactoryOutputIsRejectedWithoutTruncation() async throws {
        var calls = 0
        let source = try makeSource([0]) { _ in
            calls += 1
            return [ViewNode(), ViewNode(), ViewNode()]
        }
        let adapter = try makeAdapter(source, leaves: 2)
        guard
            case .unsupported = adapter.prepare(
                viewport: try viewport(extent: 20), protectedRoots: [], budget: try budget(1))
        else { return XCTFail("A three-leaf row cannot silently become a two-leaf row") }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(adapter.mountedLeafCount, 0)
        XCTAssertTrue(adapter.hasUnresolvedWork)
    }

    func testCappedEstimatedPrefixCanMeasureBeforeDeclaringTheWindowComplete() async throws {
        var calls = 0
        let source = try makeSource(Array(0..<10)) { _ in
            calls += 1
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source, estimate: 1, records: 2)
        let viewport = try viewport(extent: 20)
        let first = try ready(adapter, viewport: viewport)
        XCTAssertEqual(first.children.count, 2)
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        XCTAssertTrue(adapter.hasUnresolvedWork)
        _ = try measure(adapter, viewport: viewport) { _ in 20 }
        let second = try ready(adapter, viewport: viewport)
        XCTAssertEqual(second.children.count, 1)
        XCTAssertTrue(adapter.complete(candidate: second, adoptedChildren: second.children))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(adapter.mountedRecordCount, 1)
        XCTAssertFalse(adapter.hasUnresolvedWork)
    }

    func testActuallyDenseWindowStaysUnsettledAtTheRecordCap() async throws {
        var calls = 0
        let source = try makeSource(Array(0..<10)) { _ in
            calls += 1
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source, estimate: 1, records: 2)
        let viewport = try viewport(extent: 10)
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        _ = try measure(adapter, viewport: viewport) { _ in 1 }
        guard
            case .unchanged = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: try budget(10))
        else { return XCTFail("The same capped prefix needs no repeated construction") }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        XCTAssertTrue(adapter.hasUnresolvedWork)
    }

    func testProtectedCohortSurvivesOffscreenWithinTheSameCaps() async throws {
        var calls: [Int] = []
        let source = try makeSource(Array(0..<5)) { value in
            calls.append(value)
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source, records: 2, leaves: 2, protected: 1)
        let initial = try viewport(extent: 20)
        let first = try ready(adapter, viewport: initial)
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        _ = try measure(adapter, viewport: initial) { _ in 20 }
        let moved = try viewport(offset: 80, extent: 20)
        let second = try ready(adapter, viewport: moved, protectedNodes: first.children)
        XCTAssertEqual(second.children.count, 2)
        XCTAssertTrue(second.children[0] === first.children[0])
        XCTAssertTrue(adapter.complete(candidate: second, adoptedChildren: second.children))
        _ = try measure(adapter, viewport: moved) { _ in 20 }
        XCTAssertEqual(adapter.layoutPlan(viewport: moved).placements.map(\.originY), [0, 80])
        XCTAssertFalse(adapter.hasUnresolvedWork)
        let third = try ready(adapter, viewport: moved)
        XCTAssertTrue(adapter.complete(candidate: third, adoptedChildren: third.children))
        XCTAssertEqual(adapter.mountedRecordCount, 1)
        XCTAssertEqual(calls, [0, 4])
    }

    func testProtectedRecordLimitCannotGrowIntoAnUnboundedAllowance() async throws {
        var calls = 0
        let source = try makeSource(Array(0..<6)) { _ in
            calls += 1
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source, records: 3, leaves: 3, protected: 1)
        let first = try ready(adapter, viewport: viewport(extent: 40))
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        guard
            case .workRemaining = adapter.prepare(
                viewport: try viewport(offset: 100, extent: 20),
                protectedRoots: Set(first.children.map(ObjectIdentifier.init)), budget: try budget(10))
        else { return XCTFail("Two protected records exceed the explicit allowance of one") }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        XCTAssertTrue(adapter.hasUnresolvedWork)
    }

    func testProtectedAndVisibleRecordsMustFitTheSameTotalLimit() async throws {
        var calls = 0
        let source = try makeSource(Array(0..<6)) { _ in
            calls += 1
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source, records: 2, leaves: 2, protected: 1)
        let first = try ready(adapter, viewport: viewport(extent: 20))
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        let moved = try viewport(offset: 80, extent: 40)
        let second = try ready(adapter, viewport: moved, protectedNodes: first.children)
        XCTAssertEqual(second.children.count, 2)
        XCTAssertTrue(second.children[0] === first.children[0])
        XCTAssertTrue(adapter.complete(candidate: second, adoptedChildren: second.children))
        _ = try measure(adapter, viewport: moved) { _ in 20 }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        XCTAssertTrue(adapter.hasUnresolvedWork, "One visible row still cannot fit beside the owner")
    }

    func testProtectedRefreshBuildsTheOwnerBeforeAnOrdinarySmallBudgetPrefix() async throws {
        var calls: [Int] = []
        let values = Array(0..<11)
        let source = try makeSource(values) { value in
            calls.append(value)
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source, records: 3, leaves: 3, protected: 1)
        let initial = try viewport(offset: 200, extent: 20)
        let first = try ready(adapter, viewport: initial)
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        _ = try measure(adapter, viewport: initial) { _ in 20 }
        XCTAssertTrue(
            source.replaceData(values, id: \.self) { value in
                calls.append(value)
                return [ViewNode()]
            })
        calls = []
        let moved = try viewport(extent: 40)
        let owner = try ready(adapter, viewport: moved, elements: 1, protectedNodes: first.children)
        XCTAssertEqual(owner.recordLeafCounts, [1])
        XCTAssertEqual(calls, [10])
        XCTAssertTrue(adapter.complete(candidate: owner, adoptedChildren: first.children))
        _ = try measure(adapter, viewport: moved) { _ in 20 }
        for _ in 0..<2 {
            let next = try ready(adapter, viewport: moved, elements: 1, protectedNodes: first.children)
            XCTAssertTrue(adapter.complete(candidate: next, adoptedChildren: next.children))
            _ = try measure(adapter, viewport: moved) { _ in 20 }
        }
        XCTAssertEqual(calls, [10, 0, 1])
        XCTAssertEqual(adapter.mountedRecordCount, 3)
        XCTAssertFalse(adapter.hasUnresolvedWork)
    }

    func testProtectedRecordsAlreadyInWindowDoNotWasteReservedCapacity() async throws {
        let adapter = try makeAdapter(makeSource([0, 1, 2, 3]), records: 4, leaves: 4, protected: 1)
        let first = try ready(adapter, viewport: viewport(extent: 20))
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        let full = try viewport(extent: 80)
        let candidate = try ready(adapter, viewport: full, protectedNodes: first.children)
        XCTAssertEqual(candidate.children.count, 4)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        _ = try measure(adapter, viewport: full) { _ in 20 }
        XCTAssertFalse(adapter.hasUnresolvedWork)
    }

    func testWholeFreshProtectedCohortMustFitBeforeAnyAdoption() async throws {
        let values = Array(0..<10)
        let source = try makeSource(values)
        let adapter = try makeAdapter(source, records: 3, leaves: 3, protected: 2)
        let first = try ready(adapter, viewport: viewport(offset: 160, extent: 40))
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        XCTAssertTrue(source.replaceData(values, id: \.self) { _ in [ViewNode()] })
        let moved = try viewport(extent: 20)
        guard
            case .workRemaining = adapter.prepare(
                viewport: moved, protectedRoots: Set(first.children.map(ObjectIdentifier.init)),
                budget: try budget(1))
        else { return XCTFail("Abandoned epochs cannot supply a staged half of an owner cohort") }
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        XCTAssertTrue(adapter.hasUnresolvedWork)
        let sufficient = try ready(adapter, viewport: moved, elements: 2, protectedNodes: first.children)
        XCTAssertEqual(sufficient.children.count, 2)
        XCTAssertTrue(adapter.complete(candidate: sufficient, adoptedChildren: first.children))
    }

    func testVirtualizedDeparturesExcludeDeletionAndSameRecordLeafReplacement() async throws {
        let source = try makeSource([0, 1, 2])
        let adapter = try makeAdapter(source)
        let first = try ready(adapter, viewport: viewport(extent: 40))
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        let scrolled = try ready(adapter, viewport: viewport(offset: 40, extent: 20))
        XCTAssertEqual(
            scrolled.virtualizedDepartureRoots, Set(first.children.map(ObjectIdentifier.init)))
        XCTAssertTrue(
            source.replaceData([0, 2], id: \.self) { value in
                value == 0 ? [] : [ViewNode()]
            })
        let changed = try ready(adapter, viewport: viewport(extent: 40))
        XCTAssertEqual(changed.recordLeafCounts, [0, 1])
        XCTAssertTrue(changed.virtualizedDepartureRoots.isEmpty)
    }

    func testUnknownProtectedRootIsNotSilentlyIgnored() async throws {
        let adapter = try makeAdapter(makeSource([0]))
        let unrelated = ViewNode()
        guard
            case .unsupported = adapter.prepare(
                viewport: try viewport(extent: 20),
                protectedRoots: [ObjectIdentifier(unrelated)], budget: try budget(1))
        else { return XCTFail("Runtime must identify adopted top-level leaf roots") }
        XCTAssertEqual(adapter.mountedLeafCount, 0)
    }

    func testMeasurementsReferToActualAdoptedLeavesInsteadOfFactoryNodes() async throws {
        let adapter = try makeAdapter(makeSource([0]) { _ in [ViewNode(), ViewNode()] })
        let viewport = try viewport(extent: 20)
        let candidate = try ready(adapter, viewport: viewport)
        let adopted = [ViewNode(), ViewNode()]
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: adopted))
        let plan = adapter.layoutPlan(viewport: viewport)
        XCTAssertTrue(plan.placements[0].node === adopted[0])
        XCTAssertTrue(plan.placements[1].node === adopted[1])
        XCTAssertNil(
            adapter.recordMeasurements(
                plan.placements.enumerated().map {
                    .init(
                        token: $0.element.token, leafIndex: $0.offset,
                        node: candidate.children[$0.offset], extent: 10)
                }, viewport: viewport))
        _ = try measure(adapter, viewport: viewport) { _ in 10 }
        XCTAssertEqual(adapter.layoutPlan(viewport: viewport).contentExtent, 20)
    }

    func testMeasurementsRejectPartialDuplicateAndNonfiniteLeafBatches() async throws {
        let adapter = try makeAdapter(makeSource([0]) { _ in [ViewNode(), ViewNode()] })
        let viewport = try viewport(extent: 40)
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        _ = try measure(adapter, viewport: viewport) { _ in 20 }
        let placements = adapter.layoutPlan(viewport: viewport).placements
        let first = Adapter.Measurement(token: placements[0].token, leafIndex: 0, node: placements[0].node, extent: 10)
        XCTAssertNil(adapter.recordMeasurements([first], viewport: viewport))
        XCTAssertNil(adapter.recordMeasurements([first, first], viewport: viewport))
        for invalid in [-1, Double.infinity, Double.nan] {
            let second = Adapter.Measurement(
                token: placements[1].token, leafIndex: 1, node: placements[1].node, extent: invalid)
            XCTAssertNil(adapter.recordMeasurements([first, second], viewport: viewport))
        }
        let final = adapter.layoutPlan(viewport: viewport)
        XCTAssertEqual(final.contentExtent, 40)
        XCTAssertEqual(final.placements.compactMap(\.extent), [20, 20])
    }

    func testAggregateOverflowRollsBackAllEarlierPointUpdates() async throws {
        let adapter = try makeAdapter(makeSource([0, 1, 2]), estimate: 1)
        let viewport = try viewport(extent: 3)
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        _ = try measure(adapter, viewport: viewport) { _ in 1 }
        let placements = adapter.layoutPlan(viewport: viewport).placements
        let huge = Double.greatestFiniteMagnitude * 0.75
        let extents = [huge, huge, 0.0]
        let invalid = placements.enumerated().map {
            Adapter.Measurement(
                token: $0.element.token, leafIndex: $0.element.leafIndex,
                node: $0.element.node, extent: extents[$0.offset])
        }
        XCTAssertNil(adapter.recordMeasurements(invalid, viewport: viewport))
        let unchanged = adapter.layoutPlan(viewport: viewport)
        XCTAssertEqual(unchanged.contentExtent, 3)
        XCTAssertEqual(unchanged.placements.map(\.originY), [0, 1, 2])
        XCTAssertEqual(unchanged.placements.compactMap(\.extent), [1, 1, 1])
    }

    func testBatchAppliesDecreasesBeforeIncreasesToAvoidTransientOverflow() async throws {
        let adapter = try makeAdapter(makeSource([0, 1]), estimate: 1)
        let viewport = try viewport(extent: 2)
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let huge = Double.greatestFiniteMagnitude * 0.75
        let tokens = adapter.layoutPlan(viewport: viewport).placements.map(\.token)
        _ = try measure(adapter, viewport: viewport) { $0.token == tokens[0] ? huge : 1 }
        _ = try measure(adapter, viewport: viewport) { $0.token == tokens[0] ? 1 : huge }
        let plan = adapter.layoutPlan(viewport: viewport)
        XCTAssertEqual(plan.contentExtent, huge)
        XCTAssertEqual(plan.placements.compactMap(\.extent), [1, huge])
    }

    func testLeafRedistributionChangesPlacementEvenWhenRecordTotalDoesNot() async throws {
        let adapter = try makeAdapter(makeSource([0]) { _ in [ViewNode(), ViewNode()] })
        let viewport = try viewport(extent: 40)
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        _ = try measure(adapter, viewport: viewport) { $0.leafIndex == 0 ? 10 : 30 }
        let changed = try measure(adapter, viewport: viewport) { _ in 20 }
        XCTAssertTrue(changed.extentChanged)
        XCTAssertEqual(adapter.layoutPlan(viewport: viewport).contentExtent, 40)
        XCTAssertEqual(adapter.layoutPlan(viewport: viewport).placements.map(\.originY), [0, 20])
    }

    func testLocalLeafOffsetsPreserveRepresentableProgressAfterLargePrefix() async throws {
        let source = try makeSource([0, 1]) { value in
            (0..<(value == 0 ? 1 : 4)).map { _ in ViewNode() }
        }
        let adapter = try makeAdapter(source, estimate: 1)
        let viewport = try viewport(extent: 2)
        let rows = try XCTUnwrap(source.metadata).rows
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let large = 9_007_199_254_740_992.0
        _ = try measure(adapter, viewport: viewport) { $0.token == rows[0].token ? large : 1 }
        let plan = adapter.layoutPlan(viewport: viewport)
        let trailing = plan.placements.filter { $0.token == rows[1].token }
        XCTAssertEqual(trailing.map(\.originY), [large, large, large + 2, large + 4])
        XCTAssertEqual(trailing.compactMap(\.extent), [1, 1, 1, 1])
        XCTAssertEqual(plan.contentExtent, large + 4)
    }

    func testMeasurementBatchReturnsClampedKeyedAnchorAdjustment() async throws {
        let source = try makeSource([0, 1, 2])
        let adapter = try makeAdapter(source, prefetch: 100)
        let viewport = try viewport(offset: 25, extent: 10)
        let rows = try XCTUnwrap(source.metadata).rows
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        _ = try measure(adapter, viewport: viewport) { _ in 20 }
        let update = try measure(adapter, viewport: viewport) { $0.token == rows[0].token ? 40 : 20 }
        XCTAssertTrue(update.extentChanged)
        XCTAssertEqual(update.anchorAdjustedOffset, 45)
    }

    func testDuplicateFactoryLeafIdentityCannotBeAdoptedTwice() async throws {
        let leaf = ViewNode()
        let adapter = try makeAdapter(makeSource([0, 1]) { _ in [leaf] })
        guard
            case .unsupported = adapter.prepare(
                viewport: try viewport(extent: 40), protectedRoots: [], budget: try budget(2))
        else { return XCTFail("Two logical records cannot own the same leaf root") }
        XCTAssertEqual(adapter.mountedLeafCount, 0)
    }

    func testLongKnownZeroRunDoesNotBecomeMountedPlaceholderRows() async throws {
        var calls = 0
        let count = 1000
        let source = try makeSource(Array(0..<count)) { value in
            calls += 1
            return value == 0 || value == count - 1 ? [ViewNode()] : []
        }
        let adapter = try makeAdapter(source, estimate: 1, records: count, leaves: 2)
        let initial = try viewport(extent: Double(count))
        let candidate = try ready(adapter, viewport: initial, elements: count)
        XCTAssertEqual(candidate.children.count, 2)
        XCTAssertEqual(candidate.recordLeafCounts.count, count)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        _ = try measure(adapter, viewport: initial) { _ in 1 }
        let narrowed = try viewport(extent: 2)
        guard
            case .unchanged = adapter.prepare(
                viewport: narrowed, protectedRoots: [], budget: try budget(0))
        else { return XCTFail("The known zero-coordinate run requires neither nodes nor factories") }
        let plan = adapter.layoutPlan(viewport: narrowed)
        XCTAssertEqual(calls, count)
        XCTAssertEqual(adapter.logicalRecordCount, count)
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        XCTAssertEqual(plan.placements.map(\.originY), [0, 1])
        XCTAssertFalse(plan.requiresResolution)
    }

    func testLargePrefetchBuildsVisibleRowBeforeNearestNeighborsWithSmallBudgets() async throws {
        var calls: [Int] = []
        let source = try makeSource(Array(0..<100)) { value in
            calls.append(value)
            return [ViewNode()]
        }
        let adapter = try makeAdapter(source, prefetch: 1000, records: 3, leaves: 3)
        let viewport = try viewport(offset: 1000, extent: 20)
        for expectedCount in 1...3 {
            let candidate = try ready(adapter, viewport: viewport, elements: 1)
            XCTAssertEqual(candidate.children.count, expectedCount)
            XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
            _ = try measure(adapter, viewport: viewport) { _ in 20 }
        }
        XCTAssertEqual(calls, [50, 49, 51])
        let plan = adapter.layoutPlan(viewport: viewport)
        XCTAssertEqual(plan.placements.map(\.originY), [980, 1000, 1020])
        XCTAssertEqual(adapter.mountedRecordCount, 3)
        XCTAssertFalse(plan.requiresResolution, "Unselected optional prefetch does not block settlement")
        for optionalLeafCount in [1, 2] {
            var leafCalls: [Int] = []
            let leafSource = try makeSource([0, 1]) { value in
                leafCalls.append(value)
                return (0..<(value == 0 ? 1 : optionalLeafCount)).map { _ in ViewNode() }
            }
            let leafAdapter = try makeAdapter(
                leafSource, prefetch: 20, records: 2, leaves: optionalLeafCount)
            let leafViewport = try self.viewport(extent: 20)
            let visible = try ready(leafAdapter, viewport: leafViewport)
            XCTAssertEqual(visible.recordLeafCounts, [1])
            XCTAssertTrue(leafAdapter.complete(candidate: visible, adoptedChildren: visible.children))
            _ = try measure(leafAdapter, viewport: leafViewport) { _ in 20 }
            XCTAssertEqual(leafCalls, optionalLeafCount == 1 ? [0] : [0, 1])
            XCTAssertEqual(leafAdapter.mountedLeafCount, 1)
            XCTAssertFalse(leafAdapter.hasUnresolvedWork, "Optional leaf overflow cannot reject visible content")
            guard
                case .unchanged = leafAdapter.prepare(
                    viewport: leafViewport, protectedRoots: [], budget: try budget(0))
            else { return XCTFail("An exhausted optional budget cannot unsettle the visible row") }
            XCTAssertFalse(leafAdapter.hasUnresolvedWork)
        }
    }

    func testPrefetchWaitsWhileCappedVisibleEstimatesAreStillUnresolved() async throws {
        var calls: [Int] = []
        let source = try makeSource(Array(0..<1000)) { value in
            calls.append(value)
            return [ViewNode()]
        }
        let rows = try XCTUnwrap(source.metadata).rows
        let adapter = try makeAdapter(source, estimate: 1, prefetch: 1000, records: 3, leaves: 3)
        let viewport = try viewport(offset: 500, extent: 100)
        let first = try ready(adapter, viewport: viewport)
        XCTAssertEqual(calls, [500, 501, 502])
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        XCTAssertTrue(adapter.hasUnresolvedWork)
        _ = try measure(adapter, viewport: viewport) { $0.token == rows[500].token ? 100 : 1 }
        let second = try ready(adapter, viewport: viewport, elements: 1)
        XCTAssertTrue(adapter.complete(candidate: second, adoptedChildren: second.children))
        _ = try measure(adapter, viewport: viewport) { $0.token == rows[500].token ? 100 : 1 }
        let plan = adapter.layoutPlan(viewport: viewport)
        XCTAssertEqual(calls, [500, 501, 502, 499])
        XCTAssertEqual(plan.placements.map(\.originY), [499, 500, 600])
        XCTAssertFalse(plan.requiresResolution)
        XCTAssertEqual(adapter.mountedLeafCount, 3)
    }

    func testVisibleAndNearestPrefetchShareCapacityWithInsideOrOutsideProtection() async throws {
        for protectedValue in [50, 10] {
            var calls: [Int] = []
            let source = try makeSource(Array(0..<100)) { value in
                calls.append(value)
                return [ViewNode()]
            }
            let adapter = try makeAdapter(source, prefetch: 1000, records: 3, leaves: 3, protected: 1)
            let initial = try viewport(offset: Double(protectedValue) * 20, extent: 20)
            let first = try ready(adapter, viewport: initial, elements: 1)
            XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
            _ = try measure(adapter, viewport: initial) { _ in 20 }
            calls = []
            let visible = try viewport(offset: 1000, extent: 20)
            let candidate = try ready(adapter, viewport: visible, protectedNodes: first.children)
            XCTAssertEqual(candidate.children.count, 3)
            XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
            _ = try measure(adapter, viewport: visible) { _ in 20 }
            let plan = adapter.layoutPlan(viewport: visible)
            XCTAssertEqual(calls, protectedValue == 50 ? [49, 51] : [50, 49])
            XCTAssertEqual(
                plan.placements.map(\.originY), protectedValue == 50 ? [980, 1000, 1020] : [200, 980, 1000])
            XCTAssertFalse(plan.requiresResolution)
        }
    }

    func testNearestPrefetchCursorsSkipKnownZeroRunsAndHonorHalfOpenEdges() async throws {
        let count = 1000
        var calls = 0
        let source = try makeSource(Array(0..<count)) { value in
            calls += 1
            return value == 0 || value == 500 || value == count - 1 ? [ViewNode()] : []
        }
        let rows = try XCTUnwrap(source.metadata).rows
        let adapter = try makeAdapter(source, estimate: 1, prefetch: 10, records: count, leaves: 3)
        let initial = try viewport(extent: Double(count))
        let first = try ready(adapter, viewport: initial, elements: count)
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: first.children))
        _ = try measure(adapter, viewport: initial) { _ in 10 }
        let middle = try viewport(offset: 10, extent: 10)
        guard
            case .unchanged = adapter.prepare(
                viewport: middle, protectedRoots: [], budget: try budget(0))
        else { return XCTFail("Both cursors should jump over known zero-coordinate runs") }
        let plan = adapter.layoutPlan(viewport: middle)
        XCTAssertEqual(plan.placements.map(\.token), [rows[0].token, rows[500].token, rows[999].token])
        XCTAssertEqual(plan.placements.map(\.originY), [0, 10, 20])
        XCTAssertFalse(plan.requiresResolution)
        let end = try viewport(offset: 30, extent: 0)
        let last = try ready(adapter, viewport: end, elements: 0)
        XCTAssertEqual(last.children.count, 1)
        XCTAssertTrue(adapter.complete(candidate: last, adoptedChildren: last.children))
        let edgePlan = adapter.layoutPlan(viewport: end)
        XCTAssertEqual(edgePlan.placements.map(\.token), [rows[999].token])
        XCTAssertFalse(edgePlan.requiresResolution)
        XCTAssertEqual(calls, count)
    }

    func testLayoutProofRequiresAcceptanceAndRejectsRevocationAndOwnerLoss() async throws {
        let source = try makeSource([0])
        let adapter = try makeAdapter(source)
        let viewport = try viewport(extent: 20)
        XCTAssertNil(adapter.captureLayoutProof())
        do {
            let candidate = try ready(adapter, viewport: viewport)
            XCTAssertNil(adapter.captureLayoutProof(), "Construction is not an accepted snapshot")
            XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        }
        let revoked = try XCTUnwrap(adapter.captureLayoutProof())
        XCTAssertTrue(revoked.isCurrent)
        adapter.revokePendingCandidate()
        XCTAssertFalse(revoked.isCurrent)
        XCTAssertNil(adapter.captureLayoutProof())

        try adoptAndMeasure(adapter, viewport: viewport)
        let invalidated = try XCTUnwrap(adapter.captureLayoutProof())
        XCTAssertTrue(invalidated.isCurrent)
        adapter.invalidate()
        XCTAssertFalse(invalidated.isCurrent)
        XCTAssertNil(adapter.captureLayoutProof())

        try adoptAndMeasure(adapter, viewport: viewport)
        let closed = try XCTUnwrap(adapter.captureLayoutProof())
        XCTAssertTrue(closed.isCurrent)
        source.close()
        XCTAssertFalse(closed.isCurrent)
        XCTAssertNil(adapter.captureLayoutProof())

        weak var weakAdapter: Adapter?
        weak var weakSource: Source?
        weak var weakNode: ViewNode?
        @MainActor
        func captureFromTemporaryOwner() throws -> Adapter.LayoutProof {
            let temporarySource = try makeSource([1])
            let temporaryAdapter = try makeAdapter(temporarySource)
            try adoptAndMeasure(temporaryAdapter, viewport: viewport)
            weakAdapter = temporaryAdapter
            weakSource = temporarySource
            weakNode = temporaryAdapter.layoutPlan(viewport: viewport).placements.first?.node
            XCTAssertNotNil(weakAdapter)
            XCTAssertNotNil(weakSource)
            XCTAssertNotNil(weakNode)
            let proof = try XCTUnwrap(temporaryAdapter.captureLayoutProof())
            withExtendedLifetime(temporaryAdapter) { XCTAssertTrue(proof.isCurrent) }
            return proof
        }
        let orphaned = try captureFromTemporaryOwner()
        XCTAssertNil(weakAdapter)
        XCTAssertNil(weakSource)
        XCTAssertNil(weakNode)
        XCTAssertFalse(orphaned.isCurrent)
    }

    private func makeSource(
        _ values: [Int], content: @escaping @MainActor (Int) -> [ViewNode] = { _ in [ViewNode()] }
    ) throws -> Source {
        let source = Source()
        XCTAssertTrue(source.replaceData(values, id: \.self, rowContent: content))
        return source
    }

    private func makeAdapter(
        _ provider: any RetainedLazyListProvider<[ViewNode]>,
        estimate: Double = 20, prefetch: Double = 0,
        records: Int = 32, leaves: Int = 128, protected: Int = 8
    ) throws -> Adapter {
        try XCTUnwrap(
            Adapter(
                provider: provider, estimatedExtent: estimate, prefetchExtent: prefetch,
                maximumMountedRecords: records, maximumMountedLeaves: leaves,
                maximumProtectedRecords: protected))
    }

    private func viewport(
        offset: Double = 0, extent: Double = 40, width: Double = 120,
        contentRevision: UInt64 = 0, environmentRevision: UInt64 = 0
    ) throws -> Adapter.Viewport {
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: width, displayScale: 1, contentRevision: contentRevision,
                environmentRevision: environmentRevision))
        return try XCTUnwrap(Adapter.Viewport(context: context, offset: offset, extent: extent))
    }

    private func budget(_ elements: Int) throws -> RetainedLazyListWorkBudget {
        try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: elements, roundLimit: 4))
    }

    private func ready(
        _ adapter: Adapter, viewport: Adapter.Viewport, elements: Int = 128,
        protectedNodes: [ViewNode] = []
    ) throws -> Adapter.Candidate {
        let result = adapter.prepare(
            viewport: viewport, protectedRoots: Set(protectedNodes.map(ObjectIdentifier.init)),
            budget: try budget(elements))
        var candidate: Adapter.Candidate?
        if case .ready(let prepared) = result { candidate = prepared }
        return try XCTUnwrap(candidate, "Expected a current bounded candidate")
    }

    private func adoptAndMeasure(_ adapter: Adapter, viewport: Adapter.Viewport) throws {
        let candidate = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        _ = try measure(adapter, viewport: viewport) { _ in 20 }
    }

    private func measure(
        _ adapter: Adapter, viewport: Adapter.Viewport,
        height: @MainActor (Adapter.Placement) -> Double
    ) throws -> Adapter.MeasurementUpdate {
        let measurements = adapter.layoutPlan(viewport: viewport).placements.map {
            Adapter.Measurement(
                token: $0.token, leafIndex: $0.leafIndex, node: $0.node, extent: height($0))
        }
        return try XCTUnwrap(adapter.recordMeasurements(measurements, viewport: viewport))
    }
}

@MainActor
private final class AdapterProviderProbe: RetainedLazyListProvider {
    typealias RowContent = [ViewNode]
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    var metadataReads = 0
    var requestReads = 0
    var currentReads = 0
    var materializations = 0
    var onMetadata: (@MainActor () -> Void)?
    var onRequest: (@MainActor () -> Void)?
    var onCurrent: (@MainActor () -> Void)?
    var onMaterialize: (@MainActor () -> Void)?

    init(_ source: RetainedLazyListDataSource<Int, [ViewNode]>) { self.source = source }

    var metadata: RetainedLazyListMetadata? {
        metadataReads += 1
        let value = source.metadata
        onMetadata?()
        return value
    }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        requestReads += 1
        let value = source.request(for: token)
        onRequest?()
        return value
    }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        currentReads += 1
        let value = source.isCurrent(request)
        onCurrent?()
        return value
    }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        materializations += 1
        let value = source.materialize(request, budget: budget)
        onMaterialize?()
        return value
    }
}
