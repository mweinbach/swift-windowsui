import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Composition checks for the original Button source receipt and the shared
/// removal resolver. Existing ordinary and managed resolver fixtures stay intact.
@MainActor
final class RetainedButtonRemovalResolverCompositionTests: XCTestCase {
    func testModifierReattachmentCannotRecaptureTheSourceDuringReentry() async throws {
        let fixture = try ButtonRemovalCompositionFixture()
        defer { fixture.finish() }
        fixture.assertOriginalOwnership()
        var events: [String] = []
        var nestedResult: Bool?
        fixture.sourceRuntime.clock = {
            events.append("source clock")
            return 10
        }
        fixture.destinationRuntime.clock = {
            events.append("destination clock")
            return 20
        }
        fixture.source.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: { _ in events.append("later modifier") }),
            RetainedAnimationModifier(transaction: { transaction in
                events.append("first modifier")
                fixture.moveSource(to: fixture.destinationRuntime.root)
                fixture.moveSource(to: fixture.sourceRuntime.root)
                fixture.installReplacementAnimation()
                nestedResult = RetainedRemovalTransitionResolver.applyGuarded(
                    node: fixture.source, sourceDeparture: fixture.departure)
                transaction.animation = Animation(duration: 1, easing: .linear)
            }),
        ]

        XCTAssertFalse(
            RetainedRemovalTransitionResolver.applyGuarded(node: fixture.source, sourceDeparture: fixture.departure))
        XCTAssertEqual(events, ["first modifier"])
        XCTAssertEqual(nestedResult, false)
        XCTAssertTrue(fixture.source.parent === fixture.sourceRuntime.root)
        XCTAssertTrue(fixture.source.captureLazyListAttachmentProof().isCurrent)
        XCTAssertFalse(fixture.departure.owns(fixture.source))
        fixture.assertReplacementAnimation()
    }

    func testClockReparentingCannotOverwriteTheReplacementAttachmentAnimation() async throws {
        let fixture = try ButtonRemovalCompositionFixture()
        defer { fixture.finish() }
        fixture.assertOriginalOwnership()
        var sourceClocks = 0
        var destinationClocks = 0
        var replacementAttachment: RetainedLazyListAttachmentProof?
        fixture.destinationRuntime.clock = {
            destinationClocks += 1
            return 20
        }
        fixture.sourceRuntime.clock = {
            sourceClocks += 1
            fixture.sourceRuntime.clock = { 10 }
            fixture.moveSource(to: fixture.destinationRuntime.root)
            replacementAttachment = fixture.source.captureLazyListAttachmentProof()
            fixture.installReplacementAnimation()
            return 10
        }

        XCTAssertFalse(
            RetainedRemovalTransitionResolver.applyGuarded(node: fixture.source, sourceDeparture: fixture.departure))
        XCTAssertEqual(sourceClocks, 1)
        XCTAssertEqual(destinationClocks, 0)
        XCTAssertTrue(fixture.source.parent === fixture.destinationRuntime.root)
        XCTAssertTrue(replacementAttachment?.isCurrent == true)
        XCTAssertFalse(fixture.departure.owns(fixture.source))
        fixture.assertReplacementAnimation()
    }

    func testModifierCaptureDestructionSeesPublicationAndCannotBeOverwrittenAfterReentry() async throws {
        let fixture = try ButtonRemovalCompositionFixture()
        defer { fixture.finish() }
        fixture.assertOriginalOwnership()
        var releases = 0
        var sawPublishedAnimation = false
        var replacementAttachment: RetainedLazyListAttachmentProof?
        var hook: ButtonRemovalCompositionReleaseHook? = ButtonRemovalCompositionReleaseHook {
            releases += 1
            sawPublishedAnimation = fixture.source.animationStates[.opacity]?.endValue == 0
            fixture.moveSource(to: fixture.destinationRuntime.root)
            replacementAttachment = fixture.source.captureLazyListAttachmentProof()
            fixture.installReplacementAnimation()
        }
        fixture.source.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: { [capture = hook] transaction in
                withExtendedLifetime(capture) {}
                fixture.source.reconcileAnimationModifiers = []
                transaction.animation = Animation(duration: 0.4, easing: .linear)
            })
        ]
        hook = nil

        XCTAssertFalse(
            RetainedRemovalTransitionResolver.applyGuarded(node: fixture.source, sourceDeparture: fixture.departure))
        XCTAssertEqual(releases, 1)
        XCTAssertTrue(sawPublishedAnimation)
        XCTAssertTrue(fixture.source.parent === fixture.destinationRuntime.root)
        XCTAssertTrue(replacementAttachment?.isCurrent == true)
        XCTAssertFalse(fixture.departure.owns(fixture.source))
        fixture.assertReplacementAnimation()
    }

    func testOwnedSourceCleanupContinuesWhenOnlyDestinationButtonAdmissionExpires() async throws {
        for expiresDestination in [false, true] {
            let fixture = try ButtonRemovalCompositionFixture()
            defer { fixture.finish() }
            fixture.assertOriginalOwnership()
            var events: [String] = []
            fixture.source.transition = RetainedTransition(
                kind: .combined(
                    RetainedTransition(kind: .offset(x: 6, y: 8)), RetainedTransition(kind: .slide)))
            fixture.source.animationStates[.outlineWidth] = AnimationState(
                startValue: 1, endValue: 3, startTime: 2, duration: 20)
            fixture.source.reconcileAnimationModifiers = [
                RetainedAnimationModifier(transaction: { transaction in
                    events.append("inner")
                    transaction.animation = Animation(duration: 2, easing: .easeIn)
                }),
                RetainedAnimationModifier(transaction: { transaction in
                    events.append("outer")
                    if expiresDestination { fixture.pendingButton.onActivate = nil }
                    transaction.animation = Animation(duration: 3, easing: .linear)
                }),
            ]
            fixture.sourceRuntime.clock = {
                events.append("clock")
                return 15
            }

            XCTAssertTrue(
                RetainedRemovalTransitionResolver.applyGuarded(
                    node: fixture.source, sourceDeparture: fixture.departure))
            XCTAssertEqual(events, ["outer", "inner", "clock"])
            XCTAssertEqual(fixture.adoption.isCurrent, !expiresDestination)
            XCTAssertTrue(fixture.departure.owns(fixture.source))
            XCTAssertTrue(fixture.source.parent === fixture.sourceRuntime.root)
            XCTAssertEqual(fixture.source.animationStates[.transformTranslationX]?.endValue, 80)
            XCTAssertEqual(fixture.source.animationStates[.transformTranslationY]?.endValue, 8)
            XCTAssertEqual(fixture.source.animationStates[.transformTranslationX]?.duration, 2)
            XCTAssertEqual(fixture.source.animationStates[.transformTranslationX]?.easing, .easeIn)
            XCTAssertEqual(fixture.source.animationStates[.transformTranslationX]?.startTime, 15)
            XCTAssertEqual(fixture.source.animationStates[.outlineWidth]?.startTime, 2)
            XCTAssertEqual(fixture.source.animationStates[.outlineWidth]?.endValue, 3)
        }
    }

    func testValueComparisonRevocationStopsTheInoutTransactionTransform() async throws {
        let fixture = try ButtonRemovalCompositionFixture()
        let probe = ButtonRemovalCompositionComparisonProbe()
        defer {
            probe.action = nil
            fixture.finish()
        }
        fixture.assertOriginalOwnership()
        fixture.source.transition = .identity
        probe.action = { fixture.moveSource(to: fixture.destinationRuntime.root) }
        let previous = RetainedAnimationModifier(
            animation: nil, value: ButtonRemovalCompositionTrigger(value: 0, probe: probe))
        let modifier = RetainedAnimationModifier(
            animation: Animation(duration: 9, easing: .easeIn),
            value: ButtonRemovalCompositionTrigger(value: 1, probe: probe))
        var transaction = Transaction(animation: Animation(duration: 0.75, easing: .linear))

        XCTAssertFalse(
            modifier.apply(
                to: &transaction, previous: previous,
                sourceDeparture: fixture.departure, sourceDepartureNode: fixture.source))
        XCTAssertEqual(probe.comparisons, 1)
        XCTAssertEqual(transaction.animation?.duration, 0.75)
        XCTAssertEqual(transaction.animation?.easing, .linear)
        XCTAssertTrue(fixture.source.parent === fixture.destinationRuntime.root)
        XCTAssertFalse(fixture.departure.owns(fixture.source))
        XCTAssertTrue(fixture.source.animationStates.isEmpty)
    }

    func testManagedRemovalCarriesTheOriginalButtonGuardThroughPaintPreparation() async throws {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = nil
        currentAnimationTransaction = nil
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        for clearsOwner in [false, true] {
            let rows = ButtonRemovalCompositionRows()
            let host = MountedLazyListTestHost(size: Size(width: 140, height: 80)) {
                WinSwiftUI.List(rows.values, id: \.self) { _ in
                    WinSwiftUI.Button("Run") {}
                        .frame(width: 80, height: 32)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                        .accessibilityIdentifier("composition.row")
                }
                .listStyle(.plain)
            }
            defer { host.close() }
            host.runtime.clock = { 10 }
            XCTAssertNotNil(host.layout())
            XCTAssertTrue(host.runtime.renderScene(at: 10).validate().isEmpty)
            let list = try host.list()
            let row = try host.rowRoot("composition.row")
            let button = try XCTUnwrap(
                MountedLazyListTestHost.descendants(in: row).first { $0.buttonActionOwner != nil })
            let rowAttachment = row.captureLazyListAttachmentProof()
            let buttonAttachment = button.captureLazyListAttachmentProof()
            let buttonIdentity = button.captureLazyListIdentityProof()
            XCTAssertNotNil(list.retainedLazyListAdapter?.managedLogicalDescriptorBinding)
            XCTAssertTrue(row.retainedLazyListPresentedPaint?.isCurrent == true)
            XCTAssertTrue(row.hasAppeared)
            XCTAssertTrue(row.parent === list)
            XCTAssertNotEqual(row.transition.removal.kind, .identity)
            var events: [String] = []
            var disappearances = 0
            row.onDisappear = { disappearances += 1 }
            row.reconcileAnimationModifiers = [
                RetainedAnimationModifier(transaction: { transaction in
                    events.append("later")
                    transaction.animation = Animation(duration: 1, easing: .linear)
                }),
                RetainedAnimationModifier(transaction: { transaction in
                    events.append("first")
                    if clearsOwner { button.onActivate = nil }
                    transaction.animation = Animation(duration: 1, easing: .linear)
                }),
            ]
            defer {
                row.transition = .identity
                row.reconcileAnimationModifiers = []
                row.onDisappear = nil
            }

            rows.values = []
            withAnimation(.linear(duration: 1)) {
                host.reload()
                // Do not start a fresh entry after reload has reached an authored callback.
                if events.isEmpty { _ = host.layout() }
            }

            XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
            if clearsOwner {
                XCTAssertEqual(events, ["first"])
                XCTAssertNil(button.buttonActionOwner)
                XCTAssertTrue(rowAttachment.isCurrent)
                XCTAssertTrue(buttonAttachment.isCurrent)
                XCTAssertTrue(buttonIdentity.isCurrent)
                XCTAssertTrue(row.parent === list)
                XCTAssertTrue(list.children.contains { $0 === row })
                XCTAssertEqual(disappearances, 0)
                XCTAssertEqual(host.runtime.retiredLazyListPaintCount, 0)
                XCTAssertTrue(row.animationStates.isEmpty)
            } else {
                XCTAssertEqual(events, ["first", "later"])
                XCTAssertFalse(rowAttachment.isCurrent)
                XCTAssertFalse(host.contains(row))
                XCTAssertEqual(disappearances, 1)
                XCTAssertEqual(host.runtime.retiredLazyListPaintCount, 1)
            }
        }
    }
}

