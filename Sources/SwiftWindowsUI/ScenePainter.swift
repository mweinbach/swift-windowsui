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
    internal static func emit(
        path logicalPath: PathPrimitive,
        into scene: inout GPUIScene,
        layerIndex: Int,
        displayScale: Double
    ) {
        let path = logicalPath.scaled(by: displayScale)
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
        let fullClip = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
        let deviceSurfaceSize = surfaceSize.scaled(by: max(displayScale, 1.0))
        let originalDeferredDraws = deferredDraws
        var bypassReplayAfterAtlasRecovery = false

        // One LRU tick per *rendered frame*, not per attempt: the loop below
        // repaints the same frame, and advancing the clock again would age
        // glyphs the frame is still using out from under it.
        NativeGlyphAtlas.shared.beginFrame()
        defer { NativeGlyphAtlas.shared.setSuspended(false) }

        for attempt in 0..<glyphAtlasPaintAttempts {
            // The atlas recovers from exhaustion by recycling its shelves, which
            // invalidates every UV this pass already emitted. On the last attempt
            // we stop asking it for glyphs at all so the pass cannot exhaust: the
            // scene degrades to bitmap text instead of shipping — and caching —
            // quads that address someone else's atlas cells.
            let isFinalAttempt = attempt == glyphAtlasPaintAttempts - 1
            NativeGlyphAtlas.shared.setSuspended(isFinalAttempt)
            let atlasGenerationAtStart = NativeGlyphAtlas.shared.atlasGeneration

            var scene = GPUIScene(clearColor: clearColor)
            var attemptDeferredDraws = originalDeferredDraws
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
                inheritedClipCornerRadius: 0,
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
                    inheritedClipCornerRadius: 0,
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

            if usedNativeGlyphs,
                NativeGlyphAtlas.shared.atlasGeneration != atlasGenerationAtStart,
                !isFinalAttempt
            {
                // Atlas recovery invalidates every native glyph UV captured earlier in the pass,
                // including replayed text ranges. Rebuild without replay so text rerasterizes
                // against the recovered atlas before we return the scene. The generation token
                // catches a recovery anywhere in the pass, so a *second* exhaustion on the retry
                // is caught too — the previous per-frame boolean was only consulted once.
                bypassReplayAfterAtlasRecovery = true
                continue
            }

            if usedNativeGlyphs {
                scene.glyphAtlas = NativeGlyphAtlas.shared.snapshotIfUsedInCurrentFrame()
            }
            if usedPixelGlyphs {
                scene.pixelGlyphAtlas = pixelGlyphAtlasSnapshot()
            }

            deferredDraws = attemptDeferredDraws
            replayCount = attemptReplayCount
            deferredReplayCount = attemptDeferredReplayCount
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

    private struct PaintTraversalContext {
        let node: ViewNode
        let parentOrigin: Point
        let inheritedClip: Rect?
        let inheritedClipCornerRadius: Double
        let inheritedClipCornerRadii: RetainedCornerRadii?
        let layerIndex: Int
        let primitiveOpacity: Float
        let inheritedColorEffects: [RetainedColorEffect]
        let inheritedBlurRadius: Double
        let inheritedBlurOpaque: Bool
        let inheritedBlendMode: BlendMode
        let inheritedTransform: Transform2D
        let isInsideDrawingGroup: Bool
        let skipCacheUpdates: Bool
    }

    private struct PaintNodeFinishState {
        let node: ViewNode
        let startPaintRecord: Int
        let cacheKey: ViewPaintCacheKey
        let hasChildren: Bool
        let borderColor: Color
        let paintFrame: Rect
        let effectiveClip: Rect?
        let effectiveClipCornerRadius: Double
        /// Clip rounding imposed by ANCESTORS (not the node itself). The
        /// border overlay is part of the node's own decoration, so — like
        /// the background and border quads — it is rounded by its own
        /// corner radii and must not be re-rounded by its own clip.
        let inheritedClipCornerRadius: Double
        let inheritedClipCornerRadii: RetainedCornerRadii?
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
        inheritedClip: Rect?,
        inheritedClipCornerRadius: Double = 0,
        inheritedClipCornerRadii: RetainedCornerRadii? = nil,
        layerIndex: Int,
        surfaceSize: Size,
        displayScale: Double,
        textSystem: WindowTextSystem,
        previousScene: GPUIScene?,
        primitiveOpacity: Float = 1,
        inheritedColorEffects: [RetainedColorEffect] = [],
        inheritedBlurRadius: Double = 0,
        inheritedBlurOpaque: Bool = false,
        inheritedBlendMode: BlendMode = .normal,
        usedNativeGlyphs: inout Bool,
        usedPixelGlyphs: inout Bool,
        replayCount: inout Int,
        inheritedTransform: Transform2D = .identity,
        isInsideDrawingGroup: Bool = false,
        skipCacheUpdates: Bool = false
    ) {
        var traversal: [PaintTraversalStep] = [
            .enter(
                PaintTraversalContext(
                    node: node,
                    parentOrigin: parentOrigin,
                    inheritedClip: inheritedClip,
                    inheritedClipCornerRadius: inheritedClipCornerRadius,
                    inheritedClipCornerRadii: inheritedClipCornerRadii,
                    layerIndex: layerIndex,
                    primitiveOpacity: primitiveOpacity,
                    inheritedColorEffects: inheritedColorEffects,
                    inheritedBlurRadius: inheritedBlurRadius,
                    inheritedBlurOpaque: inheritedBlurOpaque,
                    inheritedBlendMode: inheritedBlendMode,
                    inheritedTransform: inheritedTransform,
                    isInsideDrawingGroup: isInsideDrawingGroup,
                    skipCacheUpdates: skipCacheUpdates
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

            let node = context.node
            let parentOrigin = context.parentOrigin
            let inheritedClip = context.inheritedClip
            let inheritedClipCornerRadius = context.inheritedClipCornerRadius
            let inheritedClipCornerRadii = context.inheritedClipCornerRadii
            let layerIndex = context.layerIndex
            let primitiveOpacity = context.primitiveOpacity
            let inheritedColorEffects = context.inheritedColorEffects
            let inheritedBlurRadius = context.inheritedBlurRadius
            let inheritedBlurOpaque = context.inheritedBlurOpaque
            let inheritedBlendMode = context.inheritedBlendMode
            let inheritedTransform = context.inheritedTransform
            let isInsideDrawingGroup = context.isInsideDrawingGroup
            let skipCacheUpdates = context.skipCacheUpdates

            let startPaintRecord = scene.paintRecordCount
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
            let centeredTransform: Transform2D
            let paintFrame: Rect
            if node.transform.isIdentity {
                centeredTransform = .identity
                paintFrame = nodeLocalFrame.applying(transform: inheritedTransform)
            } else {
                let nodeScreenFrame = nodeLocalFrame.applying(transform: inheritedTransform)
                let center = Point(x: nodeScreenFrame.midX, y: nodeScreenFrame.midY)
                centeredTransform = Transform2D.translation(x: -center.x, y: -center.y)
                    .concatenating(node.transform)
                    .concatenating(.translation(x: center.x, y: center.y))
                paintFrame = nodeScreenFrame.applying(transform: centeredTransform)
            }
            let effectiveTransform = centeredTransform.concatenating(inheritedTransform)

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
            let ownShadowRect: Rect? =
                node.shadowColor.alpha > 0
                ? paintFrame
                    .outset(by: max(0, node.shadowSpread))
                    .offsetBy(dx: node.shadowOffset.x, dy: node.shadowOffset.y)
                : nil
            let ownOutlineRect: Rect? =
                node.outlineColor.alpha > 0 && node.outlineWidth > 0
                ? paintFrame.outset(by: node.outlineWidth)
                : nil
            let cullBounds = union(paintFrame, ownShadowRect, ownOutlineRect)
            if !clipAllowsSubtreeTraversal(clip: inheritedClip, bounds: cullBounds) {
                if !skipCacheUpdates {
                    node.cachedSceneKey = nil
                    node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
                }
                node.markSubtreeRendered()
                continue
            }

            var effectiveClip = inheritedClip
            var effectiveClipCornerRadius = inheritedClipCornerRadius
            var effectiveClipCornerRadii = inheritedClipCornerRadii
            if node.clipsToBounds {
                if let inherited = inheritedClip {
                    guard let clipped = inherited.intersected(with: paintFrame) else {
                        if !skipCacheUpdates {
                            node.cachedSceneKey = nil
                            node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
                        }
                        node.markSubtreeRendered()
                        continue
                    }
                    effectiveClip = clipped
                } else {
                    effectiveClip = paintFrame
                }
                if let cornerRadii = node.cornerRadii, cornerRadii.hasPositiveRadius {
                    // Per-corner clips propagate as corner radii; each
                    // emitted quad resolves the exact uniform radius for
                    // the corners it actually reaches (see
                    // resolveClipCornerRadius). The scalar keeps the
                    // largest radius as the fallback for quads that span
                    // differently-rounded corners.
                    effectiveClipCornerRadius = cornerRadii.maxRadius
                    effectiveClipCornerRadii = cornerRadii
                } else if node.cornerRadius > 0 {
                    effectiveClipCornerRadius = node.cornerRadius
                    effectiveClipCornerRadii = nil
                }
            }

            // Clip rounding for the node's OWN quads (border, background,
            // overlay): a view's own decoration is shaped by its own corner
            // radii and is not re-rounded by its own clip — only children
            // are. The clip RECT still applies (own text/content is clipped
            // to the node's bounds); only the corner rounding reverts to
            // what ancestors imposed.
            let ownClipCornerRadius: (Rect) -> Double = { quadRect in
                resolveClipCornerRadius(
                    forQuadRect: quadRect,
                    clip: effectiveClip,
                    cornerRadii: inheritedClipCornerRadii,
                    uniformFallback: inheritedClipCornerRadius
                )
            }

            // GPUI/Zed carries opacity as an inherited paint scalar.
            let opacity = primitiveOpacity * Float(node.opacity)
            let colorEffects = inheritedColorEffects + node.colorEffects
            let blurRadius = max(inheritedBlurRadius, node.blurRadius)
            let blurOpaque = inheritedBlurOpaque || node.blurOpaque
            let resolvedHoverEffect = node.resolvedActiveHoverEffect
            let cacheKey = ViewPaintCacheKey(
                bounds: paintFrame,
                contentMask: effectiveClip,
                opacity: opacity,
                blurRadius: blurRadius,
                blurOpaque: blurOpaque,
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

            if !skipCacheUpdates,
                let previousScene,
                !node.hasDirtySubtree,
                node.cachedSceneKey == cacheKey,
                let cachedScenePaintRange = node.cachedScenePaintRange
            {
                _ = scene.replay(cachedScenePaintRange, from: previousScene)
                let delta = startPaintRecord - cachedScenePaintRange.lowerBound
                node.shiftCachedSceneRangesRecursively(by: delta)
                node.cachedSceneKey = cacheKey
                node.cachedScenePaintRange = startPaintRecord..<scene.paintRecordCount
                node.markSubtreeRendered()
                replayCount += 1
                continue
            }

            if hasPaintableExtent,
                let hoverShadow = node.hoverEffectShadowCommand(
                    for: paintFrame,
                    inheritedClip: inheritedClip,
                    opacity: opacity
                )
            {
                scene.addQuad(
                    quad(for: hoverShadow, surfaceSize: surfaceSize, displayScale: displayScale),
                    toLayer: layerIndex
                )
            }

            // Shadow
            let effectiveShadowColor = node.shadowColor.multipliedAlpha(by: opacity)
            if hasPaintableExtent, effectiveShadowColor.alpha > 0, let shadowRect = ownShadowRect {
                if clipAllowsDrawing(clip: inheritedClip, rect: shadowRect) {
                    let scaledShadowRect = scaleRect(shadowRect, by: displayScale)
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
                            offsetX: Float(node.shadowOffset.x * displayScale),
                            offsetY: Float(node.shadowOffset.y * displayScale),
                            clipX: shadowClip.0,
                            clipY: shadowClip.1,
                            clipWidth: shadowClip.2,
                            clipHeight: shadowClip.3
                        ), toLayer: layerIndex)
                }
            }

            if hasPaintableExtent,
                let focusEffect = node.focusEffectCommand(
                    for: paintFrame,
                    inheritedClip: inheritedClip,
                    opacity: opacity
                )
            {
                scene.addQuad(
                    quad(for: focusEffect, surfaceSize: surfaceSize, displayScale: displayScale),
                    toLayer: layerIndex
                )
            }

            // Outline (drawn outside the border)
            if hasPaintableExtent, let outlineRect = ownOutlineRect {
                if clipAllowsDrawing(clip: inheritedClip, rect: outlineRect) {
                    scene.addQuad(
                        solidQuad(
                            rect: outlineRect,
                            cornerRadius: (node.cornerRadii?.maxRadius ?? node.cornerRadius) + node.outlineWidth,
                            color: node.outlineColor,
                            opacity: opacity,
                            clip: inheritedClip,
                            surfaceSize: surfaceSize,
                            displayScale: displayScale,
                            colorEffects: colorEffects
                        ), toLayer: layerIndex)
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
                borderColor.alpha > 0, node.borderWidth > 0,
                node.backgroundPath == nil,
                clipAllowsDrawing(clip: effectiveClip, rect: paintFrame)
            {
                let dashedBorderSegments: [BorderSegment]?
                if let cornerRadii = node.cornerRadii, cornerRadii.hasPositiveRadius {
                    // Per-corner dash walk: square corners get no arc
                    // segments (matches the solid overlay treatment).
                    dashedBorderSegments = BorderSegments.dashedSegments(
                        frame: paintFrame,
                        width: node.borderWidth,
                        cornerRadii: cornerRadii,
                        strokeStyle: node.borderStrokeStyle
                    )
                } else {
                    dashedBorderSegments = BorderSegments.dashedSegments(
                        frame: paintFrame,
                        width: node.borderWidth,
                        cornerRadius: node.cornerRadius,
                        strokeStyle: node.borderStrokeStyle
                    )
                }
                if let borderSegments = dashedBorderSegments {
                    for segment in borderSegments where clipAllowsDrawing(clip: effectiveClip, rect: segment.rect) {
                        scene.addQuad(
                            fillQuad(
                                rect: segment.rect,
                                cornerRadius: segment.cornerRadius,
                                color: borderColor,
                                gradient: node.borderGradient,
                                opacity: opacity,
                                clip: effectiveClip,
                                surfaceSize: surfaceSize,
                                displayScale: displayScale,
                                colorEffects: colorEffects,
                                clipCornerRadius: ownClipCornerRadius(segment.rect),
                                blendMode: effectiveBlendMode
                            ), toLayer: layerIndex)
                    }
                } else {
                    scene.addQuad(
                        fillQuad(
                            rect: paintFrame,
                            cornerRadius: node.cornerRadius,
                            cornerRadii: node.cornerRadii,
                            color: borderColor,
                            gradient: node.borderGradient,
                            opacity: opacity,
                            clip: effectiveClip,
                            surfaceSize: surfaceSize,
                            displayScale: displayScale,
                            colorEffects: colorEffects,
                            clipCornerRadius: ownClipCornerRadius(paintFrame),
                            blendMode: effectiveBlendMode
                        ), toLayer: layerIndex)
                }
            }

            // Background fill (inset by border width)
            let fillRect = node.borderWidth > 0 ? paintFrame.inset(by: node.borderWidth) : paintFrame
            let fillCornerRadius = max(0, node.cornerRadius - node.borderWidth)
            let fillCornerRadii =
                node.borderWidth > 0 ? node.cornerRadii?.inset(by: node.borderWidth) : node.cornerRadii

            let resolvedBGColor = node.backgroundColor ?? node.backgroundGradient?.startColor
            if let bg = resolvedBGColor, bg.alpha > 0,
                fillRect.size.width > 0, fillRect.size.height > 0,
                clipAllowsDrawing(clip: effectiveClip, rect: fillRect),
                node.backgroundPath == nil
            {
                scene.addQuad(
                    fillQuad(
                        rect: fillRect,
                        cornerRadius: fillCornerRadius,
                        cornerRadii: fillCornerRadii,
                        color: bg,
                        gradient: node.backgroundGradient,
                        opacity: opacity,
                        clip: effectiveClip,
                        surfaceSize: surfaceSize,
                        displayScale: displayScale,
                        colorEffects: colorEffects,
                        blurRadius: Float(blurRadius * displayScale),
                        blurOpaque: blurOpaque ? 1 : 0,
                        clipCornerRadius: ownClipCornerRadius(fillRect),
                        blendMode: effectiveBlendMode
                    ),
                    toLayer: layerIndex
                )
            }

            if let path = node.backgroundPath, fillRect.size.width > 0, fillRect.size.height > 0,
                clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
            {
                let scaledPath = path.scaled(to: fillRect)
                let pathBounds = scaledPath.segments.boundingRect ?? fillRect
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
                            bounds: pathBounds,
                            fillColor: bg,
                            clipBounds: effectiveClip
                        ), into: &scene, layerIndex: layerIndex, displayScale: displayScale)
                }
                let effectiveStrokeColor = node.borderColor.multipliedAlpha(by: opacity)
                if effectiveStrokeColor.alpha > 0, node.borderWidth > 0 {
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
                            bounds: pathBounds,
                            strokeColor: effectiveStrokeColor,
                            lineWidth: node.borderWidth,
                            clipBounds: effectiveClip
                        ), into: &scene, layerIndex: layerIndex, displayScale: displayScale)
                }
            }

            if let hoverOverlay = node.hoverEffectOverlayCommand(
                for: fillRect,
                cornerRadius: fillCornerRadius,
                clipRect: effectiveClip,
                opacity: opacity
            ) {
                scene.addQuad(
                    quad(for: hoverOverlay, surfaceSize: surfaceSize, displayScale: displayScale),
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
                    solidQuad(
                        rect: fillRect,
                        cornerRadius: retainedRedactionPlaceholderCornerRadius(for: fillRect),
                        color: retainedRedactionPlaceholderBaseColor,
                        opacity: opacity,
                        clip: effectiveClip,
                        surfaceSize: surfaceSize,
                        displayScale: displayScale,
                        clipCornerRadius: ownClipCornerRadius(fillRect),
                        blendMode: effectiveBlendMode
                    ), toLayer: layerIndex)
            } else if let bitmapSurface = node.bitmapSurface,
                fillRect.size.width > 0, fillRect.size.height > 0,
                clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
            {
                let scaledFillRect = scaleRect(fillRect, by: displayScale)
                let clipR = clipRectFloats(effectiveClip, surfaceSize: surfaceSize, displayScale: displayScale)
                let textureID = scene.registerImageResource(bitmapSurface)
                scene.addImage(
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
                        textureID: textureID
                    ), toLayer: layerIndex)
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
                appendTextGlyphs(
                    for: text,
                    style: effectiveTextStyle,
                    in: fillRect,
                    opacity: 1,
                    clip: effectiveClip,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    textSystem: textSystem,
                    into: &nativeGlyphs,
                    pixelGlyphs: &pixelGlyphs,
                    decorationQuads: &textDecorationQuads
                )
                for glyph in nativeGlyphs {
                    scene.addGlyph(glyph, toLayer: layerIndex)
                }
                for glyph in pixelGlyphs {
                    scene.addPixelGlyph(glyph, toLayer: layerIndex)
                }
                for quad in textDecorationQuads {
                    scene.addQuad(quad, toLayer: layerIndex)
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
                canvasDraw(&canvasContext, fillRect.size)
                appendCanvasOperations(
                    canvasContext.operations,
                    into: &scene,
                    origin: fillRect.origin,
                    baseClip: effectiveClip,
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
            if isCompositingGroup, !isInsideDrawingGroup, hasPaintableExtent,
                !sortedChildren.isEmpty,
                let buffer = compositingGroupBuffer(
                    paintFrame: paintFrame, clip: effectiveClip, displayScale: displayScale)
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
                let subInheritedTransform = subShift.concatenating(inheritedTransform)
                let subSize = buffer.size

                // Rasterizing the group means walking and CPU-rasterizing its
                // whole subtree on the main actor, so an unchanged group reuses
                // the bitmap it produced last time. The condition is the one the
                // paint-record replay above uses — same key, clean subtree —
                // because the key covers everything about the group itself and
                // `subtreeDirtyFlags` covers everything about its descendants.
                let bitmap: BitmapSurface
                if !skipCacheUpdates, !node.hasDirtySubtree,
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
                    var subScene = GPUIScene(clearColor: .clear)
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
                            inheritedClip: nil,
                            inheritedClipCornerRadius: 0,
                            layerIndex: 0,
                            surfaceSize: surfaceSize,
                            displayScale: displayScale,
                            textSystem: textSystem,
                            previousScene: nil,
                            primitiveOpacity: 1.0,
                            inheritedColorEffects: [],
                            inheritedBlurRadius: 0,
                            inheritedBlurOpaque: false,
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
                    if !skipCacheUpdates {
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
                let clipR = clipRectFloats(effectiveClip, surfaceSize: surfaceSize, displayScale: displayScale)
                let imageOpacity = primitiveOpacity * Float(node.opacity)
                scene.addImage(
                    ImagePrimitive(
                        screenX: Float(scaledFrame.origin.x),
                        screenY: Float(scaledFrame.origin.y),
                        screenW: Float(scaledFrame.size.width),
                        screenH: Float(scaledFrame.size.height),
                        opacity: imageOpacity,
                        clipX: clipR.0,
                        clipY: clipR.1,
                        clipWidth: clipR.2,
                        clipHeight: clipR.3,
                        textureID: textureID
                    ), toLayer: layerIndex)
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
                            effectiveClip: effectiveClip,
                            effectiveClipCornerRadius: effectiveClipCornerRadius,
                            inheritedClipCornerRadius: inheritedClipCornerRadius,
                            inheritedClipCornerRadii: inheritedClipCornerRadii,
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
                                inheritedClipCornerRadius: effectiveClipCornerRadius,
                                inheritedClipCornerRadii: effectiveClipCornerRadii,
                                layerIndex: layerIndex,
                                primitiveOpacity: opacity,
                                inheritedColorEffects: colorEffects,
                                inheritedBlurRadius: blurRadius,
                                inheritedBlurOpaque: blurOpaque,
                                inheritedBlendMode: effectiveBlendMode,
                                inheritedTransform: effectiveTransform,
                                isInsideDrawingGroup: false,
                                skipCacheUpdates: false
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
                    effectiveClip: effectiveClip,
                    effectiveClipCornerRadius: effectiveClipCornerRadius,
                    inheritedClipCornerRadius: inheritedClipCornerRadius,
                    inheritedClipCornerRadii: inheritedClipCornerRadii,
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
            state.borderColor.alpha > 0, node.borderWidth > 0,
            node.backgroundPath == nil,
            clipAllowsDrawing(clip: state.effectiveClip, rect: state.paintFrame)
        {
            let segments: [BorderSegment]
            let dashedSegments: [BorderSegment]?
            if let cornerRadii = node.cornerRadii, cornerRadii.hasPositiveRadius {
                dashedSegments = BorderSegments.dashedSegments(
                    frame: state.paintFrame,
                    width: node.borderWidth,
                    cornerRadii: cornerRadii,
                    strokeStyle: node.borderStrokeStyle
                )
            } else {
                dashedSegments = BorderSegments.dashedSegments(
                    frame: state.paintFrame,
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
                    frame: state.paintFrame,
                    width: node.borderWidth,
                    cornerRadii: cornerRadii
                )
            } else {
                segments = BorderSegments.solidSegments(
                    frame: state.paintFrame,
                    width: node.borderWidth,
                    cornerRadius: node.cornerRadius
                )
            }
            for segment in segments where clipAllowsDrawing(clip: state.effectiveClip, rect: segment.rect) {
                scene.addQuad(
                    fillQuad(
                        rect: segment.rect,
                        cornerRadius: segment.cornerRadius,
                        color: state.borderColor,
                        gradient: node.borderGradient,
                        opacity: state.opacity,
                        clip: state.effectiveClip,
                        surfaceSize: surfaceSize,
                        displayScale: displayScale,
                        colorEffects: state.colorEffects,
                        clipCornerRadius: resolveClipCornerRadius(
                            forQuadRect: segment.rect,
                            clip: state.effectiveClip,
                            cornerRadii: state.inheritedClipCornerRadii,
                            uniformFallback: state.inheritedClipCornerRadius
                        ),
                        blendMode: state.effectiveBlendMode
                    ), toLayer: state.layerIndex)
            }
        }

        if !state.skipCacheUpdates {
            node.cachedSceneKey = state.cacheKey
            node.cachedScenePaintRange = state.startPaintRecord..<scene.paintRecordCount
        }
        node.markSubtreeRendered()
    }

    // MARK: - Compositing groups

    /// The offscreen buffer a compositing group will rasterize into.
    private struct CompositingGroupBuffer {
        /// The group's frame clamped to the effective clip, in logical points.
        /// The sub-scene is shifted by this origin and the composited image is
        /// placed here, so the two always agree.
        let frame: Rect
        /// Buffer extent in device pixels.
        let size: IntSize
    }

    /// Largest offscreen compositing buffer, in device pixels. A 4K window is
    /// ~8.3 M pixels, so this leaves generous headroom while keeping a single
    /// group's allocation under 64 MB — past it inline painting is both cheaper
    /// and more correct than a buffer the machine cannot afford every frame.
    private static let maxCompositingGroupPixels = 16_777_216

    /// Sizes the offscreen buffer for a compositing group, or returns nil when
    /// the group must be painted inline instead.
    ///
    /// Three things used to be missing here and each was reachable from app
    /// code: the frame was not clamped to the clip (so `.drawingGroup()` on tall
    /// scroll content allocated the *content* size every frame), the
    /// `Double → Int → Int32` conversions trapped on a non-finite or huge frame
    /// (`maxWidth: .infinity` resolving badly is a process kill, not a glitch),
    /// and there was no upper bound at all.
    private static func compositingGroupBuffer(
        paintFrame: Rect,
        clip: Rect?,
        displayScale: Double
    ) -> CompositingGroupBuffer? {
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

        return CompositingGroupBuffer(
            frame: frame,
            size: IntSize(width: Int32(width), height: Int32(height))
        )
    }

    /// Snapshot of the shared pixel-font atlas. The pixel atlas is a static
    /// surface, so every consumer in a frame can take the same full-surface
    /// snapshot without any dirty-region bookkeeping.
    private static func pixelGlyphAtlasSnapshot() -> GlyphAtlasSnapshot {
        let atlas = PixelFontAtlas.shared.surface
        return GlyphAtlasSnapshot(
            width: atlas.width,
            height: atlas.height,
            pixels: atlas.pixels,
            dirtyRegion: GlyphAtlasRegion(x: 0, y: 0, width: atlas.width, height: atlas.height)
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
        baseClip: Rect?,
        opacity: Float,
        layerIndex: Int,
        surfaceSize: Size,
        displayScale: Double,
        textSystem: WindowTextSystem,
        usedNativeGlyphs: inout Bool,
        usedPixelGlyphs: inout Bool
    ) {
        var clipStack: [Rect?] = []
        var currentClip = baseClip

        for operation in operations {
            switch operation {
            case .fillPath(let path, let color):
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0 else { continue }
                let translated = path.translated(by: origin)
                guard let bounds = translated.segments.boundingRect, !bounds.isEmpty else { continue }
                guard clipAllowsDrawing(clip: currentClip, rect: bounds) else { continue }
                Self.emit(
                    path: PathPrimitive(
                        elements: pathElements(from: translated.segments),
                        bounds: bounds,
                        fillColor: effectiveColor,
                        clipBounds: currentClip
                    ), into: &scene, layerIndex: layerIndex, displayScale: displayScale)

            case .strokePath(let path, let color, let style):
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0, style.lineWidth > 0 else { continue }
                let translated = path.translated(by: origin)
                // Strokes can have a zero-thickness path bounds (e.g. a
                // single horizontal line), so outset before the empty check
                // and use the inflated rect for clip/visibility tests.
                guard let pathBounds = translated.segments.boundingRect else { continue }
                let strokeBounds = pathBounds.outset(by: style.lineWidth / 2)
                guard !strokeBounds.isEmpty else { continue }
                guard clipAllowsDrawing(clip: currentClip, rect: strokeBounds) else { continue }
                Self.emit(
                    path: PathPrimitive(
                        elements: pathElements(from: translated.segments),
                        bounds: strokeBounds,
                        strokeColor: effectiveColor,
                        lineWidth: style.lineWidth,
                        clipBounds: currentClip
                    ), into: &scene, layerIndex: layerIndex, displayScale: displayScale)

            case .fillRect(let rect, let color):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0 else { continue }
                guard clipAllowsDrawing(clip: currentClip, rect: effectiveRect) else { continue }
                scene.addQuad(
                    solidQuad(
                        rect: effectiveRect,
                        cornerRadius: 0,
                        color: effectiveColor,
                        opacity: 1,
                        clip: currentClip,
                        surfaceSize: surfaceSize,
                        displayScale: displayScale
                    ), toLayer: layerIndex)

            case .fillRectGradient(let rect, let gradient):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                guard clipAllowsDrawing(clip: currentClip, rect: effectiveRect) else { continue }
                scene.addQuad(
                    fillQuad(
                        rect: effectiveRect,
                        cornerRadius: 0,
                        color: gradient.startColor,
                        gradient: .linear(gradient),
                        opacity: opacity,
                        clip: currentClip,
                        surfaceSize: surfaceSize,
                        displayScale: displayScale
                    ), toLayer: layerIndex)

            case .strokeRect(let rect, let color, let lineWidth):
                let effectiveColor = color.multipliedAlpha(by: opacity)
                guard effectiveColor.alpha > 0, lineWidth > 0 else { continue }
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let strokeBounds = effectiveRect.outset(by: lineWidth / 2)
                guard clipAllowsDrawing(clip: currentClip, rect: strokeBounds) else { continue }
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
                        clipBounds: currentClip
                    ), into: &scene, layerIndex: layerIndex, displayScale: displayScale)

            case .drawText(let text, let rect, let style):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveStyle = style.multipliedOpacity(by: opacity)
                guard clipAllowsDrawing(clip: currentClip, rect: effectiveRect) else { continue }
                var nativeGlyphs: [GlyphPrimitive] = []
                var pixelGlyphs: [GlyphPrimitive] = []
                var decorationQuads: [QuadPrimitive] = []
                appendTextGlyphs(
                    for: text,
                    style: effectiveStyle,
                    in: effectiveRect,
                    opacity: 1,
                    clip: currentClip,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    textSystem: textSystem,
                    into: &nativeGlyphs,
                    pixelGlyphs: &pixelGlyphs,
                    decorationQuads: &decorationQuads
                )
                for glyph in nativeGlyphs {
                    scene.addGlyph(glyph, toLayer: layerIndex)
                }
                for glyph in pixelGlyphs {
                    scene.addPixelGlyph(glyph, toLayer: layerIndex)
                }
                for quad in decorationQuads {
                    scene.addQuad(quad, toLayer: layerIndex)
                }
                usedNativeGlyphs = usedNativeGlyphs || !nativeGlyphs.isEmpty
                usedPixelGlyphs = usedPixelGlyphs || !pixelGlyphs.isEmpty

            case .drawImage(let bitmap, let rect, let imageOpacity):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                let effectiveOpacity = opacity * imageOpacity
                guard effectiveOpacity > 0 else { continue }
                guard clipAllowsDrawing(clip: currentClip, rect: effectiveRect) else { continue }
                let scaledRect = scaleRect(effectiveRect, by: displayScale)
                let clipR = clipRectFloats(currentClip, surfaceSize: surfaceSize, displayScale: displayScale)
                let textureID = scene.registerImageResource(bitmap)
                scene.addImage(
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
                        textureID: textureID
                    ), toLayer: layerIndex)

            case .pushClip(let rect):
                let effectiveRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                clipStack.append(currentClip)
                if let existing = currentClip {
                    currentClip = existing.intersected(with: effectiveRect)
                } else {
                    currentClip = effectiveRect
                }

            case .popClip:
                currentClip = clipStack.popLast() ?? baseClip
            }
        }
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

    /// Resolves the uniform clip corner radius for one emitted quad against
    /// a per-corner clip. Clip rounding is only visible in the corner zones
    /// a quad actually reaches, so:
    ///   - a quad reaching no clip-corner zone needs no rounding (0),
    ///   - a quad reaching corners that all share one radius uses exactly
    ///     that radius (e.g. the left segment of a joined control with
    ///     rounded left corners and square right corners gets the left
    ///     radius, and its square corners stay square),
    ///   - a quad spanning differently-rounded corners falls back to the
    ///     largest radius (the historic uniform approximation).
    /// Without a per-corner clip the uniform fallback applies unchanged.
    private static func resolveClipCornerRadius(
        forQuadRect quadRect: Rect,
        clip: Rect?,
        cornerRadii: RetainedCornerRadii?,
        uniformFallback: Double
    ) -> Double {
        guard let clip, let cornerRadii, cornerRadii.hasPositiveRadius else {
            return uniformFallback
        }

        let zone = cornerRadii.maxRadius
        var reached: [Double] = []
        reached.reserveCapacity(4)
        if quadRect.intersected(with: Rect(x: clip.minX, y: clip.minY, width: zone, height: zone)) != nil {
            reached.append(cornerRadii.topLeft)
        }
        if quadRect.intersected(with: Rect(x: clip.maxX - zone, y: clip.minY, width: zone, height: zone)) != nil {
            reached.append(cornerRadii.topRight)
        }
        let bottomRightZone = Rect(x: clip.maxX - zone, y: clip.maxY - zone, width: zone, height: zone)
        if quadRect.intersected(with: bottomRightZone) != nil {
            reached.append(cornerRadii.bottomRight)
        }
        if quadRect.intersected(with: Rect(x: clip.minX, y: clip.maxY - zone, width: zone, height: zone)) != nil {
            reached.append(cornerRadii.bottomLeft)
        }

        guard let first = reached.first else {
            return 0
        }
        return reached.allSatisfy { $0 == first } ? first : cornerRadii.maxRadius
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
            let startPaintRecord = scene.paintRecordCount
            if let previousScene, let cachedScenePaintRange = deferredDraws[deferredDrawIndex].cachedScenePaintRange {
                _ = scene.replay(cachedScenePaintRange, from: previousScene)
                deferredDraws[deferredDrawIndex].cachedScenePaintRange = startPaintRecord..<scene.paintRecordCount
                replayCount += 1
                continue
            }

            switch deferredDraws[deferredDrawIndex].payload {
            case .scrollIndicator:
                let fillRect = deferredDraws[deferredDrawIndex].payload.fillRectCommand(
                    contentMask: deferredDraws[deferredDrawIndex].contentMask
                )
                scene.addQuad(
                    quad(for: fillRect, surfaceSize: surfaceSize, displayScale: displayScale),
                    toLayer: 0
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
                    inheritedClipCornerRadius: payload.inheritedClipCornerRadius,
                    inheritedClipCornerRadii: payload.inheritedClipCornerRadii,
                    layerIndex: 0,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    textSystem: textSystem,
                    previousScene: previousScene,
                    primitiveOpacity: payload.inheritedOpacity,
                    inheritedColorEffects: payload.inheritedColorEffects,
                    inheritedBlurRadius: payload.inheritedBlurRadius,
                    inheritedBlurOpaque: payload.inheritedBlurOpaque,
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
        colorEffects: [RetainedColorEffect] = []
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
            blendMode: Float(command.blendMode.rawValue),
            effectType: fx.effectType,
            effectIntensity: fx.effectIntensity,
            effectParam1: fx.effectParam1,
            effectParam2: fx.effectParam2,
            effectParam3: fx.effectParam3,
            effectParam4: fx.effectParam4
        )
    }

    private static func appendTextGlyphs(
        for text: String,
        style: PixelTextStyle,
        in rect: Rect,
        opacity: Float,
        clip: Rect?,
        surfaceSize: Size,
        displayScale: Double,
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
            surfaceSize: surfaceSize,
            displayScale: displayScale,
            textSystem: textSystem,
            into: &glyphs,
            decorationQuads: &decorationQuads
        ) {
            return
        }

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
        let scaledVisibleClip = clip.map { scaleRect($0, by: displayScale) }
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
                        clipHeight: clipRect.3
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
        surfaceSize: Size,
        displayScale: Double,
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
        let scaledVisibleClip = clip.map { scaleRect($0, by: displayScale) }
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
                let glyphLayoutOrigin = Point(
                    x: (startX + glyph.origin.x) * displayScale,
                    y: (lineOriginY + glyph.origin.y) * displayScale
                )
                if let scaledVisibleClip,
                    let preflightRect = nativeGlyphPreflightRect(
                        for: glyph,
                        origin: glyphLayoutOrigin,
                        scaleFactor: displayScale
                    ),
                    scaledVisibleClip.intersected(with: preflightRect) == nil
                {
                    continue
                }

                guard
                    let preparedGlyph = NativeGlyphAtlas.shared.prepareGlyph(
                        for: glyph, style: style, scaleFactor: displayScale),
                    let previewEntry = preparedGlyph.previewEntry
                else {
                    continue
                }
                guard previewEntry.width > 0, previewEntry.height > 0 else {
                    continue
                }

                // Snap glyph destination to integer device pixels.  Without
                // this, the rasterizer's tx/ty mapping reads the same atlas
                // pixel from two adjacent destination pixels when the origin
                // is fractional, producing the classic doubled-letter smear
                // pattern.  Pixel-aligned glyphs render crisp 1:1 from atlas.
                let destinationOrigin = Point(
                    x: (glyphLayoutOrigin.x + Double(previewEntry.bearingX)).rounded(),
                    y: (glyphLayoutOrigin.y + Double(previewEntry.bearingY)).rounded()
                )
                guard destinationOrigin.x.isFinite, destinationOrigin.y.isFinite else {
                    continue
                }
                let glyphRect = Rect(
                    x: destinationOrigin.x,
                    y: destinationOrigin.y,
                    width: Double(previewEntry.width),
                    height: Double(previewEntry.height)
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
                        screenW: Float(entry.width),
                        screenH: Float(entry.height),
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
                        clipHeight: clipRect.3
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
        surfaceSize: Size,
        displayScale: Double,
        into quads: inout [QuadPrimitive]
    ) {
        guard color.alpha > 0 else {
            return
        }

        for rect in decorationSegments(lineRect: lineRect, y: y, thickness: thickness, pattern: pattern) {
            guard clipAllowsDrawing(clip: clip, rect: rect) else {
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

    private static func nativeGlyphPreflightRect(
        for glyph: NativeTextGlyphLayout,
        origin: Point,
        scaleFactor: Double
    ) -> Rect? {
        guard let metrics = makeCapturedGlyphRasterMetrics(for: glyph, scaleFactor: scaleFactor) else {
            return nil
        }

        return Rect(
            x: origin.x - Double(metrics.paddingPixels),
            y: origin.y - Double(metrics.paddingPixels) - metrics.baselineYOffset * metrics.renderScale,
            width: Double(metrics.targetWidth),
            height: Double(metrics.targetHeight)
        )
    }

    private static func shouldRenderNativeGlyph(_ glyph: NativeTextGlyphLayout) -> Bool {
        glyph.character != " " || glyph.sourceIndex == nil
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
