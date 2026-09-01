import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Raw completion exercises only the adapter's bounded table contract. These
/// tests do not establish Runtime attachment, actual-pass, scrolling, or UIA
/// projection authority, and do not claim any end-to-end convergence budget.
@MainActor
final class LazyListUIAConstructionHintTests: XCTestCase {
    private typealias Adapter = RetainedLazyListRuntimeAdapter
    private typealias Source = RetainedLazyListDataSource<Int, [ViewNode]>

    func testInstallingAPlanIsEstimateOnlyAndReadinessDoesNotPublishMeasurements() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let token = try rowToken(300, in: fixture)
        let demand = try XCTUnwrap(fixture.adapter.beginLogicalRealization(of: token, owner: fixture.owner))
        let calls = fixture.provider.calls
        let factories = fixture.probe.factories
        let hint = try XCTUnwrap(fixture.adapter.beginUIAConstructionHint(for: demand, viewport: fixture.viewport))

        XCTAssertTrue(hint.isCurrent)
        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertEqual(fixture.probe.factories, factories)
        XCTAssertEqual(fixture.adapter.contentExtent, 20_000)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 2)
        XCTAssertNil(fixture.adapter.knownLeafCount(for: token))
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(for: hint, viewport: fixture.viewport, measurements: []),
            .awaitingPreparation)

        let candidate = try ready(fixture)
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories.count)), [300, 299])
        XCTAssertEqual(rowIDs(candidate.children), [0, 1, 299, 300])
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let batch = measurements(fixture)
        let afterConstruction = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertEqual(
                fixture.adapter.uiAConstructionReadiness(for: hint, viewport: fixture.viewport, measurements: batch),
                .measurementOnly)
        }

        XCTAssertEqual(fixture.provider.calls, afterConstruction)
        XCTAssertNil(fixture.adapter.knownLeafCount(for: token))
        XCTAssertEqual(fixture.adapter.contentExtent, 20_000)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork, "A construction hint cannot publish global settlement")
    }

    func testAnAlreadyCurrentTargetCanPlanNeighborsWithoutRebuildingIt() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let token = try rowToken(300, in: fixture)
        let demand = try XCTUnwrap(fixture.adapter.beginLogicalRealization(of: token, owner: fixture.owner))
        let first = try ready(fixture)
        XCTAssertTrue(fixture.adapter.complete(candidate: first, adoptedChildren: first.children))
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(measurements(fixture), viewport: fixture.viewport))
        let actual = try XCTUnwrap(fixture.adapter.mountedNodes(for: token)?.first)
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: token), 1)
        let factories = fixture.probe.factories.count
        let hint = try XCTUnwrap(fixture.adapter.beginUIAConstructionHint(for: demand, viewport: fixture.viewport))

        let candidate = try ready(fixture)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories)), [299])
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertTrue(fixture.adapter.mountedNodes(for: token)?.first === actual)
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: hint, viewport: fixture.viewport, measurements: measurements(fixture)), .measurementOnly)
    }

    func testCurrentRequiredRowsKeepCapacityAheadOfThePlannedWindow() async throws {
        let fixture = try makeFixture(records: 3, leaves: 3, protected: 1)
        defer { fixture.source.close() }
        let request = try beginHint(fixture)
        let factories = fixture.probe.factories.count

        let candidate = try ready(fixture)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories)), [300])
        XCTAssertEqual(rowIDs(candidate.children), [0, 1, 300])
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: request.hint, viewport: fixture.viewport, measurements: measurements(fixture)),
            .awaitingPreparation)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 3)
    }

    func testPlannedRowsDoNotConsumeAnotherPhysicalProtectionSlot() async throws {
        let fixture = try makeFixture(protected: 2)
        defer { fixture.source.close() }
        let first = try XCTUnwrap(fixture.adapter.mountedNodes(for: try rowToken(0, in: fixture))?.first)
        let protectedRoots: Set<ObjectIdentifier> = [ObjectIdentifier(first)]
        let update = fixture.adapter.prepare(
            viewport: fixture.viewport, protectedRoots: protectedRoots, budget: try budget(8))
        guard case .unchanged = update else { return XCTFail("Expected the existing physical protection update") }
        let request = try beginHint(fixture)
        let candidate = try ready(fixture, protectedRoots: protectedRoots)
        XCTAssertEqual(rowIDs(candidate.children), [0, 1, 299, 300])
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertTrue(fixture.adapter.endUIAConstructionHint(request.hint))
        fixture.adapter.endLogicalRealization(request.demand)

        let next = fixture.adapter.beginLogicalRealization(of: try rowToken(301, in: fixture), owner: fixture.owner)

        XCTAssertNotNil(next, "Only row 0 and the new logical demand may occupy the two protected slots")
        if let next { fixture.adapter.endLogicalRealization(next) }
    }

    func testTwoAdaptersConsumeOneSharedElementAllowanceWithoutChargingRounds() async throws {
        let first = try makeFixture()
        let second = try makeFixture()
        defer {
            first.source.close()
            second.source.close()
        }
        _ = try beginHint(first)
        let secondRequest = try beginHint(second)
        let shared = try budget(3)
        let firstCount = first.probe.factories.count
        let secondCount = second.probe.factories.count

        let firstCandidate = try ready(first, budget: shared)
        XCTAssertTrue(first.adapter.complete(candidate: firstCandidate, adoptedChildren: firstCandidate.children))
        let secondCandidate = try ready(second, budget: shared)
        XCTAssertTrue(second.adapter.complete(candidate: secondCandidate, adoptedChildren: secondCandidate.children))

        XCTAssertEqual(Array(first.probe.factories.dropFirst(firstCount)), [300, 299])
        XCTAssertEqual(Array(second.probe.factories.dropFirst(secondCount)), [300])
        XCTAssertEqual(shared.remainingElements, 0)
        XCTAssertEqual(shared.remainingRounds, 4)
        XCTAssertEqual(
            second.adapter.uiAConstructionReadiness(
                for: secondRequest.hint, viewport: second.viewport, measurements: measurements(second)),
            .awaitingPreparation)
    }

    func testOneCandidateLocalProbeRequiresOrdinaryRetirementEvenForZeroGapPixels() async throws {
        let fixture = try makeFixture(records: 5, leaves: 10, rows: gapRows)
        defer { fixture.source.close() }
        let request = try beginHint(fixture)
        let factories = fixture.probe.factories.count
        let predecessor = try rowToken(298, in: fixture)
        let candidate = try ready(fixture)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories)), [300, 299, 298])
        XCTAssertEqual(rowIDs(candidate.children), [0, 1, 298, 299, 300])
        XCTAssertFalse(fixture.probe.factories.contains(297))
        XCTAssertNil(fixture.adapter.knownLeafCount(for: predecessor))
        XCTAssertNil(fixture.adapter.mountedNodes(for: predecessor))
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let batch = measurements(fixture)
        let calls = fixture.provider.calls

        for _ in 0..<3 {
            XCTAssertEqual(
                fixture.adapter.uiAConstructionReadiness(
                    for: request.hint, viewport: fixture.viewport, measurements: batch), .awaitingProbeRetirement)
        }

        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertNil(fixture.adapter.knownLeafCount(for: predecessor))
        // The raw table removal below is a separate preparation/completion. In
        // Runtime it must retain its ordinary paid reconciliation and cleanup.
        let retirement = try ready(fixture)
        XCTAssertEqual(rowIDs(retirement.children), [0, 1, 299, 300])
        XCTAssertTrue(fixture.adapter.complete(candidate: retirement, adoptedChildren: retirement.children))
        XCTAssertNil(fixture.adapter.mountedNodes(for: predecessor))
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: request.hint, viewport: fixture.viewport, measurements: measurements(fixture)), .measurementOnly)
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories)), [300, 299, 298])
    }

    func testRecordAndLeafCapsCannotBeBypassedToObtainTheRequiredBoundary() async throws {
        for records in [4, 5] {
            let fixture = try makeFixture(records: records, leaves: 8, rows: gapRows)
            defer { fixture.source.close() }
            let request = try beginHint(fixture)
            let factories = fixture.probe.factories.count
            let candidate = try ready(fixture)

            XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories)), [300, 299])
            XCTAssertEqual(candidate.children.count, 8)
            XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
            XCTAssertEqual(
                fixture.adapter.uiAConstructionReadiness(
                    for: request.hint, viewport: fixture.viewport, measurements: measurements(fixture)),
                .awaitingPreparation)
            XCTAssertFalse(fixture.probe.factories.contains(298))
        }
    }

    func testOversizedPlannedOutputIsDiscardedWholeAndNotRetriedAsTheProbe() async throws {
        let fixture = try makeFixture(records: 5, leaves: 8) { id in
            let rows = self.gapRows(id)
            return id == 299 ? rows + [ViewNode()] : rows
        }
        defer { fixture.source.close() }
        let request = try beginHint(fixture)
        let factories = fixture.probe.factories.count
        let shared = try budget(8)
        let candidate = try ready(fixture, budget: shared)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories)), [300, 299])
        XCTAssertEqual(shared.remainingElements, 6)
        XCTAssertEqual(rowIDs(candidate.children), [0, 1, 300])
        XCTAssertEqual(candidate.children.count, 6)
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertNil(fixture.adapter.knownLeafCount(for: try rowToken(299, in: fixture)))
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: request.hint, viewport: fixture.viewport, measurements: measurements(fixture)),
            .awaitingPreparation)
    }

    func testPreparedEmptyPredecessorDoesNotPublishBeforeAdoptionOrCauseRecursiveProbes() async throws {
        let fixture = try makeFixture(records: 5, leaves: 10) { id in id == 299 ? [] : self.gapRows(id) }
        defer { fixture.source.close() }
        let request = try beginHint(fixture)
        let empty = try rowToken(299, in: fixture)
        let factories = fixture.probe.factories.count
        let candidate = try ready(fixture)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories)), [300, 299, 298])
        XCTAssertNil(fixture.adapter.knownLeafCount(for: empty))
        XCTAssertFalse(fixture.probe.factories.contains(297))
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: empty), 0)
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: request.hint, viewport: fixture.viewport, measurements: measurements(fixture)),
            .awaitingProbeRetirement)
    }

    func testFreshEmptyCandidateShadowsAnEvictedPredecessorsCachedBoundary() async throws {
        var makePredecessorEmpty = false
        let fixture = try makeFixture(records: 5, leaves: 10) { id in
            id == 299 && makePredecessorEmpty ? [] : self.gapRows(id)
        }
        defer { fixture.source.close() }
        let distant = try XCTUnwrap(Adapter.Viewport(context: fixture.viewport.context, offset: 5_980, extent: 40))
        let oldWindow = try ready(fixture, viewport: distant)
        XCTAssertTrue(fixture.adapter.complete(candidate: oldWindow, adoptedChildren: oldWindow.children))
        let original = try ready(fixture)
        XCTAssertTrue(fixture.adapter.complete(candidate: original, adoptedChildren: original.children))
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(measurements(fixture), viewport: fixture.viewport))
        let predecessor = try rowToken(299, in: fixture)
        XCTAssertNil(fixture.adapter.mountedNodes(for: predecessor))
        makePredecessorEmpty = true
        let request = try beginHint(fixture)
        let factories = fixture.probe.factories.count

        let candidate = try ready(fixture)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories)), [300, 299, 298])
        XCTAssertFalse(fixture.probe.factories.contains(297))
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: predecessor), 0)
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: request.hint, viewport: fixture.viewport, measurements: measurements(fixture)),
            .awaitingProbeRetirement)
    }

    func testAnOldHintCannotClearItsCompetitorAndEndingAHintDoesNotResetGeometryMetadata() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let first = try beginHint(fixture)
        let generation = try XCTUnwrap(fixture.adapter.currentLogicalGeneration)
        let layoutProof = try XCTUnwrap(fixture.adapter.captureLayoutProof())
        XCTAssertTrue(fixture.adapter.endUIAConstructionHint(first.hint))
        let second = try XCTUnwrap(
            fixture.adapter.beginUIAConstructionHint(for: first.demand, viewport: fixture.viewport))
        let candidate = try ready(fixture)
        let calls = fixture.provider.calls

        XCTAssertFalse(fixture.adapter.endUIAConstructionHint(first.hint))
        XCTAssertTrue(second.isCurrent)
        XCTAssertTrue(candidate.isCurrent)
        XCTAssertTrue(fixture.adapter.endUIAConstructionHint(second))

        XCTAssertFalse(second.isCurrent)
        XCTAssertFalse(candidate.isCurrent)
        XCTAssertTrue(layoutProof.isCurrent)
        XCTAssertTrue(fixture.adapter.isUIAConstructionGenerationCurrent(generation))
        XCTAssertEqual(fixture.adapter.contentExtent, 20_000)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 2)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testOwnerLossCannotTurnAStaleHintIntoOrdinaryConstruction() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        var owner: RetainedLazyListLogicalRealizationOwner? = RetainedLazyListLogicalRealizationOwner()
        let demand = try XCTUnwrap(
            fixture.adapter.beginLogicalRealization(of: try rowToken(300, in: fixture), owner: try XCTUnwrap(owner)))
        let hint = try XCTUnwrap(fixture.adapter.beginUIAConstructionHint(for: demand, viewport: fixture.viewport))
        let calls = fixture.provider.calls
        let factories = fixture.probe.factories
        owner = nil

        let result = fixture.adapter.prepare(viewport: fixture.viewport, protectedRoots: [], budget: try budget(8))

        guard case .obsolete = result else {
            return XCTFail("An expired request cannot fall back to ordinary factories")
        }
        XCTAssertFalse(hint.isCurrent)
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(for: hint, viewport: fixture.viewport, measurements: []), .obsolete
        )
        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertEqual(fixture.probe.factories, factories)
    }

    func testAHintDoesNotRetainItsAdapterOrProvider() async throws {
        weak var weakAdapter: Adapter?
        weak var weakProvider: UIAConstructionHintProvider?
        weak var weakSource: Source?
        var owner: RetainedLazyListLogicalRealizationOwner?
        func captureHint() throws -> Adapter.UIAConstructionHint {
            let fixture = try makeFixture()
            weakAdapter = fixture.adapter
            weakProvider = fixture.provider
            weakSource = fixture.source
            owner = fixture.owner
            let request = try beginHint(fixture)
            XCTAssertTrue(request.hint.isCurrent)
            return request.hint
        }

        let hint = try captureHint()

        XCTAssertNil(weakAdapter)
        XCTAssertNil(weakProvider)
        XCTAssertNil(weakSource)
        XCTAssertFalse(hint.isCurrent)
        withExtendedLifetime(owner) {}
    }

    func testAnotherAdapterCannotRetireAForeignHint() async throws {
        let first = try makeFixture()
        let second = try makeFixture()
        defer {
            first.source.close()
            second.source.close()
        }
        let firstRequest = try beginHint(first)
        let secondRequest = try beginHint(second)

        XCTAssertFalse(second.adapter.endUIAConstructionHint(firstRequest.hint))
        XCTAssertTrue(firstRequest.hint.isCurrent)
        XCTAssertTrue(secondRequest.hint.isCurrent)
    }

    func testNativeGenerationAndHintChecksRemainCurrentDuringPreparationWithoutProviderReads() async throws {
        let fixture = try makeFixture()
        defer {
            fixture.provider.onCall = nil
            fixture.source.close()
        }
        let request = try beginHint(fixture)
        let generation = try XCTUnwrap(fixture.adapter.currentLogicalGeneration)
        var checked = 0
        fixture.provider.onCall = { _ in
            let calls = fixture.provider.calls
            XCTAssertFalse(fixture.adapter.hasCurrentLogicalSnapshot)
            XCTAssertTrue(fixture.adapter.isUIAConstructionGenerationCurrent(generation))
            XCTAssertTrue(request.hint.isCurrent)
            XCTAssertEqual(fixture.provider.calls, calls)
            checked += 1
        }

        let candidate = try ready(fixture)

        XCTAssertTrue(candidate.isCurrent)
        XCTAssertGreaterThan(checked, 0)
    }

    func testHintCancellationAtEachRawProviderBoundaryStopsLaterConstructionWithoutRefunds() async throws {
        for boundary in ["request", "current.1", "materialize", "current.2", "factory"] {
            let fixture = try makeFixture()
            defer {
                fixture.provider.onCall = nil
                fixture.probe.onFactory = nil
                fixture.source.close()
            }
            let request = try beginHint(fixture)
            let generation = try XCTUnwrap(fixture.adapter.currentLogicalGeneration)
            let factories = fixture.probe.factories.count
            var currentCalls = 0
            var canceled = false
            func cancel() {
                guard !canceled else { return }
                canceled = true
                XCTAssertTrue(fixture.adapter.endUIAConstructionHint(request.hint))
            }
            fixture.provider.onCall = { name in
                if name == "current" { currentCalls += 1 }
                if name == boundary || (name == "current" && "current.\(currentCalls)" == boundary) { cancel() }
            }
            fixture.probe.onFactory = { _ in if boundary == "factory" { cancel() } }
            let shared = try budget(8)

            let result = fixture.adapter.prepare(viewport: fixture.viewport, protectedRoots: [], budget: shared)

            guard case .obsolete = result else { return XCTFail("Expected cancellation at \(boundary)") }
            let charged = boundary == "request" || boundary == "current.1" ? 0 : 1
            XCTAssertTrue(canceled)
            XCTAssertEqual(fixture.probe.factories.count - factories, charged)
            XCTAssertEqual(shared.remainingElements, 8 - charged)
            XCTAssertEqual(shared.remainingRounds, 4)
            XCTAssertTrue(fixture.adapter.isUIAConstructionGenerationCurrent(generation))
            XCTAssertFalse(fixture.probe.factories.contains(299))
            XCTAssertEqual(fixture.adapter.mountedRecordCount, 2)
        }
    }

    func testReadinessRefusesEveryChangedContextAndViewportWithoutRefreshingMetadata() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let request = try beginHint(fixture)
        let candidate = try ready(fixture)
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let batch = measurements(fixture)
        let calls = fixture.provider.calls
        let inputs: [(Double, Double, UInt64, UInt64)] = [
            (121, 1, 0, 0), (120, 2, 0, 0), (120, 1, 1, 0), (120, 1, 0, 1),
        ]
        for (width, scale, content, environment) in inputs {
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: width, displayScale: scale, contentRevision: content, environmentRevision: environment))
            let changed = try XCTUnwrap(Adapter.Viewport(context: context, offset: 0, extent: 40))
            XCTAssertEqual(
                fixture.adapter.uiAConstructionReadiness(for: request.hint, viewport: changed, measurements: batch),
                .obsolete)
        }
        for (offset, extent) in [(1.0, 40.0), (0.0, 41.0)] {
            let changed = try XCTUnwrap(
                Adapter.Viewport(context: fixture.viewport.context, offset: offset, extent: extent))
            XCTAssertEqual(
                fixture.adapter.uiAConstructionReadiness(for: request.hint, viewport: changed, measurements: batch),
                .obsolete)
        }
        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: request.hint, viewport: fixture.viewport, measurements: batch), .measurementOnly)
    }

    func testChangedGapSummaryCannotBeRepairedByAReadinessReadEvenWhenPixelsMatch() async throws {
        let fixture = try makeFixture(records: 4, leaves: 8, rows: gapRows)
        defer { fixture.source.close() }
        let request = try beginHint(fixture, target: 0)
        let prepared = fixture.adapter.prepare(viewport: fixture.viewport, protectedRoots: [], budget: try budget(8))
        guard case .unchanged = prepared else { return XCTFail("Expected the already current bounded table") }
        let batch = measurements(fixture)
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: request.hint, viewport: fixture.viewport, measurements: batch), .measurementOnly)
        let gap = try XCTUnwrap(batch.first?.node)
        gap.retainedLazyListGap = RetainedLazyListGap(
            spacing: 0, separatorThickness: 0, nextRowIsSelected: true, nextRowIsGrouped: false)
        let calls = fixture.provider.calls

        for _ in 0..<3 {
            XCTAssertEqual(
                fixture.adapter.uiAConstructionReadiness(
                    for: request.hint, viewport: fixture.viewport, measurements: batch), .awaitingPreparation)
        }

        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertEqual(fixture.adapter.contentExtent, 20_000)
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: request.token), 2)
    }

    func testMalformedOrOverflowingBatchesCannotProduceMeasurementOnlyReadiness() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let request = try beginHint(fixture)
        let candidate = try ready(fixture)
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let batch = measurements(fixture)
        let first = try XCTUnwrap(batch.first)
        let rest = Array(batch.dropFirst())
        let calls = fixture.provider.calls
        var invalid: [[Adapter.Measurement]] = [
            Array(batch.dropLast()),
            [first] + Array(batch.dropLast()),
            [replacing(first, node: ViewNode())] + rest,
            [replacing(first, leafIndex: 1)] + rest,
        ]
        for extent in [Double.nan, .infinity, -.infinity, -1] {
            invalid.append([replacing(first, extent: extent)] + rest)
        }
        invalid.append(batch.map { replacing($0, extent: .greatestFiniteMagnitude) })

        for malformed in invalid {
            XCTAssertEqual(
                fixture.adapter.uiAConstructionReadiness(
                    for: request.hint, viewport: fixture.viewport, measurements: malformed), .awaitingPreparation)
        }

        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertNil(fixture.adapter.knownLeafCount(for: request.token))
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: request.hint, viewport: fixture.viewport, measurements: batch), .measurementOnly)
    }

    func testSourceReplacementAndRestorationCannotReviveTheOriginalHint() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let request = try beginHint(fixture)
        let generation = try XCTUnwrap(fixture.adapter.currentLogicalGeneration)
        let calls = fixture.provider.calls
        XCTAssertTrue(fixture.source.replaceData([0, 1], id: \.self) { _ in [ViewNode()] })
        XCTAssertTrue(fixture.source.replaceData(Array(0..<1000), id: \.self) { _ in [ViewNode()] })

        XCTAssertFalse(request.hint.isCurrent)
        XCTAssertFalse(fixture.adapter.isUIAConstructionGenerationCurrent(generation))
        XCTAssertEqual(
            fixture.adapter.uiAConstructionReadiness(
                for: request.hint, viewport: fixture.viewport, measurements: []), .obsolete)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testKnownEmptyTargetCannotReceiveAConstructionHint() async throws {
        let fixture = try makeFixture { id in id == 300 ? [] : self.plainRows(id) }
        defer { fixture.source.close() }
        let token = try rowToken(300, in: fixture)
        let demand = try XCTUnwrap(fixture.adapter.beginLogicalRealization(of: token, owner: fixture.owner))
        let candidate = try ready(fixture)
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: token), 0)
        let calls = fixture.provider.calls

        XCTAssertNil(fixture.adapter.beginUIAConstructionHint(for: demand, viewport: fixture.viewport))
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testActualRecordsProofRejectsIdentityABAWithoutLayoutOrAttachmentChanges() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let node = try XCTUnwrap(fixture.adapter.mountedNodes(for: try rowToken(1, in: fixture))?.first)
        let original = RetainedViewIdentity(segments: [.role(.row), .slot(1)])
        node.retainedViewIdentity = original
        let proof = try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())
        let layout = try XCTUnwrap(fixture.adapter.captureLayoutProof())
        let attachment = node.captureLazyListAttachmentProof()
        let calls = fixture.provider.calls

        node.retainedViewIdentity = RetainedViewIdentity(segments: [.role(.row), .slot(2)])
        XCTAssertFalse(proof.isCurrent)
        node.retainedViewIdentity = original

        XCTAssertFalse(proof.isCurrent, "Restoring an equal identity cannot revive the original proof")
        XCTAssertTrue(layout.isCurrent)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertEqual(fixture.provider.calls, calls)
        let replacement = try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())
        XCTAssertTrue(replacement.isCurrent)
        XCTAssertFalse(proof.isCurrent, "A fresh capture cannot repair an escaped old witness")
    }

    func testActualRecordsProofRejectsEqualNilAssignmentOnASecondLeaf() async throws {
        let fixture = try makeFixture(leaves: 8) { id in self.plainRows(id) + [ViewNode()] }
        defer { fixture.source.close() }
        let nodes = try XCTUnwrap(fixture.adapter.mountedNodes(for: try rowToken(0, in: fixture)))
        XCTAssertEqual(nodes.count, 2)
        let second = try XCTUnwrap(nodes.dropFirst().first)
        XCTAssertNil(second.retainedViewIdentity)
        let proof = try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())
        let layout = try XCTUnwrap(fixture.adapter.captureLayoutProof())
        let attachment = second.captureLazyListAttachmentProof()

        second.retainedViewIdentity = nil

        XCTAssertFalse(proof.isCurrent)
        XCTAssertTrue(layout.isCurrent)
        XCTAssertTrue(attachment.isCurrent)
    }

    func testActualRecordsProofIncludesAnUnrelatedMountedRowNotOnlyTheRequestedTarget() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let request = try beginHint(fixture)
        let candidate = try ready(fixture)
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let target = try XCTUnwrap(fixture.adapter.mountedNodes(for: request.token)?.first)
        let targetIdentity = target.captureLazyListIdentityProof()
        let other = try XCTUnwrap(fixture.adapter.mountedNodes(for: try rowToken(0, in: fixture))?.first)
        let proof = try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())

        other.retainedViewIdentity = nil

        XCTAssertTrue(targetIdentity.isCurrent)
        XCTAssertFalse(proof.isCurrent)
    }

    func testActualRecordsProofReadsDoNotInvokeProvidersOrAuthoredIdentityOperations() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let node = try XCTUnwrap(fixture.adapter.mountedNodes(for: try rowToken(0, in: fixture))?.first)
        let hooks = UIAActualRecordsKeyHooks()
        let original = RetainedViewIdentity(segments: [.keyed(.init(UIAActualRecordsKey(value: 7, hooks: hooks)))])
        node.retainedViewIdentity = original
        var hashes = 0
        var equalities = 0
        hooks.onHash = { hashes += 1 }
        hooks.onEqual = { equalities += 1 }
        defer {
            hooks.onHash = nil
            hooks.onEqual = nil
        }
        let calls = fixture.provider.calls
        let proof = try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())

        for _ in 0..<4 { XCTAssertTrue(proof.isCurrent) }
        node.retainedViewIdentity = original
        for _ in 0..<4 { XCTAssertFalse(proof.isCurrent) }

        XCTAssertEqual(hashes, 0)
        XCTAssertEqual(equalities, 0)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testActualRecordsProofSurvivesPreparationUntilTheAcceptedTableChanges() async throws {
        let fixture = try makeFixture()
        defer {
            fixture.provider.onCall = nil
            fixture.source.close()
        }
        let proof = try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())
        _ = try beginHint(fixture)
        var checks = 0
        fixture.provider.onCall = { _ in
            XCTAssertTrue(proof.isCurrent)
            XCTAssertNil(fixture.adapter.captureUIAActualRecordsProof())
            checks += 1
        }

        let candidate = try ready(fixture)

        XCTAssertGreaterThan(checks, 0)
        XCTAssertTrue(proof.isCurrent, "An unadopted candidate is not the accepted row table")
        XCTAssertNil(fixture.adapter.captureUIAActualRecordsProof())
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertFalse(proof.isCurrent)
        XCTAssertTrue(try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof()).isCurrent)
    }

    func testActualRecordsProofChecksExactRootBindingWhenRequestsAndCountsAreUnchanged() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let proof = try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())
        let layout = try XCTUnwrap(fixture.adapter.captureLayoutProof())
        let narrower = try XCTUnwrap(Adapter.Viewport(context: fixture.viewport.context, offset: 0, extent: 20))
        // Abandon a proposal, then prepare the original table under a new
        // attempt. The accepted native requests and roots have not changed.
        _ = try ready(fixture, viewport: narrower)
        let candidate = try ready(fixture)
        XCTAssertTrue(proof.isCurrent)
        XCTAssertEqual(rowIDs(candidate.children), [0, 1])

        XCTAssertTrue(
            fixture.adapter.complete(candidate: candidate, adoptedChildren: Array(candidate.children.reversed())))

        XCTAssertEqual(fixture.adapter.mountedRecordCount, 2)
        XCTAssertTrue(layout.isCurrent)
        XCTAssertFalse(proof.isCurrent, "Each native row must still own the exact original ordered roots")
    }

    func testActualRecordsProofDoesNotRetainTheAdapterProviderOrOriginalRoots() async throws {
        weak var weakAdapter: Adapter?
        weak var weakProvider: UIAConstructionHintProvider?
        weak var weakSource: Source?
        weak var weakRoot: ViewNode?
        func captureProof() throws -> Adapter.UIAActualRecordsProof {
            let fixture = try makeFixture()
            weakAdapter = fixture.adapter
            weakProvider = fixture.provider
            weakSource = fixture.source
            weakRoot = fixture.adapter.mountedNodes(for: try rowToken(0, in: fixture))?.first
            return try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())
        }

        let proof = try captureProof()

        XCTAssertNil(weakAdapter)
        XCTAssertNil(weakProvider)
        XCTAssertNil(weakSource)
        XCTAssertNil(weakRoot)
        XCTAssertFalse(proof.isCurrent)
    }

    func testActualRecordsProofDoesNotKeepEvictedRootsAliveWhileItsAdapterSurvives() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        weak var oldRoot: ViewNode? = fixture.adapter.mountedNodes(for: try rowToken(0, in: fixture))?.first
        let proof = try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())
        XCTAssertNotNil(oldRoot)
        let nextViewport = try XCTUnwrap(Adapter.Viewport(context: fixture.viewport.context, offset: 40, extent: 40))

        let candidate = try ready(fixture, viewport: nextViewport)
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))

        XCTAssertNil(oldRoot)
        XCTAssertFalse(proof.isCurrent)
        XCTAssertTrue(try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof()).isCurrent)
    }

    func testActualRecordsProofRejectsAReplacedSourceWithoutAProviderFreshnessRead() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let proof = try XCTUnwrap(fixture.adapter.captureUIAActualRecordsProof())
        let calls = fixture.provider.calls

        XCTAssertTrue(fixture.source.replaceData(Array(0..<1000), id: \.self) { _ in [ViewNode()] })

        XCTAssertFalse(proof.isCurrent)
        XCTAssertNil(fixture.adapter.captureUIAActualRecordsProof())
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    private struct Fixture {
        let source: Source
        let provider: UIAConstructionHintProvider
        let probe: UIAConstructionHintProbe
        let adapter: Adapter
        let viewport: Adapter.Viewport
        let owner: RetainedLazyListLogicalRealizationOwner
    }

    private func makeFixture(
        records: Int = 4, leaves: Int = 4, protected: Int = 2,
        rows: (@MainActor (Int) -> [ViewNode])? = nil
    ) throws -> Fixture {
        let source = Source()
        let probe = UIAConstructionHintProbe()
        XCTAssertTrue(
            source.replaceData(Array(0..<1000), id: \.self) { id in
                probe.factories.append(id)
                probe.onFactory?(id)
                return rows?(id) ?? self.plainRows(id)
            })
        do {
            let provider = UIAConstructionHintProvider(source)
            let adapter = try XCTUnwrap(
                Adapter(
                    provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                    maximumMountedRecords: records, maximumMountedLeaves: leaves, maximumProtectedRecords: protected))
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
            let viewport = try XCTUnwrap(Adapter.Viewport(context: context, offset: 0, extent: 40))
            let fixture = Fixture(
                source: source, provider: provider, probe: probe, adapter: adapter, viewport: viewport,
                owner: RetainedLazyListLogicalRealizationOwner())
            let candidate = try ready(fixture)
            XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
            _ = try XCTUnwrap(adapter.recordMeasurements(measurements(fixture), viewport: viewport))
            XCTAssertEqual(probe.factories, [0, 1])
            return fixture
        } catch {
            source.close()
            throw error
        }
    }

    private func beginHint(
        _ fixture: Fixture, target: Int = 300
    ) throws -> (
        token: RetainedLazyListRowToken, demand: RetainedLazyListLogicalRealization, hint: Adapter.UIAConstructionHint
    ) {
        let token = try rowToken(target, in: fixture)
        let demand = try XCTUnwrap(fixture.adapter.beginLogicalRealization(of: token, owner: fixture.owner))
        let hint = try XCTUnwrap(fixture.adapter.beginUIAConstructionHint(for: demand, viewport: fixture.viewport))
        return (token, demand, hint)
    }

    private func rowToken(_ position: Int, in fixture: Fixture) throws -> RetainedLazyListRowToken {
        try XCTUnwrap(fixture.source.metadata?.rows[position].token)
    }

    private func budget(_ elements: Int) throws -> RetainedLazyListWorkBudget {
        try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: elements, roundLimit: 4))
    }

    private func ready(
        _ fixture: Fixture, budget shared: RetainedLazyListWorkBudget? = nil,
        protectedRoots: Set<ObjectIdentifier> = [], viewport: Adapter.Viewport? = nil
    ) throws -> Adapter.Candidate {
        let result = fixture.adapter.prepare(
            viewport: viewport ?? fixture.viewport, protectedRoots: protectedRoots, budget: try shared ?? budget(32))
        var candidate: Adapter.Candidate?
        if case .ready(let prepared) = result { candidate = prepared }
        return try XCTUnwrap(candidate, "Expected a bounded raw candidate")
    }

    /// layoutPlan is used only for explicit fixture setup, never between the
    /// before/after observations used to check readiness purity.
    private func measurements(_ fixture: Fixture) -> [Adapter.Measurement] {
        fixture.adapter.layoutPlan(viewport: fixture.viewport).placements.map {
            Adapter.Measurement(
                token: $0.token, leafIndex: $0.leafIndex, node: $0.node,
                extent: $0.node.retainedLazyListGap == nil ? 20 : 0)
        }
    }

    private func replacing(
        _ measurement: Adapter.Measurement, node: ViewNode? = nil, leafIndex: Int? = nil, extent: Double? = nil
    ) -> Adapter.Measurement {
        Adapter.Measurement(
            token: measurement.token, leafIndex: leafIndex ?? measurement.leafIndex,
            node: node ?? measurement.node, extent: extent ?? measurement.extent)
    }

    private func rowIDs(_ nodes: [ViewNode]) -> [Int] {
        nodes.compactMap { node in node.accessibilityIdentifier.flatMap(Int.init) }
    }

    private func plainRows(_ id: Int) -> [ViewNode] {
        let node = ViewNode()
        node.accessibilityIdentifier = String(id)
        return [node]
    }

    private func gapRows(_ id: Int) -> [ViewNode] {
        let gap = ViewNode()
        gap.retainedLazyListGap = RetainedLazyListGap(
            spacing: 0, separatorThickness: 0, nextRowIsSelected: false, nextRowIsGrouped: false)
        return [gap] + plainRows(id)
    }
}

