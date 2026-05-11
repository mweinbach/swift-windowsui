import SwiftWindowsCore
import SwiftWindowsGraphics

/// Walks a ViewNode tree and produces a GPUIScene with typed primitive arrays,
/// mirroring the logic of ViewNode.appendCommands() but targeting the GPUI
/// instanced-rendering pipeline instead of the RenderCommand enum list.
@MainActor
public enum ScenePainter {

    public static func paint(root: ViewNode, clearColor: Color, surfaceSize: Size, displayScale: Double = 1.0) -> GPUIScene {
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
        deferredReplayCount: inout Int
    ) -> GPUIScene {
        let fullClip = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
        let deviceSurfaceSize = surfaceSize.scaled(by: max(displayScale, 1.0))
        let originalDeferredDraws = deferredDraws
        var bypassReplayAfterAtlasRecovery = false

        for attempt in 0..<2 {
            var scene = GPUIScene(clearColor: clearColor)
            var attemptDeferredDraws = originalDeferredDraws
            var attemptReplayCount = 0
            var attemptDeferredReplayCount = 0
            var usedNativeGlyphs = false
            var usedPixelGlyphs = false
            let replaySource = bypassReplayAfterAtlasRecovery ? nil : previousScene

            NativeGlyphAtlas.shared.beginFrame()
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
               NativeGlyphAtlas.shared.consumeRecoveryRequest(),
               attempt == 0 {
                // Atlas recovery invalidates every native glyph UV captured earlier in the pass,
                // including replayed text ranges. Rebuild once without replay so text rerasterizes
                // against the recovered atlas before we return the scene.
                bypassReplayAfterAtlasRecovery = true
                continue
            }

            if usedNativeGlyphs {
                scene.glyphAtlas = NativeGlyphAtlas.shared.snapshotIfUsedInCurrentFrame()
            }
            if usedPixelGlyphs {
                let atlas = PixelFontAtlas.shared.surface
                scene.pixelGlyphAtlas = GlyphAtlasSnapshot(
                    width: atlas.width,
                    height: atlas.height,
                    pixels: atlas.pixels,
                    dirtyRegion: GlyphAtlasRegion(x: 0, y: 0, width: atlas.width, height: atlas.height)
                )
            }

            deferredDraws = attemptDeferredDraws
            replayCount = attemptReplayCount
            deferredReplayCount = attemptDeferredReplayCount
            scene.finish()
            return scene
        }

        deferredDraws = originalDeferredDraws
        replayCount = 0
        deferredReplayCount = 0
        var scene = GPUIScene(clearColor: clearColor)
        scene.finish()
        return scene
    }

    // MARK: - Private

    private static func paintNode(
        _ node: ViewNode,
        into scene: inout GPUIScene,
        deferredDraws: inout [DeferredDrawState],
        parentOrigin: Point,
        inheritedClip: Rect?,
        layerIndex: Int,
        surfaceSize: Size,
        displayScale: Double,
        textSystem: WindowTextSystem,
        previousScene: GPUIScene?,
        primitiveOpacity: Float = 1,
        usedNativeGlyphs: inout Bool,
        usedPixelGlyphs: inout Bool,
        replayCount: inout Int
    ) {
        let startPaintRecord = scene.paintRecordCount
        guard !node.isHidden else {
            node.cachedSceneKey = nil
            node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
            node.markSubtreeRendered()
            return
        }

        let absoluteFrame = Rect(
            x: parentOrigin.x + node.resolvedFrame.origin.x,
            y: parentOrigin.y + node.resolvedFrame.origin.y,
            width: node.resolvedFrame.size.width,
            height: node.resolvedFrame.size.height
        )

        guard absoluteFrame.size.width > 0, absoluteFrame.size.height > 0 else {
            node.cachedSceneKey = nil
            node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
            node.markSubtreeRendered()
            return
        }

        // Occlusion culling against inherited clip.
        if !clipAllowsDrawing(clip: inheritedClip, rect: absoluteFrame) {
            node.cachedSceneKey = nil
            node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
            node.markSubtreeRendered()
            return
        }

        var effectiveClip = inheritedClip
        if node.clipsToBounds {
            if let inherited = inheritedClip {
                guard let clipped = inherited.intersected(with: absoluteFrame) else {
                    node.cachedSceneKey = nil
                    node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
                    node.markSubtreeRendered()
                    return
                }
                effectiveClip = clipped
            } else {
                effectiveClip = absoluteFrame
            }
        }

        // GPUI/Zed carries opacity as an inherited paint scalar.
        let opacity = primitiveOpacity * Float(node.opacity)
        let cacheKey = ViewPaintCacheKey(
            bounds: absoluteFrame,
            contentMask: effectiveClip,
            opacity: opacity,
            displayScale: displayScale
        )
        guard opacity > 0 else {
            node.cachedSceneKey = cacheKey
            node.cachedScenePaintRange = startPaintRecord..<startPaintRecord
            node.markSubtreeRendered()
            return
        }

        if
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
            return
        }

