import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics
@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI

/// WS-20: the render-pass vocabulary — `RenderTargetDescriptor`,
/// `RenderPassDescriptor`, `SubTextureRegion` and `BlurPassPlan` — plus the
/// two behaviours it exists to make impossible:
///
/// 1. A sub-texture sample that reaches texels outside its region. The
///    grow-only ping-pong targets hold the previous, larger region's pixels
///    everywhere past the current one, so an unclamped UV smears last
///    material's content along this one's right and bottom edge.
/// 2. A blur schedule that the two backends compute differently. The plan
///    is keyed on the radius alone precisely so a one-pixel disagreement
///    about the blurred region cannot flip one backend to a different
///    number of halvings.
@MainActor
final class RenderPassAbstractionTests: XCTestCase {

    // MARK: - SubTextureRegion

    func testRegionCannotDescribeTexelsOutsideItsTexture() async {
        let region = SubTextureRegion(
            originX: 200, originY: 300, width: 4096, height: 4096,
            textureWidth: 256, textureHeight: 512)
        XCTAssertEqual(region.originX, 200)
        XCTAssertEqual(region.originY, 300)
        XCTAssertEqual(region.maxX, 256, "region must be clipped to the texture's width")
        XCTAssertEqual(region.maxY, 512, "region must be clipped to the texture's height")

        let negative = SubTextureRegion(
            originX: -10, originY: -10, width: -4, height: -4,
            textureWidth: 64, textureHeight: 64)
        XCTAssertEqual(negative.originX, 0)
        XCTAssertEqual(negative.originY, 0)
        XCTAssertTrue(negative.isEmpty, "a negative extent must produce an empty region, not a trap")
    }

    /// The half-texel inset is what separates "the region's boundary" from
    /// "the region's outermost texel centre". A tap clamped to the boundary
    /// still blends the first texel outside the region 50/50.
    func testClampBoundsAreTexelCentresNotRegionBoundaries() async {
        let region = SubTextureRegion(
            originX: 0, originY: 0, width: 100, height: 50,
            textureWidth: 256, textureHeight: 256)
        XCTAssertEqual(region.uvMinU, 0.5 / 256, accuracy: 1e-7)
        XCTAssertEqual(region.uvMinV, 0.5 / 256, accuracy: 1e-7)
        XCTAssertEqual(region.uvMaxU, (100 - 0.5) / 256, accuracy: 1e-7)
        XCTAssertEqual(region.uvMaxV, (50 - 0.5) / 256, accuracy: 1e-7)
    }

    func testClampUVNeverLeavesTheRegion() async {
        let region = SubTextureRegion(
            originX: 8, originY: 16, width: 40, height: 24,
            textureWidth: 128, textureHeight: 128)

        for (u, v) in [
            (Float(-5), Float(-5)), (0, 0), (1, 1), (5, 5),
            (region.uvMaxU + 0.25, region.uvMaxV + 0.25),
        ] {
            let clamped = region.clampUV(u, v)
            XCTAssertGreaterThanOrEqual(clamped.u, region.uvMinU)
            XCTAssertLessThanOrEqual(clamped.u, region.uvMaxU)
            XCTAssertGreaterThanOrEqual(clamped.v, region.uvMinV)
            XCTAssertLessThanOrEqual(clamped.v, region.uvMaxV)

            // The real invariant: the clamped tap addresses a texel INSIDE
            // the region, with its whole bilinear footprint inside too.
            let texelX = clamped.u * Float(region.textureWidth)
            let texelY = clamped.v * Float(region.textureHeight)
            XCTAssertGreaterThanOrEqual(texelX, Float(region.originX) + 0.5 - 1e-4)
            XCTAssertLessThanOrEqual(texelX, Float(region.maxX) - 0.5 + 1e-4)
            XCTAssertGreaterThanOrEqual(texelY, Float(region.originY) + 0.5 - 1e-4)
            XCTAssertLessThanOrEqual(texelY, Float(region.maxY) - 0.5 + 1e-4)
        }
    }

