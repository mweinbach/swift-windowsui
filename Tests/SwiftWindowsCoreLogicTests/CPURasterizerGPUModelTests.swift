import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

/// The CPU rasterizer's shadow, material and effect models, pinned against
/// the shapes the shipping shaders produce.
///
/// `CrossBackendPixelParityTests` proves the two backends agree today;
/// this suite says *what* they agree on, so a change that moves both at
/// once still has to be deliberate. Every assertion here names a
/// divergence the audit found and WS-08 closed.
@MainActor
final class CPURasterizerGPUModelTests: XCTestCase {

    private static let surface = IntSize(width: 128, height: 128)

    private func render(_ build: (inout GPUIScene) -> Void, clearColor: Color = .black) -> BitmapSurface {
        var scene = GPUIScene(clearColor: clearColor)
        build(&scene)
        scene.finish()
        return GPUIRawSceneRasterizer.rasterize(scene, size: Self.surface)
    }

    private func alpha(_ bitmap: BitmapSurface, x: Int, y: Int) -> Double {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        // The scenes below draw black-on-black, so the *blue* channel over a
        // white clear reads as "how much shadow landed here".
        return 1 - Double(bitmap.pixels[offset]) / 255
    }

    // MARK: - Shadows

    /// The envelope: the shader expands the rect by `2 · blurRadius`, so a
    /// `blurRadius: 12` shadow reaches 24 px beyond the rect. The
    /// rasterizer used to expand by `blurRadius / 2` — 6 px — with a 1 px
    /// ramp, which is a different shadow rather than a differently
    /// antialiased one.
    func testShadowEnvelopeExtendsTwiceTheBlurRadius() async {
        let blurRadius: Float = 12
        let bitmap = render(
            { scene in
                scene.addShadow(
                    ShadowPrimitive(
                        x: 40, y: 40, width: 48, height: 48,
                        cornerRadius: 0,
                        colorR: 0, colorG: 0, colorB: 0, colorA: 1,
                        blurRadius: blurRadius))
            }, clearColor: .white)

        // Just inside the old ½·blur envelope: ink, then and now.
        XCTAssertGreaterThan(alpha(bitmap, x: 36, y: 64), 0.01)
        // Between the old envelope and the new one: ink only under the GPU
        // model. `1 - smoothstep(-6, 12, distance)` at 8 px out is small but
        // firmly non-zero.
        let outerAlpha = alpha(bitmap, x: 31, y: 64)
        XCTAssertGreaterThan(outerAlpha, 0.01, "the shadow must reach past the rect by more than blur/2")
        // And it is gone by 2·blur.
        XCTAssertLessThan(alpha(bitmap, x: 15, y: 64), 0.01, "nothing past 2 x blurRadius")
    }

    /// Peak alpha is the requested alpha. The magic `* 0.55` the
    /// rasterizer applied appeared nowhere else in the stack — not in the
    /// shader, not in the painter, not in the design constants — and is
    /// retired rather than promoted to a documented constant.
    func testShadowPeakAlphaIsTheRequestedAlpha() async {
        let bitmap = render(
            { scene in
                scene.addShadow(
                    ShadowPrimitive(
                        x: 32, y: 32, width: 64, height: 64,
                        colorR: 0, colorG: 0, colorB: 0, colorA: 1,
                        blurRadius: 8))
            }, clearColor: .white)

        XCTAssertEqual(alpha(bitmap, x: 64, y: 64), 1.0, accuracy: 0.01, "0.55 is gone")
    }

    /// The falloff is `1 - smoothstep(-blur/2, blur, distance)`, which is
    /// exactly ½ where `distance` is the midpoint of that range.
    func testShadowFalloffIsSmoothstepNotALinearRamp() async {
        let bitmap = render(
            { scene in
                scene.addShadow(
                    ShadowPrimitive(
                        x: 32, y: 32, width: 64, height: 64,
                        colorR: 0, colorG: 0, colorB: 0, colorA: 1,
                        blurRadius: 16))
            }, clearColor: .white)

        // distance == (−8 + 16) / 2 == 4 px outside the rect's left edge.
        XCTAssertEqual(alpha(bitmap, x: 27, y: 64), 0.5, accuracy: 0.06)
        // A linear ramp would put ~0.25 and ~0.75 symmetrically about it;
        // smoothstep is flatter at the ends.
        XCTAssertLessThan(alpha(bitmap, x: 20, y: 64), 0.25)
        XCTAssertGreaterThan(alpha(bitmap, x: 34, y: 64), 0.75)
    }

    // MARK: - Material composite

