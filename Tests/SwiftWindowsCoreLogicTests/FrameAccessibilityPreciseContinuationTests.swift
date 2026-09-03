import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Original publication, current accessibility eligibility, and animation
/// ownership remain separate requirements for a queued physical refinement.
@MainActor
final class FrameAccessibilityPreciseContinuationTests: XCTestCase {
    func testAnimatedFrameRealizeKeepsItsOriginalRefinementAndDeadline() async throws {
        let fixture = try FramePreciseContinuationFixture(centered: true)
        defer { fixture.close() }
        let request = try fixture.beginRealize(animation: .linear(duration: 1))
        fixture.render()
        XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 0, accuracy: 0.0001)
        XCTAssertTrue(fixture.row.isLayoutDeferredByVirtualization)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)

        fixture.advance(to: 100.1)
        XCTAssertTrue(fixture.row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 60, accuracy: 0.0001)

        fixture.advance(to: 100.6)

        XCTAssertFalse(fixture.row.isLayoutDeferredByVirtualization)
        let fineOffset = fixture.centeredFineOffset()
        XCTAssertGreaterThan(fineOffset, 360, "The semantic control must still need a real animated correction")
        XCTAssertLessThan(fineOffset, 600)
        XCTAssertEqual(fixture.scroll.scrollOffset, fineOffset, accuracy: 0.0001)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 360, accuracy: 0.0001)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        XCTAssertTrue(request.isCurrent(in: fixture.runtime))

        fixture.advance(to: 100.8)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 360 + (fineOffset - 360) * 0.5, accuracy: 0.0001)
        fixture.advance(to: 101)
        XCTAssertEqual(fixture.scroll.scrollOffset, fineOffset, accuracy: 0.0001)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, fineOffset, accuracy: 0.0001)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations, "Refinement must not extend the original deadline")
        fixture.query()
        fixture.render()
        XCTAssertEqual(fixture.scroll.scrollOffset, fineOffset, accuracy: 0.0001)
        XCTAssertEqual(fixture.probe.activations, 0)
    }

    func testAnimatedFrameRealizeRefinesAfterNaturalCompletionWithoutAnIntermediateRender() async throws {
        let fixture = try FramePreciseContinuationFixture(centered: true)
        defer { fixture.close() }
        let request = try fixture.beginRealize(animation: .linear(duration: 1))
        XCTAssertTrue(fixture.row.isLayoutDeferredByVirtualization)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        // No post-Realize render occurs until the original tween completes.
        // Its queued target still has only the original coarse row placement.
        fixture.clock.now = 101
        _ = fixture.runtime.tickAnimations(at: fixture.clock.now)
        XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
        XCTAssertEqual(fixture.scroll.effectiveScrollOffset, 600, accuracy: 0.0001)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
        XCTAssertTrue(fixture.row.isLayoutDeferredByVirtualization)
        fixture.countClockCalls()

        fixture.render()

        XCTAssertFalse(fixture.row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.row.resolvedFrame.minY, 400, accuracy: 0.0001)
        XCTAssertEqual(fixture.inner.resolvedFrame.minY, 140, accuracy: 0.0001)
        XCTAssertEqual(fixture.semantic.resolvedFrame.minY, 0, accuracy: 0.0001)
        let leadingFineOffset =
            fixture.row.resolvedFrame.minY + fixture.inner.resolvedFrame.minY
            + fixture.semantic.resolvedFrame.minY
        // At coarse offset600 the centered leaf lies above the viewport, so
        // existing nil-anchor reveal uses its leading edge, not its far edge.
        XCTAssertEqual(leadingFineOffset, 540, accuracy: 0.0001)
        XCTAssertEqual(fixture.scroll.scrollOffset, leadingFineOffset, accuracy: 0.0001)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, leadingFineOffset, accuracy: 0.0001)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
        XCTAssertTrue(request.isCurrent(in: fixture.runtime))
        XCTAssertEqual(fixture.probe.clockCallbacks, 1)
        fixture.query()
        fixture.render()
        XCTAssertEqual(fixture.probe.clockCallbacks, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, leadingFineOffset, accuracy: 0.0001)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
        XCTAssertEqual(fixture.probe.activations, 0)
    }

    func testQueuedFrameRefinementCannotCancelAReplacementAnimation() async throws {
        for replacementInsideClock in [false, true] {
            let fixture = try FramePreciseContinuationFixture(centered: true)
            defer { fixture.close() }
            let request = try fixture.beginRealize(animation: .linear(duration: 1))
            fixture.render()
            fixture.advance(to: 100.1)
            XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 60, accuracy: 0.0001)
            XCTAssertTrue(fixture.row.isLayoutDeferredByVirtualization)
            var replacementStart = fixture.clock.now
            var replacementPresentation = fixture.scroll.effectiveScrollOffset
            if replacementInsideClock {
                fixture.clock.now = 100.6
                _ = fixture.runtime.tickAnimations(at: fixture.clock.now)
                fixture.runtime.clock = { [weak fixture] in
                    guard let fixture else {
                        XCTFail("The original animation fixture must survive")
                        return 100.6
                    }
                    fixture.probe.clockCallbacks += 1
                    fixture.restoreClock()
                    XCTAssertTrue(request.isCurrent(in: fixture.runtime))
                    XCTAssertEqual(fixture.scroll.scrollOffset, 600)
                    replacementStart = fixture.clock.now
                    replacementPresentation = fixture.scroll.effectiveScrollOffset
                    XCTAssertEqual(replacementPresentation, 360, accuracy: 0.0001)
                    XCTAssertTrue(fixture.startReplacementAnimation())
                    XCTAssertEqual(fixture.scroll.scrollOffset, 200, accuracy: 0.0001)
                    XCTAssertEqual(fixture.scroll.effectiveScrollOffset, replacementPresentation, accuracy: 0.0001)
                    return fixture.clock.now
                }
                fixture.render()
                XCTAssertEqual(fixture.probe.clockCallbacks, 1)
            } else {
                XCTAssertTrue(fixture.startReplacementAnimation())
                fixture.render()
                XCTAssertEqual(fixture.probe.clockCallbacks, 0)
            }

            XCTAssertTrue(request.isCurrent(in: fixture.runtime))
            XCTAssertEqual(fixture.scroll.scrollOffset, 200, accuracy: 0.0001)
            XCTAssertEqual(fixture.scroll.resolvedScrollOffset, replacementPresentation, accuracy: 0.0001)
            XCTAssertTrue(fixture.runtime.hasActiveAnimations)
            fixture.advance(to: replacementStart + 0.6)
            XCTAssertEqual(
                fixture.scroll.resolvedScrollOffset, replacementPresentation + (200 - replacementPresentation) * 0.5,
                accuracy: 0.0001)
            fixture.advance(to: replacementStart + 1.2)
            XCTAssertEqual(fixture.scroll.scrollOffset, 200, accuracy: 0.0001)
            XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 200, accuracy: 0.0001)
            XCTAssertFalse(fixture.runtime.hasActiveAnimations)
            fixture.query()
            fixture.render()
            XCTAssertEqual(fixture.scroll.scrollOffset, 200, accuracy: 0.0001)
            XCTAssertEqual(fixture.probe.activations, 0)
        }
    }

    func testQueuedFrameRealizeRechecksIndependentEligibilityBeforeDrain() async throws {
        for revocation in FramePreciseEligibilityRevocation.allCases {
            let fixture = try FramePreciseContinuationFixture(centered: false)
            defer { fixture.close() }
            let request = try fixture.beginRealize(animation: nil)
            let attachment = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.semantic))
            fixture.revoke(revocation)
            fixture.assertIndependentRevocation(revocation, request: request, attachment: attachment)
            fixture.countClockCalls()

            fixture.render()

            XCTAssertEqual(fixture.probe.clockCallbacks, 0, revocation.rawValue)
            XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001, revocation.rawValue)
            fixture.query()
            fixture.render()
            XCTAssertEqual(fixture.probe.clockCallbacks, 0)
            XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
            XCTAssertTrue(fixture.runtime.isAccessibilityAttachmentCurrent(attachment))
            XCTAssertEqual(fixture.probe.activations, 0)
        }
    }

    func testQueuedFrameRealizeRechecksIndependentEligibilityAfterClock() async throws {
        for revocation in FramePreciseEligibilityRevocation.allCases {
            let fixture = try FramePreciseContinuationFixture(centered: false)
            defer { fixture.close() }
            let request = try fixture.beginRealize(animation: nil)
            let attachment = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.semantic))
            fixture.runtime.clock = { [weak fixture] in
                guard let fixture else {
                    XCTFail("The original eligibility fixture must survive")
                    return 100
                }
                fixture.probe.clockCallbacks += 1
                fixture.restoreClock()
                XCTAssertTrue(request.isCurrent(in: fixture.runtime))
                XCTAssertEqual(fixture.scroll.scrollOffset, 600)
                fixture.revoke(revocation)
                fixture.assertIndependentRevocation(revocation, request: request, attachment: attachment)
                return fixture.clock.now
            }

            fixture.render()

            XCTAssertEqual(fixture.probe.clockCallbacks, 1, revocation.rawValue)
            XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001, revocation.rawValue)
            fixture.query()
            fixture.render()
            XCTAssertEqual(fixture.probe.clockCallbacks, 1)
            XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
            XCTAssertTrue(fixture.runtime.isAccessibilityAttachmentCurrent(attachment))
            XCTAssertEqual(fixture.probe.activations, 0)
        }
    }

    func testQueuedFrameRefinementConservativelyRefusesAnUnchangedSiblingModalStack() async throws {
        let fixture = try FramePreciseContinuationFixture(centered: false, modalScopeCount: 2)
        defer { fixture.close() }
        // Frontmost modal projection admits this real public request. The
        // later conservative physical check deliberately does not treat that
        // synchronous admission as authority over a sibling modal stack.
        let request = try fixture.beginRealize(animation: nil)
        let attachment = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.semantic))
        XCTAssertEqual(fixture.runtime.root.children.count, 2)
        XCTAssertTrue(fixture.runtime.root.children.allSatisfy { $0.accessibilityTraits.contains(.isModal) })
        fixture.countClockCalls()

        fixture.render()

        XCTAssertTrue(request.isCurrent(in: fixture.runtime))
        XCTAssertTrue(fixture.runtime.isAccessibilityAttachmentCurrent(attachment))
        XCTAssertEqual(fixture.probe.clockCallbacks, 0)
        XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
        fixture.query()
        fixture.render()
        XCTAssertEqual(fixture.probe.clockCallbacks, 0)
        XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
        XCTAssertEqual(fixture.probe.activations, 0)
    }

    func testSingleEnclosingModalKeepsFineAlignmentAboveHigherAncestorPolicies() async throws {
        for policy in FramePreciseHigherAncestorPolicy.allCases {
            let fixture = try FramePreciseContinuationFixture(centered: false, modalScopeCount: 1)
            defer { fixture.close() }
            // Root is strictly above the one enclosing modal. The existing
            // projection follows the modal's real ancestry through these
            // policies; the same policies at or below that modal still block.
            switch policy {
            case .ordinary:
                break
            case .ignore:
                fixture.runtime.root.accessibilityChildBehavior = .ignore
            case .combine:
                fixture.runtime.root.accessibilityChildBehavior = .combine
            case .representation:
                fixture.runtime.root.accessibilityRepresentationChildren = [
                    ViewNode(accessibilityLabel: "Higher ancestor representation")
                ]
            }
            XCTAssertEqual(fixture.runtime.root.children.count, 1)
            XCTAssertTrue(try XCTUnwrap(fixture.runtime.root.children.first).accessibilityTraits.contains(.isModal))
            let request = try fixture.beginRealize(animation: nil)
            fixture.countClockCalls()

            fixture.render()

            XCTAssertFalse(fixture.row.isLayoutDeferredByVirtualization)
            XCTAssertEqual(fixture.row.resolvedFrame.minY, 400, accuracy: 0.0001)
            XCTAssertEqual(fixture.inner.resolvedFrame.minY, 0, accuracy: 0.0001)
            XCTAssertEqual(fixture.semantic.resolvedFrame.minY, 0, accuracy: 0.0001)
            XCTAssertEqual(fixture.scroll.scrollOffset, 400, accuracy: 0.0001, policy.rawValue)
            XCTAssertEqual(fixture.probe.clockCallbacks, 1, policy.rawValue)
            XCTAssertTrue(request.isCurrent(in: fixture.runtime))
            fixture.query()
            fixture.render()
            XCTAssertEqual(fixture.probe.clockCallbacks, 1)
            XCTAssertEqual(fixture.scroll.scrollOffset, 400, accuracy: 0.0001)
            XCTAssertEqual(fixture.probe.activations, 0)
        }
    }
}

