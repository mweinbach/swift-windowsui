import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Physical eligibility is deliberately weaker than settled geometry. These
/// controls keep the original action, work budget, and final focus contract.
@MainActor
final class LazyListKeyboardPreparationTests: XCTestCase {
    private static let down = KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue)
    private static let up = KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue)

    func testDefaultBudgetNavigatesFarDownAndBackUpWithoutAnotherAttempt() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        let handler = try XCTUnwrap(try fixture.row(0).onKeyDown)
        XCTAssertNil(fixture.findRow(899))
        XCTAssertNil(fixture.findRow(900))
        var setterSawAcceptedUnsettledTarget = false
        fixture.probe.onSet = { [weak fixture] in
            guard let fixture, let target = fixture.findRow(900) else {
                return XCTFail("The original setter needs an accepted actual destination")
            }
            XCTAssertTrue(target.parent === fixture.content)
            XCTAssertTrue(target.retainedLazyListRuntime === fixture.runtime)
            XCTAssertNotNil(target.listNavigationOwner)
            XCTAssertTrue(target.isFocusEnabled)
            XCTAssertFalse(target.isLayoutDeferredByVirtualization)
            XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
            XCTAssertFalse(target.isFocused)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            if case .unsettled = fixture.runtime.layoutSettlementStatus {
                setterSawAcceptedUnsettledTarget = true
            }
        }

        fixture.beginTrace()
        handler(Self.down)
        fixture.endTrace()

        XCTAssertTrue(setterSawAcceptedUnsettledTarget)
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertEqual(fixture.probe.selected, 900)
        let target = try fixture.row(900)
        XCTAssertTrue(fixture.runtime.focusedNode === target)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 20_000)
        XCTAssertEqual(fixture.focusedOrdinals, [900])
        XCTAssertEqual(fixture.focusWasDeferred, [false])
        assertOneBudget(fixture, rounds: 4, elements: 128)
        XCTAssertLessThan(fixture.adapter.mountedRecordCount, 40)

        fixture.probe.onSet = nil
        let returnHandler = try XCTUnwrap(target.onKeyDown)
        fixture.beginTrace()
        returnHandler(Self.up)
        fixture.endTrace()
        XCTAssertEqual(fixture.probe.writes, [900, 899])
        XCTAssertEqual(fixture.probe.selected, 899)
        let previous = try fixture.row(899)
        XCTAssertTrue(fixture.runtime.focusedNode === previous)
        XCTAssertFalse(previous.isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.focusedOrdinals, [900, 899])
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testAcceptedPhysicalEligibilityDoesNotGrantReadinessScrollOrFocus() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        let source = try fixture.row(0)
        let sourceOwner = try XCTUnwrap(source.listNavigationOwner)
        let scope = try XCTUnwrap(fixture.scroll.listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: sourceOwner))
        defer { receipt.cancelPreparedNavigation() }
        let first = try fixture.item(899)
        let second = try fixture.item(900)
        let preparation = try XCTUnwrap(
            fixture.runtime.beginLazyListKeyboardPreparation(from: first, toward: second, receipt: receipt))
        defer { fixture.runtime.endLazyListKeyboardPreparation(preparation) }
        var firstRoots: [ViewNode] = []
        var secondRoots: [ViewNode] = []
        fixture.beginTrace()
        fixture.runtime.withLazyListResolutionBudget {
            guard case .accepted(let roots) = fixture.runtime.prepareLazyListKeyboardItem(first, using: preparation)
            else {
                return XCTFail("The original selected row must have accepted physical eligibility")
            }
            firstRoots = roots
            let phaseCount = fixture.runtime.lazyListUIAPhasesForTesting.count
            guard case .accepted(let roots) = fixture.runtime.prepareLazyListKeyboardItem(second, using: preparation)
            else {
                return XCTFail("The same accepted cohort must include the adjacent destination")
            }
            secondRoots = roots
            XCTAssertEqual(fixture.runtime.lazyListUIAPhasesForTesting.count, phaseCount)
        }
        fixture.endTrace()
        XCTAssertEqual(
            firstRoots.map(ObjectIdentifier.init),
            fixture.adapter.mountedNodes(for: first.token)?.map(ObjectIdentifier.init))
        XCTAssertEqual(
            secondRoots.map(ObjectIdentifier.init),
            fixture.adapter.mountedNodes(for: second.token)?.map(ObjectIdentifier.init))
        let firstEligible = fixture.eligible(firstRoots, ordinal: 899)
        let secondEligible = fixture.eligible(secondRoots, ordinal: 900)
        XCTAssertEqual(firstEligible.count, 1)
        XCTAssertEqual(secondEligible.count, 1)
        XCTAssertTrue(firstEligible.first === fixture.findRow(899))
        XCTAssertTrue(secondEligible.first === fixture.findRow(900))
        XCTAssertTrue(receipt.permitsBindingWrite)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        XCTAssertNil(fixture.runtime.realizedLazyListAccessibilityNodes(for: second))
        guard case .unsettled = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("Eligibility must not fabricate a global settlement")
        }
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testRevokedOriginalDemandCannotReuseAcceptedPhysicalRows() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        let receipt = try XCTUnwrap(
            try XCTUnwrap(fixture.scroll.listNavigationOwner).prepareAction(
                from: try XCTUnwrap(try fixture.row(0).listNavigationOwner)))
        defer { receipt.cancelPreparedNavigation() }
        let first = try fixture.item(899)
        let second = try fixture.item(900)
        let preparation = try XCTUnwrap(
            fixture.runtime.beginLazyListKeyboardPreparation(from: first, toward: second, receipt: receipt))
        defer { fixture.runtime.endLazyListKeyboardPreparation(preparation) }
        fixture.runtime.withLazyListResolutionBudget {
            guard case .accepted = fixture.runtime.prepareLazyListKeyboardItem(first, using: preparation) else {
                return XCTFail("The revocation must follow actual accepted row construction")
            }
            XCTAssertNotNil(fixture.findRow(899))
            XCTAssertNotNil(fixture.findRow(900))
            fixture.runtime.releaseLazyListTarget(first)
            let calls = fixture.probe.factories
            let pass = fixture.runtime.layoutPassID
            guard case .obsolete = fixture.runtime.prepareLazyListKeyboardItem(second, using: preparation) else {
                return XCTFail("An ended original demand cannot refresh its preparation")
            }
            XCTAssertEqual(fixture.probe.factories, calls)
            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
        }
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertNil(fixture.runtime.focusedNode)
    }

    func testEmptyAndDisabledSelectedRowsKeepTheUnmatchedSelectionBoundary() async throws {
        for empty in [true, false] {
            let probe = KeyboardPreparationProbe()
            if empty { probe.empty.insert(899) } else { probe.disabled.insert(899) }
            let fixture = try KeyboardPreparationFixture(probe: probe)
            defer { fixture.close() }
            probe.selected = 899
            fixture.beginTrace()
            try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
            fixture.endTrace()
            XCTAssertEqual(probe.selected, 0)
            XCTAssertEqual(probe.writes, [0])
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.findRow(0))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.focusedOrdinals.contains(900))
            assertOneBudget(fixture, rounds: 4, elements: 128)
        }
    }

    func testMultipleImplicitLeavesDoNotInventADifferentSelectionTag() async throws {
        let probe = KeyboardPreparationProbe()
        probe.multiple.insert(899)
        let fixture = try KeyboardPreparationFixture(probe: probe)
        defer { fixture.close() }
        probe.selected = 899
        fixture.beginTrace()
        try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
        fixture.endTrace()
        let leaves = fixture.eligible(fixture.content.children, ordinal: 899)
        XCTAssertEqual(leaves.count, 2)
        XCTAssertEqual(
            leaves.compactMap { DeferredListRowNavigation.attached(to: $0)?.tag }, [899, 899].map(AnyHashable.init))
        XCTAssertEqual(probe.selected, 899)
        XCTAssertTrue(probe.writes.isEmpty)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testRevocationInEitherCandidateFactoryStopsTheOriginalPreparation() async throws {
        for trigger in [899, 900] {
            let fixture = try KeyboardPreparationFixture()
            defer { fixture.close() }
            fixture.probe.selected = 899
            var hits = 0
            var factoryCountAtRevocation = 0
            fixture.probe.onFactory = { [weak fixture] ordinal in
                guard let fixture, ordinal == trigger, hits == 0 else { return }
                hits += 1
                factoryCountAtRevocation = fixture.probe.factories.count
                fixture.runtime.requestFocus(fixture.alternate)
            }
            fixture.beginTrace()
            try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
            fixture.endTrace()
            XCTAssertEqual(hits, 1)
            XCTAssertEqual(fixture.probe.factories.count, factoryCountAtRevocation)
            XCTAssertTrue(fixture.probe.writes.isEmpty)
            XCTAssertEqual(fixture.probe.selected, 899)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.focusedOrdinals.contains(900))
            assertOneBudget(fixture, rounds: 4, elements: 128)
        }
    }

    func testFactoryCaptureCleanupCannotAdmitTheNextCandidate() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        let lifetime = KeyboardPreparationLifetime()
        installFactoryCleanup(on: fixture, lifetime: lifetime)
        XCTAssertNotNil(lifetime.payload)
        fixture.beginTrace()
        try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
        fixture.endTrace()
        XCTAssertEqual(lifetime.releases, 1)
        XCTAssertNil(lifetime.payload)
        XCTAssertTrue(fixture.tracedFactories.contains(899))
        XCTAssertFalse(fixture.tracedFactories.contains(900))
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testAcceptedRootReplacementDuringPreparationCannotTakeTheOldBinding() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        let originalSource = try fixture.row(0)
        let originalScope = try XCTUnwrap(fixture.scroll.listNavigationOwner)
        var replacements = 0
        fixture.probe.onFactory = { [weak fixture] ordinal in
            guard let fixture, ordinal == 899, replacements == 0 else { return }
            replacements += 1
            fixture.host.reload()
        }
        let completed = fixture.host.events.rootCompletions
        fixture.beginTrace()
        try XCTUnwrap(originalSource.onKeyDown)(Self.down)
        fixture.endTrace()
        XCTAssertEqual(replacements, 1)
        XCTAssertEqual(fixture.host.events.rootCompletions, completed + 1)
        XCTAssertTrue(fixture.findRow(0) === originalSource)
        XCTAssertFalse(fixture.scroll.listNavigationOwner === originalScope)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertEqual(fixture.probe.selected, 899)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.focusedOrdinals.contains(900))
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testMeasurementCorrectionRevocationCannotPublishRevealOrFocus() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        var corrections = 0
        fixture.runtime.root.onLayout = { [weak fixture] _ in
            guard let fixture, corrections == 0, fixture.probe.writes == [900],
                fixture.runtime.lazyListUIAPhasesForTesting.suffix(2).map(\.kind) == [.measurementPhase, .layoutPass]
            else { return }
            corrections += 1
            XCTAssertNotNil(fixture.findRow(900))
            XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
            fixture.runtime.requestFocus(fixture.alternate)
        }
        fixture.beginTrace()
        try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
        fixture.endTrace()
        XCTAssertEqual(corrections, 1)
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.focusedOrdinals.contains(900))
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testRetiringTheTemporaryPredecessorStillRunsItsPayloadCleanup() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        let lifetime = KeyboardPreparationLifetime()
        var installations = 0
        fixture.runtime.root.onLayout = { [weak fixture] _ in
            guard let fixture, installations == 0, fixture.probe.writes == [900],
                fixture.runtime.lazyListUIAPhasesForTesting.suffix(2).map(\.kind) == [.providerPhase, .layoutPass],
                let first = fixture.content.children.compactMap({ node -> (ViewNode, Int)? in
                    guard let row = DeferredListRowNavigation.attached(to: node), row.ordinal > 800 else { return nil }
                    return (node, row.ordinal)
                }).min(by: { $0.1 < $1.1 }), first.1 < 899
            else { return }
            installations += 1
            self.installRetiringPayload(on: first.0, in: fixture, lifetime: lifetime)
        }
        fixture.beginTrace()
        try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
        fixture.endTrace()
        XCTAssertEqual(installations, 1)
        XCTAssertEqual(lifetime.releases, 1)
        XCTAssertTrue(lifetime.releasedAfterDeparture)
        XCTAssertNil(lifetime.payload)
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.focusedOrdinals.contains(900))
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testSetterDeletionAndSameKeyReinsertionDoNotReviveTheOriginalTarget() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        let original = try fixture.item(900)
        var absences = 0
        fixture.probe.onSet = { [weak fixture] in
            guard let fixture else { return }
            XCTAssertNotNil(fixture.findRow(900))
            fixture.probe.rows.removeAll { $0 == 900 }
            fixture.host.reload()
            XCTAssertFalse(fixture.runtime.isLazyListAccessibilityTokenCurrent(original.token, in: original))
            absences += 1
            fixture.probe.rows.insert(900, at: 900)
            fixture.host.reload()
        }
        fixture.beginTrace()
        try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
        fixture.endTrace()
        XCTAssertEqual(absences, 1)
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertFalse(fixture.runtime.isLazyListAccessibilityTokenCurrent(original.token, in: original))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.focusedOrdinals.contains(900))
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testSetterPhysicalDepartureReparentingAndRoleABARejectTheOriginalTarget() async throws {
        for mutation in 0..<4 {
            let fixture = try KeyboardPreparationFixture()
            defer { fixture.close() }
            fixture.probe.selected = 899
            var changes = 0
            var oldHandler: ((KeyboardEvent) -> Void)?
            fixture.probe.onSet = { [weak fixture] in
                guard let fixture, let target = fixture.findRow(900) else { return XCTFail("Missing actual target") }
                changes += 1
                oldHandler = target.onKeyDown
                if mutation == 0 {
                    target.removeFromParent()
                } else if mutation == 1 {
                    let order = fixture.content.children
                    target.removeFromParent()
                    fixture.content.setChildren(order)
                } else if mutation == 2 {
                    target.removeFromParent()
                    fixture.alternate.addChild(target)
                } else {
                    target.isFocusEnabled = false
                    target.isFocusEnabled = true
                }
            }
            fixture.beginTrace()
            try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
            fixture.endTrace()
            XCTAssertEqual(changes, 1)
            XCTAssertEqual(fixture.probe.writes, [900])
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.focusedOrdinals.contains(900))
            let reads = fixture.probe.reads
            let calls = fixture.probe.factories
            try XCTUnwrap(oldHandler)(Self.down)
            XCTAssertEqual(fixture.probe.reads, reads)
            XCTAssertEqual(fixture.probe.factories, calls)
            XCTAssertEqual(fixture.probe.writes, [900])
            assertOneBudget(fixture, rounds: 4, elements: 128)
        }
    }

    func testInsufficientFutureViewportCoverageCannotGrantFocus() async throws {
        let probe = KeyboardPreparationProbe()
        probe.coldHeight = 1
        // A positive public override lowers the actual row minimum. Zero
        // would retain chrome's 30-point fallback. The native estimate still
        // uses max(1, chrome 30) plus its hairline; actual content is 1 + 12.
        probe.minimumRowHeight = 1
        let fixture = try KeyboardPreparationFixture(probe: probe)
        defer { fixture.close() }
        probe.selected = 899
        fixture.beginTrace()
        try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
        fixture.endTrace()
        XCTAssertEqual(probe.writes, [900])
        XCTAssertNotNil(fixture.findRow(900))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.focusedOrdinals.contains(900))
        XCTAssertFalse(fixture.findRow(900)?.isFocused == true)
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testAnInvalidatedPostSetterHandoffCannotPerformAnotherQuery() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        let receipt = try XCTUnwrap(
            try XCTUnwrap(fixture.scroll.listNavigationOwner).prepareAction(
                from: try XCTUnwrap(try fixture.row(0).listNavigationOwner)))
        defer { receipt.cancelPreparedNavigation() }
        let first = try fixture.item(899)
        let second = try fixture.item(900)
        let preparation = try XCTUnwrap(
            fixture.runtime.beginLazyListKeyboardPreparation(from: first, toward: second, receipt: receipt))
        defer { fixture.runtime.endLazyListKeyboardPreparation(preparation) }
        fixture.beginTrace()
        fixture.runtime.withLazyListResolutionBudget {
            guard case .accepted = fixture.runtime.prepareLazyListKeyboardItem(second, using: preparation),
                let target = fixture.findRow(900), let owner = target.listNavigationOwner
            else { return XCTFail("Actual eligibility must precede the handoff control") }
            XCTAssertTrue(receipt.prepareTarget(owner, requiresRevealBeforeFocus: true))
            XCTAssertTrue(fixture.runtime.prepareLazyListKeyboardSelection(second, using: preparation))
            fixture.probe.selected = 900
            fixture.host.reload()
            guard case .ready = receipt.settlePreparedTarget() else {
                return XCTFail("The stale-proof control needs an actual completed post-setter settlement")
            }
            guard case .settled(let settlement) = fixture.runtime.layoutSettlementStatus else {
                return XCTFail("No post-setter settlement")
            }
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(settlement))
            fixture.runtime.root.frame = Rect(x: 0, y: 0, width: 261, height: 230)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(settlement))
            let pass = fixture.runtime.layoutPassID
            let factories = fixture.probe.factories
            XCTAssertFalse(receipt.finishNavigation())
            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
            XCTAssertEqual(fixture.probe.factories, factories)
        }
        fixture.endTrace()
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testPostRevealRevocationPreservesTheAcceptedOffsetAndRejectsFocus() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        var offsets: [Double] = []
        fixture.runtime.root.onLayout = { [weak fixture] _ in
            guard let fixture, offsets.isEmpty, fixture.scroll.scrollOffset > 20_000 else { return }
            offsets.append(fixture.scroll.scrollOffset)
            fixture.runtime.requestFocus(fixture.alternate)
        }
        fixture.beginTrace()
        try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
        fixture.endTrace()
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertEqual(offsets.count, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, try XCTUnwrap(offsets.first), accuracy: 0.0001)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
        XCTAssertFalse(fixture.focusedOrdinals.contains(900))
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testOneElementOneRoundCannotSelectAnUnacceptedCandidateAndCloseReleasesTheRequest() async throws {
        let lifetime = KeyboardPreparationLifetime()
        var fixture: KeyboardPreparationFixture? = try makeLifetimeFixture(lifetime)
        weak var weakProbe = fixture?.probe
        let runtime = try XCTUnwrap(fixture?.runtime)
        let probe = try XCTUnwrap(fixture?.probe)
        probe.selected = 899
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        var handler = try XCTUnwrap(try XCTUnwrap(fixture).row(0).onKeyDown) as ((KeyboardEvent) -> Void)?
        fixture?.beginTrace()
        handler?(Self.down)
        fixture?.endTrace()
        XCTAssertGreaterThan(probe.reads, 0)
        XCTAssertEqual(probe.selected, 899)
        XCTAssertTrue(probe.writes.isEmpty)
        XCTAssertNil(fixture?.findRow(900))
        XCTAssertNil(runtime.focusedNode)
        XCTAssertEqual(fixture?.scroll.scrollOffset, 0)
        assertOneBudget(try XCTUnwrap(fixture), rounds: 1, elements: 1)
        fixture?.close()
        let reads = probe.reads
        let factories = probe.factories
        handler?(Self.down)
        XCTAssertEqual(probe.reads, reads)
        XCTAssertEqual(probe.factories, factories)
        XCTAssertTrue(probe.writes.isEmpty)
        handler = nil
        fixture = nil
        XCTAssertNotNil(weakProbe, "This local probe does not own the separately captured binding payload")
        XCTAssertNil(lifetime.payload)
        XCTAssertEqual(lifetime.releases, 1)
    }

    func testWarmPrefetchedOffscreenDestinationKeepsFocusBeforeItsOrdinaryReveal() async throws {
        let probe = KeyboardPreparationProbe()
        probe.rows = Array(0..<8)
        let fixture = try KeyboardPreparationFixture(probe: probe)
        defer { fixture.close() }
        probe.selected = 6
        let source = try fixture.row(0)
        let destination = try fixture.row(7)
        XCTAssertNotNil(fixture.runtime.realizedLazyListAccessibilityNodes(for: try fixture.item(6)))
        XCTAssertNotNil(fixture.runtime.realizedLazyListAccessibilityNodes(for: try fixture.item(7)))
        XCTAssertFalse(destination.isLayoutDeferredByVirtualization)
        XCTAssertGreaterThan(destination.resolvedFrame.minY, fixture.scroll.resolvedFrame.height)
        let previousFocusCallback = fixture.runtime.onAccessibilityFocusChanged
        var focusOffsets: [Double] = []
        fixture.runtime.onAccessibilityFocusChanged = { [weak fixture] node in
            previousFocusCallback?(node)
            guard let fixture, node === destination else { return }
            focusOffsets.append(fixture.scroll.scrollOffset)
        }

        fixture.beginTrace()
        try XCTUnwrap(source.onKeyDown)(Self.down)
        fixture.endTrace()
        XCTAssertEqual(probe.writes, [7])
        assertOneBudget(fixture, rounds: 4, elements: 128)
        // The existing warm route may defer its reveal until render consumes
        // layout flags. These are ordinary frames, never another key or query.
        for _ in 0..<4 where fixture.scroll.scrollOffset == 0 {
            fixture.host.render()
        }
        XCTAssertEqual(probe.writes, [7])
        XCTAssertEqual(focusOffsets, [0])
        XCTAssertTrue(fixture.runtime.focusedNode === destination)
        XCTAssertTrue(destination.parent === fixture.content)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0)
        XCTAssertLessThan(
            destination.resolvedFrame.minY - fixture.scroll.scrollOffset, fixture.scroll.resolvedFrame.height)
        XCTAssertGreaterThan(destination.resolvedFrame.maxY - fixture.scroll.scrollOffset, 0)
    }

    func testPendingEligibilityContinuesOnlyThroughOrdinaryFramesWithItsOriginalAction() async throws {
        let diagnosticStart = ContinuousClock.now
        let diagnosticURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent(
                "keyboard-progress-pending-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).log")
        try Data().write(to: diagnosticURL, options: .withoutOverwriting)
        let diagnosticFile = try FileHandle(forWritingTo: diagnosticURL)
        defer { try? diagnosticFile.close() }
        func diagnosticProgress(_ phase: String, frame: Int, factories: Int, writes: Int, snapshot: String = "") throws
        {
            try diagnosticFile.write(
                contentsOf: Data(
                    "[keyboard-progress] phase=\(phase) frame=\(frame) elapsed=\(diagnosticStart.duration(to: ContinuousClock.now)) factories=\(factories) writes=\(writes) \(snapshot)\n"
                        .utf8))
        }
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        try diagnosticProgress(
            "fixture-ready", frame: -1, factories: fixture.probe.factories.count, writes: fixture.probe.writes.count)
        fixture.probe.selected = 899
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        fixture.beginTrace()
        try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
        try diagnosticProgress(
            "key-return", frame: -1, factories: fixture.probe.factories.count, writes: fixture.probe.writes.count)
        fixture.endTrace()
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertNil(fixture.findRow(900))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        assertOneBudget(fixture, rounds: 1, elements: 1)
        let original = try XCTUnwrap(fixture.adapter.keyboardPreparation)

        // Keep the same limits for every ordinary frame. No further key,
        // explicit resolution query, or larger replacement budget is supplied.
        for diagnosticFrame in 0..<64
        where fixture.runtime.focusedNode !== fixture.findRow(900) || fixture.findRow(900) == nil {
            let calls = fixture.probe.factories.count
            try diagnosticProgress(
                "before-render", frame: diagnosticFrame, factories: fixture.probe.factories.count,
                writes: fixture.probe.writes.count)
            fixture.host.render()
            try diagnosticProgress(
                "after-render", frame: diagnosticFrame, factories: fixture.probe.factories.count,
                writes: fixture.probe.writes.count,
                snapshot: fixture.runtime.keyboardProgressSnapshotForTesting(
                    preparation: original, adapter: fixture.adapter))
            XCTAssertLessThanOrEqual(fixture.probe.factories.count - calls, 1)
            if let pending = fixture.adapter.keyboardPreparation { XCTAssertTrue(pending === original) }
        }
        try diagnosticProgress(
            "checks-enter", frame: -1, factories: fixture.probe.factories.count, writes: fixture.probe.writes.count)
        XCTAssertEqual(fixture.probe.writes, [900])
        let target = try fixture.row(900)
        XCTAssertTrue(fixture.runtime.focusedNode === target)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.focusedOrdinals, [900])
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 20_000)
        XCTAssertNil(fixture.adapter.keyboardPreparation)
        XCTAssertEqual(fixture.runtime.lazyListResolutionBudgetConfiguration.elementLimit, 1)
        XCTAssertEqual(fixture.runtime.lazyListResolutionBudgetConfiguration.roundLimit, 1)
        try diagnosticProgress(
            "checks-return", frame: -1, factories: fixture.probe.factories.count, writes: fixture.probe.writes.count)
    }

    func testPendingAfterTheSingleWriteUsesOrdinarySettlementWithoutRepeatingTheSetter() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 1))
        fixture.beginTrace()
        try XCTUnwrap(try fixture.row(0).onKeyDown)(Self.down)
        fixture.endTrace()
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertNotNil(fixture.findRow(900))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.focusedOrdinals.contains(900))
        assertOneBudget(fixture, rounds: 1, elements: 128)
        let original = try XCTUnwrap(fixture.adapter.keyboardPreparation)

        for _ in 0..<8 where fixture.runtime.focusedNode !== fixture.findRow(900) || fixture.findRow(900) == nil {
            fixture.host.render()
            XCTAssertEqual(fixture.probe.writes, [900])
            if let pending = fixture.adapter.keyboardPreparation { XCTAssertTrue(pending === original) }
        }
        let target = try fixture.row(900)
        XCTAssertTrue(fixture.runtime.focusedNode === target)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.focusedOrdinals, [900])
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 20_000)
        XCTAssertNil(fixture.adapter.keyboardPreparation)
        XCTAssertEqual(fixture.runtime.lazyListResolutionBudgetConfiguration.roundLimit, 1)
    }

    func testInterveningOrdinaryCallbackCannotLendAReplacementSourceToPendingEligibility() async throws {
        let diagnosticStart = ContinuousClock.now
        let diagnosticURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent(
                "keyboard-progress-intervening-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).log")
        try Data().write(to: diagnosticURL, options: .withoutOverwriting)
        let diagnosticFile = try FileHandle(forWritingTo: diagnosticURL)
        defer { try? diagnosticFile.close() }
        func diagnosticProgress(_ phase: String, frame: Int, factories: Int, writes: Int, snapshot: String = "") throws
        {
            try diagnosticFile.write(
                contentsOf: Data(
                    "[keyboard-progress] phase=\(phase) frame=\(frame) elapsed=\(diagnosticStart.duration(to: ContinuousClock.now)) factories=\(factories) writes=\(writes) \(snapshot)\n"
                        .utf8))
        }
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        try diagnosticProgress(
            "fixture-ready", frame: -1, factories: fixture.probe.factories.count, writes: fixture.probe.writes.count)
        fixture.probe.selected = 899
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        let handler = try XCTUnwrap(try fixture.row(0).onKeyDown)
        let originalScope = try XCTUnwrap(fixture.scroll.listNavigationOwner)
        fixture.beginTrace()
        handler(Self.down)
        try diagnosticProgress(
            "key-return", frame: -1, factories: fixture.probe.factories.count, writes: fixture.probe.writes.count)
        fixture.endTrace()
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        assertOneBudget(fixture, rounds: 1, elements: 1)
        let original = try XCTUnwrap(fixture.adapter.keyboardPreparation)
        var scheduled = false
        var replacements = 0
        fixture.runtime.root.onLayout = { [weak fixture] _ in
            guard let fixture, !scheduled, fixture.probe.writes.isEmpty,
                fixture.adapter.keyboardPreparation === original,
                original.cohort.allSatisfy({ fixture.adapter.mountedNodes(for: $0) != nil })
            else { return }
            scheduled = true
            fixture.runtime.scheduleAfterLayout(key: "keyboard.preparation.intervening-source") { [weak fixture] in
                guard let fixture else { return }
                XCTAssertNotNil(fixture.findRow(899))
                XCTAssertNotNil(fixture.findRow(900))
                XCTAssertTrue(fixture.probe.writes.isEmpty)
                replacements += 1
                fixture.host.reload()
            }
        }
        for diagnosticFrame in 0..<64 where replacements == 0 {
            try diagnosticProgress(
                "before-render", frame: diagnosticFrame, factories: fixture.probe.factories.count,
                writes: fixture.probe.writes.count)
            fixture.host.render()
            try diagnosticProgress(
                "after-render", frame: diagnosticFrame, factories: fixture.probe.factories.count,
                writes: fixture.probe.writes.count,
                snapshot: fixture.runtime.keyboardProgressSnapshotForTesting(
                    preparation: original, adapter: fixture.adapter))
        }
        try diagnosticProgress(
            "checks-enter", frame: -1, factories: fixture.probe.factories.count, writes: fixture.probe.writes.count)
        XCTAssertTrue(scheduled)
        XCTAssertEqual(replacements, 1)
        XCTAssertFalse(fixture.scroll.listNavigationOwner === originalScope)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.focusedOrdinals.contains(900))
        let reads = fixture.probe.reads
        let factories = fixture.probe.factories
        handler(Self.down)
        XCTAssertEqual(fixture.probe.reads, reads)
        XCTAssertEqual(fixture.probe.factories, factories)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertEqual(fixture.runtime.lazyListResolutionBudgetConfiguration.elementLimit, 1)
        XCTAssertEqual(fixture.runtime.lazyListResolutionBudgetConfiguration.roundLimit, 1)
        try diagnosticProgress(
            "checks-return", frame: -1, factories: fixture.probe.factories.count, writes: fixture.probe.writes.count)
    }

    func testAnimatedAdoptionCannotRestoreTheOriginalTargetsRevokedRowRole() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        weak var originalTarget: ViewNode?
        var oldHandler: ((KeyboardEvent) -> Void)?
        var changes = 0
        var roleWasRestored = false
        fixture.probe.onSet = { [weak fixture] in
            guard let fixture, let target = fixture.findRow(900) else {
                return XCTFail("The setter must receive the original accepted destination")
            }
            XCTAssertEqual(fixture.probe.writes, [900])
            XCTAssertTrue(target.isFocusEnabled)
            XCTAssertNil(target.backgroundColor)
            originalTarget = target
            oldHandler = target.onKeyDown
        }
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture, let target = originalTarget, changes == 0,
                fixture.probe.writes == [900], fixture.runtime.hasActiveRetainedBuild,
                target.backgroundColor == .clear
            else { return 0 }
            // The selected fill adopts onto the original physical 900. Its
            // animation starts from clear while the incoming owner is still
            // between adopt and finishAdoption; this is not the setter itself.
            changes += 1
            target.isFocusEnabled = false
            target.isFocusEnabled = true
            roleWasRestored = target.isFocusEnabled
            return 0
        }
        let handler = try XCTUnwrap(try fixture.row(0).onKeyDown)
        fixture.beginTrace()
        withAnimation(.linear(duration: 0.6)) { handler(Self.down) }
        fixture.endTrace()
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(roleWasRestored)
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.focusedOrdinals.contains(900))
        let reads = fixture.probe.reads
        let calls = fixture.probe.factories
        try XCTUnwrap(oldHandler)(Self.down)
        XCTAssertEqual(fixture.probe.reads, reads)
        XCTAssertEqual(fixture.probe.factories, calls)
        XCTAssertEqual(fixture.probe.writes, [900])
        assertOneBudget(fixture, rounds: 4, elements: 128)
    }

    func testOrdinaryManagedReaderPublicationSurvivesRejectedKeyboardEgress() async throws {
        let fixture = try KeyboardPreparationReaderFixture()
        defer { fixture.close() }
        fixture.armReaderRebuild()
        installReaderRetirement(on: fixture)
        let factories = fixture.rows.factories.count
        fixture.runtime.recordsLazyListUIAPhasesForTesting = true
        try XCTUnwrap(try fixture.sourceRow().onKeyDown)(Self.down)
        fixture.runtime.recordsLazyListUIAPhasesForTesting = false

        XCTAssertEqual(fixture.readerProbe.armedBodies, 1)
        XCTAssertEqual(fixture.readerProbe.releases, 1)
        XCTAssertTrue(fixture.readerProbe.releasedDuringBuild)
        XCTAssertNil(fixture.readerProbe.payload)
        XCTAssertEqual(fixture.readerProbe.committedEpochs, [true])
        XCTAssertNil(fixture.readerProbe.epoch)
        XCTAssertTrue(fixture.reader.retainedLazyListRuntime === fixture.runtime)
        XCTAssertNotNil(fixture.reader.parent)
        XCTAssertTrue(MountedLazyListTestHost.descendants(in: fixture.reader).contains { $0.text == "Reader 1: 41" })
        assertReaderRequestStopped(fixture, startingFactories: factories)
    }

    func testOrdinaryRawReaderCommitsOnlyItsActualPublicationAfterKeyboardRevocation() async throws {
        for revokeBeforeReturn in [false, true] {
            let fixture = try KeyboardPreparationReaderFixture()
            defer { fixture.close() }
            let lease = KeyboardPreparationReaderLease()
            fixture.installRawReader(lease: lease, revokeBeforeReturn: revokeBeforeReturn)
            fixture.armReaderRebuild()
            installReaderRetirement(on: fixture)
            let factories = fixture.rows.factories.count
            fixture.runtime.recordsLazyListUIAPhasesForTesting = true
            try XCTUnwrap(try fixture.sourceRow().onKeyDown)(Self.down)
            fixture.runtime.recordsLazyListUIAPhasesForTesting = false

            XCTAssertEqual(fixture.readerProbe.armedBodies, 1)
            XCTAssertEqual(lease.begins, 1)
            XCTAssertEqual(lease.commits, revokeBeforeReturn ? 0 : 1)
            XCTAssertEqual(lease.abandons, revokeBeforeReturn ? 1 : 0)
            XCTAssertEqual(lease.finishes, 1)
            XCTAssertEqual(fixture.readerProbe.releases, revokeBeforeReturn ? 0 : 1)
            XCTAssertEqual(fixture.readerProbe.releasedDuringBuild, !revokeBeforeReturn)
            XCTAssertEqual(fixture.reader.onLayout == nil, !revokeBeforeReturn)
            let copied = MountedLazyListTestHost.descendants(in: fixture.reader).contains { $0.text == "Raw reader 1" }
            XCTAssertEqual(copied, !revokeBeforeReturn)
            XCTAssertTrue(fixture.reader.retainedLazyListRuntime === fixture.runtime)
            XCTAssertNotNil(fixture.reader.parent)
            assertReaderRequestStopped(fixture, startingFactories: factories)
        }
    }

    @inline(never)
    private func installReaderRetirement(on fixture: KeyboardPreparationReaderFixture) {
        let payload = KeyboardPreparationPayload { [weak fixture] in
            guard let fixture, fixture.readerProbe.isArmed else { return }
            fixture.readerProbe.releases += 1
            fixture.readerProbe.releasedDuringBuild = fixture.runtime.hasActiveRetainedBuild
            fixture.runtime.requestFocus(fixture.alternate)
        }
        fixture.readerProbe.payload = payload
        fixture.reader.onLayout = { [payload] _ in withExtendedLifetime(payload) {} }
    }

    private func assertReaderRequestStopped(
        _ fixture: KeyboardPreparationReaderFixture, startingFactories: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let runtime = fixture.runtime
        XCTAssertTrue(fixture.rows.writes.isEmpty, file: file, line: line)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0, file: file, line: line)
        XCTAssertTrue(runtime.focusedNode === fixture.alternate, file: file, line: line)
        XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
        XCTAssertNil(fixture.content.retainedLazyListAdapter?.keyboardPreparation, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.rows.factories.count - startingFactories, 128, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
        let phases = runtime.lazyListUIAPhasesForTesting
        XCTAssertEqual(phases.first?.remainingRounds, 4, file: file, line: line)
        XCTAssertEqual(phases.first?.remainingElements, 128, file: file, line: line)
        XCTAssertEqual(
            phases.filter { $0.kind == .roundDebit }.count, runtime.lastLazyListConsumedRounds, file: file, line: line)
        for (first, second) in zip(phases, phases.dropFirst()) {
            XCTAssertGreaterThanOrEqual(first.remainingRounds, second.remainingRounds, file: file, line: line)
            XCTAssertGreaterThanOrEqual(first.remainingElements, second.remainingElements, file: file, line: line)
        }
    }

    private func assertOneBudget(
        _ fixture: KeyboardPreparationFixture, rounds: Int, elements: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let phases = fixture.phases
        XCTAssertFalse(phases.isEmpty, file: file, line: line)
        XCTAssertLessThan(phases.count, 512, file: file, line: line)
        XCTAssertEqual(phases.first?.remainingRounds, rounds, file: file, line: line)
        XCTAssertEqual(phases.first?.remainingElements, elements, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, rounds, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, elements, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.tracedFactories.count, elements, file: file, line: line)
        for (first, second) in zip(phases, phases.dropFirst()) {
            XCTAssertGreaterThanOrEqual(first.remainingRounds, second.remainingRounds, file: file, line: line)
            XCTAssertGreaterThanOrEqual(first.remainingElements, second.remainingElements, file: file, line: line)
            XCTAssertLessThanOrEqual(first.consumedRounds, second.consumedRounds, file: file, line: line)
        }
        let debits = phases.filter { $0.kind == .roundDebit }
        XCTAssertEqual(debits.count, fixture.runtime.lastLazyListConsumedRounds, file: file, line: line)
        for debit in debits {
            let work = phases.filter { $0.consumedRounds == debit.consumedRounds }
            XCTAssertLessThanOrEqual(work.filter { $0.kind == .measurementPhase }.count, 1, file: file, line: line)
            XCTAssertLessThanOrEqual(work.filter { $0.kind == .readerPhase }.count, 1, file: file, line: line)
            XCTAssertLessThanOrEqual(work.filter { $0.kind == .providerPhase }.count, 1, file: file, line: line)
        }
    }

    @inline(never)
    private func installFactoryCleanup(on fixture: KeyboardPreparationFixture, lifetime: KeyboardPreparationLifetime) {
        let payload = KeyboardPreparationPayload { [weak fixture] in
            lifetime.releases += 1
            guard let fixture else { return XCTFail("Cleanup must run inside the original operation") }
            fixture.runtime.requestFocus(fixture.alternate)
        }
        lifetime.payload = payload
        fixture.probe.onFactory = { [weak probe = fixture.probe, payload] ordinal in
            guard ordinal == 899 else { return }
            probe?.onFactory = nil
            withExtendedLifetime(payload) {}
        }
    }

    @inline(never)
    private func installRetiringPayload(
        on node: ViewNode, in fixture: KeyboardPreparationFixture, lifetime: KeyboardPreparationLifetime
    ) {
        let payload = KeyboardPreparationPayload { [weak fixture, weak node] in
            lifetime.releases += 1
            lifetime.releasedAfterDeparture = node == nil || node?.parent == nil
            guard let fixture else { return XCTFail("Probe cleanup must precede operation completion") }
            fixture.runtime.requestFocus(fixture.alternate)
        }
        lifetime.payload = payload
        node.retainedPreferenceValues[ObjectIdentifier(KeyboardPreparationPayload.self)] = payload
    }

    @inline(never)
    private func makeLifetimeFixture(_ lifetime: KeyboardPreparationLifetime) throws -> KeyboardPreparationFixture {
        let payload = KeyboardPreparationPayload { lifetime.releases += 1 }
        lifetime.payload = payload
        return try KeyboardPreparationFixture(bindingPayload: payload)
    }
}