    func testClampUVTreatsNonFiniteTapsAsTheLowerBound() async {
        let region = SubTextureRegion(textureWidth: 64, textureHeight: 64)
        let clamped = region.clampUV(.nan, .infinity)
        XCTAssertEqual(clamped.u, region.uvMinU)
        XCTAssertEqual(clamped.v, region.uvMinV)
    }

    func testSingleTexelRegionClampsEveryTapToThatTexel() async {
        let region = SubTextureRegion(
            originX: 3, originY: 3, width: 1, height: 1,
            textureWidth: 32, textureHeight: 32)
        XCTAssertEqual(region.uvMinU, region.uvMaxU, accuracy: 1e-7)
        XCTAssertEqual(region.uvMinV, region.uvMaxV, accuracy: 1e-7)
        let clamped = region.clampUV(1, 1)
        XCTAssertEqual(clamped.u * 32, 3.5, accuracy: 1e-4)
        XCTAssertEqual(clamped.v * 32, 3.5, accuracy: 1e-4)
    }

    func testReducedRegionKeepsTheTextureAndShrinksTheImage() async {
        let region = SubTextureRegion(
            originX: 0, originY: 0, width: 100, height: 60,
            textureWidth: 128, textureHeight: 128)
        let halved = region.reduced(byFactor: 2)
        XCTAssertEqual(halved.width, 50)
        XCTAssertEqual(halved.height, 30)
        XCTAssertEqual(halved.textureWidth, 128, "the scratch texture does not shrink with the image")
        XCTAssertEqual(halved.textureHeight, 128)
        XCTAssertEqual(region.reduced(byFactor: 1), region)
    }

    // MARK: - The halving rule both backends run

    /// The rule that makes a 2× halving an exact 2×2 box average on both
    /// backends, and the one place it is written down.
    ///
    /// The GPU halving pass is the blur shader at radius 0, and the shader
    /// maps a `[0,1]` viewport coordinate through `uv = input.uv *
    /// blurUVScale.xy`. Output texel `i` therefore taps the source at
    /// `(i + 0.5) · span / outputExtent` texels, and that is the boundary
    /// between texels `2i` and `2i+1` — where bilinear filtering returns
    /// their exact average — only if `span == 2 · outputExtent`.
    ///
    /// The engine used to hand the shader the **whole region** as the span.
    /// At an even extent that is the same number; at an odd one the taps
    /// drift by `(i + 0.5) / outputExtent` texels, reaching a full texel of
    /// offset at the far edge and pulling in the trailing column the CPU's
    /// block average drops — while both implementations documented each
    /// other as exact transcriptions.
    func testHalvingReadsASpanExactlyTwiceTheOutputExtent() async {
        for extent in 1...33 {
            let region = SubTextureRegion(
                originX: 0, originY: 0, width: extent, height: extent,
                textureWidth: 64, textureHeight: 64)
            let output = region.halved.width
            let span = region.halvingSource.width
            XCTAssertLessThanOrEqual(span, extent, "the halving may only read texels the region holds")

            for i in 0..<output {
                let tap = (Float(i) + 0.5) * Float(span) / Float(output)
                let expected = extent == 1 ? Float(0.5) : Float(2 * i + 1)
                XCTAssertEqual(
                    tap, expected, accuracy: 1e-4,
                    "extent \(extent), output texel \(i): the halving tap must land on the boundary "
                        + "between texels \(2 * i) and \(2 * i + 1), not at \(tap)")
            }
        }
    }

    /// The model above is only worth anything while the shader still maps
    /// viewport to UV that way.
    func testBlurShaderStillScalesTheViewportCoordinateByTheRegionUVScale() async {
        XCTAssertTrue(
            batchBackdropBlurShaderSource.contains("float2 uv = input.uv * blurUVScale.xy;"),
            "the halving pass's exactness is a property of this mapping; if it changes, "
                + "`SubTextureRegion.halvingSource` has to change with it")
    }