private enum FramePreciseHigherAncestorPolicy: String, CaseIterable {
    case ordinary
    case ignore
    case combine
    case representation
}

private enum FramePreciseEligibilityRevocation: String, CaseIterable {
    case terminal
    case physicalHiddenAncestor
    case accessibilityHiddenAncestor
    case disabledAncestor
    case ignoreAncestor
    case combineAncestor
    case representationAncestor
    case competingModal
    case accessibilityHiddenCompetingModal
}

@MainActor
private final class FramePreciseContinuationClock {
    var now: Double = 100
}

@MainActor
private final class FramePreciseContinuationProbe {
    var clockCallbacks = 0
    var activations = 0
}

@MainActor
private final class FramePreciseContinuationFixture {
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    let scroll: ViewNode
    let row: ViewNode
    let inner: ViewNode
    let semantic: ViewNode
    let replacementTarget: ViewNode
    let clock: FramePreciseContinuationClock
    let probe: FramePreciseContinuationProbe

    init(centered: Bool, modalScopeCount: Int = 0) throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 240))
        let runtime = RetainedViewRuntime(root: root)
        let clock = FramePreciseContinuationClock()
        runtime.clock = { [weak clock] in clock?.now ?? 100 }
        let probe = FramePreciseContinuationProbe()
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 320, height: 240) }, invalidateHandler: {})
        let row = Button("Queued continuation target") { probe.activations += 1 }
            .frame(width: 80, height: 20, alignment: .topLeading)
            .frame(width: 80, height: 300, alignment: centered ? .center : .topLeading)
            .accessibilityLabel("Original continuation frame")
            .accessibilityIdentifier("precise-continuation-subject")
            .makeComponent(context: context).makeNode(runtime: runtime)
        let inner = try XCTUnwrap(row.children.first)
        let semantic = try XCTUnwrap(inner.children.first)
        XCTAssertTrue(row.accessibilityDeclaredFrameContent === inner)
        XCTAssertTrue(inner.accessibilityDeclaredFrameContent === semantic)
        let preceding = (0..<10).map { _ in
            ViewNode(preferredSize: Size(width: 80, height: 40), isHitTestVisible: false)
        }
        let trailing = (0..<4).map { _ in
            ViewNode(preferredSize: Size(width: 80, height: 40), isHitTestVisible: false)
        }
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100), clipsToBounds: true,
            layoutMode: .lazyStack(.vertical(spacing: 0)), scrollAxis: .vertical,
            children: preceding + [row] + trailing)
        scroll.showsScrollIndicator = false
        scroll.scrollIndicatorAutoHides = false
        if modalScopeCount == 2 {
            let behind = ViewNode(
                frame: Rect(x: 0, y: 0, width: 320, height: 240),
                accessibilityLabel: "Behind modal scope", accessibilityTraits: .isModal)
            behind.paintsInDeferredPhase = true
            let front = ViewNode(
                frame: Rect(x: 0, y: 0, width: 320, height: 240),
                accessibilityLabel: "Front modal scope", accessibilityTraits: .isModal, children: [scroll])
            front.paintsInDeferredPhase = true
            front.zIndex = 1
            root.addChild(behind)
            root.addChild(front)
        } else if modalScopeCount == 1 {
            let modal = ViewNode(
                frame: Rect(x: 0, y: 0, width: 320, height: 240),
                accessibilityLabel: "Single modal scope", accessibilityTraits: .isModal, children: [scroll])
            modal.paintsInDeferredPhase = true
            root.addChild(modal)
        } else {
            root.addChild(scroll)
        }
        self.runtime = runtime
        self.source = RuntimeUIAElementTreeSource(runtime: runtime)
        self.scroll = scroll
        self.row = row
        self.inner = inner
        self.semantic = semantic
        self.replacementTarget = preceding[5]
        self.clock = clock
        self.probe = probe
        _ = runtime.renderFrame(at: clock.now)
        XCTAssertNil(scroll.retainedLazyListAdapter)
        XCTAssertTrue(row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(row.resolvedFrame.minY, 400, accuracy: 0.0001)
        XCTAssertEqual(row.resolvedFrame.size.height, 300, accuracy: 0.0001)
        XCTAssertEqual(scroll.scrollOffset, 0)
    }

    func beginRealize(animation: Animation?) throws -> RetainedAccessibilitySemanticRequest {
        let matches = source.uiaElementSnapshots().filter { $0.automationID == "precise-continuation-subject" }
        XCTAssertEqual(matches.count, 1)
        let snapshot = try XCTUnwrap(matches.first)
        let request = try XCTUnwrap(row.currentAccessibilitySemanticRequest)
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertTrue(request.semanticNode === semantic)
        XCTAssertTrue(snapshot.isVirtualizedPlaceholder)
        XCTAssertNotEqual(snapshot.id, UIAProviderBridge.rootElementID)
        // This is the public ambient transaction that initial physical Realize
        // already reads. The queued correction cannot borrow a later one.
        let realized = withAnimation(animation) { source.uiaRealizeVirtualizedItem(elementID: snapshot.id) }
        XCTAssertTrue(realized)
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertEqual(scroll.scrollOffset, 600, accuracy: 0.0001)
        XCTAssertTrue(row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(scroll.effectiveScrollOffset, animation == nil ? 600 : 0, accuracy: 0.0001)
        return request
    }

    func centeredFineOffset() -> Double {
        XCTAssertEqual(row.resolvedFrame.minY, 400, accuracy: 0.0001)
        XCTAssertEqual(row.resolvedFrame.size.height, 300, accuracy: 0.0001)
        XCTAssertEqual(inner.resolvedFrame.minY, 140, accuracy: 0.0001)
        XCTAssertEqual(inner.resolvedFrame.size.height, 20, accuracy: 0.0001)
        XCTAssertEqual(semantic.resolvedFrame.minY, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(semantic.resolvedFrame.size.height, 0)
        XCTAssertLessThanOrEqual(semantic.resolvedFrame.size.height, 100)
        return row.resolvedFrame.minY + inner.resolvedFrame.minY + semantic.resolvedFrame.maxY
            - scroll.resolvedFrame.size.height
    }

    func startReplacementAnimation() -> Bool {
        runtime.scrollToDescendant(
            replacementTarget, anchorY: 0, transaction: Transaction(animation: .linear(duration: 1.2)))
    }

    func render() { _ = runtime.renderFrame(at: clock.now) }
    func query() { XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root)) }
    func advance(to time: Double) {
        clock.now = time
        _ = runtime.tickAnimations(at: time)
        render()
    }

    func restoreClock() { runtime.clock = { [weak clock] in clock?.now ?? 100 } }
    func countClockCalls() {
        probe.clockCallbacks = 0
        runtime.clock = { [weak clock, weak probe] in
            probe?.clockCallbacks += 1
            return clock?.now ?? 100
        }
    }

    func revoke(_ revocation: FramePreciseEligibilityRevocation) {
        switch revocation {
        case .terminal:
            runtime.stopRenderLifecycleCallbacks()
        case .physicalHiddenAncestor:
            scroll.isHidden = true
        case .accessibilityHiddenAncestor:
            scroll.isAccessibilityHidden = true
        case .disabledAncestor:
            scroll.accessibilityRespondsToUserInteraction = false
        case .ignoreAncestor:
            scroll.accessibilityChildBehavior = .ignore
        case .combineAncestor:
            scroll.accessibilityChildBehavior = .combine
        case .representationAncestor:
            scroll.accessibilityRepresentationChildren = [ViewNode(accessibilityLabel: "Replacement representation")]
        case .competingModal, .accessibilityHiddenCompetingModal:
            let modal = ViewNode(
                frame: Rect(x: 110, y: 10, width: 180, height: 180),
                accessibilityLabel: "New competing modal", accessibilityTraits: .isModal)
            if revocation == .accessibilityHiddenCompetingModal { modal.isAccessibilityHidden = true }
            modal.paintsInDeferredPhase = true
            runtime.root.addChild(modal)
        }
    }

    func assertIndependentRevocation(
        _ revocation: FramePreciseEligibilityRevocation, request: RetainedAccessibilitySemanticRequest,
        attachment: RetainedAccessibilityTarget
    ) {
        XCTAssertTrue(runtime.isAccessibilityAttachmentCurrent(attachment), revocation.rawValue)
        XCTAssertTrue(row.accessibilityDeclaredFrameContent === inner)
        XCTAssertTrue(inner.parent === row)
        XCTAssertTrue(semantic.parent === inner)
        if revocation == .terminal {
            // Terminal Button retirement need not promise continued effect
            // eligibility through a still-inspectable semantic publication.
            XCTAssertFalse(runtime.permitsRetainedActionInvocation)
        } else {
            XCTAssertTrue(request.isCurrent(in: runtime), "Independent ancestor: \(revocation.rawValue)")
        }
    }

    func close() {
        restoreClock()
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}