/// Root descriptor adoption retires the old List scope immediately; row
/// declarations refresh only when ordinary bounded construction rebuilds them.
@MainActor
final class LazyListKeyboardReplacementContinuationTests: XCTestCase {
    private static let down = KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue)

    func testRootReplacementRejectsEscapedHandlerBeforeAndAfterSettlementAndKeepsFreshNavigationUsable() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        let originalSource = try fixture.row(0)
        let originalOwner = try XCTUnwrap(originalSource.listNavigationOwner)
        let originalScope = try XCTUnwrap(fixture.scroll.listNavigationOwner)
        let oldHandler = try XCTUnwrap(originalSource.onKeyDown)
        var replacements = 0
        fixture.probe.onFactory = { [weak fixture] ordinal in
            guard let fixture, ordinal == 899, replacements == 0 else { return }
            replacements += 1
            fixture.host.reload()
        }
        let completed = fixture.host.events.rootCompletions

        fixture.beginTrace()
        oldHandler(Self.down)
        fixture.endTrace()
        XCTAssertEqual(replacements, 1)
        XCTAssertEqual(fixture.host.events.rootCompletions, completed + 1)
        XCTAssertTrue(fixture.findRow(0) === originalSource)
        XCTAssertFalse(fixture.scroll.listNavigationOwner === originalScope)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertEqual(fixture.probe.selected, 899)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        assertDefaultBudget(fixture)
        assertNoEffects(from: oldHandler, in: fixture)

        // This is a separate ordinary layout opportunity, not another key or
        // target query for the rejected original preparation.
        let factoriesBeforeSettlement = fixture.probe.factories.count
        for _ in 0..<16 {
            let factoriesBeforeFrame = fixture.probe.factories.count
            fixture.host.render()
            XCTAssertLessThanOrEqual(fixture.probe.factories.count - factoriesBeforeFrame, 128)
            XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128)
            XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
            if !fixture.runtime.isDirty { break }
        }
        XCTAssertFalse(fixture.runtime.isDirty)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        guard case .settled(let settlement) = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("Ordinary frames must settle the accepted replacement before its fresh action")
        }
        XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(settlement))
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        XCTAssertNil(fixture.adapter.keyboardPreparation)
        XCTAssertEqual(fixture.runtime.lazyListResolutionBudgetConfiguration.elementLimit, 128)
        XCTAssertEqual(fixture.runtime.lazyListResolutionBudgetConfiguration.roundLimit, 4)
        let refreshedSource = try fixture.row(0)
        XCTAssertTrue(refreshedSource === originalSource)
        XCTAssertTrue(fixture.probe.factories.dropFirst(factoriesBeforeSettlement).contains(0))
        XCTAssertFalse(refreshedSource.listNavigationOwner === originalOwner)
        XCTAssertTrue(fixture.probe.writes.isEmpty)
        XCTAssertEqual(fixture.probe.selected, 899)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        assertNoEffects(from: oldHandler, in: fixture)

        // A distinct current warm selection checks the replacement declaration,
        // without retrying the rejected far-row request or borrowing its budget.
        fixture.probe.selected = 0
        let freshHandler = try XCTUnwrap(refreshedSource.onKeyDown)
        fixture.beginTrace()
        freshHandler(Self.down)
        fixture.endTrace()
        assertDefaultBudget(fixture)
        XCTAssertEqual(fixture.probe.writes, [1])
        XCTAssertEqual(fixture.probe.selected, 1)
        // The existing warm route may finish its accepted setter's geometry
        // in ordinary frames. This sends no second key and repeats no setter.
        for _ in 0..<4 where fixture.runtime.focusedNode !== fixture.findRow(1) || fixture.findRow(1) == nil {
            let factoriesBeforeFrame = fixture.probe.factories.count
            fixture.host.render()
            XCTAssertEqual(fixture.probe.writes, [1])
            XCTAssertLessThanOrEqual(fixture.probe.factories.count - factoriesBeforeFrame, 128)
            XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128)
            XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        }
        let destination = try fixture.row(1)
        XCTAssertTrue(fixture.runtime.focusedNode === destination)
        XCTAssertEqual(fixture.focusedOrdinals, [1])
        XCTAssertFalse(destination.isLayoutDeferredByVirtualization)
        XCTAssertTrue(destination.parent === fixture.content)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        assertNoEffects(from: oldHandler, in: fixture)
    }

    private func assertNoEffects(
        from handler: (KeyboardEvent) -> Void, in fixture: KeyboardPreparationFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let reads = fixture.probe.reads
        let factories = fixture.probe.factories
        let writes = fixture.probe.writes
        let selected = fixture.probe.selected
        let focus = fixture.runtime.focusedNode
        let focusedOrdinals = fixture.focusedOrdinals
        let offset = fixture.scroll.scrollOffset
        let completions = fixture.host.events.rootCompletions
        let resolutions = fixture.runtime.lazyListResolveCount
        handler(Self.down)
        XCTAssertEqual(fixture.probe.reads, reads, file: file, line: line)
        XCTAssertEqual(fixture.probe.factories, factories, file: file, line: line)
        XCTAssertEqual(fixture.probe.writes, writes, file: file, line: line)
        XCTAssertEqual(fixture.probe.selected, selected, file: file, line: line)
        XCTAssertTrue(fixture.runtime.focusedNode === focus, file: file, line: line)
        XCTAssertEqual(fixture.focusedOrdinals, focusedOrdinals, file: file, line: line)
        XCTAssertEqual(fixture.scroll.scrollOffset, offset, file: file, line: line)
        XCTAssertEqual(fixture.host.events.rootCompletions, completions, file: file, line: line)
        XCTAssertEqual(fixture.runtime.lazyListResolveCount, resolutions, file: file, line: line)
    }

    private func assertDefaultBudget(
        _ fixture: KeyboardPreparationFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        let phases = fixture.phases
        XCTAssertFalse(phases.isEmpty, file: file, line: line)
        XCTAssertLessThan(phases.count, 512, file: file, line: line)
        XCTAssertEqual(phases.first?.remainingRounds, 4, file: file, line: line)
        XCTAssertEqual(phases.first?.remainingElements, 128, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128, file: file, line: line)
        XCTAssertLessThanOrEqual(fixture.tracedFactories.count, 128, file: file, line: line)
        for (first, second) in zip(phases, phases.dropFirst()) {
            XCTAssertGreaterThanOrEqual(first.remainingRounds, second.remainingRounds, file: file, line: line)
            XCTAssertGreaterThanOrEqual(first.remainingElements, second.remainingElements, file: file, line: line)
            XCTAssertLessThanOrEqual(first.consumedRounds, second.consumedRounds, file: file, line: line)
        }
        let debits = phases.filter { $0.kind == .roundDebit }
        XCTAssertEqual(debits.count, fixture.runtime.lastLazyListConsumedRounds, file: file, line: line)
        for debit in debits {
            let work = phases.filter { $0.consumedRounds == debit.consumedRounds }
            XCTAssertLessThanOrEqual(work.filter { $0.kind == .measurementPhase }.count, 1, file: file, line: line)
            XCTAssertLessThanOrEqual(work.filter { $0.kind == .readerPhase }.count, 1, file: file, line: line)
            XCTAssertLessThanOrEqual(work.filter { $0.kind == .providerPhase }.count, 1, file: file, line: line)
        }
    }
}

