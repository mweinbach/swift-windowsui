import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsGraphics
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class RetainedLongPressGestureTests: XCTestCase {
    func testDeadlineRunsOnceWithoutReleaseAndKeepsTheTimerAwakeOnlyWhilePending() async {
        let fixture = LongPressFixture()
        var completions = 0
        var pressing: [Bool] = []
        fixture.setContent {
            Text("Hold")
                .frame(width: 120, height: 60)
                .onLongPressGesture(
                    perform: { completions += 1 },
                    onPressingChanged: { pressing.append($0) }
                )
        }
        let point = fixture.center

        fixture.runtime.pointerDown(at: point)
        XCTAssertEqual(pressing, [true])
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        fixture.advance(to: 10.499)
        XCTAssertEqual(completions, 0)
        fixture.advance(to: 10.5)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(pressing, [true, false])
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)

        fixture.advance(to: 20)
        fixture.runtime.pointerUp(at: point)
        fixture.runtime.pointerCancelled()
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(pressing, [true, false])
    }

    func testReleaseAfterDeadlineRecognizesEvenWithoutAnAnimationTick() async {
        let fixture = LongPressFixture()
        var completions = 0
        fixture.setContent {
            Text("Hold").onLongPressGesture(minimumDuration: 0.2) { completions += 1 }
        }
        let point = fixture.center
        fixture.runtime.pointerDown(at: point)
        fixture.clock.now = 10.2
        fixture.runtime.pointerUp(at: point)
        XCTAssertEqual(completions, 1, "The exact captured deadline must not lose floating-point precision")
        fixture.advance(to: 11)
        fixture.runtime.pointerUp(at: point)
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testEarlyReleaseCancelsAndDoesNotBecomeALateSuccess() async {
        let fixture = LongPressFixture()
        var completions = 0
        var pressing: [Bool] = []
        fixture.setContent {
            Text("Hold").onLongPressGesture(
                minimumDuration: 0.5,
                pressing: { pressing.append($0) },
                perform: { completions += 1 }
            )
        }
        let point = fixture.center
        fixture.runtime.pointerDown(at: point)
        fixture.clock.now = 10.499
        fixture.runtime.pointerUp(at: point)
        fixture.advance(to: 30)
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(pressing, [true, false])
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testMaximumDistanceUsesLogicalEuclideanRadiusAndIncludesItsBoundary() async {
        let fixture = LongPressFixture()
        var completions = 0
        fixture.setContent {
            Text("Hold").frame(width: 120, height: 60)
                .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10) { completions += 1 }
        }
        let point = fixture.center
        fixture.runtime.pointerDown(at: point)
        fixture.runtime.pointerMoved(to: Point(x: point.x + 6, y: point.y + 8))
        fixture.advance(to: 10.5)
        XCTAssertEqual(completions, 1)

        fixture.runtime.pointerUp(at: point)
        fixture.clock.now = 11
        fixture.runtime.pointerDown(at: point)
        fixture.runtime.pointerMoved(to: Point(x: point.x + 6.01, y: point.y + 8))
        fixture.runtime.pointerMoved(to: point)
        fixture.advance(to: 12)
        fixture.runtime.pointerUp(at: point)
        XCTAssertEqual(completions, 1, "Returning inside the radius must not revive a canceled attempt")
    }

    func testReleaseChecksDisplacementWhenNoMoveEventWasDelivered() async {
        let fixture = LongPressFixture()
        var completions = 0
        fixture.setContent {
            Text("Hold").onLongPressGesture { completions += 1 }
        }
        let point = fixture.center
        fixture.runtime.pointerDown(at: point)
        fixture.clock.now = 11
        fixture.runtime.pointerUp(at: Point(x: point.x + 11, y: point.y))
        XCTAssertEqual(completions, 0)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testLeavingSmallViewBoundsWithinTheDistanceLimitDoesNotCancel() async {
        let fixture = LongPressFixture()
        var completions = 0
        fixture.setContent {
            Rectangle().frame(width: 8, height: 8)
                .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10) { completions += 1 }
        }
        let point = fixture.center
        fixture.runtime.pointerDown(at: point)
        fixture.runtime.pointerMoved(to: Point(x: point.x + 6, y: point.y))
        fixture.runtime.pointerExitedWindow()
        fixture.advance(to: 10.5)
        XCTAssertEqual(completions, 1, "Hover exit is not capture loss or excessive gesture movement")
    }

    func testRemovalHidingDisablingCaptureLossAndModifierRemovalCancelExactlyOnce() async {
        let cancellations: [(String, (LongPressFixture, ViewNode) -> Void)] = [
            ("capture", { fixture, _ in fixture.runtime.pointerCancelled() }),
            ("hidden ancestor", { fixture, _ in fixture.runtime.root.isHidden = true }),
            ("removed subtree", { fixture, _ in fixture.runtime.root.removeAllChildren() }),
            ("disabled recognizer", { _, node in node.longPressGesture?.isEnabled = false }),
            ("hit testing", { _, node in node.isHitTestVisible = false }),
            ("removed modifier", { _, node in node.longPressGesture = nil }),
            ("window focus", { fixture, _ in fixture.runtime.keyboardFocusDidLeaveWindow() }),
        ]
        for (name, cancel) in cancellations {
            let fixture = LongPressFixture()
            var completions = 0
            var pressing: [Bool] = []
            fixture.setContent {
                Text("Hold").onLongPressGesture(
                    perform: { completions += 1 },
                    onPressingChanged: { pressing.append($0) }
                )
            }
            guard let node = fixture.gestureNode else { return XCTFail("Missing recognizer") }
            let point = fixture.center
            fixture.runtime.pointerDown(at: point)
            cancel(fixture, node)
            fixture.advance(to: 20)
            fixture.runtime.pointerUp(at: point)
            fixture.runtime.pointerCancelled()
            XCTAssertEqual(completions, 0, name)
            XCTAssertEqual(pressing, [true, false], name)
            XCTAssertFalse(fixture.runtime.hasActiveAnimations, name)
        }
    }

    func testInheritedDisabledAndGestureMaskPreventRecognition() async {
        for enabled in [false, true] {
            let fixture = LongPressFixture()
            var completions = 0
            fixture.setContent {
                VStack {
                    Text("Hold").frame(width: 120, height: 60)
                        .onLongPressGesture { completions += 1 }
                }
                .disabled(!enabled)
            }
            fixture.runtime.pointerDown(at: fixture.center)
            fixture.advance(to: 11)
            XCTAssertEqual(completions, enabled ? 1 : 0)
        }

        let fixture = LongPressFixture()
        fixture.setContent {
            Text("Masked").gesture(LongPressGesture(), including: .none)
        }
        XCTAssertNil(fixture.gestureNode)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testReconciliationKeepsOriginalThresholdsAndUsesCurrentCompletion() async {
        let fixture = LongPressFixture()
        var duration = 0.5
        var distance = 10.0
        var version = 1
        var completions: [Int] = []
        fixture.setContent {
            let capturedVersion = version
            return Text("Hold").frame(width: 120, height: 60)
                .onLongPressGesture(minimumDuration: duration, maximumDistance: distance) {
                    completions.append(capturedVersion)
                }
        }
        let node = fixture.gestureNode
        let point = fixture.center
        fixture.runtime.pointerDown(at: point)
        fixture.clock.now = 10.25
        duration = 5
        distance = 1
        version = 2
        fixture.host.reload()
        XCTAssertTrue(fixture.gestureNode === node)
        fixture.runtime.pointerMoved(to: Point(x: point.x + 6, y: point.y))
        fixture.advance(to: 10.5)
        XCTAssertEqual(completions, [2])

        fixture.runtime.pointerUp(at: point)
        fixture.clock.now = 11
        fixture.runtime.pointerDown(at: point)
        fixture.runtime.pointerMoved(to: Point(x: point.x + 2, y: point.y))
        fixture.advance(to: 20)
        XCTAssertEqual(completions, [2], "New attempts use the replacement thresholds")
    }

    func testGestureStateUpdatesVisibleBodyAndResetsOnceWithoutTerminalUpdatingFalse() async {
        let fixture = LongPressFixture()
        var updates: [Bool] = []
        var changes: [Bool] = []
        var endings: [Bool] = []
        let view = LongPressStateProbe(
            onUpdating: { value, state, _ in
                updates.append(value)
                state = value
            },
            onChanged: { changes.append($0) },
            onEnded: { endings.append($0) }
        )
        fixture.setContent { view }
        let node = fixture.gestureNode
        let point = fixture.center

        fixture.runtime.pointerDown(at: point)
        XCTAssertTrue(view.isPressing)
        XCTAssertTrue(fixture.texts.contains("HOLDING"))
        XCTAssertTrue(fixture.gestureNode === node, "The updating invalidation must retain the active owner")
        XCTAssertEqual(fixture.invalidations, 1)
        fixture.advance(to: 10.5)
        XCTAssertFalse(view.isPressing)
        XCTAssertTrue(fixture.texts.contains("READY"))
        XCTAssertEqual(fixture.invalidations, 2)
        fixture.runtime.pointerUp(at: point)
        fixture.advance(to: 12)
        XCTAssertEqual(fixture.invalidations, 2)
        XCTAssertEqual(updates, [true])
        XCTAssertEqual(changes, [true])
        XCTAssertEqual(endings, [true])
    }

    func testGestureStateCancellationResetsWithoutEndedOrTerminalUpdating() async {
        let fixture = LongPressFixture()
        var updates: [Bool] = []
        var endings: [Bool] = []
        let view = LongPressStateProbe(
            onUpdating: { value, state, _ in
                updates.append(value)
                state = value
            },
            onEnded: { endings.append($0) }
        )
        fixture.setContent { view }
        let point = fixture.center
        fixture.runtime.pointerDown(at: point)
        fixture.clock.now = 10.1
        fixture.runtime.pointerUp(at: point)
        fixture.advance(to: 12)
        XCTAssertFalse(view.isPressing)
        XCTAssertEqual(updates, [true])
        XCTAssertEqual(endings, [])
        XCTAssertEqual(fixture.invalidations, 2)
    }

    func testUpdatingTransactionControlsRealReconciliationAndRestoresAmbientScope() async {
        let fixture = LongPressFixture()
        let view = LongPressStateProbe(onUpdating: { value, state, transaction in
            state = value
            transaction.animation = .linear(duration: 1)
        })
        fixture.setContent { view }
        guard let node = fixture.gestureNode else { return XCTFail("Missing recognizer") }
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        currentTransaction = nil
        currentAnimationTransaction = nil
        withAnimation(.easeIn(duration: 4)) {
            fixture.runtime.pointerDown(at: fixture.center)
            XCTAssertEqual(currentTransaction?.animation?.duration, 4)
        }
        XCTAssertNil(currentTransaction)
        XCTAssertEqual(fixture.transactions.compactMap { $0 }.first?.animation?.duration, 1)
        XCTAssertEqual(node.opacity, 1, accuracy: 0.0001)
        fixture.advance(to: 10.25)
        XCTAssertEqual(node.opacity, 0.8125, accuracy: 0.0001)
        XCTAssertTrue(view.isPressing)
        fixture.runtime.pointerCancelled()
        XCTAssertFalse(view.isPressing)
    }

    func testDefaultUpdatingPreservesFullAmbientTransactionBeforeLegacyAnimation() async {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        currentTransaction = nil
        currentAnimationTransaction = nil

        let fixture = LongPressFixture()
        let view = LongPressStateProbe()
        fixture.setContent { view }
        var ambient = Transaction(animation: .easeOut(duration: 0.8))
        ambient.disablesAnimations = true
        ambient.isContinuous = true
        ambient.scrollTargetAnchor = .bottom
        ambient.tracksVelocity = true
        currentTransaction = ambient
        currentAnimationTransaction = (duration: 4, easing: .easeIn)

        fixture.runtime.pointerDown(at: fixture.center)
        guard let transaction = fixture.transactions.compactMap({ $0 }).first else {
            return XCTFail("Missing gesture-state transaction")
        }
        XCTAssertEqual(transaction.animation?.duration, 0.8)
        XCTAssertEqual(transaction.animation?.easing, .easeOut)
        XCTAssertTrue(transaction.disablesAnimations)
        XCTAssertTrue(transaction.isContinuous)
        XCTAssertEqual(transaction.scrollTargetAnchor, .bottom)
        XCTAssertTrue(transaction.tracksVelocity)
        XCTAssertEqual(currentTransaction?.animation?.duration, 0.8)
        XCTAssertTrue(currentTransaction?.disablesAnimations == true)
        XCTAssertEqual(currentAnimationTransaction?.duration, 4)
        XCTAssertEqual(currentAnimationTransaction?.easing, .easeIn)

        currentTransaction = nil
        currentAnimationTransaction = nil
        fixture.runtime.pointerCancelled()
        XCTAssertFalse(view.isPressing)
    }

    func testDefaultUpdatingInheritsLegacyAnimationAndReachesItsRealMidpoint() async {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        currentTransaction = nil
        currentAnimationTransaction = nil

        let fixture = LongPressFixture()
        let view = LongPressStateProbe()
        fixture.setContent { view }
        guard let node = fixture.gestureNode else { return XCTFail("Missing recognizer") }
        currentAnimationTransaction = (duration: 0.4, easing: .linear)

        fixture.runtime.pointerDown(at: fixture.center)
        guard let transaction = fixture.transactions.compactMap({ $0 }).first else {
            return XCTFail("Missing gesture-state transaction")
        }
        XCTAssertEqual(transaction.animation?.duration, 0.4)
        XCTAssertEqual(transaction.animation?.easing, .linear)
        XCTAssertFalse(transaction.disablesAnimations)
        XCTAssertNil(currentTransaction)
        XCTAssertEqual(currentAnimationTransaction?.duration, 0.4)
        XCTAssertEqual(currentAnimationTransaction?.easing, .linear)
        XCTAssertEqual(node.opacity, 1, accuracy: 0.0001)

        fixture.advance(to: 10.2)
        XCTAssertEqual(node.opacity, 0.625, accuracy: 0.0001)
        XCTAssertTrue(view.isPressing)
        currentAnimationTransaction = nil
        fixture.runtime.pointerCancelled()
        XCTAssertFalse(view.isPressing)
    }

    func testExplicitNilAnimationTransactionDoesNotFallBackToLegacyAnimation() async {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        currentTransaction = nil
        currentAnimationTransaction = nil

        let fixture = LongPressFixture()
        let view = LongPressStateProbe()
        fixture.setContent { view }
        guard let node = fixture.gestureNode else { return XCTFail("Missing recognizer") }
        currentTransaction = Transaction(animation: nil)
        currentAnimationTransaction = (duration: 0.4, easing: .linear)

        fixture.runtime.pointerDown(at: fixture.center)
        guard let transaction = fixture.transactions.compactMap({ $0 }).first else {
            return XCTFail("Missing explicit gesture-state transaction")
        }
        XCTAssertNil(transaction.animation)
        XCTAssertFalse(transaction.disablesAnimations)
        XCTAssertNotNil(currentTransaction)
        XCTAssertNil(currentTransaction?.animation)
        XCTAssertEqual(currentAnimationTransaction?.duration, 0.4)
        XCTAssertEqual(node.opacity, 0.25, accuracy: 0.0001)
        fixture.advance(to: 10.2)
        XCTAssertEqual(node.opacity, 0.25, accuracy: 0.0001)

        currentTransaction = nil
        currentAnimationTransaction = nil
        fixture.runtime.pointerCancelled()
        XCTAssertFalse(view.isPressing)
    }

    func testChangedCallbackCanRemoveTheOwnerAndResetGestureState() async {
        let fixture = LongPressFixture()
        var endings = 0
        let view = LongPressStateProbe(
            onChanged: { _ in fixture.host.setComponents { [] } },
            onEnded: { _ in endings += 1 }
        )
        fixture.setContent { view }
        fixture.runtime.pointerDown(at: fixture.center)
        fixture.advance(to: 12)
        XCTAssertFalse(view.isPressing)
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertEqual(endings, 0)
        XCTAssertEqual(fixture.invalidations, 2)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testUpdatingCallbackRemovalStillRunsItsDeferredCleanupExactlyOnce() async {
        let fixture = LongPressFixture()
        var endings = 0
        let view = LongPressStateProbe(
            onUpdating: { value, state, _ in
                state = value
                fixture.host.setComponents { [] }
            },
            onEnded: { _ in endings += 1 }
        )
        fixture.setContent { view }
        fixture.runtime.pointerDown(at: fixture.center)
        fixture.advance(to: 12)
        XCTAssertFalse(view.isPressing)
        XCTAssertEqual(fixture.invalidations, 2)
        XCTAssertEqual(endings, 0)
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testCompletionCanRemoveCancelAndTickReentrantlyWithoutFinishingTwice() async {
        let fixture = LongPressFixture()
        var endings = 0
        let view = LongPressStateProbe(onEnded: { _ in
            endings += 1
            fixture.host.setComponents { [] }
            fixture.runtime.pointerCancelled()
            _ = fixture.runtime.tickAnimations(at: 20)
        })
        fixture.setContent { view }
        fixture.runtime.pointerDown(at: fixture.center)
        fixture.advance(to: 10.5)
        XCTAssertEqual(endings, 1)
        XCTAssertFalse(view.isPressing)
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testLateReleaseCompletionCanStartANewPressWithoutOldReleaseClearingIt() async {
        let fixture = LongPressFixture()
        var endings = 0
        let view = LongPressStateProbe(onEnded: { _ in
            endings += 1
            if endings == 1 {
                fixture.clock.now = 11
                fixture.runtime.pointerDown(at: fixture.center)
            }
        })
        fixture.setContent { view }
        let point = fixture.center
        fixture.runtime.pointerDown(at: point)
        fixture.clock.now = 10.75
        fixture.runtime.pointerUp(at: point)
        XCTAssertEqual(endings, 1)
        XCTAssertTrue(view.isPressing)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        fixture.advance(to: 11.499)
        XCTAssertEqual(endings, 1)
        fixture.advance(to: 11.5)
        XCTAssertEqual(endings, 2)
        XCTAssertFalse(view.isPressing)
    }

    func testReentrantUpdatingDoesNotRunStaleLaterUpdatersOrResetNewAttempt() async {
        let fixture = LongPressFixture()
        var firstUpdates = 0
        var secondUpdates = 0
        let view = LongPressTwoStateProbe(
            onFirstUpdate: {
                firstUpdates += 1
                if firstUpdates == 1 {
                    fixture.clock.now = 11
                    fixture.runtime.pointerDown(at: fixture.center)
                }
            },
            onSecondUpdate: { secondUpdates += 1 }
        )
        fixture.setContent { view }
        fixture.runtime.pointerDown(at: fixture.center)
        XCTAssertEqual(firstUpdates, 2)
        XCTAssertEqual(secondUpdates, 1)
        XCTAssertTrue(view.first)
        XCTAssertTrue(view.second)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        fixture.advance(to: 11.5)
        XCTAssertFalse(view.first)
        XCTAssertFalse(view.second)
        XCTAssertEqual(secondUpdates, 1)
    }

    func testReconciliationCancellationCallbackCannotBeOverwrittenByOuterRebuild() async {
        let fixture = LongPressFixture()
        var pressing: [Bool] = []
        fixture.setContent {
            Text("Hold").id("original")
                .onLongPressGesture(
                    perform: {},
                    onPressingChanged: { value in
                        pressing.append(value)
                        if !value {
                            fixture.setContent { Text("Callback replacement").id("replacement") }
                        }
                    }
                )
        }
        fixture.runtime.pointerDown(at: fixture.center)
        fixture.setContent { Text("Stale outer rebuild").id("original") }
        XCTAssertEqual(pressing, [true, false])
        XCTAssertTrue(fixture.texts.contains("Callback replacement"))
        XCTAssertFalse(fixture.texts.contains("Stale outer rebuild"))
        fixture.advance(to: 20)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testInvalidConfigurationAndClockValuesNeverLeaveAPendingTimer() async {
        let cases: [(Double, Double, Double)] = [
            (.nan, 10, 10), (.infinity, 10, 10), (-1, 10, 10),
            (0.5, .nan, 10), (0.5, .infinity, 10), (0.5, -1, 10),
            (0.5, 10, .nan), (0.5, 10, .infinity),
            (.greatestFiniteMagnitude, 10, .greatestFiniteMagnitude),
        ]
        for (duration, distance, time) in cases {
            let fixture = LongPressFixture()
            var completions = 0
            fixture.setContent {
                Text("Hold").onLongPressGesture(minimumDuration: duration, maximumDistance: distance) {
                    completions += 1
                }
            }
            fixture.clock.now = time
            fixture.runtime.pointerDown(at: fixture.center)
            XCTAssertEqual(completions, 0)
            XCTAssertFalse(fixture.runtime.hasActiveAnimations)
        }
    }

    func testDirectChildReplacementDefersCancellationUntilItsIndexIsNoLongerInUse() async {
        let fixture = LongPressFixture()
        fixture.setContent {
            Text("Hold").onLongPressGesture(
                perform: {},
                onPressingChanged: { pressing in
                    if !pressing { fixture.runtime.root.removeAllChildren() }
                }
            )
        }
        fixture.runtime.pointerDown(at: fixture.center)
        fixture.runtime.root.replaceChild(at: 0, with: ViewNode(text: "Replacement"))
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testRemoveAllChildrenPreservesReplacementInstalledByCancellationCallback() async {
        let fixture = LongPressFixture()
        let replacement = ViewNode(text: "Replacement")
        fixture.setContent {
            Text("Hold").onLongPressGesture(
                perform: {},
                onPressingChanged: { pressing in
                    if !pressing { fixture.runtime.root.addChild(replacement) }
                }
            )
        }
        fixture.runtime.pointerDown(at: fixture.center)
        fixture.runtime.root.removeAllChildren()
        XCTAssertEqual(fixture.runtime.root.children.count, 1)
        XCTAssertTrue(fixture.runtime.root.children.first === replacement)
        XCTAssertTrue(replacement.parent === fixture.runtime.root)
    }

    func testCancellationCanReattachRemovedNodeWithoutLeavingItsRuntimeDetached() async {
        let fixture = LongPressFixture()
        var heldNode: ViewNode?
        var didReattach = false
        var completions = 0
        fixture.setContent {
            Text("Hold").onLongPressGesture(
                perform: { completions += 1 },
                onPressingChanged: { pressing in
                    if !pressing, !didReattach, let heldNode {
                        didReattach = true
                        fixture.runtime.root.addChild(heldNode)
                    }
                }
            )
        }
        guard let node = fixture.gestureNode else { return XCTFail("Missing recognizer") }
        heldNode = node
        fixture.runtime.pointerDown(at: fixture.center)
        fixture.runtime.root.removeChild(node)
        XCTAssertTrue(node.parent === fixture.runtime.root)
        fixture.clock.now = 11
        fixture.runtime.pointerDown(at: fixture.center)
        fixture.advance(to: 11.5)
        XCTAssertEqual(completions, 1, "A callback-reattached node must participate in its runtime again")
    }

    func testModalAppearingBeforeTheDeadlineCancelsTheBackgroundAttempt() async {
        let fixture = LongPressFixture()
        var completions = 0
        var pressing: [Bool] = []
        fixture.setContent {
            Text("Hold").onLongPressGesture(
                perform: { completions += 1 },
                onPressingChanged: { pressing.append($0) }
            )
        }
        let point = fixture.center
        fixture.runtime.pointerDown(at: point)
        let modal = ViewNode(
            frame: Rect(x: 0, y: 0, width: 320, height: 160),
            accessibilityTraits: [.isModal]
        )
        modal.paintsInDeferredPhase = true
        fixture.runtime.root.addChild(modal)
        // Deliberately no render between insertion and the due tick.
        fixture.advance(to: 10.5)
        fixture.runtime.pointerUp(at: point)
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(pressing, [true, false])
    }

    func testPaintOnlyModalReorderingCancelsTheFormerForegroundAttemptAtDeadline() async {
        for deferred in [false, true] {
            let fixture = LongPressFixture()
            let foreground = ViewNode(
                frame: Rect(x: 0, y: 0, width: 320, height: 160),
                accessibilityTraits: [.isModal]
            )
            let background = ViewNode(
                frame: Rect(x: 0, y: 0, width: 320, height: 160),
                accessibilityTraits: [.isModal]
            )
            foreground.zIndex = 1
            foreground.paintsInDeferredPhase = deferred
            background.paintsInDeferredPhase = deferred
            var completions = 0
            var pressing: [Bool] = []
            foreground.longPressGesture = RetainedLongPressGesture(
                onPressingChanged: { pressing.append($0) },
                onRecognized: { completions += 1 }
            )
            fixture.runtime.root.addChild(foreground)
            fixture.runtime.root.addChild(background)
            _ = fixture.runtime.renderScene()
            XCTAssertTrue(fixture.runtime.activeModalPresentationNode === foreground)

            let point = Point(x: 120, y: 20)
            fixture.runtime.pointerDown(at: point)
            XCTAssertEqual(pressing, [true])
            _ = fixture.runtime.renderScene()
            XCTAssertTrue(fixture.runtime.dirtyFlags.isEmpty)
            background.zIndex = 2
            XCTAssertEqual(fixture.runtime.dirtyFlags, .paint)
            XCTAssertTrue(fixture.runtime.activeModalPresentationNode === foreground)

            // No render or layout occurs between the paint-only reorder and
            // the due tick; recognition must refresh the prepaint authority.
            fixture.advance(to: 10.5)
            XCTAssertTrue(fixture.runtime.activeModalPresentationNode === background)
            XCTAssertEqual(completions, 0)
            XCTAssertEqual(pressing, [true, false])
            XCTAssertFalse(fixture.runtime.hasActiveAnimations)
            fixture.runtime.pointerUp(at: point)
            XCTAssertEqual(completions, 0)
        }
    }

    func testDeadlineLayoutCallbackCanReenterTickOrReleaseWithoutRecursionOrLostRecognition() async {
        for releases in [false, true] {
            let fixture = LongPressFixture()
            var completions = 0
            fixture.setContent {
                Text("Hold").onLongPressGesture { completions += 1 }
            }
            let point = fixture.center
            fixture.runtime.pointerDown(at: point)
            var layouts = 0
            fixture.runtime.root.onLayout = { _ in
                layouts += 1
                if releases {
                    if layouts == 1 { fixture.runtime.pointerUp(at: point) }
                } else {
                    _ = fixture.runtime.tickAnimations(at: fixture.clock.now)
                }
            }
            fixture.runtime.setRootSize(IntSize(width: 321, height: 160))
            fixture.advance(to: 10.5)
            XCTAssertGreaterThan(layouts, 0)
            XCTAssertLessThan(layouts, 5)
            XCTAssertEqual(completions, 1)
            XCTAssertFalse(fixture.runtime.hasActiveAnimations)
        }
    }

    func testCrossRuntimeMoveDefersCancellationUntilTheWholeReparentIsComplete() async {
        let fixture = LongPressFixture()
        let destination = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 160)))
        var heldNode: ViewNode?
        fixture.setContent {
            Text("Hold").onLongPressGesture(
                perform: {},
                onPressingChanged: { pressing in
                    if !pressing, let heldNode { fixture.runtime.root.addChild(heldNode) }
                }
            )
        }
        guard let node = fixture.gestureNode else { return XCTFail("Missing recognizer") }
        heldNode = node
        fixture.runtime.pointerDown(at: fixture.center)
        destination.root.addChild(node)
        XCTAssertTrue(destination.root.children.isEmpty)
        XCTAssertEqual(fixture.runtime.root.children.count, 1)
        XCTAssertTrue(fixture.runtime.root.children.first === node)
        XCTAssertTrue(node.parent === fixture.runtime.root)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
        XCTAssertFalse(destination.hasActiveAnimations)
    }

    func testTerminalCallbackCanPressAnotherOwnerWithoutStaleChromeOrFocusCleanup() async {
        for recognizes in [true, false] {
            let fixture = LongPressFixture()
            let first = ViewNode(frame: Rect(x: 0, y: 0, width: 60, height: 40), isHitTestVisible: true)
            let second = ViewNode(
                frame: Rect(x: 100, y: 0, width: 60, height: 40),
                isFocusable: true, isHitTestVisible: true
            )
            first.interactionSurface = RetainedInteractionSurface(
                idleBackground: .black, pressedBackground: .white,
                hoverDuration: 0, pressDuration: 0, focusDuration: 0
            )
            var completions = 0
            first.longPressGesture = RetainedLongPressGesture(
                onPressingChanged: { pressing in
                    if !pressing { fixture.runtime.pointerDown(at: Point(x: 120, y: 20)) }
                },
                onRecognized: { completions += 1 }
            )
            second.longPressGesture = RetainedLongPressGesture(onRecognized: {})
            fixture.runtime.root.addChild(first)
            fixture.runtime.root.addChild(second)
            fixture.runtime.pointerDown(at: Point(x: 20, y: 20))
            XCTAssertEqual(first.backgroundColor, .white)
            if recognizes {
                fixture.advance(to: 10.5)
            } else {
                fixture.runtime.keyboardFocusDidLeaveWindow()
            }
            XCTAssertEqual(completions, recognizes ? 1 : 0)
            XCTAssertEqual(first.backgroundColor, .black)
            XCTAssertEqual(fixture.runtime.interactionPhase(for: second), .pressed)
            XCTAssertTrue(fixture.runtime.focusedNode === second)
            XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        }
    }

    func testZeroDurationRecognizesImmediatelyAndAbsentGesturesStaySparse() async {
        let node = ViewNode()
        XCTAssertNil(node.longPressGesture)
        node.longPressGesture = nil
        XCTAssertFalse(node.hasAllocatedInteractionHandlers)
        XCTAssertFalse(Mirror(reflecting: node).children.compactMap(\.label).contains("longPressGesture"))

        let fixture = LongPressFixture()
        var completions = 0
        fixture.setContent {
            Text("Hold").onLongPressGesture(minimumDuration: 0, maximumDistance: 0) { completions += 1 }
        }
        fixture.runtime.pointerDown(at: fixture.center)
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testPrimaryTouchAndMouseShareLogicalDistanceTimingAndCaptureCancellation() async {
        let clock = RuntimeTestClock()
        clock.now = 10
        var completions = 0
        var pressing: [Bool] = []
        let fixture = makeLongPressWindow(
            clock: clock,
            content: AnyView(
                Text("Hold").frame(width: 120, height: 60)
                    .onLongPressGesture(
                        minimumDuration: 0.5,
                        maximumDistance: 10,
                        perform: { completions += 1 },
                        onPressingChanged: { pressing.append($0) }
                    )
            )
        )
        guard let node = firstLongPressNode(in: fixture.host.hostedRuntime.root) else {
            return XCTFail("Missing hosted recognizer")
        }
        let logical = longPressCenter(of: node)
        let physical = Point(x: logical.x * 2, y: logical.y * 2)
        fixture.host.window(fixture.window, touchBegan: [physical])
        fixture.host.window(fixture.window, touchBegan: [Point(x: 600, y: 300)])
        fixture.host.window(
            fixture.window, touchMoved: [Point(x: physical.x + 12, y: physical.y + 16)]
        )
        clock.now = 10.5
        fixture.host.window(fixture.window, animationFrameAt: clock.now)
        XCTAssertEqual(completions, 1)
        fixture.host.window(fixture.window, touchEnded: [physical])

        clock.now = 11
        fixture.host.window(fixture.window, leftMouseDownAt: physical)
        fixture.host.window(fixture.window, pointerMovedTo: Point(x: physical.x + 20.02, y: physical.y))
        clock.now = 12
        fixture.host.window(fixture.window, leftMouseUpAt: physical)
        XCTAssertEqual(completions, 1)

        clock.now = 13
        fixture.host.window(fixture.window, touchBegan: [physical])
        fixture.host.windowDidCancelPointerInteraction(fixture.window)
        clock.now = 14
        fixture.host.window(fixture.window, animationFrameAt: clock.now)
        fixture.host.window(fixture.window, touchEnded: [physical])
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(pressing, [true, false, true, false, true, false])
    }

    func testLiveGalleryShowsHoldingAndConfirmationThenResetsThroughRealInput() async {
        let clock = RuntimeTestClock()
        clock.now = 10
        let state = DemoLongPressState()
        let fixture = makeLongPressWindow(
            clock: clock,
            content: AnyView(DemoLongPressShowcase(state: state).frame(width: 360)),
            size: IntSize(width: 420, height: 280)
        )
        let runtime = fixture.host.hostedRuntime
        guard let target = firstLongPressNode(in: runtime.root) else {
            return XCTFail("Missing live gallery long-press target")
        }
        let point = longPressCenter(of: target)
        let physical = Point(x: point.x * 2, y: point.y * 2)
        fixture.host.window(fixture.window, leftMouseDownAt: physical)
        fixture.host.windowNeedsDisplay(fixture.window)
        XCTAssertTrue(state.isPressing)
        XCTAssertTrue(longPressTexts(in: runtime.root).contains("Keep holding..."))
        clock.now = 10.59
        fixture.host.window(fixture.window, animationFrameAt: clock.now)
        XCTAssertEqual(state.confirmationCount, 0)
        clock.now = 10.6
        fixture.host.window(fixture.window, animationFrameAt: clock.now)
        fixture.host.windowNeedsDisplay(fixture.window)
        XCTAssertFalse(state.isPressing)
        XCTAssertEqual(state.confirmationCount, 1)
        XCTAssertTrue(longPressTexts(in: runtime.root).contains("Confirmed 1 time"))
        fixture.host.window(fixture.window, leftMouseUpAt: physical)
        XCTAssertEqual(state.confirmationCount, 1)

        func resetNode(in node: ViewNode) -> ViewNode? {
            if node.accessibilityIdentifier == "gallery.long-press.reset" { return node }
            return node.children.lazy.compactMap { resetNode(in: $0) }.first
        }
        guard let reset = resetNode(in: runtime.root) else { return XCTFail("Missing reset control") }
        let resetCenter = longPressCenter(of: reset)
        let resetPhysical = Point(x: resetCenter.x * 2, y: resetCenter.y * 2)
        fixture.host.window(fixture.window, leftMouseDownAt: resetPhysical)
        fixture.host.window(fixture.window, leftMouseUpAt: resetPhysical)
        fixture.host.windowNeedsDisplay(fixture.window)
        XCTAssertEqual(state.confirmationCount, 0)
        XCTAssertTrue(longPressTexts(in: runtime.root).contains("Ready to hold"))
        XCTAssertTrue(DemoGalleryCategory.controls.matches(query: "long press gesture"))
    }
}

@MainActor
private final class LongPressFixture {
    let clock = RuntimeTestClock()
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    var invalidations = 0
    var transactions: [Transaction?] = []

    init() {
        runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 160)))
        host = ComponentHost(runtime: runtime)
        clock.now = 10
        runtime.clock = { [clock] in clock.now }
    }

    func setContent<V: View>(_ build: @escaping @MainActor () -> V) {
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 320, height: 160) },
            invalidateHandler: { [weak self] in
                guard let self else { return }
                invalidations += 1
                transactions.append(currentTransaction)
                host.reload()
            }
        )
        host.setComponents { [build().makeComponent(context: context)] }
        _ = runtime.renderScene()
    }

    var gestureNode: ViewNode? { firstLongPressNode(in: runtime.root) }

    var center: Point {
        guard let gestureNode else { return .zero }
        return longPressCenter(of: gestureNode)
    }

    var texts: [String] {
        longPressTexts(in: runtime.root)
    }

    func advance(to time: Double) {
        clock.now = time
        _ = runtime.tickAnimations(at: time)
    }
}

