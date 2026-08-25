import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics

/// Walks a ViewNode tree and produces a GPUIScene with typed primitive arrays,
/// mirroring the logic of ViewNode.appendCommands() but targeting the GPUI
/// instanced-rendering pipeline instead of the RenderCommand enum list.
@MainActor
public enum ScenePainter {

    /// Emits `path` through the tessellator's mixed-output API. Each
    /// axis-aligned segment becomes a `QuadPrimitive` on the GPU; any
    /// remaining diagonal/curved fragments are bundled into a residual
    /// `PathPrimitive` that goes to CPU rasterization. A path that
    /// can't be tessellated at all stays as a single CPU path.
    /// Updates `scene.paintMetrics` so apps and tests can observe the
    /// GPU promotion rate at the frame boundary.
    ///
    /// This is the single lowering point for path geometry, so it is also
    /// where logical points become device pixels: callers build paths in
    /// the same logical space as every other primitive and `emit` applies
    /// `displayScale` exactly once, before tessellation, so the promoted
    /// quads and the residual CPU path land in the same space the backends
    /// already assume.
    ///
    /// It is also the single place a *rotation* reaches path geometry. Paths
    /// never cross the GPU as typed primitives, so there is no
    /// `rotationRadians` field to hand a shader the way the quad, glyph,
    /// image and shadow families have one; the honest lowering is to turn the
    /// path's own elements, which both the coverage rasterizer and the D3D11
    /// path-texture cache then simply cover. `PathPrimitive.shapeHash`
    /// digests the element stream, so a turned path re-keys those caches by
    /// construction rather than by anyone remembering to add the angle.
    internal static func emit(
        path logicalPath: PathPrimitive,
        into scene: inout GPUIScene,
        layerIndex: Int,
        displayScale: Double,
        placement: PaintPlacement? = nil
    ) {
        // A dash pattern can resolve to no geometry at all — every run of a
        // short outline landing in an "off" span — and an empty `Path` is a
        // no-op the same way. Neither should cost a paint operation.
        guard !logicalPath.elements.isEmpty else { return }
        // Turn before scaling: the rotation is about the node's centre in
        // *logical* points, and a uniform scale commutes with a rotation
        // about a correspondingly scaled pivot, so either order is exact —
        // this one keeps the pivot in the space the placement states it in.
        let placed: PathPrimitive
        if let placement, placement.isRotated {
            placed = logicalPath.rotated(
                by: placement.rotation,
                about: Point(x: placement.frame.midX, y: placement.frame.midY))
        } else {
            placed = logicalPath
        }
        let path = placed.scaled(by: displayScale)
        if path.fillGradient != nil || path.strokeGradient != nil {
            if path.fillGradient != nil,
                path.strokeGradient == nil,
                couldBeSingleQuadGradientFill(path)
            {
                // Ask the existing geometry tessellator whether the complete
                // fill is exactly one rectangle or rounded rectangle. An
                // opaque probe also admits gradients whose first stop is
                // transparent; authored colors and opacity are restored by
                // the bounded directional-gradient lowering afterward.
                var geometry = path
                geometry.fillGradient = nil
                geometry.fillColor = .white
                if let mixed = PathToQuadTessellator.tessellateMixed(geometry),
                    mixed.residualPath == nil,
                    mixed.quads.count == 1,
                    let quads = path.gradientFillQuads(covering: mixed.quads[0])
                {
                    for quad in quads {
                        scene.addQuad(quad, toLayer: layerIndex)
                    }
                    scene.paintMetrics.pathsPromotedToGPU += 1
                    scene.paintMetrics.quadInstancesFromPromotedPaths += quads.count
                    return
                }
            }

            // Strokes, combined paint and complex fill topology still need
            // one continuous coverage buffer to preserve joins, fill rules,
            // translucent overlap and the authored gradient coordinate frame.
            scene.addPath(path, toLayer: layerIndex)
            scene.paintMetrics.pathsRasterizedOnCPU += 1
            return
        }
        guard let mixed = PathToQuadTessellator.tessellateMixed(path) else {
            scene.addPath(path, toLayer: layerIndex)
            scene.paintMetrics.pathsRasterizedOnCPU += 1
            return
        }

        for quad in mixed.quads {
            scene.addQuad(quad, toLayer: layerIndex)
        }
        if let residualPath = mixed.residualPath {
            scene.addPath(residualPath, toLayer: layerIndex)
        }

        // Count the source path once on each side it ended up on; both
        // counters can increment in the mixed case where some segments
        // hit GPU and others fall back. quadInstances only counts the
        // GPU portion.
        if !mixed.quads.isEmpty {
            scene.paintMetrics.pathsPromotedToGPU += 1
            scene.paintMetrics.quadInstancesFromPromotedPaths += mixed.quads.count
        }
        if mixed.residualPath != nil {
            scene.paintMetrics.pathsRasterizedOnCPU += 1
        }
    }

    /// Reject general curves and polygons before probing the solid-path
    /// tessellator. Without this cheap topology check, a large gradient
    /// triangle could allocate thousands of scanline quads merely to discover
    /// that its result cannot take the single-footprint gradient lane.
    private static func couldBeSingleQuadGradientFill(_ path: PathPrimitive) -> Bool {
        guard (4...6).contains(path.elements.count) || (9...10).contains(path.elements.count) else {
            return false
        }

        var moveCount = 0
        var vertexCount = 0
        var arcCount = 0

        for element in path.elements {
            switch element {
            case .moveTo:
                moveCount += 1
                vertexCount += 1
            case .lineTo:
                vertexCount += 1
            case .arc:
                arcCount += 1
            case .close:
                break
            case .quadraticCurveTo, .cubicCurveTo:
                return false
            }
        }

        guard moveCount == 1 else { return false }
        return arcCount == 0
            ? (vertexCount == 4 || vertexCount == 5)
            : (arcCount == 4 && vertexCount == 5)
    }

    public static func paint(root: ViewNode, clearColor: Color, surfaceSize: Size, displayScale: Double = 1.0)
        -> GPUIScene
    {
        var replayCount = 0
        var deferredReplayCount = 0
        var deferredDraws: [DeferredDrawState] = []
        return paint(
            root: root,
            clearColor: clearColor,
            surfaceSize: surfaceSize,
            displayScale: displayScale,
            textSystem: WindowTextSystem(),
            previousScene: nil,
            deferredDraws: &deferredDraws,
            replayCount: &replayCount,
            deferredReplayCount: &deferredReplayCount
        )
    }

    static func paint(
        root: ViewNode,
        clearColor: Color,
        surfaceSize: Size,
        displayScale: Double = 1.0,
        textSystem: WindowTextSystem,
        previousScene: GPUIScene?,
        deferredDraws: inout [DeferredDrawState],
        replayCount: inout Int,
        deferredReplayCount: inout Int,
        overlays: [ViewNode] = []
    ) -> GPUIScene {
        let fullClip = RuntimeClipShape(
            rect: Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height), space: .painted)
        let deviceSurfaceSize = surfaceSize.scaled(by: max(displayScale, 1.0))
        let originalDeferredDraws = deferredDraws

        // One LRU tick per *rendered frame*, not per attempt: the loop below
        // repaints the same frame, and advancing the clock again would age
        // glyphs the frame is still using out from under it.
        NativeGlyphAtlas.shared.beginFrame()
        defer { NativeGlyphAtlas.shared.setSuspended(false) }

        // A frame that follows one which reused reclaimed atlas space starts
        // with replay already off: the previous scene's glyph quads may address
        // cells that were handed to someone else, and finding that out halfway
        // through this pass would cost the pass. Off from the start, it costs
        // nothing but the replay.
        var bypassReplayAfterAtlasRecovery = NativeGlyphAtlas.shared.replayIsUnsafeThisFrame

        for attempt in 0..<glyphAtlasPaintAttempts {
            // The atlas recovers from exhaustion by recycling its shelves, which
            // invalidates every UV this pass already emitted. On the last attempt
            // we stop asking it for glyphs at all so the pass cannot exhaust: the
            // scene degrades to bitmap text instead of shipping — and caching —
            // quads that address someone else's atlas cells.
            let isFinalAttempt = attempt == glyphAtlasPaintAttempts - 1
            NativeGlyphAtlas.shared.setSuspended(isFinalAttempt)
            NativeGlyphAtlas.shared.beginPass()
            let atlasGenerationAtStart = NativeGlyphAtlas.shared.atlasGeneration
            let atlasRecycleGenerationAtStart = NativeGlyphAtlas.shared.atlasRecycleGeneration
            // Counters describe the attempt that ships, not the ones discarded
            // along the way - except the recovery count, which is the reason
            // there was more than one attempt.
            TextRenderDiagnosticsCounters.beginPass(preservingAtlasRecoveries: attempt > 0)

            var scene = GPUIScene(clearColor: clearColor)
            // The list outlives the frame (it carries the replay ranges);
            // "an earlier pass already drew this" does not. Every attempt
            // starts with every deferred entry undrawn.
            var attemptDeferredDraws = originalDeferredDraws.map { entry -> DeferredDrawState in
                var entry = entry
                entry.isDrawnInline = false
                return entry
            }
            var attemptReplayCount = 0
            var attemptDeferredReplayCount = 0
            var usedNativeGlyphs = false
            var usedPixelGlyphs = false
            let replaySource = bypassReplayAfterAtlasRecovery ? nil : previousScene

            paintNode(
                root,
                into: &scene,
                deferredDraws: &attemptDeferredDraws,
                parentOrigin: .zero,
                inheritedClip: fullClip,
                layerIndex: 0,
                surfaceSize: deviceSurfaceSize,
                displayScale: max(displayScale, 1.0),
                textSystem: textSystem,
                previousScene: replaySource,
                usedNativeGlyphs: &usedNativeGlyphs,
                usedPixelGlyphs: &usedPixelGlyphs,
                replayCount: &attemptReplayCount
            )
            for overlay in overlays {
                paintNode(
                    overlay,
                    into: &scene,
                    deferredDraws: &attemptDeferredDraws,
                    parentOrigin: .zero,
                    inheritedClip: fullClip,
                    layerIndex: 0,
                    surfaceSize: deviceSurfaceSize,
                    displayScale: max(displayScale, 1.0),
                    textSystem: textSystem,
                    previousScene: replaySource,
                    usedNativeGlyphs: &usedNativeGlyphs,
                    usedPixelGlyphs: &usedPixelGlyphs,
                    replayCount: &attemptReplayCount
                )
            }
            appendDeferredDraws(
                &attemptDeferredDraws,
                into: &scene,
                previousScene: replaySource,
                surfaceSize: deviceSurfaceSize,
                displayScale: max(displayScale, 1.0),
                textSystem: textSystem,
                usedNativeGlyphs: &usedNativeGlyphs,
                usedPixelGlyphs: &usedPixelGlyphs,
                replayCount: &attemptDeferredReplayCount
            )

            if usedNativeGlyphs, NativeGlyphAtlas.shared.atlasGeneration != atlasGenerationAtStart {
                // The atlas handed out space it had handed out before. Which
                // holders that invalidates depends on *how*:
                //
                // - a recycle (`clear()`) moved every shelf, so every UV this
                //   pass captured is wrong;
                // - a replayed paint record carries last frame's UVs forward
                //   verbatim, and this pass never re-looked them up;
                // - freeing a cell this pass had already drawn from is the one
                //   way reuse can alias one of *this* pass's own emissions.
                //
                // Any of those and the pass is unshippable: rebuild it without
                // replay so every glyph is re-addressed against the atlas as it
                // stands now. None of them, and reuse only invalidated cells
                // nothing in this scene is looking at — ship it, and let the
                // next frame start with replay off instead.
                let recycled = NativeGlyphAtlas.shared.atlasRecycleGeneration != atlasRecycleGenerationAtStart
                let replayedStaleRanges = attemptReplayCount + attemptDeferredReplayCount > 0
                NativeGlyphAtlas.shared.noteReclaimedSpaceReused()
                if !isFinalAttempt,
                    recycled || replayedStaleRanges || NativeGlyphAtlas.shared.didFreeCellUsedThisFrame
                {
                    bypassReplayAfterAtlasRecovery = true
                    TextRenderDiagnosticsCounters.atlasRecoveries += 1
                    continue
                }
            }

            if usedNativeGlyphs {
                scene.glyphAtlas = NativeGlyphAtlas.shared.snapshotIfUsedInCurrentFrame()
            }
            if usedPixelGlyphs {
                scene.pixelGlyphAtlas = pixelGlyphAtlasSnapshot()
            }
            attachCachedGlyphAtlases(to: &scene)

            deferredDraws = attemptDeferredDraws
            replayCount = attemptReplayCount
            deferredReplayCount = attemptDeferredReplayCount
            scene.paintMetrics.textDiagnostics = TextRenderDiagnosticsCounters.snapshot()
            scene.finish()
            return scene
        }

