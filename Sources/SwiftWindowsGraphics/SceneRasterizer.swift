import Foundation
import SwiftWindowsCore

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
        guard let bounds = clippedPixelBounds(rect, clip: clipRect(quad.clipX, quad.clipY, quad.clipWidth, quad.clipHeight)) else {
            return
        }

        let radius = max(0, Double(quad.cornerRadius))
        let start = RasterColor(red: quad.startR, green: quad.startG, blue: quad.startB, alpha: quad.startA)
        let end = RasterColor(red: quad.endR, green: quad.endG, blue: quad.endB, alpha: quad.endA)
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let centerX = Double(x) + 0.5
                let centerY = Double(y) + 0.5
                let coverage = roundedRectCoverage(x: centerX, y: centerY, rect: rect, radius: radius)
                guard coverage > 0 else {
                    continue
                }

                let progress: Float
                if quad.gradientAxis >= 0.5 {
                    progress = Float(clamp((centerX - rect.minX) / max(rect.size.width, 1), lower: 0, upper: 1))
                } else {
                    progress = Float(clamp((centerY - rect.minY) / max(rect.size.height, 1), lower: 0, upper: 1))
                }
                blend(start.interpolated(to: end, progress: progress).withAlphaMultiplier(Float(coverage)), x: x, y: y)
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
        guard let bounds = clippedPixelBounds(rect, clip: clipRect(shadow.clipX, shadow.clipY, shadow.clipWidth, shadow.clipHeight)) else {
            return
        }

        let color = RasterColor(red: shadow.colorR, green: shadow.colorG, blue: shadow.colorB, alpha: shadow.colorA * 0.55)
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
        guard let bounds = clippedPixelBounds(rect, clip: clipRect(glyph.clipX, glyph.clipY, glyph.clipWidth, glyph.clipHeight)) else {
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
                let sourceX = clamp(Int(((u0 + (u1 - u0) * tx) * Double(atlasWidth)).rounded(.down)), lower: 0, upper: atlasWidth - 1)
                let sourceY = clamp(Int(((v0 + (v1 - v0) * ty) * Double(atlasHeight)).rounded(.down)), lower: 0, upper: atlasHeight - 1)
                let offset = (sourceY * atlasWidth + sourceX) * 4
                guard offset + 3 < atlas.pixels.count else {
                    continue
                }

                let alphaByte = atlas.pixels[offset + 3]
                let coverage = alphaByte > 0 ? Float(alphaByte) / 255.0 : Float(max(atlas.pixels[offset], max(atlas.pixels[offset + 1], atlas.pixels[offset + 2]))) / 255.0
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
        guard let bounds = clippedPixelBounds(rect, clip: clipRect(image.clipX, image.clipY, image.clipWidth, image.clipHeight)) else {
            return
        }

        let sourceWidth = max(1, Int(bitmap.width))
        let sourceHeight = max(1, Int(bitmap.height))
        let bytesPerRow = max(sourceWidth * 4, Int(bitmap.bytesPerRow))
        for y in bounds.y0..<bounds.y1 {
            for x in bounds.x0..<bounds.x1 {
                let tx = clamp((Double(x) + 0.5 - rect.minX) / max(rect.size.width, 1), lower: 0, upper: 1)
                let ty = clamp((Double(y) + 0.5 - rect.minY) / max(rect.size.height, 1), lower: 0, upper: 1)
                let sourceX = clamp(Int((Double(image.uvX) + Double(image.uvW) * tx) * Double(sourceWidth)), lower: 0, upper: sourceWidth - 1)
                let sourceY = clamp(Int((Double(image.uvY) + Double(image.uvH) * ty) * Double(sourceHeight)), lower: 0, upper: sourceHeight - 1)
                let offset = sourceY * bytesPerRow + sourceX * 4
                guard offset + 3 < bitmap.pixels.count else {
                    continue
                }

                blend(
                    RasterColor(
                        red: Float(bitmap.pixels[offset + 2]) / 255,
                        green: Float(bitmap.pixels[offset + 1]) / 255,
                        blue: Float(bitmap.pixels[offset]) / 255,
                        alpha: Float(bitmap.pixels[offset + 3]) / 255 * image.opacity
                    ),
                    x: x,
                    y: y
                )
            }
        }
    }

    func bitmapSurface() -> BitmapSurface {
        BitmapSurface(width: Int32(width), height: Int32(height), bytesPerRow: Int32(width * 4), pixels: Data(pixels))
    }

    private mutating func writeOpaque(_ color: RasterColor, x: Int, y: Int) {
        let offset = pixelOffset(x: x, y: y)
        pixels[offset] = byte(color.blue)
        pixels[offset + 1] = byte(color.green)
        pixels[offset + 2] = byte(color.red)
        pixels[offset + 3] = byte(color.alpha)
    }

    private mutating func blend(_ color: RasterColor, x: Int, y: Int) {
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

        pixels[offset] = byte((color.blue * sourceAlpha + destinationBlue * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        pixels[offset + 1] = byte((color.green * sourceAlpha + destinationGreen * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        pixels[offset + 2] = byte((color.red * sourceAlpha + destinationRed * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
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

private func roundedRectCoverage(x: Double, y: Double, rect: Rect, radius: Double) -> Double {
    guard radius > 0 else {
        return rect.contains(Point(x: x, y: y)) ? 1 : 0
    }

    let clampedRadius = min(radius, min(rect.size.width, rect.size.height) * 0.5)
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
