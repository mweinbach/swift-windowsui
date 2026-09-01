import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedRemovalTransitionResolverTests: XCTestCase {
    func testAbsentTransactionUsesDefaultOrImplicitTimingWithoutMutatingTheNode() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        var clocks = 0
        fixture.runtime.clock = {
            clocks += 1
            return 12
        }

        let fallback = try animatedRemoval(fixture.node)
        XCTAssertEqual(fallback.states[.opacity]?.duration, 0.35)
        XCTAssertEqual(fallback.states[.opacity]?.easing, .easeInOut)
        XCTAssertEqual(fallback.resolvedAt, 12)
        XCTAssertEqual(fallback.initialOpacity, 0.6)
        XCTAssertEqual(fallback.frame, fixture.node.resolvedFrame)
        XCTAssertEqual(fallback.initialTransform, fixture.node.transform)
        XCTAssertTrue(fixture.node.animationStates.isEmpty)
        XCTAssertFalse(fixture.node.hasAppeared)

        fixture.node.implicitReconcileAnimation = AnimationTransaction(duration: 0.8, easing: .linear)
        let implicit = try animatedRemoval(fixture.node)
        XCTAssertEqual(implicit.states[.opacity]?.duration, 0.8)
        XCTAssertEqual(implicit.states[.opacity]?.easing, .linear)
        XCTAssertEqual(clocks, 2)
        XCTAssertTrue(fixture.node.animationStates.isEmpty)
    }

    func testExplicitNilDisabledAndZeroDurationTransactionsDoNotReadTheClock() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        var clocks = 0
        fixture.runtime.clock = {
            clocks += 1
            return 12
        }
        fixture.node.implicitReconcileAnimation = AnimationTransaction(duration: 0.8, easing: .linear)
        currentAnimationTransaction = (2, .easeIn)
        currentTransaction = Transaction()
        assertDisabledRemoval(fixture.node)

        var disabled = Transaction(animation: Animation(duration: 1, easing: .linear))
        disabled.disablesAnimations = true
        currentTransaction = disabled
        assertDisabledRemoval(fixture.node)

        currentTransaction = Transaction(animation: Animation(duration: 0, easing: .linear))
        assertDisabledRemoval(fixture.node)
        XCTAssertEqual(clocks, 0)
        XCTAssertTrue(fixture.node.animationStates.isEmpty)
    }

    func testModifiersRunFromOuterToInnerAndPreserveExplicitNil() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        var order: [String] = []
        currentTransaction = Transaction(animation: Animation(duration: 4, easing: .easeOut))
        fixture.node.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: {
                order.append("inner")
                $0.animation = Animation(duration: 2, easing: .easeIn)
            }),
            RetainedAnimationModifier(transaction: {
                order.append("outer")
                $0.animation = Animation(duration: 3, easing: .linear)
            }),
        ]

        let animation = try animatedRemoval(fixture.node)
        XCTAssertEqual(order, ["outer", "inner"])
        XCTAssertEqual(animation.states[.opacity]?.duration, 2)
        XCTAssertEqual(animation.states[.opacity]?.easing, .easeIn)

        currentTransaction = nil
        currentAnimationTransaction = nil
        fixture.node.implicitReconcileAnimation = AnimationTransaction(duration: 5, easing: .linear)
        fixture.node.reconcileAnimationModifiers = [RetainedAnimationModifier(animation: nil)]
        assertDisabledRemoval(fixture.node)
    }

    func testEveryRemovalEndpointAndCombinedOverwriteMatchesTheExistingRules() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        currentAnimationTransaction = (1.5, .linear)
        let existing = AnimationState(startValue: 0, endValue: 3, startTime: 2, duration: 20, easing: .easeOut)
        fixture.node.animationStates[.outlineWidth] = existing
        let cases: [(RetainedTransition.Kind, [AnimatableProperty: Double])] = [
            (.opacity, [.opacity: 0]),
            (.scale(scaleX: 0.4, scaleY: 0.5, anchorX: 0, anchorY: 1), [.transformScaleX: 0.4, .transformScaleY: 0.5]),
            (.offset(x: 6, y: 8), [.transformTranslationX: 6, .transformTranslationY: 8]),
            (.move(edge: .leading), [.transformTranslationX: -80, .transformTranslationY: 0]),
            (.move(edge: .trailing), [.transformTranslationX: 80, .transformTranslationY: 0]),
            (.move(edge: .top), [.transformTranslationX: 0, .transformTranslationY: -40]),
            (.move(edge: .bottom), [.transformTranslationX: 0, .transformTranslationY: 40]),
            (.slide, [.transformTranslationX: 80]),
            (.push(from: .top), [.transformTranslationX: 40, .transformScaleX: 0.85]),
            (
                .combined(.init(kind: .offset(x: 6, y: 8)), .init(kind: .slide)),
                [.transformTranslationX: 80, .transformTranslationY: 8]
            ),
            (
                .asymmetric(insertion: .init(kind: .opacity), removal: .init(kind: .offset(x: 9, y: 10))),
                [.transformTranslationX: 9, .transformTranslationY: 10]
            ),
        ]
        let starts: [AnimatableProperty: Double] = [
            .opacity: 0.6, .transformScaleX: 1.2, .transformScaleY: 1.4,
            .transformTranslationX: 3, .transformTranslationY: 4,
        ]
        for (kind, endpoints) in cases {
            fixture.node.transition = RetainedTransition(kind: kind)
            let animation = try animatedRemoval(fixture.node)
            XCTAssertEqual(animation.states.count, endpoints.count + 1)
            XCTAssertEqual(animation.removalProperties, Set(endpoints.keys))
            for (property, endpoint) in endpoints {
                let state = try XCTUnwrap(animation.states[property])
                XCTAssertEqual(state.startValue, starts[property])
                XCTAssertEqual(state.endValue, endpoint)
                XCTAssertEqual(state.startTime, 10)
                XCTAssertEqual(state.duration, 1.5)
                XCTAssertEqual(state.easing, .linear)
            }
            XCTAssertEqual(animation.states[.outlineWidth]?.startTime, existing.startTime)
            XCTAssertEqual(animation.states[.outlineWidth]?.endValue, existing.endValue)
            XCTAssertEqual(animation.earliestStartTime, 2)
            XCTAssertEqual(animation.duration, 20)
            XCTAssertEqual(animation.resolvedAt, 10)
            XCTAssertEqual(fixture.node.animationStates.count, 1)
        }
        fixture.node.transition = .identity
        assertDisabledRemoval(fixture.node)
        XCTAssertEqual(fixture.node.animationStates.count, 1)
    }

    func testFixedClockMarksOnlyThePropertiesWrittenByRemoval() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        fixture.node.animationStates[.transformTranslationX] = AnimationState(
            startValue: 20, endValue: 40, startTime: 10, duration: 2, easing: .easeIn)
        let animation = try animatedRemoval(fixture.node)
        XCTAssertEqual(animation.resolvedAt, 10)
        XCTAssertEqual(animation.states[.transformTranslationX]?.startTime, 10)
        XCTAssertEqual(animation.states[.transformTranslationX]?.startValue, 20)
        XCTAssertEqual(animation.removalProperties, [.opacity])
    }

    func testGuardedResolutionCallsEachModifierAndClockAtMostOnce() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        var modifiers = 0
        var clocks = 0
        fixture.node.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: {
                modifiers += 1
                $0.animation = Animation(duration: 0.4, easing: .linear)
            })
        ]
        fixture.runtime.clock = {
            clocks += 1
            return 15
        }
        let admission = try fixture.admission()
        let animation = try animatedRemoval(fixture.node, admission: admission)
        XCTAssertEqual(animation.resolvedAt, 15)
        XCTAssertEqual(modifiers, 1)
        XCTAssertEqual(clocks, 1)
        XCTAssertTrue(admission.isCurrent)
        assertRejectedRemoval(fixture.node, admission: admission)
        XCTAssertEqual(modifiers, 1)
        XCTAssertEqual(clocks, 1)
        XCTAssertTrue(fixture.node.animationStates.isEmpty)
    }

    func testOrdinaryPublicationPrecedesModifierCaptureDestruction() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        var sawPublishedAnimation = false
        var hook: RemovalResolverReleaseHook? = RemovalResolverReleaseHook {
            sawPublishedAnimation = fixture.node.animationStates[.opacity]?.endValue == 0
            fixture.node.animationStates[.opacity] = AnimationState(
                startValue: 0.6, endValue: 0.25, startTime: 10, duration: 1)
        }
        fixture.node.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: { [capture = hook] transaction in
                withExtendedLifetime(capture) {}
                fixture.node.reconcileAnimationModifiers = []
                transaction.animation = Animation(duration: 0.4, easing: .linear)
            })
        ]
        hook = nil

        XCTAssertTrue(RetainedRemovalTransitionResolver.applyOrdinary(node: fixture.node))
        XCTAssertTrue(sawPublishedAnimation)
        XCTAssertEqual(fixture.node.animationStates[.opacity]?.endValue, 0.25)
    }

    func testTriggerEqualityChangingTheSameConfigurationStopsLaterCallbacks() async throws {
        let fixture = RemovalResolverFixture()
        let trigger = RemovalResolverTriggerProbe()
        defer {
            trigger.action = nil
            fixture.finish()
        }
        var laterModifiers = 0
        var clocks = 0
        fixture.runtime.clock = {
            clocks += 1
            return 20
        }
        trigger.action = {
            let sameTransition = fixture.node.transition
            fixture.node.transition = sameTransition
        }
        fixture.node.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: { _ in laterModifiers += 1 }),
            RetainedAnimationModifier(animation: Animation(duration: 1), value: RemovalResolverTrigger(probe: trigger)),
        ]
        let admission = try fixture.admission()

        assertRejectedRemoval(fixture.node, admission: admission)
        XCTAssertEqual(trigger.comparisons, 1)
        XCTAssertEqual(laterModifiers, 0)
        XCTAssertEqual(clocks, 0)
        XCTAssertFalse(admission.isCurrent)
        XCTAssertTrue(fixture.node.animationStates.isEmpty)
    }

    func testModifierChangingAnotherDepartureRejectsTheWholeForest() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        let sibling = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        fixture.parent.addChild(sibling)
        var siblingModifiers = 0
        var clocks = 0
        sibling.reconcileAnimationModifiers = [RetainedAnimationModifier(transaction: { _ in siblingModifiers += 1 })]
        fixture.node.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: { _ in sibling.implicitReconcileAnimation = nil })
        ]
        fixture.runtime.clock = {
            clocks += 1
            return 20
        }
        let admission = try fixture.admission(roots: [fixture.node, sibling])

        assertRejectedRemoval(fixture.node, admission: admission)
        assertRejectedRemoval(sibling, admission: admission)
        XCTAssertFalse(admission.isCurrent)
        XCTAssertEqual(siblingModifiers, 0)
        XCTAssertEqual(clocks, 0)
    }

    func testParentReorderInvalidatesResolutionWithoutChangingAttachments() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        let sibling = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        fixture.parent.addChild(sibling)
        let original = fixture.node.captureLazyListAttachmentProof()
        let other = sibling.captureLazyListAttachmentProof()
        fixture.node.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: { _ in fixture.parent.setChildren([sibling, fixture.node]) })
        ]
        let admission = try fixture.admission(roots: [fixture.node, sibling])

        assertRejectedRemoval(fixture.node, admission: admission)
        XCTAssertTrue(original.isCurrent)
        XCTAssertTrue(other.isCurrent)
        XCTAssertFalse(admission.isCurrent)
        XCTAssertTrue(fixture.node.animationStates.isEmpty)
    }

    func testClockInvalidationRejectsTheResolvedAnimation() async throws {
        let fixture = RemovalResolverFixture()
        defer { fixture.finish() }
        var clocks = 0
        fixture.runtime.clock = {
            clocks += 1
            fixture.node.transition = RetainedTransition(kind: .slide)
            return 20
        }
        let admission = try fixture.admission()

        assertRejectedRemoval(fixture.node, admission: admission)
        XCTAssertEqual(clocks, 1)
        XCTAssertFalse(admission.isCurrent)
        XCTAssertTrue(fixture.node.animationStates.isEmpty)
    }

    func testIncomingSubtreeABAAndSourceOrderChangesStopLaterRemovalCallouts() async throws {
        for reorderSource in [false, true] {
            let fixture = RemovalResolverFixture()
            defer { fixture.finish() }
            let sourceParent = ViewNode()
            let incoming = ViewNode()
            let incomingChild = ViewNode()
            let otherSource = ViewNode()
            incoming.addChild(incomingChild)
            sourceParent.setChildren([incoming, otherSource])
            let incomingAttachment = incoming.captureLazyListAttachmentProof()
            let childAttachment = incomingChild.captureLazyListAttachmentProof()
            var mutations = 0
            var laterModifiers = 0
            var clocks = 0
            fixture.node.reconcileAnimationModifiers = [
                RetainedAnimationModifier(transaction: { _ in laterModifiers += 1 }),
                RetainedAnimationModifier(transaction: { _ in
                    mutations += 1
                    if reorderSource {
                        sourceParent.setChildren([otherSource, incoming])
                    } else {
                        incoming.removeAllChildren()
                        incoming.addChild(incomingChild)
                    }
                }),
            ]
            fixture.runtime.clock = {
                clocks += 1
                return 20
            }
            let nativeCheck = try XCTUnwrap(
                ComponentHost.makeRemovalTransitionCheck(
                    admission: nil, target: fixture.parent, parent: fixture.parent,
                    sourceParent: sourceParent, proposedChildren: [incoming], lazyJournal: nil))
            let admission = try XCTUnwrap(
                RetainedRemovalTransitionAdmission(nativeCheck: nativeCheck, departingRoots: [fixture.node]))

            assertRejectedRemoval(fixture.node, admission: admission)
            XCTAssertEqual(mutations, 1)
            XCTAssertEqual(laterModifiers, 0)
            XCTAssertEqual(clocks, 0)
            XCTAssertTrue(incomingAttachment.isCurrent)
            XCTAssertEqual(childAttachment.isCurrent, reorderSource)
            XCTAssertFalse(admission.isCurrent)
            XCTAssertTrue(fixture.node.parent === fixture.parent)
            XCTAssertTrue(fixture.node.animationStates.isEmpty)
        }
    }
}