private struct LongPressStateProbe: View {
    @GestureState var isPressing = false
    var onUpdating: @MainActor (Bool, inout Bool, inout Transaction) -> Void = { value, state, _ in state = value }
    var onChanged: @MainActor (Bool) -> Void = { _ in }
    var onEnded: @MainActor (Bool) -> Void = { _ in }

    var body: some View {
        Text(isPressing ? "HOLDING" : "READY")
            .frame(width: 120, height: 60)
            .opacity(isPressing ? 0.25 : 1)
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .updating($isPressing, body: onUpdating)
                    .onChanged(onChanged)
                    .onEnded(onEnded)
            )
    }
}

private struct LongPressTwoStateProbe: View {
    @GestureState var first = false
    @GestureState var second = false
    var onFirstUpdate: @MainActor () -> Void
    var onSecondUpdate: @MainActor () -> Void

    var body: some View {
        Text(first && second ? "HOLDING" : "READY")
            .frame(width: 120, height: 60)
            .gesture(
                LongPressGesture()
                    .updating($first) { value, state, _ in
                        state = value
                        onFirstUpdate()
                    }
                    .updating($second) { value, state, _ in
                        state = value
                        onSecondUpdate()
                    }
            )
    }
}

@MainActor
private func firstLongPressNode(in root: ViewNode) -> ViewNode? {
    if root.longPressGesture != nil { return root }
    for child in root.children {
        if let node = firstLongPressNode(in: child) { return node }
    }
    return nil
}

