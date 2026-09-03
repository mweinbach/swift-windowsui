import Foundation
import SwiftWindowsCore

/// Builds a 1D Gaussian kernel suitable for a separable two-pass blur.
/// Sigma is `radius / 2.0` so a `radius=6` blur visually matches what a
/// 6-pixel box approximation roughly produced before — but with a real
/// bell-shaped falloff instead of uniform weighting. Materials' soft
/// backdrop now looks like macOS visual-effects blur instead of a
/// "smeared rectangle" box approximation.
///
/// Public so tests can verify the kernel shape directly, and so the D3D11
/// backdrop-blur engine uploads the exact same weights.
public func gaussianBlurKernel(radius: Int) -> [Float] {
    precondition(radius > 0)
    let sigma = max(Float(radius) / 2.0, 0.5)
    let twoSigmaSq = 2 * sigma * sigma
    let size = radius * 2 + 1
    var kernel = [Float](repeating: 0, count: size)
    var sum: Float = 0
    for i in 0..<size {
        let offset = Float(i - radius)
        let weight = exp(-(offset * offset) / twoSigmaSq)
        kernel[i] = weight
        sum += weight
    }
    // Normalise so weights sum to 1.0; the blurred result has the same
    // overall brightness as the input.
    if sum > 0 {
        for i in 0..<size { kernel[i] /= sum }
    }
    return kernel
}

/// Rotates the offset `(dx, dy)` from the centre by `(cosR, sinR)` and
/// returns the resulting world-space point. Used by the rasterizer's
/// rotated-quad path to compute the bounding box of a rotated rect.
private func rotatedCorner(_ dx: Double, _ dy: Double, cosR: Double, sinR: Double, centre: Point) -> Point {
    Point(x: centre.x + cosR * dx - sinR * dy, y: centre.y + sinR * dx + cosR * dy)
}

public enum GPUIRawSceneRasterizer {
    public static func rasterize(_ scene: GPUIScene, size: IntSize) -> BitmapSurface {
        rasterize(scene, size: size, imageRenderPassBudget: GPUISceneImageRenderPassBudget())
    }

    /// A value-scoped test seam exercises exhaustion with tiny images without
    /// allocating the production budget or changing process-global limits.
    internal static func rasterize(
        _ scene: GPUIScene, size: IntSize, imageRenderPassBudget: GPUISceneImageRenderPassBudget
    ) -> BitmapSurface {
        var budget = imageRenderPassBudget
        return rasterize(
            scene, size: size, imageRenderPassDepth: 0, imageRenderPassBudget: &budget)
    }

    private static func rasterize(
        _ scene: GPUIScene, size: IntSize, imageRenderPassDepth: Int,
        imageRenderPassBudget: inout GPUISceneImageRenderPassBudget
    ) -> BitmapSurface {
        // Clamped at both ends: the backing buffer is `width * height * 4`
        // bytes and `bitmapSurface()` reports the stride as an `Int32`, so
        // an absurd surface size is an allocation failure or an overflow
        // trap rather than a picture.
        let width = min(max(1, Int(size.width)), GPUISceneLimits.maxSurfaceDimension)
        let height = min(max(1, Int(size.height)), GPUISceneLimits.maxSurfaceDimension)
        var target = RasterTarget(width: width, height: height, clearColor: scene.clearColor)
        // `uniquingKeysWith:` rather than `uniqueKeysWithValues:`: duplicate
        // texture IDs are a producer bug, not a reason to trap the process.
        // Last binding wins, matching `bindImageResource`'s overwrite.
        let imageBindings = Dictionary(
            scene.imageResources.map { ($0.textureID, $0.bitmap) }, uniquingKeysWith: { _, latest in latest })

        rasterizeLayerOperations(
            in: scene, target: &target, imageBindings: imageBindings,
            imageRenderPassDepth: imageRenderPassDepth, imageRenderPassBudget: &imageRenderPassBudget)

        return target.bitmapSurface()
    }

    public static func rasterize(_ frame: RenderFrame, size: IntSize) -> BitmapSurface {
        rasterize(frame, size: size, onBitmapPlacementFailure: nil)
    }

    /// Retains the frame bridge's explicit partial-frame admission. The observer
    /// receives typed placement refusals once; nil reports to stderr rather than
    /// silently omitting rejected bitmap commands. The original overload keeps
    /// its two-argument function type.
    public static func rasterize(
        _ frame: RenderFrame, size: IntSize,
        onBitmapPlacementFailure: ((FrameBitmapPlacementFailure) -> Void)?
    ) -> BitmapSurface {
        let surfaceSize = Size(width: Double(max(1, size.width)), height: Double(max(1, size.height)))
        return rasterize(
            GPUIScene(from: frame, surfaceSize: surfaceSize, onBitmapPlacementFailure: onBitmapPlacementFailure),
            size: size)
    }

    /// Rasterize a single path primitive to a bitmap sized to its masked bounds.
    /// Returns `nil` if the path has empty bounds.
    ///
    /// Public and reachable with an unsanitized primitive — the D3D11
    /// path-texture cache calls it directly — so the size derivation
    /// saturates and clamps rather than trusting `bounds`.
    public static func rasterizePath(_ path: PathPrimitive) -> BitmapSurface? {
        guard let path = GPUISceneSanitizer.sanitized(path),
            let maskedBounds = path.contentMaskedBounds, !maskedBounds.isEmpty
        else {
            return nil
        }

        let width = min(
            max(1, GPUISceneValue.int(maskedBounds.width.rounded(.up))), GPUISceneLimits.maxSurfaceDimension)
        let height = min(
            max(1, GPUISceneValue.int(maskedBounds.height.rounded(.up))), GPUISceneLimits.maxSurfaceDimension)
        let offset = Point(x: -maskedBounds.origin.x, y: -maskedBounds.origin.y)
        let translated = path.translated(by: offset)

        var scene = GPUIScene(clearColor: .clear)
        scene.addPath(translated, toLayer: 0)
        scene.finish()

        return rasterize(scene, size: IntSize(width: Int32(width), height: Int32(height)))
    }

    /// Draws the scene in `presentationOrder()` — the same layer-major
    /// walk over `layer.paintOperations` the D3D11 plan builder makes.
    ///
    /// This used to prefer a second walk over the flat `paintRecords` log,
    /// which discarded `layerIndex`, so an interleaved multi-layer scene
    /// rendered in insertion order here and in layer order on the GPU. No
    /// screenshot could ever show the difference, because every screenshot
    /// came through this function.
    private static func rasterizeLayerOperations(
        in scene: GPUIScene,
        target: inout RasterTarget,
        imageBindings: [Int32: BitmapSurface],
        imageRenderPassDepth: Int,
        imageRenderPassBudget: inout GPUISceneImageRenderPassBudget
    ) {
        var resolvedImages = imageBindings
        let passes = Dictionary(
            scene.imageRenderPasses.map { ($0.textureID, $0) }, uniquingKeysWith: { _, last in last })
        for run in scene.presentationOrder() {
            let layer = scene.layers[run.layerIndex]
            switch run.kind {
            case .shadow:
                for index in run.range { target.drawShadow(layer.shadows[index]) }
            case .quad:
                for index in run.range { target.drawQuad(layer.quads[index]) }
            case .glyph:
                for index in run.range { target.drawGlyph(layer.glyphs[index], atlas: scene.glyphAtlas) }
            case .pixelGlyph:
                for index in run.range { target.drawGlyph(layer.pixelGlyphs[index], atlas: scene.pixelGlyphAtlas) }
            case .image:
                for index in run.range {
                    let textureID = layer.images[index].textureID
                    if imageBindings[textureID] == nil, let pass = passes[textureID] {
                        switch pass.input {
                        case .currentTarget:
                            rasterizeCurrentTargetImage(
                                layer.images[index], pass: pass, target: &target,
                                imageRenderPassDepth: imageRenderPassDepth,
                                imageRenderPassBudget: &imageRenderPassBudget)
                            continue
                        case .isolatedBackdrop:
                            rasterizeIsolatedBackdropImage(
                                layer.images[index], pass: pass, target: &target,
                                imageRenderPassDepth: imageRenderPassDepth,
                                imageRenderPassBudget: &imageRenderPassBudget)
                            continue
                        case .independent:
                            break
                        }
                    }
                    if resolvedImages[textureID] == nil, let pass = passes[textureID] {
                        if pass.hasValidExtent,
                            pass.colorEffects.count <= GPUISceneLimits.maxColorEffects,
                            pass.contentBlurRadiusDefect == nil,
                            imageRenderPassDepth < GPUISceneLimits.maxImageRenderPassDepth,
                            imageRenderPassBudget.consume(pass)
                        {
                            let bitmap = rasterize(
                                pass.scene, size: pass.size, imageRenderPassDepth: imageRenderPassDepth + 1,
                                imageRenderPassBudget: &imageRenderPassBudget)
                            resolvedImages[textureID] = SceneColorEffects.applying(pass.colorEffects, to: bitmap)
                        } else {
                            // The software reference cannot throw through its
                            // historical API. A conspicuous unsupported tile
                            // makes a rejected effect visible; validate() gives
                            // the caller its precise structural diagnosis.
                            resolvedImages[textureID] = BitmapSurface(
                                width: 2, height: 2, bytesPerRow: 8,
                                pixels: Data([255, 0, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 0, 255, 255]))
                        }
                    }
                    if let bitmap = resolvedImages[textureID] {
                        target.drawImage(layer.images[index], bitmap: bitmap)
                    }
                }
            case .path:
                for index in run.range { target.drawPath(layer.paths[index]) }
            }
        }
    }

