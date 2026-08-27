import Foundation
import XCTest

@testable import SwiftWindowsCore

final class AnimationDefaultsTests: XCTestCase {
    func testDefaultAnimationMatchesSwiftUIEaseInOut() {
        let animation = Animation.default
        XCTAssertEqual(animation.duration, 0.35, accuracy: 0.001)
        XCTAssertEqual(animation.easing, .easeInOut)
    }

    func testEaseInOutSharesDefaultDuration() {
        XCTAssertEqual(Animation.easeInOut.duration, Animation.default.duration, accuracy: 0.001)
        XCTAssertEqual(Animation.easeInOut.easing, .easeInOut)
    }

    func testDefaultSpringMatchesSwiftUIResponseDampingFraction() {
        let animation = Animation.spring
        guard case .spring(let response, let damping) = animation.easing else {
            return XCTFail("Animation.spring should use .spring easing")
        }
        XCTAssertEqual(response, 0.55, accuracy: 0.001)
        XCTAssertEqual(damping, 0.825, accuracy: 0.001)
    }

    func testInteractiveSpringMatchesSwiftUIInteractiveDefaults() {
        let animation = Animation.interactiveSpring()
        guard case .spring(let response, let damping) = animation.easing else {
            return XCTFail("interactiveSpring should use .spring easing")
        }
        XCTAssertEqual(response, 0.15, accuracy: 0.001)
        XCTAssertEqual(damping, 0.86, accuracy: 0.001)
    }

    func testSmoothSpringIsCriticallyDamped() {
        guard case .spring(let response, let damping) = Animation.smooth.easing else {
            return XCTFail("Animation.smooth should use .spring easing")
        }
        XCTAssertEqual(response, 0.5, accuracy: 0.001)
        XCTAssertEqual(damping, 1.0, accuracy: 0.001)
    }

    func testSnappySpringMatchesSwiftUIBounce015() {
        guard case .spring(let response, let damping) = Animation.snappy.easing else {
            return XCTFail("Animation.snappy should use .spring easing")
        }
        XCTAssertEqual(response, 0.5, accuracy: 0.001)
        XCTAssertEqual(damping, 0.85, accuracy: 0.001)
    }

    func testBouncySpringMatchesSwiftUIBounce03() {
        guard case .spring(let response, let damping) = Animation.bouncy.easing else {
            return XCTFail("Animation.bouncy should use .spring easing")
        }
        XCTAssertEqual(response, 0.5, accuracy: 0.001)
        XCTAssertEqual(damping, 0.7, accuracy: 0.001)
    }

    func testSpringDurationBounceConvenienceMaps() {
        let zero = Animation.spring(duration: 0.5, bounce: 0)
        guard case .spring(_, let zeroDamping) = zero.easing else {
            return XCTFail("spring(duration:bounce:) should use .spring easing")
        }
        XCTAssertEqual(zeroDamping, 1.0, accuracy: 0.001)

        let bouncy = Animation.spring(duration: 0.5, bounce: 0.3)
        guard case .spring(_, let bouncyDamping) = bouncy.easing else {
            return XCTFail("spring(duration:bounce:) should use .spring easing")
        }
        XCTAssertEqual(bouncyDamping, 0.7, accuracy: 0.001)
    }