/// Suppressing framework anchors must not turn an equal authored offset
/// assignment into permission for an already prepared keyboard action.
@MainActor
final class LazyListKeyboardScrollIntentTests: XCTestCase {
    func testAuthoredSameValueScrollAtNonzeroOffsetRevokesTheOriginalKeyboardSettlement() async throws {
        let fixture = try KeyboardPreparationFixture()
        defer { fixture.close() }
        fixture.probe.selected = 899
        try XCTUnwrap(try fixture.row(0).onKeyDown)(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
        let source = try fixture.row(900)
        XCTAssertEqual(fixture.probe.writes, [900])
        XCTAssertTrue(fixture.runtime.focusedNode === source)
        XCTAssertEqual(fixture.focusedOrdinals, [900])
        let originalOffset = fixture.scroll.scrollOffset
        XCTAssertGreaterThan(originalOffset, 20_000)

        var authoredOffsets: [Double] = []
        fixture.runtime.root.onLayout = { [weak fixture] _ in
            guard let fixture, authoredOffsets.isEmpty, fixture.probe.writes == [900, 899] else { return }
            XCTAssertNotNil(fixture.adapter.keyboardPreparation)
            XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
            XCTAssertTrue(fixture.runtime.focusedNode === source)
            XCTAssertNotNil(fixture.findRow(899))
            let offset = fixture.scroll.scrollOffset
            XCTAssertEqual(offset, originalOffset)
            authoredOffsets.append(offset)
            // This is a new authored intent despite having the same scalar
            // value. No focus mutation or physical departure causes refusal.
            fixture.scroll.scrollOffset = offset
        }

        fixture.beginTrace()
        try XCTUnwrap(source.onKeyDown)(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
        fixture.endTrace()
        fixture.runtime.root.onLayout = nil

        XCTAssertEqual(authoredOffsets.count, 1)
        XCTAssertEqual(try XCTUnwrap(authoredOffsets.first), originalOffset)
        XCTAssertEqual(fixture.probe.writes, [900, 899])
        XCTAssertEqual(fixture.probe.selected, 899)
        XCTAssertTrue(fixture.runtime.focusedNode === source)
        XCTAssertTrue(source.isFocused)
        XCTAssertEqual(fixture.focusedOrdinals, [900])
        let target = try fixture.row(899)
        XCTAssertTrue(target.parent === fixture.content)
        XCTAssertTrue(target.isFocusEnabled)
        XCTAssertFalse(target.isFocused)
        XCTAssertEqual(fixture.scroll.scrollOffset, originalOffset)
        XCTAssertNil(fixture.adapter.keyboardPreparation)

        let phases = fixture.phases
        XCTAssertFalse(phases.isEmpty)
        XCTAssertLessThan(phases.count, 512)
        XCTAssertEqual(phases.first?.remainingRounds, 4)
        XCTAssertEqual(phases.first?.remainingElements, 128)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128)
        XCTAssertLessThanOrEqual(fixture.tracedFactories.count, 128)
        XCTAssertEqual(phases.filter { $0.kind == .roundDebit }.count, fixture.runtime.lastLazyListConsumedRounds)
        for (first, second) in zip(phases, phases.dropFirst()) {
            XCTAssertGreaterThanOrEqual(first.remainingRounds, second.remainingRounds)
            XCTAssertGreaterThanOrEqual(first.remainingElements, second.remainingElements)
            XCTAssertLessThanOrEqual(first.consumedRounds, second.consumedRounds)
        }
        XCTAssertEqual(fixture.runtime.lazyListResolutionBudgetConfiguration.elementLimit, 128)
        XCTAssertEqual(fixture.runtime.lazyListResolutionBudgetConfiguration.roundLimit, 4)
    }
}

@MainActor
private final class KeyboardPreparationFixture {
    let probe: KeyboardPreparationProbe
    let host: MountedLazyListTestHost
    let content: ViewNode
    let scroll: ViewNode
    let alternate: ViewNode
    private var firstFactory = 0
    private(set) var phases: [RetainedViewRuntime.LazyListUIAPhaseTrace] = []
    private(set) var tracedFactories: [Int] = []
    private(set) var focusedOrdinals: [Int] = []
    private(set) var focusWasDeferred: [Bool] = []

