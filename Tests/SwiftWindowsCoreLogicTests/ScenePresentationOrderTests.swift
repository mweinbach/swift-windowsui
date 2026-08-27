import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI

/// `GPUIScene.presentationOrder()` is the stack's only draw-order
/// authority, and this suite is what makes that a fact rather than a
/// comment.
///
/// Before it there were three orderings: the CPU rasterizer walked the
/// flat `paintRecords` log (global insertion order, `layerIndex`
/// discarded), the D3D11 plan builder walked `layers[*].paintOperations`
/// (layer-major), and a bounds-tree order was computed for every primitive
/// of every frame and read by nothing outside tests. The first two agreed
/// only because `ScenePainter` never pushed a second layer — and because
/// *every* screenshot, gallery baseline and parity render came through the
/// CPU walk, no visual gate could ever have shown the divergence.
@MainActor
final class ScenePresentationOrderTests: XCTestCase {

    // MARK: - Helpers

    /// The presentation order flattened to one primitive per entry, which
    /// is the granularity at which the two backends must agree (run
    /// boundaries are a batching detail, not an order).
    private func presentationSequence(_ scene: GPUIScene) -> [String] {
        var sequence: [String] = []
        for run in scene.presentationOrder() {
            for index in run.range {
                sequence.append("\(run.layerIndex)/\(run.kind)/\(index)")
            }
        }
        return sequence
    }

    /// The same flattening applied to a D3D11 `RenderPlan`, so the two
    /// lists are directly comparable.
    private func planSequence(_ plan: D3D11BatchRenderer.RenderPlan) -> [String] {
        var sequence: [String] = []
        for step in plan.steps {
            let layerIndex: Int
            let kind: GPUIPaintPrimitiveKind
            let range: Range<Int>
            switch step {
            case .shadows(let layer, let stepRange):
                (layerIndex, kind, range) = (layer, .shadow, stepRange)
            case .quads(let layer, let stepRange):
                (layerIndex, kind, range) = (layer, .quad, stepRange)
            case .glyphs(let layer, let stepRange, _):
                (layerIndex, kind, range) = (layer, .glyph, stepRange)
            case .pixelGlyphs(let layer, let stepRange, _):
                (layerIndex, kind, range) = (layer, .pixelGlyph, stepRange)
            case .images(let layer, let stepRange, _):
                (layerIndex, kind, range) = (layer, .image, stepRange)
            case .paths(let layer, let stepRange):
                (layerIndex, kind, range) = (layer, .path, stepRange)
            }
            for index in range {
                sequence.append("\(layerIndex)/\(kind)/\(index)")
            }
        }
        return sequence
    }

    /// Atlases and image textures reported as already resident, so the
    /// plan builder gets past resource resolution and onto the ordering
    /// this suite is actually about.
    private static let residentResources = D3D11BatchRenderer.CachedResources(
        hasGlyphAtlas: true,
        hasPixelGlyphAtlas: true,
        boundImageTextureIDs: [0, 1, 2]
    )

    /// A deterministic pseudo-random generator — the scenes have to be
    /// reproducible for a failure to be debuggable.
    private struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A scene of `count` primitives spread over `layerCount` layers and
    /// all six families, with layer indices chosen at random so the
    /// insertion order and the layer-major order genuinely differ.
    private func randomScene(seed: UInt64, count: Int, layerCount: Int) -> GPUIScene {
        var generator = SplitMix64(seed: seed)
        var scene = GPUIScene()
        for layer in 0..<layerCount {
            scene.ensureLayer(layer)
        }

        for step in 0..<count {
            let layerIndex = Int.random(in: 0..<layerCount, using: &generator)
            let x = Float(Int.random(in: 0..<200, using: &generator))
            let y = Float(Int.random(in: 0..<200, using: &generator))
            switch Int.random(in: 0..<6, using: &generator) {
            case 0:
                scene.addShadow(ShadowPrimitive(x: x, y: y, width: 24, height: 24), toLayer: layerIndex)
            case 1:
                scene.addQuad(QuadPrimitive(x: x, y: y, width: 24, height: 24), toLayer: layerIndex)
            case 2:
                scene.addGlyph(
                    GlyphPrimitive(screenX: x, screenY: y, screenW: 10, screenH: 12), toLayer: layerIndex)
            case 3:
                scene.addPixelGlyph(
                    GlyphPrimitive(screenX: x, screenY: y, screenW: 8, screenH: 8), toLayer: layerIndex)
            case 4:
                scene.addImage(
                    ImagePrimitive(
                        screenX: x, screenY: y, screenW: 32, screenH: 32,
                        textureID: Int32(step % 3)),
                    toLayer: layerIndex)
            default:
                scene.addPath(
                    PathPrimitive(
                        elements: [
                            .moveTo(Point(x: Double(x), y: Double(y))),
                            .lineTo(Point(x: Double(x) + 24, y: Double(y) + 24)),
                        ],
                        bounds: Rect(x: Double(x), y: Double(y), width: 24, height: 24),
                        strokeColor: .white,
                        lineWidth: 1
                    ), toLayer: layerIndex)
            }
        }

        scene.finish()
        return scene
    }

