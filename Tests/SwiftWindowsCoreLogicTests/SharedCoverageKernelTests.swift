import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

/// The coverage kernel every CPU rasterizer call site shares, checked
/// against an independent transcription of the HLSL on a dense sample
/// grid.
///
/// `roundedRectDistance` exists twice on purpose — once in
/// `BatchShaders.swift` as HLSL text that only a GPU can run, once in
/// `GPUIQuadCoverage` as Swift. There is no way to run one against the
/// other in-process, so this suite holds a *third* copy, transcribed
/// line-by-line from the shader source below, and compares it to the
/// shipping Swift on every sample of a dense grid. Editing one side
/// without the other fails here; that the pair actually matches the
/// running shader is pinned end-to-end by `CrossBackendPixelParityTests`
/// on WARP.
final class SharedCoverageKernelTests: XCTestCase {

    // MARK: - Independent transcription

    /// Transcribed from `batchQuadShaderSharedSource`:
    ///
    /// ```hlsl
    /// float2 halfSize = size * 0.5;
    /// float2 localPoint = localPosition - halfSize;
    /// float radius = localPoint.x > 0.0
    ///     ? (localPoint.y > 0.0 ? cornerRadii.z : cornerRadii.y)
    ///     : (localPoint.y > 0.0 ? cornerRadii.w : cornerRadii.x);
    /// float clampedRadius = min(radius, min(halfSize.x, halfSize.y));
    /// float2 corner = max(halfSize - float2(clampedRadius, clampedRadius), float2(0.0, 0.0));
    /// float2 delta = abs(localPoint) - corner;
    /// return length(max(delta, float2(0.0, 0.0))) + min(max(delta.x, delta.y), 0.0) - clampedRadius;
    /// ```
    private func shaderRoundedRectDistance(
        localX: Double, localY: Double, width: Double, height: Double,
        radii: (topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double)
    ) -> Double {
        let halfSizeX = width * 0.5
        let halfSizeY = height * 0.5
        let localPointX = localX - halfSizeX
        let localPointY = localY - halfSizeY
        let radius =
            localPointX > 0
            ? (localPointY > 0 ? radii.bottomRight : radii.topRight)
            : (localPointY > 0 ? radii.bottomLeft : radii.topLeft)
        let clampedRadius = min(radius, min(halfSizeX, halfSizeY))
        let cornerX = max(halfSizeX - clampedRadius, 0)
        let cornerY = max(halfSizeY - clampedRadius, 0)
        let deltaX = abs(localPointX) - cornerX
        let deltaY = abs(localPointY) - cornerY
        let outsideX = max(deltaX, 0)
        let outsideY = max(deltaY, 0)
        return (outsideX * outsideX + outsideY * outsideY).squareRoot() + min(max(deltaX, deltaY), 0)
            - clampedRadius
    }

    // MARK: - Grid

    private static let width = 37.0
    private static let height = 23.0

    /// Radii the audit named: 0 (the case the rasterizer used to short
    /// circuit into binary coverage), 1, 8, and the half-min-extent cap.
    private static let uniformRadii: [Double] = [0, 1, 8, min(width, height) * 0.5]

    /// Per-corner mixes, including one past the cap and one negative — the
    /// shader clamps neither with `max(_, 0)`, and the Swift must not
    /// either or the two disagree on malformed input.
    private static let cornerMixes: [(Double, Double, Double, Double)] = [
        (12, 0, 6, 3),
        (0, 9, 0, 9),
        (40, 2, 2, 2),
        (-4, 5, 0, 11),
    ]