    private static func rasterizeCurrentTargetImage(
        _ image: ImagePrimitive, pass: GPUISceneImageRenderPass,
        target: inout RasterTarget, imageRenderPassDepth: Int,
        imageRenderPassBudget: inout GPUISceneImageRenderPassBudget
    ) {
        let parentSize = IntSize(width: Int32(target.width), height: Int32(target.height))
        guard let region = pass.currentTargetRegion(for: image, parentSize: parentSize),
            imageRenderPassDepth < GPUISceneLimits.maxImageRenderPassDepth
        else {
            drawRejectedImage(image, target: &target)
            return
        }

        if target.isBackdropIsolated {
            // Preserve the original current-target placement restrictions. Only
            // its result representation changes inside a dependent isolation:
            // seeding the foreground would make the whole rectangle participate
            // in an enclosing content blur, including untouched parent pixels.
            var isolatedPass = pass
            isolatedPass.input = .isolatedBackdrop
            isolatedPass.contentBlurRadius = 0
            guard let mapping = isolatedPass.isolatedBackdropMapping(for: image, parentSize: parentSize),
                imageRenderPassBudget.consume(pass, inBackdropIsolation: true)
            else {
                drawRejectedImage(image, target: &target)
                return
            }
            rasterizeBackdropIsolation(
                image, pass: isolatedPass, mapping: mapping, target: &target,
                imageRenderPassDepth: imageRenderPassDepth, imageRenderPassBudget: &imageRenderPassBudget)
            return
        }

        guard imageRenderPassBudget.consume(pass) else {
            drawRejectedImage(image, target: &target)
            return
        }

        // Copy the current prefix only after admission and the execution charge.
        // This target owns straight-alpha bytes, just like its enclosing target;
        // a premultiplied conversion here would needlessly quantize the seed.
        var child = RasterTarget(cropping: target, to: region)
        let bindings = Dictionary(
            pass.scene.imageResources.map { ($0.textureID, $0.bitmap) }, uniquingKeysWith: { _, latest in latest })
        rasterizeLayerOperations(
            in: pass.scene, target: &child, imageBindings: bindings,
            imageRenderPassDepth: imageRenderPassDepth + 1, imageRenderPassBudget: &imageRenderPassBudget)
        target.replaceImage(image, with: child, in: region)
    }

    private static func rasterizeIsolatedBackdropImage(
        _ image: ImagePrimitive, pass: GPUISceneImageRenderPass,
        target: inout RasterTarget, imageRenderPassDepth: Int,
        imageRenderPassBudget: inout GPUISceneImageRenderPassBudget
    ) {
        let parentSize = IntSize(width: Int32(target.width), height: Int32(target.height))
        guard let mapping = pass.isolatedBackdropMapping(for: image, parentSize: parentSize),
            imageRenderPassDepth < GPUISceneLimits.maxImageRenderPassDepth,
            imageRenderPassBudget.consume(pass, inBackdropIsolation: target.isBackdropIsolated)
        else {
            drawRejectedImage(image, target: &target)
            return
        }

        rasterizeBackdropIsolation(
            image, pass: pass, mapping: mapping, target: &target,
            imageRenderPassDepth: imageRenderPassDepth, imageRenderPassBudget: &imageRenderPassBudget)
    }

    /// Mapping and all source/scratch reservations have succeeded before this
    /// function creates any child planes. Every occurrence owns a fresh frozen
    /// backdrop and its child's resource namespace; none enters resolvedImages.
    private static func rasterizeBackdropIsolation(
        _ image: ImagePrimitive, pass: GPUISceneImageRenderPass,
        mapping: GPUISceneBackdropIsolationMapping, target: inout RasterTarget,
        imageRenderPassDepth: Int, imageRenderPassBudget: inout GPUISceneImageRenderPassBudget
    ) {
        var child = RasterTarget(isolating: target, mapping: mapping)
        let bindings = Dictionary(
            pass.scene.imageResources.map { ($0.textureID, $0.bitmap) }, uniquingKeysWith: { _, latest in latest })
        rasterizeLayerOperations(
            in: pass.scene, target: &child, imageBindings: bindings,
            imageRenderPassDepth: imageRenderPassDepth + 1, imageRenderPassBudget: &imageRenderPassBudget)
        let result = child.finishBackdropIsolation(radius: Int(pass.contentBlurRadius))
        target.compositeIsolatedImage(image, result: result, mapping: mapping)
    }

    private static func drawRejectedImage(_ image: ImagePrimitive, target: inout RasterTarget) {
        // The software reference cannot throw through its historical API. Keep
        // rejection visible without caching a parent-dependent diagnostic.
        let diagnostic = BitmapSurface(
            width: 2, height: 2, bytesPerRow: 8,
            pixels: Data([255, 0, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 0, 255, 255]))
        target.drawImage(image, bitmap: diagnostic)
    }
}
/// One axis of a bilinear tap, matching `D3D11_FILTER_MIN_MAG_MIP_LINEAR`
/// with `D3D11_TEXTURE_ADDRESS_CLAMP` — the sampler both the glyph and the
/// image pipeline bind (`D3D11BatchRenderer.createSamplerState`).
///
/// Texel centres sit at `(i + 0.5) / size`, so a normalized coordinate maps to
/// texel space as `u * size - 0.5`; the two taps are that value's floor and
/// floor + 1, clamped into range, weighted by its fraction. Clamping `u` into
/// `[0, 1]` first is equivalent to the hardware's index clamping and keeps the
/// `Double → Int` conversion in range for any scene value.
///
/// At a texel-aligned 1:1 draw the fraction is 0 and this returns exactly the
/// texel nearest sampling would have picked, which is why unmagnified glyph
/// and image output is unchanged by the switch.
private struct BilinearAxisTap {
    let low: Int
    let high: Int
    let fraction: Double

    init(_ tap: ImageSamplingAxisTap) {
        low = tap.low
        high = tap.high
        fraction = tap.fraction
    }

    /// The caller has already bounded this index against the actual bitmap.
    init(exactIndex: Int) {
        low = exactIndex
        high = exactIndex
        fraction = 0
    }

    init(normalized: Double, size: Int) {
        let bounded = clamp(normalized, lower: 0, upper: 1)
        let texel = bounded * Double(size) - 0.5
        let floored = texel.rounded(.down)
        fraction = texel - floored
        let lowIndex = GPUISceneValue.int(floored)
        low = clamp(lowIndex, lower: 0, upper: size - 1)
        high = clamp(lowIndex + 1, lower: 0, upper: size - 1)
    }
}

/// A texel in the space the GPU image sampler filters in.
private struct PremultipliedTexel {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

/// Bilinear blend of four taps, laid out as the hardware does it: lerp along
/// x on each row, then lerp the two rows along y.
@inline(__always)
private func bilinearMix(
    _ topLeft: Double, _ topRight: Double, _ bottomLeft: Double, _ bottomRight: Double,
    fractionX: Double, fractionY: Double
) -> Double {
    let top = topLeft + (topRight - topLeft) * fractionX
    let bottom = bottomLeft + (bottomRight - bottomLeft) * fractionX
    return top + (bottom - top) * fractionY
}

/// A path-local colour ramp prepared once per fill/stroke rather than sorting
/// authored stops again for every covered pixel.
private struct RasterPathGradient {
    private struct Segment {
        var startColor: RasterColor
        var endColor: RasterColor
        var start: Float
        var end: Float
    }

    private let segments: [Segment]
    private let origin: Point
    private let vectorX: Double
    private let vectorY: Double
    private let vectorLengthSquared: Double
    let hasVisibleStops: Bool

    init(_ gradient: LinearGradient, space: PathGradientSpace) {
        segments = gradient.renderedSegments.map {
            Segment(
                startColor: RasterColor($0.startColor),
                endColor: RasterColor($0.endColor),
                start: $0.start,
                end: $0.end)
        }
        hasVisibleStops = segments.contains { $0.startColor.alpha > 0 || $0.endColor.alpha > 0 }
        origin = space.origin
        let end = gradient.axis == .horizontal ? space.horizontalEnd : space.verticalEnd
        vectorX = end.x - origin.x
        vectorY = end.y - origin.y
        vectorLengthSquared = vectorX * vectorX + vectorY * vectorY
    }

    func color(atPixelX x: Int, y: Int) -> RasterColor {
        guard !segments.isEmpty else { return RasterColor(.clear) }

        let progress: Float
        if vectorLengthSquared > 0, vectorLengthSquared.isFinite {
            let offsetX = Double(x) + 0.5 - origin.x
            let offsetY = Double(y) + 0.5 - origin.y
            let projection = (offsetX * vectorX + offsetY * vectorY) / vectorLengthSquared
            progress = Float(clamp(projection, lower: 0, upper: 1))
        } else {
            progress = 0
        }

        // Intervals are half-open except for the final one. Choosing the next
        // interval at its exact start preserves duplicate-position hard stops
        // without blending two translucent colours over one another.
        var low = 0
        var high = segments.count - 1
        while low < high {
            let middle = low + (high - low) / 2
            if progress < segments[middle].end {
                high = middle
            } else {
                low = middle + 1
            }
        }

        let segment = segments[low]
        let length = segment.end - segment.start
        let localProgress = length > 0 ? (progress - segment.start) / length : 0
        return segment.startColor.interpolated(to: segment.endColor, progress: localProgress)
    }
}

/// A completed dependent subtree. Foreground is premultiplied; coverage says
/// how much of the immediate parent it replaces and may exceed foreground
/// alpha for a material over a translucent backdrop.
private struct RasterIsolatedImage {
    var width: Int
    var height: Int
    var premultipliedPixels: [UInt8]
    var coverage: [UInt8]
}

private struct RasterTarget {
    var width: Int
    var height: Int
    var pixels: [UInt8]
    private var backdropPixels: [UInt8] = []
    private var replacementCoverage: [UInt8] = []
    private var validBackdropRegion: SubTextureRegion?

    var isBackdropIsolated: Bool { !replacementCoverage.isEmpty }

    init(width: Int, height: Int, clearColor: Color) {
        self.width = width
        self.height = height
        self.pixels = Array(repeating: 0, count: width * height * 4)

        let color = RasterColor(clearColor)
        for y in 0..<height {
            for x in 0..<width {
                writeOpaque(color, x: x, y: y)
            }
        }
    }

    /// Called only with a wholly contained 1:1 region admitted against `parent`.
    /// Copy all seed pixels before drawing the child; output clipping is separate.
    init(cropping parent: RasterTarget, to region: SubTextureRegion) {
        width = region.width
        height = region.height
        pixels = Array(repeating: 0, count: width * height * 4)
        let rowBytes = width * 4
        for row in 0..<height {
            let source = ((region.originY + row) * parent.width + region.originX) * 4
            let destination = row * rowBytes
            pixels.replaceSubrange(
                destination..<(destination + rowBytes), with: parent.pixels[source..<(source + rowBytes)])
        }
    }

