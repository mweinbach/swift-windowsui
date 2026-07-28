import Foundation
import SwiftWindowsCore

/// Builds a 1D Gaussian kernel suitable for a separable two-pass blur.
/// Sigma is `radius / 2.0` so a `radius=6` blur visually matches what a
/// 6-pixel box approximation roughly produced before — but with a real
/// bell-shaped falloff instead of uniform weighting. Materials' soft
/// backdrop now looks like macOS visual-effects blur instead of a
/// "smeared rectangle" box approximation.
///
/// Public so tests can verify the kernel shape directly.
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

// MARK: - Path Flattening & Scanline Fill

/// Rotates the offset `(dx, dy)` from the centre by `(cosR, sinR)` and
/// returns the resulting world-space point. Used by the rasterizer's
/// rotated-quad path to compute the bounding box of a rotated rect.
private func rotatedCorner(_ dx: Double, _ dy: Double, cosR: Double, sinR: Double, centre: Point) -> Point {
    Point(x: centre.x + cosR * dx - sinR * dy, y: centre.y + sinR * dx + cosR * dy)
}

public enum GPUIRawSceneRasterizer {
    public static func rasterize(_ scene: GPUIScene, size: IntSize) -> BitmapSurface {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        var target = RasterTarget(width: width, height: height, clearColor: scene.clearColor)
        let imageBindings = Dictionary(uniqueKeysWithValues: scene.imageResources.map { ($0.textureID, $0.bitmap) })

        if scene.paintRecords.isEmpty {
            rasterizeLayerOperations(in: scene, target: &target, imageBindings: imageBindings)
        } else {
            for record in scene.paintRecords {
                guard case .primitive(_, let primitive) = record else {
                    continue
                }
                rasterize(primitive, scene: scene, target: &target, imageBindings: imageBindings)
            }
        }

        return target.bitmapSurface()
    }

    public static func rasterize(_ frame: RenderFrame, size: IntSize) -> BitmapSurface {
        let surfaceSize = Size(width: Double(max(1, size.width)), height: Double(max(1, size.height)))
        return rasterize(GPUIScene(from: frame, surfaceSize: surfaceSize), size: size)
    }

    /// Rasterize a single path primitive to a bitmap sized to its masked bounds.
    /// Returns `nil` if the path has empty bounds.
    public static func rasterizePath(_ path: PathPrimitive) -> BitmapSurface? {
        guard let maskedBounds = path.contentMaskedBounds, !maskedBounds.isEmpty else {
            return nil
        }

        let width = max(1, Int(maskedBounds.width.rounded(.up)))
        let height = max(1, Int(maskedBounds.height.rounded(.up)))
        let offset = Point(x: -maskedBounds.origin.x, y: -maskedBounds.origin.y)
        let translated = path.translated(by: offset)

        var scene = GPUIScene(clearColor: .clear)
        scene.addPath(translated, toLayer: 0)
        scene.finish()

        return rasterize(scene, size: IntSize(width: Int32(width), height: Int32(height)))
    }

    private static func rasterizeLayerOperations(
        in scene: GPUIScene,
        target: inout RasterTarget,
        imageBindings: [Int32: BitmapSurface]
    ) {
        for layer in scene.layers {
            for operation in layer.paintOperations {
                for index in operation.startIndex..<(operation.startIndex + operation.count) {
                    switch operation.kind {
                    case .shadow where layer.shadows.indices.contains(index):
                        target.drawShadow(layer.shadows[index])
                    case .quad where layer.quads.indices.contains(index):
                        target.drawQuad(layer.quads[index])
                    case .glyph where layer.glyphs.indices.contains(index):
                        target.drawGlyph(layer.glyphs[index], atlas: scene.glyphAtlas)
                    case .pixelGlyph where layer.pixelGlyphs.indices.contains(index):
                        target.drawGlyph(layer.pixelGlyphs[index], atlas: scene.pixelGlyphAtlas)
                    case .image where layer.images.indices.contains(index):
                        if let bitmap = imageBindings[layer.images[index].textureID] {
                            target.drawImage(layer.images[index], bitmap: bitmap)
                        }
                    case .path where layer.paths.indices.contains(index):
                        target.drawPath(layer.paths[index])
                    default:
                        break
                    }
                }
            }
        }
    }