@MainActor
private final class UIAConstructionHintProbe {
    var factories: [Int] = []
    var onFactory: (@MainActor (Int) -> Void)?
}

@MainActor
private final class UIAActualRecordsKeyHooks {
    var onHash: (() -> Void)?
    var onEqual: (() -> Void)?
}

private struct UIAActualRecordsKey: Hashable {
    let value: Int
    let hooks: UIAActualRecordsKeyHooks

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.hooks.onEqual?() }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { hooks.onHash?() }
        hasher.combine(value)
    }
}

@MainActor
private final class UIAConstructionHintProvider: RetainedLazyListProvider {
    typealias RowContent = [ViewNode]
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    private(set) var calls: [String] = []
    var onCall: (@MainActor (String) -> Void)?

    init(_ source: RetainedLazyListDataSource<Int, [ViewNode]>) { self.source = source }

    var metadata: RetainedLazyListMetadata? {
        calls.append("metadata")
        let value = source.metadata
        onCall?("metadata")
        return value
    }

    func token(for key: RetainedViewIdentity.Key, occurrence: Int) -> RetainedLazyListRowToken? {
        calls.append("token")
        let value = source.token(for: key, occurrence: occurrence)
        onCall?("token")
        return value
    }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        calls.append("request")
        let value = source.request(for: token)
        onCall?("request")
        return value
    }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        calls.append("current")
        let value = source.isCurrent(request)
        onCall?("current")
        return value
    }

    func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity? {
        calls.append("identity")
        let value = source.identityPrefix(for: request)
        onCall?("identity")
        return value
    }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        calls.append("materialize")
        let value = source.materialize(request, budget: budget)
        onCall?("materialize")
        return value
    }
}