    /// The mapping was admitted against this actual parent and its reservation
    /// paid before entry. Copy only available pixels; material reads clamp D to
    /// this region without making the transparent foreground halo opaque.
    init(isolating parent: RasterTarget, mapping: GPUISceneBackdropIsolationMapping) {
        width = Int(mapping.size.width)
        height = Int(mapping.size.height)
        pixels = Array(repeating: 0, count: width * height * 4)
        backdropPixels = Array(repeating: 0, count: width * height * 4)
        replacementCoverage = Array(repeating: 0, count: width * height)
        validBackdropRegion = mapping.validChildRegion

        guard let region = mapping.parentCopyRegion else { return }
        for row in 0..<region.height {
            for column in 0..<region.width {
                // An isolated parent's virtual composition is defined over its
                // whole canvas, including earlier local drawing in its halo.
                // Its child must not inherit a narrower grandparent rectangle.
                let color = parent.premultipliedColor(x: region.originX + column, y: region.originY + row)
                let destination = ((mapping.childOffsetY + row) * width + mapping.childOffsetX + column) * 4
                backdropPixels[destination] = byte(color.blue)
                backdropPixels[destination + 1] = byte(color.green)
                backdropPixels[destination + 2] = byte(color.red)
                backdropPixels[destination + 3] = byte(color.alpha)
            }
        }
    }

    mutating func finishBackdropIsolation(radius: Int) -> RasterIsolatedImage {
        var coverage = replacementCoverage
        replacementCoverage = []
        backdropPixels = []
        validBackdropRegion = nil

        // D is no longer needed. Convert F in place, then use exactly the same
        // byte-quantized Gaussian plan for color and replacement coverage.
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Float(pixels[offset + 3]) / 255
            pixels[offset] = byte(Float(pixels[offset]) / 255 * alpha)
            pixels[offset + 1] = byte(Float(pixels[offset + 1]) / 255 * alpha)
            pixels[offset + 2] = byte(Float(pixels[offset + 2]) / 255 * alpha)
        }
        if radius > 0 {
            PremultipliedImageBlur.blur(&pixels, width: width, height: height, radius: radius)
            var expandedCoverage = [UInt8](repeating: 0, count: width * height * 4)
            for index in coverage.indices { expandedCoverage[index * 4 + 3] = coverage[index] }
            PremultipliedImageBlur.blur(&expandedCoverage, width: width, height: height, radius: radius)
            for index in coverage.indices { coverage[index] = expandedCoverage[index * 4 + 3] }
        }
        return RasterIsolatedImage(
            width: width, height: height, premultipliedPixels: pixels, coverage: coverage)
    }

    /// F + (1 - C)D is the virtual immediate-parent surface. Clamp only D:
    /// local foreground and coverage at an out-of-parent pixel still belong to
    /// that pixel, and must not disappear when another material reads them.
    private func premultipliedColor(x: Int, y: Int) -> RasterColor {
        let offset = pixelOffset(x: x, y: y)
        let alpha = Float(pixels[offset + 3]) / 255
        var color = RasterColor(
            red: Float(pixels[offset + 2]) / 255 * alpha,
            green: Float(pixels[offset + 1]) / 255 * alpha,
            blue: Float(pixels[offset]) / 255 * alpha,
            alpha: alpha)
        guard isBackdropIsolated, let region = validBackdropRegion, !region.isEmpty else { return color }
        let backdropX = clamp(x, lower: region.originX, upper: region.maxX - 1)
        let backdropY = clamp(y, lower: region.originY, upper: region.maxY - 1)
        let backdropOffset = pixelOffset(x: backdropX, y: backdropY)
        let retained = 1 - Float(replacementCoverage[y * width + x]) / 255
        color.blue += Float(backdropPixels[backdropOffset]) / 255 * retained
        color.green += Float(backdropPixels[backdropOffset + 1]) / 255 * retained
        color.red += Float(backdropPixels[backdropOffset + 2]) / 255 * retained
        color.alpha += Float(backdropPixels[backdropOffset + 3]) / 255 * retained
        return color
    }