    private static func rasterize(
        _ primitive: GPUIScenePrimitive,
        scene: GPUIScene,
        target: inout RasterTarget,
        imageBindings: [Int32: BitmapSurface]
    ) {
        switch primitive {
        case .shadow(let shadow):
            target.drawShadow(shadow)
        case .quad(let quad):
            target.drawQuad(quad)
        case .glyph(let glyph):
            target.drawGlyph(glyph, atlas: scene.glyphAtlas)
        case .pixelGlyph(let glyph):
            target.drawGlyph(glyph, atlas: scene.pixelGlyphAtlas)
        case .image(let image):
            if let bitmap = imageBindings[image.textureID] {
                target.drawImage(image, bitmap: bitmap)
            }
        case .path(let path):
            target.drawPath(path)
        }
    }
}
private struct RasterTarget {
    var width: Int
    var height: Int
    var pixels: [UInt8]

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

    mutating func drawQuad(_ quad: QuadPrimitive) {
        let rect = Rect(
            x: Double(quad.x),
            y: Double(quad.y),
            width: Double(quad.width),
            height: Double(quad.height)
        )
        let rotation = Double(quad.rotationRadians)
        // Choose pixel-scan bounds and the (x, y) → local-coords mapping
        // based on whether the quad is rotated. For rotation == 0 the
        // local coords are the pixel center, preserving byte-identical
        // output with the historic axis-aligned fast path.
        let bounds: PixelBounds
        let localOf: (Double, Double) -> (Double, Double)
        let clipForScan = clipRect(quad.clipX, quad.clipY, quad.clipWidth, quad.clipHeight)
        if rotation == 0 {
            guard let unrotatedBounds = clippedPixelBounds(rect, clip: clipForScan) else { return }
            bounds = unrotatedBounds
            localOf = { ($0, $1) }
        } else {
            // Bounding box of the rotated rect, used as the pixel scan
            // window. Inverse rotation maps each world pixel back into
            // the un-rotated rect's coordinate space; the existing
            // coverage / gradient / corner-radius math then applies
            // unchanged in local space.
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
            guard let rotatedBounds = clippedPixelBounds(aabb, clip: clipForScan) else { return }
            bounds = rotatedBounds
            // Pre-compute inverse-rotation values for the closure.
            let invCos = cos(-rotation)
            let invSin = sin(-rotation)
            localOf = { (worldX, worldY) in
                let dx = worldX - centre.x
                let dy = worldY - centre.y
                let lx = invCos * dx - invSin * dy + halfW + rect.origin.x
                let ly = invSin * dx + invCos * dy + halfH + rect.origin.y
                return (lx, ly)
            }
        }

        // Resolve the effective corner radii: per-corner values win when
        // the primitive carries any; otherwise broadcast the uniform
        // cornerRadius (the historic path, byte-identical output).
        let cornerRadii: (topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double)
        if quad.usesPerCornerRadii {
            cornerRadii = (
                topLeft: Double(quad.cornerRadiusTopLeft),
                topRight: Double(quad.cornerRadiusTopRight),
                bottomRight: Double(quad.cornerRadiusBottomRight),
                bottomLeft: Double(quad.cornerRadiusBottomLeft)
            )
        } else {
            let uniform = max(0, Double(quad.cornerRadius))
            cornerRadii = (topLeft: uniform, topRight: uniform, bottomRight: uniform, bottomLeft: uniform)
        }
        let start = RasterColor(red: quad.startR, green: quad.startG, blue: quad.startB, alpha: quad.startA)
        let end = RasterColor(red: quad.endR, green: quad.endG, blue: quad.endB, alpha: quad.endA)
        let effectType = quad.effectType
        let effectIntensity = quad.effectIntensity
        let effectParam1 = quad.effectParam1
        let effectParam2 = quad.effectParam2
        let effectParam3 = quad.effectParam3
        let effectParam4 = quad.effectParam4
        let clipRadius = max(0, Double(quad.clipCornerRadius))
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let pixelCenterX = Double(x) + 0.5
                let pixelCenterY = Double(y) + 0.5
                let (localX, localY) = localOf(pixelCenterX, pixelCenterY)
                let coverage = roundedRectCoverage(x: localX, y: localY, rect: rect, cornerRadii: cornerRadii)
                guard coverage > 0 else {
                    continue
                }

                if clipRadius > 0 {
                    let clipRect = Rect(
                        x: Double(quad.clipX),
                        y: Double(quad.clipY),
                        width: Double(quad.clipWidth),
                        height: Double(quad.clipHeight)
                    )
                    // Clip is in world (pre-rotation) coordinates; use
                    // the world pixel center, not the local-rotated one.
                    let clipCoverage = roundedRectCoverage(
                        x: pixelCenterX, y: pixelCenterY, rect: clipRect, radius: clipRadius)
                    guard clipCoverage > 0 else {
                        continue
                    }
                }

                let progress: Float
                if quad.gradientAxis >= 0.5 {
                    progress = Float(clamp((localX - rect.minX) / max(rect.size.width, 1), lower: 0, upper: 1))
                } else {
                    progress = Float(clamp((localY - rect.minY) / max(rect.size.height, 1), lower: 0, upper: 1))
                }
                var color = start.interpolated(to: end, progress: progress).withAlphaMultiplier(Float(coverage))
                color = applyRasterColorEffect(
                    color, effectType: effectType, intensity: effectIntensity, param1: effectParam1,
                    param2: effectParam2, param3: effectParam3, param4: effectParam4)
                let mode = BlendMode(rawValue: Int(quad.blendMode)) ?? .normal
                blend(color, x: x, y: y, mode: mode)
            }
        }

        let blurRadius = Int(quad.blurRadius)
        if blurRadius > 0 {
            applyBoxBlur(to: bounds, radius: blurRadius)
            if quad.blurOpaque > 0.5 {
                for y in bounds.y0..<bounds.y1 {
                    for x in bounds.x0..<bounds.x1 {
                        let offset = pixelOffset(x: x, y: y)
                        pixels[offset + 3] = 255
                    }
                }
            }
        }
    }

    mutating func drawShadow(_ shadow: ShadowPrimitive) {
        let spread = Double(max(shadow.blurRadius, 0))
        let rect = Rect(
            x: Double(shadow.x + shadow.offsetX) - spread * 0.5,
            y: Double(shadow.y + shadow.offsetY) - spread * 0.5,
            width: Double(shadow.width) + spread,
            height: Double(shadow.height) + spread
        )
        guard
            let bounds = clippedPixelBounds(
                rect, clip: clipRect(shadow.clipX, shadow.clipY, shadow.clipWidth, shadow.clipHeight))
        else {
            return
        }

        let color = RasterColor(
            red: shadow.colorR, green: shadow.colorG, blue: shadow.colorB, alpha: shadow.colorA * 0.55)
        let radius = max(0, Double(shadow.cornerRadius + shadow.blurRadius * 0.35))
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let coverage = roundedRectCoverage(
                    x: Double(x) + 0.5,
                    y: Double(y) + 0.5,
                    rect: rect,
                    radius: radius
                )
                if coverage > 0 {
                    blend(color.withAlphaMultiplier(Float(coverage)), x: x, y: y)
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
            let bounds = clippedPixelBounds(
                rect, clip: clipRect(glyph.clipX, glyph.clipY, glyph.clipWidth, glyph.clipHeight))
        else {
            return
        }

        let atlasWidth = max(1, Int(atlas.width))
        let atlasHeight = max(1, Int(atlas.height))
        let color = RasterColor(red: glyph.colorR, green: glyph.colorG, blue: glyph.colorB, alpha: glyph.colorA)
        let u0 = Double(glyph.atlasU0)
        let v0 = Double(glyph.atlasV0)
        let u1 = Double(glyph.atlasU1)
        let v1 = Double(glyph.atlasV1)

        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let tx = clamp((Double(x) + 0.5 - rect.minX) / max(rect.size.width, 1), lower: 0, upper: 1)
                let ty = clamp((Double(y) + 0.5 - rect.minY) / max(rect.size.height, 1), lower: 0, upper: 1)
                let sourceX = clamp(
                    Int(((u0 + (u1 - u0) * tx) * Double(atlasWidth)).rounded(.down)), lower: 0, upper: atlasWidth - 1)
                let sourceY = clamp(
                    Int(((v0 + (v1 - v0) * ty) * Double(atlasHeight)).rounded(.down)), lower: 0, upper: atlasHeight - 1)
                let offset = (sourceY * atlasWidth + sourceX) * 4
                guard offset + 3 < atlas.pixels.count else {
                    continue
                }

                let alphaByte = atlas.pixels[offset + 3]
                let coverage =
                    alphaByte > 0
                    ? Float(alphaByte) / 255.0
                    : Float(max(atlas.pixels[offset], max(atlas.pixels[offset + 1], atlas.pixels[offset + 2]))) / 255.0
                if coverage > 0 {
                    blend(color.withAlphaMultiplier(coverage), x: x, y: y)
                }
            }
        }
    }

    mutating func drawImage(_ image: ImagePrimitive, bitmap: BitmapSurface) {
        let rect = Rect(
            x: Double(image.screenX),
            y: Double(image.screenY),
            width: Double(image.screenW),
            height: Double(image.screenH)
        )
        guard
            let bounds = clippedPixelBounds(
                rect, clip: clipRect(image.clipX, image.clipY, image.clipWidth, image.clipHeight))
        else {
            return
        }

        let sourceWidth = max(1, Int(bitmap.width))
        let sourceHeight = max(1, Int(bitmap.height))
        let bytesPerRow = max(sourceWidth * 4, Int(bitmap.bytesPerRow))
        // `blend` works in straight alpha, so premultiplied sources (the
        // DirectWrite/GDI text path, and anything read back from the GPU)
        // are divided out per texel. The GPU does the mirror of this by
        // normalizing every upload to premultiplied instead.
        let isPremultiplied = bitmap.format.alphaMode == .premultiplied
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let tx = clamp((Double(x) + 0.5 - rect.minX) / max(rect.size.width, 1), lower: 0, upper: 1)
                let ty = clamp((Double(y) + 0.5 - rect.minY) / max(rect.size.height, 1), lower: 0, upper: 1)
                let sourceX = clamp(
                    Int((Double(image.uvX) + Double(image.uvW) * tx) * Double(sourceWidth)), lower: 0,
                    upper: sourceWidth - 1)
                let sourceY = clamp(
                    Int((Double(image.uvY) + Double(image.uvH) * ty) * Double(sourceHeight)), lower: 0,
                    upper: sourceHeight - 1)
                let offset = sourceY * bytesPerRow + sourceX * 4
                guard offset + 3 < bitmap.pixels.count else {
                    continue
                }

                let sourceAlpha = Float(bitmap.pixels[offset + 3]) / 255
                let divisor = isPremultiplied && sourceAlpha > 0 ? sourceAlpha : 1
                blend(
                    RasterColor(
                        red: Float(bitmap.pixels[offset + 2]) / 255 / divisor,
                        green: Float(bitmap.pixels[offset + 1]) / 255 / divisor,
                        blue: Float(bitmap.pixels[offset]) / 255 / divisor,
                        alpha: sourceAlpha * image.opacity
                    ),
                    x: x,
                    y: y
                )
            }
        }
    }

    private mutating func applyBoxBlur(to bounds: PixelBounds, radius: Int) {
        guard radius > 0 else { return }
        let w = bounds.x1 - bounds.x0
        let h = bounds.y1 - bounds.y0
        guard w > 0, h > 0 else { return }

        let kernel = gaussianBlurKernel(radius: radius)
        var temp = [UInt8](repeating: 0, count: h * w * 4)

        // Horizontal pass: each pixel becomes a weighted sum of its
        // horizontal neighbourhood. Edge samples clamp by re-normalising
        // the truncated kernel so the bounds don't darken the borders.
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                var sumB: Float = 0
                var sumG: Float = 0
                var sumR: Float = 0
                var sumA: Float = 0
                var weight: Float = 0
                let xStart = max(x - radius, bounds.x0)
                let xEnd = min(x + radius + 1, bounds.x1)
                for k in xStart..<xEnd {
                    let kw = kernel[k - x + radius]
                    let offset = pixelOffset(x: k, y: y)
                    sumB += Float(pixels[offset]) * kw
                    sumG += Float(pixels[offset + 1]) * kw
                    sumR += Float(pixels[offset + 2]) * kw
                    sumA += Float(pixels[offset + 3]) * kw
                    weight += kw
                }
                let inv = weight > 0 ? 1 / weight : 0
                let tempOffset = ((y - bounds.y0) * w + (x - bounds.x0)) * 4
                temp[tempOffset] = byte(sumB * inv / 255)
                temp[tempOffset + 1] = byte(sumG * inv / 255)
                temp[tempOffset + 2] = byte(sumR * inv / 255)
                temp[tempOffset + 3] = byte(sumA * inv / 255)
            }
        }

        // Vertical pass: same Gaussian kernel sampled vertically from the
        // horizontal pass's intermediate buffer.
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                var sumB: Float = 0
                var sumG: Float = 0
                var sumR: Float = 0
                var sumA: Float = 0
                var weight: Float = 0
                let yStart = max(y - radius, bounds.y0)
                let yEnd = min(y + radius + 1, bounds.y1)
                for k in yStart..<yEnd {
                    let kw = kernel[k - y + radius]
                    let tempOffset = ((k - bounds.y0) * w + (x - bounds.x0)) * 4
                    sumB += Float(temp[tempOffset]) * kw
                    sumG += Float(temp[tempOffset + 1]) * kw
                    sumR += Float(temp[tempOffset + 2]) * kw
                    sumA += Float(temp[tempOffset + 3]) * kw
                    weight += kw
                }
                let inv = weight > 0 ? 1 / weight : 0
                let offset = pixelOffset(x: x, y: y)
                pixels[offset] = byte(sumB * inv / 255)
                pixels[offset + 1] = byte(sumG * inv / 255)
                pixels[offset + 2] = byte(sumR * inv / 255)
                pixels[offset + 3] = byte(sumA * inv / 255)
            }
        }
    }

    mutating func drawPath(_ path: PathPrimitive) {
        let clip = path.clipBounds ?? Rect(x: 0, y: 0, width: Double(width), height: Double(height))
        guard let bounds = clippedPixelBounds(path.bounds, clip: clip) else {
            return
        }

        let fillColor = RasterColor(path.fillColor)
        let strokeColor = RasterColor(path.strokeColor)
        let flattened = FlattenedPath(path.elements, bounds: path.bounds)

        if fillColor.alpha > 0 {
            for y in bounds.y0..<bounds.y1 {
                let scanY = Double(y) + 0.5
                let intersections = flattened.scanlineIntersections(y: scanY)
                guard intersections.count >= 2 else { continue }
                let sorted = intersections.sorted()
                for i in stride(from: 0, to: sorted.count - 1, by: 2) {
                    let x0 = max(bounds.x0, Int(sorted[i].rounded(.up)))
                    let x1 = min(bounds.x1, Int(sorted[i + 1].rounded(.down)) + 1)
                    for x in x0..<x1 {
                        blend(fillColor, x: x, y: y)
                    }
                }
            }
        }

        if strokeColor.alpha > 0, path.lineWidth > 0 {
            let halfWidth = path.lineWidth / 2
            for segment in flattened.segments {
                let dx = segment.end.x - segment.start.x
                let dy = segment.end.y - segment.start.y
                let length = hypot(dx, dy)
                guard length > 0 else { continue }
                let nx = -dy / length * halfWidth
                let ny = dx / length * halfWidth

                let strokeQuad = [
                    Point(x: segment.start.x + nx, y: segment.start.y + ny),
                    Point(x: segment.end.x + nx, y: segment.end.y + ny),
                    Point(x: segment.end.x - nx, y: segment.end.y - ny),
                    Point(x: segment.start.x - nx, y: segment.start.y - ny),
                ]
                let strokePath = FlattenedPath(polygon: strokeQuad)
                for y in bounds.y0..<bounds.y1 {
                    let scanY = Double(y) + 0.5
                    let intersections = strokePath.scanlineIntersections(y: scanY)
                    guard intersections.count >= 2 else { continue }
                    let sorted = intersections.sorted()
                    for i in stride(from: 0, to: sorted.count - 1, by: 2) {
                        let x0 = max(bounds.x0, Int(sorted[i].rounded(.up)))
                        let x1 = min(bounds.x1, Int(sorted[i + 1].rounded(.down)) + 1)
                        for x in x0..<x1 {
                            blend(strokeColor, x: x, y: y)
                        }
                    }
                }
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

    private mutating func blend(_ color: RasterColor, x: Int, y: Int, mode: BlendMode = .normal) {
        let sourceAlpha = clamp(color.alpha, lower: 0, upper: 1)
        guard sourceAlpha > 0 else {
            return
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

        let blendedRed: Float
        let blendedGreen: Float
        let blendedBlue: Float
        switch mode {
        case .normal:
            blendedRed = color.red
            blendedGreen = color.green
            blendedBlue = color.blue
        case .multiply:
            blendedRed = color.red * destinationRed
            blendedGreen = color.green * destinationGreen
            blendedBlue = color.blue * destinationBlue
        case .screen:
            blendedRed = 1 - (1 - color.red) * (1 - destinationRed)
            blendedGreen = 1 - (1 - color.green) * (1 - destinationGreen)
            blendedBlue = 1 - (1 - color.blue) * (1 - destinationBlue)
        case .overlay:
            blendedRed =
                destinationRed < 0.5 ? 2 * color.red * destinationRed : 1 - 2 * (1 - color.red) * (1 - destinationRed)
            blendedGreen =
                destinationGreen < 0.5
                ? 2 * color.green * destinationGreen : 1 - 2 * (1 - color.green) * (1 - destinationGreen)
            blendedBlue =
                destinationBlue < 0.5
                ? 2 * color.blue * destinationBlue : 1 - 2 * (1 - color.blue) * (1 - destinationBlue)
        case .additive:
            blendedRed = min(1, color.red + destinationRed)
            blendedGreen = min(1, color.green + destinationGreen)
            blendedBlue = min(1, color.blue + destinationBlue)
        }

        pixels[offset] = byte(
            (blendedBlue * sourceAlpha + destinationBlue * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        pixels[offset + 1] = byte(
            (blendedGreen * sourceAlpha + destinationGreen * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        pixels[offset + 2] = byte(
            (blendedRed * sourceAlpha + destinationRed * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        pixels[offset + 3] = byte(outputAlpha)
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
private struct PixelBounds {
    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int
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
private func clipRect(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Rect? {
    guard width > 0, height > 0 else {
        return nil
    }
    return Rect(x: Double(x), y: Double(y), width: Double(width), height: Double(height))
}
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
            red: (color.red - 0.5) * Float(1.0 + i) + 0.5,
            green: (color.green - 0.5) * Float(1.0 + i) + 0.5,
            blue: (color.blue - 0.5) * Float(1.0 + i) + 0.5,
            alpha: color.alpha
        )
    }

    // 3 = saturation
    if t < 3.5 {
        let lum = Float(0.299 * Double(color.red) + 0.587 * Double(color.green) + 0.114 * Double(color.blue))
        return RasterColor(
            red: lum + (color.red - lum) * Float(1.0 + i),
            green: lum + (color.green - lum) * Float(1.0 + i),
            blue: lum + (color.blue - lum) * Float(1.0 + i),
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

    // 8 = luminanceToAlpha
    if t < 8.5 {
        let lum = Float(0.299 * Double(color.red) + 0.587 * Double(color.green) + 0.114 * Double(color.blue))
        return RasterColor(red: lum, green: lum, blue: lum, alpha: lum)
    }

    return color
}
private func roundedRectCoverage(x: Double, y: Double, rect: Rect, radius: Double) -> Double {
    let r = max(0, radius)
    return roundedRectCoverage(
        x: x, y: y, rect: rect, cornerRadii: (topLeft: r, topRight: r, bottomRight: r, bottomLeft: r))
}
/// Per-corner variant of the uniform rounded-rect coverage above. The
/// corner radius is selected by the quadrant the sample falls into
/// (split along the rect's centrelines) — the same rule the D3D11
/// pixel shader's `roundedRectDistance` implements, so both backends
/// agree on the shape boundary. With four equal radii this reduces to
/// exactly the historic uniform computation (byte-identical output).
private func roundedRectCoverage(
    x: Double,
    y: Double,
    rect: Rect,
    cornerRadii: (topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double)
) -> Double {
    let localX = x - rect.midX
    let localY = y - rect.midY
    let radius =
        localX > 0
        ? (localY > 0 ? cornerRadii.bottomRight : cornerRadii.topRight)
        : (localY > 0 ? cornerRadii.bottomLeft : cornerRadii.topLeft)
    let clampedRadius = max(0, min(radius, min(rect.size.width, rect.size.height) * 0.5))
    guard clampedRadius > 0 else {
        return rect.contains(Point(x: x, y: y)) ? 1 : 0
    }

    let innerMinX = rect.minX + clampedRadius
    let innerMaxX = rect.maxX - clampedRadius
    let innerMinY = rect.minY + clampedRadius
    let innerMaxY = rect.maxY - clampedRadius
    let closestX = clamp(x, lower: innerMinX, upper: innerMaxX)
    let closestY = clamp(y, lower: innerMinY, upper: innerMaxY)
    let distance = ((x - closestX) * (x - closestX) + (y - closestY) * (y - closestY)).squareRoot()
    return clamp(clampedRadius + 0.5 - distance, lower: 0, upper: 1)
}
private func byte(_ value: Float) -> UInt8 {
    UInt8((clamp(value, lower: 0, upper: 1) * 255).rounded())
}
private func clamp<T: Comparable>(_ value: T, lower: T, upper: T) -> T {
    min(max(value, lower), upper)
}
private struct FlattenedSegment {
    var start: Point
    var end: Point
}
private struct FlattenedPath {
    var segments: [FlattenedSegment]

    init(polygon points: [Point]) {
        var segs: [FlattenedSegment] = []
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            segs.append(FlattenedSegment(start: points[i], end: points[j]))
        }
        self.segments = segs
    }

    init(_ elements: [PathElement], bounds: Rect) {
        var segs: [FlattenedSegment] = []
        var current = Point.zero
        var subpathStart = Point.zero
        var needsMove = true

        for element in elements {
            switch element {
            case .moveTo(let p):
                current = p
                subpathStart = p
                needsMove = false
            case .lineTo(let p):
                if !needsMove {
                    segs.append(FlattenedSegment(start: current, end: p))
                }
                current = p
            case .quadraticCurveTo(let control, let end):
                if !needsMove {
                    segs.append(contentsOf: flattenQuadratic(start: current, control: control, end: end))
                }
                current = end
            case .cubicCurveTo(let control1, let control2, let end):
                if !needsMove {
                    segs.append(
                        contentsOf: flattenCubic(start: current, control1: control1, control2: control2, end: end))
                }
                current = end
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                segs.append(
                    contentsOf: flattenArc(
                        center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise
                    ))
                let finalAngle = clockwise ? endAngle : startAngle
                current = Point(x: center.x + radius * cos(finalAngle), y: center.y + radius * sin(finalAngle))
            case .close:
                if current != subpathStart {
                    segs.append(FlattenedSegment(start: current, end: subpathStart))
                }
                current = subpathStart
            }
        }
        self.segments = segs
    }

    func scanlineIntersections(y: Double) -> [Double] {
        var xs: [Double] = []
        for seg in segments {
            let y0 = seg.start.y
            let y1 = seg.end.y
            if (y0 < y && y1 >= y) || (y1 < y && y0 >= y) || (y0 == y && y1 == y) {
                if y0 == y1 {
                    xs.append(seg.start.x)
                    xs.append(seg.end.x)
                } else {
                    let t = (y - y0) / (y1 - y0)
                    xs.append(seg.start.x + t * (seg.end.x - seg.start.x))
                }
            }
        }
        return xs
    }
}
private func flattenQuadratic(start: Point, control: Point, end: Point) -> [FlattenedSegment] {
    let flatness: Double = 0.25
    let dx = end.x - start.x
    let dy = end.y - start.y
    let d = abs((control.x - end.x) * dy - (control.y - end.y) * dx)
    if d * d <= flatness * flatness * (dx * dx + dy * dy) {
        return [FlattenedSegment(start: start, end: end)]
    }
    let m0 = Point(x: (start.x + control.x) * 0.5, y: (start.y + control.y) * 0.5)
    let m1 = Point(x: (control.x + end.x) * 0.5, y: (control.y + end.y) * 0.5)
    let mid = Point(x: (m0.x + m1.x) * 0.5, y: (m0.y + m1.y) * 0.5)
    var left = flattenQuadratic(start: start, control: m0, end: mid)
    let right = flattenQuadratic(start: mid, control: m1, end: end)
    left.append(contentsOf: right)
    return left
}
private func flattenCubic(start: Point, control1: Point, control2: Point, end: Point) -> [FlattenedSegment] {
    let flatness: Double = 0.25
    let dx = end.x - start.x
    let dy = end.y - start.y
    let d1 = abs((control1.x - end.x) * dy - (control1.y - end.y) * dx)
    let d2 = abs((control2.x - end.x) * dy - (control2.y - end.y) * dx)
    if (d1 * d1 + d2 * d2) <= flatness * flatness * (dx * dx + dy * dy) {
        return [FlattenedSegment(start: start, end: end)]
    }
    let m0 = Point(x: (start.x + control1.x) * 0.5, y: (start.y + control1.y) * 0.5)
    let m1 = Point(x: (control1.x + control2.x) * 0.5, y: (control1.y + control2.y) * 0.5)
    let m2 = Point(x: (control2.x + end.x) * 0.5, y: (control2.y + end.y) * 0.5)
    let n0 = Point(x: (m0.x + m1.x) * 0.5, y: (m0.y + m1.y) * 0.5)
    let n1 = Point(x: (m1.x + m2.x) * 0.5, y: (m1.y + m2.y) * 0.5)
    let mid = Point(x: (n0.x + n1.x) * 0.5, y: (n0.y + n1.y) * 0.5)
    var left = flattenCubic(start: start, control1: m0, control2: n0, end: mid)
    let right = flattenCubic(start: mid, control1: n1, control2: m2, end: end)
    left.append(contentsOf: right)
    return left
}
private func flattenArc(center: Point, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool)
    -> [FlattenedSegment]
{
    // Only the end angle is normalized into the directed sweep range; start is fixed.
    var end = endAngle
    if clockwise {
        while end > startAngle { end -= 2 * .pi }
    } else {
        while end < startAngle { end += 2 * .pi }
    }
    let sweep = end - startAngle
    let steps = max(4, Int(ceil(abs(sweep) * radius * 0.5)))
    var segs: [FlattenedSegment] = []
    let step = sweep / Double(steps)
    var prev = Point(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle))
    for i in 1...steps {
        let a = startAngle + step * Double(i)
        let p = Point(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        segs.append(FlattenedSegment(start: prev, end: p))
        prev = p
    }
    return segs
}
