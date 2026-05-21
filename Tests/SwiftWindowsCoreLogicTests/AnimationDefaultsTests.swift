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

    func testSpringEasingMonotonicallyApproachesOne() {
        let easing = AnimationEasing.spring(response: 0.55, dampingRatio: 0.825)
        XCTAssertEqual(easing.apply(0), 0, accuracy: 0.05)
        XCTAssertEqual(easing.apply(1), 1, accuracy: 0.05)
    }
}
