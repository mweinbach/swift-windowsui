import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The hook observes the actual corrective pass after paid measurement. It
/// cannot provide a phase, debit, receipt, replacement witness, or query result.
@MainActor
final class LazyListUIAMeasurementCorrectionTests: XCTestCase {
    func testQuietCorrectionPreservesTheUnenteredSecondRoundWithinTheDefaultFour() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }

        XCTAssertTrue(fixture.realize())

        try assertCompletedCorrection(fixture)
    }

    func testPaintOnlyMutationDuringCorrectionCannotEnterTheRemainingPhase() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        fixture.onCorrection = { $0.runtime.root.backgroundColor = .red }

        try assertRejectedCorrection(fixture)

        XCTAssertEqual(fixture.runtime.root.backgroundColor, .red)
    }

    func testRestoredScrollIdentityAndScaleCannotReviveTheOriginalCorrection() async throws {
        for mutation in MeasurementCorrectionRestoredInput.allCases {
            let fixture = try MeasurementCorrectionFixture()
            defer { fixture.close() }
            let offset = fixture.scroll.scrollOffset
            let identity = fixture.list.retainedViewIdentity
            let scale = fixture.runtime.displayScale
            fixture.onCorrection = { fixture in
                switch mutation {
                case .scroll:
                    fixture.scroll.scrollOffset = offset + 1
                    fixture.scroll.scrollOffset = offset
                case .identity:
                    fixture.list.retainedViewIdentity = RetainedViewIdentity(segments: [.slot(999)])
                    fixture.list.retainedViewIdentity = identity
                case .scale:
                    fixture.runtime.displayScale = scale + 1
                    fixture.runtime.displayScale = scale
                }
            }

            try assertRejectedCorrection(fixture)

            XCTAssertEqual(fixture.scroll.scrollOffset, offset, "\(mutation)")
            XCTAssertEqual(fixture.list.retainedViewIdentity, identity, "\(mutation)")
            XCTAssertEqual(fixture.runtime.displayScale, scale, "\(mutation)")
        }
    }

    func testRestoredLeaseAndBodyStillRevokeTheirOriginalConstructionNonce() async throws {
        for mutation in MeasurementCorrectionConstructionInput.allCases {
            let fixture = try MeasurementCorrectionFixture()
            defer { fixture.close() }
            let lease = try XCTUnwrap(fixture.list.retainedSubtreeBuildLease)
            XCTAssertNil(fixture.list.geometryReaderBuild)
            fixture.onCorrection = { fixture in
                switch mutation {
                case .lease:
                    // Even assigning the same lease rotates construction identity.
                    // It does not invalidate geometry or replace the adapter.
                    fixture.list.retainedSubtreeBuildLease = lease
                case .body:
                    fixture.list.geometryReaderBuild = { _, _ in [] }
                    fixture.list.geometryReaderBuild = nil
                }
            }

            try assertRejectedCorrection(fixture)

            XCTAssertTrue(fixture.list.retainedSubtreeBuildLease === lease, "\(mutation)")
            XCTAssertNil(fixture.list.geometryReaderBuild, "\(mutation)")
        }
    }

    func testBodyAddedAfterANonReaderVisitInvalidatesCorrectionBeforeTheRemainingPhase() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        let target = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10), isHitTestVisible: false)
        let observer = ViewNode(frame: Rect(x: 0, y: 0, width: 1, height: 1), isHitTestVisible: false)
        fixture.runtime.root.addChild(target)
        fixture.runtime.root.addChild(observer)
        XCTAssertNil(target.retainedLazyListAdapter)
        XCTAssertNil(target.geometryReaderBuild)
        var assignmentCalls = 0
        var bodyCalls = 0
        observer.onLayout = { [weak fixture, weak target] _ in
            guard let fixture, let target, fixture.isCorrectionBoundary else { return }
            assignmentCalls += 1
            guard assignmentCalls == 1 else { return }
            XCTAssertEqual(target.lastLayoutVisitPassID, fixture.runtime.layoutPassID)
            XCTAssertNil(target.geometryReaderBuild)
            // The node was visited without a body, so it is absent from this
            // pass's reader cohort. Only proof of all actual tree inputs can
            // detect this new body before the remaining phases are entered.
            target.geometryReaderBuild = { _, _ in
                bodyCalls += 1
                return []
            }
        }

        try assertRejectedCorrection(fixture)

        XCTAssertEqual(assignmentCalls, 1)
        XCTAssertEqual(bodyCalls, 0)
        XCTAssertNotNil(target.geometryReaderBuild)
    }

    func testCorrectionDoesNotKeepARemovedListLeaseAlive() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        weak var oldLease: MeasurementCorrectionRecordingLease?
        do {
            let lease = MeasurementCorrectionRecordingLease(
                base: try XCTUnwrap(fixture.list.retainedSubtreeBuildLease), fixture: fixture)
            fixture.list.retainedSubtreeBuildLease = lease
            oldLease = lease
        }
        XCTAssertNotNil(oldLease)
        var expiredInsideCorrection = false
        fixture.onCorrection = { fixture in
            fixture.list.retainedSubtreeBuildLease = nil
            expiredInsideCorrection = oldLease == nil
            XCTAssertNil(oldLease, "Only weak native correction proof may survive into this actual pass")
        }

        try assertRejectedCorrection(fixture)

        XCTAssertTrue(expiredInsideCorrection)
        XCTAssertNil(oldLease)
    }

    func testCheckedGeometryExhaustionDuringCorrectionCannotEnterTheRemainingPhase() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        fixture.onCorrection = { fixture in
            fixture.runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
            fixture.runtime.root.frame.size.width += 1
        }

        try assertRejectedCorrection(fixture)

        guard case .unavailable = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("A checked generation cannot wrap into a new settlement")
        }
    }

    func testRejectedNestedQueryDoesNotCreateAnotherPassOrDebit() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        var nestedQueries = 0
        fixture.onCorrection = { fixture in
            let traceCount = fixture.runtime.lazyListUIAPhasesForTesting.count
            let pass = fixture.runtime.layoutPassID
            nestedQueries += 1

            XCTAssertNil(fixture.runtime.resolvedLayoutFrame(of: fixture.runtime.root))

            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
            XCTAssertEqual(fixture.runtime.lazyListUIAPhasesForTesting.count, traceCount)
        }

        XCTAssertTrue(fixture.realize())

        XCTAssertEqual(nestedQueries, 1)
        try assertCompletedCorrection(fixture)
    }

    func testAlreadyQueuedCallbackDeclinesSavingAndRunsTheRemainingPhaseOnce() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        var callbacks = 0
        var callbackTrace: [Phase] = []
        fixture.runtime.scheduleAfterLayout(key: "uia-correction-already-queued") { [weak fixture] in
            callbacks += 1
            callbackTrace = fixture?.trace ?? []
        }

        try fixture.withPreparation { request in
            XCTAssertNil(request, "Ordinary queued work uses the default allowance before any target demand")
            XCTAssertEqual(fixture.probe.correctionCalls, 0, "Pending work makes the moved pass ineligible")
            XCTAssertNil(fixture.probe.correctionTrace)
            let trace = fixture.trace
            for kind in [Phase.Kind.roundDebit, .measurementPhase, .readerPhase, .providerPhase] {
                XCTAssertEqual(trace.filter { $0.kind == kind }.map(\.consumedRounds), [1, 2, 3, 4])
            }
            let second = trace.filter { $0.consumedRounds == 2 }
            let provider = try XCTUnwrap(second.firstIndex { $0.kind == .providerPhase })
            let tail = try XCTUnwrap(second.firstIndex { $0.kind == .layoutPass })
            XCTAssertLessThan(provider, tail, "The ineligible path retains the ordinary post-phase layout")
            XCTAssertEqual(second.filter { $0.kind == .layoutPass }.count, 1)
            XCTAssertFalse(trace.contains { $0.kind == .savedProviderPhase || $0.kind == .resumedProviderPhase })
            XCTAssertEqual(callbacks, 1, "The ordinary initial epilogue still owns its queued callback")
            XCTAssertEqual(callbackTrace.last?.consumedRounds, 3)
            XCTAssertTrue(callbackTrace.contains { $0.kind == .layoutPass && $0.consumedRounds == 2 })
            XCTAssertFalse(fixture.probe.factories.contains(MeasurementCorrectionFixture.targetIndex))
            try assertSettled(fixture.runtime)
        }
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
    }

    func testCallbackQueuedInsideCorrectionInvalidatesBeforeTheRemainingPhase() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        var callbacks = 0
        fixture.onCorrection = { fixture in
            fixture.runtime.scheduleAfterLayout(key: "uia-correction-new-callback") { callbacks += 1 }
        }

        try assertRejectedCorrection(fixture, layoutPasses: 2)

        XCTAssertEqual(callbacks, 1, "Failure cannot suppress already-due ordinary callback cleanup")
    }

    func testChangedReaderOutputSlotUsesOneOrdinaryBuildAndOneNecessaryTailPass() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        let readerProbe = MeasurementCorrectionReaderProbe()
        let reader = readerProbe.makeNode(builtSize: Size(width: 120, height: 20))
        fixture.runtime.root.addChild(reader)
        let authoredFrame = reader.frame
        let preferredSize = reader.preferredSize
        fixture.onCorrection = { _ in
            // Only an external layout input changes. The preinstalled callback
            // publishes its resolved slot without rewriting authored node fields.
            readerProbe.expandsSlot = true
        }

        try fixture.withPreparation { request in
            XCTAssertNotNil(request)
            try assertOrdinarySecondRound(fixture, layoutPasses: 2)
            XCTAssertEqual(readerProbe.calls, 1)
            XCTAssertEqual(readerProbe.rounds, [2])
            XCTAssertEqual(reader.frame, authoredFrame)
            XCTAssertEqual(reader.preferredSize, preferredSize)
            XCTAssertEqual(reader.resolvedFrame.size, Size(width: 120, height: 40))
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 40))
            XCTAssertNil(reader.geometryReaderBuild, "The accepted body is a plain leaf, not another pending reader")
            XCTAssertFalse(fixture.probe.factories.contains(MeasurementCorrectionFixture.targetIndex))
            try assertSettled(fixture.runtime)
        }
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 2)
    }

    func testUnchangedProviderFallbackStillPaysItsNecessarySecondActualPass() async throws {
        let fixture = try MeasurementCorrectionFixture(warmViewportHeight: 160)
        defer { fixture.close() }
        let lease = MeasurementCorrectionRecordingLease(
            base: try XCTUnwrap(fixture.list.retainedSubtreeBuildLease), fixture: fixture)
        fixture.list.retainedSubtreeBuildLease = lease
        let fallback = installProtectedRootPerturbation(in: fixture)

        try fixture.withPreparation { request in
            XCTAssertNotNil(request)
            try assertOrdinarySecondRound(fixture, layoutPasses: 2)
            XCTAssertEqual(fallback.calls, 1)
            XCTAssertEqual(lease.beginRounds, [1, 2])
            XCTAssertEqual(fixture.probe.factories.count, try XCTUnwrap(fallback.factoryCount))
            XCTAssertEqual(fixture.list.children.map(ObjectIdentifier.init), try XCTUnwrap(fallback.childIDs))
            XCTAssertEqual(
                MeasurementCorrectionNodeBits.capture(in: fixture.runtime), try XCTUnwrap(lease.secondRoundBits))
            let passes = fixture.trace.filter { $0.kind == .layoutPass && $0.consumedRounds == 2 }
            XCTAssertEqual(passes.count, 2)
            if passes.count == 2 {
                XCTAssertGreaterThan(passes[1].geometryRevision, passes[0].geometryRevision)
                XCTAssertEqual(passes[1].resolutionSequence, passes[0].resolutionSequence)
            }
            XCTAssertFalse(fixture.probe.factories.contains(MeasurementCorrectionFixture.targetIndex))
            try assertSettled(fixture.runtime)
        }
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 2)
    }

    func testOptionalProviderExpansionRequiresTheNextPaidMeasurement() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        let lease = MeasurementCorrectionRecordingLease(
            base: try XCTUnwrap(fixture.list.retainedSubtreeBuildLease), fixture: fixture)
        fixture.list.retainedSubtreeBuildLease = lease
        let fallback = installProtectedRootPerturbation(in: fixture)

        try fixture.withPreparation { request in
            XCTAssertNotNil(request)
            _ = try assertObservedCorrection(fixture)
            let trace = fixture.trace
            for kind in [Phase.Kind.roundDebit, .measurementPhase] {
                XCTAssertEqual(trace.filter { $0.kind == kind }.map(\.consumedRounds), [1, 2, 3])
            }
            for kind in [Phase.Kind.readerPhase, .providerPhase] {
                XCTAssertEqual(trace.filter { $0.kind == kind }.map(\.consumedRounds), [1, 2])
            }
            let passes = trace.filter { $0.kind == .layoutPass && $0.consumedRounds == 2 }
            XCTAssertEqual(passes.count, 2)
            let tail = try XCTUnwrap(passes.last)
            let debit = try XCTUnwrap(trace.first { $0.kind == .roundDebit && $0.consumedRounds == 3 })
            let measurement = try XCTUnwrap(trace.first { $0.kind == .measurementPhase && $0.consumedRounds == 3 })
            XCTAssertEqual(debit.layoutPassID, tail.layoutPassID)
            XCTAssertEqual(measurement.layoutPassID, tail.layoutPassID)
            let saved = trace.filter { $0.kind == .savedProviderPhase }
            XCTAssertEqual(saved.count, 1)
            XCTAssertEqual(saved.first?.consumedRounds, 3)
            XCTAssertFalse(trace.contains { $0.kind == .resumedProviderPhase })
            XCTAssertEqual(fallback.calls, 1)
            XCTAssertEqual(lease.beginRounds, [1, 2])
            XCTAssertEqual(fixture.probe.factories.count, try XCTUnwrap(fallback.factoryCount) + 3)
            let originalChildren = try XCTUnwrap(fallback.childIDs)
            let currentChildren = fixture.list.children.map(ObjectIdentifier.init)
            XCTAssertEqual(currentChildren.count, originalChildren.count + 6)
            XCTAssertTrue(Set(originalChildren).isSubset(of: Set(currentChildren)))
            XCTAssertFalse(fixture.probe.factories.contains(MeasurementCorrectionFixture.targetIndex))
            try assertSettled(fixture.runtime)
        }
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 3)
    }

    func testDeclinedProviderFallbackContinuesAtTheNextPaidMeasurementWithoutAnotherPass() async throws {
        let fixture = try MeasurementCorrectionFixture()
        defer { fixture.close() }
        let lease = MeasurementCorrectionRecordingLease(
            base: try XCTUnwrap(fixture.list.retainedSubtreeBuildLease), fixture: fixture, decliningRound: 2)
        fixture.list.retainedSubtreeBuildLease = lease
        let fallback = installProtectedRootPerturbation(in: fixture)

        try fixture.withPreparation { _ in
            let correction = try assertObservedCorrection(fixture)
            let trace = fixture.trace
            XCTAssertEqual(trace.filter { $0.kind == .roundDebit }.map(\.consumedRounds), [1, 2, 3])
            XCTAssertEqual(trace.filter { $0.kind == .measurementPhase }.map(\.consumedRounds), [1, 2, 3])
            let second = trace.filter { $0.consumedRounds == 2 }
            for kind in [Phase.Kind.roundDebit, .measurementPhase, .readerPhase, .providerPhase, .layoutPass] {
                XCTAssertEqual(second.filter { $0.kind == kind }.count, 1)
            }
            XCTAssertFalse(second.contains { $0.kind == .savedProviderPhase || $0.kind == .resumedProviderPhase })
            let nextDebit = try XCTUnwrap(trace.first { $0.kind == .roundDebit && $0.consumedRounds == 3 })
            XCTAssertEqual(nextDebit.layoutPassID, correction.layoutPassID)
            XCTAssertEqual(nextDebit.geometryRevision, correction.geometryRevision)
            XCTAssertEqual(nextDebit.resolutionSequence, correction.resolutionSequence)
            XCTAssertEqual(lease.canBuildRounds.filter { $0 == 2 }, [2])
            XCTAssertFalse(lease.beginRounds.contains(2), "Refusal must not enter a build or invalidate geometry")
            XCTAssertEqual(fallback.calls, 1)
            XCTAssertEqual(fixture.probe.factories.count, try XCTUnwrap(fallback.factoryCount))
            XCTAssertEqual(fixture.list.children.map(ObjectIdentifier.init), try XCTUnwrap(fallback.childIDs))
            XCTAssertEqual(
                MeasurementCorrectionNodeBits.capture(in: fixture.runtime), try XCTUnwrap(lease.secondRoundBits))
            XCTAssertFalse(fixture.probe.factories.contains(MeasurementCorrectionFixture.targetIndex))
            XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        }
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 3)
    }

    func testASecondActualListCannotBeOmittedFromCorrectionEligibility() async throws {
        let fixture = try MeasurementCorrectionFixture(hasSecondList: true)
        defer { fixture.close() }
        let secondFactories = fixture.probe.factories.filter { $0 == 100 }.count

        try fixture.withPreparation { request in
            XCTAssertNil(request, "Both accepted replacements share the original four-round allowance")
            XCTAssertEqual(fixture.host.lists.count, 2)
            for list in fixture.host.lists {
                XCTAssertTrue(list.retainedLazyListRuntime === fixture.runtime)
                XCTAssertEqual(list.lastLayoutVisitPassID, fixture.runtime.layoutPassID)
                XCTAssertGreaterThan(list.resolvedFrame.width, 0)
                XCTAssertGreaterThan(list.resolvedFrame.height, 0)
                XCTAssertFalse(list.isLayoutDeferredByVirtualization)
            }
            XCTAssertEqual(fixture.probe.correctionCalls, 0, "The unprepared second List is part of the real cohort")
            XCTAssertNil(fixture.probe.correctionTrace)
            let trace = fixture.trace
            for kind in [Phase.Kind.roundDebit, .measurementPhase, .readerPhase, .providerPhase] {
                XCTAssertEqual(trace.filter { $0.kind == kind }.map(\.consumedRounds), [1, 2, 3, 4])
            }
            XCTAssertFalse(trace.contains { $0.kind == .savedProviderPhase || $0.kind == .resumedProviderPhase })
            XCTAssertFalse(fixture.probe.factories.contains(MeasurementCorrectionFixture.targetIndex))
            XCTAssertGreaterThan(fixture.probe.factories.filter { $0 == 100 }.count, secondFactories)
            XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        }
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
    }

    private func installProtectedRootPerturbation(
        in fixture: MeasurementCorrectionFixture
    ) -> MeasurementCorrectionProviderProbe {
        let probe = MeasurementCorrectionProviderProbe()
        let observer = ViewNode(frame: Rect(x: 0, y: 0, width: 1, height: 1), isHitTestVisible: false)
        fixture.runtime.root.addChild(observer)
        observer.onLayout = { [weak fixture, weak probe] _ in
            guard let fixture, let probe, fixture.isCorrectionBoundary else { return }
            probe.calls += 1
            guard probe.calls == 1 else { return }
            XCTAssertEqual(fixture.list.lastLayoutVisitPassID, fixture.runtime.layoutPassID)
            guard let adapter = fixture.list.retainedLazyListAdapter,
                let row = fixture.list.children.first(where: { !$0.isSeparatorRule && $0.retainedLazyListGap == nil })
            else {
                return XCTFail("Expected the already adopted public List row after its actual layout")
            }
            probe.factoryCount = fixture.probe.factories.count
            probe.childIDs = fixture.list.children.map(ObjectIdentifier.init)
            // Explicit internal fallback regression, not an app input scenario.
            // Perturb only the native protection plan after actual List layout.
            // Ordinary admission clears it from the real, empty protected roots,
            // yielding .unchanged without a factory or child-table replacement.
            XCTAssertTrue(adapter.updateProtectedRoots([ObjectIdentifier(row)]))
            XCTAssertTrue(adapter.hasUnresolvedWork)
        }
        return probe
    }

    private func assertCompletedCorrection(
        _ fixture: MeasurementCorrectionFixture, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let correction = try assertObservedCorrection(fixture, file: file, line: line)
        let trace = fixture.trace
        for kind in [Phase.Kind.roundDebit, .measurementPhase, .readerPhase, .providerPhase] {
            XCTAssertEqual(
                trace.filter { $0.kind == kind }.map(\.consumedRounds), [1, 2, 3, 4], file: file, line: line)
        }
        let saved = trace.filter { $0.kind == .savedProviderPhase }
        let resumed = trace.filter { $0.kind == .resumedProviderPhase }
        XCTAssertEqual(saved.count, 1, file: file, line: line)
        XCTAssertEqual(resumed.count, 1, file: file, line: line)
        let original = try XCTUnwrap(saved.first, file: file, line: line)
        let resume = try XCTUnwrap(resumed.first, file: file, line: line)
        XCTAssertEqual(original.consumedRounds, 2, file: file, line: line)
        XCTAssertEqual(original.layoutPassID, correction.layoutPassID, file: file, line: line)
        XCTAssertEqual(resume.layoutPassID, original.layoutPassID, file: file, line: line)
        XCTAssertEqual(resume.consumedRounds, original.consumedRounds, file: file, line: line)
        XCTAssertEqual(resume.remainingRounds, original.remainingRounds, file: file, line: line)
        XCTAssertEqual(resume.remainingElements, original.remainingElements, file: file, line: line)
        XCTAssertEqual(resume.geometryRevision, original.geometryRevision + 1, file: file, line: line)
        XCTAssertEqual(resume.mutationRevision, original.mutationRevision + 1, file: file, line: line)
        XCTAssertEqual(resume.resolutionSequence, original.resolutionSequence + 1, file: file, line: line)
        XCTAssertFalse(trace.contains { $0.kind == .revokedProviderPhase }, file: file, line: line)
        XCTAssertEqual(
            trace.filter { $0.kind == .layoutPass && $0.consumedRounds == 2 }.count, 2, file: file, line: line)
        XCTAssertEqual(trace.filter { $0.kind == .ownedScroll }.count, 1, file: file, line: line)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128, file: file, line: line)
        XCTAssertEqual(fixture.probe.targetFactoryRounds, [2], file: file, line: line)
        XCTAssertEqual(
            fixture.source.uiaLogicalItemState(elementID: fixture.element), .ordinary, file: file, line: line)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0, file: file, line: line)
        XCTAssertTrue(fixture.probe.activations.isEmpty, file: file, line: line)
        try assertSettled(fixture.runtime, file: file, line: line)
    }

    private func assertRejectedCorrection(
        _ fixture: MeasurementCorrectionFixture, layoutPasses: Int = 1,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let originalOffset = fixture.scroll.scrollOffset
        XCTAssertFalse(fixture.realize(), file: file, line: line)
        _ = try assertObservedCorrection(fixture, file: file, line: line)
        let trace = fixture.trace
        XCTAssertEqual(trace.filter { $0.kind == .roundDebit }.map(\.consumedRounds), [1, 2], file: file, line: line)
        XCTAssertEqual(
            trace.filter { $0.kind == .measurementPhase }.map(\.consumedRounds), [1, 2], file: file, line: line)
        XCTAssertEqual(
            trace.filter { $0.kind == .layoutPass && $0.consumedRounds == 2 }.count, layoutPasses, file: file,
            line: line)
        XCTAssertFalse(
            trace.contains { $0.consumedRounds >= 2 && ($0.kind == .readerPhase || $0.kind == .providerPhase) },
            "A failed original correction cannot enter remaining authored work", file: file, line: line)
        XCTAssertFalse(
            trace.contains { $0.kind == .savedProviderPhase || $0.kind == .resumedProviderPhase }, file: file,
            line: line)
        XCTAssertFalse(trace.contains { $0.kind == .ownedScroll }, file: file, line: line)
        XCTAssertEqual(fixture.scroll.scrollOffset, originalOffset, file: file, line: line)
        XCTAssertFalse(
            fixture.probe.factories.contains(MeasurementCorrectionFixture.targetIndex), file: file, line: line)
        XCTAssertEqual(trace.last?.consumedRounds, 2, file: file, line: line)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 2, file: file, line: line)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild, file: file, line: line)
        XCTAssertTrue(fixture.probe.activations.isEmpty, file: file, line: line)
    }

    private func assertOrdinarySecondRound(
        _ fixture: MeasurementCorrectionFixture, layoutPasses: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let correction = try assertObservedCorrection(fixture, file: file, line: line)
        let trace = fixture.trace
        for kind in [Phase.Kind.roundDebit, .measurementPhase, .readerPhase, .providerPhase] {
            XCTAssertEqual(trace.filter { $0.kind == kind }.map(\.consumedRounds), [1, 2], file: file, line: line)
        }
        let second = trace.filter { $0.consumedRounds == 2 }
        XCTAssertEqual(second.filter { $0.kind == .layoutPass }.count, layoutPasses, file: file, line: line)
        XCTAssertLessThanOrEqual(second.filter { $0.kind == .layoutPass }.count, 2, file: file, line: line)
        let reader = try XCTUnwrap(second.first { $0.kind == .readerPhase }, file: file, line: line)
        let provider = try XCTUnwrap(second.first { $0.kind == .providerPhase }, file: file, line: line)
        XCTAssertEqual(reader.layoutPassID, correction.layoutPassID, file: file, line: line)
        XCTAssertEqual(provider.layoutPassID, correction.layoutPassID, file: file, line: line)
        XCTAssertFalse(
            trace.contains { $0.kind == .savedProviderPhase || $0.kind == .resumedProviderPhase }, file: file,
            line: line)
        XCTAssertEqual(trace.last?.consumedRounds, 2, file: file, line: line)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild, file: file, line: line)
    }

    private typealias Phase = RetainedViewRuntime.LazyListUIAPhaseTrace

    private func assertObservedCorrection(
        _ fixture: MeasurementCorrectionFixture, file: StaticString = #filePath, line: UInt = #line
    ) throws -> Phase {
        XCTAssertEqual(
            fixture.probe.correctionCalls, 1, "The actual new boundary must be reached once", file: file, line: line)
        let trace = try XCTUnwrap(fixture.probe.correctionTrace, file: file, line: line)
        let correction = try XCTUnwrap(trace.last, file: file, line: line)
        XCTAssertTrue(correction.kind == .layoutPass, file: file, line: line)
        XCTAssertEqual(correction.consumedRounds, 2, file: file, line: line)
        XCTAssertEqual(
            trace.filter { $0.kind == .measurementPhase && $0.consumedRounds == 2 }.count, 1, file: file, line: line)
        XCTAssertFalse(
            trace.contains { $0.consumedRounds == 2 && ($0.kind == .readerPhase || $0.kind == .providerPhase) },
            file: file, line: line)
        return correction
    }

    private func assertSettled(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            XCTFail("The operation must supply its own completed settlement", file: file, line: line)
            return
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
    }
}