    /// And the CPU runs the same rule: the odd trailing column is dropped,
    /// not folded in, because the GPU's taps never reach it.
    func testCPUHalvingAveragesTheEvenSpanAndDropsTheOddColumn() async {
        // One row, five columns: 0, 64, 128, 192, 255 in every channel.
        let levels: [UInt8] = [0, 64, 128, 192, 255]
        var image = [UInt8]()
        for level in levels { image.append(contentsOf: [level, level, level, 255]) }

        let halved = PremultipliedImageBlur.halved(image, width: 5, height: 1)
        XCTAssertEqual(halved.width, 2)
        XCTAssertEqual(halved.height, 1)
        XCTAssertEqual(
            halved.pixels[0], 32,
            "output texel 0 is the average of source texels 0 and 1")
        XCTAssertEqual(
            halved.pixels[4], 160,
            "output texel 1 is the average of source texels 2 and 3; texel 4 is dropped, because the "
                + "GPU's UV mapping does not reach it either")
    }

    // MARK: - Render targets and passes

    func testRenderTargetDistinguishesClearFromLoad() async {
        let loading = RenderTargetDescriptor(kind: .presentation, width: 800, height: 600)
        XCTAssertTrue(loading.loadsExistingContents, "a nil clear colour means the pass composites over the target")
        XCTAssertFalse(loading.isEmpty)

        let clearing = RenderTargetDescriptor(kind: .offscreen, width: 64, height: 64, clearColor: .clear)
        XCTAssertFalse(clearing.loadsExistingContents)
    }

    func testRenderTargetSaturatesRatherThanTrappingOnAbsurdSizes() async {
        let collapsed = RenderTargetDescriptor(kind: .offscreen, width: -20, height: 40)
        XCTAssertTrue(collapsed.isEmpty)
        let huge = RenderTargetDescriptor(kind: .offscreen, width: 1_000_000, height: 1_000_000)
        XCTAssertEqual(huge.width, GPUISceneLimits.maxSurfaceDimension)
        XCTAssertEqual(huge.height, GPUISceneLimits.maxSurfaceDimension)
    }

    func testRenderPassIsEmptyWhenEitherTargetOrViewportIs() async {
        let target = RenderTargetDescriptor(kind: .offscreen, width: 128, height: 128, clearColor: .clear)
        let emptyViewport = RenderPassDescriptor(
            label: "group",
            target: target,
            viewport: SubTextureRegion(
                originX: 0, originY: 0, width: 0, height: 32,
                textureWidth: 128, textureHeight: 128))
        XCTAssertTrue(emptyViewport.isEmpty)

        let live = RenderPassDescriptor(
            label: "group",
            target: target,
            viewport: SubTextureRegion(textureWidth: 128, textureHeight: 128),
            inheritedOpacity: 0.5,
            isCacheable: true)
        XCTAssertFalse(live.isEmpty)
        XCTAssertEqual(live.inheritedOpacity, 0.5)
        XCTAssertTrue(live.isCacheable)
    }

    func testRenderPassClampsInheritedOpacity() async {
        let pass = RenderPassDescriptor(
            label: "group",
            target: RenderTargetDescriptor(kind: .offscreen, width: 8, height: 8),
            viewport: SubTextureRegion(textureWidth: 8, textureHeight: 8),
            inheritedOpacity: .nan)
        XCTAssertEqual(pass.inheritedOpacity, 0, "a non-finite inherited opacity must not reach a shader")
    }

    /// The vocabulary is only worth having if the three consumers actually
    /// speak it. The batch renderer states which surface it is drawing into
    /// once, and the blur engine reads that rather than a pair of loose
    /// surface ints — which is what makes a material blur correctly inside
    /// an offscreen snapshot rather than only against a swap-chain buffer.
    func testBatchRendererDescribesItsCurrentTargetAsARenderTarget() async throws {
        let renderer = D3D11BatchRenderer()
        defer { renderer.detach() }
        do {
            try renderer.attachOffscreen(size: IntSize(width: 128, height: 96), driver: .warpFirst)
        } catch {
            throw XCTSkip("No D3D11 device available: \(error)")
        }

        let target = renderer.currentRenderTargetDescriptor
        XCTAssertEqual(target.kind, .offscreen)
        XCTAssertEqual(target.width, 128)
        XCTAssertEqual(target.height, 96)
        XCTAssertTrue(
            target.loadsExistingContents,
            "a frame's draws composite over what the clear already put there; the clear is not a pass")
    }

