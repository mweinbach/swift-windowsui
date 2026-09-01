import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Deterministic local playback policies, not measured native SwiftUI parity.
/// Values below come from installed retained nodes, not content-call counts.
@MainActor
final class KeyframePlaybackTests: XCTestCase {
    func testUnequalTypedTriggersWithTheSameDescriptionReplaceFromTheCurrentTime() async throws {
        let probe = KeyframeTestProbe()
        probe.target = 10
        var trigger = KeyframeSameDescriptionTrigger(value: 0)
        let host = KeyframeAnimatorTestHost {
            AnyView(
                KeyframeAnimator(initialValue: 0.0, trigger: trigger) { value in
                    keyframeTestContent(probe, value: value)
                } keyframes: { value in
                    keyframeTestFrames(probe, initialValue: value)
                })
        }
        defer { host.close() }

        XCTAssertEqual(try host.sample(), 0)
        XCTAssertTrue(probe.factoryInputs.isEmpty)
        trigger = KeyframeSameDescriptionTrigger(value: 1)
        host.reload()
        host.tick(0.25)
        XCTAssertEqual(try host.sample(), 2.5, accuracy: 0.000_001)

        // No frame has published the value at 0.5. Replacement must sample
        // that time, rather than start from the last presented value, 2.5.
        host.clock.now = 0.5
        probe.target = 20
        let replacement = KeyframeSameDescriptionTrigger(value: 2)
        XCTAssertEqual(String(describing: trigger), String(describing: replacement))
        XCTAssertNotEqual(trigger, replacement)
        trigger = replacement
        host.reload()

        XCTAssertEqual(probe.factoryInputs, [0, 5])
        XCTAssertEqual(try host.sample(), 5, accuracy: 0.000_001)
        host.tick(0.75)
        XCTAssertEqual(try host.sample(), 8.75, accuracy: 0.000_001)
        host.tick(1.5)
        XCTAssertEqual(try host.sample(), 20, accuracy: 0.000_001)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
    }

    func testEquivalentTypedTriggerIgnoresPayloadAndKeepsTheExistingTimeline() async throws {
        let probe = KeyframeTestProbe()
        probe.target = 10
        var trigger = KeyframePayloadIgnoredTrigger(value: 0, payload: "mount")
        let host = KeyframeAnimatorTestHost {
            AnyView(
                KeyframeAnimator(initialValue: probe.initialValue, trigger: trigger) { value in
                    keyframeTestContent(probe, value: value)
                } keyframes: { value in
                    keyframeTestFrames(probe, initialValue: value)
                })
        }
        defer { host.close() }

        trigger = KeyframePayloadIgnoredTrigger(value: 1, payload: "first")
        host.reload()
        host.tick(0.25)
        XCTAssertEqual(try host.sample(), 2.5, accuracy: 0.000_001)
        let equivalent = KeyframePayloadIgnoredTrigger(value: 1, payload: "ignored")
        XCTAssertEqual(trigger, equivalent)
        XCTAssertNotEqual(String(describing: trigger), String(describing: equivalent))
        trigger = equivalent
        probe.initialValue = 99
        probe.target = 100
        host.reload()
        host.tick(0.75)

        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertEqual(try host.sample(), 7.5, accuracy: 0.000_001)
        host.tick(1)
        XCTAssertEqual(try host.sample(), 10, accuracy: 0.000_001)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
    }

    func testRepeatingFalseModifierPublishesTheMoveBeginningWithoutAFrameSlot() async throws {
        let probe = KeyframeTestProbe()
        probe.repeating = false
        let host = KeyframeAnimatorTestHost {
            AnyView(
                Rectangle()
                    .frame(width: 20, height: 20)
                    .keyframeAnimator(initialValue: probe.initialValue, repeating: probe.repeating) { content, value in
                        content.offset(x: value).accessibilityIdentifier("sample")
                    } keyframes: { value in
                        keyframePlaybackMoveFrames(probe, initialValue: value)
                    })
        }
        defer { host.close() }

        XCTAssertEqual(try host.sample(), 2)
        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        host.tick(100)
        probe.initialValue = 99
        host.reload()
        XCTAssertEqual(try host.sample(), 2)
        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertFalse(host.runtime.hasActiveAnimations)
    }