    mutating func drawQuad(_ quad: QuadPrimitive) {
        let rect = Rect(
            x: Double(quad.x),
            y: Double(quad.y),
            width: Double(quad.width),
            height: Double(quad.height)
        )
        let rotation = Double(quad.rotationRadians)
        guard
            !GPUIClipEncoding.isEmpty(
                clipX: quad.clipX, clipY: quad.clipY, clipWidth: quad.clipWidth, clipHeight: quad.clipHeight)
        else {
            return
        }
        let clip = GPUIClipRegion(
            x: quad.clipX, y: quad.clipY, width: quad.clipWidth, height: quad.clipHeight,
            cornerRadius: quad.clipCornerRadius,
            cornerRadii: GPUIQuadCoverage.CornerRadii(
                topLeft: Double(quad.clipCornerRadiusTopLeft), topRight: Double(quad.clipCornerRadiusTopRight),
                bottomRight: Double(quad.clipCornerRadiusBottomRight),
                bottomLeft: Double(quad.clipCornerRadiusBottomLeft)),
            shapeBounds: quad.clipShapeBounds)
        // Pixel-scan bounds and the (x, y) → local-coords mapping, shared
        // with every other rotation-carrying family. For rotation == 0 the
        // local coords are the pixel center, preserving byte-identical
        // output with the historic axis-aligned fast path.
        guard let scan = rotatedScan(rect, rotation: rotation, clip: clip.rect) else { return }
        let bounds = scan.bounds
        let localOf = scan.localOf

        // Resolve the effective corner radii: per-corner values win when
        // the primitive carries any; otherwise broadcast the uniform
        // cornerRadius — the same rule the shader's vertex stage applies.
        let radii: GPUIQuadCoverage.CornerRadii
        if quad.usesPerCornerRadii {
            radii = GPUIQuadCoverage.CornerRadii(
                topLeft: Double(quad.cornerRadiusTopLeft),
                topRight: Double(quad.cornerRadiusTopRight),
                bottomRight: Double(quad.cornerRadiusBottomRight),
                bottomLeft: Double(quad.cornerRadiusBottomLeft))
        } else {
            radii = GPUIQuadCoverage.CornerRadii(uniform: max(0, Double(quad.cornerRadius)))
        }
        let start = RasterColor(red: quad.startR, green: quad.startG, blue: quad.startB, alpha: quad.startA)
        let end = RasterColor(red: quad.endR, green: quad.endG, blue: quad.endB, alpha: quad.endA)

        // Capped at the shared engine limit the GPU's backdrop blur
        // honours too (`GPUISceneLimits.maxBlurRadius`), so the two
        // backends truncate at the same radius or not at all: the
        // separable blur below is O(w·h·r) and allocates a `2r+1` kernel,
        // so an uncapped radius is an unbounded frame even before the
        // conversion trap.
        //
        // The predicate is `> 0` after truncation, which is exactly
        // `D3D11BatchRenderer.splitQuadRangeForBackdropBlur`'s: a quad
        // that blurs here takes the backdrop path there.
        let blurRadius = min(GPUISceneValue.int(quad.blurRadius), Int(GPUISceneLimits.maxBlurRadius))
        if blurRadius > 0 {
            drawMaterialQuad(
                quad, rect: rect, radii: radii, clip: clip, bounds: bounds, localOf: localOf,
                start: start, end: end, blurRadius: blurRadius)
            return
        }

        // Only the three exact authored selectors are implemented. A material
        // already returned through its distinct replacement path above.
        let separableBlendMode = SceneSeparableBlendCompositing.mode(for: quad.blendMode)

        // The plain quad shader widens its edge falloff by `blurRadius * 2`
        // instead of blurring. Only sub-pixel radii ever reach it — anything
        // that truncates to ≥ 1 went to the material path above — but the
        // term is transcribed rather than dropped so the two agree there too.
        let extraEdgeSoftness = 2 * max(Double(quad.blurRadius), 0)
        let distanceAt = quadDistanceSampler(rect: rect, radii: radii, localOf: localOf)
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                // Clip is in world (pre-rotation) coordinates; use the
                // world pixel center, not the local-rotated one.
                let clipAlpha = clip.alpha(atPixelX: x, y: y)
                guard clipAlpha > 0 else { continue }
                let (localX, localY) = localOf(Double(x) + 0.5, Double(y) + 0.5)
                guard GPUIQuadCoverage.geometryCovers(localX: localX, localY: localY, rect: rect) else { continue }
                let coverage = GPUIQuadCoverage.coverage(
                    pixelX: x, pixelY: y, extraEdgeSoftness: extraEdgeSoftness, distanceAt: distanceAt)
                guard coverage > 0 else { continue }

                guard
                    let color = shadedQuadColor(
                        quad, start: start, end: end, localX: localX, localY: localY, rect: rect)
                else { continue }
                blend(
                    color.withAlphaMultiplier(Float(coverage * clipAlpha)), x: x, y: y,
                    separableMode: separableBlendMode)
            }
        }
    }

    /// Wraps a quad's geometry as the surface-space distance function
    /// `GPUIQuadCoverage.coverage` samples. The inverse rotation lives in
    /// `localOf`, so the finite difference the coverage function takes is
    /// a screen-space one — which is where `fwidth` takes it.
    private func quadDistanceSampler(
        rect: Rect,
        radii: GPUIQuadCoverage.CornerRadii,
        localOf: @escaping (Double, Double) -> (Double, Double)
    ) -> (Double, Double) -> Double {
        { sampleX, sampleY in
            let (localX, localY) = localOf(sampleX, sampleY)
            return GPUIQuadCoverage.signedDistance(
                localX: localX - rect.minX, localY: localY - rect.minY,
                width: rect.size.width, height: rect.size.height, radii: radii)
        }
    }

    /// The material/backdrop-blur path, ported from the GPU's ordering:
    /// snapshot the scene-so-far under the quad, blur *that*, then
    /// composite the tint over the blurred copy and write the result
    /// through the quad's own coverage.
    ///
    /// The rasterizer used to draw the tint into the framebuffer and blur
    /// the result in place over the quad's whole axis-aligned scan window.
    /// Two consequences, both visible in every screenshot of a card: the
    /// backdrop *outside* a rounded corner was smeared into a square halo,
    /// and `blurOpaque` overwrote the same window's alpha unconditionally,
    /// so an opaque material's rounded corners became square opaque
    /// blocks. Compositing through coverage cannot express either.
    private mutating func drawMaterialQuad(
        _ quad: QuadPrimitive,
        rect: Rect,
        radii: GPUIQuadCoverage.CornerRadii,
        clip: GPUIClipRegion,
        bounds: PixelBounds,
        localOf: @escaping (Double, Double) -> (Double, Double),
        start: RasterColor,
        end: RasterColor,
        blurRadius: Int
    ) {
        let regionWidth = bounds.width
        let regionHeight = bounds.height
        guard regionWidth > 0, regionHeight > 0 else { return }

        var backdrop = premultipliedRegion(bounds)
        blurPremultipliedRegion(&backdrop, width: regionWidth, height: regionHeight, radius: blurRadius)
        let forcesOpaque = quad.blurOpaque > 0.5
        let distanceAt = quadDistanceSampler(rect: rect, radii: radii, localOf: localOf)

        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let clipAlpha = clip.alpha(atPixelX: x, y: y)
                guard clipAlpha > 0 else { continue }
                let (localX, localY) = localOf(Double(x) + 0.5, Double(y) + 0.5)
                guard GPUIQuadCoverage.geometryCovers(localX: localX, localY: localY, rect: rect) else { continue }
                let coverage = GPUIQuadCoverage.coverage(pixelX: x, pixelY: y, distanceAt: distanceAt)
                guard coverage > 0 else { continue }

                guard
                    let color = shadedQuadColor(
                        quad, start: start, end: end, localX: localX, localY: localY, rect: rect)
                else { continue }
                let offset = ((y - bounds.y0) * regionWidth + (x - bounds.x0)) * 4
                // The blurred backdrop is premultiplied, matching the
                // render target the GPU's blur pass copies from.
                let inverse = 1 - color.alpha
                let compositedBlue = color.blue * color.alpha + Float(backdrop[offset]) / 255 * inverse
                let compositedGreen = color.green * color.alpha + Float(backdrop[offset + 1]) / 255 * inverse
                let compositedRed = color.red * color.alpha + Float(backdrop[offset + 2]) / 255 * inverse
                let backdropAlpha = Float(backdrop[offset + 3]) / 255
                let materialAlpha = forcesOpaque ? 1 : color.alpha + backdropAlpha * inverse

                // This material pixel already contains the backdrop. Replace
                // the covered fraction instead of blending it over that same
                // backdrop again; source-over would turn a uniform 50%-alpha
                // backdrop into 75% alpha even with a fully transparent tint.
                // The GPU's dual-source blend uses this same coverage factor.
                let mask = Float(coverage * clipAlpha)
                let destinationOffset = pixelOffset(x: x, y: y)
                let retainedAlpha = Float(pixels[destinationOffset + 3]) / 255 * (1 - mask)
                let outputAlpha = materialAlpha * mask + retainedAlpha
                let unpremultiply: Float = outputAlpha > 0 ? 1 / outputAlpha : 0
                pixels[destinationOffset] = byte(
                    (compositedBlue * mask + Float(pixels[destinationOffset]) / 255 * retainedAlpha) * unpremultiply)
                pixels[destinationOffset + 1] = byte(
                    (compositedGreen * mask + Float(pixels[destinationOffset + 1]) / 255 * retainedAlpha)
                        * unpremultiply)
                pixels[destinationOffset + 2] = byte(
                    (compositedRed * mask + Float(pixels[destinationOffset + 2]) / 255 * retainedAlpha) * unpremultiply)
                pixels[destinationOffset + 3] = byte(outputAlpha)
                accumulateReplacementCoverage(mask, x: x, y: y)
            }
        }
    }

    /// The quad's tint at a local sample: gradient lerp, then the colour
    /// effect — including `luminanceToAlpha`, which the shader applies to
    /// `color.a` **before** the coverage multiply.
    ///
    /// The rasterizer used to multiply coverage in first, so effect 8's
    /// `alpha = luminance` overwrote both the quad's alpha and its
    /// antialiasing: a `luminanceToAlpha` quad was a hard-edged block on
    /// CPU and a properly feathered, correctly clipped shape on screen.
    private func shadedQuadColor(
        _ quad: QuadPrimitive,
        start: RasterColor,
        end: RasterColor,
        localX: Double,
        localY: Double,
        rect: Rect
    ) -> RasterColor? {
        var progress: Float
        if quad.usesRadialGradient {
            let offsetX = localX - rect.minX - Double(quad.effectParam1)
            let offsetY = localY - rect.minY - Double(quad.effectParam2)
            let distance = (offsetX * offsetX + offsetY * offsetY).squareRoot()
            let startRadius = Double(quad.effectParam3)
            let endRadius = Double(quad.effectParam4)
            let span = endRadius - startRadius
            if abs(span) > 0.000_001 {
                progress = Float(clamp((distance - startRadius) / span, lower: 0, upper: 1))
            } else {
                progress = distance <= startRadius ? 0 : 1
            }
        } else if quad.usesConicGradient {
            let offsetX = localX - rect.minX - Double(quad.effectParam1)
            let offsetY = localY - rect.minY - Double(quad.effectParam2)
            let rawAngle = atan2(offsetY, offsetX) + Double.pi / 2 - Double(quad.effectParam3)
            let sweep = Double(quad.effectParam4)
            let directedAngle = sweep < 0 ? -rawAngle : rawAngle
            let completeTurn = 2 * Double.pi
            let wrappedAngle = directedAngle - floor(directedAngle / completeTurn) * completeTurn
            progress = Float(clamp(wrappedAngle / max(abs(sweep), 0.000_001), lower: 0, upper: 1))
        } else if quad.usesDirectionalGradient {
            let startX = Double(quad.effectParam1)
            let startY = Double(quad.effectParam2)
            let vectorX = Double(quad.effectParam3) - startX
            let vectorY = Double(quad.effectParam4) - startY
            let lengthSquared = vectorX * vectorX + vectorY * vectorY
            if lengthSquared > 0, lengthSquared.isFinite {
                let offsetX = localX - rect.minX - startX
                let offsetY = localY - rect.minY - startY
                progress = Float(
                    clamp((offsetX * vectorX + offsetY * vectorY) / lengthSquared, lower: 0, upper: 1))
            } else {
                progress = 0
            }
        } else if quad.gradientAxis > 0.5 {
            progress = Float(clamp((localX - rect.minX) / max(rect.size.width, 1), lower: 0, upper: 1))
        } else {
            progress = Float(clamp((localY - rect.minY) / max(rect.size.height, 1), lower: 0, upper: 1))
        }

        if quad.gradientSegmentMode > 0.5 {
            let start = quad.gradientSegmentStart
            let end = quad.gradientSegmentEnd
            let isFinalSegment = quad.gradientSegmentMode > 1.5
            guard progress >= start, progress <= end, isFinalSegment || progress < end else {
                return nil
            }
            progress = clamp((progress - start) / max(end - start, 0.000_001), lower: 0, upper: 1)
        }

        let color = start.interpolated(to: end, progress: progress)
        // 8 = luminanceToAlpha, branched in psMain rather than inside
        // applyColorEffect because it writes alpha as well as rgb.
        if quad.effectType > 7.5, quad.effectType < 8.5 {
            let luminance = Float(
                0.2126 * Double(color.red) + 0.7152 * Double(color.green) + 0.0722 * Double(color.blue))
            return RasterColor(red: 0, green: 0, blue: 0, alpha: color.alpha * luminance)
        }
        return applyRasterColorEffect(
            color, effectType: quad.effectType, intensity: quad.effectIntensity, param1: quad.effectParam1,
            param2: quad.effectParam2, param3: quad.effectParam3, param4: quad.effectParam4)
    }

    /// Copies the visible surface under `bounds` into premultiplied BGRA.
    /// An isolation contributes its virtual F + (1 - C)D surface; ordinary
    /// targets keep the original framebuffer conversion. The full material
    /// scan window is blurred in either case, not just the valid D rectangle.
    private func premultipliedRegion(_ bounds: PixelBounds) -> [UInt8] {
        let regionWidth = bounds.width
        let regionHeight = bounds.height
        var region = [UInt8](repeating: 0, count: regionWidth * regionHeight * 4)
        if isBackdropIsolated {
            for y in bounds.y0..<bounds.y1 {
                for x in bounds.x0..<bounds.x1 {
                    let color = premultipliedColor(x: x, y: y)
                    let destination = ((y - bounds.y0) * regionWidth + (x - bounds.x0)) * 4
                    region[destination] = byte(color.blue)
                    region[destination + 1] = byte(color.green)
                    region[destination + 2] = byte(color.red)
                    region[destination + 3] = byte(color.alpha)
                }
            }
            return region
        }
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let source = pixelOffset(x: x, y: y)
                let destination = ((y - bounds.y0) * regionWidth + (x - bounds.x0)) * 4
                let alpha = Float(pixels[source + 3]) / 255
                region[destination] = byte(Float(pixels[source]) / 255 * alpha)
                region[destination + 1] = byte(Float(pixels[source + 1]) / 255 * alpha)
                region[destination + 2] = byte(Float(pixels[source + 2]) / 255 * alpha)
                region[destination + 3] = pixels[source + 3]
            }
        }
        return region
    }

    /// Blurs an isolated region according to the shared `BlurPassPlan`.
    ///
    /// The passes themselves live in `PremultipliedImageBlur`, because the
    /// painter needs the identical chain for the isolated bitmap a
    /// `.blur(radius:)` subtree rasterizes into and a second transcription
    /// of a transcription is how the halving rule drifted in the first
    /// place.
    private func blurPremultipliedRegion(_ region: inout [UInt8], width: Int, height: Int, radius: Int) {
        PremultipliedImageBlur.blur(&region, width: width, height: height, radius: radius)
    }

    /// The GPU's shadow model, transcribed: the envelope is the rect grown
    /// by `2 · blurRadius`, the falloff is
    /// `1 - GPUIQuadCoverage.smoothstep(-blur/2, blur, distance)`, and the
    /// peak alpha is the requested alpha.
    ///
    /// What this replaces was a different shadow, not a differently
    /// antialiased one: a rect grown by `blurRadius / 2` with a 1 px ramp
    /// on a rounded rect of radius `cornerRadius + 0.35 · blurRadius`, at
    /// `colorA * 0.55`. A `.shadow(radius: 20)` was a crisp 10 px halo at
    /// 55 % in every screenshot and a soft 40 px halo at full alpha on
    /// screen; the `0.55` appeared nowhere else in the stack and is
    /// retired rather than promoted to a design constant.
    mutating func drawShadow(_ shadow: ShadowPrimitive) {
        let blurRadius = max(Double(shadow.blurRadius), 0)
        let expand = blurRadius * 2
        let rect = Rect(
            x: Double(shadow.x + shadow.offsetX),
            y: Double(shadow.y + shadow.offsetY),
            width: Double(shadow.width),
            height: Double(shadow.height)
        )
        let envelope = Rect(
            x: rect.minX - expand,
            y: rect.minY - expand,
            width: rect.size.width + expand * 2,
            height: rect.size.height + expand * 2
        )
        guard
            !GPUIClipEncoding.isEmpty(
                clipX: shadow.clipX, clipY: shadow.clipY, clipWidth: shadow.clipWidth,
                clipHeight: shadow.clipHeight)
        else {
            return
        }
        let clip = GPUIClipRegion(
            x: shadow.clipX, y: shadow.clipY, width: shadow.clipWidth, height: shadow.clipHeight,
            cornerRadius: shadow.clipCornerRadius,
            cornerRadii: GPUIQuadCoverage.CornerRadii(
                topLeft: Double(shadow.clipCornerRadiusTopLeft), topRight: Double(shadow.clipCornerRadiusTopRight),
                bottomRight: Double(shadow.clipCornerRadiusBottomRight),
                bottomLeft: Double(shadow.clipCornerRadiusBottomLeft)),
            shapeBounds: shadow.clipShapeBounds)
        // The envelope is concentric with the offset rect, so one turn about
        // the envelope's centre turns both — which is exactly what the
        // shader's vertex stage does. Local coordinates stay unrotated, so
        // the rounded-rect distance field below is unchanged.
        guard
            let scan = rotatedScan(envelope, rotation: Double(shadow.rotationRadians), clip: clip.rect)
        else {
            return
        }
        let bounds = scan.bounds

        let color = RasterColor(
            red: shadow.colorR, green: shadow.colorG, blue: shadow.colorB, alpha: shadow.colorA)
        let radii = GPUIQuadCoverage.CornerRadii(uniform: Double(shadow.cornerRadius))
        let blur = max(blurRadius, 0.5)
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let (pixelCenterX, pixelCenterY) = scan.localOf(Double(x) + 0.5, Double(y) + 0.5)
                // A rounded clip contributes antialiased coverage, not a
                // yes/no gate — the shader multiplies `clipAlpha` into the
                // output and so must this. The clip is compared in *world*
                // space; only the shadow's own geometry is un-turned.
                let clipAlpha = clip.alpha(atPixelX: x, y: y)
                guard clipAlpha > 0 else { continue }
                // The shader only runs where the expanded quad covers the
                // pixel centre; the scan window rounds outward.
                guard
                    GPUIQuadCoverage.geometryCovers(localX: pixelCenterX, localY: pixelCenterY, rect: envelope)
                else { continue }
                let distance = GPUIQuadCoverage.signedDistance(
                    localX: pixelCenterX - rect.minX,
                    localY: pixelCenterY - rect.minY,
                    width: rect.size.width,
                    height: rect.size.height,
                    radii: radii)
                let alpha = (1 - GPUIQuadCoverage.smoothstep(-blur * 0.5, blur, distance)) * clipAlpha
                if alpha > 0 {
                    blend(color.withAlphaMultiplier(Float(alpha)), x: x, y: y)
                }
            }
        }
    }

    mutating func drawGlyph(_ glyph: GlyphPrimitive, atlas: GlyphAtlasSnapshot?) {
        guard let atlas else {
            return
        }

        let rect = Rect(
            x: Double(glyph.screenX),
            y: Double(glyph.screenY),
            width: Double(glyph.screenW),
            height: Double(glyph.screenH)
        )
        guard
            !GPUIClipEncoding.isEmpty(
                clipX: glyph.clipX, clipY: glyph.clipY, clipWidth: glyph.clipWidth,
                clipHeight: glyph.clipHeight)
        else {
            return
        }
        let clip = GPUIClipRegion(
            x: glyph.clipX, y: glyph.clipY, width: glyph.clipWidth, height: glyph.clipHeight,
            cornerRadius: glyph.clipCornerRadius,
            cornerRadii: GPUIQuadCoverage.CornerRadii(
                topLeft: Double(glyph.clipCornerRadiusTopLeft), topRight: Double(glyph.clipCornerRadiusTopRight),
                bottomRight: Double(glyph.clipCornerRadiusBottomRight),
                bottomLeft: Double(glyph.clipCornerRadiusBottomLeft)),
            shapeBounds: glyph.clipShapeBounds)
        // A glyph inside a `.rotationEffect` subtree carries the subtree's
        // angle; the atlas cell is sampled in unrotated cell coordinates, so
        // the UV lerp below is the same one an upright glyph runs — which is
        // also how the shader does it (the UVs ride the turned vertices).
        guard let scan = rotatedScan(rect, rotation: Double(glyph.rotationRadians), clip: clip.rect) else {
            return
        }
        let bounds = scan.bounds

        let atlasWidth = max(1, Int(atlas.width))
        let atlasHeight = max(1, Int(atlas.height))
        let color = RasterColor(red: glyph.colorR, green: glyph.colorG, blue: glyph.colorB, alpha: glyph.colorA)
        let u0 = Double(glyph.atlasU0)
        let v0 = Double(glyph.atlasV0)
        let u1 = Double(glyph.atlasU1)
        let v1 = Double(glyph.atlasV1)

        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                // The shader rejects per pixel centre against the float
                // clip rect; the integer scan window rounds outward, so
                // without this the two disagree by a pixel wherever the
                // clip lands on a fraction — which at 125 % and 150 % DPI
                // is most of the time. The same argument applies to the
                // glyph's own quad, which the rasterizer covers only at
                // pixel centres inside it.
                let (pixelCenterX, pixelCenterY) = scan.localOf(Double(x) + 0.5, Double(y) + 0.5)
                let clipAlpha = clip.alpha(atPixelX: x, y: y)
                guard clipAlpha > 0 else { continue }
                guard GPUIQuadCoverage.geometryCovers(localX: pixelCenterX, localY: pixelCenterY, rect: rect)
                else { continue }
                let tx = clamp((pixelCenterX - rect.minX) / max(rect.size.width, 1), lower: 0, upper: 1)
                let ty = clamp((pixelCenterY - rect.minY) / max(rect.size.height, 1), lower: 0, upper: 1)
                let tapX = BilinearAxisTap(normalized: u0 + (u1 - u0) * tx, size: atlasWidth)
                let tapY = BilinearAxisTap(normalized: v0 + (v1 - v0) * ty, size: atlasHeight)

                // Alpha only, exactly like the glyph shader
                // (`glyphAtlas.Sample(...).a`) — and *bilinear*, also exactly
                // like the glyph shader, which binds a
                // `MIN_MAG_MIP_LINEAR` sampler. Point-sampling here made
                // every magnified glyph a staircase on the reference
                // renderer and a smooth ramp on screen, which is the gap
                // `CrossBackendPixelParityTests` recorded as a known
                // divergence until this line.
                //
                // Sampling alpha used to substitute `max(r, g, b)` wherever
                // alpha was zero, which no atlas producer needs — every one
                // of them writes coverage into alpha
                // (`NativeTextRenderer.tint` writes premultiplied BGRA,
                // `PixelFontAtlas` writes 255 in all four channels) — and
                // which the GPU has no equivalent of.
                guard
                    let alphaTopLeft = atlasAlpha(atlas, x: tapX.low, y: tapY.low, width: atlasWidth),
                    let alphaTopRight = atlasAlpha(atlas, x: tapX.high, y: tapY.low, width: atlasWidth),
                    let alphaBottomLeft = atlasAlpha(atlas, x: tapX.low, y: tapY.high, width: atlasWidth),
                    let alphaBottomRight = atlasAlpha(atlas, x: tapX.high, y: tapY.high, width: atlasWidth)
                else {
                    continue
                }
                let sampledAlpha = bilinearMix(
                    alphaTopLeft, alphaTopRight, alphaBottomLeft, alphaBottomRight,
                    fractionX: tapX.fraction, fractionY: tapY.fraction)
                let coverage = Float(sampledAlpha) * Float(clipAlpha)
                if coverage > 0 {
                    blend(color.withAlphaMultiplier(coverage), x: x, y: y)
                }
            }
        }
    }

    /// One image texel in the space the GPU sampler filters in: premultiplied,
    /// 0…1 per channel. Straight-alpha sources are premultiplied here because
    /// `createImageTextureResource` premultiplies them before upload, so a
    /// straight source and a premultiplied one must filter identically.
    /// `nil` when the buffer is shorter than the rect it claims.
    private func premultipliedTexel(
        _ bitmap: BitmapSurface, x: Int, y: Int, bytesPerRow: Int, isPremultiplied: Bool
    ) -> PremultipliedTexel? {
        let offset = y * bytesPerRow + x * 4
        guard offset >= 0, offset + 3 < bitmap.pixels.count else {
            return nil
        }
        let alpha = Double(bitmap.pixels[offset + 3]) / 255
        let premultiplier = isPremultiplied ? 1 : alpha
        return PremultipliedTexel(
            red: Double(bitmap.pixels[offset + 2]) / 255 * premultiplier,
            green: Double(bitmap.pixels[offset + 1]) / 255 * premultiplier,
            blue: Double(bitmap.pixels[offset]) / 255 * premultiplier,
            alpha: alpha
        )
    }

    /// One atlas texel's alpha as 0…1, or `nil` when the snapshot is shorter
    /// than the rect it claims to hold — a truncated upload must skip the
    /// pixel, not read whatever the buffer's tail happens to contain.
    private func atlasAlpha(_ atlas: GlyphAtlasSnapshot, x: Int, y: Int, width atlasWidth: Int) -> Double? {
        let offset = (y * atlasWidth + x) * 4
        guard offset >= 0, offset + 3 < atlas.pixels.count else {
            return nil
        }
        return Double(atlas.pixels[offset + 3]) / 255.0
    }

    /// Composite the filtered pair as pF + (1 - pC)D. In another isolation D
    /// here is that parent's foreground, while its own C receives pC over C.
    /// Output opacity and clipping act after both filters, never on the frozen
    /// backdrop or transparent foreground margin that fed them.
    mutating func compositeIsolatedImage(
        _ image: ImagePrimitive, result: RasterIsolatedImage, mapping: GPUISceneBackdropIsolationMapping
    ) {
        guard let region = mapping.parentCopyRegion,
            !GPUIClipEncoding.isEmpty(
                clipX: image.clipX, clipY: image.clipY, clipWidth: image.clipWidth,
                clipHeight: image.clipHeight)
        else { return }
        let opacity = clamp(image.opacity, lower: 0, upper: 1)
        guard opacity > 0 else { return }
        let clip = GPUIClipRegion(
            x: image.clipX, y: image.clipY, width: image.clipWidth, height: image.clipHeight,
            cornerRadius: image.clipCornerRadius,
            cornerRadii: GPUIQuadCoverage.CornerRadii(
                topLeft: Double(image.clipCornerRadiusTopLeft), topRight: Double(image.clipCornerRadiusTopRight),
                bottomRight: Double(image.clipCornerRadiusBottomRight),
                bottomLeft: Double(image.clipCornerRadiusBottomLeft)),
            shapeBounds: image.clipShapeBounds)
        for row in 0..<region.height {
            let y = region.originY + row
            let sourceY = mapping.childOffsetY + row
            for column in 0..<region.width {
                let x = region.originX + column
                let sourceIndex = sourceY * result.width + mapping.childOffsetX + column
                let weight = opacity * Float(clip.alpha(atPixelX: x, y: y))
                let coverage = weight * Float(result.coverage[sourceIndex]) / 255
                // Preserve empty content byte for byte, including hidden RGB
                // in a transparent destination. The parent copy is only input.
                guard coverage > 0 else { continue }
                let source = sourceIndex * 4
                let destination = pixelOffset(x: x, y: y)
                let sourceAlpha = Float(result.premultipliedPixels[source + 3]) / 255
                let retainedAlpha = Float(pixels[destination + 3]) / 255 * (1 - coverage)
                let outputAlpha = sourceAlpha * weight + retainedAlpha
                let unpremultiply: Float = outputAlpha > 0 ? 1 / outputAlpha : 0
                pixels[destination] = byte(
                    (Float(result.premultipliedPixels[source]) / 255 * weight
                        + Float(pixels[destination]) / 255 * retainedAlpha) * unpremultiply)
                pixels[destination + 1] = byte(
                    (Float(result.premultipliedPixels[source + 1]) / 255 * weight
                        + Float(pixels[destination + 1]) / 255 * retainedAlpha) * unpremultiply)
                pixels[destination + 2] = byte(
                    (Float(result.premultipliedPixels[source + 2]) / 255 * weight
                        + Float(pixels[destination + 2]) / 255 * retainedAlpha) * unpremultiply)
                pixels[destination + 3] = byte(outputAlpha)
                accumulateReplacementCoverage(coverage, x: x, y: y)
            }
        }
    }

    /// The source already includes the admitted parent crop. Its alpha is not
    /// output coverage: retain `(1 - coverage)` of the old destination, unlike
    /// source-over's `(1 - sourceAlpha * coverage)`. Admission makes each source
    /// pixel correspond exactly to one parent pixel, so no resampling is needed.
    mutating func replaceImage(_ image: ImagePrimitive, with source: RasterTarget, in region: SubTextureRegion) {
        guard
            !GPUIClipEncoding.isEmpty(
                clipX: image.clipX, clipY: image.clipY, clipWidth: image.clipWidth,
                clipHeight: image.clipHeight)
        else { return }
        let opacity = clamp(image.opacity, lower: 0, upper: 1)
        guard opacity > 0 else { return }
        let clip = GPUIClipRegion(
            x: image.clipX, y: image.clipY, width: image.clipWidth, height: image.clipHeight,
            cornerRadius: image.clipCornerRadius,
            cornerRadii: GPUIQuadCoverage.CornerRadii(
                topLeft: Double(image.clipCornerRadiusTopLeft), topRight: Double(image.clipCornerRadiusTopRight),
                bottomRight: Double(image.clipCornerRadiusBottomRight),
                bottomLeft: Double(image.clipCornerRadiusBottomLeft)),
            shapeBounds: image.clipShapeBounds)
        for row in 0..<region.height {
            let y = region.originY + row
            for column in 0..<region.width {
                let x = region.originX + column
                let coverage = opacity * Float(clip.alpha(atPixelX: x, y: y))
                guard coverage > 0 else { continue }
                let destination = pixelOffset(x: x, y: y)
                let input = (row * source.width + column) * 4
                // Preserve untouched bytes exactly, including transparent hidden
                // RGB. All other colors are combined in premultiplied space.
                if pixels[destination] == source.pixels[input],
                    pixels[destination + 1] == source.pixels[input + 1],
                    pixels[destination + 2] == source.pixels[input + 2],
                    pixels[destination + 3] == source.pixels[input + 3]
                {
                    continue
                }
                let sourceAlpha = Float(source.pixels[input + 3]) / 255
                let destinationAlpha = Float(pixels[destination + 3]) / 255
                let weightedSourceAlpha = sourceAlpha * coverage
                let retainedAlpha = destinationAlpha * (1 - coverage)
                let outputAlpha = weightedSourceAlpha + retainedAlpha
                let unpremultiply: Float = outputAlpha > 0 ? 1 / outputAlpha : 0
                pixels[destination] = byte(
                    (Float(source.pixels[input]) / 255 * weightedSourceAlpha
                        + Float(pixels[destination]) / 255 * retainedAlpha) * unpremultiply)
                pixels[destination + 1] = byte(
                    (Float(source.pixels[input + 1]) / 255 * weightedSourceAlpha
                        + Float(pixels[destination + 1]) / 255 * retainedAlpha) * unpremultiply)
                pixels[destination + 2] = byte(
                    (Float(source.pixels[input + 2]) / 255 * weightedSourceAlpha
                        + Float(pixels[destination + 2]) / 255 * retainedAlpha) * unpremultiply)
                pixels[destination + 3] = byte(outputAlpha)
            }
        }
    }

    mutating func drawImage(_ image: ImagePrimitive, bitmap: BitmapSurface) {
        let sampling = image.sampling
        let sourceSize = IntSize(width: bitmap.width, height: bitmap.height)
        guard
            sampling.validationFailure(
                sourceSize: sourceSize, uvX: image.uvX, uvY: image.uvY, uvW: image.uvW, uvH: image.uvH) == nil
        else { return }
        let rect = Rect(
            x: Double(image.screenX),
            y: Double(image.screenY),
            width: Double(image.screenW),
            height: Double(image.screenH)
        )
        guard sampling.placementValidationFailure(rect: rect) == nil else { return }
        let samplingKernel = ImageSamplingKernel(sampling: sampling, sourceSize: sourceSize)
        guard
            !GPUIClipEncoding.isEmpty(
                clipX: image.clipX, clipY: image.clipY, clipWidth: image.clipWidth,
                clipHeight: image.clipHeight)
        else {
            return
        }
        let clip = GPUIClipRegion(
            x: image.clipX, y: image.clipY, width: image.clipWidth, height: image.clipHeight,
            cornerRadius: image.clipCornerRadius,
            cornerRadii: GPUIQuadCoverage.CornerRadii(
                topLeft: Double(image.clipCornerRadiusTopLeft), topRight: Double(image.clipCornerRadiusTopRight),
                bottomRight: Double(image.clipCornerRadiusBottomRight),
                bottomLeft: Double(image.clipCornerRadiusBottomLeft)),
            shapeBounds: image.clipShapeBounds)
        // UVs are evaluated in the original destination coordinates after
        // undoing rotation and the affine basis. A shear or reflection must
        // not stretch the image into its axis-aligned bounding rectangle.
        guard let scan = imageScan(image, rect: rect, clip: clip.rect) else {
            return
        }
        let bounds = scan.bounds
        let legacyIdentity = sampling.isLegacy && image.hasIdentityAffineTransform
        let sampleWidth = legacyIdentity ? max(rect.size.width, 1) : rect.size.width
        let sampleHeight = legacyIdentity ? max(rect.size.height, 1) : rect.size.height

        let sourceWidth = max(1, Int(bitmap.width))
        let sourceHeight = max(1, Int(bitmap.height))
        let bytesPerRow = max(sourceWidth * 4, Int(bitmap.bytesPerRow))
        // Preserve exact texel centers for an integral 1:1 placement. A
        // normalized divide/multiply can invent a tiny neighboring weight,
        // leaving nonzero straight RGB even when its alpha rounds to zero.
        let usesExactTexelIndices =
            sampling == .legacy && image.hasIdentityAffineTransform && image.rotationRadians == 0
            && image.uvX == 0 && image.uvY == 0 && image.uvW == 1 && image.uvH == 1
            && bitmap.width > 0 && bitmap.height > 0
            && rect.size.width == Double(bitmap.width) && rect.size.height == Double(bitmap.height)
            && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.origin.x == rect.origin.x.rounded(.towardZero)
            && rect.origin.y == rect.origin.y.rounded(.towardZero)
        // `blend` works in straight alpha, so premultiplied sources (the
        // DirectWrite/GDI text path, and anything read back from the GPU)
        // are divided out per texel. The GPU does the mirror of this by
        // normalizing every upload to premultiplied instead.
        let isPremultiplied = bitmap.format.alphaMode == .premultiplied
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let (pixelCenterX, pixelCenterY) = scan.localOf(Double(x) + 0.5, Double(y) + 0.5)
                let clipAlpha = clip.alpha(atPixelX: x, y: y)
                guard clipAlpha > 0 else { continue }
                guard scan.covers(pixelCenterX, pixelCenterY) else { continue }
                let tx = clamp((pixelCenterX - rect.minX) / sampleWidth, lower: 0, upper: 1)
                let ty = clamp((pixelCenterY - rect.minY) / sampleHeight, lower: 0, upper: 1)
                let tapX: BilinearAxisTap
                let tapY: BilinearAxisTap
                if usesExactTexelIndices {
                    // Subtract in Double and bound before conversion, including
                    // a negative destination origin cropped by the surface.
                    let sourceX = Double(x) - rect.minX
                    let sourceY = Double(y) - rect.minY
                    guard sourceX >= 0, sourceX < Double(sourceWidth),
                        sourceY >= 0, sourceY < Double(sourceHeight),
                        let texelX = Int(exactly: sourceX), let texelY = Int(exactly: sourceY)
                    else { continue }
                    tapX = BilinearAxisTap(exactIndex: texelX)
                    tapY = BilinearAxisTap(exactIndex: texelY)
                } else if let samplingKernel {
                    let taps = samplingKernel.taps(unitX: Float(tx), unitY: Float(ty))
                    tapX = BilinearAxisTap(taps.x)
                    tapY = BilinearAxisTap(taps.y)
                } else {
                    tapX = BilinearAxisTap(
                        normalized: Double(image.uvX) + Double(image.uvW) * tx, size: sourceWidth)
                    tapY = BilinearAxisTap(
                        normalized: Double(image.uvY) + Double(image.uvH) * ty, size: sourceHeight)
                }

                // The GPU filters *premultiplied* texels — every upload is
                // normalized to premultiplied BGRA before it reaches the
                // sampler, which is what makes linear filtering correct at a
                // transparent edge (interpolating straight-alpha colour
                // against a transparent texel drags the wrong hue in). So
                // interpolate premultiplied here too, and un-premultiply the
                // *result*; `blend` composites in straight alpha.
                guard
                    let topLeft = premultipliedTexel(
                        bitmap, x: tapX.low, y: tapY.low, bytesPerRow: bytesPerRow, isPremultiplied: isPremultiplied),
                    let topRight = premultipliedTexel(
                        bitmap, x: tapX.high, y: tapY.low, bytesPerRow: bytesPerRow, isPremultiplied: isPremultiplied),
                    let bottomLeft = premultipliedTexel(
                        bitmap, x: tapX.low, y: tapY.high, bytesPerRow: bytesPerRow, isPremultiplied: isPremultiplied),
                    let bottomRight = premultipliedTexel(
                        bitmap, x: tapX.high, y: tapY.high, bytesPerRow: bytesPerRow, isPremultiplied: isPremultiplied)
                else {
                    continue
                }
                let sampledAlpha = bilinearMix(
                    topLeft.alpha, topRight.alpha, bottomLeft.alpha, bottomRight.alpha,
                    fractionX: tapX.fraction, fractionY: tapY.fraction)
                let divisor = sampledAlpha > 0 ? sampledAlpha : 1
                let sampledRed = bilinearMix(
                    topLeft.red, topRight.red, bottomLeft.red, bottomRight.red,
                    fractionX: tapX.fraction, fractionY: tapY.fraction)
                let sampledGreen = bilinearMix(
                    topLeft.green, topRight.green, bottomLeft.green, bottomRight.green,
                    fractionX: tapX.fraction, fractionY: tapY.fraction)
                let sampledBlue = bilinearMix(
                    topLeft.blue, topRight.blue, bottomLeft.blue, bottomRight.blue,
                    fractionX: tapX.fraction, fractionY: tapY.fraction)
                blend(
                    RasterColor(
                        red: Float(sampledRed / divisor),
                        green: Float(sampledGreen / divisor),
                        blue: Float(sampledBlue / divisor),
                        alpha: Float(sampledAlpha) * image.opacity * Float(clipAlpha)
                    ),
                    x: x,
                    y: y
                )
            }
        }
    }

    /// Fill and stroke, each accumulated into one per-path coverage buffer
    /// and composited with a single blend per pixel.
    ///
    /// This is not a fallback-only concern: `ensureCachedPathTexture`
    /// CPU-rasterizes every `PathPrimitive` and uploads the bitmap, so
    /// whatever happens here *is* the shipping appearance of `Canvas`,
    /// `Shape` strokes, charts and the SF-symbol vector fallback.
    mutating func drawPath(_ path: PathPrimitive) {
        let clipRect = path.clipBounds ?? Rect(x: 0, y: 0, width: Double(width), height: Double(height))
        guard let bounds = clippedPixelBounds(path.bounds, clip: clipRect) else {
            return
        }
        let clip = GPUIClipRegion(
            x: clipRect.origin.x, y: clipRect.origin.y,
            width: clipRect.size.width, height: clipRect.size.height,
            cornerRadius: path.clipCornerRadius,
            cornerRadii: GPUIQuadCoverage.CornerRadii(
                topLeft: path.clipCornerRadiusTopLeft, topRight: path.clipCornerRadiusTopRight,
                bottomRight: path.clipCornerRadiusBottomRight, bottomLeft: path.clipCornerRadiusBottomLeft),
            shapeBounds: path.clipShapeBounds)

        let fillColor = RasterColor(path.fillColor)
        let strokeColor = RasterColor(path.strokeColor)
        let gradientSpace = path.resolvedGradientSpace
        let fillGradient = path.fillGradient.flatMap { gradient in
            gradientSpace.map { RasterPathGradient(gradient, space: $0) }
        }
        let strokeGradient = path.strokeGradient.flatMap { gradient in
            gradientSpace.map { RasterPathGradient(gradient, space: $0) }
        }
        let flattened = FlattenedPath(path.elements)

        if fillGradient?.hasVisibleStops ?? (fillColor.alpha > 0) {
            var coverage = [Float](repeating: 0, count: bounds.width * bounds.height)
            PathCoverageRasterizer.accumulate(
                edges: flattened.fillEdges, bounds: bounds, fillRule: path.fillRule, into: &coverage)
            blendCoverage(coverage, bounds: bounds, color: fillColor, gradient: fillGradient, clip: clip)
        }

        if strokeGradient?.hasVisibleStops ?? (strokeColor.alpha > 0), path.lineWidth > 0 {
            var coverage = [Float](repeating: 0, count: bounds.width * bounds.height)
            PathCoverageRasterizer.accumulate(
                edges: flattened.strokeOutlineEdges(
                    lineWidth: path.lineWidth,
                    lineCap: path.lineCap,
                    lineJoin: path.lineJoin,
                    miterLimit: path.miterLimit),
                bounds: bounds, into: &coverage)
            blendCoverage(coverage, bounds: bounds, color: strokeColor, gradient: strokeGradient, clip: clip)
        }
    }

    private mutating func blendCoverage(
        _ coverage: [Float], bounds: PixelBounds, color: RasterColor,
        gradient: RasterPathGradient?, clip: GPUIClipRegion
    ) {
        for y in bounds.y0..<bounds.y1 {
            let rowOffset = (y - bounds.y0) * bounds.width
            for x in bounds.x0..<bounds.x1 {
                let value = coverage[rowOffset + (x - bounds.x0)]
                guard value > 0 else { continue }
                let clipAlpha = clip.alpha(atPixelX: x, y: y)
                guard clipAlpha > 0 else { continue }
                let pixelColor = gradient?.color(atPixelX: x, y: y) ?? color
                blend(pixelColor.withAlphaMultiplier(value * Float(clipAlpha)), x: x, y: y)
            }
        }
    }

    func bitmapSurface() -> BitmapSurface {
        // `blend` un-premultiplies before storing (it divides by
        // `outputAlpha`), so the rasterizer's output is straight alpha.
        BitmapSurface(
            width: Int32(width),
            height: Int32(height),
            bytesPerRow: Int32(width * 4),
            pixels: Data(pixels),
            format: .bgra8Straight
        )
    }

    private mutating func writeOpaque(_ color: RasterColor, x: Int, y: Int) {
        let offset = pixelOffset(x: x, y: y)
        pixels[offset] = byte(color.blue)
        pixels[offset + 1] = byte(color.green)
        pixels[offset + 2] = byte(color.red)
        pixels[offset + 3] = byte(color.alpha)
    }

    /// Ordinary source-over, with an optional adjusted source for the three
    /// implemented quad blend modes. The destination read includes an isolated
    /// target's frozen backdrop, but the write updates only local foreground.
    /// Keeping source alpha unchanged also preserves its separate coverage plane.
    private mutating func blend(
        _ color: RasterColor, x: Int, y: Int, separableMode: BlendMode? = nil
    ) {
        let sourceAlpha = clamp(color.alpha, lower: 0, upper: 1)
        guard sourceAlpha > 0 else {
            return
        }

        let source: RasterColor
        if let separableMode {
            let backdrop = premultipliedColor(x: x, y: y)
            source = RasterColor(
                SceneSeparableBlendCompositing.adjustedSource(
                    Color(red: color.red, green: color.green, blue: color.blue, alpha: sourceAlpha),
                    premultipliedBackdrop: Color(
                        red: backdrop.red, green: backdrop.green, blue: backdrop.blue, alpha: backdrop.alpha),
                    mode: separableMode))
        } else {
            source = color
        }

        let offset = pixelOffset(x: x, y: y)
        let destinationBlue = Float(pixels[offset]) / 255
        let destinationGreen = Float(pixels[offset + 1]) / 255
        let destinationRed = Float(pixels[offset + 2]) / 255
        let destinationAlpha = Float(pixels[offset + 3]) / 255
        let outputAlpha = sourceAlpha + destinationAlpha * (1 - sourceAlpha)
        guard outputAlpha > 0 else {
            return
        }

        pixels[offset] = byte(
            (source.blue * sourceAlpha + destinationBlue * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        pixels[offset + 1] = byte(
            (source.green * sourceAlpha + destinationGreen * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        pixels[offset + 2] = byte(
            (source.red * sourceAlpha + destinationRed * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        pixels[offset + 3] = byte(outputAlpha)
        accumulateReplacementCoverage(sourceAlpha, x: x, y: y)
    }

    /// Ordinary drawing supplies source alpha; material drawing supplies its
    /// geometric/clip coverage. These differ when the replacement contains a
    /// translucent backdrop. Independent targets carry no coverage plane.
    private mutating func accumulateReplacementCoverage(_ amount: Float, x: Int, y: Int) {
        guard isBackdropIsolated else { return }
        let mask = clamp(amount, lower: 0, upper: 1)
        let index = y * width + x
        let previous = Float(replacementCoverage[index]) / 255
        replacementCoverage[index] = byte(mask + previous * (1 - mask))
    }

    /// The pixel-scan window for `rect` turned by `rotation` about its own
    /// centre, together with the map from a world pixel back into `rect`'s
    /// unrotated space.
    ///
    /// Every rotation-carrying family shares this, because every one of them
    /// wants the same two things: scan the bounding box of the turned rect,
    /// and evaluate its interior maths — coverage, gradient, corner radius,
    /// atlas UV, image UV — at the *unrotated* local coordinate. The clip is
    /// deliberately compared in world space: the scene contract's clip is an
    /// axis-aligned screen rect and does not turn with the primitive.
    ///
    /// For `rotation == 0` this is the historic
    /// `clippedPixelBounds(rect, clip:)` with an identity map, so unrotated
    /// output stays byte-identical.
    private func rotatedScan(_ rect: Rect, rotation: Double, clip: Rect?)
        -> (bounds: PixelBounds, localOf: (Double, Double) -> (Double, Double))?
    {
        guard rotation != 0, rotation.isFinite else {
            guard let bounds = clippedPixelBounds(rect, clip: clip) else { return nil }
            return (bounds, { ($0, $1) })
        }

        let centre = Point(x: rect.midX, y: rect.midY)
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        let halfW = rect.size.width * 0.5
        let halfH = rect.size.height * 0.5
        let corners = [
            rotatedCorner(-halfW, -halfH, cosR: cosR, sinR: sinR, centre: centre),
            rotatedCorner(halfW, -halfH, cosR: cosR, sinR: sinR, centre: centre),
            rotatedCorner(halfW, halfH, cosR: cosR, sinR: sinR, centre: centre),
            rotatedCorner(-halfW, halfH, cosR: cosR, sinR: sinR, centre: centre),
        ]
        let minX = corners.map(\.x).min() ?? rect.minX
        let maxX = corners.map(\.x).max() ?? rect.maxX
        let minY = corners.map(\.y).min() ?? rect.minY
        let maxY = corners.map(\.y).max() ?? rect.maxY
        let aabb = Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let bounds = clippedPixelBounds(aabb, clip: clip) else { return nil }

        // Pre-compute inverse-rotation values for the closure.
        let invCos = cos(-rotation)
        let invSin = sin(-rotation)
        let localOf: (Double, Double) -> (Double, Double) = { worldX, worldY in
            let dx = worldX - centre.x
            let dy = worldY - centre.y
            let lx = invCos * dx - invSin * dy + halfW + rect.origin.x
            let ly = invSin * dx + invCos * dy + halfH + rect.origin.y
            return (lx, ly)
        }
        return (bounds, localOf)
    }

    private func imageScan(_ image: ImagePrimitive, rect: Rect, clip: Rect?)
        -> (
            bounds: PixelBounds, localOf: (Double, Double) -> (Double, Double),
            covers: (Double, Double) -> Bool
        )?
    {
        guard let geometry = ImagePlacementGeometry(image), !rect.isEmpty else { return nil }
        if image.hasIdentityAffineTransform {
            guard let scan = rotatedScan(rect, rotation: Double(image.rotationRadians), clip: clip) else { return nil }
            return (
                scan.bounds, scan.localOf,
                { GPUIQuadCoverage.geometryCovers(localX: $0, localY: $1, rect: rect) }
            )
        }
        guard let bounds = clippedPixelBounds(geometry.bounds, clip: clip) else { return nil }
        return (
            bounds, { geometry.localPoint(worldX: $0, worldY: $1) },
            { geometry.geometryCovers(localX: $0, localY: $1, rect: rect) }
        )
    }

    private func clippedPixelBounds(_ rect: Rect, clip: Rect?) -> PixelBounds? {
        guard !rect.isEmpty else {
            return nil
        }

        let surface = Rect(x: 0, y: 0, width: Double(width), height: Double(height))
        let clipped = (clip.flatMap { rect.intersected(with: $0) } ?? rect).intersected(with: surface)
        guard let clipped, !clipped.isEmpty else {
            return nil
        }

        let x0 = clamp(Int(clipped.minX.rounded(.down)), lower: 0, upper: width)
        let y0 = clamp(Int(clipped.minY.rounded(.down)), lower: 0, upper: height)
        let x1 = clamp(Int(clipped.maxX.rounded(.up)), lower: 0, upper: width)
        let y1 = clamp(Int(clipped.maxY.rounded(.up)), lower: 0, upper: height)
        guard x1 > x0, y1 > y0 else {
            return nil
        }
        return PixelBounds(x0: x0, y0: y0, x1: x1, y1: y1)
    }

    private func pixelOffset(x: Int, y: Int) -> Int {
        (y * width + x) * 4
    }
}
private struct RasterColor {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    init(_ color: Color) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = clamp(red, lower: 0, upper: 1)
        self.green = clamp(green, lower: 0, upper: 1)
        self.blue = clamp(blue, lower: 0, upper: 1)
        self.alpha = clamp(alpha, lower: 0, upper: 1)
    }

    func interpolated(to other: RasterColor, progress: Float) -> RasterColor {
        let t = clamp(progress, lower: 0, upper: 1)
        return RasterColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    func withAlphaMultiplier(_ multiplier: Float) -> RasterColor {
        RasterColor(red: red, green: green, blue: blue, alpha: alpha * multiplier)
    }
}
/// The Swift half of `applyColorEffect` in `BatchShaders.swift`. Effect 8
/// (`luminanceToAlpha`) is deliberately absent from both: it writes alpha
/// as well as rgb, so both sides branch it in the caller.
///
/// `RasterColor`'s initializer clamps every channel, which is the CPU's
/// `saturate`; the shader gained an explicit one so an over-driven
/// brightness or contrast composites the same on both.
private func applyRasterColorEffect(
    _ color: RasterColor, effectType: Float, intensity: Float, param1: Float = 0, param2: Float = 0, param3: Float = 0,
    param4: Float = 0
) -> RasterColor {
    let t = Double(effectType)
    let i = Double(intensity)

    // 0 = none
    if t < 0.5 { return color }

    // 1 = brightness
    if t < 1.5 {
        return RasterColor(
            red: color.red + Float(i), green: color.green + Float(i), blue: color.blue + Float(i), alpha: color.alpha)
    }

    // 2 = contrast
    if t < 2.5 {
        return RasterColor(
            red: (color.red - 0.5) * Float(i) + 0.5,
            green: (color.green - 0.5) * Float(i) + 0.5,
            blue: (color.blue - 0.5) * Float(i) + 0.5,
            alpha: color.alpha
        )
    }

    // 3 = saturation
    if t < 3.5 {
        let lum = Float(0.299 * Double(color.red) + 0.587 * Double(color.green) + 0.114 * Double(color.blue))
        return RasterColor(
            red: lum + (color.red - lum) * Float(i),
            green: lum + (color.green - lum) * Float(i),
            blue: lum + (color.blue - lum) * Float(i),
            alpha: color.alpha
        )
    }

    // 4 = grayscale
    if t < 4.5 {
        let lum = Float(0.299 * Double(color.red) + 0.587 * Double(color.green) + 0.114 * Double(color.blue))
        return RasterColor(
            red: color.red + (lum - color.red) * Float(i),
            green: color.green + (lum - color.green) * Float(i),
            blue: color.blue + (lum - color.blue) * Float(i),
            alpha: color.alpha
        )
    }

    // 5 = colorInvert
    if t < 5.5 {
        return RasterColor(red: 1.0 - color.red, green: 1.0 - color.green, blue: 1.0 - color.blue, alpha: color.alpha)
    }

    // 6 = hueRotation
    if t < 6.5 {
        let angle = Double(param1)
        if angle == 0 { return color }
        let cosA = cos(angle)
        let sinA = sin(angle)
        let r = color.red
        let g = color.green
        let b = color.blue
        let nr =
            Float(0.299 + cosA * 0.701 + sinA * 0.168) * r + Float(0.587 + cosA * (-0.587) + sinA * 0.330) * g + Float(
                0.114 + cosA * (-0.114) + sinA * (-0.497)) * b
        let ng =
            Float(0.299 + cosA * (-0.299) + sinA * (-0.328)) * r + Float(0.587 + cosA * 0.413 + sinA * 0.035) * g
            + Float(0.114 + cosA * (-0.114) + sinA * 0.292) * b
        let nb =
            Float(0.299 + cosA * (-0.300) + sinA * 1.250) * r + Float(0.587 + cosA * (-0.588) + sinA * (-1.050)) * g
            + Float(0.114 + cosA * 0.886 + sinA * (-0.203)) * b
        return RasterColor(red: nr, green: ng, blue: nb, alpha: color.alpha)
    }

    // 7 = colorMultiply
    if t < 7.5 {
        return RasterColor(
            red: color.red * param1, green: color.green * param2, blue: color.blue * param3, alpha: color.alpha)
    }

    return color
}
private func byte(_ value: Float) -> UInt8 {
    UInt8((clamp(value, lower: 0, upper: 1) * 255).rounded())
}
private func clamp<T: Comparable>(_ value: T, lower: T, upper: T) -> T {
    min(max(value, lower), upper)
}