    /// The blur is applied to a *snapshot* of the backdrop and composited
    /// through the quad's coverage, so a rounded `blurOpaque` material
    /// leaves the pixels outside its corners exactly as it found them.
    ///
    /// The rasterizer used to blur the framebuffer in place over the
    /// quad's whole axis-aligned window and then force alpha to 255 over
    /// the same window, which turned an opaque material's rounded corners
    /// into square opaque blocks in every screenshot.
    func testOpaqueRoundedMaterialLeavesItsAABBCornersUntouched() async {
        func scene(withMaterial: Bool) -> BitmapSurface {
            render { scene in
                // Checkerboard backdrop: a corner that got smeared is
                // obvious, a corner that got overwritten even more so.
                for row in 0..<16 {
                    for column in 0..<16 {
                        let dark = (row + column) % 2 == 0
                        scene.addQuad(
                            QuadPrimitive(
                                x: Float(column * 8), y: Float(row * 8), width: 8, height: 8,
                                startR: dark ? 0.1 : 0.9, startG: dark ? 0.1 : 0.9, startB: dark ? 0.1 : 0.9,
                                startA: 1,
                                endR: dark ? 0.1 : 0.9, endG: dark ? 0.1 : 0.9, endB: dark ? 0.1 : 0.9, endA: 1))
                    }
                }
                guard withMaterial else { return }
                scene.addQuad(
                    QuadPrimitive(
                        x: 24, y: 24, width: 80, height: 80,
                        cornerRadius: 24,
                        startR: 1, startG: 1, startB: 1, startA: 0.3,
                        endR: 1, endG: 1, endB: 1, endA: 0.3,
                        blurRadius: 12,
                        blurOpaque: 1))
            }
        }

        let plain = scene(withMaterial: false)
        let material = scene(withMaterial: true)

        // The four AABB corners of the material quad, one pixel inside the
        // bounding box and well outside the radius-24 arc.
        for corner in [(25, 25), (102, 25), (25, 102), (102, 102)] {
            let offset = corner.1 * Int(material.bytesPerRow) + corner.0 * 4
            XCTAssertEqual(
                Array(material.pixels[offset..<(offset + 4)]),
                Array(plain.pixels[offset..<(offset + 4)]),
                "the material must not touch (\(corner.0), \(corner.1)) — it is outside its rounded coverage")
        }

        // And it did do something in the middle.
        let centre = 64 * Int(material.bytesPerRow) + 64 * 4
        XCTAssertNotEqual(
            Array(material.pixels[centre..<(centre + 4)]), Array(plain.pixels[centre..<(centre + 4)]))
    }

    /// The blur radius is capped at the same value on both backends, so a
    /// runaway animated radius truncates identically rather than
    /// allocating an unbounded kernel on one of them.
    func testBlurRadiusCapIsSharedWithTheGPUEngine() async {
        func material(radius: Float) -> BitmapSurface {
            render { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 0, y: 0, width: 128, height: 64,
                        startR: 0.95, startG: 0.30, startB: 0.15, startA: 1,
                        endR: 0.95, endG: 0.30, endB: 0.15, endA: 1))
                scene.addQuad(
                    QuadPrimitive(
                        x: 0, y: 64, width: 128, height: 64,
                        startR: 0.10, startG: 0.35, startB: 0.85, startA: 1,
                        endR: 0.10, endG: 0.35, endB: 0.85, endA: 1))
                scene.addQuad(
                    QuadPrimitive(
                        x: 8, y: 8, width: 112, height: 112,
                        startR: 1, startG: 1, startB: 1, startA: 0.2,
                        endR: 1, endG: 1, endB: 1, endA: 0.2,
                        blurRadius: radius))
            }
        }

        let cap = GPUISceneLimits.maxBlurRadius
        XCTAssertEqual(Double(cap), 256, "the shared cap moved; update the GPU weight cbuffer with it")
        XCTAssertEqual(material(radius: cap).pixels, material(radius: cap + 1).pixels)
        XCTAssertEqual(material(radius: cap).pixels, material(radius: 100_000).pixels)
        XCTAssertNotEqual(
            material(radius: 40).pixels, material(radius: cap).pixels,
            "radii under the cap must still differ, or the cap is not a cap")
    }

    // MARK: - Colour effects

    /// `luminanceToAlpha` writes alpha, so the shader applies it *before*
    /// multiplying by coverage. Applying it after — which the rasterizer
    /// did — overwrote the antialiasing and the quad's own alpha, turning
    /// the shape into a hard-edged block.
    func testLuminanceToAlphaKeepsCoverageAndClipping() async {
        // effectType 8, on a half-pixel-offset rect so its edge pixels are
        // genuinely fractional, under a rounded clip. The clear is fully
        // transparent so the surface alpha *is* the quad's alpha.
        let bitmap = render(
            { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 16.5, y: 16, width: 80, height: 80,
                        startR: 0.9, startG: 0.9, startB: 0.9, startA: 1,
                        endR: 0.9, endG: 0.9, endB: 0.9, endA: 1,
                        clipX: 20, clipY: 20, clipWidth: 72, clipHeight: 72,
                        clipCornerRadius: 24,
                        effectType: 8))
            }, clearColor: Color(red: 0, green: 0, blue: 0, alpha: 0))

        func alphaAt(x: Int, y: Int) -> Double {
            let offset = y * Int(bitmap.bytesPerRow) + x * 4
            return Double(bitmap.pixels[offset + 3]) / 255
        }
        // Interior: alpha is the luminance of 0.9 grey, which is 0.9.
        XCTAssertEqual(alphaAt(x: 56, y: 56), 0.9, accuracy: 0.01)
        // The clip's rounded corner still feathers rather than stepping:
        // somewhere along its diagonal a pixel is partly covered, which is
        // impossible if the effect has overwritten alpha with luminance.
        let feathered = (22...34).map { alphaAt(x: $0, y: $0) }.filter { $0 > 0.001 && $0 < 0.895 }
        XCTAssertFalse(
            feathered.isEmpty,
            "coverage survives the effect instead of being overwritten by it; diagonal alphas were "
                + "\((22...34).map { alphaAt(x: $0, y: $0) })")
    }
}