    func testRepeatingFalseToTrueStartsAndTrueToFalseRestoresTheBeginning() async throws {
        let probe = KeyframeTestProbe()
        probe.repeating = false
        let host = KeyframeAnimatorTestHost { AnyView(keyframePlaybackMoveView(probe)) }
        defer { host.close() }

        host.tick(10)
        probe.repeating = true
        host.reload()
        XCTAssertEqual(probe.factoryInputs, [0, 2])
        XCTAssertEqual(try host.sample(), 2)
        XCTAssertTrue(host.runtime.hasActiveAnimations)
        host.tick(10.5)
        XCTAssertEqual(try host.sample(), 6, accuracy: 0.000_001)

        probe.repeating = false
        host.reload()
        XCTAssertEqual(try host.sample(), 2)
        XCTAssertEqual(probe.factoryInputs, [0, 2])
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        host.tick(20)
        XCTAssertEqual(try host.sample(), 2)
        XCTAssertEqual(probe.factoryInputs, [0, 2])
    }

    func testExactRepeatBoundaryAndOrdinaryOvershootStayAnchoredToThePreviousEnd() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframePlaybackRelativeView(probe)) }
        defer { host.close() }

        host.tick(1)
        XCTAssertEqual(try host.sample(), 1, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 1])
        XCTAssertTrue(host.runtime.hasActiveAnimations)
        host.tick(1.25)
        XCTAssertEqual(try host.sample(), 1.25, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 1])
        host.tick(2.25)
        XCTAssertEqual(try host.sample(), 2.25, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 1, 2])
    }

    func testSeveralOrdinaryRepeatCyclesCarryEachTerminalValueIntoTheNextFactory() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframePlaybackRelativeView(probe)) }
        defer { host.close() }

        host.tick(3.25)
        XCTAssertEqual(try host.sample(), 3.25, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 1, 2, 3])
        host.tick(4)
        XCTAssertEqual(try host.sample(), 4, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 1, 2, 3, 4])
        host.tick(4.25)
        XCTAssertEqual(try host.sample(), 4.25, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 1, 2, 3, 4])
    }

    func testLongGapBuildsAtMostEightCyclesThenResetsAtTheAdmittedFrame() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframePlaybackRelativeView(probe)) }
        defer { host.close() }

        // This pins the bounded local pause/reset candidate policy. Native
        // SwiftUI behavior after a long suspension remains unqualified.
        let beforeFirstGap = probe.factoryInputs.count
        host.tick(20)
        XCTAssertEqual(probe.factoryInputs.count - beforeFirstGap, 8)
        XCTAssertEqual(probe.factoryInputs, (0...8).map { Double($0) })
        XCTAssertEqual(try host.sample(), 8, accuracy: 0.000_001)
        host.tick(20.5)
        XCTAssertEqual(try host.sample(), 8.5, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs.count, 9)
        host.tick(21)
        XCTAssertEqual(try host.sample(), 9, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs.last, 9)

        let beforeSecondGap = probe.factoryInputs.count
        host.tick(40)
        XCTAssertEqual(probe.factoryInputs.count - beforeSecondGap, 8)
        XCTAssertEqual(probe.factoryInputs, (0...17).map { Double($0) })
        XCTAssertEqual(try host.sample(), 17, accuracy: 0.000_001)
        XCTAssertTrue(host.runtime.hasActiveAnimations)
    }

    func testZeroDurationRepeatsFinishWithoutRearmingOrLoopingTheFactory() async throws {
        for initiallyZero in [true, false] {
            let probe = KeyframeTestProbe()
            probe.duration = initiallyZero ? 0 : 1
            let host = KeyframeAnimatorTestHost { AnyView(keyframePlaybackRelativeView(probe)) }
            defer { host.close() }

            if !initiallyZero {
                XCTAssertEqual(try host.sample(), 0)
                XCTAssertTrue(host.runtime.hasActiveAnimations)
                probe.duration = 0
                host.tick(1)
            }
            let terminal = initiallyZero ? 1.0 : 2.0
            let expectedInputs: [Double] = initiallyZero ? [0] : [0, 1]
            XCTAssertEqual(try host.sample(), terminal)
            XCTAssertEqual(probe.factoryInputs, expectedInputs)
            XCTAssertFalse(host.runtime.hasActiveAnimations)
            host.tick(100)
            host.reload()
            XCTAssertEqual(try host.sample(), terminal)
            XCTAssertEqual(probe.factoryInputs, expectedInputs)
            XCTAssertFalse(host.runtime.hasActiveAnimations)
        }
    }

    func testReducedMotionOnlyPublishesTheTerminalValueWhenPlaybackIsRequested() async throws {
        for repeats in [true, false] {
            let probe = KeyframeTestProbe()
            probe.repeating = repeats
            let host = KeyframeAnimatorTestHost {
                AnyView(keyframePlaybackMoveView(probe).environment(\.accessibilityReduceMotion, true))
            }
            defer { host.close() }

            // Reduce Motion does not request playback for repeating=false.
            // Its sample remains Move(2), even though an active run ends at 10.
            let expected = repeats ? 10.0 : 2.0
            XCTAssertEqual(try host.sample(), expected)
            XCTAssertEqual(probe.factoryInputs, [0])
            XCTAssertFalse(host.runtime.hasActiveAnimations)
            host.tick(100)
            host.reload()
            XCTAssertEqual(try host.sample(), expected)
            XCTAssertEqual(probe.factoryInputs, [0])
            XCTAssertFalse(host.runtime.hasActiveAnimations)
        }
    }

    func testDisablingRepeatAndReducedMotionTogetherRestoresMoveBeginningWithoutAFactory() async throws {
        let probe = KeyframeTestProbe()
        var reduceMotion = true
        let host = KeyframeAnimatorTestHost {
            AnyView(keyframePlaybackMoveView(probe).environment(\.accessibilityReduceMotion, reduceMotion))
        }
        defer { host.close() }

        XCTAssertEqual(try host.sample(), 10)
        XCTAssertEqual(probe.factoryInputs, [0])
        probe.repeating = false
        reduceMotion = false
        host.reload()

        // The beginning is Move(2), not the seeded 0 or reduced-motion end 10.
        XCTAssertEqual(try host.sample(), 2)
        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        host.tick(10)
        XCTAssertEqual(try host.sample(), 2)
        XCTAssertEqual(probe.factoryInputs, [0])
    }

    func testReducedMotionStopsAMidrunRepeatAndReenablingMotionStartsFromItsEnd() async throws {
        let probe = KeyframeTestProbe()
        var reduceMotion = false
        let host = KeyframeAnimatorTestHost {
            AnyView(keyframePlaybackRelativeView(probe).environment(\.accessibilityReduceMotion, reduceMotion))
        }
        defer { host.close() }

        host.tick(0.25)
        XCTAssertEqual(try host.sample(), 0.25, accuracy: 0.000_001)
        reduceMotion = true
        host.reload()
        XCTAssertEqual(try host.sample(), 1)
        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        host.tick(10)
        XCTAssertEqual(try host.sample(), 1)

        reduceMotion = false
        host.reload()
        XCTAssertEqual(probe.factoryInputs, [0, 1])
        XCTAssertEqual(try host.sample(), 1)
        XCTAssertTrue(host.runtime.hasActiveAnimations)
        host.tick(10.5)
        XCTAssertEqual(try host.sample(), 1.5, accuracy: 0.000_001)
    }

    func testBackwardsTicksDoNotRewindThePresentedSampleOrRestartACycle() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframePlaybackRelativeView(probe)) }
        defer { host.close() }

        host.tick(0.75)
        XCTAssertEqual(try host.sample(), 0.75, accuracy: 0.000_001)
        host.tick(0.25)
        XCTAssertEqual(try host.sample(), 0.75, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0])
        host.tick(0.75)
        XCTAssertEqual(try host.sample(), 0.75, accuracy: 0.000_001)
        host.tick(1.25)
        XCTAssertEqual(try host.sample(), 1.25, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 1])
        host.tick(0.5)
        XCTAssertEqual(try host.sample(), 1.25, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 1])
        host.tick(1.5)
        XCTAssertEqual(try host.sample(), 1.5, accuracy: 0.000_001)
        XCTAssertTrue(host.runtime.hasActiveAnimations)
    }

    func testTriggeredModifierSupportsANonAnimatableRootWithIndependentTracks() async throws {
        var trigger = 0
        let initial = KeyframePlaybackRoot(x: 0, y: 10, label: "preserved")
        let host = KeyframeAnimatorTestHost {
            AnyView(
                Rectangle()
                    .frame(width: 20, height: 20)
                    .keyframeAnimator(initialValue: initial, trigger: trigger) { content, value in
                        content
                            .offset(x: value.x, y: value.y)
                            .accessibilityIdentifier("sample")
                            .accessibilityLabel(value.label)
                    } keyframes: { _ in
                        KeyframeTrack(\KeyframePlaybackRoot.x) {
                            LinearKeyframe(4.0, duration: 1)
                        }
                        KeyframeTrack(\KeyframePlaybackRoot.y) {
                            LinearKeyframe(18.0, duration: 2)
                        }
                    })
        }
        defer { host.close() }

        XCTAssertEqual(try host.sample(), 0)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        trigger = 1
        host.reload()
        host.tick(0.5)
        XCTAssertEqual(try host.sample(), 2, accuracy: 0.000_001)
        let midpoint = try XCTUnwrap(host.nodes.first { $0.accessibilityIdentifier == "sample" })
        XCTAssertEqual(midpoint.transform.translationY, 12, accuracy: 0.000_001)
        XCTAssertEqual(midpoint.accessibilityLabel, "preserved")
        host.tick(1.5)
        XCTAssertEqual(try host.sample(), 4, accuracy: 0.000_001)
        let held = try XCTUnwrap(host.nodes.first { $0.accessibilityIdentifier == "sample" })
        XCTAssertEqual(held.transform.translationY, 16, accuracy: 0.000_001)
        XCTAssertEqual(held.accessibilityLabel, "preserved")
        host.tick(2)
        XCTAssertEqual(try host.sample(), 4)
        let terminal = try XCTUnwrap(host.nodes.first { $0.accessibilityIdentifier == "sample" })
        XCTAssertEqual(terminal.transform.translationY, 18)
        XCTAssertEqual(terminal.accessibilityLabel, "preserved")
        XCTAssertFalse(host.runtime.hasActiveAnimations)
    }

    func testCapturedTransactionSlotsSurviveFramesAndSuppressSecondaryTweens() async throws {
        let savedTransaction = currentTransaction
        let savedAnimation = currentAnimationTransaction
        defer {
            currentTransaction = savedTransaction
            currentAnimationTransaction = savedAnimation
        }
        var captured = Transaction(animation: .linear(duration: 3))
        captured.isContinuous = true
        captured.scrollTargetAnchor = .bottom
        captured.tracksVelocity = true

        for includesFullTransaction in [true, false] {
            let probe = KeyframeTestProbe()
            var factoryScopes: [KeyframePlaybackTransactionSnapshot] = []
            var contentScopes: [KeyframePlaybackTransactionSnapshot] = []
            probe.onFactory = { factoryScopes.append(KeyframePlaybackTransactionSnapshot()) }
            probe.onContent = { _ in contentScopes.append(KeyframePlaybackTransactionSnapshot()) }
            currentTransaction = includesFullTransaction ? captured : nil
            // The legacy slot is deliberately independent of the full slot.
            currentAnimationTransaction = (duration: 7, easing: .easeIn)
            let host = KeyframeAnimatorTestHost {
                AnyView(
                    KeyframeAnimator(initialValue: 0.0) { value in
                        keyframeTestContent(probe, value: value)
                            .animation(.linear(duration: 5), value: value)
                    } keyframes: { value in
                        keyframePlaybackRelativeSegment(probe, initialValue: value)
                    })
            }
            defer { host.close() }

            contentScopes.removeAll()
            currentTransaction = nil
            currentAnimationTransaction = (duration: 13, easing: .easeOut)
            host.tick(0.5)
            XCTAssertEqual(try host.sample(), 0.5, accuracy: 0.000_001)
            XCTAssertNil(currentTransaction)
            XCTAssertEqual(currentAnimationTransaction?.duration, 13)
            XCTAssertEqual(currentAnimationTransaction?.easing, .easeOut)

            var outside = Transaction(animation: .linear(duration: 11))
            outside.scrollTargetAnchor = .top
            currentTransaction = outside
            host.tick(1.25)
            XCTAssertEqual(try host.sample(), 1.25, accuracy: 0.000_001)
            XCTAssertEqual(currentTransaction?.animation?.duration, 11)
            XCTAssertEqual(currentTransaction?.scrollTargetAnchor, .top)
            XCTAssertEqual(currentTransaction?.isContinuous, false)
            XCTAssertEqual(currentTransaction?.tracksVelocity, false)
            XCTAssertEqual(currentAnimationTransaction?.duration, 13)
            XCTAssertEqual(currentAnimationTransaction?.easing, .easeOut)

            XCTAssertEqual(probe.factoryInputs, [0, 1])
            XCTAssertEqual(factoryScopes.count, 2)
            for scope in factoryScopes {
                XCTAssertEqual(scope.transaction?.animation?.duration, includesFullTransaction ? 3 : nil)
                XCTAssertEqual(scope.transaction?.disablesAnimations, includesFullTransaction ? false : nil)
                XCTAssertEqual(scope.transaction?.isContinuous, includesFullTransaction ? true : nil)
                XCTAssertEqual(scope.transaction?.tracksVelocity, includesFullTransaction ? true : nil)
                XCTAssertEqual(scope.transaction?.scrollTargetAnchor, includesFullTransaction ? .bottom : nil)
                XCTAssertEqual(scope.legacyDuration, 7)
                XCTAssertEqual(scope.legacyEasing, .easeIn)
            }
            XCTAssertFalse(contentScopes.isEmpty)
            for scope in contentScopes {
                let frame = try XCTUnwrap(scope.transaction)
                XCTAssertNil(frame.animation)
                XCTAssertTrue(frame.disablesAnimations)
                XCTAssertEqual(frame.isContinuous, includesFullTransaction)
                XCTAssertEqual(frame.tracksVelocity, includesFullTransaction)
                XCTAssertEqual(frame.scrollTargetAnchor, includesFullTransaction ? .bottom : nil)
                XCTAssertNil(scope.legacyDuration)
                XCTAssertNil(scope.legacyEasing)
            }
            XCTAssertTrue(host.nodes.allSatisfy { $0.animationStates.isEmpty })
            XCTAssertTrue(host.runtime.hasActiveAnimations, "Only the keyframe frame slot should remain active")
        }
    }

    func testRetriggerCarriesTheSampledVelocityIntoCubicAndSpringTracks() async throws {
        for useSpring in [false, true] {
            let probe = KeyframeTestProbe()
            let host = KeyframeAnimatorTestHost {
                AnyView(
                    KeyframeAnimator(initialValue: 0.0, trigger: probe.trigger) { value in
                        keyframeTestContent(probe, value: value)
                    } keyframes: { value in
                        keyframePlaybackInterruptionFrames(probe, initialValue: value, useSpring: useSpring)
                    })
            }
            defer { host.close() }

            probe.trigger = 1
            host.reload()
            host.tick(0.25)
            XCTAssertEqual(try host.sample(), 2.5, accuracy: 0.000_001)
            host.clock.now = 0.5
            probe.trigger = 2
            host.reload()
            XCTAssertEqual(probe.factoryInputs, [0, 5])
            XCTAssertEqual(try host.sample(), 5, accuracy: 0.000_001)

            // At replacement, value is 5 and incoming velocity is 10. Cubic
            // Hermite interpolation and a critical spring with omega = 1
            // give these independent closed-form expectations.
            host.tick(0.75)
            let quarter = useSpring ? 20 - 16.25 * exp(-0.25) : 8.75
            XCTAssertEqual(try host.sample(), quarter, accuracy: 0.000_001)
            host.tick(1)
            let half = useSpring ? 20 - 17.5 * exp(-0.5) : 13.75
            XCTAssertEqual(try host.sample(), half, accuracy: 0.000_001)
            host.tick(1.5)
            let terminal = useSpring ? 20 - 20 * exp(-1) : 20
            XCTAssertEqual(try host.sample(), terminal, accuracy: 0.000_001)
            XCTAssertEqual(probe.factoryInputs, [0, 5])
            XCTAssertFalse(host.runtime.hasActiveAnimations)
        }
    }
}

