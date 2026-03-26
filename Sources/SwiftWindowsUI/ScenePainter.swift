import SwiftWindowsCore
import SwiftWindowsGraphics

/// Walks a ViewNode tree and produces a GPUIScene with typed primitive arrays,
/// mirroring the logic of ViewNode.appendCommands() but targeting the GPUI
/// instanced-rendering pipeline instead of the RenderCommand enum list.
@MainActor
public enum ScenePainter {

    public static func paint(root: ViewNode, clearColor: Color, surfaceSize: Size, displayScale: Double = 1.0) -> GPUIScene {
        var scene = GPUIScene(clearColor: clearColor)
        NativeGlyphAtlas.shared.beginFrame()
        let fullClip = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
        let deviceSurfaceSize = surfaceSize.scaled(by: max(displayScale, 1.0))
        paintNode(
            root,
            into: &scene,
            parentOrigin: .zero,
            inheritedClip: fullClip,
            surfaceSize: deviceSurfaceSize,
            displayScale: max(displayScale, 1.0)
        )
        if scene.layers.contains(where: { !$0.glyphs.isEmpty }) {
            if let atlas = NativeGlyphAtlas.shared.snapshotIfUsedInCurrentFrame() {
                scene.glyphAtlas = atlas
            } else {
                let atlas = PixelFontAtlas.shared.surface
                scene.glyphAtlas = GlyphAtlasSnapshot(width: atlas.width, height: atlas.height, pixels: atlas.pixels)
            }
        }
        return scene
    }

    // MARK: - Private

