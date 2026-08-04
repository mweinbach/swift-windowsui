import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI

/// Pixel parity between the two renderers that consume `GPUIScene`: the
/// shipping D3D11 batch backend (rendered offscreen on WARP) and
/// `GPUIRawSceneRasterizer`, the CPU rasterizer that produces every
/// screenshot, gallery baseline and macOS-parity render.
///
/// This matters because the verification workflow validates the CPU
/// rasterizer while users see the GPU one. `CPUBatchRenderer`'s own doc
/// comment says "any pixel diff between CPU and GPU output indicates a bug
/// in the GPU shader" — before this suite, that claim was pinned by a
/// single scanline of a single synthetic 8×8 glyph.
///
/// Each canonical scene renders through both backends and asserts a
/// per-channel delta of at most `channelTolerance` over at least
/// `requiredMatchRatio` of pixels — the same tolerance shape
/// `scripts/gallery-compare.ps1` uses, so 8-bit rounding and antialiasing
/// noise pass while structural divergence does not.
///
/// **Every scene in this suite gates except the two magnified sampler
/// scenes.** Seven scenes used to carry a measured floor — corner AA at
/// 0.990–0.994, the shadow at 0.967, a large-radius material at 0.620 —
/// because the CPU rasterizer ran a different coverage ramp, a different
/// shadow, and a different blur ordering than the shipping shaders. WS-08
/// replaced all three with transcriptions of the HLSL, and the seven now
/// agree to a maximum per-channel delta of 1 over every pixel.
///
/// What is left on a floor is one divergence with one owner: the GPU
/// samples textures bilinearly and the CPU rasterizer picks the nearest
/// texel, which is invisible at 1:1 and unmissable under magnification.
/// `magnifiedGlyphGradientScene` and `magnifiedHighContrastImageScene`
/// exist to hold that number rather than let a gentle fixture hide it.
///
/// The floor machinery is the honest way to carry such a gap: a divergent
/// scene belongs *in* the suite with a recorded floor, not skipped. It is
/// pinned from both sides —
///
/// - the ratio may not fall below the floor recorded when the divergence
///   was accepted, so a shader change that halves a deferred scene's
///   agreement is a failure rather than a green skip;
/// - the ratio may not *reach* `requiredMatchRatio` either — a scene that
///   has quietly started passing fails with "promote me", because a
///   deferred scene that nobody unskips is a gate nobody is minding.
///
/// Skipping after computing the comparison, which is what this suite did
/// first, bought neither: it discarded the report it had just built.
@MainActor
final class CrossBackendPixelParityTests: XCTestCase {

    /// Maximum per-channel delta (0…255) that still counts as a match.
    private static let channelTolerance = 4
    /// Fraction of pixels that must be within tolerance.
    private static let requiredMatchRatio = 0.995

    // MARK: - Scene Catalogue

    /// A scene the backends are known to disagree on, with the floor its
    /// agreement may not fall below.
    private struct KnownDivergence {
        /// The workstream that will close the gap, and why it is open.
        let reason: String
        /// The measured match ratio, rounded *down* to three decimals: tight
        /// enough that a real regression trips it (0.001 of a 128×128
        /// surface is 16 pixels), loose enough to absorb the rounding
        /// differences between WARP builds.
        let matchRatioFloor: Double
    }

    private struct ParityScene {
        let name: String
        let size: IntSize
        let scene: GPUIScene
        /// Non-nil when the backends are known to disagree today.
        let knownDivergence: KnownDivergence?

        init(name: String, size: IntSize, knownDivergence: KnownDivergence? = nil, scene: GPUIScene) {
            self.name = name
            self.size = size
            self.knownDivergence = knownDivergence
            self.scene = scene
        }
    }

    private static let surface = IntSize(width: 128, height: 128)