private struct KeyframeSameDescriptionTrigger: Equatable, CustomStringConvertible {
    let value: Int
    var description: String { "same" }
}

private struct KeyframePayloadIgnoredTrigger: Equatable, CustomStringConvertible {
    let value: Int
    let payload: String
    var description: String { payload }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }
}

// Intentionally no Animatable conformance: each writable track is animatable.
private struct KeyframePlaybackRoot {
    var x: Double
    var y: Double
    var label: String
}

@MainActor
private struct KeyframePlaybackTransactionSnapshot {
    let transaction = currentTransaction
    let legacyDuration = currentAnimationTransaction?.duration
    let legacyEasing = currentAnimationTransaction?.easing
}

@MainActor
private func keyframePlaybackMoveFrames(_ probe: KeyframeTestProbe, initialValue: Double) -> some Keyframes<Double> {
    probe.factoryInputs.append(initialValue)
    probe.onFactory?()
    return KeyframeTrack(\Double.self) {
        MoveKeyframe(2.0)
        LinearKeyframe(10.0, duration: probe.duration)
    }
}

@MainActor
private func keyframePlaybackRelativeSegment(_ probe: KeyframeTestProbe, initialValue: Double) -> LinearKeyframe<Double>
{
    probe.factoryInputs.append(initialValue)
    probe.onFactory?()
    return LinearKeyframe(initialValue + 1, duration: probe.duration)
}