    // MARK: - BlurPassPlan

    func testOrdinaryRadiiStayAtFullResolution() async {
        for radius in [1, 8, 22, 40, 64, BlurPassPlan.fullResolutionRadiusLimit] {
            let plan = BlurPassPlan(radius: radius, regionWidth: 400, regionHeight: 300)
            XCTAssertEqual(
                plan.downsampleFactor, 1,
                "radius \(radius) is inside the range every material and every pinned baseline uses; "
                    + "it must render exactly as it did before the downsample chain existed")
            XCTAssertEqual(plan.reducedRadius, radius)
            XCTAssertEqual(plan.halvingPassCount, 0)
            XCTAssertFalse(plan.isReduced)
        }
    }

    func testWideRadiiReduceInPowersOfTwo() async {
        let half = BlurPassPlan(radius: 160, regionWidth: 400, regionHeight: 300)
        XCTAssertEqual(half.downsampleFactor, 2)
        XCTAssertEqual(half.halvingPassCount, 1)
        XCTAssertEqual(half.reducedRadius, 80)
        XCTAssertEqual(half.reducedWidth, 200)
        XCTAssertEqual(half.reducedHeight, 150)

        let quarter = BlurPassPlan(radius: 256, regionWidth: 400, regionHeight: 300)
        XCTAssertEqual(quarter.downsampleFactor, 4)
        XCTAssertEqual(quarter.halvingPassCount, 2)
        XCTAssertEqual(quarter.reducedRadius, 64)
    }

    /// The invariant that keeps the two backends in step. If the plan ever
    /// consulted the region size, the CPU rasterizer's scan bounds and the
    /// GPU's `blurRegion` would only have to disagree by a pixel at a
    /// threshold for one backend to run a different number of halvings —
    /// a parity failure with no local cause.
    func testTheScheduleDependsOnTheRadiusAlone() async {
        for radius in [4, 100, 129, 200, 256] {
            let factors = Set(
                [(1, 1), (7, 3), (400, 300), (4096, 2160)].map {
                    BlurPassPlan(radius: radius, regionWidth: $0.0, regionHeight: $0.1).downsampleFactor
                })
            XCTAssertEqual(
                factors.count, 1,
                "radius \(radius) must produce one schedule for every region size")
            XCTAssertEqual(factors.first, BlurPassPlan.downsampleFactor(forRadius: radius))
        }
    }

    func testReducedRadiusNeverCollapsesABlurToAResample() async {
        // A tiny region with a huge radius still blurs; the reduction may
        // not round the radius away.
        let plan = BlurPassPlan(radius: 256, regionWidth: 3, regionHeight: 2)
        XCTAssertGreaterThanOrEqual(plan.reducedRadius, 1)
        XCTAssertGreaterThanOrEqual(plan.reducedWidth, 1)
        XCTAssertGreaterThanOrEqual(plan.reducedHeight, 1)
    }

    /// The cost model's whole point: a wide blur stops scaling cubically
    /// with display scale.
    func testWideBlursCostAnOrderOfMagnitudeLess() async {
        let plan = BlurPassPlan(radius: 256, regionWidth: 800, regionHeight: 600)
        XCTAssertGreaterThan(plan.fullResolutionSampleCost, 0)
        XCTAssertLessThan(
            plan.sampleCost, plan.fullResolutionSampleCost / 30,
            "two halvings must buy back at least 30x of a full-resolution 256-radius blur; "
                + "measured 2026-08: 64x minus the halving passes themselves")

        let unreduced = BlurPassPlan(radius: 40, regionWidth: 800, regionHeight: 600)
        XCTAssertEqual(
            unreduced.sampleCost, unreduced.fullResolutionSampleCost,
            "an unreduced plan must cost exactly what the full-resolution blur costs")
    }

