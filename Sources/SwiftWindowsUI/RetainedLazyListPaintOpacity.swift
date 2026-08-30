import SwiftWindowsCore
import SwiftWindowsGraphics

extension RetainedLazyListPaintSource {
    /// Replays inherited opacity at the same boundary as ordinary painting.
    /// Inline siblings fade separately, while an explicit group's image fades
    /// once after its children have composed. Its owned child scene is never
    /// visited or rewritten here.
    ///
    /// The capture has already bounded and validated these namespaces. This
    /// projection allocates only primitive arrays and top-level gradient stops;
    /// atlas pixels, bitmaps and child passes retain their original value buffers.
    /// `permitsInheritedEffectOpacity` requires the original paint witness to
    /// prove that the retiring root had neither its own content blur nor color
    /// effects. Only then do top-level effect images belong to descendants and
    /// carry this root's opacity at their consuming image boundary.
    /// `permitsInheritedBackdropOpacity` additionally permits the original
    /// dependent namespace to rerun against its current backdrop. It requires
    /// the same witness and an outer isolated-backdrop image with opacity one;
    /// multiplying that image instead would fade overlapping children as a group.
    /// The caller still omits a root with nonpositive opacity, just as normal
    /// painting does: a zero-alpha material tint does not disable its blur.
    func sceneApplyingInheritedOpacity(
        _ multiplier: Float, permitsInheritedEffectOpacity: Bool = false,
        permitsInheritedBackdropOpacity: Bool = false
    ) -> GPUIScene? {
        let permitsBackdrop =
            input == .isolatedBackdrop && permitsInheritedEffectOpacity && permitsInheritedBackdropOpacity
        guard input == .independent || permitsBackdrop,
            multiplier.isFinite, multiplier >= 0,
            scene.clearColor == .clear,
            recordCount >= 0, recordCount <= Self.maximumRecordCount,
            resourceBytes >= 0, resourceBytes <= Self.maximumResourceBytes,
            scene.layers.count <= GPUISceneLimits.maxLayers,
            scene.imageRenderPasses.count <= GPUISceneLimits.maxImageRenderPassCount
        else { return nil }

        var permitsImageOpacity: [Int32: Bool] = [:]
        for pass in scene.imageRenderPasses {
            guard pass.textureID >= 0, permitsImageOpacity[pass.textureID] == nil else { return nil }
            // A color-effect isolation records its node's own opacity inside
            // the source, but places ancestor opacity on the consuming image.
            // Its finished values do not identify which boundary is retiring.
            // Multiplying the image would silently invent group opacity when
            // the retiring node owns that effect, even for luminanceToAlpha.
            // The caller's original paint witness establishes the descendant
            // case. A dependent child's image applies the same ancestor scalar
            // to its foreground and replacement coverage; its source retains
            // its own opacity and must not be multiplied recursively.
            switch pass.input {
            case .independent:
                permitsImageOpacity[pass.textureID] =
                    pass.contentBlurRadius == 0 && (permitsInheritedEffectOpacity || pass.colorEffects.isEmpty)
            case .currentTarget:
                permitsImageOpacity[pass.textureID] =
                    permitsBackdrop && pass.scene.clearColor == .clear
                    && pass.colorEffects.isEmpty && pass.contentBlurRadius == 0
            case .isolatedBackdrop:
                permitsImageOpacity[pass.textureID] = permitsBackdrop && pass.isolatedBackdropSourceDefect == nil
            }
        }

        var projected = GPUIScene(
            clearColor: scene.clearColor, glyphAtlas: scene.glyphAtlas, pixelGlyphAtlas: scene.pixelGlyphAtlas,
            imageResources: scene.imageResources, imageRenderPasses: scene.imageRenderPasses)
        projected.paintMetrics = scene.paintMetrics
        var count = 0
        for run in scene.presentationOrder() {
            for index in run.range {
                guard count < Self.maximumRecordCount else { return nil }
                count += 1
                switch scene.primitive(kind: run.kind, inLayer: run.layerIndex, at: index) {
                case .quad(var quad):
                    // A material reruns its original backdrop operation with
                    // the newly scaled tint. It never becomes independent.
                    // Fractional radii below one only soften ordinary edges;
                    // the native material path tests the truncated radius.
                    // Primitive effects, including native luminanceToAlpha,
                    // retain alpha multiplicatively at this same boundary.
                    guard quad.blendMode == 0,
                        GPUISceneValue.int(quad.blurRadius) <= 0 || permitsBackdrop
                    else { return nil }
                    quad.startA = Self.projectedAlpha(quad.startA, multiplier: multiplier)
                    quad.endA = Self.projectedAlpha(quad.endA, multiplier: multiplier)
                    projected.addQuad(quad, toLayer: run.layerIndex)
                case .glyph(var glyph):
                    glyph.colorA = Self.projectedAlpha(glyph.colorA, multiplier: multiplier)
                    projected.addGlyph(glyph, toLayer: run.layerIndex)
                case .pixelGlyph(var glyph):
                    glyph.colorA = Self.projectedAlpha(glyph.colorA, multiplier: multiplier)
                    projected.addPixelGlyph(glyph, toLayer: run.layerIndex)
                case .image(var image):
                    guard permitsImageOpacity[image.textureID] != false else { return nil }
                    image.opacity = Self.projectedAlpha(image.opacity, multiplier: multiplier)
                    projected.addImage(image, toLayer: run.layerIndex)
                case .shadow(var shadow):
                    shadow.colorA = Self.projectedAlpha(shadow.colorA, multiplier: multiplier)
                    projected.addShadow(shadow, toLayer: run.layerIndex)
                case .path(var path):
                    path.fillColor = path.fillColor.multipliedAlpha(by: multiplier)
                    path.strokeColor = path.strokeColor.multipliedAlpha(by: multiplier)
                    path.fillGradient = path.fillGradient.map { Self.projectedGradient($0, multiplier: multiplier) }
                    path.strokeGradient = path.strokeGradient.map { Self.projectedGradient($0, multiplier: multiplier) }
                    projected.addPath(path, toLayer: run.layerIndex)
                case nil:
                    return nil
                }
                guard projected.paintRecordCount == count else { return nil }
            }
        }
        guard count == scene.primitiveCount else { return nil }
        projected.finish()
        return projected
    }

    private static func projectedAlpha(_ alpha: Float, multiplier: Float) -> Float {
        max(0, min(1, alpha * multiplier))
    }

    private static func projectedGradient(_ gradient: LinearGradient, multiplier: Float) -> LinearGradient {
        var result = gradient
        result.stops = gradient.stops.map { stop in
            GradientStop(color: stop.color.multipliedAlpha(by: multiplier), position: stop.position)
        }
        return result
    }
}