@MainActor
private final class ButtonRemovalCompositionFixture {
    let sourceRuntime: RetainedViewRuntime
    let destinationRuntime: RetainedViewRuntime
    let source: ViewNode
    let pendingButton: ViewNode
    let adoption: RetainedButtonActionAdoption
    let departure: ButtonActionSourceDeparture
    private let cleanupCheck: ComponentHost.NodeReconcileAdmission
    private let previousTransaction: Transaction?
    private let previousAnimation: (duration: Double, easing: AnimationEasing)?
    private var didFinish = false

    init() throws {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = nil
        currentAnimationTransaction = nil
        let sourceRuntime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100)))
        let destinationRuntime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100)))
        var initialized = false
        defer {
            if !initialized {
                sourceRuntime.stopRenderLifecycleCallbacks()
                destinationRuntime.stopRenderLifecycleCallbacks()
                sourceRuntime.cancelRenderLifecycleTasks()
                destinationRuntime.cancelRenderLifecycleTasks()
                currentTransaction = previousTransaction
                currentAnimationTransaction = previousAnimation
            }
        }
        sourceRuntime.clock = { 10 }
        destinationRuntime.clock = { 20 }
        let source = ViewNode(frame: Rect(x: 7, y: 9, width: 80, height: 40))
        source.resolvedFrame = source.frame
        source.opacity = 0.6
        source.transition = RetainedTransition(kind: .opacity)
        sourceRuntime.root.addChild(source)
        let pendingButton = Controls.button(
            runtime: destinationRuntime, frame: Rect(x: 0, y: 0, width: 80, height: 24), cornerRadius: 4,
            palette: SurfacePalette(idle: .gray, focused: .blue, pressed: .black), action: {})
        let cleanupCheck = try XCTUnwrap(
            ComponentHost.makeRemovalTransitionCheck(
                admission: nil, target: destinationRuntime.root, parent: destinationRuntime.root,
                proposedChildren: [], lazyJournal: nil))
        let adoption = try XCTUnwrap(
            RetainedButtonActionAdoption(
                retainedRoots: [destinationRuntime.root], sourceRoots: [source, pendingButton]))
        self.sourceRuntime = sourceRuntime
        self.destinationRuntime = destinationRuntime
        self.source = source
        self.pendingButton = pendingButton
        self.adoption = adoption
        departure = ButtonActionSourceDeparture(root: source, buttonActions: adoption)
        self.cleanupCheck = cleanupCheck
        self.previousTransaction = previousTransaction
        self.previousAnimation = previousAnimation
        initialized = true
    }

    func assertOriginalOwnership(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(adoption.isCurrent, file: file, line: line)
        XCTAssertTrue(departure.owns(source), file: file, line: line)
        XCTAssertTrue(source.parent === sourceRuntime.root, file: file, line: line)
    }

    func moveSource(to parent: ViewNode) {
        let transition = source.transition
        // Moving a still-mounted source must not recursively evaluate the same
        // removal modifiers through ordinary child removal.
        source.transition = .identity
        parent.addChild(source)
        source.transition = transition
    }

    func installReplacementAnimation() {
        source.animationStates[.opacity] = AnimationState(
            startValue: 0.6, endValue: 0.25, startTime: 99, duration: 7, easing: .linear)
    }

    func assertReplacementAnimation(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(source.animationStates[.opacity]?.endValue, 0.25, file: file, line: line)
        XCTAssertEqual(source.animationStates[.opacity]?.startTime, 99, file: file, line: line)
        XCTAssertEqual(source.animationStates[.opacity]?.duration, 7, file: file, line: line)
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        sourceRuntime.clock = { 0 }
        destinationRuntime.clock = { 0 }
        _ = adoption.finish(completed: false, check: cleanupCheck, completion: nil)
        source.transition = .identity
        source.reconcileAnimationModifiers = []
        source.animationStates = [:]
        sourceRuntime.stopRenderLifecycleCallbacks()
        destinationRuntime.stopRenderLifecycleCallbacks()
        sourceRuntime.root.removeAllChildren()
        destinationRuntime.root.removeAllChildren()
        sourceRuntime.cancelRenderLifecycleTasks()
        destinationRuntime.cancelRenderLifecycleTasks()
        currentTransaction = previousTransaction
        currentAnimationTransaction = previousAnimation
    }
}

@MainActor
private final class ButtonRemovalCompositionRows {
    var values = [0]
}

@MainActor
private final class ButtonRemovalCompositionComparisonProbe {
    var action: (() -> Void)?
    var comparisons = 0

    func compare() {
        comparisons += 1
        action?()
    }
}

private struct ButtonRemovalCompositionTrigger: Equatable {
    let value: Int
    let probe: ButtonRemovalCompositionComparisonProbe

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.probe.compare()
            return lhs.value == rhs.value
        }
    }
}

private final class ButtonRemovalCompositionReleaseHook {
    let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) { self.action = action }

    deinit { MainActor.assumeIsolated { [action] in action() } }
}