@MainActor
private func longPressCenter(of node: ViewNode) -> Point {
    var point = Point(x: node.resolvedFrame.midX, y: node.resolvedFrame.midY)
    var ancestor = node.parent
    while let current = ancestor {
        point.x += current.resolvedFrame.origin.x
        point.y += current.resolvedFrame.origin.y
        ancestor = current.parent
    }
    return point
}

@MainActor
private func longPressTexts(in node: ViewNode) -> [String] {
    (node.text.map { [$0] } ?? []) + node.children.flatMap { longPressTexts(in: $0) }
}

@MainActor
private func makeLongPressWindow(
    clock: RuntimeTestClock,
    content: AnyView,
    size: IntSize = IntSize(width: 320, height: 160)
) -> (host: WinSwiftUIWindowHost, window: Win32Window) {
    let pixels = IntSize(width: size.width * 2, height: size.height * 2)
    let surface = SurfaceDescriptor(
        windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
        pixelSize: pixels,
        scaleFactor: 2
    )
    let window = Win32Window(title: "Long press", clientSize: pixels)
    window.testScaleFactorOverride = 2
    let host = WinSwiftUIWindowHost(
        configuration: WindowGroupConfiguration(
            title: "Long press", size: size, clearColor: .black, content: [content]),
        platformWindow: window,
        renderer: FakeRenderBackend(),
        batchRenderer: nil,
        surfaceDescriptorProvider: { _ in surface },
        startupProbeConfiguration: nil
    )
    host.frameClock = { clock.now }
    host.hostedRuntime.clock = { clock.now }
    host.windowDidCreate(window)
    return (host, window)
}