private enum MeasurementCorrectionRestoredInput: CaseIterable { case scroll, identity, scale }
private enum MeasurementCorrectionConstructionInput: CaseIterable { case lease, body }

@MainActor
private final class MeasurementCorrectionFixture {
    static let targetIndex = 30
    let probe: MeasurementCorrectionProbe
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let element: UInt64
    let witness: RetainedLazyListAccessibilityItem
    let list: ViewNode
    let scroll: ViewNode
    var onCorrection: (@MainActor (MeasurementCorrectionFixture) -> Void)?

    var runtime: RetainedViewRuntime { host.runtime }
    var trace: [RetainedViewRuntime.LazyListUIAPhaseTrace] { runtime.lazyListUIAPhasesForTesting }
    var isCorrectionBoundary: Bool {
        guard let last = trace.last, last.kind == .layoutPass, last.consumedRounds == 2 else { return false }
        return trace.contains { $0.kind == .measurementPhase && $0.consumedRounds == 2 }
            && !trace.contains { $0.consumedRounds == 2 && ($0.kind == .readerPhase || $0.kind == .providerPhase) }
    }

    init(hasSecondList: Bool = false, warmViewportHeight: Double = 80) throws {
        let probe = MeasurementCorrectionProbe()
        self.probe = probe
        let host: MountedLazyListTestHost
        if hasSecondList {
            host = MountedLazyListTestHost(size: Size(width: 640, height: 80)) {
                HStack(spacing: 0) {
                    List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
                        .frame(width: 320, height: 80)
                    List(Array(100..<200), id: \.self) { probe.makeRows($0) }.listStyle(.plain)
                        .frame(width: 320, height: 80)
                }
                .frame(width: 640, height: 80)
            }
        } else {
            host = MountedLazyListTestHost(size: Size(width: 320, height: warmViewportHeight)) {
                List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
            }
        }
        self.host = host
        probe.runtime = host.runtime
        let source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        self.source = source
        do {
            XCTAssertNotNil(host.layout())
            let container = try XCTUnwrap(source.uiaElementSnapshots().first(where: \.supportsItemContainer)?.id)
            var current: UInt64?
            for _ in 0...Self.targetIndex {
                guard case .item(let id) = source.uiaFindItem(containerID: container, afterElementID: current) else {
                    XCTFail("Expected the next actual logical public List identity")
                    throw MeasurementCorrectionFixtureError.missingItem
                }
                current = id
            }
            element = try XCTUnwrap(current)
            let warmList = try host.list()
            var native: RetainedLazyListAccessibilityItem?
            for _ in 0...Self.targetIndex {
                native = try XCTUnwrap(host.runtime.lazyListAccessibilityItem(in: warmList, after: native))
            }
            let nativeWitness = try XCTUnwrap(native)
            witness = nativeWitness
            if warmViewportHeight != 80 {
                XCTAssertFalse(hasSecondList)
                try Self.assertWarmRequiredRowsCoverOrdinaryPrefetch(in: host, list: warmList, target: nativeWitness)
                host.runtime.root.frame.size.height = 80
            }
            host.reload()
            list = try host.list()
            scroll = try host.scrollContainer()
        } catch {
            host.close()
            throw error
        }
        runtime.recordsLazyListUIAPhasesForTesting = true
        runtime.root.onLayout = { [weak self] _ in
            guard let self, self.probe.correctionCalls == 0, self.isCorrectionBoundary else { return }
            self.probe.correctionCalls += 1
            self.probe.correctionTrace = self.trace
            self.onCorrection?(self)
        }
    }

