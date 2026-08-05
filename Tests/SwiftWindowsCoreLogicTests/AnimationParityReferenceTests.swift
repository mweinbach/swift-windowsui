import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsUI

/// Source-of-truth reference values for animation defaults, cross-referenced
/// in `docs/AnimationParity.md`. Each constant below mirrors a public Apple
/// SwiftUI default; if these tests fail, either the implementation drifted
/// from SwiftUI parity OR the doc and the source both need to update.
///
/// Keep this list and the markdown doc in lockstep.
final class AnimationParityReferenceTests: XCTestCase {

    // MARK: - Static eases

    func testStaticEasingsUseDefaultDuration() {
        XCTAssertEqual(Animation.default.duration, 0.35, accuracy: 0.001)
        XCTAssertEqual(Animation.linear.duration, 0.35, accuracy: 0.001)
        XCTAssertEqual(Animation.easeIn.duration, 0.35, accuracy: 0.001)
        XCTAssertEqual(Animation.easeOut.duration, 0.35, accuracy: 0.001)
        XCTAssertEqual(Animation.easeInOut.duration, 0.35, accuracy: 0.001)
    }

    func testStaticEasingsUseExpectedCurves() {
        XCTAssertEqual(Animation.default.easing, .easeInOut)
        XCTAssertEqual(Animation.linear.easing, .linear)
        XCTAssertEqual(Animation.easeIn.easing, .easeIn)
        XCTAssertEqual(Animation.easeOut.easing, .easeOut)
        XCTAssertEqual(Animation.easeInOut.easing, .easeInOut)
    }

    // MARK: - Named springs

    private func extractSpring(_ animation: Animation, file: StaticString = #filePath, line: UInt = #line)
        -> (response: Double, damping: Double)
    {
        guard case .spring(let response, let damping) = animation.easing else {
            XCTFail("Expected .spring easing on the supplied animation", file: file, line: line)
            return (0, 0)
        }
        return (response, damping)
    }

    func testAnimationSpringMatchesSwiftUIDefaultResponseDamping() {
        let s = extractSpring(Animation.spring)
        XCTAssertEqual(s.response, 0.55, accuracy: 0.001)
        XCTAssertEqual(s.damping, 0.825, accuracy: 0.001)
    }

    func testAnimationSmoothMatchesSwiftUIBounce0() {
        let s = extractSpring(Animation.smooth)
        XCTAssertEqual(s.response, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.damping, 1.0, accuracy: 0.001)
    }

    func testAnimationSnappyMatchesSwiftUIBounce015() {
        let s = extractSpring(Animation.snappy)
        XCTAssertEqual(s.response, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.damping, 0.85, accuracy: 0.001)
    }

    func testAnimationBouncyMatchesSwiftUIBounce03() {
        let s = extractSpring(Animation.bouncy)
        XCTAssertEqual(s.response, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.damping, 0.7, accuracy: 0.001)
    }

    func testAnimationInteractiveSpringMatchesSwiftUIDefaults() {
        let s = extractSpring(Animation.interactiveSpring())
        XCTAssertEqual(s.response, 0.15, accuracy: 0.001)
        XCTAssertEqual(s.damping, 0.86, accuracy: 0.001)
    }

    // MARK: - Convenience factories

    func testSpringDurationBounceFactoryRoundTrips() {
        let zeroBounce = extractSpring(Animation.spring(duration: 0.5, bounce: 0))
        XCTAssertEqual(zeroBounce.damping, 1.0, accuracy: 0.001)

        let halfBounce = extractSpring(Animation.spring(duration: 0.5, bounce: 0.5))
        XCTAssertEqual(halfBounce.damping, 0.5, accuracy: 0.001)
    }

    func testSmoothSnappyBouncyFactoryDefaults() {
        let smooth = extractSpring(Animation.smooth())
        let snappy = extractSpring(Animation.snappy())
        let bouncy = extractSpring(Animation.bouncy())
        XCTAssertEqual(smooth.damping, 1.0, accuracy: 0.001, "smooth() default = bounce 0 → damping 1")
        XCTAssertEqual(snappy.damping, 0.85, accuracy: 0.001, "snappy() default = bounce 0.15 → damping 0.85")
        XCTAssertEqual(bouncy.damping, 0.7, accuracy: 0.001, "bouncy() default = bounce 0.3 → damping 0.7")
    }

    func testLinearEaseInEaseOutEaseInOutFactoriesOverrideDuration() {
        XCTAssertEqual(Animation.linear(duration: 1.25).duration, 1.25, accuracy: 0.0001)
        XCTAssertEqual(Animation.easeIn(duration: 1.25).duration, 1.25, accuracy: 0.0001)
        XCTAssertEqual(Animation.easeOut(duration: 1.25).duration, 1.25, accuracy: 0.0001)
        XCTAssertEqual(Animation.easeInOut(duration: 1.25).duration, 1.25, accuracy: 0.0001)
    }

    // MARK: - Operations

    func testSpeedScalesDuration() {
        let doubled = Animation.default.speed(2)
        XCTAssertEqual(doubled.duration, 0.175, accuracy: 0.0001, "speed(2) halves the duration")
    }

    func testDelayAddsToDuration() {
        let delayed = Animation.default.delay(0.5)
        XCTAssertEqual(
            delayed.duration, 0.35 + 0.5, accuracy: 0.0001,
            "delay() rolls into the same animation's duration in this implementation")
    }

    // MARK: - Control transition timings

    func testDefaultControlAnimationStyleMatchesDocumentedDurations() {
        let style = ControlAnimationStyle.default
        XCTAssertEqual(style.focusDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(style.pressDuration, 0.14, accuracy: 0.001)
        XCTAssertEqual(style.activationDuration, 0.18, accuracy: 0.001)
    }

    /// macOS does not scale a control on press — an AppKit cell highlights in
    /// the frame it already had, in every appearance and every control family
    /// from Big Sur through Sonoma. The 0.97 shrink this stack shipped as "the
    /// Big Sur feel" is an iOS / custom-`ButtonStyle` idiom, and parity is the
    /// standard, so the default is now `1`.
    ///
    /// The constant stays for a style that deliberately wants the shrink;
    /// nothing built for parity references it. See docs/AnimationParity.md.
    func testDefaultPressIsAFillChangeNotATransform() {
        XCTAssertEqual(
            ControlAnimationStyle.default.pressedScale, 1.0, accuracy: 0.0001,
            "a control's press feedback is its pressed fill, not a geometric shrink")
        XCTAssertEqual(
            ControlAnimationStyle.tactilePressedScale, 0.97, accuracy: 0.001,
            "the opt-in shrink is still available to a style that asks for it")
        XCTAssertEqual(
            ControlAnimationStyle(pressedScale: ControlAnimationStyle.tactilePressedScale).pressedScale,
            0.97,
            accuracy: 0.001,
            "…and asking for it is a per-style initializer argument")
    }
}