@MainActor
private func animatedRemoval(
    _ node: ViewNode, admission: RetainedRemovalTransitionAdmission? = nil,
    file: StaticString = #filePath, line: UInt = #line
) throws -> RetainedRemovalTransitionAnimation {
    let result = RetainedRemovalTransitionResolver.resolve(node: node, admission: admission)
    if case .animated(let animation) = result { return animation }
    XCTFail("Expected an animation resolved from the current removal configuration", file: file, line: line)
    throw RemovalResolverTestError.expectedAnimation
}

@MainActor
private func assertDisabledRemoval(_ node: ViewNode, file: StaticString = #filePath, line: UInt = #line) {
    guard case .disabled = RetainedRemovalTransitionResolver.resolve(node: node) else {
        return XCTFail("Expected removal animation to be disabled", file: file, line: line)
    }
}

@MainActor
private func assertRejectedRemoval(
    _ node: ViewNode, admission: RetainedRemovalTransitionAdmission,
    file: StaticString = #filePath, line: UInt = #line
) {
    guard case .rejected = RetainedRemovalTransitionResolver.resolve(node: node, admission: admission) else {
        return XCTFail("Expected expired or already used removal admission to be rejected", file: file, line: line)
    }
}

private enum RemovalResolverTestError: Error { case expectedAnimation }

