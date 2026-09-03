import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics

/// Fixed numerical obligations frozen before the separable blend implementation.
/// The backdrop argument is premultiplied; the adjusted source remains straight.
@MainActor
final class SeparableBlendCompositingTests: XCTestCase {
    private let modes: [BlendMode] = [.multiply, .screen, .overlay]

    func testFixedOpaqueAndTranslucentSourceTermVectors() async {
        let source = Color(red: 0.8, green: 0.2, blue: 0.4, alpha: 0.5)
        let translucent = Color(red: 0.15, green: 0.3, blue: 0.05, alpha: 0.5)
        let opaque = Color(red: 0.3, green: 0.6, blue: 0.1, alpha: 1)
        let cases: [(BlendMode, Color, Color)] = [
            (
                .multiply, Color(red: 0.52, green: 0.16, blue: 0.22, alpha: 0.5),
                Color(red: 0.24, green: 0.12, blue: 0.04, alpha: 0.5)
            ),
            (
                .screen, Color(red: 0.83, green: 0.44, blue: 0.43, alpha: 0.5),
                Color(red: 0.86, green: 0.68, blue: 0.46, alpha: 0.5)
            ),
            (
                .overlay, Color(red: 0.64, green: 0.28, blue: 0.24, alpha: 0.5),
                Color(red: 0.48, green: 0.36, blue: 0.08, alpha: 0.5)
            ),
        ]
        for (mode, expectedTranslucent, expectedOpaque) in cases {
            assertColor(
                SceneSeparableBlendCompositing.adjustedSource(
                    source, premultipliedBackdrop: translucent, mode: mode),
                expectedTranslucent)
            assertColor(
                SceneSeparableBlendCompositing.adjustedSource(source, premultipliedBackdrop: opaque, mode: mode),
                expectedOpaque)
        }
    }

    func testTransparentBackdropDoesNotIntroduceItsHiddenColor() async {
        let source = Color(red: 0.2, green: 0.7, blue: 0.4, alpha: 0.6)
        // Deliberately retain hidden RGB to guard division by zero and leakage.
        let backdrop = Color(red: 0.9, green: 0.8, blue: 0.1, alpha: 0)
        for mode in modes {
            XCTAssertEqual(
                SceneSeparableBlendCompositing.adjustedSource(source, premultipliedBackdrop: backdrop, mode: mode),
                source)
        }
    }

    func testOverlayChoosesItsBranchFromTheBackdrop() async {
        let source = Color(red: 0.8, green: 0.2, blue: 0.6, alpha: 0.37)
        let backdrop = Color(red: 0.25, green: 0.75, blue: 0.4, alpha: 1)
        assertColor(
            SceneSeparableBlendCompositing.adjustedSource(source, premultipliedBackdrop: backdrop, mode: .overlay),
            Color(red: 0.4, green: 0.6, blue: 0.48, alpha: 0.37))
    }

    func testSourceAlphaIncludingCoverageIsPreservedForTheCoveragePlane() async {
        let backdrop = Color(red: 0.18, green: 0.3, blue: 0.12, alpha: 0.6)
        for alpha in [Float(0), 0.125, 0.5, 1] {
            let source = Color(red: 0.9, green: 0.4, blue: 0.7, alpha: alpha)
            for mode in modes {
                let result = SceneSeparableBlendCompositing.adjustedSource(
                    source, premultipliedBackdrop: backdrop, mode: mode)
                XCTAssertEqual(result.alpha, alpha)
                for component in [result.red, result.green, result.blue] {
                    XCTAssertTrue(component.isFinite)
                    XCTAssertGreaterThanOrEqual(component, 0)
                    XCTAssertLessThanOrEqual(component, 1)
                }
            }
        }
    }

    func testNormalAndAdditiveLeaveTheAuthoredSourceUnchanged() async {
        let source = Color(red: 0.12, green: 0.43, blue: 0.98, alpha: 0.27)
        let backdrop = Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.8)
        for mode in [BlendMode.normal, .additive] {
            XCTAssertEqual(
                SceneSeparableBlendCompositing.adjustedSource(source, premultipliedBackdrop: backdrop, mode: mode),
                source)
        }
    }

    func testNearZeroBackdropAlphaDoesNotProduceNonfiniteComponents() async {
        let alpha = Float.leastNormalMagnitude
        let backdrop = Color(red: alpha * 0.2, green: alpha * 0.7, blue: alpha * 0.4, alpha: alpha)
        let source = Color(red: 0.4, green: 0.3, blue: 0.9, alpha: 0.6)
        for mode in modes {
            assertColor(
                SceneSeparableBlendCompositing.adjustedSource(source, premultipliedBackdrop: backdrop, mode: mode),
                source)
        }
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
