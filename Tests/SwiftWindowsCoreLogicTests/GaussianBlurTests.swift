import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

/// Pins the post-process blur kernel shape. The CPU rasterizer used to
/// apply a uniform box-blur kernel; now it uses a separable 1D
/// Gaussian so the falloff matches macOS visual-effects blur quality
/// rather than producing a flat smear.
final class GaussianBlurTests: XCTestCase {

    func testGaussianKernelIsBellShapedAndSymmetric() {
        let kernel = gaussianBlurKernel(radius: 4)
        XCTAssertEqual(kernel.count, 9, "radius=4 → kernel size 2*radius + 1 = 9")
        // Symmetry: index i and (size - 1 - i) must match.
        for i in 0..<(kernel.count / 2) {
            XCTAssertEqual(
                kernel[i], kernel[kernel.count - 1 - i], accuracy: 1e-6,
                "Gaussian kernel must be symmetric around its centre")
        }
        // Bell shape: every step away from the centre must be smaller
        // or equal to the previous (monotonic decrease).
        let centre = kernel.count / 2
        for i in 0..<centre {
            XCTAssertLessThanOrEqual(
                kernel[centre - i - 1], kernel[centre - i],
                "Each step toward the edge must not increase (Gaussian is unimodal)")
        }
    }

    func testGaussianKernelWeightsSumToOne() {
        let kernel = gaussianBlurKernel(radius: 6)
        let sum = kernel.reduce(0, +)
        XCTAssertEqual(
            sum, 1.0, accuracy: 1e-5,
            "Normalised kernel weights must sum to 1 so the blurred image keeps brightness"
        )
    }

    func testGaussianKernelCentreWeightExceedsEdge() {
        // Specifically check the centre carries more weight than the
        // outermost samples — this is what makes Gaussian "true blur"
        // distinct from the old uniform box blur.
        let kernel = gaussianBlurKernel(radius: 4)
        let centre = kernel[kernel.count / 2]
        let edge = kernel.first ?? 0
        XCTAssertGreaterThan(
            centre, edge * 2,
            "Centre weight should be much heavier than the kernel edges — a box blur would have all weights equal"
        )
    }

    func testGaussianKernelDifferentRadiiProduceDifferentSpreads() {
        let small = gaussianBlurKernel(radius: 2)
        let large = gaussianBlurKernel(radius: 8)
        // Larger radius → wider sigma → centre carries proportionally
        // less of the total weight (mass is spread further).
        XCTAssertGreaterThan(
            small[small.count / 2], large[large.count / 2],
            "Smaller radius concentrates more weight at the centre than a larger radius does"
        )
    }
}