        // Shadow
        let effectiveShadowColor = node.shadowColor.multipliedAlpha(by: opacity)
        if effectiveShadowColor.alpha > 0 {
            let shadowRect = absoluteFrame
                .outset(by: max(0, node.shadowSpread))
                .offsetBy(dx: node.shadowOffset.x, dy: node.shadowOffset.y)

            if clipAllowsDrawing(clip: inheritedClip, rect: shadowRect) {
                let scaledShadowRect = scaleRect(shadowRect, by: displayScale)
                let shadowClip = clipRectFloats(inheritedClip, surfaceSize: surfaceSize, displayScale: displayScale)
                scene.addShadow(ShadowPrimitive(
                    x: Float(scaledShadowRect.origin.x),
                    y: Float(scaledShadowRect.origin.y),
                    width: Float(scaledShadowRect.size.width),
                    height: Float(scaledShadowRect.size.height),
                    cornerRadius: Float((node.cornerRadius + max(0, node.shadowSpread)) * displayScale),
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

        // Outline (drawn outside the border)
        if node.outlineColor.alpha > 0, node.outlineWidth > 0 {
            let outlineRect = absoluteFrame.outset(by: node.outlineWidth)
            if clipAllowsDrawing(clip: inheritedClip, rect: outlineRect) {
                scene.addQuad(solidQuad(
                rect: outlineRect,
                cornerRadius: node.cornerRadius + node.outlineWidth,
                color: node.outlineColor,
                opacity: opacity,
                clip: inheritedClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale
            ), toLayer: layerIndex)
            }
        }

        // Border (full rect drawn under the fill area)
        if node.borderColor.alpha > 0, node.borderWidth > 0,
           clipAllowsDrawing(clip: effectiveClip, rect: absoluteFrame)
        {
            scene.addQuad(solidQuad(
                rect: absoluteFrame,
                cornerRadius: node.cornerRadius,
                color: node.borderColor,
                opacity: opacity,
                clip: effectiveClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale
            ), toLayer: layerIndex)
        }

        // Background fill (inset by border width)
        let fillRect = node.borderWidth > 0 ? absoluteFrame.inset(by: node.borderWidth) : absoluteFrame
        let fillCornerRadius = max(0, node.cornerRadius - node.borderWidth)

        let resolvedBGColor = node.backgroundColor ?? node.backgroundGradient?.startColor
        if let bg = resolvedBGColor, bg.alpha > 0,
           fillRect.size.width > 0, fillRect.size.height > 0,
           clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
        {
            let scaledFillRect = scaleRect(fillRect, by: displayScale)
            let clipR = clipRectFloats(effectiveClip, surfaceSize: surfaceSize, displayScale: displayScale)
            let endColor = node.backgroundGradient?.endColor ?? bg
            let axis: Float = {
                guard let grad = node.backgroundGradient else { return 0 }
                return grad.axis == .horizontal ? 1 : 0
            }()

            scene.addQuad(QuadPrimitive(
                x: Float(scaledFillRect.origin.x),
                y: Float(scaledFillRect.origin.y),
                width: Float(scaledFillRect.size.width),
                height: Float(scaledFillRect.size.height),
                cornerRadius: Float(fillCornerRadius * displayScale),
                startR: bg.red, startG: bg.green, startB: bg.blue,
                startA: bg.alpha * opacity,
                endR: endColor.red, endG: endColor.green, endB: endColor.blue,
                endA: endColor.alpha * opacity,
                gradientAxis: axis,
                clipX: clipR.0, clipY: clipR.1,
                clipWidth: clipR.2, clipHeight: clipR.3
            ), toLayer: layerIndex)
        }

        let drawsRedactionPlaceholder = node.redactionReasons.contains(.placeholder)
            && (node.bitmapSurface != nil || (node.text?.isEmpty == false))
            && fillRect.size.width > 0
            && fillRect.size.height > 0
            && clipAllowsDrawing(clip: effectiveClip, rect: fillRect)

        if drawsRedactionPlaceholder {
            scene.addQuad(solidQuad(
                rect: fillRect,
                cornerRadius: retainedRedactionPlaceholderCornerRadius(for: fillRect),
                color: retainedRedactionPlaceholderBaseColor,
                opacity: opacity,
                clip: effectiveClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale
            ), toLayer: layerIndex)
        } else if let bitmapSurface = node.bitmapSurface,
                  fillRect.size.width > 0, fillRect.size.height > 0,
                  clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
        {
            let scaledFillRect = scaleRect(fillRect, by: displayScale)
            let clipR = clipRectFloats(effectiveClip, surfaceSize: surfaceSize, displayScale: displayScale)
            let textureID = scene.registerImageResource(bitmapSurface)
            scene.addImage(ImagePrimitive(
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

        // Children -- sort by zIndex (stable) and rely on scene draw orders
        // rather than allocating paint-order layers.
        let childOrigin = Point(
            x: absoluteFrame.origin.x - (node.scrollAxis == .horizontal ? node.resolvedScrollOffset : 0),
            y: absoluteFrame.origin.y - (node.scrollAxis == .vertical ? node.resolvedScrollOffset : 0)
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

        for child in sortedChildren {
            if child.paintsInDeferredPhase {
                continue
            }
            paintNode(
                child,
                into: &scene,
                deferredDraws: &deferredDraws,
                parentOrigin: childOrigin,
                inheritedClip: effectiveClip,
                layerIndex: layerIndex,
                surfaceSize: surfaceSize,
                displayScale: displayScale,
                textSystem: textSystem,
                previousScene: previousScene,
                primitiveOpacity: opacity,
                usedNativeGlyphs: &usedNativeGlyphs,
                usedPixelGlyphs: &usedPixelGlyphs,
                replayCount: &replayCount
            )
        }

        node.cachedSceneKey = cacheKey
        node.cachedScenePaintRange = startPaintRecord..<scene.paintRecordCount
        node.markSubtreeRendered()
    }

    // MARK: - Helpers

    /// Builds a solid-color QuadPrimitive (start color == end color, no gradient).
    private static func solidQuad(
        rect: Rect,
        cornerRadius: Double,
        color: Color,
        opacity: Float,
        clip: Rect?,
        surfaceSize: Size,
        displayScale: Double
    ) -> QuadPrimitive {
        let scaledRect = scaleRect(rect, by: displayScale)
        let clipR = clipRectFloats(clip, surfaceSize: surfaceSize, displayScale: displayScale)
        let a = color.alpha * opacity
        return QuadPrimitive(
            x: Float(scaledRect.origin.x),
            y: Float(scaledRect.origin.y),
            width: Float(scaledRect.size.width),
            height: Float(scaledRect.size.height),
            cornerRadius: Float(cornerRadius * displayScale),
            startR: color.red, startG: color.green, startB: color.blue, startA: a,
            endR: color.red, endG: color.green, endB: color.blue, endA: a,
            clipX: clipR.0, clipY: clipR.1,
            clipWidth: clipR.2, clipHeight: clipR.3
        )
    }

    private static func clipAllowsDrawing(clip: Rect?, rect: Rect) -> Bool {
        guard let clip = clip else { return true }
        return clip.intersected(with: rect) != nil
    }

    /// Converts an optional clip Rect into four Float values for primitive clip fields.
    private static func clipRectFloats(_ clip: Rect?, surfaceSize: Size, displayScale: Double) -> (Float, Float, Float, Float) {
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
                    layerIndex: 0,
                    surfaceSize: surfaceSize,
                    displayScale: displayScale,
                    textSystem: textSystem,
                    previousScene: previousScene,
                    primitiveOpacity: payload.inheritedOpacity,
                    usedNativeGlyphs: &usedNativeGlyphs,
                    usedPixelGlyphs: &usedPixelGlyphs,
                    replayCount: &replayCount
                )
            }

            deferredDraws[deferredDrawIndex].cachedScenePaintRange = startPaintRecord..<scene.paintRecordCount
        }
    }

    private static func quad(
        for command: FillRectCommand,
        surfaceSize: Size,
        displayScale: Double
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
            clipHeight: clipR.3
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
            measureLine: { line in PixelFont.rawLineWidth(line, letterSpacing: style.letterSpacing) * max(style.scale, 0.01) }
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
        let horizontalAdvance = (Double(PixelFontAtlas.glyphWidth) + effectiveStyle.letterSpacing) * scale * displayScale
        let verticalAdvance = (Double(PixelFontAtlas.glyphHeight) * scale + effectiveStyle.lineSpacing * scale) * displayScale
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
        guard let layout = textSystem.layout(text, style: style, maxWidth: contentRect.size.width, scaleFactor: displayScale) else {
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
                   scaledVisibleClip.intersected(with: preflightRect) == nil {
                    continue
                }

                guard let preparedGlyph = NativeGlyphAtlas.shared.prepareGlyph(for: glyph, style: style, scaleFactor: displayScale),
                      let previewEntry = preparedGlyph.previewEntry
                else {
                    continue
                }
                guard previewEntry.width > 0, previewEntry.height > 0 else {
                    continue
                }

                let destinationOrigin = Point(
                    x: glyphLayoutOrigin.x + Double(previewEntry.bearingX),
                    y: glyphLayoutOrigin.y + Double(previewEntry.bearingY)
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
        opacity: Float,
        clip: Rect?,
        surfaceSize: Size,
        displayScale: Double,
        into quads: inout [QuadPrimitive]
    ) {
        guard color.alpha > 0 else {
            return
        }

        let rect = Rect(
            x: lineRect.origin.x,
            y: y,
            width: lineRect.size.width,
            height: thickness
        )
        guard clipAllowsDrawing(clip: clip, rect: rect) else {
            return
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