    /// Opaque dark clear: an opaque destination keeps premultiplied GPU
    /// output and the CPU rasterizer's straight-alpha compositing on the
    /// same footing, so a diff means geometry or colour, not alpha
    /// convention.
    private static let clearColor = Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)

    private static func makeScene(_ build: (inout GPUIScene) -> Void) -> GPUIScene {
        var scene = GPUIScene(clearColor: clearColor)
        build(&scene)
        scene.finish()
        return scene
    }

    /// A solid, integer-aligned rectangle — the simplest thing both
    /// backends can draw, and the control for every other scene.
    private static func solidQuadScene() -> ParityScene {
        ParityScene(
            name: "solid quad",
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 16, y: 16, width: 96, height: 64,
                        startR: 0.20, startG: 0.55, startB: 0.90, startA: 1,
                        endR: 0.20, endG: 0.55, endB: 0.90, endA: 1
                    )
                )
            }
        )
    }

    private static func gradientScene(axis: Float, name: String) -> ParityScene {
        ParityScene(
            name: name,
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 8, y: 8, width: 112, height: 112,
                        startR: 0.95, startG: 0.25, startB: 0.15, startA: 1,
                        endR: 0.10, endG: 0.35, endB: 0.85, endA: 1,
                        gradientAxis: axis
                    )
                )
            }
        )
    }

    private static func uniformRadiusScene() -> ParityScene {
        ParityScene(
            name: "uniform corner radius",
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 16, y: 24, width: 96, height: 80,
                        cornerRadius: 18,
                        startR: 0.95, startG: 0.75, startB: 0.20, startA: 1,
                        endR: 0.95, endG: 0.75, endB: 0.20, endA: 1
                    )
                )
            }
        )
    }

    private static func perCornerRadiiScene() -> ParityScene {
        ParityScene(
            name: "per-corner radii",
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 16, y: 16, width: 96, height: 96,
                        startR: 0.35, startG: 0.85, startB: 0.55, startA: 1,
                        endR: 0.35, endG: 0.85, endB: 0.55, endA: 1,
                        cornerRadiusTopLeft: 28,
                        cornerRadiusTopRight: 4,
                        cornerRadiusBottomRight: 20,
                        cornerRadiusBottomLeft: 12
                    )
                )
            }
        )
    }

    private static func rotatedQuadScene() -> ParityScene {
        ParityScene(
            name: "rotated quad",
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 32, y: 40, width: 64, height: 48,
                        startR: 0.85, startG: 0.45, startB: 0.90, startA: 1,
                        endR: 0.85, endG: 0.45, endB: 0.90, endA: 1,
                        rotationRadians: 0.4
                    )
                )
            }
        )
    }

    /// R-ROT. A rotated card's `.shadow()`. The halo has to turn with the
    /// card — both backends grow the same soft envelope about the same
    /// turned rect, or the shadow is a diamond on one and a square on the
    /// other. The quad on top shares the angle so the fixture reads as one
    /// object rather than two.
    private static func rotatedShadowScene() -> ParityScene {
        ParityScene(
            name: "rotated shadow",
            size: surface,
            scene: makeScene { scene in
                scene.addShadow(
                    ShadowPrimitive(
                        x: 34, y: 42, width: 60, height: 44,
                        cornerRadius: 8,
                        colorR: 0, colorG: 0, colorB: 0, colorA: 0.7,
                        blurRadius: 9,
                        offsetX: 2, offsetY: 3,
                        rotationRadians: 0.55
                    )
                )
                scene.addQuad(
                    QuadPrimitive(
                        x: 34, y: 42, width: 60, height: 44,
                        cornerRadius: 8,
                        startR: 0.92, startG: 0.92, startB: 0.94, startA: 1,
                        endR: 0.92, endG: 0.92, endB: 0.94, endA: 1,
                        rotationRadians: 0.55
                    )
                )
            }
        )
    }

    /// R-ROT. The composite a rotated `clipsToBounds` subtree lands as: an
    /// offscreen bitmap drawn through `ImagePrimitive.rotationRadians`. The
    /// checker fixture is deliberate — a turned sampler that walks the
    /// texture in the wrong direction is invisible in a smooth gradient.
    private static func rotatedImageScene() -> ParityScene {
        let bitmap = checkerImageFixture(size: 8)
        return ParityScene(
            name: "rotated image",
            size: surface,
            scene: makeScene { scene in
                scene.bindImageResource(bitmap, for: 31)
                scene.addImage(
                    ImagePrimitive(
                        screenX: 32, screenY: 36, screenW: 64, screenH: 56,
                        uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                        opacity: 1,
                        textureID: 31,
                        rotationRadians: 0.6
                    )
                )
            }
        )
    }

    /// R-ROT. A glyph cell inside a rotated subtree. Magnified 8x for the
    /// same reason `magnifiedGlyphGradientScene` is: the turn has to reach
    /// the *sampler*, not only the vertices, and at 1:1 that is a rounding
    /// artefact rather than a picture.
    private static func rotatedGlyphScene() -> ParityScene {
        ParityScene(
            name: "rotated glyph cell",
            size: surface,
            scene: makeScene { scene in
                scene.glyphAtlas = rampGlyphAtlas()
                scene.addGlyph(
                    GlyphPrimitive(
                        screenX: 32, screenY: 32, screenW: 64, screenH: 64,
                        atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                        colorR: 0.95, colorG: 0.85, colorB: 0.35, colorA: 1,
                        rotationRadians: 0.45
                    )
                )
            }
        )
    }

    /// E6-TEXT. A run under a `scaleEffect` is laid out in the view's own
    /// space and the finished cells are scaled, so the glyph family now
    /// receives cells at *fractional* origins and fractional sizes drawn from
    /// a raster of a nearby-but-not-equal size. Every glyph cell the painter
    /// emitted before this was integer-snapped in both position and extent, so
    /// the sampler question the two backends have to answer the same way had
    /// never actually been asked by a shipping scene.
    ///
    /// Three cells with a 1.4x scale's worth of fractional geometry, spaced by
    /// a fractional advance — the shape of a scaled run, at the size a control
    /// label actually is.
    private static func scaledRunGlyphScene() -> ParityScene {
        ParityScene(
            name: "scaled run glyph cells",
            size: surface,
            scene: makeScene { scene in
                scene.glyphAtlas = rampGlyphAtlas()
                let scale: Float = 1.4
                for index in 0..<3 {
                    scene.addGlyph(
                        GlyphPrimitive(
                            screenX: 24.3 + Float(index) * 18.2 * scale,
                            screenY: 40.7,
                            screenW: 11 * scale,
                            screenH: 16 * scale,
                            atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                            colorR: 0.95, colorG: 0.85, colorB: 0.35, colorA: 1
                        )
                    )
                }
            }
        )
    }

    /// The same cells with the node's rotation on them: `placingRun` composes
    /// scale and rotation, so the two arrive together on one primitive.
    private static func scaledRotatedRunGlyphScene() -> ParityScene {
        ParityScene(
            name: "scaled and turned run glyph cells",
            size: surface,
            scene: makeScene { scene in
                scene.glyphAtlas = rampGlyphAtlas()
                let scale: Float = 1.4
                for index in 0..<3 {
                    scene.addGlyph(
                        GlyphPrimitive(
                            screenX: 24.3 + Float(index) * 18.2 * scale,
                            screenY: 40.7,
                            screenW: 11 * scale,
                            screenH: 16 * scale,
                            atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                            colorR: 0.95, colorG: 0.85, colorB: 0.35, colorA: 1,
                            rotationRadians: 0.45
                        )
                    )
                }
            }
        )
    }

    private static func shadowScene() -> ParityScene {
        ParityScene(
            name: "shadow",
            size: surface,
            scene: makeScene { scene in
                scene.addShadow(
                    ShadowPrimitive(
                        x: 32, y: 32, width: 64, height: 48,
                        cornerRadius: 10,
                        colorR: 0, colorG: 0, colorB: 0, colorA: 0.6,
                        blurRadius: 12
                    )
                )
                scene.addQuad(
                    QuadPrimitive(
                        x: 32, y: 32, width: 64, height: 48,
                        cornerRadius: 10,
                        startR: 0.9, startG: 0.9, startB: 0.9, startA: 1,
                        endR: 0.9, endG: 0.9, endB: 0.9, endA: 1
                    )
                )
            }
        )
    }

    /// A deliberately asymmetric RGB fixture: a channel swap is invisible in
    /// a gray or single-channel image, and a straight/premultiplied mix-up
    /// is invisible in a fully opaque one.
    private static func imageFixture(size: Int, alpha: UInt8, step: Int = 4) -> BitmapSurface {
        var pixels = Data()
        for y in 0..<size {
            for x in 0..<size {
                pixels.append(UInt8(min(255, step * x)))  // B
                pixels.append(UInt8(min(255, step * y + 60)))  // G
                pixels.append(200)  // R
                pixels.append(alpha)  // A
            }
        }
        return BitmapSurface(
            width: Int32(size), height: Int32(size), bytesPerRow: Int32(size * 4), pixels: pixels)
    }

    /// An image drawn at its native size: the pixel-format contract with no
    /// resampling in the way.
    private static func imageScene() -> ParityScene {
        let bitmap = imageFixture(size: 64, alpha: 255)
        return ParityScene(
            name: "image",
            size: surface,
            scene: makeScene { scene in
                scene.bindImageResource(bitmap, for: 7)
                scene.addImage(
                    ImagePrimitive(
                        screenX: 32, screenY: 32, screenW: 64, screenH: 64,
                        uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                        opacity: 1,
                        textureID: 7
                    )
                )
            }
        )
    }

    /// The same fixture at 40 % alpha: this is the scene that separates
    /// straight-alpha from premultiplied compositing, since an opaque image
    /// composites identically under either convention.
    private static func translucentImageScene() -> ParityScene {
        let bitmap = imageFixture(size: 64, alpha: 102)
        return ParityScene(
            name: "translucent image",
            size: surface,
            scene: makeScene { scene in
                scene.bindImageResource(bitmap, for: 8)
                scene.addImage(
                    ImagePrimitive(
                        screenX: 32, screenY: 32, screenW: 64, screenH: 64,
                        uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                        opacity: 0.75,
                        textureID: 8
                    )
                )
            }
        )
    }

    /// The same image stretched 3×, which is what every icon draw does.
    ///
    /// The backends resample differently — the GPU samples through a
    /// `MIN_MAG_MIP_LINEAR` sampler, `RasterTarget.drawImage` picks the
    /// nearest texel — so the fixture uses a gentle per-texel gradient that
    /// keeps the two filters inside the tolerance. Making them agree on a
    /// high-contrast image needs a bilinear CPU sampler and is still open;
    /// this scene's job is to prove the channel order and alpha convention
    /// survive magnification.
    private static func scaledImageScene() -> ParityScene {
        let bitmap = imageFixture(size: 32, alpha: 255, step: 2)
        return ParityScene(
            name: "scaled image",
            size: surface,
            scene: makeScene { scene in
                scene.bindImageResource(bitmap, for: 9)
                scene.addImage(
                    ImagePrimitive(
                        screenX: 16, screenY: 16, screenW: 96, screenH: 96,
                        uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                        opacity: 1,
                        textureID: 9
                    )
                )
            }
        )
    }

    /// A path lowered to quads by `PathToQuadTessellator` — the fast path
    /// the painter takes for simple shapes, and the one that stays inside
    /// the quad family on both backends.
    private static func pathAsQuadsScene() -> ParityScene {
        let triangle = PathPrimitive(
            elements: [
                .moveTo(Point(x: 24, y: 100)),
                .lineTo(Point(x: 64, y: 24)),
                .lineTo(Point(x: 104, y: 100)),
                .close,
            ],
            bounds: Rect(x: 24, y: 24, width: 80, height: 76),
            fillColor: Color(red: 0.95, green: 0.55, blue: 0.20, alpha: 1)
        )
        let quads = PathToQuadTessellator.tessellate(triangle) ?? []
        // An empty tessellation would make both backends draw the clear
        // colour and agree perfectly, which reads as a promotion rather
        // than as the broken fixture it is.
        XCTAssertFalse(quads.isEmpty, "the tessellator produced no quads for the fixture path")

        return ParityScene(
            name: "path as quads",
            size: surface,
            scene: makeScene { scene in
                for quad in quads {
                    scene.addQuad(quad)
                }
            }
        )
    }

    /// A `PathPrimitive` taking the shipping GPU route: the batch renderer
    /// CPU-rasterizes it and uploads the bitmap as a texture.
    private static func pathTextureScene() -> ParityScene {
        ParityScene(
            name: "path texture",
            size: surface,
            scene: makeScene { scene in
                scene.addPath(
                    PathPrimitive(
                        elements: [
                            .moveTo(Point(x: 24, y: 100)),
                            .lineTo(Point(x: 64, y: 24)),
                            .lineTo(Point(x: 104, y: 100)),
                            .close,
                        ],
                        bounds: Rect(x: 24, y: 24, width: 80, height: 76),
                        fillColor: Color(red: 0.20, green: 0.75, blue: 0.95, alpha: 1)
                    ),
                    toLayer: 0
                )
            }
        )
    }

    /// The same shipping path route with a rounded clip over it.
    ///
    /// The clip used to be baked into the raster: the D3D11 backend
    /// CPU-rasterized the path *cropped to its masked bounds*, which made the
    /// clip part of the cache key and squared off every corner arc. WS-18
    /// moved it to a draw parameter — a UV sub-rect for the rectangle, the
    /// shader's clip rect and radius for the arc — so this scene is what
    /// checks the two backends still cut the path in the same place.
    private static func clippedPathTextureScene() -> ParityScene {
        ParityScene(
            name: "clipped path texture",
            size: surface,
            scene: makeScene { scene in
                scene.addPath(
                    PathPrimitive(
                        elements: [
                            .moveTo(Point(x: 16, y: 16)),
                            .lineTo(Point(x: 112, y: 16)),
                            .lineTo(Point(x: 112, y: 112)),
                            .lineTo(Point(x: 16, y: 112)),
                            .close,
                        ],
                        bounds: Rect(x: 16, y: 16, width: 96, height: 96),
                        fillColor: Color(red: 0.95, green: 0.55, blue: 0.20, alpha: 1),
                        clipBounds: Rect(x: 32, y: 32, width: 64, height: 64),
                        clipCornerRadius: 16
                    ),
                    toLayer: 0
                )
            }
        )
    }

    /// A Material: an opaque backdrop with a blurred, tinted panel over it.
    ///
    /// Both backends now compose the effect the same way — snapshot the
    /// region, blur the snapshot, composite the tint through the quad's
    /// coverage. The CPU used to tint first and blur the framebuffer in
    /// place over the whole AABB, which cleared the ratio anyway (99.96%)
    /// because the residual was a thin band on the panel's edge; the
    /// scenes that ordering actually broke are the rounded ones, where it
    /// smeared a square halo outside the corners.
    private static func materialScene() -> ParityScene {
        ParityScene(
            name: "material",
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 0, y: 0, width: 128, height: 128,
                        startR: 0.10, startG: 0.45, startB: 0.75, startA: 1,
                        endR: 0.85, endG: 0.30, endB: 0.20, endA: 1,
                        gradientAxis: 1
                    )
                )
                scene.addQuad(
                    QuadPrimitive(
                        x: 24, y: 32, width: 80, height: 64,
                        startR: 1, startG: 1, startB: 1, startA: 0.4,
                        endR: 1, endG: 1, endB: 1, endA: 0.4,
                        blurRadius: 16
                    )
                )
            }
        )
    }

    /// A blur radius past the old 128-device-pixel cap.
    ///
    /// The painter emits `radius × displayScale`, so `.blur(radius: 80)` on
    /// a 2× display is 160 device pixels — which both backends used to clamp
    /// back to 128 and silently render sharper than asked. The shared cap is
    /// 256 now (`GPUISceneLimits.maxBlurRadius`, with the GPU's weight
    /// cbuffer sized to match), and this scene is what stops one of the two
    /// from quietly re-introducing a lower one: a backend still clamping at
    /// 128 blurs visibly less than the other and misses the ratio.
    ///
    /// Two flat bands rather than a gradient backdrop, because a kernel this
    /// wide averages a gradient into near-uniform grey, which any two
    /// implementations agree on for the wrong reason.
    ///
    /// This scene carried the suite's worst floor, 0.620, and it was the
    /// kernel *edge policy* that earned it: a kernel wider than the region
    /// makes the edges the dominant term rather than a border effect, and
    /// the CPU re-normalized the truncated kernel where the GPU clamps taps
    /// to the region's outermost texels. Clamping on both sides closed it
    /// outright. That each backend actually honours a radius past the old
    /// 128 cap is pinned separately, in `D3D11BackdropBlurTests`.
    private static func largeRadiusMaterialScene() -> ParityScene {
        ParityScene(
            name: "large-radius material",
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 0, y: 0, width: 128, height: 64,
                        startR: 0.95, startG: 0.30, startB: 0.15, startA: 1,
                        endR: 0.95, endG: 0.30, endB: 0.15, endA: 1
                    )
                )
                scene.addQuad(
                    QuadPrimitive(
                        x: 0, y: 64, width: 128, height: 64,
                        startR: 0.10, startG: 0.35, startB: 0.85, startA: 1,
                        endR: 0.10, endG: 0.35, endB: 0.85, endA: 1
                    )
                )
                scene.addQuad(
                    QuadPrimitive(
                        x: 16, y: 24, width: 96, height: 80,
                        startR: 1, startG: 1, startB: 1, startA: 0.25,
                        endR: 1, endG: 1, endB: 1, endA: 0.25,
                        blurRadius: 160
                    )
                )
            }
        )
    }

    /// Rounded-clip coverage: content clipped by a rounded container, which
    /// is what every card in the demo does.
    private static func clippedRoundedContentScene() -> ParityScene {
        ParityScene(
            name: "clipped rounded content",
            size: surface,
            scene: makeScene { scene in
                // Content deliberately larger than the clip on every side so
                // all four rounded corners are exercised.
                scene.addQuad(
                    QuadPrimitive(
                        x: 0, y: 0, width: 128, height: 128,
                        startR: 0.90, startG: 0.35, startB: 0.45, startA: 1,
                        endR: 0.20, endG: 0.55, endB: 0.90, endA: 1,
                        clipX: 24, clipY: 24, clipWidth: 80, clipHeight: 80,
                        clipCornerRadius: 20
                    )
                )
            }
        )
    }

    /// The same clip without rounding: the per-pixel clip rejection itself,
    /// with no corner arc to hide behind.
    private static func clippedRectContentScene() -> ParityScene {
        ParityScene(
            name: "clipped rect content",
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 0, y: 0, width: 128, height: 128,
                        startR: 0.90, startG: 0.35, startB: 0.45, startA: 1,
                        endR: 0.20, endG: 0.55, endB: 0.90, endA: 1,
                        clipX: 24, clipY: 24, clipWidth: 80, clipHeight: 80
                    )
                )
            }
        )
    }

    /// A fully opaque 16x16 glyph atlas cell: the glyph's own coverage is
    /// uniform, so the only thing this scene can disagree about is the
    /// rounded clip's coverage ramp.
    private static func solidGlyphAtlas() -> GlyphAtlasSnapshot {
        let side = 16
        var pixels = [UInt8]()
        pixels.reserveCapacity(side * side * 4)
        for _ in 0..<(side * side) {
            pixels.append(contentsOf: [255, 255, 255, 255])
        }
        return GlyphAtlasSnapshot(
            width: Int32(side), height: Int32(side), pixels: Data(pixels),
            contentVersion: RenderContentVersion.next(), update: .full)
    }

    /// Text inside a rounded container. Before `clipCornerRadius` reached the
    /// glyph family, text in a rounded card was clipped square on both
    /// backends — consistent, and consistently wrong against macOS — so this
    /// scene could not have failed and could not have caught it either.
    private static func glyphInRoundedContainerScene() -> ParityScene {
        ParityScene(
            name: "glyph in rounded container",
            size: surface,
            scene: makeScene { scene in
                scene.glyphAtlas = solidGlyphAtlas()
                for row in 0..<4 {
                    for column in 0..<4 {
                        scene.addGlyph(
                            GlyphPrimitive(
                                screenX: Float(8 + column * 28), screenY: Float(8 + row * 28),
                                screenW: 28, screenH: 28,
                                atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                                colorR: 0.95, colorG: 0.85, colorB: 0.35, colorA: 1,
                                clipX: 24, clipY: 24, clipWidth: 80, clipHeight: 80,
                                clipCornerRadius: 20
                            )
                        )
                    }
                }
            }
        )
    }

    /// An 8x8 atlas cell whose alpha ramps across its texels, drawn at 8x.
    ///
    /// `solidGlyphAtlas` is uniform and opaque, so the glyph sampler itself
    /// is unobservable through it: every tap of every filter returns the
    /// same texel. This cell makes the sampler the subject — the GPU reads
    /// it through `MIN_MAG_MIP_LINEAR`, the CPU picks the nearest texel, and
    /// magnifying 8x puts 64 screen pixels inside each texel so the
    /// difference is a visible staircase rather than a rounding artefact.
    /// Real text magnifies far less than this, but it magnifies: a glyph
    /// rastered at one scale and drawn at another (icon scaling, an
    /// animating `.scaleEffect` on text) samples between texels exactly like
    /// this.
    ///
    /// Colour channels carry the alpha value, matching the premultiplied
    /// white `NativeTextRenderer.tint` writes into the atlas — the shader
    /// reads only `.a`, and so does the rasterizer now, but a fixture that
    /// disagreed with the real producer would be testing a shape nothing
    /// ships.
    ///
    /// This scene carried a `knownDivergence` floor of 0.835 until WS-18 gave
    /// `RasterTarget.drawGlyph` a bilinear tap; it gates like every other
    /// scene now.
    private static func rampGlyphAtlas() -> GlyphAtlasSnapshot {
        let side = 8
        var pixels = [UInt8]()
        pixels.reserveCapacity(side * side * 4)
        for _ in 0..<side {
            for column in 0..<side {
                let coverage = UInt8(column * 255 / (side - 1))
                pixels.append(contentsOf: [coverage, coverage, coverage, coverage])
            }
        }
        return GlyphAtlasSnapshot(
            width: Int32(side), height: Int32(side), pixels: Data(pixels),
            contentVersion: RenderContentVersion.next(), update: .full)
    }

    private static func magnifiedGlyphGradientScene() -> ParityScene {
        ParityScene(
            name: "magnified gradient glyph cell",
            size: surface,
            scene: makeScene { scene in
                scene.glyphAtlas = rampGlyphAtlas()
                scene.addGlyph(
                    GlyphPrimitive(
                        screenX: 32, screenY: 32, screenW: 64, screenH: 64,
                        atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                        colorR: 0.95, colorG: 0.85, colorB: 0.35, colorA: 1
                    )
                )
            }
        )
    }

    /// A high-contrast 8x8 image drawn at 8x — the same sampler question on
    /// the image family.
    ///
    /// `scaledImageScene` uses a deliberately gentle per-texel gradient so
    /// nearest and linear stay inside the tolerance; that keeps the channel
    /// order and alpha convention gated, but it means the filter gap itself
    /// is invisible by construction. A checkerboard is the opposite fixture:
    /// every texel boundary is a full-range step, so the gap is the whole
    /// signal.
    ///
    /// It carried a `knownDivergence` floor of 0.753 (max channel delta 116)
    /// until WS-18 taught `RasterTarget.drawImage` to filter *premultiplied*
    /// texels the way `imageTexture.Sample` does.
    private static func checkerImageFixture(size: Int) -> BitmapSurface {
        var pixels = Data()
        for y in 0..<size {
            for x in 0..<size {
                // Asymmetric across channels for the same reason
                // `imageFixture` is: a channel swap must not survive.
                let isLight = (x + y) % 2 == 0
                pixels.append(isLight ? 245 : 10)  // B
                pixels.append(isLight ? 245 : 30)  // G
                pixels.append(isLight ? 200 : 10)  // R
                pixels.append(255)  // A
            }
        }
        return BitmapSurface(
            width: Int32(size), height: Int32(size), bytesPerRow: Int32(size * 4), pixels: pixels)
    }

    private static func magnifiedHighContrastImageScene() -> ParityScene {
        let bitmap = checkerImageFixture(size: 8)
        return ParityScene(
            name: "magnified high-contrast image",
            size: surface,
            scene: makeScene { scene in
                scene.bindImageResource(bitmap, for: 22)
                scene.addImage(
                    ImagePrimitive(
                        screenX: 32, screenY: 32, screenW: 64, screenH: 64,
                        uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                        opacity: 1,
                        textureID: 22
                    )
                )
            }
        )
    }

    /// The same rounding on the image family: an icon or a `.drawingGroup()`
    /// composite inside a rounded card.
    private static func imageInRoundedContainerScene() -> ParityScene {
        let bitmap = imageFixture(size: 64, alpha: 255)
        return ParityScene(
            name: "image in rounded container",
            size: surface,
            scene: makeScene { scene in
                scene.bindImageResource(bitmap, for: 21)
                scene.addImage(
                    ImagePrimitive(
                        screenX: 0, screenY: 0, screenW: 128, screenH: 128,
                        uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                        opacity: 1,
                        clipX: 24, clipY: 24, clipWidth: 80, clipHeight: 80,
                        clipCornerRadius: 20,
                        textureID: 21
                    )
                )
            }
        )
    }

    /// And on the shadow family: a card shadow inside a rounded scroll clip.
    private static func shadowInRoundedContainerScene() -> ParityScene {
        ParityScene(
            name: "shadow in rounded container",
            size: surface,
            scene: makeScene { scene in
                scene.addShadow(
                    ShadowPrimitive(
                        x: 20, y: 20, width: 88, height: 88,
                        cornerRadius: 8,
                        colorR: 0, colorG: 0, colorB: 0, colorA: 0.8,
                        blurRadius: 10,
                        clipX: 24, clipY: 24, clipWidth: 80, clipHeight: 80,
                        clipCornerRadius: 20
                    )
                )
            }
        )
    }

    /// A colour effect applied to a gradient: `applyColorEffect` exists once
    /// in HLSL and once in Swift, and this is the only thing that keeps the
    /// two transcriptions honest.
    private static func colorEffectScene() -> ParityScene {
        ParityScene(
            name: "grayscale colour effect",
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 16, y: 16, width: 96, height: 96,
                        startR: 0.90, startG: 0.30, startB: 0.20, startA: 1,
                        endR: 0.15, endG: 0.45, endB: 0.85, endA: 1,
                        gradientAxis: 1,
                        effectType: 4,
                        effectIntensity: 1
                    )
                )
            }
        )
    }

    /// Alpha compositing: three overlapping translucent quads, so the blend
    /// equation itself is under test rather than opaque coverage.
    private static func translucentStackScene() -> ParityScene {
        ParityScene(
            name: "translucent stack",
            size: surface,
            scene: makeScene { scene in
                scene.addQuad(
                    QuadPrimitive(
                        x: 16, y: 16, width: 64, height: 64,
                        startR: 0.95, startG: 0.25, startB: 0.25, startA: 0.6,
                        endR: 0.95, endG: 0.25, endB: 0.25, endA: 0.6
                    )
                )
                scene.addQuad(
                    QuadPrimitive(
                        x: 48, y: 32, width: 64, height: 64,
                        startR: 0.25, startG: 0.85, startB: 0.35, startA: 0.5,
                        endR: 0.25, endG: 0.85, endB: 0.35, endA: 0.5
                    )
                )
                scene.addQuad(
                    QuadPrimitive(
                        x: 32, y: 56, width: 64, height: 56,
                        startR: 0.30, startG: 0.40, startB: 0.95, startA: 0.4,
                        endR: 0.30, endG: 0.40, endB: 0.95, endA: 0.4
                    )
                )
            }
        )
    }

    /// A thick open polyline with one of the three caps, on the shipping GPU
    /// path route (CPU-rasterized, uploaded as a texture).
    ///
    /// The primitive used to carry a `lineWidth` and nothing else, so both
    /// stroke rasterizers invented the rest and a `Canvas` stroke asking for
    /// a round cap got a butt one here and a square one through the painter's
    /// tessellator. Each cap is its own scene because a cap is the only place
    /// the three differ, and a single fixture would let two of them hide.
    private static func cappedPolylineScene(_ cap: StrokeStyle.LineCap, name: String) -> ParityScene {
        ParityScene(
            name: name,
            size: surface,
            scene: makeScene { scene in
                scene.addPath(
                    PathPrimitive(
                        elements: [
                            .moveTo(Point(x: 28, y: 36)),
                            .lineTo(Point(x: 96, y: 36)),
                            .lineTo(Point(x: 96, y: 92)),
                        ],
                        bounds: Rect(x: 8, y: 16, width: 112, height: 96),
                        strokeColor: Color(red: 0.95, green: 0.65, blue: 0.20, alpha: 1),
                        lineWidth: 14,
                        lineCap: cap
                    ),
                    toLayer: 0
                )
            }
        )
    }

    /// A sharp corner with one of the three joins, plus the miter-limit
    /// exceedance that turns a miter into a bevel. `miterLimit` is the one
    /// stroke scalar that changes the drawn shape without changing any
    /// coordinate, so it needs its own scene.
    private static func joinedCornerScene(
        _ join: StrokeStyle.LineJoin, miterLimit: Double = 10, name: String
    ) -> ParityScene {
        ParityScene(
            name: name,
            size: surface,
            scene: makeScene { scene in
                scene.addPath(
                    PathPrimitive(
                        elements: [
                            .moveTo(Point(x: 24, y: 108)),
                            .lineTo(Point(x: 64, y: 24)),
                            .lineTo(Point(x: 104, y: 108)),
                        ],
                        bounds: Rect(x: 8, y: 0, width: 112, height: 128),
                        strokeColor: Color(red: 0.35, green: 0.80, blue: 0.95, alpha: 1),
                        lineWidth: 12,
                        lineJoin: join,
                        miterLimit: miterLimit
                    ),
                    toLayer: 0
                )
            }
        )
    }

    /// The same round-capped, round-joined polyline the painter promotes to
    /// quads — segment bodies plus a disc per cap and join. This is the route
    /// every SF-symbol vector icon takes, and the one where a cap is a
    /// `cornerRadius` rather than a coverage polygon.
    private static func roundCappedPolylineAsQuadsScene() -> ParityScene {
        let polyline = PathPrimitive(
            elements: [
                .moveTo(Point(x: 28, y: 40)),
                .lineTo(Point(x: 72, y: 40)),
                .lineTo(Point(x: 100, y: 96)),
            ],
            bounds: Rect(x: 8, y: 20, width: 112, height: 96),
            strokeColor: Color(red: 0.90, green: 0.35, blue: 0.55, alpha: 1),
            lineWidth: 12,
            lineCap: .round,
            lineJoin: .round
        )
        let quads = PathToQuadTessellator.tessellate(polyline) ?? []
        XCTAssertEqual(quads.count, 5, "two bodies, two cap discs and one join disc")

        return ParityScene(
            name: "round-capped polyline as quads",
            size: surface,
            scene: makeScene { scene in
                for quad in quads { scene.addQuad(quad) }
            }
        )
    }

    // MARK: - Assertion

    private func assertParity(_ parityScene: ParityScene, file: StaticString = #filePath, line: UInt = #line) throws {
        let cpu = GPUIRawSceneRasterizer.rasterize(parityScene.scene, size: parityScene.size)
        // No `catch` here on purpose. This used to swallow a GPU render
        // failure into a skip for any scene carrying a known divergence,
        // which turned "the backend threw" into "we already knew about
        // that". `WARPBatchRenderer` throws `XCTSkip` itself when no D3D11
        // device exists, and that propagates as a skip; anything else is a
        // failure for every scene.
        let gpu = try WARPBatchRenderer.render(parityScene.scene, size: parityScene.size)

        let report = comparePixels(gpu, cpu, tolerance: Self.channelTolerance)
        var detail = String(
            format: "%@: %.4f of pixels within ±%d (max channel delta %d)",
            parityScene.name, report.matchRatio, Self.channelTolerance, report.maxChannelDelta)
        if let failure = report.firstFailure {
            detail +=
                "; first mismatch at (\(failure.x), \(failure.y)) GPU BGRA \(failure.actual) vs CPU \(failure.expected)"
        }

        guard let divergence = parityScene.knownDivergence else {
            XCTAssertGreaterThanOrEqual(
                report.matchRatio, Self.requiredMatchRatio,
                "Cross-backend parity failed for \(detail)", file: file, line: line)
            return
        }

        // A deferred scene is pinned from both sides: it may not drift down,
        // and it may not quietly become passable without anyone noticing.
        XCTAssertGreaterThanOrEqual(
            report.matchRatio, divergence.matchRatioFloor,
            "Known-divergent scene regressed below its recorded floor of \(divergence.matchRatioFloor) — "
                + "\(detail). The accepted divergence is: \(divergence.reason)",
            file: file, line: line)

        if report.matchRatio >= Self.requiredMatchRatio {
            XCTFail(
                "Promote me: \(detail) now meets the suite's required ratio of \(Self.requiredMatchRatio), so "
                    + "its knownDivergence must be removed and the scene must gate like the rest. The "
                    + "divergence it was deferred for was: \(divergence.reason)",
                file: file, line: line)
        }
    }

    // MARK: - Scenes

    func testSolidQuadParity() async throws { try assertParity(Self.solidQuadScene()) }

    func testVerticalGradientParity() async throws {
        try assertParity(Self.gradientScene(axis: 0, name: "vertical gradient"))
    }

    func testHorizontalGradientParity() async throws {
        try assertParity(Self.gradientScene(axis: 1, name: "horizontal gradient"))
    }

    func testUniformCornerRadiusParity() async throws { try assertParity(Self.uniformRadiusScene()) }

    func testPerCornerRadiiParity() async throws { try assertParity(Self.perCornerRadiiScene()) }

    func testTranslucentStackParity() async throws { try assertParity(Self.translucentStackScene()) }

    func testClippedRectContentParity() async throws { try assertParity(Self.clippedRectContentScene()) }

    func testColorEffectParity() async throws { try assertParity(Self.colorEffectScene()) }

    func testClippedRoundedContentParity() async throws { try assertParity(Self.clippedRoundedContentScene()) }

    func testGlyphInRoundedContainerParity() async throws { try assertParity(Self.glyphInRoundedContainerScene()) }

    func testImageInRoundedContainerParity() async throws { try assertParity(Self.imageInRoundedContainerScene()) }

    func testShadowInRoundedContainerParity() async throws { try assertParity(Self.shadowInRoundedContainerScene()) }

    func testPathAsQuadsParity() async throws { try assertParity(Self.pathAsQuadsScene()) }

    func testRotatedQuadParity() async throws { try assertParity(Self.rotatedQuadScene()) }

    func testRotatedShadowParity() async throws { try assertParity(Self.rotatedShadowScene()) }

    func testRotatedImageParity() async throws { try assertParity(Self.rotatedImageScene()) }

    func testRotatedGlyphParity() async throws { try assertParity(Self.rotatedGlyphScene()) }

    func testScaledRunGlyphParity() async throws { try assertParity(Self.scaledRunGlyphScene()) }

    func testScaledRotatedRunGlyphParity() async throws { try assertParity(Self.scaledRotatedRunGlyphScene()) }

    func testShadowParity() async throws { try assertParity(Self.shadowScene()) }

    func testImageParity() async throws { try assertParity(Self.imageScene()) }

    func testTranslucentImageParity() async throws { try assertParity(Self.translucentImageScene()) }

    func testScaledImageParity() async throws { try assertParity(Self.scaledImageScene()) }

    func testPathTextureParity() async throws { try assertParity(Self.pathTextureScene()) }

    func testClippedPathTextureParity() async throws { try assertParity(Self.clippedPathTextureScene()) }

    func testButtCappedPolylineParity() async throws {
        try assertParity(Self.cappedPolylineScene(.butt, name: "butt-capped polyline"))
    }

    func testRoundCappedPolylineParity() async throws {
        try assertParity(Self.cappedPolylineScene(.round, name: "round-capped polyline"))
    }

    func testSquareCappedPolylineParity() async throws {
        try assertParity(Self.cappedPolylineScene(.square, name: "square-capped polyline"))
    }

    func testMiterJoinedCornerParity() async throws {
        try assertParity(Self.joinedCornerScene(.miter, name: "miter-joined corner"))
    }

    func testRoundJoinedCornerParity() async throws {
        try assertParity(Self.joinedCornerScene(.round, name: "round-joined corner"))
    }

    func testBevelJoinedCornerParity() async throws {
        try assertParity(Self.joinedCornerScene(.bevel, name: "bevel-joined corner"))
    }

    func testMiterLimitExceededCornerParity() async throws {
        try assertParity(
            Self.joinedCornerScene(.miter, miterLimit: 1.5, name: "miter past its limit"))
    }

    func testRoundCappedPolylineAsQuadsParity() async throws {
        try assertParity(Self.roundCappedPolylineAsQuadsScene())
    }

    func testMagnifiedGlyphGradientParity() async throws { try assertParity(Self.magnifiedGlyphGradientScene()) }

    func testMagnifiedHighContrastImageParity() async throws {
        try assertParity(Self.magnifiedHighContrastImageScene())
    }

    func testMaterialParity() async throws { try assertParity(Self.materialScene()) }

    func testLargeRadiusMaterialParity() async throws { try assertParity(Self.largeRadiusMaterialScene()) }
}