    func realize() -> Bool { source.uiaRealizeVirtualizedItem(elementID: element) }

    @inline(never)
    private static func assertWarmRequiredRowsCoverOrdinaryPrefetch(
        in host: MountedLazyListTestHost, list: ViewNode, target: RetainedLazyListAccessibilityItem
    ) throws {
        let runtime = host.runtime
        let scroll = try host.scrollContainer()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertEqual(runtime.root.resolvedFrame.height, 160)
        XCTAssertEqual(scroll.resolvedFrame.height, 160)
        XCTAssertEqual(scroll.scrollOffset, 0)
        XCTAssertEqual(list.resolvedFrame.origin.y, 0)
        let rows = list.children.filter { !$0.isHidden && !$0.isSeparatorRule && $0.retainedLazyListGap == nil }
        XCTAssertGreaterThan(rows.count, 6)
        let firstSix = Array(rows.prefix(6))
        let visible = rows.filter { $0.resolvedFrame.maxY > 0 && $0.resolvedFrame.minY < scroll.resolvedFrame.height }
        XCTAssertEqual(visible.map(ObjectIdentifier.init), firstSix.map(ObjectIdentifier.init))
        XCTAssertEqual(firstSix.count, 6)
        for row in firstSix {
            XCTAssertTrue(row.parent === list && row.retainedLazyListRuntime === runtime)
            XCTAssertEqual(row.lastLayoutVisitPassID, runtime.layoutPassID)
            XCTAssertFalse(row.isLayoutDeferredByVirtualization)
            let token = try XCTUnwrap(adapter.mountedToken(containing: row))
            XCTAssertEqual(adapter.knownLeafCount(for: token), 2)
            let bounds = try XCTUnwrap(adapter.logicalBounds(for: token))
            XCTAssertLessThan(bounds.origin, 160)
            XCTAssertGreaterThan(bounds.origin + bounds.extent, 0)
        }
        // DeferredList derives prefetch from its estimate. Read that estimate
        // from a real cold token; no provider call or viewport plan is needed.
        XCTAssertNil(adapter.mountedNodes(for: target.token))
        XCTAssertNil(adapter.knownLeafCount(for: target.token))
        let estimate = try XCTUnwrap(adapter.logicalBounds(for: target.token)).extent
        XCTAssertEqual(estimate, 31)
        let ordinaryEnd = 80 + min(256, max(64, estimate * 3))
        let sixth = try XCTUnwrap(firstSix.last)
        let sixthToken = try XCTUnwrap(adapter.mountedToken(containing: sixth))
        let sixthBounds = try XCTUnwrap(adapter.logicalBounds(for: sixthToken))
        let seventh = try XCTUnwrap(rows.dropFirst(6).first)
        let seventhToken = try XCTUnwrap(adapter.mountedToken(containing: seventh))
        let seventhBounds = try XCTUnwrap(adapter.logicalBounds(for: seventhToken))
        XCTAssertLessThan(sixthBounds.origin, ordinaryEnd)
        XCTAssertGreaterThanOrEqual(sixthBounds.origin + sixthBounds.extent, ordinaryEnd)
        XCTAssertGreaterThanOrEqual(seventhBounds.origin, ordinaryEnd)
        // Native selection makes these six visible, measured records required.
        // Replacement carries that cohort; shrinking to 80 cannot turn its
        // already-required rows into new optional factory work.
    }