    func testZeroRadiusPlanCostsNothing() async {
        let plan = BlurPassPlan(radius: 0, regionWidth: 100, regionHeight: 100)
        XCTAssertEqual(plan.sampleCost, 0)
        XCTAssertEqual(plan.fullResolutionSampleCost, 0)
        XCTAssertEqual(plan.reducedRadius, 0)
    }

    // MARK: - The reduced path is the same effect, not a different one

    /// Crossing the downsample threshold must not be visible. Radius 128
    /// runs at full resolution and radius 132 runs halved; four units of
    /// radius on a 128-pixel blur is a change no one can see, so if the
    /// reduced path were a materially different effect this is where it
    /// would show.
    func testCPUBlurIsContinuousAcrossTheDownsampleThreshold() async {
        let size = IntSize(width: 96, height: 96)
        let belowThreshold = GPUIRawSceneRasterizer.rasterize(
            Self.bandedBlurScene(radius: Float(BlurPassPlan.fullResolutionRadiusLimit), size: size), size: size)
        let aboveThreshold = GPUIRawSceneRasterizer.rasterize(
            Self.bandedBlurScene(radius: Float(BlurPassPlan.fullResolutionRadiusLimit + 4), size: size),
            size: size)

        let report = comparePixels(aboveThreshold, belowThreshold, tolerance: 6)
        XCTAssertGreaterThan(
            report.matchRatio, 0.99,
            "the reduced blur path must be the same effect as the full-resolution one; "
                + "max channel delta \(report.maxChannelDelta)")
    }

    /// And it still honours the radius: a reduced blur must not quietly
    /// become a fixed-width one.
    func testReducedBlurStillWidensWithRadius() async {
        let size = IntSize(width: 96, height: 96)
        let narrow = GPUIRawSceneRasterizer.rasterize(Self.bandedBlurScene(radius: 140, size: size), size: size)
        let wide = GPUIRawSceneRasterizer.rasterize(Self.bandedBlurScene(radius: 240, size: size), size: size)
        let report = comparePixels(wide, narrow, tolerance: 2)
        XCTAssertLessThan(
            report.matchRatio, 0.99,
            "radius 140 (halved) and radius 240 (quartered) must produce different pixels")
    }

    /// Cross-backend parity through the deepest reduction. The suite's own
    /// large-radius scene covers one halving; this covers two, where the
    /// CPU's successive 2×2 box averages and the GPU's successive bilinear
    /// taps have the most opportunity to part company.
    func testQuarterResolutionBlurAgreesAcrossBackends() async throws {
        let size = IntSize(width: 96, height: 96)
        let scene = Self.bandedBlurScene(radius: 220, size: size)
        let gpu = try WARPBatchRenderer.render(scene, size: size)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: size)