@MainActor
private func keyframePlaybackMoveView(_ probe: KeyframeTestProbe) -> some View {
    KeyframeAnimator(initialValue: probe.initialValue, repeating: probe.repeating) { value in
        keyframeTestContent(probe, value: value)
    } keyframes: { value in
        keyframePlaybackMoveFrames(probe, initialValue: value)
    }
}

@MainActor
private func keyframePlaybackRelativeView(_ probe: KeyframeTestProbe) -> some View {
    KeyframeAnimator(initialValue: probe.initialValue, repeating: probe.repeating) { value in
        keyframeTestContent(probe, value: value)
    } keyframes: { value in
        keyframePlaybackRelativeSegment(probe, initialValue: value)
    }
}

@MainActor
private func keyframePlaybackInterruptionFrames(
    _ probe: KeyframeTestProbe, initialValue: Double, useSpring: Bool
) -> some Keyframes<Double> {
    probe.factoryInputs.append(initialValue)
    probe.onFactory?()
    return KeyframeTrack(\Double.self) {
        if probe.trigger == 1 {
            LinearKeyframe(10.0, duration: 1)
        } else if useSpring {
            SpringKeyframe(20.0, duration: 1, spring: Spring(response: 2 * Double.pi, dampingRatio: 1))
        } else {
            CubicKeyframe(20.0, duration: 1)
        }
    }
}