        // Unreachable by construction: the final attempt runs with the atlas
        // suspended, so it emits no native glyph, cannot exhaust, and always
        // takes the return above. Kept as a typed backstop rather than a trap —
        // a blank frame is recoverable, a runtime crash is not.
        deferredDraws = originalDeferredDraws
        replayCount = 0
        deferredReplayCount = 0
        var scene = GPUIScene(clearColor: clearColor)
        scene.finish()
        return scene
    }

    // MARK: - Private

    /// Paint attempts per frame before the glyph atlas is given up on.
    ///
    /// Attempt 0 paints normally, attempt 1 repaints without scene replay after
    /// an atlas recovery, and attempt 2 paints with the atlas suspended so the
    /// frame is guaranteed to be free of recycled UVs.
    private static let glyphAtlasPaintAttempts = 3

    /// Cached paint ranges the scene refused to replay. Diagnostic only —
    /// every rejection is answered by repainting the subtree — but a
    /// non-zero count means some node is carrying a range from a scene it
    /// never painted into, which is a cache-bookkeeping bug worth finding.
    internal private(set) static var rejectedReplayCount = 0
    private static var hasReportedRejectedReplay = false

    private static func reportRejectedReplay() {
        rejectedReplayCount += 1
        guard !hasReportedRejectedReplay else { return }
        hasReportedRejectedReplay = true
        FileHandle.standardError.write(
            Data(
                """
                [SwiftWindowsUI] scene replay rejected for a cached paint \
                range; the subtree is being repainted instead of replayed.

                """.utf8
            )
        )
    }

    /// Test seam: lets a test observe rejections from a known baseline.
    internal static func resetRejectedReplayCountForTesting() {
        rejectedReplayCount = 0
        hasReportedRejectedReplay = false
    }

    private struct PaintTraversalContext {
        let node: ViewNode
        let parentOrigin: Point
        let inheritedClip: RuntimeClipShape?
        let layerIndex: Int
        let primitiveOpacity: Float
        let inheritedColorEffects: [RetainedColorEffect]
        // No inherited blur. `blurRadius` is the node's OWN backdrop effect
        // (Material) and `contentBlurRadius` is resolved once, after the
        // subtree is painted, so neither is pushed down the traversal.
        let inheritedBlendMode: BlendMode
        let inheritedTransform: Transform2D
        let isInsideDrawingGroup: Bool
        let skipCacheUpdates: Bool
        /// True only for the node an isolation pass re-enters, so that the
        /// pass paints the subtree instead of recursing into itself. It is
        /// deliberately *not* inherited: a nested `.blur()` inside a blurred
        /// subtree is its own isolation, exactly as it is in SwiftUI.
        let suppressesContentBlurIsolation: Bool
    }

    private struct PaintNodeFinishState {
        let node: ViewNode
        let startPaintRecord: Int
        let cacheKey: ViewPaintCacheKey
        let hasChildren: Bool
        let borderColor: Color
        let paintFrame: Rect
        /// WS-19. The rotation lowered out of the node's effective transform.
        /// The ring is laid out in `placement.frame` and each segment is
        /// turned about the node's centre, exactly like the pre-children
        /// border.
        let placement: PaintPlacement
        let effectiveClip: RuntimeClipShape?
        /// The ancestors' clip. The border overlay is part of the node's own
        /// decoration, so — like the background and border quads — it is
        /// rounded by its own corner radii and must not be re-rounded by its
        /// own clip; only what ancestors imposed applies.
        let inheritedClip: RuntimeClipShape?
        let opacity: Float
        let colorEffects: [RetainedColorEffect]
        let effectiveBlendMode: BlendMode
        let layerIndex: Int
        let skipCacheUpdates: Bool
    }

    private enum PaintTraversalStep {
        case enter(PaintTraversalContext)
        case finish(PaintNodeFinishState)
    }

    private static func paintNode(
        _ node: ViewNode,
        into scene: inout GPUIScene,
        deferredDraws: inout [DeferredDrawState],
        parentOrigin: Point,
        inheritedClip: RuntimeClipShape?,
        layerIndex: Int,
        surfaceSize: Size,
        displayScale: Double,
        textSystem: WindowTextSystem,
        previousScene: GPUIScene?,
        primitiveOpacity: Float = 1,
        inheritedColorEffects: [RetainedColorEffect] = [],
        inheritedBlendMode: BlendMode = .normal,
        usedNativeGlyphs: inout Bool,
        usedPixelGlyphs: inout Bool,
        replayCount: inout Int,
        inheritedTransform: Transform2D = .identity,
        isInsideDrawingGroup: Bool = false,
        skipCacheUpdates: Bool = false,
        suppressesContentBlurIsolation: Bool = false
    ) {
        var traversal: [PaintTraversalStep] = [
            .enter(
                PaintTraversalContext(
                    node: node,
                    parentOrigin: parentOrigin,
                    inheritedClip: inheritedClip,
                    layerIndex: layerIndex,
                    primitiveOpacity: primitiveOpacity,
                    inheritedColorEffects: inheritedColorEffects,
                    inheritedBlendMode: inheritedBlendMode,
                    inheritedTransform: inheritedTransform,
                    isInsideDrawingGroup: isInsideDrawingGroup,
                    skipCacheUpdates: skipCacheUpdates,
                    suppressesContentBlurIsolation: suppressesContentBlurIsolation
                )
            )
        ]

        while let traversalStep = traversal.popLast() {
            let context: PaintTraversalContext
            switch traversalStep {
            case .finish(let state):
                finishPaintNode(
                    state,
                    into: &scene,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale
                )
                continue

            case .enter(let entryContext):
                context = entryContext
            }

            // Counted on entry, before any of the reasons this node might not
            // paint: entering it is the work replay avoids, and a node that
            // enters and then culls has already cost the traversal.
            scene.paintMetrics.nodesVisited += 1

            let node = context.node
            let parentOrigin = context.parentOrigin
            let inheritedClip = context.inheritedClip
            let layerIndex = context.layerIndex
            let primitiveOpacity = context.primitiveOpacity
            let inheritedColorEffects = context.inheritedColorEffects
            let inheritedBlendMode = context.inheritedBlendMode
            let inheritedTransform = context.inheritedTransform
            let isInsideDrawingGroup = context.isInsideDrawingGroup
            let skipCacheUpdates = context.skipCacheUpdates

            let startPaintRecord = scene.paintRecordCount

            // "Did this node's last visit paint via the isolation pass?" —
            // cleared here so that every way of *not* isolating (a buffer that
            // could not be sized, a culled or hidden subtree, a zero radius)
            // leaves it false and the deferred phase draws the headers itself.
            // Only the composite below sets it. The suppressed re-entry is the
            // isolation pass painting this very node into its own buffer, and
            // must not clear the answer it is in the middle of producing.
            if node.contentBlurRadius > 0, !context.suppressesContentBlurIsolation {
                node.lastPaintedViaContentBlurIsolation = false
            }

            // Inside a compositing group nothing this node paints reaches the
            // scene the caches are measured against, so the cache it is
            // carrying from before the group existed has to go. Skipping the
            // *write* is not enough: a range measured against a real earlier
            // frame stays in bounds of the next one, so removing the group
            // replayed whatever primitives happen to live at those indices
            // now. `.invalidRange` only catches the out-of-bounds half of
            // that. Clearing on entry also covers the reverse toggle, since
            // the frame a group appears on walks its whole subtree.
            if skipCacheUpdates {
                node.cachedSceneKey = nil
                node.cachedScenePaintRange = nil
            }

            guard !node.isHidden else {
                if !skipCacheUpdates {
                    node.cachedSceneKey = nil
                    node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
                }
                node.markSubtreeRendered()
                continue
            }

            let effectiveBlendMode: BlendMode = node.blendMode == .normal ? inheritedBlendMode : node.blendMode
            // Needed before the border is emitted: a container's border is a
            // ring drawn after children, so the pre-children fill has to know
            // whether it would be redrawn.
            let hasChildren = !node.children.isEmpty

            // The node's frame in its parent's local coordinate space.
            let nodeLocalFrame = Rect(
                x: parentOrigin.x + node.resolvedFrame.origin.x,
                y: parentOrigin.y + node.resolvedFrame.origin.y,
                width: node.resolvedFrame.size.width,
                height: node.resolvedFrame.size.height
            )

            // Map the local frame into screen space using the inherited ancestor
            // transform, then apply the node's own transform centered around the
            // screen-space center so that scaleEffect/rotationEffect affect both
            // the node and all descendants consistently.
            let effectiveTransform: Transform2D
            if node.transform.isIdentity {
                effectiveTransform = inheritedTransform
            } else {
                let nodeScreenFrame = nodeLocalFrame.applying(transform: inheritedTransform)
                let center = Point(x: nodeScreenFrame.midX, y: nodeScreenFrame.midY)
                let centeredTransform = Transform2D.translation(x: -center.x, y: -center.y)
                    .concatenating(node.transform)
                    .concatenating(.translation(x: center.x, y: center.y))
                // WS-19. Ancestors first, then this node. `concatenating` is
                // self-first (`a.concatenating(b)` maps a point through `a`
                // then through `b`), and `centeredTransform` is built around
                // the node's *screen-space* centre — it is a screen-space
                // operator, so it has to be applied after the map that
                // produced that screen space. The other order composed
                // node-before-ancestors, which left the node's own frame and
                // the frames its descendants inherited in different spaces:
                // an ancestor `.offset(100, 0)` under a `.scaleEffect(2)`
                // child moved the child by 100 and its grandchildren by 200.
                // `concatenating` round-trips through the decomposition,
                // which is not a fixed point for shears, so an identity
                // ancestor short-circuits rather than paying a lossy compose.
                effectiveTransform =
                    inheritedTransform.isIdentity
                    ? centeredTransform : inheritedTransform.concatenating(centeredTransform)
            }
            // WS-19. `boundingBox` is what every predicate and every family
            // without a rotation field uses (it is the value the whole painter
            // used before rotation was lowered); `frame` plus the placement's
            // rotation is what the quad families carry. The two are the same
            // rect for any node that is not rotated.
            let placement = PaintPlacement.lowering(nodeLocalFrame, through: effectiveTransform)
            // L7-FONTS. A hairline rule is pinned to the device pixel grid
            // before anything else reads its frame — see
            // `devicePixelSnappedRule` for why a rule that is not pinned
            // renders at half weight at 125% and 150%.
            let pinsRule = snapsRuleToDevicePixels(node, placement: placement)
            let paintFrame =
                pinsRule
                ? devicePixelSnappedRule(placement.boundingBox, displayScale: displayScale)
                : placement.boundingBox
            let quadFrame =
                pinsRule
                ? devicePixelSnappedRule(placement.frame, displayScale: displayScale)
                : placement.frame

            // A degenerate frame paints none of the node's own decoration, but
            // it is not a reason to drop the subtree: macOS SwiftUI does not
            // clip at a frame boundary, so `.frame(height: 0)` without
            // `.clipped()` overflows and the children still render. Own
            // decoration is gated on this flag; children are visited unless the
            // cull below prunes them (a `clipsToBounds` node collapses its clip
            // to nothing, which prunes them for the right reason).
            let hasPaintableExtent = paintFrame.size.width > 0 && paintFrame.size.height > 0

            // Occlusion culling against the inherited clip, for every node —
            // a degenerate frame parked outside the clip has to prune its
            // subtree like any other. The footprint is the node's frame unioned
            // with the decoration that reaches outside it — a shadow or
            // focus/outline ring on a card scrolled one pixel past the clip edge
            // is still visible, and culling on `paintFrame` alone made it pop.
            // The offset is turned by the node's rotation, exactly as the
            // emission below turns it (`placement.turning`). A shadow's
            // offset is authored in the shadowed view's own space, so a card
            // turned 90° with `.shadow(y: 40)` casts 40pt to its *side*; a
            // footprint that still assumed 40pt down could miss the clip the
            // halo actually falls in and prune a visibly-shadowed subtree.
            var ownShadowRect: Rect?
            if node.shadowColor.alpha > 0 {
                let placedOffset = placement.turning(node.shadowOffset)
                ownShadowRect =
                    paintFrame
                    .outset(by: max(0, node.shadowSpread))
                    .offsetBy(dx: placedOffset.x, dy: placedOffset.y)
            }
            let ownOutlineRect: Rect? =
                node.outlineColor.alpha > 0 && node.outlineWidth > 0
                ? paintFrame.outset(by: node.outlineWidth)
                : nil
            let cullBounds = union(paintFrame, ownShadowRect, ownOutlineRect)
            if !inheritedClip.allowsSubtreeTraversal(bounds: cullBounds) {
                if !skipCacheUpdates {
                    node.cachedSceneKey = nil
                    node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
                }
                node.markSubtreeRendered()
                continue
            }

            // One narrowing rule, shared with prepaint, hit testing and the
            // frame path (`RuntimeClipShape.intersecting`): the rejection rect
            // is intersected, the rounding stays anchored to the frame of the
            // node that established it.
            var effectiveClip = inheritedClip
            if node.clipsToBounds {
                guard
                    let clipped = inheritedClip.narrowed(
                        to: paintFrame,
                        shape: quadFrame,
                        radii: node.cornerRadii,
                        uniformRadius: node.cornerRadius,
                        rotation: placement.rotation,
                        space: .painted
                    )
                else {
                    if !skipCacheUpdates {
                        node.cachedSceneKey = nil
                        node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
                    }
                    node.markSubtreeRendered()
                    continue
                }
                effectiveClip = clipped
            }
            let effectiveClipRect = effectiveClip?.rect

            // Clip rounding for the node's OWN quads (border, background,
            // overlay): a view's own decoration is shaped by its own corner
            // radii and is not re-rounded by its own clip — only children
            // are. The clip RECT still applies (own text/content is clipped
            // to the node's bounds); only the corner rounding reverts to
            // what ancestors imposed.
            let ownClipCornerRadius: (Rect) -> Double = { quadRect in
                inheritedClip.ancestorCornerRadius(forQuadRect: quadRect, rejectingOutside: effectiveClipRect)
            }

            // GPUI/Zed carries opacity as an inherited paint scalar.
            let opacity = primitiveOpacity * Float(node.opacity)
            let colorEffects = inheritedColorEffects + node.colorEffects
            // The node's own backdrop blur (Material). A subtree-wide
            // `.blur()` is `contentBlurRadius` and is emitted as one pass in
            // `finishPaintNode`, after everything below has painted.
            let blurRadius = node.blurRadius
            let blurOpaque = node.blurOpaque
            let resolvedHoverEffect = node.resolvedActiveHoverEffect
            let cacheKey = ViewPaintCacheKey(
                bounds: paintFrame,
                transform: effectiveTransform.matrix,
                contentMask: effectiveClip,
                opacity: opacity,
                blurRadius: blurRadius,
                blurOpaque: blurOpaque,
                contentBlurRadius: node.contentBlurRadius,
                contentBlurOpaque: node.contentBlurOpaque,
                blendMode: effectiveBlendMode,
                isCompositingGroup: node.isCompositingGroup,
                drawingGroup: node.drawingGroup,
                colorEffects: colorEffects,
                visualEffects: node.visualEffects,
                viewMask: node.viewMask,
                displayScale: displayScale,
                isHovered: node.isHovered,
                hoverEffect: resolvedHoverEffect,
                isFocused: node.isFocused,
                isFocusEffectDisabled: node.isFocusEffectDisabled
            )
            guard opacity > 0 else {
                if !skipCacheUpdates {
                    node.cachedSceneKey = cacheKey
                    node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
                }
                node.markSubtreeRendered()
                continue
            }

            // A node `.blur(radius:)` isolates never replays its outer range.
            // The isolation branch below is the only caller of
            // `claimDeferredDescendants`, and a replayed range carries the
            // composited bitmap forward while leaving the node's deferred
            // descendants unclaimed — the deferred phase would then put a
            // second, sharp copy of every pinned header on top of the bitmap
            // that already contains it. The bitmap cache still carries the
            // savings: a clean subtree re-composites its cached bitmap rather
            // than re-rasterizing or re-blurring anything.
            let refusesReplayForContentBlur =
                node.contentBlurRadius > 0 && !context.suppressesContentBlurIsolation

            if !skipCacheUpdates,
                !refusesReplayForContentBlur,
                let previousScene,
                !node.hasDirtySubtree,
                node.cachedSceneKey == cacheKey,
                let cachedScenePaintRange = node.cachedScenePaintRange
            {
                // Replay validates before it appends anything, so a
                // rejected range leaves the scene untouched and the node
                // falls through to a full repaint below. Discarding the
                // result — which is what this call site did — turned a
                // rejection into a permanently blank subtree: the empty
                // replay range was written straight back into the cache.
                switch scene.replay(cachedScenePaintRange, from: previousScene) {
                case .success:
                    let delta = startPaintRecord - cachedScenePaintRange.lowerBound
                    node.shiftCachedSceneRangesRecursively(by: delta)
                    node.cachedSceneKey = cacheKey
                    node.cachedScenePaintRange = startPaintRecord..<scene.paintRecordCount
                    node.markSubtreeRendered()
                    replayCount += 1
                    continue
                case .invalidRange, .unbalanced:
                    reportRejectedReplay()
                    node.cachedSceneKey = nil
                    node.cachedScenePaintRange = nil
                }
            }

            // `.blur(radius:)` blurs *this subtree*, and nothing else. The
            // subtree renders into its own offscreen buffer, is blurred
            // there, and is composited back — so a sibling one pixel outside
            // the frame is untouched, while the blur still fades out past the
            // frame rather than ending at a hard edge.
            //
            // This runs before any of the node's own decoration is emitted,
            // because the node's background and border are part of what a
            // `.blur()` on it blurs.
            if node.contentBlurRadius > 0, !context.suppressesContentBlurIsolation, hasPaintableExtent,
                appendIsolatedContentBlur(
                    ContentBlurIsolation(
                        node: node,
                        parentOrigin: parentOrigin,
                        inheritedTransform: inheritedTransform,
                        inheritedColorEffects: inheritedColorEffects,
                        inheritedBlendMode: inheritedBlendMode,
                        paintFrame: paintFrame,
                        effectiveClip: effectiveClip,
                        cacheKey: cacheKey,
                        primitiveOpacity: primitiveOpacity,
                        layerIndex: layerIndex,
                        isInsideDrawingGroup: isInsideDrawingGroup,
                        skipCacheUpdates: skipCacheUpdates
                    ),
                    into: &scene,
                    deferredDraws: &deferredDraws,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    textSystem: textSystem,
                    usedNativeGlyphs: &usedNativeGlyphs,
                    usedPixelGlyphs: &usedPixelGlyphs
                )
            {
                // The subtree's deferred descendants are inside the bitmap this
                // just composited. Recorded on the node because the frame that
                // *replays* this range from a clean ancestor never comes back
                // here, and the deferred phase still has to know.
                node.lastPaintedViaContentBlurIsolation = true
                if !skipCacheUpdates {
                    node.cachedSceneKey = cacheKey
                    node.cachedScenePaintRange = startPaintRecord..<scene.paintRecordCount
                }
                node.markSubtreeRendered()
                continue
            }

            if hasPaintableExtent,
                let hoverShadow = node.hoverEffectShadowCommand(
                    for: paintFrame,
                    inheritedClip: inheritedClip?.rect,
                    opacity: opacity
                )
            {
                scene.addQuad(
                    placement.rotating(
                        quad(for: hoverShadow, surfaceSize: surfaceSize, displayScale: displayScale),
                        displayScale: displayScale),
                    toLayer: layerIndex
                )
            }

            // Shadow
            let effectiveShadowColor = node.shadowColor.multipliedAlpha(by: opacity)
            if hasPaintableExtent, effectiveShadowColor.alpha > 0, let shadowRect = ownShadowRect {
                if clipAllowsDrawing(clip: inheritedClip, rect: shadowRect) {
                    // R-ROT. The halo is laid out in the node's *unrotated*
                    // paint space and turned about the node's centre, the same
                    // two steps the border ring and the background fill take.
                    // Emitting `paintFrame`'s outset instead haloed the
                    // bounding box: at 45° a √2-too-large square around a
                    // diamond, with the corners glowing where the card has
                    // none. `placement.rotation` rides along on the primitive
                    // so both backends turn the soft envelope with it.
                    //
                    // The rect emitted here is the *unoffset* halo. Both
                    // backends draw a shadow at `(x + offsetX, y + offsetY)`
                    // — the rasterizer in `drawShadow`, the shader in
                    // `ShadowPipeline` — so pre-offsetting the origin *and*
                    // filling in the offset field moved every halo twice: a
                    // `.shadow(y: 14)` pill cast its slab 28 pt down, detached
                    // from the control, and disagreed with the frame path,
                    // which offsets once. The offset is turned with the node
                    // (it is authored in the shadowed view's own space) and
                    // handed to the primitive whole.
                    let quadShadowRect = quadFrame.outset(by: max(0, node.shadowSpread))
                    let scaledShadowRect = placement.placingDevice(
                        scaleRect(quadShadowRect, by: displayScale), displayScale: displayScale)
                    let placedShadowOffset = placement.turning(node.shadowOffset)
                    let shadowClip = clipRectFloats(inheritedClip, surfaceSize: surfaceSize, displayScale: displayScale)
                    scene.addShadow(
                        ShadowPrimitive(
                            x: Float(scaledShadowRect.origin.x),
                            y: Float(scaledShadowRect.origin.y),
                            width: Float(scaledShadowRect.size.width),
                            height: Float(scaledShadowRect.size.height),
                            cornerRadius: Float(
                                ((node.cornerRadii?.maxRadius ?? node.cornerRadius) + max(0, node.shadowSpread))
                                    * displayScale),
                            colorR: effectiveShadowColor.red,
                            colorG: effectiveShadowColor.green,
                            colorB: effectiveShadowColor.blue,
                            colorA: effectiveShadowColor.alpha,
                            blurRadius: Float(node.shadowSpread * displayScale),
                            offsetX: Float(placedShadowOffset.x * displayScale),
                            offsetY: Float(placedShadowOffset.y * displayScale),
                            clipX: shadowClip.0,
                            clipY: shadowClip.1,
                            clipWidth: shadowClip.2,
                            clipHeight: shadowClip.3,
                            clipCornerRadius: Float(
                                inheritedClip.resolvedCornerRadius(forQuadRect: shadowRect) * displayScale),
                            rotationRadians: Float(placement.rotation)
                        ), toLayer: layerIndex)
                }
            }

            if hasPaintableExtent {
                for focusEffect in node.focusEffectCommands(
                    for: paintFrame,
                    inheritedClip: inheritedClip?.rect,
                    opacity: opacity
                ) {
                    scene.addQuad(
                        placement.rotating(
                            quad(for: focusEffect, surfaceSize: surfaceSize, displayScale: displayScale),
                            displayScale: displayScale),
                        toLayer: layerIndex
                    )
                }
            }

            // Outline — the keyboard focus ring, drawn OUTSIDE the border.
            //
            // As a ring, not a slab. This used to fill the whole outset rect
            // and lean on the border and background painted over it to hide
            // everything but the 4pt margin. That holds only while those are
            // opaque, and the macOS palettes are not: a bordered control's
            // fill is `white(0.15)`-style translucency over the window, so the
            // accent slab showed straight through the body and a focused push
            // button turned solid blue — a `.borderedProminent` button, which
            // is a different control. `BorderSegments.solidSegments` is the
            // same ring walk the container border already uses when it has to
            // paint after its children; it covers the margin and nothing else,
            // so no fill above it can be seen through.
            if hasPaintableExtent, let outlineRect = ownOutlineRect {
                if clipAllowsDrawing(clip: inheritedClip, rect: outlineRect) {
                    appendFocusRing(
                        node: node,
                        quadFrame: quadFrame,
                        placement: placement,
                        opacity: opacity,
                        inheritedClip: inheritedClip,
                        colorEffects: colorEffects,
                        layerIndex: layerIndex,
                        into: &scene,
                        surfaceSize: surfaceSize,
                        displayScale: displayScale
                    )
                }
            }

            // Border (full rect drawn under the fill area; for leaf nodes the
            // inset fill leaves the border ring visible).
            //
            // A container re-draws the same border as a ring *after* its
            // children (`finishPaintNode`), so emitting it here as well blended
            // a translucent border twice: `.border(Color.white.opacity(0.10))`
            // landed at 0.19 on a container and 0.10 on a leaf. The ring covers
            // exactly the pixels this fill would leave visible, so containers
            // emit the border once, after children.
            let borderColor = node.borderGradient?.startColor ?? node.borderColor
            if hasPaintableExtent, !hasChildren,
                borderColor.alpha > 0 || hasVisibleLinearGradient(node.borderGradient),
                node.borderWidth > 0,
                node.backgroundPath == nil,
                clipAllowsDrawing(clip: effectiveClip, rect: paintFrame)
            {
                // WS-19. Border segments are laid out in the node's *unrotated*
                // paint space and each one is then turned about the node's
                // centre by `placement.rotating`. Walking the bounding box
                // instead would dash a ring around a rect the node does not
                // occupy. The clip predicates keep using the axis-aligned
                // footprint, which contains the rotated segment.
                let dashedBorderSegments: [BorderSegment]?
                if let cornerRadii = node.cornerRadii, cornerRadii.hasPositiveRadius {
                    // Per-corner dash walk: square corners get no arc
                    // segments (matches the solid overlay treatment).
                    dashedBorderSegments = BorderSegments.dashedSegments(
                        frame: quadFrame,
                        width: node.borderWidth,
                        cornerRadii: cornerRadii,
                        strokeStyle: node.borderStrokeStyle
                    )
                } else {
                    dashedBorderSegments = BorderSegments.dashedSegments(
                        frame: quadFrame,
                        width: node.borderWidth,
                        cornerRadius: node.cornerRadius,
                        strokeStyle: node.borderStrokeStyle
                    )
                }
                if let borderSegments = dashedBorderSegments {
                    for segment in borderSegments
                    where clipAllowsDrawing(clip: effectiveClip, rect: placement.footprint(of: segment.rect)) {
                        let stops = BorderSegments.segmentStops(
                            gradient: node.borderGradient,
                            start: borderColor,
                            segment: segment.rect,
                            in: quadFrame
                        )
                        appendFillQuad(
                            placement.rotating(
                                fillQuad(
                                    rect: segment.rect,
                                    cornerRadius: segment.cornerRadius,
                                    color: stops.color,
                                    gradient: stops.gradient,
                                    opacity: opacity,
                                    clip: effectiveClipRect,
                                    surfaceSize: surfaceSize,
                                    displayScale: displayScale,
                                    colorEffects: colorEffects,
                                    clipCornerRadius: ownClipCornerRadius(placement.footprint(of: segment.rect)),
                                    blendMode: effectiveBlendMode
                                ), displayScale: displayScale),
                            gradient: stops.gradient, opacity: opacity, into: &scene, layerIndex: layerIndex)
                    }
                } else {
                    appendFillQuad(
                        placement.rotating(
                            fillQuad(
                                rect: quadFrame,
                                cornerRadius: node.cornerRadius,
                                cornerRadii: node.cornerRadii,
                                color: borderColor,
                                gradient: node.borderGradient,
                                opacity: opacity,
                                clip: effectiveClipRect,
                                surfaceSize: surfaceSize,
                                displayScale: displayScale,
                                colorEffects: colorEffects,
                                clipCornerRadius: ownClipCornerRadius(paintFrame),
                                blendMode: effectiveBlendMode
                            ), displayScale: displayScale),
                        gradient: node.borderGradient, opacity: opacity, into: &scene, layerIndex: layerIndex)
                }
            }

            // Background fill (inset by border width). `fillRect` is the
            // axis-aligned footprint every non-rotatable family paints into
            // (image, glyph, canvas, path); `quadFillRect` is the same
            // inset taken in the node's unrotated paint space, which is what
            // the rotation-carrying quad families use. They are the same rect
            // whenever the node is not rotated.
            let fillRect = node.borderWidth > 0 ? paintFrame.inset(by: node.borderWidth) : paintFrame
            let quadFillRect = node.borderWidth > 0 ? quadFrame.inset(by: node.borderWidth) : quadFrame
            let fillCornerRadius = max(0, node.cornerRadius - node.borderWidth)
            let fillCornerRadii =
                node.borderWidth > 0 ? node.cornerRadii?.inset(by: node.borderWidth) : node.cornerRadii

            let resolvedBGColor = node.backgroundColor ?? node.backgroundGradient?.startColor
            if let bg = resolvedBGColor,
                bg.alpha > 0 || hasVisibleLinearGradient(node.backgroundGradient),
                fillRect.size.width > 0, fillRect.size.height > 0,
                clipAllowsDrawing(clip: effectiveClip, rect: fillRect),
                node.backgroundPath == nil
            {
                appendFillQuad(
                    placement.rotating(
                        fillQuad(
                            rect: quadFillRect,
                            cornerRadius: fillCornerRadius,
                            cornerRadii: fillCornerRadii,
                            color: bg,
                            gradient: node.backgroundGradient,
                            opacity: opacity,
                            clip: effectiveClipRect,
                            surfaceSize: surfaceSize,
                            displayScale: displayScale,
                            colorEffects: colorEffects,
                            blurRadius: Float(blurRadius * displayScale),
                            blurOpaque: blurOpaque ? 1 : 0,
                            clipCornerRadius: ownClipCornerRadius(fillRect),
                            blendMode: effectiveBlendMode
                        ), displayScale: displayScale),
                    gradient: node.backgroundGradient, opacity: opacity,
                    into: &scene, layerIndex: layerIndex
                )
            }

            if let path = node.backgroundPath, fillRect.size.width > 0, fillRect.size.height > 0,
                clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
            {
                // R-ROT. The shape is scaled into the node's *unrotated* paint
                // space and `emit` turns its elements about the node's centre;
                // scaling into `fillRect` (the bounding box) and leaving the
                // elements upright drew a √2-too-large upright shape wherever
                // a `Shape` background sat under a `.rotationEffect`. The two
                // rects are the same for any node that is not rotated.
                let scaledPath = path.scaled(to: quadFillRect)
                let localBounds = scaledPath.segments.boundingRect ?? quadFillRect
                let pathBounds = placement.footprint(of: localBounds)
                // Inherited opacity must compose into the path fill the
                // same way it does for quad fills and the path stroke
                // below; without this, shapes ignored ancestor opacity.
                let effectiveFillColor = resolvedBGColor?.multipliedAlpha(by: opacity)
                if let bg = effectiveFillColor, bg.alpha > 0 {
                    Self.emit(
                        path: PathPrimitive(
                            elements: scaledPath.segments.map { segment in
                                switch segment {
                                case .moveTo(let p): return .moveTo(p)
                                case .lineTo(let p): return .lineTo(p)
                                case .quadCurveTo(let c, let e): return .quadraticCurveTo(control: c, end: e)
                                case .cubicCurveTo(let c1, let c2, let e):
                                    return .cubicCurveTo(control1: c1, control2: c2, end: e)
                                case .arc(let c, let r, let s, let e, let cw):
                                    return .arc(center: c, radius: r, startAngle: s, endAngle: e, clockwise: cw)
                                case .close: return .close
                                }
                            },
                            bounds: localBounds,
                            fillColor: bg,
                            clipBounds: effectiveClipRect,
                            clipCornerRadius: effectiveClip.resolvedCornerRadius(forQuadRect: pathBounds)
                        ), into: &scene, layerIndex: layerIndex, displayScale: displayScale,
                        placement: placement)
                }
                let effectiveStrokeColor = node.borderColor.multipliedAlpha(by: opacity)
                if effectiveStrokeColor.alpha > 0, node.borderWidth > 0 {
                    let strokeStyle = node.borderStrokeStyle ?? StrokeStyle(lineWidth: node.borderWidth)
                    let solidElements: [PathElement] = scaledPath.segments.map { segment in
                        switch segment {
                        case .moveTo(let p): return .moveTo(p)
                        case .lineTo(let p): return .lineTo(p)
                        case .quadCurveTo(let c, let e): return .quadraticCurveTo(control: c, end: e)
                        case .cubicCurveTo(let c1, let c2, let e):
                            return .cubicCurveTo(control1: c1, control2: c2, end: e)
                        case .arc(let c, let r, let s, let e, let cw):
                            return .arc(center: c, radius: r, startAngle: s, endAngle: e, clockwise: cw)
                        case .close: return .close
                        }
                    }
                    // A shape outline is not a rounded rect, so `BorderSegments`
                    // — which resolves dashes by walking a rect perimeter —
                    // cannot see it. `Circle().stroke(style: .init(dash:))`
                    // therefore shipped solid. `PathDashing` is the same walk
                    // over an arbitrary outline, and it runs here so the path
                    // contract stays dash-free for everyone below.
                    let strokeElements =
                        PathDashing.dashed(
                            solidElements, pattern: strokeStyle.dashPattern,
                            offset: strokeStyle.dashOffset) ?? solidElements
                    // A stroke straddles its path, so its footprint is wider
                    // than the path's own bounding rect. The primitive used
                    // to be handed `pathBounds` unchanged, which cropped the
                    // outer half of every shape outline the tessellator sent
                    // to CPU rasterization.
                    let localStrokeBounds = localBounds.outset(
                        by: StrokeOutlineGeometry.boundsOutset(
                            forElements: strokeElements, lineWidth: node.borderWidth,
                            lineCap: strokeStyle.lineCap, lineJoin: strokeStyle.lineJoin,
                            miterLimit: strokeStyle.miterLimit))
                    let strokeBounds = placement.footprint(of: localStrokeBounds)
                    Self.emit(
                        path: PathPrimitive(
                            elements: strokeElements,
                            bounds: localStrokeBounds,
                            strokeColor: effectiveStrokeColor,
                            lineWidth: node.borderWidth,
                            lineCap: strokeStyle.lineCap,
                            lineJoin: strokeStyle.lineJoin,
                            miterLimit: strokeStyle.miterLimit,
                            clipBounds: effectiveClipRect,
                            clipCornerRadius: effectiveClip.resolvedCornerRadius(forQuadRect: strokeBounds)
                        ), into: &scene, layerIndex: layerIndex, displayScale: displayScale,
                        placement: placement)
                }
            }

            if let hoverOverlay = node.hoverEffectOverlayCommand(
                for: fillRect,
                cornerRadius: fillCornerRadius,
                clipRect: effectiveClipRect,
                opacity: opacity
            ) {
                scene.addQuad(
                    placement.rotating(
                        quad(for: hoverOverlay, surfaceSize: surfaceSize, displayScale: displayScale),
                        displayScale: displayScale),
                    toLayer: layerIndex
                )
            }

            let drawsRedactionPlaceholder =
                node.redactionReasons.contains(.placeholder)
                && (node.bitmapSurface != nil || (node.text?.isEmpty == false))
                && fillRect.size.width > 0
                && fillRect.size.height > 0
                && clipAllowsDrawing(clip: effectiveClip, rect: fillRect)

            if drawsRedactionPlaceholder {
                scene.addQuad(
                    placement.rotating(
                        solidQuad(
                            rect: quadFillRect,
                            cornerRadius: retainedRedactionPlaceholderCornerRadius(for: fillRect),
                            color: retainedRedactionPlaceholderBaseColor,
                            opacity: opacity,
                            clip: effectiveClipRect,
                            surfaceSize: surfaceSize,
                            displayScale: displayScale,
                            clipCornerRadius: ownClipCornerRadius(fillRect),
                            blendMode: effectiveBlendMode
                        ), displayScale: displayScale), toLayer: layerIndex)
            } else if let bitmapSurface = node.bitmapSurface,
                fillRect.size.width > 0, fillRect.size.height > 0,
                clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
            {
                let scaledFillRect = scaleRect(quadFillRect, by: displayScale)
                let clipR = clipRectFloats(effectiveClip, surfaceSize: surfaceSize, displayScale: displayScale)
                let textureID = scene.registerImageResource(bitmapSurface)
                scene.addImage(
                    placement.rotating(
                        ImagePrimitive(
                            screenX: Float(scaledFillRect.origin.x),
                            screenY: Float(scaledFillRect.origin.y),
                            screenW: Float(scaledFillRect.size.width),
                            screenH: Float(scaledFillRect.size.height),
                            opacity: opacity,
                            clipX: clipR.0,
                            clipY: clipR.1,
                            clipWidth: clipR.2,
                            clipHeight: clipR.3,
                            // An image carries no corner radius of its own, so —
                            // unlike the background quad — it is rounded by the
                            // node's own clip, not only by its ancestors'.
                            clipCornerRadius: Float(
                                effectiveClip.resolvedCornerRadius(forQuadRect: fillRect) * displayScale),
                            textureID: textureID
                        ), displayScale: displayScale), toLayer: layerIndex)
            }

            if !drawsRedactionPlaceholder,
                let text = node.text, !text.isEmpty,
                fillRect.size.width > 0, fillRect.size.height > 0,
                clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
            {
                let effectiveTextStyle = node.textStyle.multipliedOpacity(by: opacity)
                var nativeGlyphs: [GlyphPrimitive] = []
                var pixelGlyphs: [GlyphPrimitive] = []
                var textDecorationQuads: [QuadPrimitive] = []
                // R-ROT / E6-TEXT. Text is shaped and laid out in the node's
                // *untransformed* paint space and each cell is then scaled and
                // turned about the node's centre — the same two steps the
                // border ring takes. Laying out in `paintFrame` and leaving the
                // cells upright is what kept a rotated card's label horizontal
                // inside a turned card, with the line breaking to the bounding
                // box's width rather than the card's; laying out in the
                // *scaled* rect at an unscaled font size is what made
                // `scaleEffect` re-break the string and a 0.97 press ellipsize
                // a button's own title. `runLayoutRect` is the width the view
                // actually has, and `unplacedRunFootprint` is the preimage of
                // the clip so the pre-placement cull cannot drop a glyph the
                // placement brings in.
                appendTextGlyphs(
                    for: text,
                    style: effectiveTextStyle,
                    in: placement.runLayoutRect(quadFillRect),
                    opacity: 1,
                    clip: effectiveClipRect,
                    cullClip: effectiveClipRect.map { placement.unplacedRunFootprint(of: $0) },
                    clipCornerRadius: effectiveClip.resolvedCornerRadius(forQuadRect: fillRect),
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    contentScale: placement.scale,
                    textSystem: textSystem,
                    into: &nativeGlyphs,
                    pixelGlyphs: &pixelGlyphs,
                    decorationQuads: &textDecorationQuads
                )
                for glyph in nativeGlyphs {
                    scene.addGlyph(placement.placingRun(glyph, displayScale: displayScale), toLayer: layerIndex)
                }
                for glyph in pixelGlyphs {
                    scene.addPixelGlyph(placement.placingRun(glyph, displayScale: displayScale), toLayer: layerIndex)
                }
                for quad in textDecorationQuads {
                    scene.addQuad(placement.placingRun(quad, displayScale: displayScale), toLayer: layerIndex)
                }
                usedNativeGlyphs = usedNativeGlyphs || !nativeGlyphs.isEmpty
                usedPixelGlyphs = usedPixelGlyphs || !pixelGlyphs.isEmpty
            }

            // Canvas custom drawing -- mirror the RenderFrame canvasDraw path
            // (see Runtime.swift) so `Canvas { ctx, size in ... }` content renders
            // through the default GPUIScene/D3D11 path, not only the frame fallback.
            if let canvasDraw = node.canvasDraw,
                fillRect.size.width > 0, fillRect.size.height > 0,
                clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
            {
                var canvasContext = CanvasGraphicsContext()
                canvasDraw(&canvasContext, quadFillRect.size)
                appendCanvasOperations(
                    canvasContext.operations,
                    into: &scene,
                    origin: quadFillRect.origin,
                    baseClip: effectiveClip,
                    placement: placement,
                    opacity: opacity,
                    layerIndex: layerIndex,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    textSystem: textSystem,
                    usedNativeGlyphs: &usedNativeGlyphs,
                    usedPixelGlyphs: &usedPixelGlyphs
                )
            }

            // Children -- sort by zIndex (stable) and rely on scene draw orders
            // rather than allocating paint-order layers.  parentOrigin is kept in
            // untransformed local space; the accumulated screen-space transform is
            // passed separately so that both child origin and size are affected.
            let scrollX = node.scrollAxis == .horizontal ? node.resolvedScrollOffset : 0
            let scrollY = node.scrollAxis == .vertical ? node.resolvedScrollOffset : 0
            let childOrigin = Point(
                x: nodeLocalFrame.origin.x - scrollX,
                y: nodeLocalFrame.origin.y - scrollY
            )

            let sortedChildren: [ViewNode]
            if node.children.contains(where: { $0.zIndex != 0 }) {
                sortedChildren = node.children.enumerated()
                    .sorted { a, b in
                        if a.element.zIndex != b.element.zIndex {
                            return a.element.zIndex < b.element.zIndex
                        }
                        return a.offset < b.offset
                    }
                    .map(\.element)
            } else {
                sortedChildren = node.children
            }

            let isCompositingGroup = node.drawingGroup != nil || node.isCompositingGroup
            // R-ROT / CLF-9. A `clipsToBounds` node whose accumulated transform
            // has a rotation cannot express its clip in the scene contract: the
            // primitive clip is four floats naming an axis-aligned rect, and the
            // turned rect's box is √2 too large at 45°. So the subtree takes
            // the offscreen route — the same `RenderPassDescriptor` machinery a
            // `.drawingGroup()` uses — painted *un*-turned into a buffer whose
            // edges are the clip, and composited back through an
            // `ImagePrimitive.rotationRadians`. The bitmap's own extent is then
            // the clip shape, exactly, on both backends.
            //
            // The buffer is sized from the node's unrotated frame and clamped
            // to the ancestors' clip pulled back into that space; when it
            // cannot be sized (non-finite frame, or past the offscreen budget)
            // the node falls through to inline painting with the bounding-box
            // clip, which is what the whole stack did before this route existed.
            let routesRotatedClip = node.clipsToBounds && placement.isRotated
            let offscreenFrame = routesRotatedClip ? quadFrame : paintFrame
            let offscreenClip =
                routesRotatedClip
                ? inheritedClip.map { placement.unplacedFootprint(of: $0.rect) } : effectiveClipRect
            if isCompositingGroup || routesRotatedClip, !isInsideDrawingGroup, hasPaintableExtent,
                !sortedChildren.isEmpty,
                let buffer = offscreenPassBuffer(
                    label: routesRotatedClip ? "rotatedClip" : "compositingGroup",
                    paintFrame: offscreenFrame, clip: offscreenClip,
                    displayScale: displayScale, isCacheable: true)
            {
                // Compositing group: render children into an offscreen buffer so
                // overlapping content is blended together before ancestor opacity
                // or blend modes are applied. `buffer.frame` is the group's frame
                // clamped to the effective clip — pixels outside it could not
                // survive the clip anyway, and sizing from the raw frame turned
                // `.drawingGroup()` on tall scroll content into a hundreds-of-MB
                // allocation per frame. When the buffer cannot be sized at all
                // (non-finite frame, or past the area budget) `compositingGroupBuffer`
                // returns nil and the group falls back to inline painting.
                let subShift = Transform2D.translation(x: -buffer.frame.origin.x, y: -buffer.frame.origin.y)
                // WS-19. The children map layout space through this node's
                // *effective* transform into screen space, and only then get
                // shifted into the buffer's own origin — the shift is a
                // screen-space translation, so it composes last. Shifting
                // first (and dropping the node's own transform entirely) put
                // a `.drawingGroup()` under any transformed ancestor at the
                // wrong offset inside its own bitmap.
                //
                // R-ROT. On the rotated-clip route the node's own rotation is
                // taken *out* first, because the bitmap holds the subtree
                // upright and the composite puts the angle back. Everything
                // else about the transform — ancestors, scale, translation —
                // still applies, so a rotated clip nested under a scaled
                // ancestor lands at the right size.
                let subInheritedTransform =
                    routesRotatedClip
                    ? Self.unrotating(effectiveTransform, by: placement).concatenating(subShift)
                    : effectiveTransform.concatenating(subShift)
                // The buffer's edges are the clip on the rotated route, and the
                // node's own rounding rides along anchored to its unrotated
                // frame — both expressed in the sub-scene's own space.
                let subClip: RuntimeClipShape? =
                    routesRotatedClip
                    ? RuntimeClipShape(
                        rect: Rect(origin: .zero, size: buffer.frame.size),
                        shapeRect: Rect(
                            x: quadFrame.origin.x - buffer.frame.origin.x,
                            y: quadFrame.origin.y - buffer.frame.origin.y,
                            width: quadFrame.size.width, height: quadFrame.size.height),
                        radii: node.cornerRadii, uniformRadius: node.cornerRadius, space: .painted)
                    : nil
                let subSize = buffer.size

                // Rasterizing the group means walking and CPU-rasterizing its
                // whole subtree on the main actor, so an unchanged group reuses
                // the bitmap it produced last time. The condition is the one the
                // paint-record replay above uses — same key, clean subtree —
                // because the key covers everything about the group itself and
                // `subtreeDirtyFlags` covers everything about its descendants.
                let bitmap: BitmapSurface
                if buffer.pass.isCacheable, !skipCacheUpdates, !node.hasDirtySubtree,
                    node.cachedCompositingGroupKey == cacheKey,
                    let cached = node.cachedCompositingGroupBitmap,
                    cached.width == subSize.width, cached.height == subSize.height,
                    node.cachedCompositingGroupAtlasGeneration.map({
                        $0 == NativeGlyphAtlas.shared.atlasGeneration
                    }) ?? true
                {
                    bitmap = cached
                    scene.paintMetrics.compositingGroupsReused += 1
                } else {
                    var subScene = GPUIScene(clearColor: buffer.clearColor)
                    var subDeferred: [DeferredDrawState] = []
                    var subNative = false
                    var subPixel = false
                    var subReplay = 0

                    for child in sortedChildren {
                        if child.paintsInDeferredPhase {
                            continue
                        }
                        paintNode(
                            child,
                            into: &subScene,
                            deferredDraws: &subDeferred,
                            parentOrigin: childOrigin,
                            inheritedClip: subClip,
                            layerIndex: 0,
                            surfaceSize: surfaceSize,
                            displayScale: displayScale,
                            textSystem: textSystem,
                            previousScene: nil,
                            primitiveOpacity: 1.0,
                            inheritedColorEffects: [],
                            inheritedBlendMode: .normal,
                            usedNativeGlyphs: &subNative,
                            usedPixelGlyphs: &subPixel,
                            replayCount: &subReplay,
                            inheritedTransform: subInheritedTransform,
                            isInsideDrawingGroup: true,
                            skipCacheUpdates: true
                        )
                    }

                    subScene.finish()
                    // The sub-scene is rasterized on the CPU right here, and
                    // `RasterTarget.drawGlyph` returns immediately when its atlas is
                    // nil — which is why every piece of text inside `.drawingGroup()`
                    // used to vanish. The peek below deliberately does *not* consume
                    // the atlas dirty region: the frame has a single consumer at the
                    // end of `paint`, and letting the sub-scene call
                    // `snapshotIfUsedInCurrentFrame()` would hand the outer scene an
                    // empty dirty region for glyphs it still has to upload.
                    if subNative {
                        subScene.glyphAtlas = NativeGlyphAtlas.shared.currentSnapshot()
                    }
                    if subPixel {
                        subScene.pixelGlyphAtlas = pixelGlyphAtlasSnapshot()
                    }
                    // Glyph usage inside the group is glyph usage for the frame: the
                    // atlas-recovery retry and the outer snapshot both key off it.
                    // A reused bitmap has its glyphs baked in and needs neither.
                    usedNativeGlyphs = usedNativeGlyphs || subNative
                    usedPixelGlyphs = usedPixelGlyphs || subPixel

                    bitmap = GPUIRawSceneRasterizer.rasterize(subScene, size: subSize)
                    scene.paintMetrics.compositingGroupsRasterized += 1
                    if buffer.pass.isCacheable, !skipCacheUpdates {
                        node.cachedCompositingGroupKey = cacheKey
                        node.cachedCompositingGroupBitmap = bitmap
                        // Only text ties the bitmap to the atlas; a group without
                        // glyphs stays valid across every recycle.
                        node.cachedCompositingGroupAtlasGeneration =
                            subNative ? NativeGlyphAtlas.shared.atlasGeneration : nil
                    }
                }

                let textureID = scene.registerImageResource(bitmap)
                let scaledFrame = scaleRect(buffer.frame, by: displayScale)
                // On the rotated route the node's own clip is the bitmap, so
                // the composite carries only what its ancestors imposed;
                // re-applying `effectiveClip` would square the result off
                // against the very bounding box the route exists to escape.
                let compositeClip = routesRotatedClip ? inheritedClip : effectiveClip
                let clipR = clipRectFloats(compositeClip, surfaceSize: surfaceSize, displayScale: displayScale)
                let imageOpacity = primitiveOpacity * Float(node.opacity)
                let composite = ImagePrimitive(
                    screenX: Float(scaledFrame.origin.x),
                    screenY: Float(scaledFrame.origin.y),
                    screenW: Float(scaledFrame.size.width),
                    screenH: Float(scaledFrame.size.height),
                    opacity: imageOpacity,
                    clipX: clipR.0,
                    clipY: clipR.1,
                    clipWidth: clipR.2,
                    clipHeight: clipR.3,
                    clipCornerRadius: Float(
                        compositeClip.resolvedCornerRadius(forQuadRect: buffer.frame) * displayScale),
                    textureID: textureID
                )
                scene.addImage(
                    routesRotatedClip
                        ? placement.rotating(composite, displayScale: displayScale) : composite,
                    toLayer: layerIndex)
            } else {
                // This node painted inline, so whatever buffer it composited
                // into on an earlier frame is dead weight now.
                node.releaseCompositingGroupCache()
                traversal.append(
                    .finish(
                        PaintNodeFinishState(
                            node: node,
                            startPaintRecord: startPaintRecord,
                            cacheKey: cacheKey,
                            hasChildren: hasChildren,
                            borderColor: borderColor,
                            paintFrame: paintFrame,
                            placement: placement,
                            effectiveClip: effectiveClip,
                            inheritedClip: inheritedClip,
                            opacity: opacity,
                            colorEffects: colorEffects,
                            effectiveBlendMode: effectiveBlendMode,
                            layerIndex: layerIndex,
                            skipCacheUpdates: skipCacheUpdates
                        )
                    )
                )
                for child in sortedChildren.reversed() where !child.paintsInDeferredPhase {
                    traversal.append(
                        .enter(
                            PaintTraversalContext(
                                node: child,
                                parentOrigin: childOrigin,
                                inheritedClip: effectiveClip,
                                layerIndex: layerIndex,
                                primitiveOpacity: opacity,
                                inheritedColorEffects: colorEffects,
                                inheritedBlendMode: effectiveBlendMode,
                                inheritedTransform: effectiveTransform,
                                // Both flags are inherited, not reset. Hard-coding
                                // them to false made every grandchild of a
                                // `.drawingGroup()` write a `cachedScenePaintRange`
                                // measured against the group's *sub-scene* — indices
                                // into a scene that is discarded as soon as it is
                                // rasterized. Replaying such a range against the real
                                // `previousScene` reads someone else's primitives, or
                                // walks past the end of the record log.
                                isInsideDrawingGroup: isInsideDrawingGroup,
                                skipCacheUpdates: skipCacheUpdates,
                                suppressesContentBlurIsolation: false
                            )
                        )
                    )
                }
                continue
            }

            finishPaintNode(
                PaintNodeFinishState(
                    node: node,
                    startPaintRecord: startPaintRecord,
                    cacheKey: cacheKey,
                    hasChildren: hasChildren,
                    borderColor: borderColor,
                    paintFrame: paintFrame,
                    placement: placement,
                    effectiveClip: effectiveClip,
                    inheritedClip: inheritedClip,
                    opacity: opacity,
                    colorEffects: colorEffects,
                    effectiveBlendMode: effectiveBlendMode,
                    layerIndex: layerIndex,
                    skipCacheUpdates: skipCacheUpdates
                ),
                into: &scene,
                surfaceSize: surfaceSize,
                displayScale: displayScale
            )
        }
    }

    private static func finishPaintNode(
        _ state: PaintNodeFinishState,
        into scene: inout GPUIScene,
        surfaceSize: Size,
        displayScale: Double
    ) {
        let node = state.node

        // Border overlay for nodes with children: re-drawn after children so
        // the border ring remains visible when child content fills the frame.
        // Uses thin edge segments instead of a full-rect fill.
        if state.hasChildren,
            state.borderColor.alpha > 0 || hasVisibleLinearGradient(node.borderGradient),
            node.borderWidth > 0,
            node.backgroundPath == nil,
            clipAllowsDrawing(clip: state.effectiveClip, rect: state.paintFrame)
        {
            // WS-19. The ring is walked in the node's unrotated paint space
            // and each segment is turned about the node's centre, matching
            // the pre-children border exactly; the clip predicates keep using
            // each segment's axis-aligned footprint.
            let ringFrame = state.placement.frame
            let segments: [BorderSegment]
            let dashedSegments: [BorderSegment]?
            if let cornerRadii = node.cornerRadii, cornerRadii.hasPositiveRadius {
                dashedSegments = BorderSegments.dashedSegments(
                    frame: ringFrame,
                    width: node.borderWidth,
                    cornerRadii: cornerRadii,
                    strokeStyle: node.borderStrokeStyle
                )
            } else {
                dashedSegments = BorderSegments.dashedSegments(
                    frame: ringFrame,
                    width: node.borderWidth,
                    cornerRadius: node.cornerRadius,
                    strokeStyle: node.borderStrokeStyle
                )
            }
            if let dashed = dashedSegments {
                segments = dashed
            } else if let cornerRadii = node.cornerRadii, cornerRadii.hasPositiveRadius {
                // Per-corner ring: square corners get no arc segments, so
                // the overlay no longer paints faint arcs there.
                segments = BorderSegments.solidSegments(
                    frame: ringFrame,
                    width: node.borderWidth,
                    cornerRadii: cornerRadii
                )
            } else {
                segments = BorderSegments.solidSegments(
                    frame: ringFrame,
                    width: node.borderWidth,
                    cornerRadius: node.cornerRadius
                )
            }
            for segment in segments
            where clipAllowsDrawing(clip: state.effectiveClip, rect: state.placement.footprint(of: segment.rect)) {
                let segmentFootprint = state.placement.footprint(of: segment.rect)
                let stops = BorderSegments.segmentStops(
                    gradient: node.borderGradient,
                    start: state.borderColor,
                    segment: segment.rect,
                    in: ringFrame
                )
                appendFillQuad(
                    state.placement.rotating(
                        fillQuad(
                            rect: segment.rect,
                            cornerRadius: segment.cornerRadius,
                            color: stops.color,
                            gradient: stops.gradient,
                            opacity: state.opacity,
                            clip: state.effectiveClip?.rect,
                            surfaceSize: surfaceSize,
                            displayScale: displayScale,
                            colorEffects: state.colorEffects,
                            clipCornerRadius: state.inheritedClip.ancestorCornerRadius(
                                forQuadRect: segmentFootprint, rejectingOutside: state.effectiveClip?.rect),
                            blendMode: state.effectiveBlendMode
                        ), displayScale: displayScale),
                    gradient: stops.gradient, opacity: state.opacity,
                    into: &scene, layerIndex: state.layerIndex)
            }
        }

        appendContentBlurPass(
            state, into: &scene, surfaceSize: surfaceSize, displayScale: displayScale)

        if !state.skipCacheUpdates {
            node.cachedSceneKey = state.cacheKey
            node.cachedScenePaintRange = state.startPaintRecord..<scene.paintRecordCount
        }
        node.markSubtreeRendered()
    }

    /// The **fallback** lowering of `.blur(radius:)`: a backdrop-blur quad
    /// over the node's painted frame, taken only when the isolation pass
    /// (`appendIsolatedContentBlur`) could not size its buffer — a
    /// non-finite frame, or one whose outset area is past the offscreen
    /// budget.
    ///
    /// The primitive is the existing backdrop-blur quad — both backends
    /// already know how to snapshot what is painted so far under a rect,
    /// blur it, and composite through the quad's coverage — with a fully
    /// transparent tint, so the composite writes the blurred result alone.
    ///
    /// Two divergences from the isolation pass, both documented in
    /// `docs/GPURenderingPipeline.md`:
    ///
    /// - It blurs everything already painted within the bounds, not the
    ///   subtree alone. Identical whenever the backdrop is flat.
    /// - The bounds are the painted frame with **no outset**, so the blur
    ///   ends at a hard rectangular edge instead of fading out. That is
    ///   deliberate: the outset this used to apply is what made a `.blur()`
    ///   smear its siblings. `VStack { a; b.blur(10); c }` composited the
    ///   blurred backdrop over a band of `a` and `c` too, so blurring one
    ///   view changed the pixels of two others — a hard edge is wrong in a
    ///   way the user can see is theirs, a smeared neighbour is not.
    private static func appendContentBlurPass(
        _ state: PaintNodeFinishState,
        into scene: inout GPUIScene,
        surfaceSize: Size,
        displayScale: Double
    ) {
        let node = state.node
        let radius = node.contentBlurRadius
        guard radius > 0, state.paintFrame.size.width > 0, state.paintFrame.size.height > 0 else { return }

        let bounds = state.paintFrame
        guard clipAllowsDrawing(clip: state.effectiveClip, rect: bounds) else { return }

        scene.addQuad(
            fillQuad(
                rect: bounds,
                cornerRadius: 0,
                cornerRadii: nil,
                // Fully transparent tint: the composite is
                // `tint over blurred backdrop`, so alpha 0 leaves the
                // blurred subtree itself and nothing else.
                color: .clear,
                gradient: nil,
                opacity: state.opacity,
                clip: state.effectiveClip?.rect,
                surfaceSize: surfaceSize,
                displayScale: displayScale,
                colorEffects: state.colorEffects,
                blurRadius: Float(radius * displayScale),
                blurOpaque: node.contentBlurOpaque ? 1 : 0,
                clipCornerRadius: state.inheritedClip.ancestorCornerRadius(
                    forQuadRect: bounds, rejectingOutside: state.effectiveClip?.rect),
                blendMode: state.effectiveBlendMode
            ),
            toLayer: state.layerIndex)
    }

    // MARK: - Content blur as an isolated pass

    /// Everything the isolation pass needs from the traversal. It travels as
    /// one value so the branch in `paintNode` — a function that recurses —
    /// costs one argument rather than a dozen more live locals.
    private struct ContentBlurIsolation {
        let node: ViewNode
        let parentOrigin: Point
        let inheritedTransform: Transform2D
        let inheritedColorEffects: [RetainedColorEffect]
        let inheritedBlendMode: BlendMode
        let paintFrame: Rect
        let effectiveClip: RuntimeClipShape?
        let cacheKey: ViewPaintCacheKey
        /// Ancestors' opacity only. The node's own opacity is applied inside
        /// the bitmap, because the sub-paint enters the node itself.
        let primitiveOpacity: Float
        let layerIndex: Int
        let isInsideDrawingGroup: Bool
        let skipCacheUpdates: Bool
    }

    /// SwiftUI's `.blur(radius:)`: render the subtree in isolation, blur
    /// *that*, and composite the result.
    ///
    /// What it replaces, in two steps. First `.blur()` was an inherited
    /// radius applied to every descendant *background quad* — one backbuffer
    /// copy and two blur passes per descendant, and text, images, borders
    /// and paths stayed perfectly sharp because they carry no such field.
    /// Then it became a single backdrop-blur quad over the subtree's bounds
    /// **outset by the radius**, which fixed both of those and introduced a
    /// third: a backdrop pass blurs whatever is already painted under it, so
    /// `VStack { a; b.blur(10); c }` blurred a 10-point band of `a` and `c`
    /// into `b`'s panel. Blurring one view is not allowed to change the
    /// pixels of another.
    ///
    /// Isolation is the fix, and it is the same offscreen machinery a
    /// compositing group uses: an `.offscreen` target cleared to transparent,
    /// the subtree painted into it shifted to the buffer's origin, the result
    /// blurred by `PremultipliedImageBlur` — the CPU spelling of the blur
    /// both backends run — and placed as an `ImagePrimitive`. The buffer is
    /// the frame outset by the radius, so the blur still fades out past the
    /// frame; that margin is transparent in the bitmap, so it fades to
    /// nothing rather than to a neighbour.
    ///
    /// Returns false when the buffer cannot be sized (non-finite frame, or
    /// past the offscreen area budget); the caller then paints inline and
    /// `appendContentBlurPass` degrades to the backdrop quad.
    ///
    /// Cost: a blurred subtree is one CPU rasterization plus one Gaussian
    /// when it changes and nothing at all when it does not — the bitmap is
    /// keyed on the node's paint key, and the key includes the radius.
    private static func appendIsolatedContentBlur(
        _ isolation: ContentBlurIsolation,
        into scene: inout GPUIScene,
        deferredDraws: inout [DeferredDrawState],
        surfaceSize: Size,
        displayScale: Double,
        textSystem: WindowTextSystem,
        usedNativeGlyphs: inout Bool,
        usedPixelGlyphs: inout Bool
    ) -> Bool {
        let node = isolation.node
        // The radius the blur actually runs at, capped exactly where the
        // backdrop path caps it. The buffer is outset by the *capped* radius:
        // outsetting by an uncapped one would size a buffer for a blur that
        // cannot happen, and push it past the area budget on the way.
        //
        // `contentBlurOpaque` — SwiftUI's `.blur(radius:opaque:)` hint — is
        // not modelled here. It says the blurred result may be treated as
        // opaque, and an isolated pass has a transparent margin by
        // construction: that margin is what lets the blur fade out instead of
        // smearing a neighbour. It survives as node metadata and still
        // reaches the backdrop-quad fallback.
        let deviceRadius = min(
            GPUISceneValue.int((node.contentBlurRadius * displayScale).rounded()),
            Int(GPUISceneLimits.maxBlurRadius))
        guard deviceRadius > 0 else { return false }

        guard
            let buffer = offscreenPassBuffer(
                label: "contentBlur",
                paintFrame: isolation.paintFrame.inset(by: -Double(deviceRadius) / displayScale),
                clip: isolation.effectiveClip?.rect,
                displayScale: displayScale,
                // A pass whose caches are suppressed (inside a compositing
                // group) cannot key its result on anything the next frame
                // will still recognise, so it must not try.
                isCacheable: !isolation.skipCacheUpdates)
        else {
            return false
        }

        // Claimed before the cache is consulted, and on both paths: with a
        // reused bitmap the deferred descendants are *already inside it*, and
        // leaving them unclaimed lets the deferred phase put a second, sharp
        // copy of every pinned header on top from the second frame onwards.
        // The outer paint-record replay is refused for content-blur nodes
        // (see `paintNode`) for the same reason: this claim is the only
        // thing that keeps those entries out of the deferred phase, so every
        // frame that composites the bitmap has to pass through here.
        let deferredDescendants = claimDeferredDescendants(of: isolation, in: &deferredDraws)

        let subSize = buffer.size
        let bitmap: BitmapSurface
        if buffer.pass.isCacheable, !node.hasDirtySubtree,
            node.cachedCompositingGroupKey == isolation.cacheKey,
            let cached = node.cachedCompositingGroupBitmap,
            cached.width == subSize.width, cached.height == subSize.height,
            node.cachedCompositingGroupAtlasGeneration.map({
                $0 == NativeGlyphAtlas.shared.atlasGeneration
            }) ?? true
        {
            bitmap = cached
            scene.paintMetrics.contentBlurPassesReused += 1
        } else {
            var subNative = false
            var subPixel = false
            let rasterized = rasterizeIsolatedSubtree(
                isolation,
                buffer: buffer,
                deferredDescendants: deferredDescendants,
                surfaceSize: surfaceSize,
                displayScale: displayScale,
                textSystem: textSystem,
                usedNativeGlyphs: &subNative,
                usedPixelGlyphs: &subPixel)
            // Glyph usage inside the pass is glyph usage for the frame: the
            // atlas-recovery retry and the outer snapshot both key off it. A
            // reused bitmap has its glyphs baked in and needs neither.
            usedNativeGlyphs = usedNativeGlyphs || subNative
            usedPixelGlyphs = usedPixelGlyphs || subPixel

            bitmap = PremultipliedImageBlur.blurred(rasterized, radius: deviceRadius)
            if buffer.pass.isCacheable {
                node.cachedCompositingGroupKey = isolation.cacheKey
                node.cachedCompositingGroupBitmap = bitmap
                // Only text ties the bitmap to the atlas; a pass without
                // glyphs stays valid across every recycle.
                node.cachedCompositingGroupAtlasGeneration =
                    subNative ? NativeGlyphAtlas.shared.atlasGeneration : nil
            }
        }
        scene.paintMetrics.contentBlurPasses += 1

        let textureID = scene.registerImageResource(bitmap)
        let scaledFrame = scaleRect(buffer.frame, by: displayScale)
        let clipR = clipRectFloats(isolation.effectiveClip, surfaceSize: surfaceSize, displayScale: displayScale)
        scene.addImage(
            ImagePrimitive(
                screenX: Float(scaledFrame.origin.x),
                screenY: Float(scaledFrame.origin.y),
                screenW: Float(scaledFrame.size.width),
                screenH: Float(scaledFrame.size.height),
                opacity: isolation.primitiveOpacity,
                clipX: clipR.0,
                clipY: clipR.1,
                clipWidth: clipR.2,
                clipHeight: clipR.3,
                clipCornerRadius: Float(
                    isolation.effectiveClip.resolvedCornerRadius(forQuadRect: buffer.frame) * displayScale),
                textureID: textureID
            ), toLayer: isolation.layerIndex)
        return true
    }

    /// Paints the blurred subtree into its own scene and rasterizes it.
    ///
    /// Out of line, and returning the bitmap rather than taking the sub-scene
    /// as an `inout`, so none of it is live in the caller's frame while the
    /// rasterizer runs.
    private static func rasterizeIsolatedSubtree(
        _ isolation: ContentBlurIsolation,
        buffer: OffscreenPassBuffer,
        deferredDescendants: [ClaimedDeferredDraw],
        surfaceSize: Size,
        displayScale: Double,
        textSystem: WindowTextSystem,
        usedNativeGlyphs: inout Bool,
        usedPixelGlyphs: inout Bool
    ) -> BitmapSurface {
        var subScene = GPUIScene(clearColor: buffer.clearColor)
        var subDeferred: [DeferredDrawState] = []
        var subReplay = 0
        // The children map layout space through the node's inherited
        // transform into screen space and are only then shifted into the
        // buffer's origin, so the shift composes last — the same order a
        // compositing group uses, and the reason a blurred subtree under a
        // transformed ancestor lands in the right place inside its bitmap.
        let bufferShift = Transform2D.translation(
            x: -buffer.frame.origin.x, y: -buffer.frame.origin.y)
        let subTransform = isolation.inheritedTransform.concatenating(bufferShift)

        paintNode(
            isolation.node,
            into: &subScene,
            deferredDraws: &subDeferred,
            parentOrigin: isolation.parentOrigin,
            inheritedClip: nil,
            layerIndex: 0,
            surfaceSize: surfaceSize,
            displayScale: displayScale,
            textSystem: textSystem,
            previousScene: nil,
            // The node's own opacity is applied by the node; ancestors'
            // opacity is applied to the composited image instead, so it is
            // not baked into a bitmap that outlives this frame.
            primitiveOpacity: 1,
            inheritedColorEffects: isolation.inheritedColorEffects,
            inheritedBlendMode: isolation.inheritedBlendMode,
            usedNativeGlyphs: &usedNativeGlyphs,
            usedPixelGlyphs: &usedPixelGlyphs,
            replayCount: &subReplay,
            inheritedTransform: subTransform,
            isInsideDrawingGroup: isolation.isInsideDrawingGroup,
            skipCacheUpdates: true,
            suppressesContentBlurIsolation: true
        )

        appendDeferredDescendants(
            deferredDescendants,
            of: isolation,
            into: &subScene,
            subDeferredDraws: &subDeferred,
            bufferShift: bufferShift,
            surfaceSize: surfaceSize,
            displayScale: displayScale,
            textSystem: textSystem,
            usedNativeGlyphs: &usedNativeGlyphs,
            usedPixelGlyphs: &usedPixelGlyphs,
            replayCount: &subReplay)

        subScene.finish()
        // The sub-scene is CPU-rasterized here, and `RasterTarget.drawGlyph`
        // returns immediately when its atlas is nil. The peek deliberately
        // does not consume the atlas dirty region: the frame has a single
        // consumer at the end of `paint`.
        if usedNativeGlyphs {
            subScene.glyphAtlas = NativeGlyphAtlas.shared.currentSnapshot()
        }
        if usedPixelGlyphs {
            subScene.pixelGlyphAtlas = pixelGlyphAtlasSnapshot()
        }
        return GPUIRawSceneRasterizer.rasterize(subScene, size: buffer.size)
    }

    /// A deferred entry the isolation pass has taken away from the deferred
    /// phase, in the order that phase would have drawn it.
    private enum ClaimedDeferredDraw {
        case subtree(DeferredSubtreePayload)
        /// A nested scroll view's indicator, with the content mask its
        /// deferred entry carried — the quad is built exactly as the
        /// deferred drain builds it, just shifted into the pass's buffer.
        case scrollIndicator(ScrollIndicatorDeferredDrawPayload, contentMask: RuntimeClipShape?)
    }

    /// Takes the deferred entries that belong to the blurred subtree away
    /// from the deferred phase, in the order that phase would have drawn
    /// them.
    ///
    /// A pinned header is a deferred subtree of its scroll view: it is
    /// collected during prepaint and drained after every node has painted, so
    /// a `.blur()` on a `LazyVStack(pinnedViews:)` rendered blurred rows with
    /// perfectly sharp headers sitting on top of them. There is no ordering
    /// of one pass that fixes that — the pinned header has to be *inside* the
    /// thing being blurred. A scroll view nested inside the subtree defers
    /// its indicator the same way, so the indicator is claimed by owning
    /// node exactly like a subtree is.
    ///
    /// Claiming is separate from drawing because the isolation pass may skip
    /// the drawing entirely: a reused bitmap already contains these entries,
    /// and the deferred phase must skip them on that frame too.
    private static func claimDeferredDescendants(
        of isolation: ContentBlurIsolation,
        in deferredDraws: inout [DeferredDrawState]
    ) -> [ClaimedDeferredDraw] {
        guard !deferredDraws.isEmpty else { return [] }
        var claimed: [ClaimedDeferredDraw] = []
        // Same order the deferred phase drains in: priority, then the order
        // prepaint recorded them.
        for index in deferredDraws.indices.sorted(by: { lhs, rhs in
            let left = deferredDraws[lhs]
            let right = deferredDraws[rhs]
            if left.priority != right.priority { return left.priority < right.priority }
            return lhs < rhs
        }) {
            guard !deferredDraws[index].isDrawnInline else { continue }
            let claim: ClaimedDeferredDraw?
            switch deferredDraws[index].payload {
            case .subtree(let payload):
                // Strictly *below* the blurred node: an entry for the node
                // itself is the one being drained right now, and painting it
                // here would recurse without end.
                if let deferredNode = payload.node,
                    deferredNode !== isolation.node,
                    isNode(deferredNode, insideSubtreeOf: isolation.node)
                {
                    claim = .subtree(payload)
                } else {
                    claim = nil
                }
            case .scrollIndicator(let payload):
                // Same rule by the indicator's owning node. Strictly below
                // again — not for recursion this time, but so the blurred
                // node's *own* indicator keeps drawing sharp above its
                // blurred content, matching the subtree exclusion.
                if let owningNode = payload.node,
                    owningNode !== isolation.node,
                    isNode(owningNode, insideSubtreeOf: isolation.node)
                {
                    claim = .scrollIndicator(payload, contentMask: deferredDraws[index].contentMask)
                } else {
                    claim = nil
                }
            }
            guard let claim else { continue }

            deferredDraws[index].isDrawnInline = true
            // The entry no longer draws into the outer scene, so any
            // paint-record range it carries describes a scene it is not in.
            deferredDraws[index].cachedScenePaintRange = nil
            claimed.append(claim)
        }
        return claimed
    }

    /// Draws the claimed deferred entries into the isolation pass's scene.
    private static func appendDeferredDescendants(
        _ claims: [ClaimedDeferredDraw],
        of isolation: ContentBlurIsolation,
        into subScene: inout GPUIScene,
        subDeferredDraws: inout [DeferredDrawState],
        bufferShift: Transform2D,
        surfaceSize: Size,
        displayScale: Double,
        textSystem: WindowTextSystem,
        usedNativeGlyphs: inout Bool,
        usedPixelGlyphs: inout Bool,
        replayCount: inout Int
    ) {
        for claim in claims {
            switch claim {
            case .subtree(let payload):
                guard let deferredNode = payload.node else { continue }
                paintNode(
                    deferredNode,
                    into: &subScene,
                    deferredDraws: &subDeferredDraws,
                    parentOrigin: payload.parentOrigin,
                    inheritedClip: nil,
                    layerIndex: 0,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    textSystem: textSystem,
                    previousScene: nil,
                    // `inheritedOpacity` is accumulated from the root and so
                    // already contains the ancestors' opacity that the composited
                    // image applies again; divide it back out rather than
                    // multiplying it in twice.
                    primitiveOpacity: isolation.primitiveOpacity > 0
                        ? payload.inheritedOpacity / isolation.primitiveOpacity
                        : payload.inheritedOpacity,
                    inheritedColorEffects: payload.inheritedColorEffects,
                    inheritedBlendMode: payload.inheritedBlendMode,
                    usedNativeGlyphs: &usedNativeGlyphs,
                    usedPixelGlyphs: &usedPixelGlyphs,
                    replayCount: &replayCount,
                    // The deferred payload's transform is the outer screen space
                    // its parent handed it; the buffer shift composes last, as it
                    // does for the subtree painted above.
                    inheritedTransform: payload.inheritedTransform.concatenating(bufferShift),
                    skipCacheUpdates: true
                )
            case .scrollIndicator(let payload, let contentMask):
                // The deferred drain's spelling of the indicator quad — same
                // command, same clip rounding — shifted into the buffer's
                // origin. Track and mask are already in painted space and the
                // buffer shift is a pure translation, so translating the two
                // rects is exact; the corner rounding resolves against the
                // *unshifted* pair, which is the same answer because both
                // rects move together.
                var command = payload.fillRectCommand(contentMask: contentMask?.rect)
                let clipCornerRadius = contentMask.resolvedCornerRadius(forQuadRect: command.rect)
                command.rect = Rect(origin: command.rect.origin.applying(bufferShift), size: command.rect.size)
                command.clipRect = command.clipRect.map {
                    Rect(origin: $0.origin.applying(bufferShift), size: $0.size)
                }
                // The payload's color was multiplied by the node's effective
                // opacity at prepaint, which contains the ancestors' opacity
                // the composited image applies again; divide it back out, as
                // the subtree path above does.
                if isolation.primitiveOpacity > 0 {
                    command.color = command.color.multipliedAlpha(by: 1 / isolation.primitiveOpacity)
                }
                appendFillQuad(
                    quad(
                        for: command, surfaceSize: surfaceSize, displayScale: displayScale,
                        clipCornerRadius: clipCornerRadius),
                    gradient: command.gradient, opacity: 1,
                    into: &subScene, layerIndex: 0)
            }
        }
    }

    /// The drain-side half of `claimDeferredDescendants`: true when this
    /// entry's owner sits under a content-blur node whose last visit painted
    /// via the isolation pass, so the bitmap already in the scene contains it.
    ///
    /// Claiming can only speak for frames that *reach* the blurred node. A
    /// clean ancestor replaying its own cached range carries the composited
    /// bitmap forward and never re-enters the blur, so on that frame the entry
    /// is unclaimed and would be drawn sharp on top of pixels that already have
    /// it. Asking the node instead of the claim covers both.
    ///
    /// The rule is the claim's rule, exactly: the blur must be a *strict*
    /// ancestor — a blurred scroll view's own indicator stays sharp above its
    /// blurred content, and a deferred subtree rooted at the blurred node is
    /// the thing being drained, not something inside it — so the walk starts at
    /// the parent.
    ///
    /// Both payload kinds, deliberately. `DeferredDrawPayload` has exactly two,
    /// and every producer of the subtree kind — sheets, full-screen covers,
    /// popovers, inspectors, alerts, confirmation dialogs, context menus, menu
    /// panels and pinned section headers/footers — carries the presented node,
    /// so all of them are answered here by the same walk. Cost is the entry's
    /// depth, and deferred entries are counted in ones.
    private static func isDrawnByAnAncestorsContentBlurBitmap(_ payload: DeferredDrawPayload) -> Bool {
        let owner: ViewNode?
        switch payload {
        case .subtree(let payload): owner = payload.node
        case .scrollIndicator(let payload): owner = payload.node
        }
        var current = owner?.parent
        while let node = current {
            if node.contentBlurRadius > 0, node.lastPaintedViaContentBlurIsolation { return true }
            current = node.parent
        }
        return false
    }

    /// True when `candidate` is `root` or lives under it. Walks parents, so
    /// it costs the subtree's depth and nothing per frame otherwise.
    private static func isNode(_ candidate: ViewNode, insideSubtreeOf root: ViewNode) -> Bool {
        var current: ViewNode? = candidate
        while let node = current {
            if node === root { return true }
            current = node.parent
        }
        return false
    }

    // MARK: - Offscreen subtree passes

    /// The offscreen buffer a subtree pass rasterizes into.
    ///
    /// Two passes use it: a compositing group (`.drawingGroup()`,
    /// `.compositingGroup()`) and the isolation pass a `.blur(radius:)`
    /// subtree runs. They differ only in the descriptor they ask for, which
    /// is the point of describing them in one vocabulary.
    private struct OffscreenPassBuffer {
        /// The pass's frame clamped to the effective clip, in logical points.
        /// The sub-scene is shifted by this origin and the composited image is
        /// placed here, so the two always agree.
        let frame: Rect
        /// The offscreen pass, in the render-pass vocabulary the batch
        /// renderer and the blur engine also speak: an `.offscreen` target
        /// with a clear colour, whose viewport is the whole target. Every
        /// field on it is read — `target.width/height` size the bitmap,
        /// `target.clearColor` is what the sub-scene clears to, and
        /// `isCacheable` decides whether last frame's bitmap may stand in.
        let pass: RenderPassDescriptor

        /// Buffer extent in device pixels.
        var size: IntSize {
            IntSize(width: Int32(pass.target.width), height: Int32(pass.target.height))
        }

        /// What the sub-scene clears to. A transparent clear is what makes
        /// the pass an *isolation*: nothing painted before it is in the
        /// bitmap, which is exactly why a Material inside one blurs nothing
        /// (see `docs/GPURenderingPipeline.md`).
        var clearColor: Color { pass.target.clearColor ?? .clear }
    }

    /// Largest offscreen buffer, in device pixels. A 4K window is
    /// ~8.3 M pixels, so this leaves generous headroom while keeping a single
    /// pass's allocation under 64 MB — past it inline painting is both cheaper
    /// and more correct than a buffer the machine cannot afford every frame.
    private static let maxCompositingGroupPixels = 16_777_216

    /// `transform` with `placement`'s rotation removed: the map that puts the
    /// node's subtree where it would have been had it not been turned.
    ///
    /// Built as a screen-space operator around the node's *placed* centre and
    /// composed last, for the same reason the node's own centred transform is
    /// — it is expressed in the space `transform` produces. Composing it the
    /// other way would un-turn about a point in the pre-transform space, which
    /// is the wrong pivot for anything under a scale or an offset.
    private static func unrotating(_ transform: Transform2D, by placement: PaintPlacement) -> Transform2D {
        guard placement.isRotated else { return transform }
        let pivot = Point(x: placement.frame.midX, y: placement.frame.midY)
        let unrotate = Transform2D.translation(x: -pivot.x, y: -pivot.y)
            .concatenating(Transform2D(rotation: -placement.rotation))
            .concatenating(.translation(x: pivot.x, y: pivot.y))
        return transform.concatenating(unrotate)
    }

    /// Sizes the offscreen buffer for a subtree pass, or returns nil when the
    /// subtree must be painted inline instead.
    ///
    /// Three things used to be missing here and each was reachable from app
    /// code: the frame was not clamped to the clip (so `.drawingGroup()` on tall
    /// scroll content allocated the *content* size every frame), the
    /// `Double → Int → Int32` conversions trapped on a non-finite or huge frame
    /// (`maxWidth: .infinity` resolving badly is a process kill, not a glitch),
    /// and there was no upper bound at all.
    private static func offscreenPassBuffer(
        label: String,
        paintFrame: Rect,
        clip: Rect?,
        displayScale: Double,
        isCacheable: Bool
    ) -> OffscreenPassBuffer? {
        guard paintFrame.origin.x.isFinite, paintFrame.origin.y.isFinite,
            paintFrame.size.width.isFinite, paintFrame.size.height.isFinite,
            displayScale.isFinite, displayScale > 0
        else {
            return nil
        }

        // Only the clipped region can contribute pixels; anything outside it is
        // discarded by the image primitive's own clip either way.
        let frame: Rect
        if let clip {
            guard let visible = paintFrame.intersected(with: clip) else { return nil }
            frame = visible
        } else {
            frame = paintFrame
        }
        guard frame.size.width > 0, frame.size.height > 0 else { return nil }

        let width = min(
            max(1, GPUISceneValue.int((frame.size.width * displayScale).rounded(.up))),
            GPUISceneLimits.maxSurfaceDimension
        )
        let height = min(
            max(1, GPUISceneValue.int((frame.size.height * displayScale).rounded(.up))),
            GPUISceneLimits.maxSurfaceDimension
        )
        guard width * height <= maxCompositingGroupPixels else { return nil }

        let target = RenderTargetDescriptor(
            kind: .offscreen, width: width, height: height, clearColor: .clear)
        return OffscreenPassBuffer(
            frame: frame,
            pass: RenderPassDescriptor(
                label: label,
                target: target,
                viewport: SubTextureRegion(textureWidth: width, textureHeight: height),
                inheritedOpacity: 1,
                // The bitmap is keyed on the subtree's paint cache key and
                // reused across frames while nothing beneath it changed —
                // except where the caller says the result cannot be reused.
                isCacheable: isCacheable
            )
        )
    }

    /// Attaches the atlases a scene's glyph quads address when the pass that
    /// produced it rasterized no glyph of its own.
    ///
    /// Which atlases a frame ships is decided by the primitives in it, not by
    /// what the painter happened to do this pass. A frame that replayed all of
    /// its text — or a cached scene the runtime returns without painting at
    /// all — emits no glyph, and used to ship no atlas because of it: D3D11
    /// covered for that by resolving `.cached`, while the CPU rasterizer (every
    /// screenshot, gallery baseline and macOS parity render) got `nil` and drew
    /// no text at all, for a frame the user sees text in.
    ///
    /// Cheap by construction: the snapshot carries the atlas `Data` by
    /// reference and declares `.unchanged` at the version the consumer already
    /// holds, so a GPU backend skips the upload.
    static func attachCachedGlyphAtlases(to scene: inout GPUIScene) {
        if scene.usesGlyphs, scene.glyphAtlas == nil {
            scene.glyphAtlas = NativeGlyphAtlas.shared.snapshotForCachedGlyphs()
        }
        if scene.usesPixelGlyphs, scene.pixelGlyphAtlas == nil {
            scene.pixelGlyphAtlas = pixelGlyphAtlasSnapshot()
        }
    }

    /// Snapshot of the shared pixel-font atlas. The pixel atlas is built
    /// once and never written again, so every snapshot of it carries the
    /// same content version and reports `.unchanged`: the first frame
    /// uploads it, every later frame skips. It used to declare the whole
    /// surface dirty on every frame, which is a full texture upload per
    /// frame for pixels that cannot change.
    private static func pixelGlyphAtlasSnapshot() -> GlyphAtlasSnapshot {
        let atlas = PixelFontAtlas.shared.surface
        return GlyphAtlasSnapshot(
            width: atlas.width,
            height: atlas.height,
            pixels: atlas.pixels,
            contentVersion: atlas.contentToken,
            update: .unchanged
        )
    }

    // MARK: - Helpers

    /// Bounding rect covering `rect` and any non-nil additional rects.
    private static func union(_ rect: Rect, _ others: Rect?...) -> Rect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY
        for other in others {
            guard let other else { continue }
            minX = min(minX, other.minX)
            minY = min(minY, other.minY)
            maxX = max(maxX, other.maxX)
            maxY = max(maxY, other.maxY)
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Builds a solid-color QuadPrimitive (start color == end color, no gradient).
    private static func solidQuad(
        rect: Rect,
        cornerRadius: Double,
        cornerRadii: RetainedCornerRadii? = nil,
        color: Color,
        opacity: Float,
        clip: Rect?,
        surfaceSize: Size,
        displayScale: Double,
        colorEffects: [RetainedColorEffect] = [],
        blurRadius: Float = 0,
        blurOpaque: Float = 0,
        clipCornerRadius: Double = 0,
        blendMode: BlendMode = .normal
    ) -> QuadPrimitive {
        let scaledRect = scaleRect(rect, by: displayScale)
        let clipR = clipRectFloats(clip, surfaceSize: surfaceSize, displayScale: displayScale)
        let a = color.alpha * opacity
        let fx = encodeColorEffects(colorEffects)
        var quad = QuadPrimitive(
            x: Float(scaledRect.origin.x),
            y: Float(scaledRect.origin.y),
            width: Float(scaledRect.size.width),
            height: Float(scaledRect.size.height),
            cornerRadius: Float(cornerRadius * displayScale),
            startR: color.red, startG: color.green, startB: color.blue, startA: a,
            endR: color.red, endG: color.green, endB: color.blue, endA: a,
            gradientAxis: 0,
            clipX: clipR.0, clipY: clipR.1,
            clipWidth: clipR.2, clipHeight: clipR.3,
            clipCornerRadius: Float(clipCornerRadius * displayScale),
            blendMode: Float(blendMode.rawValue),
            effectType: fx.effectType,
            effectIntensity: fx.effectIntensity,
            blurRadius: blurRadius,
            blurOpaque: blurOpaque,
            effectParam1: fx.effectParam1,
            effectParam2: fx.effectParam2,
            effectParam3: fx.effectParam3,
            effectParam4: fx.effectParam4
        )
        applyPerCornerRadii(cornerRadii, displayScale: displayScale, to: &quad)
        return quad
    }

    /// Writes per-corner radii onto a quad (scaled to device pixels).
    /// All-zero radii leave the quad on the uniform `cornerRadius` path.
    private static func applyPerCornerRadii(
        _ cornerRadii: RetainedCornerRadii?,
        displayScale: Double,
        to quad: inout QuadPrimitive
    ) {
        guard let cornerRadii, cornerRadii.hasPositiveRadius else {
            return
        }
        quad.cornerRadiusTopLeft = Float(max(0, cornerRadii.topLeft) * displayScale)
        quad.cornerRadiusTopRight = Float(max(0, cornerRadii.topRight) * displayScale)
        quad.cornerRadiusBottomRight = Float(max(0, cornerRadii.bottomRight) * displayScale)
        quad.cornerRadiusBottomLeft = Float(max(0, cornerRadii.bottomLeft) * displayScale)
    }

    private static func hasVisibleLinearGradient(_ gradient: GradientType?) -> Bool {
        guard case .linear(let linear) = gradient else { return false }
        return linear.stops.contains { $0.color.alpha > 0 }
    }

    /// One logical fill remains one contiguous run in presentation order;
    /// only authored intermediate or displaced stops need extra instances.
    private static func appendFillQuad(
        _ quad: QuadPrimitive,
        gradient: GradientType?,
        opacity: Float,
        into scene: inout GPUIScene,
        layerIndex: Int
    ) {
        guard case .linear(let linear) = gradient else {
            scene.addQuad(quad, toLayer: layerIndex)
            return
        }
        let segments = quad.segmented(for: linear, opacity: opacity)

        // A material draw snapshots and blurs everything already beneath it.
        // Replaying that full-footprint pass once per gradient interval would
        // blur the preceding interval into the next and multiply the work by
        // the stop count. Until one backdrop can be shared by the segments,
        // preserve the existing documented first/last-color material fallback.
        if segments.count > 1, GPUISceneValue.int(quad.blurRadius) > 0,
            let first = segments.first, let last = segments.last
        {
            var fallback = first
            fallback.endR = last.endR
            fallback.endG = last.endG
            fallback.endB = last.endB
            fallback.endA = last.endA
            fallback.gradientSegmentStart = 0
            fallback.gradientSegmentEnd = 0
            fallback.gradientSegmentMode = 0
            scene.addQuad(fallback, toLayer: layerIndex)
            return
        }

        for segment in segments {
            scene.addQuad(segment, toLayer: layerIndex)
        }
    }

    private static func fillQuad(
        rect: Rect,
        cornerRadius: Double,
        cornerRadii: RetainedCornerRadii? = nil,
        color: Color,
        gradient: GradientType?,
        opacity: Float,
        clip: Rect?,
        surfaceSize: Size,
        displayScale: Double,
        colorEffects: [RetainedColorEffect] = [],
        blurRadius: Float = 0,
        blurOpaque: Float = 0,
        clipCornerRadius: Double = 0,
        blendMode: BlendMode = .normal
    ) -> QuadPrimitive {
        guard case .linear(let gradient) = gradient else {
            return solidQuad(
                rect: rect,
                cornerRadius: cornerRadius,
                cornerRadii: cornerRadii,
                color: color,
                opacity: opacity,
                clip: clip,
                surfaceSize: surfaceSize,
                displayScale: displayScale,
                colorEffects: colorEffects,
                blurRadius: blurRadius,
                blurOpaque: blurOpaque,
                clipCornerRadius: clipCornerRadius,
                blendMode: blendMode
            )
        }

        let scaledRect = scaleRect(rect, by: displayScale)
        let clipR = clipRectFloats(clip, surfaceSize: surfaceSize, displayScale: displayScale)
        let endColor = gradient.endColor
        let axis: Float = gradient.axis == .horizontal ? 1 : 0
        let fx = encodeColorEffects(colorEffects)
        var quad = QuadPrimitive(
            x: Float(scaledRect.origin.x),
            y: Float(scaledRect.origin.y),
            width: Float(scaledRect.size.width),
            height: Float(scaledRect.size.height),
            cornerRadius: Float(cornerRadius * displayScale),
            startR: color.red, startG: color.green, startB: color.blue,
            startA: color.alpha * opacity,
            endR: endColor.red, endG: endColor.green, endB: endColor.blue,
            endA: endColor.alpha * opacity,
            gradientAxis: axis,
            clipX: clipR.0, clipY: clipR.1,
            clipWidth: clipR.2, clipHeight: clipR.3,
            clipCornerRadius: Float(clipCornerRadius * displayScale),
            blendMode: Float(blendMode.rawValue),
            effectType: fx.effectType,
            effectIntensity: fx.effectIntensity,
            blurRadius: blurRadius,
            blurOpaque: blurOpaque,
            effectParam1: fx.effectParam1,
            effectParam2: fx.effectParam2,
            effectParam3: fx.effectParam3,
            effectParam4: fx.effectParam4
        )
        applyPerCornerRadii(cornerRadii, displayScale: displayScale, to: &quad)
        return quad
    }

    // MARK: - Canvas

    /// Translate ``CanvasGraphicsContext`` operations recorded by a
    /// `Canvas { ctx, size in ... }` renderer into scene primitives.  Mirrors
    /// the ``CanvasGraphicsContext.appendCommands`` path used by
    /// ``RenderFrame``, so canvas content paints in both the default scene
    /// pipeline and the legacy frame fallback.
    private static func appendCanvasOperations(
        _ operations: [CanvasGraphicsContext.Operation],
        into scene: inout GPUIScene,
        origin: Point,
        baseClip: RuntimeClipShape?,
        placement: PaintPlacement,
        opacity: Float,
        layerIndex: Int,
        surfaceSize: Size,
        displayScale: Double,
        textSystem: WindowTextSystem,
        usedNativeGlyphs: inout Bool,
        usedPixelGlyphs: inout Bool
    ) {
        // The canvas keeps its own square push/pop clip stack; the enclosing
        // node's rounding still applies to whatever the canvas draws, resolved
        // by the same corner-survival rule every other emitter uses — so a
        // `Canvas` inside a rounded card is cut by the card arc until the
        // canvas narrows the clip away from it.
        //
        // R-ROT. Two clips, one region. `currentClip` is the screen-space
        // rejection rect the primitives carry; `currentCullClip` is that same
        // region expressed in the canvas's own drawing space, which is where
        // every operation's rect lives *before* `placement` turns it. Culling
        // a pre-rotation rect against the post-rotation clip is what erased a
        // `Canvas` drawn near the edge of a rotated card. The two are the same
        // rect for every node that is not rotated.
        var clipStack: [(emit: Rect?, cull: Rect?)] = []
        var currentClip = baseClip?.rect
        var currentCullClip = baseClip.map { placement.unplacedFootprint(of: $0.rect) }
        func clipRadius(_ quadRect: Rect) -> Double {
            baseClip.ancestorCornerRadius(
                forQuadRect: placement.footprint(of: quadRect), rejectingOutside: currentClip)
        }

        for operation in operations {
            switch operation {
            case .fillPath(let path, let color):
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0 else { continue }
                let translated = path.translated(by: origin)
                guard let bounds = translated.segments.boundingRect, !bounds.isEmpty else { continue }
                guard clipAllowsDrawing(clip: currentCullClip, rect: bounds) else { continue }
                Self.emit(
                    path: PathPrimitive(
                        elements: pathElements(from: translated.segments),
                        bounds: bounds,
                        fillColor: effectiveColor,
                        clipBounds: currentClip,
                        clipCornerRadius: clipRadius(bounds)
                    ), into: &scene, layerIndex: layerIndex, displayScale: displayScale,
                    placement: placement)

            case .fillPathGradient(let path, let gradient, let startPoint, let endPoint):
                guard opacity > 0, gradient.stops.contains(where: { $0.color.alpha > 0 }) else {
                    continue
                }
                let translated = path.translated(by: origin)
                guard let bounds = translated.segments.boundingRect, !bounds.isEmpty else { continue }
                guard clipAllowsDrawing(clip: currentCullClip, rect: bounds) else { continue }
                let effectiveGradient = canvasGradient(gradient, multipliedBy: opacity)
                var primitive = PathPrimitive(
                    elements: pathElements(from: translated.segments),
                    bounds: bounds,
                    fillColor: effectiveGradient.startColor,
                    fillGradient: effectiveGradient,
                    clipBounds: currentClip,
                    clipCornerRadius: clipRadius(bounds)
                )
                if let startPoint, let endPoint {
                    primitive.setGradientEndpoints(
                        start: Point(x: startPoint.x + origin.x, y: startPoint.y + origin.y),
                        end: Point(x: endPoint.x + origin.x, y: endPoint.y + origin.y)
                    )
                }
                Self.emit(
                    path: primitive, into: &scene, layerIndex: layerIndex, displayScale: displayScale,
                    placement: placement)

            case .strokePath(let path, let color, let style):
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0, style.lineWidth > 0 else { continue }
                let translated = path.translated(by: origin)
                // Strokes can have a zero-thickness path bounds (e.g. a
                // single horizontal line), so outset before the empty check
                // and use the inflated rect for clip/visibility tests.
                guard let pathBounds = translated.segments.boundingRect else { continue }
                let solidElements = pathElements(from: translated.segments)
                // `context.stroke(path, with: .color(c), style: .init(dash:
                // [4, 4]))` used to draw solid: the dash pattern had nowhere
                // to go, because the path contract carries no dashes and the
                // only dash resolver walked a rect perimeter. Resolve it into
                // geometry here, where the outline is still a `Path`.
                let strokeElements =
                    PathDashing.dashed(
                        solidElements, pattern: style.dashPattern, offset: style.dashOffset)
                    ?? solidElements
                let strokeBounds = pathBounds.outset(
                    by: StrokeOutlineGeometry.boundsOutset(
                        forElements: strokeElements, lineWidth: style.lineWidth, lineCap: style.lineCap,
                        lineJoin: style.lineJoin, miterLimit: style.miterLimit))
                guard !strokeBounds.isEmpty else { continue }
                guard clipAllowsDrawing(clip: currentCullClip, rect: strokeBounds) else { continue }
                Self.emit(
                    path: PathPrimitive(
                        elements: strokeElements,
                        bounds: strokeBounds,
                        strokeColor: effectiveColor,
                        lineWidth: style.lineWidth,
                        lineCap: style.lineCap,
                        lineJoin: style.lineJoin,
                        miterLimit: style.miterLimit,
                        clipBounds: currentClip,
                        clipCornerRadius: clipRadius(strokeBounds)
                    ), into: &scene, layerIndex: layerIndex, displayScale: displayScale,
                    placement: placement)

            case .strokePathGradient(let path, let gradient, let style, let startPoint, let endPoint):
                guard opacity > 0, style.lineWidth > 0,
                    gradient.stops.contains(where: { $0.color.alpha > 0 })
                else {
                    continue
                }
                let translated = path.translated(by: origin)
                guard let pathBounds = translated.segments.boundingRect else { continue }
                let solidElements = pathElements(from: translated.segments)
                let strokeElements =
                    PathDashing.dashed(
                        solidElements, pattern: style.dashPattern, offset: style.dashOffset)
                    ?? solidElements
                let strokeBounds = pathBounds.outset(
                    by: StrokeOutlineGeometry.boundsOutset(
                        forElements: strokeElements, lineWidth: style.lineWidth, lineCap: style.lineCap,
                        lineJoin: style.lineJoin, miterLimit: style.miterLimit))
                guard !strokeBounds.isEmpty else { continue }
                guard clipAllowsDrawing(clip: currentCullClip, rect: strokeBounds) else { continue }
                let effectiveGradient = canvasGradient(gradient, multipliedBy: opacity)
                var primitive = PathPrimitive(
                    elements: strokeElements,
                    bounds: strokeBounds,
                    strokeColor: effectiveGradient.startColor,
                    strokeGradient: effectiveGradient,
                    lineWidth: style.lineWidth,
                    lineCap: style.lineCap,
                    lineJoin: style.lineJoin,
                    miterLimit: style.miterLimit,
                    clipBounds: currentClip,
                    clipCornerRadius: clipRadius(strokeBounds)
                )
                if let startPoint, let endPoint {
                    primitive.setGradientEndpoints(
                        start: Point(x: startPoint.x + origin.x, y: startPoint.y + origin.y),
                        end: Point(x: endPoint.x + origin.x, y: endPoint.y + origin.y)
                    )
                }
                Self.emit(
                    path: primitive, into: &scene, layerIndex: layerIndex, displayScale: displayScale,
                    placement: placement)

            case .fillRect(let rect, let color):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0 else { continue }
                guard clipAllowsDrawing(clip: currentCullClip, rect: effectiveRect) else { continue }
                scene.addQuad(
                    placement.rotating(
                        solidQuad(
                            rect: effectiveRect,
                            cornerRadius: 0,
                            color: effectiveColor,
                            opacity: 1,
                            clip: currentClip,
                            surfaceSize: surfaceSize,
                            displayScale: displayScale,
                            clipCornerRadius: clipRadius(effectiveRect)
                        ), displayScale: displayScale), toLayer: layerIndex)

            case .fillRectGradient(let rect, let gradient):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                guard clipAllowsDrawing(clip: currentCullClip, rect: effectiveRect) else { continue }
                appendFillQuad(
                    placement.rotating(
                        fillQuad(
                            rect: effectiveRect,
                            cornerRadius: 0,
                            color: gradient.startColor,
                            gradient: .linear(gradient),
                            opacity: opacity,
                            clip: currentClip,
                            surfaceSize: surfaceSize,
                            displayScale: displayScale,
                            clipCornerRadius: clipRadius(effectiveRect)
                        ), displayScale: displayScale),
                    gradient: .linear(gradient), opacity: opacity,
                    into: &scene, layerIndex: layerIndex)

            case .strokeRect(let rect, let color, let lineWidth):
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0, lineWidth > 0 else { continue }
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                // A closed rect outline's miters reach exactly half a line
                // width past each corner on each axis, which is what the
                // outset already is.
                let strokeBounds = effectiveRect.outset(by: lineWidth / 2)
                guard clipAllowsDrawing(clip: currentCullClip, rect: strokeBounds) else { continue }
                let outline: [RenderPath.Segment] = [
                    .moveTo(Point(x: effectiveRect.minX, y: effectiveRect.minY)),
                    .lineTo(Point(x: effectiveRect.maxX, y: effectiveRect.minY)),
                    .lineTo(Point(x: effectiveRect.maxX, y: effectiveRect.maxY)),
                    .lineTo(Point(x: effectiveRect.minX, y: effectiveRect.maxY)),
                    .close,
                ]
                Self.emit(
                    path: PathPrimitive(
                        elements: pathElements(from: outline),
                        bounds: strokeBounds,
                        strokeColor: effectiveColor,
                        lineWidth: lineWidth,
                        clipBounds: currentClip,
                        clipCornerRadius: clipRadius(strokeBounds)
                    ), into: &scene, layerIndex: layerIndex, displayScale: displayScale,
                    placement: placement)

            case .drawText(let text, let rect, let style):
                // E6-TEXT residual. A `Canvas` closure is handed the *placed*
                // size and draws in that space, so its text rect is already
                // scaled and there is no untransformed box to lay out in: the
                // run keeps the placed rect and `rotating`, not `placingRun`.
                // Putting the canvas in local space is a change to what the
                // closure is handed, which is a `Canvas` semantics question,
                // not a text one — see `docs/GPURenderingPipeline.md`.
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveStyle = style.multipliedOpacity(by: opacity)
                guard clipAllowsDrawing(clip: currentCullClip, rect: effectiveRect) else { continue }
                var nativeGlyphs: [GlyphPrimitive] = []
                var pixelGlyphs: [GlyphPrimitive] = []
                var decorationQuads: [QuadPrimitive] = []
                appendTextGlyphs(
                    for: text,
                    style: effectiveStyle,
                    in: effectiveRect,
                    opacity: 1,
                    clip: currentClip,
                    cullClip: currentCullClip,
                    clipCornerRadius: clipRadius(effectiveRect),
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    textSystem: textSystem,
                    into: &nativeGlyphs,
                    pixelGlyphs: &pixelGlyphs,
                    decorationQuads: &decorationQuads
                )
                for glyph in nativeGlyphs {
                    scene.addGlyph(placement.rotating(glyph, displayScale: displayScale), toLayer: layerIndex)
                }
                for glyph in pixelGlyphs {
                    scene.addPixelGlyph(placement.rotating(glyph, displayScale: displayScale), toLayer: layerIndex)
                }
                for quad in decorationQuads {
                    scene.addQuad(placement.rotating(quad, displayScale: displayScale), toLayer: layerIndex)
                }
                usedNativeGlyphs = usedNativeGlyphs || !nativeGlyphs.isEmpty
                usedPixelGlyphs = usedPixelGlyphs || !pixelGlyphs.isEmpty

            case .drawImage(let bitmap, let rect, let imageOpacity):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveOpacity = opacity * imageOpacity
                guard effectiveOpacity > 0 else { continue }
                guard clipAllowsDrawing(clip: currentCullClip, rect: effectiveRect) else { continue }
                let scaledRect = scaleRect(effectiveRect, by: displayScale)
                let clipR = clipRectFloats(currentClip, surfaceSize: surfaceSize, displayScale: displayScale)
                let textureID = scene.registerImageResource(bitmap)
                scene.addImage(
                    placement.rotating(
                        ImagePrimitive(
                            screenX: Float(scaledRect.origin.x),
                            screenY: Float(scaledRect.origin.y),
                            screenW: Float(scaledRect.size.width),
                            screenH: Float(scaledRect.size.height),
                            opacity: effectiveOpacity,
                            clipX: clipR.0,
                            clipY: clipR.1,
                            clipWidth: clipR.2,
                            clipHeight: clipR.3,
                            clipCornerRadius: Float(clipRadius(effectiveRect) * displayScale),
                            textureID: textureID
                        ), displayScale: displayScale), toLayer: layerIndex)

            case .pushClip(let rect):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                clipStack.append((currentClip, currentCullClip))
                // The pushed rect is in the canvas's drawing space, so it
                // narrows the cull clip directly and the screen-space clip
                // through its turned footprint.
                let screenRect = placement.footprint(of: effectiveRect)
                currentClip = currentClip.map { $0.intersected(with: screenRect) } ?? screenRect
                currentCullClip = currentCullClip.map { $0.intersected(with: effectiveRect) } ?? effectiveRect

            case .popClip:
                let restored = clipStack.popLast()
                currentClip = restored?.emit ?? baseClip?.rect
                currentCullClip = restored?.cull ?? baseClip.map { placement.unplacedFootprint(of: $0.rect) }
            }
        }
    }

    private static func canvasGradient(
        _ gradient: LinearGradient,
        multipliedBy opacity: Float
    ) -> LinearGradient {
        LinearGradient(
            stops: gradient.stops.map {
                GradientStop(color: $0.color.multipliedAlpha(by: opacity), position: $0.position)
            },
            axis: gradient.axis,
            reversesAuthoredStops: gradient.reversesAuthoredStops
        )
    }

    private static func pathElements(from segments: [RenderPath.Segment]) -> [PathElement] {
        segments.map { segment in
            switch segment {
            case .moveTo(let p):
                return .moveTo(p)
            case .lineTo(let p):
                return .lineTo(p)
            case .quadCurveTo(let c, let e):
                return .quadraticCurveTo(control: c, end: e)
            case .cubicCurveTo(let c1, let c2, let e):
                return .cubicCurveTo(control1: c1, control2: c2, end: e)
            case .arc(let c, let r, let s, let e, let cw):
                return .arc(center: c, radius: r, startAngle: s, endAngle: e, clockwise: cw)
            case .close:
                return .close
            }
        }
    }

    // MARK: - Color Effects

    /// Encode the first supported ``RetainedColorEffect`` into primitive
    /// shader fields.  Only one effect per primitive is supported today;
    /// additional effects are dropped.
    internal static func encodeColorEffects(_ effects: [RetainedColorEffect]) -> (
        effectType: Float, effectIntensity: Float, effectParam1: Float, effectParam2: Float, effectParam3: Float,
        effectParam4: Float
    ) {
        guard let first = effects.first else {
            return (0, 0, 0, 0, 0, 0)
        }
        switch first {
        case .brightness(let amount):
            return (1, Float(amount), 0, 0, 0, 0)
        case .contrast(let amount):
            return (2, Float(amount), 0, 0, 0, 0)
        case .saturation(let amount):
            return (3, Float(amount), 0, 0, 0, 0)
        case .grayscale(let amount):
            return (4, Float(amount), 0, 0, 0, 0)
        case .colorInvert:
            return (5, 0, 0, 0, 0, 0)
        case .hueRotation(let angle):
            return (6, 0, Float(angle), 0, 0, 0)
        case .colorMultiply(let color):
            return (7, 0, color.red, color.green, color.blue, 0)
        case .luminanceToAlpha:
            return (8, 0, 0, 0, 0, 0)
        }
    }

    private static func clipAllowsDrawing(clip: Rect?, rect: Rect) -> Bool {
        guard let clip = clip else { return true }
        return clip.intersected(with: rect) != nil
    }

    private static func clipAllowsDrawing(clip: RuntimeClipShape?, rect: Rect) -> Bool {
        clip.allowsDrawing(rect)
    }

    /// Converts a clip shape's rejection rect into four Float values for
    /// primitive clip fields. The shape's *rounding* is lowered separately,
    /// per primitive, by `RuntimeClipShape.resolvedCornerRadius(forQuadRect:)`.
    private static func clipRectFloats(_ clip: RuntimeClipShape?, surfaceSize: Size, displayScale: Double) -> (
        Float, Float, Float, Float
    ) {
        clipRectFloats(clip?.rect, surfaceSize: surfaceSize, displayScale: displayScale)
    }

    /// Converts an optional clip Rect into four Float values for primitive clip fields.
    private static func clipRectFloats(_ clip: Rect?, surfaceSize: Size, displayScale: Double) -> (
        Float, Float, Float, Float
    ) {
        if let c = clip {
            let scaledClip = scaleRect(c, by: displayScale)
            return (
                Float(scaledClip.origin.x),
                Float(scaledClip.origin.y),
                Float(scaledClip.size.width),
                Float(scaledClip.size.height)
            )
        }
        return (0, 0, Float(surfaceSize.width), Float(surfaceSize.height))
    }

    private static func appendDeferredDraws(
        _ deferredDraws: inout [DeferredDrawState],
        into scene: inout GPUIScene,
        previousScene: GPUIScene?,
        surfaceSize: Size,
        displayScale: Double,
        textSystem: WindowTextSystem,
        usedNativeGlyphs: inout Bool,
        usedPixelGlyphs: inout Bool,
        replayCount: inout Int
    ) {
        for deferredDrawIndex in deferredDraws.indices.sorted(by: { lhs, rhs in
            let left = deferredDraws[lhs]
            let right = deferredDraws[rhs]
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return lhs < rhs
        }) {
            // An isolation pass may have drawn this entry into its own
            // bitmap already (a pinned header inside a `.blur()`ed subtree).
            // Drawing it again here would put a sharp copy on top of the
            // blurred one.
            guard !deferredDraws[deferredDrawIndex].isDrawnInline else { continue }
            // …and the pass may have run on an *earlier* frame, with a clean
            // ancestor replaying its cached range this one: the bitmap is in
            // the scene, the blurred node was never visited, and nothing
            // claimed this entry. Same conclusion, reached from the node side.
            if isDrawnByAnAncestorsContentBlurBitmap(deferredDraws[deferredDrawIndex].payload) {
                deferredDraws[deferredDrawIndex].isDrawnInline = true
                // It did not draw into this scene, so any range it carries
                // describes a scene it is not in.
                deferredDraws[deferredDrawIndex].cachedScenePaintRange = nil
                continue
            }
            let startPaintRecord = scene.paintRecordCount
            if let previousScene, let cachedScenePaintRange = deferredDraws[deferredDrawIndex].cachedScenePaintRange {
                switch scene.replay(cachedScenePaintRange, from: previousScene) {
                case .success:
                    deferredDraws[deferredDrawIndex].cachedScenePaintRange = startPaintRecord..<scene.paintRecordCount
                    replayCount += 1
                    continue
                case .invalidRange, .unbalanced:
                    // Same rule as the node cache: a rejected replay added
                    // nothing, so drop the range and repaint the overlay
                    // rather than caching the emptiness.
                    reportRejectedReplay()
                    deferredDraws[deferredDrawIndex].cachedScenePaintRange = nil
                }
            }

            switch deferredDraws[deferredDrawIndex].payload {
            case .scrollIndicator:
                let contentMask = deferredDraws[deferredDrawIndex].contentMask
                let fillRect = deferredDraws[deferredDrawIndex].payload.fillRectCommand(
                    contentMask: contentMask?.rect
                )
                appendFillQuad(
                    quad(
                        for: fillRect, surfaceSize: surfaceSize, displayScale: displayScale,
                        clipCornerRadius: contentMask.resolvedCornerRadius(forQuadRect: fillRect.rect)),
                    gradient: fillRect.gradient, opacity: 1,
                    into: &scene, layerIndex: 0
                )
            case .subtree(let payload):
                guard let node = payload.node else {
                    deferredDraws[deferredDrawIndex].cachedScenePaintRange = startPaintRecord..<startPaintRecord
                    continue
                }
                paintNode(
                    node,
                    into: &scene,
                    deferredDraws: &deferredDraws,
                    parentOrigin: payload.parentOrigin,
                    inheritedClip: payload.inheritedClip,
                    layerIndex: 0,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    textSystem: textSystem,
                    previousScene: previousScene,
                    primitiveOpacity: payload.inheritedOpacity,
                    inheritedColorEffects: payload.inheritedColorEffects,
                    inheritedBlendMode: payload.inheritedBlendMode,
                    usedNativeGlyphs: &usedNativeGlyphs,
                    usedPixelGlyphs: &usedPixelGlyphs,
                    replayCount: &replayCount,
                    inheritedTransform: payload.inheritedTransform
                )
            }

            deferredDraws[deferredDrawIndex].cachedScenePaintRange = startPaintRecord..<scene.paintRecordCount
        }
    }

    private static func quad(
        for command: FillRectCommand,
        surfaceSize: Size,
        displayScale: Double,
        colorEffects: [RetainedColorEffect] = [],
        clipCornerRadius: Double = 0
    ) -> QuadPrimitive {
        let scaledRect = scaleRect(command.rect, by: displayScale)
        let clipR = clipRectFloats(command.clipRect, surfaceSize: surfaceSize, displayScale: displayScale)

        let startColor: Color
        let endColor: Color
        let axis: Float

        switch command.gradient {
        case .linear(let gradient):
            startColor = gradient.startColor
            endColor = gradient.endColor
            axis = gradient.axis == .horizontal ? 1 : 0
        default:
            startColor = command.color
            endColor = command.color
            axis = 0
        }

        let fx = encodeColorEffects(colorEffects)
        return QuadPrimitive(
            x: Float(scaledRect.origin.x),
            y: Float(scaledRect.origin.y),
            width: Float(scaledRect.size.width),
            height: Float(scaledRect.size.height),
            cornerRadius: Float(command.cornerRadius * displayScale),
            startR: startColor.red,
            startG: startColor.green,
            startB: startColor.blue,
            startA: startColor.alpha,
            endR: endColor.red,
            endG: endColor.green,
            endB: endColor.blue,
            endA: endColor.alpha,
            gradientAxis: axis,
            clipX: clipR.0,
            clipY: clipR.1,
            clipWidth: clipR.2,
            clipHeight: clipR.3,
            clipCornerRadius: Float(clipCornerRadius * displayScale),
            blendMode: Float(command.blendMode.rawValue),
            effectType: fx.effectType,
            effectIntensity: fx.effectIntensity,
            effectParam1: fx.effectParam1,
            effectParam2: fx.effectParam2,
            effectParam3: fx.effectParam3,
            effectParam4: fx.effectParam4
        )
    }

    /// `cullClip` is the clip the *layout* is compared against, which is not
    /// always the clip the primitives carry: a run inside a transformed
    /// subtree is laid out in the node's own untransformed space and placed
    /// afterwards, so it has to be culled against the preimage of the
    /// screen-space clip (`PaintPlacement.unplacedRunFootprint`) or the
    /// placement drops glyphs it would have brought into view. For every
    /// axis-aligned caller the two are the same rect.
    ///
    /// `contentScale` is the uniform scale the caller will apply to the
    /// finished run. It never reaches the *layout* — that is the point, and
    /// `rect` is already the untransformed box — it only chooses the pixel
    /// size the glyphs are rasterized at, so a scaled run is crisp instead of
    /// a stretched 1x raster. The cells come back in the untransformed space
    /// at device resolution either way.
    private static func appendTextGlyphs(
        for text: String,
        style: PixelTextStyle,
        in rect: Rect,
        opacity: Float,
        clip: Rect?,
        cullClip: Rect?,
        clipCornerRadius: Double = 0,
        surfaceSize: Size,
        displayScale: Double,
        contentScale: Double = 1,
        textSystem: WindowTextSystem,
        into glyphs: inout [GlyphPrimitive],
        pixelGlyphs: inout [GlyphPrimitive],
        decorationQuads: inout [QuadPrimitive]
    ) {
        guard !text.isEmpty, style.color.alpha > 0 else {
            return
        }

        let contentRect = rect.inset(by: style.insets)
        guard contentRect.size.width > 0, contentRect.size.height > 0 else {
            return
        }

        if appendNativeTextGlyphs(
            for: text,
            style: style,
            in: rect,
            opacity: opacity,
            clip: clip,
            cullClip: cullClip,
            clipCornerRadius: clipCornerRadius,
            surfaceSize: surfaceSize,
            displayScale: displayScale,
            contentScale: contentScale,
            textSystem: textSystem,
            into: &glyphs,
            decorationQuads: &decorationQuads
        ) {
            return
        }

        // Everything below draws through the 5x7 bitmap atlas, which uppercases
        // its input and maps anything outside A-Z/0-9 and a handful of symbols
        // to "?". That is a severe, silent quality cliff; count it.
        TextRenderDiagnosticsCounters.pixelFontFallbacks += 1

        let effectiveStyle = style.resolvingMinimumScaleFactor(
            for: text,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: { line in
                PixelFont.rawLineWidth(line, letterSpacing: style.letterSpacing) * max(style.scale, 0.01)
            }
        )
        let scale = max(effectiveStyle.scale, 0.01)
        let layout = resolveTextLayout(
            for: text,
            style: effectiveStyle,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: { line in PixelFont.rawLineWidth(line, letterSpacing: effectiveStyle.letterSpacing) * scale }
        )
        let reservedLineCount = reservedTextLineCount(for: effectiveStyle)
        let verticalLineCount = max(max(layout.lines.count, 1), reservedLineCount ?? 0)
        let totalTextHeight = pixelTextContentHeight(
            lineCount: verticalLineCount,
            style: effectiveStyle,
            scale: scale
        )

        let startY: Double
        switch effectiveStyle.verticalAlignment {
        case .top:
            startY = contentRect.origin.y
        case .center:
            startY = contentRect.origin.y + max(0, (contentRect.size.height - totalTextHeight) * 0.5)
        case .bottom:
            startY = contentRect.maxY - totalTextHeight
        }

        let clipRect = clipRectFloats(clip, surfaceSize: surfaceSize, displayScale: displayScale)
        let scaledVisibleClip = cullClip.map { scaleRect($0, by: displayScale) }
        let glyphWidth = Double(PixelFontAtlas.glyphWidth) * scale * displayScale
        let glyphHeight = Double(PixelFontAtlas.glyphHeight) * scale * displayScale
        let horizontalAdvance =
            (Double(PixelFontAtlas.glyphWidth) + effectiveStyle.letterSpacing) * scale * displayScale
        let verticalAdvance =
            (Double(PixelFontAtlas.glyphHeight) * scale + effectiveStyle.lineSpacing * scale) * displayScale
        var cursorY = startY * displayScale

        for line in layout.lines {
            let lineWidth = PixelFont.rawLineWidth(line, letterSpacing: effectiveStyle.letterSpacing) * scale
            let startX: Double
            switch effectiveStyle.alignment {
            case .leading:
                startX = contentRect.origin.x
            case .center:
                startX = contentRect.origin.x + max(0, (contentRect.size.width - lineWidth) * 0.5)
            case .trailing:
                startX = contentRect.maxX - lineWidth
            }

            var cursorX = startX * displayScale
            for character in line.uppercased() {
                defer {
                    cursorX += horizontalAdvance
                }

                guard character != " " else {
                    continue
                }

                let glyphRect = Rect(
                    x: cursorX,
                    y: cursorY,
                    width: glyphWidth,
                    height: glyphHeight
                )
                if let scaledVisibleClip, scaledVisibleClip.intersected(with: glyphRect) == nil {
                    continue
                }

                let atlas = PixelFontAtlas.shared
                let entry = PixelFontAtlas.glyph(for: character)
                let uv = entry.uvRect(atlasWidth: atlas.surface.width, atlasHeight: atlas.surface.height)
                pixelGlyphs.append(
                    GlyphPrimitive(
                        screenX: Float(cursorX),
                        screenY: Float(cursorY),
                        screenW: Float(glyphWidth),
                        screenH: Float(glyphHeight),
                        atlasU0: uv.u0,
                        atlasV0: uv.v0,
                        atlasU1: uv.u1,
                        atlasV1: uv.v1,
                        colorR: effectiveStyle.color.red,
                        colorG: effectiveStyle.color.green,
                        colorB: effectiveStyle.color.blue,
                        colorA: effectiveStyle.color.alpha * opacity,
                        clipX: clipRect.0,
                        clipY: clipRect.1,
                        clipWidth: clipRect.2,
                        clipHeight: clipRect.3,
                        clipCornerRadius: Float(clipCornerRadius * displayScale)
                    )
                )
            }

            appendTextDecorationQuads(
                lineRect: Rect(
                    x: startX,
                    y: cursorY / displayScale,
                    width: lineWidth,
                    height: Double(PixelFontAtlas.glyphHeight) * scale
                ),
                style: effectiveStyle,
                opacity: opacity,
                clip: clip,
                cullClip: cullClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale,
                into: &decorationQuads
            )
            cursorY += verticalAdvance
        }
    }

    private static func appendNativeTextGlyphs(
        for text: String,
        style: PixelTextStyle,
        in rect: Rect,
        opacity: Float,
        clip: Rect?,
        cullClip: Rect?,
        clipCornerRadius: Double = 0,
        surfaceSize: Size,
        displayScale: Double,
        contentScale: Double = 1,
        textSystem: WindowTextSystem,
        into glyphs: inout [GlyphPrimitive],
        decorationQuads: inout [QuadPrimitive]
    ) -> Bool {
        guard !text.unicodeScalars.contains(where: isPrivateUseScalar) else {
            return false
        }

        let contentRect = rect.inset(by: style.insets)
        guard contentRect.size.width > 0, contentRect.size.height > 0 else {
            return false
        }
        guard
            let layout = textSystem.layout(
                text, style: style, maxWidth: contentRect.size.width, scaleFactor: displayScale)
        else {
            return false
        }

        let totalTextHeight = layout.contentSize.height
        let baseY: Double
        switch style.verticalAlignment {
        case .top:
            baseY = contentRect.origin.y
        case .center:
            baseY = contentRect.origin.y + max(0, (contentRect.size.height - totalTextHeight) * 0.5)
        case .bottom:
            baseY = contentRect.maxY - totalTextHeight
        }
        let clipRect = clipRectFloats(clip, surfaceSize: surfaceSize, displayScale: displayScale)
        let scaledVisibleClip = cullClip.map { scaleRect($0, by: displayScale) }
        // E6-TEXT. The run is laid out and emitted in the node's untransformed
        // space, but it is *rasterized* for the size it will end up drawn at:
        // `rasterScale` is the atlas rung nearest the caller's `contentScale`
        // (see `NativeGlyphAtlas.glyphRasterScale`). The cells then come back
        // in untransformed space by dividing the raster's pixel metrics by the
        // rung — `placingRun` multiplies by the true scale, so the net cell is
        // `metric × contentScale / rasterScale`, i.e. exactly the right size
        // drawn from the nearest crisp raster. Both factors are `1` for every
        // untransformed run, which is the bit-identical path.
        let rasterScale = NativeGlyphAtlas.glyphRasterScale(for: contentScale)
        let rasterScaleFactor = displayScale * rasterScale
        let cellScale = 1 / rasterScale
        var appendedGlyphs: [GlyphPrimitive] = []
        var appendedDecorationQuads: [QuadPrimitive] = []
        var lineOriginY = baseY

        for line in layout.lines {
            let startX: Double
            switch style.alignment {
            case .leading:
                startX = contentRect.origin.x
            case .center:
                startX = contentRect.origin.x + max(0, (contentRect.size.width - line.width) * 0.5)
            case .trailing:
                startX = contentRect.maxX - line.width
            }

            for glyph in line.glyphs where shouldRenderNativeGlyph(glyph) {
                // Two anchors, because the two rasterizers measure ink from two
                // different places (see `GlyphVerticalFrame`). A shaped glyph's
                // `origin.y` is its baseline; the hit-test walk's is the line
                // top. Whichever frame the *raster* came back in is the one the
                // destination is computed against, so a raster that fell back
                // to the other path lands right instead of one ascent low.
                let glyphLayoutX = (startX + glyph.origin.x) * displayScale
                let lineTopY = lineOriginY * displayScale
                let baselineY =
                    glyph.verticalFrame == .baseline
                    ? (lineOriginY + glyph.origin.y) * displayScale
                    : (lineOriginY + line.ascent) * displayScale
                let glyphLayoutOrigin = Point(x: glyphLayoutX, y: baselineY)
                if let scaledVisibleClip,
                    let preflightRect = nativeGlyphPreflightRect(
                        for: glyph,
                        origin: Point(x: glyphLayoutX, y: baselineY),
                        lineTopY: lineTopY,
                        scaleFactor: displayScale
                    ),
                    scaledVisibleClip.intersected(with: preflightRect) == nil
                {
                    continue
                }

                guard
                    let preparedGlyph = NativeGlyphAtlas.shared.prepareGlyph(
                        for: glyph, style: style, scaleFactor: rasterScaleFactor),
                    let previewEntry = preparedGlyph.previewEntry
                else {
                    continue
                }
                guard previewEntry.width > 0, previewEntry.height > 0 else {
                    continue
                }
                let anchorY = previewEntry.verticalFrame == .baseline ? baselineY : lineTopY

                // Snap glyph destination to integer device pixels.  Without
                // this, the rasterizer's tx/ty mapping reads the same atlas
                // pixel from two adjacent destination pixels when the origin
                // is fractional, producing the classic doubled-letter smear
                // pattern.  Pixel-aligned glyphs render crisp 1:1 from atlas.
                //
                // Only for a run that lands on the device grid, though: a run
                // under a scale is placed by `placingRun` afterwards, so
                // snapping *here* snaps a pre-image and lands the cell off the
                // grid by the scale factor anyway — while quantising the run's
                // internal spacing at the wrong resolution. A scaled run is
                // resampled by construction; it keeps its exact metrics.
                let unsnapped = Point(
                    x: glyphLayoutOrigin.x + Double(previewEntry.bearingX) * cellScale,
                    y: anchorY + Double(previewEntry.bearingY) * cellScale
                )
                let destinationOrigin =
                    rasterScale == 1 && contentScale == 1
                    ? Point(x: unsnapped.x.rounded(), y: unsnapped.y.rounded())
                    : unsnapped
                guard destinationOrigin.x.isFinite, destinationOrigin.y.isFinite else {
                    continue
                }
                let glyphRect = Rect(
                    x: destinationOrigin.x,
                    y: destinationOrigin.y,
                    width: Double(previewEntry.width) * cellScale,
                    height: Double(previewEntry.height) * cellScale
                )
                if let scaledVisibleClip, scaledVisibleClip.intersected(with: glyphRect) == nil {
                    continue
                }
                guard let entry = NativeGlyphAtlas.shared.commitPreparedGlyph(preparedGlyph) else {
                    continue
                }
                let atlasSize = NativeGlyphAtlas.shared.size
                let uv = entry.uvRect(atlasWidth: atlasSize.width, atlasHeight: atlasSize.height)
                appendedGlyphs.append(
                    GlyphPrimitive(
                        screenX: Float(destinationOrigin.x),
                        screenY: Float(destinationOrigin.y),
                        screenW: Float(Double(entry.width) * cellScale),
                        screenH: Float(Double(entry.height) * cellScale),
                        atlasU0: uv.u0,
                        atlasV0: uv.v0,
                        atlasU1: uv.u1,
                        atlasV1: uv.v1,
                        colorR: style.color.red,
                        colorG: style.color.green,
                        colorB: style.color.blue,
                        colorA: style.color.alpha * opacity,
                        clipX: clipRect.0,
                        clipY: clipRect.1,
                        clipWidth: clipRect.2,
                        clipHeight: clipRect.3,
                        clipCornerRadius: Float(clipCornerRadius * displayScale)
                    )
                )
            }

            appendTextDecorationQuads(
                lineRect: Rect(
                    x: startX,
                    y: lineOriginY,
                    width: line.width,
                    height: line.height
                ),
                style: style,
                opacity: opacity,
                clip: clip,
                cullClip: cullClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale,
                into: &appendedDecorationQuads
            )
            lineOriginY += line.height + layout.lineSpacing
        }

        guard !appendedGlyphs.isEmpty else {
            return false
        }

        glyphs.append(contentsOf: appendedGlyphs)
        decorationQuads.append(contentsOf: appendedDecorationQuads)
        return true
    }

    private static func appendTextDecorationQuads(
        lineRect: Rect,
        style: PixelTextStyle,
        opacity: Float,
        clip: Rect?,
        cullClip: Rect?,
        surfaceSize: Size,
        displayScale: Double,
        into quads: inout [QuadPrimitive]
    ) {
        guard lineRect.size.width > 0, lineRect.size.height > 0 else {
            return
        }

        let thickness = max(1 / max(displayScale, 1), min(lineRect.size.height, max(1, lineRect.size.height * 0.08)))
        if style.underline {
            appendDecorationQuad(
                lineRect: lineRect,
                y: min(lineRect.maxY - thickness, lineRect.origin.y + lineRect.size.height * 0.86),
                thickness: thickness,
                color: style.underlineColor ?? style.color,
                pattern: style.underlinePattern,
                opacity: opacity,
                clip: clip,
                cullClip: cullClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale,
                into: &quads
            )
        }

        if style.strikethrough {
            appendDecorationQuad(
                lineRect: lineRect,
                y: lineRect.origin.y + max(0, (lineRect.size.height - thickness) * 0.52),
                thickness: thickness,
                color: style.strikethroughColor ?? style.color,
                pattern: style.strikethroughPattern,
                opacity: opacity,
                clip: clip,
                cullClip: cullClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale,
                into: &quads
            )
        }
    }

    private static func appendDecorationQuad(
        lineRect: Rect,
        y: Double,
        thickness: Double,
        color: Color,
        pattern: TextDecorationPattern,
        opacity: Float,
        clip: Rect?,
        cullClip: Rect?,
        surfaceSize: Size,
        displayScale: Double,
        into quads: inout [QuadPrimitive]
    ) {
        guard color.alpha > 0 else {
            return
        }

        for rect in decorationSegments(lineRect: lineRect, y: y, thickness: thickness, pattern: pattern) {
            guard clipAllowsDrawing(clip: cullClip, rect: rect) else {
                continue
            }

            quads.append(
                solidQuad(
                    rect: rect,
                    cornerRadius: 0,
                    color: color,
                    opacity: opacity,
                    clip: clip,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale
                )
            )
        }
    }

    private static func decorationSegments(
        lineRect: Rect,
        y: Double,
        thickness: Double,
        pattern: TextDecorationPattern
    ) -> [Rect] {
        guard lineRect.size.width > 0 else {
            return []
        }
        guard pattern != .solid else {
            return [Rect(x: lineRect.origin.x, y: y, width: lineRect.size.width, height: thickness)]
        }

        let unit = max(thickness, 1)
        let sequence: [(draw: Bool, length: Double)] = decorationSequence(for: pattern, unit: unit)
        var segments: [Rect] = []
        var x = lineRect.origin.x
        var index = 0
        while x < lineRect.maxX {
            let item = sequence[index % sequence.count]
            let width = min(item.length, lineRect.maxX - x)
            if item.draw, width > 0 {
                segments.append(Rect(x: x, y: y, width: width, height: thickness))
            }
            x += max(width, 0.01)
            index += 1
        }
        return segments
    }

    private static func decorationSequence(for pattern: TextDecorationPattern, unit: Double) -> [(
        draw: Bool, length: Double
    )] {
        switch pattern {
        case .solid:
            return [(true, Double.greatestFiniteMagnitude)]
        case .dot:
            return [(true, unit), (false, unit)]
        case .dash:
            return [(true, unit * 4), (false, unit * 2)]
        case .dashDot:
            return [(true, unit * 4), (false, unit * 1.5), (true, unit), (false, unit * 1.5)]
        case .dashDotDot:
            return [
                (true, unit * 4),
                (false, unit * 1.5),
                (true, unit),
                (false, unit * 1.5),
                (true, unit),
                (false, unit * 1.5),
            ]
        }
    }

    /// Conservative device-space bound for a glyph that has not been rastered
    /// yet, used only to cull. It spans both possible anchors - baseline and
    /// line top - because which one the raster will report is not known until
    /// the raster exists, and a cull that guesses wrong drops visible text.
    private static func nativeGlyphPreflightRect(
        for glyph: NativeTextGlyphLayout,
        origin: Point,
        lineTopY: Double,
        scaleFactor: Double
    ) -> Rect? {
        guard let metrics = makeCapturedGlyphRasterMetrics(for: glyph, scaleFactor: scaleFactor) else {
            return nil
        }

        let baselineAnchoredTop =
            origin.y - Double(metrics.paddingPixels) - metrics.baselineYOffset * metrics.renderScale
        let lineTopAnchoredTop = lineTopY - Double(metrics.paddingPixels)
        let top = min(baselineAnchoredTop, lineTopAnchoredTop)
        let bottom = max(baselineAnchoredTop, lineTopAnchoredTop) + Double(metrics.targetHeight)

        return Rect(
            x: origin.x - Double(metrics.paddingPixels),
            y: top,
            width: Double(metrics.targetWidth),
            height: max(0, bottom - top)
        )
    }

    private static func shouldRenderNativeGlyph(_ glyph: NativeTextGlyphLayout) -> Bool {
        glyph.character != " " || glyph.sourceIndex == nil
    }

    /// Emits the keyboard focus ring as an annulus around `quadFrame`.
    ///
    /// Out of line, and deliberately so: the paint loop it is called from is
    /// the deepest frame in the traversal, and a ring walk needs a segment
    /// array plus per-corner arc state. Kept here, the loop gains a call and
    /// not a hundred bytes of stack per level.
    @inline(never)
    private static func appendFocusRing(
        node: ViewNode,
        quadFrame: Rect,
        placement: PaintPlacement,
        opacity: Float,
        inheritedClip: RuntimeClipShape?,
        colorEffects: [RetainedColorEffect],
        layerIndex: Int,
        into scene: inout GPUIScene,
        surfaceSize: Size,
        displayScale: Double
    ) {
        let ringFrame = quadFrame.outset(by: node.outlineWidth)
        // The ring's own radius follows the control's, widened by the ring so
        // the outer edge stays concentric with the bezel.
        let outerRadius = (node.cornerRadii?.maxRadius ?? node.cornerRadius) + node.outlineWidth
        let segments = BorderSegments.solidSegments(
            frame: ringFrame,
            width: node.outlineWidth,
            cornerRadius: outerRadius
        )
        // A degenerate walk (zero perimeter) must not silently drop the ring;
        // fall back to the rect the ring would have covered.
        guard !segments.isEmpty else {
            scene.addQuad(
                placement.rotating(
                    solidQuad(
                        rect: ringFrame,
                        cornerRadius: outerRadius,
                        color: node.outlineColor,
                        opacity: opacity,
                        clip: inheritedClip?.rect,
                        surfaceSize: surfaceSize,
                        displayScale: displayScale,
                        colorEffects: colorEffects
                    ), displayScale: displayScale), toLayer: layerIndex)
            return
        }

        for segment in segments
        where clipAllowsDrawing(clip: inheritedClip, rect: placement.footprint(of: segment.rect)) {
            scene.addQuad(
                placement.rotating(
                    solidQuad(
                        rect: segment.rect,
                        cornerRadius: segment.cornerRadius,
                        color: node.outlineColor,
                        opacity: opacity,
                        clip: inheritedClip?.rect,
                        surfaceSize: surfaceSize,
                        displayScale: displayScale,
                        colorEffects: colorEffects
                    ), displayScale: displayScale), toLayer: layerIndex)
        }
    }

    /// Whether `node`'s own decoration is pinned to the device pixel grid.
    ///
    /// Only nodes the runtime has marked as separator rules, and only when
    /// they are axis-aligned leaves. A rotated or scaled rule has no device
    /// axis to pin to, and a rule with children would drag its own paint off
    /// the frame its children are placed against.
    static func snapsRuleToDevicePixels(_ node: ViewNode, placement: PaintPlacement) -> Bool {
        node.isSeparatorRule && node.children.isEmpty && !placement.isRotated && !placement.isScaled
    }

    /// Pins a hairline rule to whole device pixels along its thin axis.
    ///
    /// ## Why a rule needs this
    ///
    /// Both backends rasterize a quad with the same rule: the pixel shader
    /// runs only where a pixel *centre* falls inside the rect, and the
    /// signed-distance term inside it can attenuate that coverage but never
    /// extend it (the D3D11 vertex stage emits the rect itself, with no
    /// antialiasing margin, and `GPUIQuadCoverage.geometryCovers` mirrors
    /// that exactly). So a rect one device pixel thick sitting on a half
    /// pixel — device y `12.5 ..< 13.5` — contains exactly one pixel centre,
    /// at distance 0 from its edge, and draws at coverage `0.5`. Half the
    /// rule's ink is not redistributed to the neighbouring row; it is simply
    /// gone, and the separator renders at half its intended weight.
    ///
    /// At 100% and 200% that almost never happens, because a layout in whole
    /// points lands on whole device pixels. At 125%, 150% and 175% it is the
    /// common case: 10pt × 1.25 is 12.5. That is the whole reason hairline
    /// weight looked inconsistent between integer and fractional scales.
    ///
    /// ## The policy
    ///
    /// The thin axis is snapped so the rule spans whole device pixels:
    /// the extent rounds to the nearest whole pixel with a floor of one (a
    /// rule never vanishes), and the origin is placed so the snapped span
    /// keeps the rule's centre — it moves by at most half a device pixel from
    /// where layout put it, and never changes which side of anything it is
    /// on. The long axis is left exactly as laid out: its ends are covered by
    /// whatever it runs between, and rounding them would shorten a rule that
    /// is supposed to reach the edge.
    ///
    /// This is a *paint*-time pin. The node's layout frame is untouched, so
    /// no sibling moves and no container re-measures.
    static func devicePixelSnappedRule(_ rect: Rect, displayScale: Double) -> Rect {
        guard displayScale.isFinite, displayScale > 0,
            rect.size.width.isFinite, rect.size.height.isFinite,
            rect.origin.x.isFinite, rect.origin.y.isFinite
        else {
            return rect
        }

        func snap(origin: Double, extent: Double) -> (origin: Double, extent: Double) {
            let deviceOrigin = origin * displayScale
            let deviceExtent = extent * displayScale
            let snappedExtent = max(1, deviceExtent.rounded())
            let snappedOrigin = (deviceOrigin + deviceExtent * 0.5 - snappedExtent * 0.5).rounded()
            return (snappedOrigin / displayScale, snappedExtent / displayScale)
        }

        if rect.size.height <= rect.size.width {
            let (y, height) = snap(origin: rect.origin.y, extent: rect.size.height)
            return Rect(x: rect.origin.x, y: y, width: rect.size.width, height: height)
        }
        let (x, width) = snap(origin: rect.origin.x, extent: rect.size.width)
        return Rect(x: x, y: rect.origin.y, width: width, height: rect.size.height)
    }

    private static func scaleRect(_ rect: Rect, by factor: Double) -> Rect {
        Rect(
            x: rect.origin.x * factor,
            y: rect.origin.y * factor,
            width: rect.size.width * factor,
            height: rect.size.height * factor
        )
    }

    private static func isPrivateUseScalar(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        return (0xE000...0xF8FF).contains(value)
            || (0xF0000...0xFFFFD).contains(value)
            || (0x100000...0x10FFFD).contains(value)
    }
}