    var runtime: RetainedViewRuntime { host.runtime }
    var adapter: RetainedLazyListRuntimeAdapter { content.retainedLazyListAdapter! }

    init(
        probe: KeyboardPreparationProbe = KeyboardPreparationProbe(), bindingPayload: KeyboardPreparationPayload? = nil
    )
        throws
    {
        self.probe = probe
        let binding = Binding<Int?>(
            get: { [bindingPayload] in
                withExtendedLifetime(bindingPayload) {}
                probe.reads += 1
                return probe.selected
            },
            set: { [bindingPayload] in
                withExtendedLifetime(bindingPayload) {}
                probe.selected = $0
                probe.writes.append($0)
                probe.onSet?()
            })
        host = MountedLazyListTestHost(size: Size(width: 260, height: 230)) {
            VStack(spacing: 0) {
                keyboardPreparationList(probe, selection: binding)
                    .frame(width: 260, height: 200)
                Button("Alternate") {}.accessibilityIdentifier("keyboard.preparation.alternate")
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
        alternate = try XCTUnwrap(host.find("keyboard.preparation.alternate"))
        XCTAssertTrue(alternate.isFocusable)
        XCTAssertEqual(scroll.scrollOffset, 0)
        XCTAssertFalse(try XCTUnwrap(content.retainedLazyListAdapter).hasUnresolvedWork)
        guard case .settled(let settlement) = host.runtime.layoutSettlementStatus else {
            host.close()
            throw KeyboardPreparationFixtureError.unsettled
        }
        XCTAssertTrue(host.runtime.isLayoutSettlementReceiptCurrent(settlement))
        host.runtime.onAccessibilityFocusChanged = { [weak self] node in
            guard let self, let node, let row = DeferredListRowNavigation.attached(to: node) else { return }
            self.focusedOrdinals.append(row.ordinal)
            var cursor: ViewNode? = node
            var deferred = false
            while let current = cursor {
                deferred = deferred || current.isLayoutDeferredByVirtualization
                cursor = current.parent
            }
            self.focusWasDeferred.append(deferred)
        }
    }

    func findRow(_ ordinal: Int) -> ViewNode? {
        eligible(content.children, ordinal: ordinal).first
    }

    func eligible(_ nodes: [ViewNode], ordinal: Int) -> [ViewNode] {
        nodes.filter {
            !$0.isHidden && !$0.isSeparatorRule && $0.isFocusEnabled && $0.listNavigationOwner != nil
                && DeferredListRowNavigation.attached(to: $0)?.ordinal == ordinal
        }
    }

    func row(_ ordinal: Int) throws -> ViewNode { try XCTUnwrap(findRow(ordinal)) }

    func item(_ ordinal: Int) throws -> RetainedLazyListAccessibilityItem {
        let source = try XCTUnwrap(DeferredListScrollSource.attached(to: content))
        let row = try XCTUnwrap(source.row(at: ordinal))
        return try XCTUnwrap(runtime.lazyListTarget(in: content, key: row.providerKey))
    }

    func beginTrace() {
        firstFactory = probe.factories.count
        runtime.recordsLazyListUIAPhasesForTesting = true
    }

    func endTrace() {
        runtime.recordsLazyListUIAPhasesForTesting = false
        phases = runtime.lazyListUIAPhasesForTesting
        tracedFactories = Array(probe.factories.dropFirst(firstFactory))
    }

    func close() {
        probe.onFactory = nil
        probe.onSet = nil
        runtime.recordsLazyListUIAPhasesForTesting = false
        runtime.root.onLayout = nil
        scroll.onLayout = nil
        runtime.onAccessibilityFocusChanged = nil
        host.close()
    }
}

@MainActor
private final class KeyboardPreparationProbe {
    var rows = Array(0..<1_000)
    var selected: Int? = 0
    var reads = 0
    var writes: [Int?] = []
    var factories: [Int] = []
    var empty: Set<Int> = []
    var disabled: Set<Int> = []
    var multiple: Set<Int> = []
    var coldHeight: Double = 24
    var minimumRowHeight: Double?
    var onFactory: ((Int) -> Void)?
    var onSet: (() -> Void)?

    func content(for ordinal: Int) -> [AnyView] {
        factories.append(ordinal)
        onFactory?(ordinal)
        guard !empty.contains(ordinal) else { return [] }
        let height = ordinal > 800 ? coldHeight : 24
        var output = [
            AnyView(
                Text("Row \(ordinal)").frame(width: 220, height: height)
                    .selectionDisabled(disabled.contains(ordinal)))
        ]
        if multiple.contains(ordinal) {
            output.append(AnyView(Text("Tail \(ordinal)").frame(width: 220, height: height)))
        }
        return output
    }
}

@MainActor
@ViewBuilder
private func keyboardPreparationList(_ probe: KeyboardPreparationProbe, selection: Binding<Int?>) -> some View {
    if let minimum = probe.minimumRowHeight {
        List(probe.rows, id: \.self, selection: selection) { probe.content(for: $0) }
            .environment(\.defaultMinListRowHeight, minimum)
    } else {
        List(probe.rows, id: \.self, selection: selection) { probe.content(for: $0) }
    }
}

private enum KeyboardPreparationFixtureError: Error { case unsettled }

@MainActor
private final class KeyboardPreparationLifetime {
    weak var payload: KeyboardPreparationPayload?
    var releases = 0
    var releasedAfterDeparture = false
}

@MainActor
private final class KeyboardPreparationPayload {
    private let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

@MainActor
private final class KeyboardPreparationReaderFixture {
    let rows = KeyboardPreparationProbe()
    let readerProbe = KeyboardPreparationReaderProbe()
    let host: MountedLazyListTestHost
    let content: ViewNode
    let scroll: ViewNode
    let reader: ViewNode
    let alternate: ViewNode
    var runtime: RetainedViewRuntime { host.runtime }

    init() throws {
        let rows = rows
        let readerProbe = readerProbe
        let binding = Binding<Int?>(
            get: {
                rows.reads += 1
                return rows.selected
            },
            set: {
                rows.selected = $0
                rows.writes.append($0)
            })
        host = MountedLazyListTestHost(size: Size(width: 260, height: 230)) {
            VStack(spacing: 0) {
                List(rows.rows, id: \.self, selection: binding) { rows.content(for: $0) }
                    .frame(width: 260, height: 200)
                HStack(spacing: 0) {
                    GeometryReader { _ in KeyboardPreparationReaderContent(probe: readerProbe) }
                        .frame(width: 130, height: 30)
                    Button("Alternate") {}.accessibilityIdentifier("keyboard.reader.alternate")
                        .frame(width: 130, height: 30)
                }
            }
        }
        for _ in 0..<16 {
            host.render()
            if !host.runtime.isDirty { break }
        }
        XCTAssertFalse(host.runtime.isDirty)
        content = try host.list()
        scroll = try host.scrollContainer()
        reader = try XCTUnwrap(
            MountedLazyListTestHost.descendants(in: host.runtime.root).first { $0.geometryReaderBuild != nil })
        alternate = try XCTUnwrap(host.find("keyboard.reader.alternate"))
        XCTAssertTrue(alternate.isFocusable)
        XCTAssertNotNil(reader.retainedSubtreeBuildLease)
        XCTAssertFalse(MountedLazyListTestHost.descendants(in: content).contains { $0 === reader })
        XCTAssertEqual(reader.geometryReaderBuiltSize, reader.resolvedFrame.size)
        XCTAssertEqual(scroll.scrollOffset, 0)
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            host.close()
            throw KeyboardPreparationFixtureError.unsettled
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        readerProbe.runtime = runtime
    }

    func sourceRow() throws -> ViewNode {
        try XCTUnwrap(
            content.children.first {
                !$0.isSeparatorRule && $0.isFocusEnabled && $0.listNavigationOwner != nil
                    && DeferredListRowNavigation.attached(to: $0)?.ordinal == 0
            })
    }

    func armReaderRebuild() {
        rows.selected = 899
        rows.onFactory = { [weak self] ordinal in
            guard let self, ordinal == 899, !self.readerProbe.isArmed else { return }
            self.readerProbe.isArmed = true
            self.readerProbe.revision = 1
            // The provider's required actual pass discovers this original
            // ordinary reader. No extra query or authored adoption hook runs.
            self.reader.geometryReaderBuiltSize = .zero
        }
    }

    func installRawReader(lease: KeyboardPreparationReaderLease, revokeBeforeReturn: Bool) {
        reader.retainedSubtreeBuildLease = lease
        readerProbe.installRaw(on: reader, builtSize: reader.resolvedFrame.size, lease: lease)
        readerProbe.beforeRawReturn = { [weak self] in
            guard revokeBeforeReturn, let self, self.readerProbe.isArmed else { return }
            self.runtime.requestFocus(self.alternate)
        }
    }

    func close() {
        readerProbe.isArmed = false
        readerProbe.beforeRawReturn = nil
        rows.onFactory = nil
        runtime.recordsLazyListUIAPhasesForTesting = false
        reader.onLayout = nil
        host.close()
    }
}

@MainActor
private final class KeyboardPreparationReaderProbe {
    weak var runtime: RetainedViewRuntime?
    weak var epoch: StateMountEpoch?
    weak var payload: KeyboardPreparationPayload?
    var isArmed = false
    var revision = 0
    var armedBodies = 0
    var releases = 0
    var releasedDuringBuild = false
    var committedEpochs: [Bool?] = []
    var beforeRawReturn: (() -> Void)?

    func recordManagedBody() {
        guard isArmed else { return }
        armedBodies += 1
        guard let runtime, let epoch = ViewBuildContextScope.current?.viewIdentity.installedEpoch else {
            return XCTFail("An ordinary managed reader must enter its original State epoch")
        }
        self.epoch = epoch
        runtime.afterRetainedCallbacks { [weak self, weak epoch] in
            self?.committedEpochs.append(epoch?.didCommit)
        }
    }

    func installRaw(on node: ViewNode, builtSize: Size, lease: KeyboardPreparationReaderLease) {
        let preferred = node.preferredSize
        let identity = node.retainedViewIdentity
        let axes = node.layoutFillAxes
        let layoutMode = node.layoutMode
        node.geometryReaderBuiltSize = builtSize
        node.geometryReaderBuild = { [self, lease] _, slot in
            if isArmed { armedBodies += 1 }
            let candidate = ViewNode(preferredSize: preferred)
            candidate.retainedViewIdentity = identity
            candidate.layoutFillAxes = axes
            candidate.layoutMode = layoutMode
            candidate.retainedSubtreeBuildLease = lease
            installRaw(on: candidate, builtSize: slot, lease: lease)
            let label = ViewNode(preferredSize: Size(width: 120, height: 20))
            label.text = "Raw reader \(revision)"
            candidate.setChildren([label])
            beforeRawReturn?()
            return [candidate]
        }
    }
}

@MainActor
private struct KeyboardPreparationReaderContent: View {
    @State private var value = 41
    let probe: KeyboardPreparationReaderProbe
    var body: some View {
        probe.recordManagedBody()
        return Text("Reader \(probe.revision): \(value)")
    }
}

@MainActor
private final class KeyboardPreparationReaderLease: RetainedSubtreeBuildLease {
    var begins = 0
    var commits = 0
    var abandons = 0
    var finishes = 0
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? {
        begins += 1
        return KeyboardPreparationReaderEpoch(lease: self)
    }
}

@MainActor
private final class KeyboardPreparationReaderEpoch: RetainedBuildEpoch {
    let lease: KeyboardPreparationReaderLease
    private var prepared = false
    private var wasSuperseded = false
    init(lease: KeyboardPreparationReaderLease) { self.lease = lease }
    var canAdopt: Bool { !prepared && !wasSuperseded }
    func supersede() { if !prepared { wasSuperseded = true } }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        prepared = true
        return true
    }
    func commit() { lease.commits += 1 }
    func abandon() { lease.abandons += 1 }
    func finishAfterCallbacks() { lease.finishes += 1 }
}