    private static func paintNode(
        _ node: ViewNode,
        into scene: inout GPUIScene,
        parentOrigin: Point,
        inheritedClip: Rect?,
        surfaceSize: Size,
        displayScale: Double
    ) {
        guard !node.isHidden else { return }

        let absoluteFrame = Rect(
            x: parentOrigin.x + node.resolvedFrame.origin.x,
            y: parentOrigin.y + node.resolvedFrame.origin.y,
            width: node.resolvedFrame.size.width,
            height: node.resolvedFrame.size.height
        )

        guard absoluteFrame.size.width > 0, absoluteFrame.size.height > 0 else { return }
        guard node.opacity > 0 else { return }

        // Occlusion culling against inherited clip.
        if !clipAllowsDrawing(clip: inheritedClip, rect: absoluteFrame) {
            return
        }

        var effectiveClip = inheritedClip
        if node.clipsToBounds {
            if let inherited = inheritedClip {
                guard let clipped = inherited.intersected(with: absoluteFrame) else {
                    return
                }
                effectiveClip = clipped
            } else {
                effectiveClip = absoluteFrame
            }
        }

        let layerIndex = scene.layers.count - 1
        let opacity = Float(node.opacity)

        // Shadow
        if node.shadowColor.alpha > 0 {
            let shadowRect = absoluteFrame
                .outset(by: max(0, node.shadowSpread))
                .offsetBy(dx: node.shadowOffset.x, dy: node.shadowOffset.y)

            if clipAllowsDrawing(clip: inheritedClip, rect: shadowRect) {
                let scaledShadowRect = scaleRect(shadowRect, by: displayScale)
                scene.layers[layerIndex].shadows.append(ShadowPrimitive(
                    x: Float(scaledShadowRect.origin.x),
                    y: Float(scaledShadowRect.origin.y),
                    width: Float(scaledShadowRect.size.width),
                    height: Float(scaledShadowRect.size.height),
                    cornerRadius: Float((node.cornerRadius + max(0, node.shadowSpread)) * displayScale),
                    colorR: node.shadowColor.red,
                    colorG: node.shadowColor.green,
                    colorB: node.shadowColor.blue,
                    colorA: node.shadowColor.alpha,
                    blurRadius: Float(node.shadowSpread * displayScale),
                    offsetX: Float(node.shadowOffset.x * displayScale),
                    offsetY: Float(node.shadowOffset.y * displayScale)
                ))
            }
        }

        // Outline (drawn outside the border)
        if node.outlineColor.alpha > 0, node.outlineWidth > 0 {
            let outlineRect = absoluteFrame.outset(by: node.outlineWidth)
            if clipAllowsDrawing(clip: inheritedClip, rect: outlineRect) {
                scene.layers[layerIndex].quads.append(solidQuad(
                rect: outlineRect,
                cornerRadius: node.cornerRadius + node.outlineWidth,
                color: node.outlineColor,
                opacity: opacity,
                clip: inheritedClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale
            ))
        }
        }

        // Border (full rect drawn under the fill area)
        if node.borderColor.alpha > 0, node.borderWidth > 0,
           clipAllowsDrawing(clip: effectiveClip, rect: absoluteFrame)
        {
            scene.layers[layerIndex].quads.append(solidQuad(
                rect: absoluteFrame,
                cornerRadius: node.cornerRadius,
                color: node.borderColor,
                opacity: opacity,
                clip: effectiveClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale
            ))
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

            scene.layers[layerIndex].quads.append(QuadPrimitive(
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
            ))
        }

        if let text = node.text, !text.isEmpty,
           fillRect.size.width > 0, fillRect.size.height > 0,
           clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
        {
            appendTextGlyphs(
                for: text,
                style: node.textStyle,
                in: fillRect,
                opacity: opacity,
                clip: effectiveClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale,
                into: &scene.layers[layerIndex].glyphs
            )
        }

        // Children -- sort by zIndex (stable), push new layers when zIndex changes.
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

        var currentZIndex = sortedChildren.first?.zIndex ?? 0
        for child in sortedChildren {
            if child.zIndex != currentZIndex {
                scene.pushLayer()
                currentZIndex = child.zIndex
            }
            paintNode(
                child,
                into: &scene,
                parentOrigin: childOrigin,
                inheritedClip: effectiveClip,
                surfaceSize: surfaceSize,
                displayScale: displayScale
            )
        }
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

    private static func appendTextGlyphs(
        for text: String,
        style: PixelTextStyle,
        in rect: Rect,
        opacity: Float,
        clip: Rect?,
        surfaceSize: Size,
        displayScale: Double,
        into glyphs: inout [GlyphPrimitive]
    ) {
        guard !text.isEmpty, style.color.alpha > 0 else {
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
            into: &glyphs
        ) {
            return
        }

        let contentRect = rect.inset(by: style.insets)
        let scale = max(style.scale, 1)
        let layout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: { line in PixelFont.rawLineWidth(line, letterSpacing: style.letterSpacing) * scale }
        )
        let totalTextHeight = (
            Double(max(layout.lines.count, 1) * PixelFontAtlas.glyphHeight) +
            Double(max(layout.lines.count - 1, 0)) * style.lineSpacing
        ) * scale

        let startY: Double
        switch style.verticalAlignment {
        case .top:
            startY = contentRect.origin.y
        case .center:
            startY = contentRect.origin.y + max(0, (contentRect.size.height - totalTextHeight) * 0.5)
        case .bottom:
            startY = contentRect.maxY - totalTextHeight
        }

        let clipRect = clipRectFloats(clip, surfaceSize: surfaceSize, displayScale: displayScale)
        let glyphWidth = Double(PixelFontAtlas.glyphWidth) * scale * displayScale
        let glyphHeight = Double(PixelFontAtlas.glyphHeight) * scale * displayScale
        let horizontalAdvance = (Double(PixelFontAtlas.glyphWidth) + style.letterSpacing) * scale * displayScale
        let verticalAdvance = (Double(PixelFontAtlas.glyphHeight) * scale + style.lineSpacing * scale) * displayScale
        var cursorY = startY * displayScale

        for line in layout.lines {
            let lineWidth = PixelFont.rawLineWidth(line, letterSpacing: style.letterSpacing) * scale
            let startX: Double
            switch style.alignment {
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

                let atlas = PixelFontAtlas.shared
                let entry = PixelFontAtlas.glyph(for: character)
                let uv = entry.uvRect(atlasWidth: atlas.surface.width, atlasHeight: atlas.surface.height)
                glyphs.append(
                    GlyphPrimitive(
                        screenX: Float(cursorX),
                        screenY: Float(cursorY),
                        screenW: Float(glyphWidth),
                        screenH: Float(glyphHeight),
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
        into glyphs: inout [GlyphPrimitive]
    ) -> Bool {
        guard !text.unicodeScalars.contains(where: isPrivateUseScalar) else {
            return false
        }

        var glyphStyle = style
        glyphStyle.insets = .zero
        glyphStyle.maximumNumberOfLines = 1

        let contentRect = rect.inset(by: style.insets)
        let measureLine: (String) -> Double = { line in
            NativeTextRenderer.measure(line, style: glyphStyle, scaleFactor: displayScale, maxWidth: nil)?.width ?? 0
        }
        let layout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: measureLine
        )

        let lineHeight = NativeTextRenderer.measure("Ag", style: glyphStyle, scaleFactor: displayScale, maxWidth: nil)?.height
            ?? max(1, style.nativeFontPixelSize / max(displayScale, 1))
        let totalTextHeight = lineHeight * Double(max(layout.lines.count, 1))
            + style.lineSpacing * Double(max(layout.lines.count - 1, 0))

        let startY: Double
        switch style.verticalAlignment {
        case .top:
            startY = contentRect.origin.y
        case .center:
            startY = contentRect.origin.y + max(0, (contentRect.size.height - totalTextHeight) * 0.5)
        case .bottom:
            startY = contentRect.maxY - totalTextHeight
        }

        let clipRect = clipRectFloats(clip, surfaceSize: surfaceSize, displayScale: displayScale)
        var appendedAnyGlyph = false
        var cursorY = startY

        for line in layout.lines {
            let lineWidth = measureLine(line)
            let startX: Double
            switch style.alignment {
            case .leading:
                startX = contentRect.origin.x
            case .center:
                startX = contentRect.origin.x + max(0, (contentRect.size.width - lineWidth) * 0.5)
            case .trailing:
                startX = contentRect.maxX - lineWidth
            }

            var previousAdvance = 0.0
            var prefix = ""

            for character in line {
                let nextPrefix = prefix + String(character)
                let totalAdvance = measureLine(nextPrefix)
                defer {
                    prefix = nextPrefix
                    previousAdvance = totalAdvance
                }

                guard character != " " else {
                    continue
                }

                guard let entry = NativeGlyphAtlas.shared.glyph(for: character, style: glyphStyle, scaleFactor: displayScale) else {
                    continue
                }

                let destinationRect = Rect(
                    x: (startX + previousAdvance) * displayScale,
                    y: cursorY * displayScale,
                    width: Double(entry.width),
                    height: Double(entry.height)
                )

                let atlasSize = NativeGlyphAtlas.shared.size
                let uv = entry.uvRect(atlasWidth: atlasSize.width, atlasHeight: atlasSize.height)
                glyphs.append(
                    GlyphPrimitive(
                        screenX: Float(destinationRect.origin.x),
                        screenY: Float(destinationRect.origin.y),
                        screenW: Float(destinationRect.size.width),
                        screenH: Float(destinationRect.size.height),
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
                appendedAnyGlyph = true
            }

            cursorY += lineHeight + style.lineSpacing
        }

        return appendedAnyGlyph
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
