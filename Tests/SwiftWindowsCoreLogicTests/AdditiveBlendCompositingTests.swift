import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics

/// Independent premultiplied delta obligations, frozen before additive production.
@MainActor
final class AdditiveBlendCompositingTests: XCTestCase {
    func testOpaqueAndTranslucentLiteralIncrements() async {
        let cases: [(Color, Color, Color)] = [
            (
                Color(red: 1, green: 0, blue: 0, alpha: 1),
                Color(red: 0, green: 1, blue: 0, alpha: 1),
                Color(red: 1, green: 0, blue: 0, alpha: 0)
            ),
            (
                Color(red: 0.75, green: 0.25, blue: 0.5, alpha: 0.25),
                Color(red: 0.125, green: 0.25, blue: 0.375, alpha: 0.5),
                Color(red: 0.1875, green: 0.0625, blue: 0.125, alpha: 0.25)
            ),
            (
                Color(red: 0.75, green: 0.25, blue: 0.5, alpha: 0.25),
                .clear,
                Color(red: 0.1875, green: 0.0625, blue: 0.125, alpha: 0.25)
            ),
        ]
        for (source, backdrop, expected) in cases {
            assertColor(
                SceneAdditiveBlendCompositing.premultipliedIncrement(
                    source: source, premultipliedBackdrop: backdrop),
                expected)
        }
    }

    func testZeroAlphaSourceIgnoresItsHiddenRGBExactly() async {
        let source = Color(red: 1, green: 0.125, blue: 0.75, alpha: 0)
        for backdrop in [
            Color.clear,
            Color(red: 0.125, green: 0.25, blue: 0.375, alpha: 0.5),
            Color(red: 1, green: 1, blue: 1, alpha: 1),
        ] {
            XCTAssertEqual(
                SceneAdditiveBlendCompositing.premultipliedIncrement(
                    source: source, premultipliedBackdrop: backdrop),
                .clear)
        }
    }

    func testSourceAlphaAlreadyIncludesCoverageAndIsAppliedOnce() async {
        // Authored alpha .5 times coverage .25 is supplied as .125.
        let increment = SceneAdditiveBlendCompositing.premultipliedIncrement(
            source: Color(red: 0.75, green: 0.25, blue: 0.5, alpha: 0.125),
            premultipliedBackdrop: Color(red: 0.125, green: 0.25, blue: 0.375, alpha: 0.5))
        assertColor(increment, Color(red: 0.09375, green: 0.03125, blue: 0.0625, alpha: 0.125))
    }

    func testRGBAndAlphaSaturateIndependently() async {
        let cases: [(Color, Color, Color)] = [
            (
                Color(red: 1, green: 0.25, blue: 0.5, alpha: 0.75),
                Color(red: 0.5625, green: 0.375, blue: 0.75, alpha: 0.75),
                Color(red: 0.4375, green: 0.1875, blue: 0.25, alpha: 0.25)
            ),
            (
                Color(red: 0.5, green: 0.25, blue: 0.75, alpha: 0.75),
                Color(red: 0.125, green: 0.25, blue: 0, alpha: 0.5),
                Color(red: 0.375, green: 0.1875, blue: 0.5625, alpha: 0.5)
            ),
        ]
        for (source, backdrop, expected) in cases {
            assertColor(
                SceneAdditiveBlendCompositing.premultipliedIncrement(
                    source: source, premultipliedBackdrop: backdrop),
                expected)
        }
    }

    func testOpaqueBackdropProducesPositiveRGBWithZeroIncrementAlpha() async {
        let emission = SceneAdditiveBlendCompositing.premultipliedIncrement(
            source: Color(red: 1, green: 0, blue: 0, alpha: 0.5),
            premultipliedBackdrop: Color(red: 0, green: 1, blue: 0, alpha: 1))
        assertColor(emission, Color(red: 0.5, green: 0, blue: 0, alpha: 0))
        XCTAssertEqual(emission.alpha, 0)
        XCTAssertGreaterThan(emission.red, emission.alpha)

        let saturatedEmission = SceneAdditiveBlendCompositing.premultipliedIncrement(
            source: Color(red: 1, green: 0, blue: 0, alpha: 0.2),
            premultipliedBackdrop: Color(red: 0.9, green: 0, blue: 0, alpha: 1))
        assertColor(saturatedEmission, Color(red: 0.1, green: 0, blue: 0, alpha: 0))
        XCTAssertEqual(saturatedEmission.alpha, 0)
    }

    func testLaterAdditiveDrawSeesTheAlreadySaturatedVirtualDestination() async {
        let increment = SceneAdditiveBlendCompositing.premultipliedIncrement(
            source: Color(red: 0.75, green: 0.5, blue: 1, alpha: 0.5),
            premultipliedBackdrop: Color(red: 0.75, green: 1, blue: 0.25, alpha: 1))
        assertColor(increment, Color(red: 0.25, green: 0, blue: 0.5, alpha: 0))
    }

    func testVirtualDestinationWithExistingForegroundHasTheLiteralDelta() async {
        // B=(.125,.25,.375,.5), F=(.125,.0625,.03125,.25), K=.25.
        // D=F+(1-K)B=(.21875,.25,.3125,.625). Adding the returned
        // delta to F gives (.3125,.125,.15625,.5), without changing K.
        let increment = SceneAdditiveBlendCompositing.premultipliedIncrement(
            source: Color(red: 0.75, green: 0.25, blue: 0.5, alpha: 0.25),
            premultipliedBackdrop: Color(red: 0.21875, green: 0.25, blue: 0.3125, alpha: 0.625))
        assertColor(increment, Color(red: 0.1875, green: 0.0625, blue: 0.125, alpha: 0.25))
    }

    private func assertColor(
        _ actual: Color, _ expected: Color, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.red, expected.red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.alpha, expected.alpha, accuracy: 0.000_001, file: file, line: line)
    }
}