    /// Stop before target demand, under the same default four-round allowance.
    /// Inspect the ordinary preparation's trace and receipt before owed cleanup.
    func withPreparation(_ inspect: (RetainedLazyListUIARequest?) throws -> Void) throws {
        XCTAssertTrue(runtime.isLazyListAccessibilityTokenCurrent(witness.token, in: witness))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        try runtime.withLazyListResolutionBudget {
            let request = runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation)
            defer { if let request { runtime.finishLazyListUIARequest(request) } }
            XCTAssertFalse(trace.contains { $0.kind == .resumedProviderPhase || $0.kind == .ownedScroll })
            try inspect(request)
        }
    }

    func close() {
        onCorrection = nil
        runtime.root.onLayout = nil
        host.close()
    }
}

private enum MeasurementCorrectionFixtureError: Error { case missingItem }

@MainActor
private final class MeasurementCorrectionProbe {
    let rows = Array(0..<100)
    weak var runtime: RetainedViewRuntime?
    var factories: [Int] = []
    var targetFactoryRounds: [Int] = []
    var activations: [Int] = []
    var correctionCalls = 0
    var correctionTrace: [RetainedViewRuntime.LazyListUIAPhaseTrace]?

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        if id == MeasurementCorrectionFixture.targetIndex {
            targetFactoryRounds.append(runtime?.lazyListUIAPhasesForTesting.last?.consumedRounds ?? 0)
        }
        return [AnyView(Button("Row \(id)") { [weak self] in self?.activations.append(id) }.frame(height: 24))]
    }
}