    func testEaseInOutCurveIsSymmetricAroundMidpoint() {
        let easing = AnimationEasing.easeInOut
        XCTAssertEqual(easing.apply(0), 0, accuracy: 0.001)
        XCTAssertEqual(easing.apply(0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(easing.apply(1), 1, accuracy: 0.001)
        // First half should be slower than linear (eased-in shape).
        XCTAssertLessThan(easing.apply(0.25), 0.25)
        // Second half should be faster (eased-out shape).
        XCTAssertGreaterThan(easing.apply(0.75), 0.75)
    }

    func testDefaultSpringStartsAtZeroAndSettlesExactlyAtOne() {
        let easing = AnimationEasing.spring(response: 0.55, dampingRatio: 0.825)
        XCTAssertEqual(easing.apply(0), 0)
        XCTAssertEqual(easing.apply(1), 1)
    }

    func testUnderdampedSpringPeakScalesWithResponseWithoutClamping() {
        let damping = 0.5
        let dampedFrequency = sqrt(1 - damping * damping)
        let expectedPeak = 1 + exp(-damping * Double.pi / dampedFrequency)

        for response in [0.15, 0.5, 1.25] {
            let animation = Animation.spring(response: response, dampingRatio: damping)
            let peakTime = response / (2 * dampedFrequency)
            let peakProgress = peakTime / animation.duration
            XCTAssertEqual(
                animation.easing.apply(peakProgress), expectedPeak, accuracy: 0.000_000_001,
                "a spring's physical response must scale once, not once in duration and again in easing")
            XCTAssertLessThan(animation.easing.apply(peakProgress * 0.9), expectedPeak)
            XCTAssertLessThan(animation.easing.apply(peakProgress * 1.1), expectedPeak)
        }
    }

    func testSmoothSpringIsMonotonicWithoutOvershootThroughoutItsEnvelope() {
        let easing = Animation.smooth.easing
        var previous = easing.apply(0)
        for sample in 1...1_000 {
            let progress = easing.apply(Double(sample) / 1_000)
            XCTAssertGreaterThanOrEqual(progress, previous)
            XCTAssertLessThanOrEqual(progress, 1)
            previous = progress
        }
    }

    func testOverdampedSpringIsMonotonicAndSlowerThanCriticalSpring() {
        let critical = AnimationEasing.spring(response: 0.5, dampingRatio: 1)
        let overdamped = AnimationEasing.spring(response: 0.5, dampingRatio: 2)
        var previous = overdamped.apply(0)
        for sample in 1...1_000 {
            let time = Double(sample) / 1_000
            let progress = overdamped.apply(time)
            XCTAssertGreaterThanOrEqual(progress, previous)
            XCTAssertLessThanOrEqual(progress, critical.apply(time))
            previous = progress
        }
    }

    func testSpringIsStableNearCriticalAndExtremeDamping() {
        let time = 1 / (10 * Double.pi)
        let expectedProgress = 1 - 2 / exp(1.0)
        for damping in [0.999_999_9, 1, 1.000_000_1] {
            let easing = AnimationEasing.spring(response: 0.5, dampingRatio: damping)
            XCTAssertEqual(easing.apply(time), expectedProgress, accuracy: 0.000_001)
        }

        for damping in [1e160, 1e300, Double.greatestFiniteMagnitude] {
            let easing = AnimationEasing.spring(response: 0.5, dampingRatio: damping)
            for sample in [0.0, 0.01, 0.25, 0.75, 1] {
                let progress = easing.apply(sample)
                XCTAssertTrue(progress.isFinite, "finite damping must never overflow the spring evaluator")
                XCTAssertGreaterThanOrEqual(progress, 0)
                XCTAssertLessThanOrEqual(progress, 1)
            }
        }

        let critical = AnimationEasing.spring(response: 0.5, dampingRatio: 1)
        for damping in [-1, -Double.greatestFiniteMagnitude, .nan, .infinity, -.infinity] {
            let easing = AnimationEasing.spring(response: 0.5, dampingRatio: damping)
            for sample in [0.0, 0.01, 0.25, 0.75, 1] {
                XCTAssertEqual(
                    easing.apply(sample), critical.apply(sample),
                    "invalid damping uses the finite, non-bouncing critical response")
            }
        }
    }

    func testSnappySpringDoesNotBackslideLongAfterItsInitialMotion() {
        let animation = Animation.snappy
        for sample in 100...250 {
            let elapsed = Double(sample) / 100
            XCTAssertEqual(
                animation.easing.apply(elapsed / animation.duration), 1, accuracy: 0.000_1,
                "the old clamped curve paused at its target and then retreated about 1.7 percent at 1.1s")
        }
    }
}