@MainActor
private final class RemovalResolverFixture {
    let node: ViewNode
    let parent: ViewNode
    let runtime: RetainedViewRuntime
    private let previousTransaction = currentTransaction
    private let previousAnimation = currentAnimationTransaction

    init() {
        currentTransaction = nil
        currentAnimationTransaction = nil
        let node = ViewNode(frame: Rect(x: 7, y: 9, width: 80, height: 40))
        node.resolvedFrame = node.frame
        node.opacity = 0.6
        node.transform.scaleX = 1.2
        node.transform.scaleY = 1.4
        node.transform.translationX = 3
        node.transform.translationY = 4
        node.transition = RetainedTransition(kind: .opacity)
        let parent = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200))
        parent.addChild(node)
        let runtime = RetainedViewRuntime(root: parent)
        runtime.clock = { 10 }
        self.node = node
        self.parent = parent
        self.runtime = runtime
    }

    func admission(roots: [ViewNode]? = nil) throws -> RetainedRemovalTransitionAdmission {
        let nativeCheck = try XCTUnwrap(
            ComponentHost.makeRemovalTransitionCheck(
                admission: nil, target: node, parent: parent, proposedChildren: [], lazyJournal: nil))
        return try XCTUnwrap(
            RetainedRemovalTransitionAdmission(
                nativeCheck: nativeCheck, departingRoots: roots ?? [node]))
    }

    func finish() {
        runtime.clock = { 0 }
        for child in parent.children {
            child.transition = .identity
            child.reconcileAnimationModifiers = []
            child.animationStates = [:]
        }
        runtime.stopRenderLifecycleCallbacks()
        parent.removeAllChildren()
        runtime.cancelRenderLifecycleTasks()
        currentTransaction = previousTransaction
        currentAnimationTransaction = previousAnimation
    }
}

@MainActor
private final class RemovalResolverTriggerProbe {
    var action: (() -> Void)?
    var comparisons = 0

    func compare() {
        comparisons += 1
        action?()
    }
}

private struct RemovalResolverTrigger: Equatable {
    let probe: RemovalResolverTriggerProbe

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.probe.compare()
            return lhs.probe === rhs.probe
        }
    }
}

private final class RemovalResolverReleaseHook {
    let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) { self.action = action }

    deinit { MainActor.assumeIsolated { [action] in action() } }
}