    // MARK: - The two backends read one order

    func testPseudoRandomMultiLayerScenesPlanExactlyThePresentationOrder() async throws {
        for seed in UInt64(1)...12 {
            let scene = randomScene(seed: seed, count: 90, layerCount: 3)
            XCTAssertTrue(scene.validate().isEmpty, "seed \(seed) produced a structurally invalid scene")

            let plan = try D3D11BatchRenderer.makeRenderPlan(
                for: scene, cachedResources: Self.residentResources)

            XCTAssertEqual(
                planSequence(plan), presentationSequence(scene),
                "seed \(seed): the GPU plan and the presentation order must be the same sequence")
        }
    }

    func testPresentationOrderIsLayerMajorEvenWhenInsertionInterleavesLayers() async throws {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10), toLayer: 1)
        scene.addQuad(QuadPrimitive(x: 20, y: 0, width: 10, height: 10), toLayer: 0)
        scene.addQuad(QuadPrimitive(x: 40, y: 0, width: 10, height: 10), toLayer: 1)
        scene.addQuad(QuadPrimitive(x: 60, y: 0, width: 10, height: 10), toLayer: 0)
        scene.finish()

        XCTAssertEqual(
            presentationSequence(scene),
            ["0/quad/0", "0/quad/1", "1/quad/0", "1/quad/1"])
    }

    /// The regression that could not be seen: an overlay layer added
    /// *before* the content it covers. Walking `paintRecords` drew the
    /// overlay first and the content on top of it; the layer-major rule
    /// puts the overlay where the layer index says it goes.
    func testHigherLayerPaintsOverLowerLayerRegardlessOfInsertionOrder() async throws {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: 48, height: 48,
                startR: 0, startG: 0, startB: 1, startA: 1,
                endR: 0, endG: 0, endB: 1, endA: 1
            ), toLayer: 1)
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: 48, height: 48,
                startR: 1, startG: 0, startB: 0, startA: 1,
                endR: 1, endG: 0, endB: 0, endA: 1
            ), toLayer: 0)
        scene.finish()

        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 64, height: 64))
        let offset = (32 * Int(bitmap.bytesPerRow)) + 32 * 4
        // BGRA: the layer-1 blue quad wins.
        XCTAssertEqual(Int(bitmap.pixels[offset]), 255, "blue channel")
        XCTAssertEqual(Int(bitmap.pixels[offset + 2]), 0, "red channel")
    }

    func testInterleavedLayerSceneMatchesTheGPUOnWARP() async throws {
        let size = IntSize(width: 64, height: 64)
        var scene = GPUIScene(clearColor: Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: 32, height: 32,
                startR: 0.15, startG: 0.25, startB: 0.90, startA: 1,
                endR: 0.15, endG: 0.25, endB: 0.90, endA: 1
            ), toLayer: 1)
        scene.addQuad(
            QuadPrimitive(
                x: 16, y: 16, width: 32, height: 32,
                startR: 0.90, startG: 0.30, startB: 0.20, startA: 1,
                endR: 0.90, endG: 0.30, endB: 0.20, endA: 1
            ), toLayer: 0)
        scene.finish()

        let gpu = try WARPBatchRenderer.render(scene, size: size)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: size)
        let report = comparePixels(gpu, cpu, tolerance: 4)
        var detail = String(
            format: "%.4f of pixels within ±4 (max channel delta %d)",
            report.matchRatio, report.maxChannelDelta)
        if let failure = report.firstFailure {
            detail += "; first mismatch at (\(failure.x), \(failure.y))"
        }
        XCTAssertGreaterThanOrEqual(
            report.matchRatio, 0.995,
            "interleaved-layer scene diverged across backends: \(detail)")
    }

    // MARK: - One out-of-range predicate, two answers

    func testOutOfRangePaintOperationIsSkippedOnCPUAndRefusedByThePlan() async throws {
        var scene = GPUIScene()
        scene.installHandBuiltLayers([
            GPUILayer(
                quads: [QuadPrimitive(x: 0, y: 0, width: 10, height: 10)],
                paintOperations: [
                    GPUIPaintOperation(kind: .quad, startIndex: 0, count: 1),
                    GPUIPaintOperation(kind: .quad, startIndex: 1, count: 4),
                ])
        ])

        // The CPU walk drops the bad run rather than trapping on the range.
        XCTAssertEqual(presentationSequence(scene), ["0/quad/0"])
        // The GPU refuses the whole scene, so the defect is reported, not
        // silently rendered short.
        XCTAssertThrowsError(try D3D11BatchRenderer.makeRenderPlan(for: scene))
        XCTAssertFalse(scene.validate().isEmpty)
    }

    // MARK: - Replay log integrity

    func testReplayRangeBeyondTheSourceSceneIsRejectedNotTrapped() async throws {
        var source = GPUIScene()
        source.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10))

        var target = GPUIScene()
        // The shape a stale `drawingGroup` sub-scene range has: indices
        // measured against a scene that no longer exists.
        let result = target.replay(40..<60, from: source)

        XCTAssertEqual(result, .invalidRange(40..<60, recordCount: source.paintRecordCount))
        XCTAssertEqual(target.paintRecordCount, 0, "a rejected replay must add nothing")
    }

    /// The same in-bounds-but-wrong replay class, reached from the other
    /// side: `installHandBuiltLayers` swaps the primitives out from under a
    /// log that still names their indices. Every record stays in range, so
    /// `.invalidRange` never fires and the replay reproduces whatever moved
    /// into those slots. The log does not survive the swap.
    func testInstallingHandBuiltLayersDropsTheStaleReplayLog() async throws {
        var source = GPUIScene()
        source.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10))
        source.addQuad(QuadPrimitive(x: 20, y: 0, width: 10, height: 10))
        let recordedRange = 0..<source.paintRecordCount
        XCTAssertEqual(recordedRange.count, 2)

        source.installHandBuiltLayers([
            GPUILayer(quads: [QuadPrimitive(x: 400, y: 400, width: 1, height: 1)])
        ])
        XCTAssertEqual(source.paintRecordCount, 0, "a hand-built layer set has no valid replay log")

        var target = GPUIScene()
        XCTAssertEqual(target.replay(recordedRange, from: source), .invalidRange(recordedRange, recordCount: 0))
        XCTAssertTrue(target.layers[0].quads.isEmpty, "and a rejected replay must add nothing")
    }

    /// `installHandBuiltLayer(_:at:)` drops the log for the same reason; an
    /// index that addresses no layer changes nothing at all, log included.
    func testInstallingOneHandBuiltLayerDropsTheLogOnlyWhenItReplacesSomething() async throws {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10))
        scene.addQuad(QuadPrimitive(x: 20, y: 0, width: 10, height: 10))
        XCTAssertEqual(scene.paintRecordCount, 2)

        scene.installHandBuiltLayer(GPUILayer(quads: [QuadPrimitive(x: 5, y: 5, width: 1, height: 1)]), at: 7)
        XCTAssertEqual(scene.paintRecordCount, 2, "a no-op install must not discard a valid log")

        scene.installHandBuiltLayer(GPUILayer(quads: [QuadPrimitive(x: 5, y: 5, width: 1, height: 1)]), at: 0)
        XCTAssertEqual(scene.paintRecordCount, 0)
    }

    /// One painted frame, threading snapshot ownership the way the runtime does.
    private func paintFrame(_ root: ViewNode, previous: ScenePaintSnapshot?, surfaceSize: Size) -> ScenePaintSnapshot {
        var deferredDraws: [DeferredDrawState] = []
        var replayCount = 0
        var deferredReplayCount = 0
        return ScenePainter.paintSnapshot(
            root: root,
            clearColor: .black,
            surfaceSize: surfaceSize,
            textSystem: WindowTextSystem(),
            previousSnapshot: previous,
            deferredDraws: &deferredDraws,
            replayCount: &replayCount,
            deferredReplayCount: &deferredReplayCount
        )
    }

    /// A cached paint range describes the scene it was measured against, and
    /// a subtree inside a compositing group does not paint into that scene at
    /// all — its primitives go into a sub-scene that is rasterized into a
    /// bitmap and discarded. Descendants were told to skip cache *writes*
    /// while in there, which left the range they were carrying from before
    /// the group was applied in place: still keyed the same, still in bounds
    /// of the next real scene, so removing the group replayed whichever
    /// primitives had since moved into those indices. Here that is the
    /// group's own composited image, in place of the leaf's quad —
    /// `.invalidRange` never sees it, because the range is perfectly valid.
    func testUnwrappingADrawingGroupDoesNotReplayItsSubtreesStaleRange() async throws {
        let surfaceSize = Size(width: 100, height: 100)

        func makeTree() -> (root: ViewNode, group: ViewNode) {
            let leaf = ViewNode(
                frame: Rect(x: 0, y: 0, width: 20, height: 20),
                backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
            let group = ViewNode(frame: Rect(x: 0, y: 40, width: 40, height: 40), children: [leaf])
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                children: [
                    ViewNode(
                        frame: Rect(x: 0, y: 0, width: 20, height: 20),
                        backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)),
                    ViewNode(
                        frame: Rect(x: 0, y: 20, width: 20, height: 20),
                        backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)),
                    group,
                ])
            return (root, group)
        }

        let (root, group) = makeTree()

        // Frame 1, inline: three quads, and the leaf caches the third.
        let inlineScene = paintFrame(root, previous: nil, surfaceSize: surfaceSize)
        XCTAssertEqual(inlineScene.scene.layers[0].quads.count, 3)

        // Frame 2, grouped: the leaf's quad moves into the discarded
        // sub-scene and an image takes its place at record index 2.
        group.isCompositingGroup = true
        let groupedScene = paintFrame(root, previous: inlineScene, surfaceSize: surfaceSize)
        XCTAssertEqual(groupedScene.scene.layers[0].quads.count, 2)
        XCTAssertEqual(groupedScene.scene.layers[0].images.count, 1)

        // Frame 3, inline again.
        group.isCompositingGroup = false
        let unwrappedScene = paintFrame(root, previous: groupedScene, surfaceSize: surfaceSize)

        let (freshRoot, _) = makeTree()
        let freshScene = paintFrame(freshRoot, previous: nil, surfaceSize: surfaceSize)

        XCTAssertTrue(
            unwrappedScene.scene.layers[0].images.isEmpty,
            "the leaf replayed the group's composited image out of a range that no longer describes it")
        XCTAssertEqual(unwrappedScene.scene.layers[0].quads, freshScene.scene.layers[0].quads)
        XCTAssertEqual(unwrappedScene.scene.paintRecords, freshScene.scene.paintRecords)
    }

    /// A frame that replays all of its text rasterizes no glyph, and the
    /// painter used to read that as "this frame does not use the atlas" and
    /// ship none. D3D11 covered for it by resolving `.cached`; the CPU
    /// rasterizer — every screenshot, gallery baseline and macOS parity
    /// render — got `nil` and drew no text at all, for a frame the user sees
    /// text in.
    func testFullyReplayedTextFrameStillShipsTheAtlasItDrawsFrom() async throws {
        let surfaceSize = Size(width: 200, height: 60)
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 60),
            text: "REPLAY",
            textStyle: PixelTextStyle(
                color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
        )

        let firstScene = paintFrame(root, previous: nil, surfaceSize: surfaceSize)
        let glyphCount = firstScene.scene.layers[0].glyphs.count + firstScene.scene.layers[0].pixelGlyphs.count
        XCTAssertGreaterThan(glyphCount, 0, "this test only means something if the frame draws text")

        let replayedScene = paintFrame(root, previous: firstScene, surfaceSize: surfaceSize)
        XCTAssertEqual(
            replayedScene.scene.layers[0].glyphs, firstScene.scene.layers[0].glyphs,
            "the replayed frame must carry the same glyph quads")
        XCTAssertEqual(replayedScene.scene.layers[0].pixelGlyphs, firstScene.scene.layers[0].pixelGlyphs)
        XCTAssertEqual(replayedScene.scene.usesGlyphs, replayedScene.scene.glyphAtlas != nil)
        XCTAssertEqual(replayedScene.scene.usesPixelGlyphs, replayedScene.scene.pixelGlyphAtlas != nil)

        // The claim that matters is pixels, not payload presence.
        let size = IntSize(width: 200, height: 60)
        let firstPixels = GPUIRawSceneRasterizer.rasterize(firstScene.scene, size: size).pixels
        let replayedPixels = GPUIRawSceneRasterizer.rasterize(replayedScene.scene, size: size).pixels
        XCTAssertTrue(firstPixels.contains { $0 != 0 }, "the first frame must actually draw something")
        XCTAssertEqual(
            replayedPixels, firstPixels,
            "the CPU rasterizer must draw the replayed frame exactly like the frame it replays")
    }

    /// The painter's answer to a rejection: repaint, do not cache the
    /// emptiness. Both call sites used to discard the result with `_ =`
    /// and then write the (empty) replay range back into the cache, which
    /// made a single stale range a permanently blank overlay.
    func testPainterRepaintsInsteadOfCachingARejectedReplay() async throws {
        ScenePainter.resetRejectedReplayCountForTesting()

        let root = ViewNode()
        root.resolvedFrame = Rect(x: 0, y: 0, width: 100, height: 100)

        // A previous scene far too short for the cached range below — the
        // shape a range measured against a discarded sub-scene has.
        var previousScene = GPUIScene(clearColor: .black)
        previousScene.addQuad(QuadPrimitive(x: 0, y: 0, width: 4, height: 4))
        previousScene.finish()
        let previousSnapshot = ScenePaintSnapshot(scene: previousScene, identity: PaintSnapshotIdentity())

        var deferredDraws = [
            DeferredDrawState(
                priority: 0,
                parentDispatchIndex: 0,
                contentMask: nil,
                payload: .scrollIndicator(
                    ScrollIndicatorDeferredDrawPayload(
                        dispatchIndex: 0,
                        track: ScrollIndicatorTrack(
                            axis: .vertical,
                            origin: 0,
                            travel: 40,
                            indicatorRect: Rect(x: 90, y: 10, width: 6, height: 30)
                        ),
                        color: Color(red: 1, green: 1, blue: 1, alpha: 1),
                        cornerRadius: 3
                    )),
                cachedFrameCommandRange: nil,
                cachedScenePaintRange: 900..<920,
                cachedSceneSnapshotIdentity: previousSnapshot.identity
            )
        ]

        var replayCount = 0
        var deferredReplayCount = 0
        let scene = ScenePainter.paintSnapshot(
            root: root,
            clearColor: .black,
            surfaceSize: Size(width: 100, height: 100),
            textSystem: WindowTextSystem(),
            previousSnapshot: previousSnapshot,
            deferredDraws: &deferredDraws,
            replayCount: &replayCount,
            deferredReplayCount: &deferredReplayCount
        ).scene

        XCTAssertGreaterThan(ScenePainter.rejectedReplayCount, 0, "the rejection must be reported")
        XCTAssertEqual(deferredReplayCount, 0, "a rejected replay is not a replay")
        XCTAssertEqual(scene.layers[0].quads.count, 1, "the overlay must be repainted, not left blank")
        XCTAssertNotNil(deferredDraws[0].cachedScenePaintRange)
        XCTAssertEqual(
            deferredDraws[0].cachedScenePaintRange, 0..<1,
            "the cached range must describe the scene that was just painted")

        ScenePainter.resetRejectedReplayCountForTesting()
    }

    func testReplayReconstructsPrimitivesFromFamilyArraysNotRecordCopies() async throws {
        var source = GPUIScene(clearColor: .white)
        source.addQuad(QuadPrimitive(x: 4, y: 6, width: 20, height: 12, cornerRadius: 3))
        source.addGlyph(GlyphPrimitive(screenX: 2, screenY: 3, screenW: 8, screenH: 10))
        source.addShadow(ShadowPrimitive(x: 1, y: 1, width: 30, height: 30, blurRadius: 5))

        var replayed = GPUIScene(clearColor: .white)
        XCTAssertEqual(replayed.replay(0..<source.paintRecordCount, from: source), .success)

        XCTAssertEqual(replayed.layers[0].quads, source.layers[0].quads)
        XCTAssertEqual(replayed.layers[0].glyphs, source.layers[0].glyphs)
        XCTAssertEqual(replayed.layers[0].shadows, source.layers[0].shadows)
        XCTAssertEqual(replayed.paintRecords, source.paintRecords)
    }

    // MARK: - Cost of the ordering machinery

    /// A paint record is a reference now, not a second copy of the
    /// primitive. It used to carry a `GPUIScenePrimitive` payload whose
    /// stride was set by the largest family (`QuadPrimitive`, 144 B), so a
    /// 20,000-glyph screen paid ~3 MB for the log alone — and again while
    /// `previousScene` was retained for replay.
    func testPaintRecordStrideStaysAReference() async throws {
        XCTAssertLessThanOrEqual(
            MemoryLayout<GPUIScenePaintRecord>.stride, 48,
            "paintRecords must stay a reference log, not a second copy of every primitive")
        XCTAssertLessThan(
            MemoryLayout<GPUIScenePaintRecord>.stride, QuadPrimitive.byteSize,
            "a record must be cheaper than the primitive it points at")
    }

    /// An *unsealed* single-family scene, so a caller can time insertion
    /// separately from `finish()`.
    private static func makeQuadScene(count: Int) -> GPUIScene {
        var scene = GPUIScene()
        for index in 0..<count {
            scene.addQuad(
                QuadPrimitive(x: Float(index % 500), y: Float(index / 500), width: 2, height: 2))
        }
        return scene
    }

    private static func makeGlyphScene(count: Int) -> GPUIScene {
        var scene = GPUIScene()
        for index in 0..<count {
            scene.addGlyph(
                GlyphPrimitive(
                    screenX: Float(index % 500), screenY: Float(index / 500), screenW: 4, screenH: 6))
        }
        return scene
    }

    func testLargeSingleFamilyScenesCollapseToOneRunAndOneStep() async throws {
        var quadScene = Self.makeQuadScene(count: 5_000)
        quadScene.finish()

        XCTAssertEqual(quadScene.layers[0].quads.count, 5_000)
        XCTAssertEqual(quadScene.layers[0].paintOperations.count, 1)
        XCTAssertEqual(Array(quadScene.presentationOrder()).count, 1)
        let quadPlan = try D3D11BatchRenderer.makeRenderPlan(
            for: quadScene, cachedResources: Self.residentResources)
        XCTAssertEqual(quadPlan.steps, [.quads(layerIndex: 0, range: 0..<5_000)])

        var glyphScene = Self.makeGlyphScene(count: 10_000)
        glyphScene.finish()

        XCTAssertEqual(glyphScene.layers[0].glyphs.count, 10_000)
        XCTAssertEqual(glyphScene.layers[0].paintOperations.count, 1)
        XCTAssertEqual(Array(glyphScene.presentationOrder()).count, 1)
        let glyphPlan = try D3D11BatchRenderer.makeRenderPlan(
            for: glyphScene, cachedResources: Self.residentResources)
        XCTAssertEqual(
            glyphPlan.steps, [.glyphs(layerIndex: 0, range: 0..<10_000, atlasSource: .cached)])
    }

    /// Seconds spent inserting primitives, and seconds spent sealing and
    /// planning them, accumulated over `rounds` independently built scenes.
    ///
    /// Accumulating rather than taking a single sample is deliberate: one
    /// round of either phase can land inside a system tick, and the sum of
    /// many rounds converges on the real total whatever the clock's
    /// granularity is.
    private func measureSealAndPlanCost(
        rounds: Int,
        build: () -> GPUIScene
    ) throws -> (insertion: TimeInterval, sealAndPlan: TimeInterval) {
        var insertion: TimeInterval = 0
        var sealAndPlan: TimeInterval = 0
        for _ in 0..<rounds {
            let buildStart = Date()
            var scene = build()
            let sealStart = Date()
            scene.finish()
            _ = try D3D11BatchRenderer.makeRenderPlan(
                for: scene, cachedResources: Self.residentResources)
            let planEnd = Date()
            insertion += sealStart.timeIntervalSince(buildStart)
            sealAndPlan += planEnd.timeIntervalSince(sealStart)
        }
        return (insertion, sealAndPlan)
    }

    /// The ceiling `finish()` + `makeRenderPlan` must stay under: an eighth
    /// of what inserting the same primitives cost, floored at 5 ms so a
    /// clock too coarse to see the baseline cannot fail the test outright.
    private func sealAndPlanBudget(insertion: TimeInterval) -> TimeInterval {
        max(insertion / 8, 0.005)
    }

    /// WS-07's cost claim, made falsifiable.
    ///
    /// `GPUILayer.finish()` used to sort every family into a bounds-tree
    /// draw order and remap `paintOperations` back onto it — ~12 heap
    /// allocations per primitive per frame — to produce an ordering only
    /// `orderedBatches()` read. Today it re-coalesces an already-canonical
    /// run list and `makeRenderPlan` walks runs rather than primitives, so
    /// both are O(runs); the scenes above collapse to one run each. The
    /// structural half of that is asserted directly, but a per-primitive
    /// pass could be reintroduced *inside* `finish()` without moving a
    /// single run count, so the cost needs its own budget.
    ///
    /// The budget is stated relative to the insertion loop that built the
    /// same scene rather than as an absolute wall-clock ceiling. One `add*`
    /// call is the cheapest per-primitive work a scene can do — an array
    /// append plus a paint record — so measuring against it turns "not
    /// per-primitive" into a number, and it self-calibrates: a slow or
    /// contended runner moves both sides together instead of tripping a
    /// fixed millisecond figure.
    ///
    /// Measured 2026-08 on this tree: sealing and planning costs 0.1–0.3 %
    /// of insertion. Injecting a *single* heap allocation per primitive
    /// into the sealed phase takes it to 20–27 %, so the eighth-of-insertion
    /// ceiling rejects even the mildest per-primitive regression, and the
    /// retired sort — a dozen allocations per primitive plus a sort per
    /// family — misses it by two orders of magnitude. The remaining ~50×
    /// headroom on the passing side is what absorbs a scheduler stall
    /// landing inside the measured window.
    func testSealingAndPlanningIsNotPerPrimitiveWork() async throws {
        let quads = try measureSealAndPlanCost(rounds: 80) {
            Self.makeQuadScene(count: 5_000)
        }
        XCTAssertLessThan(
            quads.sealAndPlan, sealAndPlanBudget(insertion: quads.insertion),
            """
            sealing and planning 80 x 5,000 quads cost \(quads.sealAndPlan) s against an \
            insertion cost of \(quads.insertion) s; finish() and makeRenderPlan are O(runs), \
            so something in them went per-primitive
            """)

        let glyphs = try measureSealAndPlanCost(rounds: 40) {
            Self.makeGlyphScene(count: 10_000)
        }
        XCTAssertLessThan(
            glyphs.sealAndPlan, sealAndPlanBudget(insertion: glyphs.insertion),
            """
            sealing and planning 40 x 10,000 glyphs cost \(glyphs.sealAndPlan) s against an \
            insertion cost of \(glyphs.insertion) s; finish() and makeRenderPlan are O(runs), \
            so something in them went per-primitive
            """)
    }
}