@MainActor
private final class MeasurementCorrectionReaderProbe {
    var expandsSlot = false
    var calls = 0
    var rounds: [Int] = []

    func makeNode(builtSize: Size) -> ViewNode {
        let node = makeLayoutNode()
        node.geometryReaderBuiltSize = builtSize
        node.geometryReaderBuild = { [weak self] runtime, _ in
            guard let self else { return [] }
            self.calls += 1
            self.rounds.append(runtime.lazyListUIAPhasesForTesting.last?.consumedRounds ?? 0)
            return [self.makeLayoutNode()]
        }
        return node
    }

    private func makeLayoutNode() -> ViewNode {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 20), preferredSize: Size(width: 120, height: 20))
        node.onLayoutWithNode = { [weak self] node, _ in
            if self?.expandsSlot == true { node.resolvedFrame.size.height = 40 }
        }
        return node
    }
}

private struct MeasurementCorrectionNodeBits: Equatable {
    let node: ObjectIdentifier
    let frame: Rect
    let preferredSize: Size?
    let constraints: LayoutConstraints?
    let children: [ObjectIdentifier]
    let flags: DirtyFlags

    @MainActor static func capture(in runtime: RetainedViewRuntime) -> [Self] {
        MountedLazyListTestHost.descendants(in: runtime.root).map {
            Self(
                node: ObjectIdentifier($0), frame: $0.frame, preferredSize: $0.preferredSize,
                constraints: $0.layoutConstraints, children: $0.children.map(ObjectIdentifier.init),
                flags: $0.subtreeDirtyFlags)
        }
    }
}