        let report = comparePixels(gpu, cpu, tolerance: 4)
        XCTAssertGreaterThan(
            report.matchRatio, 0.995,
            "a quarter-resolution blur must agree across backends within the suite's parity floor; "
                + "max channel delta \(report.maxChannelDelta), first failure \(String(describing: report.firstFailure))"
        )
    }

    /// The same parity bar over an **odd** region, which is where the two
    /// halvings had nothing keeping them together: 5 device pixels wide, so
    /// the first reduction has a trailing column to decide about and the
    /// second runs on the result. Vertical stripes underneath, so which
    /// column each backend averages is visible in the output rather than
    /// hidden by a uniform backdrop.
    func testOddWidthDownsampleAgreesAcrossBackends() async throws {
        let size = IntSize(width: 96, height: 96)
        let scene = Self.stripedNarrowBlurScene(radius: 220, size: size)
        let gpu = try WARPBatchRenderer.render(scene, size: size)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: size)

        let report = comparePixels(gpu, cpu, tolerance: 4)
        XCTAssertGreaterThan(
            report.matchRatio, 0.995,
            "an odd-extent downsample must agree across backends within the suite's parity floor; "
                + "max channel delta \(report.maxChannelDelta), first failure \(String(describing: report.firstFailure))"
        )
    }

    // MARK: - Residual: a Material inside an offscreen pass has no backdrop

    /// An offscreen subtree pass clears to transparent, and a Material is a
    /// *backdrop* effect: it samples what is already painted under it. Inside
    /// a `.drawingGroup()` that is nothing at all, so the material composites
    /// its tint over emptiness and the group's bitmap then lands over the
    /// wallpaper unblurred — the stripes under the panel stay razor sharp
    /// where they should have been smeared.
    ///
    /// The render-pass vocabulary did not change this and was wrongly
    /// documented as having done so. Fixing it means seeding the sub-scene
    /// with the already-painted backdrop under the group's frame (a read of
    /// the outer surface the painter has no access to at that point, because
    /// the outer scene is a *scene*, not pixels) or teaching the backend to
    /// run the group as a real GPU pass. Both are larger than a
    /// documentation fix, so this test states what happens today and skips
    /// the assertion that will hold when it is closed.
    func testMaterialInsideADrawingGroupBlursNothing() async throws {
        let size = IntSize(width: 100, height: 100)

        func scene(grouped: Bool) -> GPUIScene {
            var children: [ViewNode] = []
            for stripe in 0..<25 {
                children.append(
                    ViewNode(
                        frame: Rect(x: 0, y: Double(stripe) * 4, width: 100, height: 2),
                        backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1)))
            }
            let panel = ViewNode(
                frame: Rect(x: 20, y: 20, width: 60, height: 60),
                backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 0.35),
                blurRadius: 12)
            children.append(
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 100),
                    isCompositingGroup: grouped,
                    children: [panel]))
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: children)
            return ScenePainter.paint(
                root: root, clearColor: .black, surfaceSize: Size(width: 100, height: 100))
        }

        let inline = GPUIRawSceneRasterizer.rasterize(scene(grouped: false), size: size)
        let grouped = GPUIRawSceneRasterizer.rasterize(scene(grouped: true), size: size)

        // Inside the panel, away from its edges.
        let inlineContrast = Self.maxNeighbourDelta(inline, rows: 40..<60, columns: 40..<60)
        let groupedContrast = Self.maxNeighbourDelta(grouped, rows: 40..<60, columns: 40..<60)
        XCTAssertLessThan(
            inlineContrast, 20,
            "painted inline, the material blurs the stripes under it into a smooth field")
        XCTAssertGreaterThan(
            groupedContrast, 100,
            "inside a compositing group the same material has no backdrop to blur, so the stripes "
                + "under it stay sharp — the divergence this test records")

        throw XCTSkip(
            "Residual (documented in docs/GPURenderingPipeline.md, 'a Material inside an offscreen pass "
                + "has no backdrop'): a compositing-group sub-scene clears to transparent, so a Material "
                + "inside `.drawingGroup()` composites its tint over nothing and blurs nothing. Closing it "
                + "needs the sub-scene seeded with the already-painted backdrop, or the group run as a "
                + "real GPU pass.")
    }

    /// Largest channel step between neighbouring pixels in a window of the
    /// surface — high for a stripe pattern, low once a Gaussian has run.
    private static func maxNeighbourDelta(
        _ surface: BitmapSurface, rows: Range<Int>, columns: Range<Int>
    ) -> Int {
        var worst = 0
        let stride = Int(surface.bytesPerRow)
        for y in rows where y >= 1 && y < Int(surface.height) {
            for x in columns where x >= 1 && x < Int(surface.width) {
                let offset = y * stride + x * 4
                guard offset + 3 < surface.pixels.count else { continue }
                for neighbour in [offset - 4, offset - stride] where neighbour >= 0 {
                    for channel in 0..<3 {
                        worst = max(
                            worst,
                            abs(Int(surface.pixels[offset + channel]) - Int(surface.pixels[neighbour + channel])))
                    }
                }
            }
        }
        return worst
    }

    // MARK: - Residual: rotated clipping

    /// WS-19 lowered rotation for quad *geometry*; a rotated `.clipped()`
    /// container still clips to the axis-aligned bounding box of its rotated
    /// frame, which at 45° is `√2` too large on each axis.
    ///
    /// The fix is a render pass whose result is composited through a rotated
    /// transform. The offscreen half already exists — a compositing group
    /// rasterizes a subtree into a bitmap and places it as an
    /// `ImagePrimitive` — but `ImagePrimitive` carries no rotation, so the
    /// composite would clip as an AABB again, one layer down. Closing it is
    /// a scene-ABI change (rotation on `ImagePrimitive`, matching HLSL,
    /// matching the CPU sampler), which is larger than this workstream.
    ///
    /// This test records the residual: the first assertion is what the code
    /// does today, and the skip names what it should do instead.
    func testRotatedClipStillNarrowsToAnAxisAlignedBox() async throws {
        let frame = Rect(x: 0, y: 0, width: 100, height: 40)
        let rotated = frame.applying(transform: Transform2D(rotation: .pi / 4))

        // Today: the clip narrows to this box.
        XCTAssertGreaterThan(
            rotated.size.height, frame.size.height * 1.5,
            "a 45° rotation of a wide rect has a much taller bounding box; that box is what the clip "
                + "narrows to today")

        throw XCTSkip(
            "Residual (documented in docs/GPURenderingPipeline.md, 'a rotated clip is still an AABB'): "
                + "RuntimeClipShape narrows to the AABB of the rotated frame, so a rotated clipsToBounds "
                + "container lets children draw in the corners the rotated rect does not cover. Routing "
                + "the subtree through an offscreen pass does not fix it until ImagePrimitive can be "
                + "composited rotated.")
    }

    /// Two flat bands under a translucent material panel — the same shape
    /// the large-radius parity scene uses, for the same reason: a wide
    /// kernel averages a gradient into uniform grey, which any two
    /// implementations agree on for the wrong reason.
    /// Vertical stripes with a 5-pixel-wide material strip over them: an odd
    /// blur region whose source columns are all different, so a halving that
    /// samples the wrong ones shows up in the composite.
    private static func stripedNarrowBlurScene(radius: Float, size: IntSize) -> GPUIScene {
        var scene = GPUIScene(clearColor: Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        for column in 0..<Int(size.width) {
            let level = Float(column % 5) / 4
            scene.addQuad(
                QuadPrimitive(
                    x: Float(column), y: 0, width: 1, height: Float(size.height),
                    startR: level, startG: 1 - level, startB: 0.5, startA: 1,
                    endR: level, endG: 1 - level, endB: 0.5, endA: 1))
        }
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: 5, height: Float(size.height) - 16,
                startR: 1, startG: 1, startB: 1, startA: 0.35,
                endR: 1, endG: 1, endB: 1, endA: 0.35,
                blurRadius: radius))
        scene.finish()
        return scene
    }

    private static func bandedBlurScene(radius: Float, size: IntSize) -> GPUIScene {
        var scene = GPUIScene(clearColor: Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        let half = Float(size.height) / 2
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: Float(size.width), height: half,
                startR: 0.95, startG: 0.30, startB: 0.15, startA: 1,
                endR: 0.95, endG: 0.30, endB: 0.15, endA: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: half, width: Float(size.width), height: half,
                startR: 0.10, startG: 0.35, startB: 0.85, startA: 1,
                endR: 0.10, endG: 0.35, endB: 0.85, endA: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: Float(size.width) - 16, height: Float(size.height) - 16,
                startR: 1, startG: 1, startB: 1, startA: 0.35,
                endR: 1, endG: 1, endB: 1, endA: 0.35,
                blurRadius: radius))
        scene.finish()
        return scene
    }
}