    private func assertGridMatches(
        _ radii: (topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let swiftRadii = GPUIQuadCoverage.CornerRadii(
            topLeft: radii.topLeft, topRight: radii.topRight,
            bottomRight: radii.bottomRight, bottomLeft: radii.bottomLeft)
        // A third of a pixel, sampled a couple of pixels beyond the rect on
        // every side so the outside, edge, corner-arc and interior branches
        // are all covered.
        var samples = 0
        var sampleY = -2.0
        while sampleY <= Self.height + 2 {
            var sampleX = -2.0
            while sampleX <= Self.width + 2 {
                let expected = shaderRoundedRectDistance(
                    localX: sampleX, localY: sampleY, width: Self.width, height: Self.height, radii: radii)
                let actual = GPUIQuadCoverage.signedDistance(
                    localX: sampleX, localY: sampleY, width: Self.width, height: Self.height, radii: swiftRadii)
                XCTAssertEqual(
                    actual, expected, accuracy: 1e-9,
                    "signed distance diverges at (\(sampleX), \(sampleY)) for radii \(radii)",
                    file: file, line: line)
                samples += 1
                sampleX += 1.0 / 3
            }
            sampleY += 1.0 / 3
        }
        XCTAssertGreaterThan(samples, 8000, "the grid must actually be dense", file: file, line: line)
    }

    func testUniformRadiiMatchTheShaderOnADenseGrid() {
        for radius in Self.uniformRadii {
            assertGridMatches((radius, radius, radius, radius))
        }
    }

    func testPerCornerMixesMatchTheShaderOnADenseGrid() {
        for mix in Self.cornerMixes {
            assertGridMatches(mix)
        }
    }

    // MARK: - Coverage

    private func boxCoverage(pixelX: Int, pixelY: Int, rect: Rect, radius: Double = 0) -> Double {
        let radii = GPUIQuadCoverage.CornerRadii(uniform: radius)
        return GPUIQuadCoverage.coverage(pixelX: pixelX, pixelY: pixelY) { sampleX, sampleY in
            GPUIQuadCoverage.signedDistance(
                localX: sampleX - rect.minX, localY: sampleY - rect.minY,
                width: rect.size.width, height: rect.size.height, radii: radii)
        }
    }

    /// The regression this whole workstream started from: a radius-0 quad
    /// used to answer `rect.contains(pixelCentre) ? 1 : 0`, which is not a
    /// branch the shader has.
    func testSquareQuadsGetTheBoxSDFRampNotBinaryCoverage() {
        // Rect edge at x = 10.0: the pixel whose centre sits half a pixel
        // inside the edge is half covered, not fully covered.
        let rect = Rect(x: 10, y: 0, width: 20, height: 20)
        XCTAssertEqual(boxCoverage(pixelX: 10, pixelY: 10, rect: rect), 1.0, accuracy: 1e-9)

        // Edge on a pixel centre: exactly half.
        let halfPixelRect = Rect(x: 10.5, y: 0, width: 20, height: 20)
        XCTAssertEqual(boxCoverage(pixelX: 10, pixelY: 10, rect: halfPixelRect), 0.5, accuracy: 1e-9)

        // And a quarter-pixel offset lands in between — the value a binary
        // test cannot produce.
        let quarterPixelRect = Rect(x: 10.25, y: 0, width: 20, height: 20)
        let partial = boxCoverage(pixelX: 10, pixelY: 10, rect: quarterPixelRect)
        XCTAssertGreaterThan(partial, 0.5)
        XCTAssertLessThan(partial, 1.0)
    }

    /// The shipping AA is a half ramp: the shader only runs where the
    /// geometry covers the pixel centre, so nothing feathers *outward*.
    func testGeometryRuleCutsCoverageOutsideTheRect() {
        let integerRect = Rect(x: 10, y: 4, width: 20, height: 20)
        let fractionalRect = Rect(x: 10.75, y: 4, width: 20, height: 20)
        XCTAssertTrue(GPUIQuadCoverage.geometryCovers(localX: 10.5, localY: 10.5, rect: integerRect))
        XCTAssertFalse(
            GPUIQuadCoverage.geometryCovers(localX: 10.5, localY: 10.5, rect: fractionalRect),
            "a pixel centre left of a fractional edge is never shaded, so no outward feather exists")
        // Top-left inclusive, bottom-right exclusive, as the rasterizer is.
        XCTAssertTrue(GPUIQuadCoverage.geometryCovers(localX: 10, localY: 4, rect: integerRect))
        XCTAssertFalse(GPUIQuadCoverage.geometryCovers(localX: 30, localY: 24, rect: integerRect))
    }

    /// `aa` is `fwidth`, a finite difference over the 2×2 derivative quad —
    /// not the analytic gradient. Where both axes of the box SDF move
    /// across that quad it doubles to 2, which is why the far corner pixel
    /// of every square rect is 75 % covered on both backends.
    func testFarCornerPixelIsThreeQuartersCovered() {
        let rect = Rect(x: 0, y: 0, width: 40, height: 40)
        XCTAssertEqual(boxCoverage(pixelX: 39, pixelY: 39, rect: rect), 0.75, accuracy: 1e-9)
        // The near corner's derivative quad is anchored on the corner
        // itself, so its difference is zero and the pixel is fully covered.
        XCTAssertEqual(boxCoverage(pixelX: 0, pixelY: 0, rect: rect), 1.0, accuracy: 1e-9)
    }

    /// A rounded clip contributes an antialiased alpha rather than a
    /// boolean gate, and rejects per pixel centre against the float rect
    /// rather than an outward-rounded integer window.
    func testRoundedClipProducesFractionalAlphaAndExactRectRejection() {
        let clip = GPUIClipRegion(x: 8.0, y: 8.0, width: 32.0, height: 32.0, cornerRadius: 10.0)
        XCTAssertEqual(clip.alpha(atPixelX: 24, y: 24), 1.0, accuracy: 1e-9)
        let cornerAlpha = clip.alpha(atPixelX: 10, y: 10)
        XCTAssertGreaterThan(cornerAlpha, 0)
        XCTAssertLessThan(cornerAlpha, 1, "a rounded clip corner must feather, not gate")

        // Fractional clip edge: the pixel whose centre is outside is
        // rejected outright, where the old integer window painted it.
        let fractional = GPUIClipRegion(x: 10.2, y: 0.0, width: 10.0, height: 20.0)
        XCTAssertEqual(fractional.alpha(atPixelX: 10, y: 5), 1.0)
        XCTAssertEqual(fractional.alpha(atPixelX: 20, y: 5), 0.0, "20.5 is past 20.2 and the shader discards")
    }

    func testAdjacentFractionalClipsOwnTheirSharedPixelOnlyOnce() {
        let left = GPUIClipRegion(x: 0.0, y: 0.0, width: 8.5, height: 24.0)
        let right = GPUIClipRegion(x: 8.5, y: 0.0, width: 15.5, height: 24.0)
        let top = GPUIClipRegion(x: 0.0, y: 0.0, width: 24.0, height: 8.5)
        let bottom = GPUIClipRegion(x: 0.0, y: 8.5, width: 24.0, height: 15.5)

        XCTAssertEqual(left.alpha(atPixelX: 8, y: 12), 0)
        XCTAssertEqual(right.alpha(atPixelX: 8, y: 12), 1)
        XCTAssertEqual(top.alpha(atPixelX: 12, y: 8), 0)
        XCTAssertEqual(bottom.alpha(atPixelX: 12, y: 8), 1)
    }
}