@MainActor
private final class MeasurementCorrectionProviderProbe {
    var calls = 0
    var factoryCount: Int?
    var childIDs: [ObjectIdentifier]?
}

@MainActor
private final class MeasurementCorrectionRecordingLease: RetainedSubtreeBuildLease {
    private let base: any RetainedSubtreeBuildLease
    private weak var fixture: MeasurementCorrectionFixture?
    private let decliningRound: Int?
    var canBuildRounds: [Int] = []
    var beginRounds: [Int] = []
    var secondRoundBits: [MeasurementCorrectionNodeBits]?

    init(base: any RetainedSubtreeBuildLease, fixture: MeasurementCorrectionFixture, decliningRound: Int? = nil) {
        self.base = base
        self.fixture = fixture
        self.decliningRound = decliningRound
    }

    var canBuild: Bool {
        let round = fixture?.trace.last?.consumedRounds ?? 0
        canBuildRounds.append(round)
        if let fixture, fixture.trace.last?.consumedRounds == 2 {
            secondRoundBits = MeasurementCorrectionNodeBits.capture(in: fixture.runtime)
        }
        let permitted = base.canBuild
        return permitted && round != decliningRound
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        beginRounds.append(fixture?.trace.last?.consumedRounds ?? 0)
        return base.beginBuild()
    }
}
