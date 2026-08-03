import Foundation
import SwiftWindowsCore

/// The CPU side of the blur, over a premultiplied BGRA byte buffer.
///
/// Two callers share it, and that is the point:
///
/// - `GPUIRawSceneRasterizer` blurs the framebuffer region under a material
///   quad, transcribing `D3D11BackdropBlurEngine` pass for pass;
/// - `ScenePainter` blurs the isolated bitmap a `.blur(radius:)` subtree
///   rasterized into, where there is no GPU pass at all.
///
/// Everything here is 8-bit between passes because the GPU's ping-pong
/// targets are `B8G8R8A8_UNORM`: a float pipeline would be *more* accurate
/// and would therefore diverge from the backend it exists to match.
public enum PremultipliedImageBlur {

    /// Blurs an isolated premultiplied image according to the shared
    /// `BlurPassPlan`: full resolution for ordinary radii, and successive
    /// 2× halvings + a reduced-radius blur + a bilinear upsample once the
    /// radius passes `BlurPassPlan.fullResolutionRadiusLimit`.
    ///
    /// Every step is the CPU transcription of what the D3D11 blur engine
    /// does, in the same order and at the same precision. The halving reads
    /// the span `SubTextureRegion.halvingSourceExtent` names — the same
    /// derivation the GPU pass's UV scale comes from — and the upsample
    /// clamps through `SubTextureRegion`'s texel-centre bounds. The plan is
    /// keyed on the radius alone so the two backends can never disagree
    /// about how many halvings to run.
    public static func blur(_ image: inout [UInt8], width: Int, height: Int, radius: Int) {
        guard radius > 0, width > 0, height > 0 else { return }
        let plan = BlurPassPlan(radius: radius, regionWidth: width, regionHeight: height)
        guard plan.isReduced else {
            blurAtFullResolution(&image, width: width, height: height, radius: radius)
            return
        }

        var reduced = image
        var reducedWidth = width
        var reducedHeight = height
        for _ in 0..<plan.halvingPassCount {
            let halved = halved(reduced, width: reducedWidth, height: reducedHeight)
            reduced = halved.pixels
            reducedWidth = halved.width
            reducedHeight = halved.height
        }
        blurAtFullResolution(&reduced, width: reducedWidth, height: reducedHeight, radius: plan.reducedRadius)
        upsample(
            reduced, sourceWidth: reducedWidth, sourceHeight: reducedHeight,
            into: &image, width: width, height: height, factor: plan.downsampleFactor)
    }

    /// One 2× reduction: each output texel is the average of the 2×2 block
    /// below it, which is exactly what a bilinear tap placed on the boundary
    /// between texels `2i` and `2i+1` returns on the GPU.
    ///
    /// The source span is `SubTextureRegion.halvingSourceExtent`, so an odd
    /// trailing row or column is dropped — and it is dropped on the GPU too,
    /// because the halving pass derives its UV scale from the same value.
    /// The two used to differ here: the GPU's UVs came off the full region,
    /// so at an odd extent its taps drifted by up to a whole texel and both
    /// backends claimed to be an exact transcription of the other.
    static func halved(
        _ image: [UInt8], width: Int, height: Int
    ) -> (pixels: [UInt8], width: Int, height: Int) {
        let outputWidth = SubTextureRegion.halvedExtent(width)
        let outputHeight = SubTextureRegion.halvedExtent(height)
        let sourceWidth = SubTextureRegion.halvingSourceExtent(width)
        let sourceHeight = SubTextureRegion.halvingSourceExtent(height)
        var output = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)
        for y in 0..<outputHeight {
            let sourceY0 = min(y * 2, sourceHeight - 1)
            let sourceY1 = min(sourceY0 + 1, sourceHeight - 1)
            for x in 0..<outputWidth {
                let sourceX0 = min(x * 2, sourceWidth - 1)
                let sourceX1 = min(sourceX0 + 1, sourceWidth - 1)
                let a = (sourceY0 * width + sourceX0) * 4
                let b = (sourceY0 * width + sourceX1) * 4
                let c = (sourceY1 * width + sourceX0) * 4
                let d = (sourceY1 * width + sourceX1) * 4
                let destination = (y * outputWidth + x) * 4
                for channel in 0..<4 {
                    let sum =
                        Float(image[a + channel]) + Float(image[b + channel])
                        + Float(image[c + channel]) + Float(image[d + channel])
                    output[destination + channel] = clampedByte(sum / (4 * 255))
                }
            }
        }
        return (output, outputWidth, outputHeight)
    }

    /// Bilinear upsample back to the image's resolution, sampling at the
    /// same coordinates the composite pixel shader does: a full-resolution
    /// pixel `p` reads the reduced image at `(p + 0.5) / factor`, clamped to
    /// the reduced image's outermost texel centres through
    /// `SubTextureRegion.clampTexelCentre` — the same bounds the shader
    /// clamps to, from the same derivation rather than a second spelling of
    /// it.
    static func upsample(
        _ source: [UInt8],
        sourceWidth: Int,
        sourceHeight: Int,
        into destination: inout [UInt8],
        width: Int,
        height: Int,
        factor: Int
    ) {
        guard sourceWidth > 0, sourceHeight > 0 else { return }
        let scale = Float(max(1, factor))
        // The reduced image occupies the whole of its own buffer here, so
        // the region and the texture coincide; what the region contributes
        // is the clamp, which is what keeps the bilinear footprint inside
        // the texels the blur actually wrote.
        let region = SubTextureRegion(textureWidth: sourceWidth, textureHeight: sourceHeight)
        for y in 0..<height {
            for x in 0..<width {
                let tap = region.clampTexelCentre((Float(x) + 0.5) / scale, (Float(y) + 0.5) / scale)
                // Texel centres sit at `index + 0.5`, so the lower texel of
                // the bilinear pair is the tap minus that half.
                let sampleX = max(tap.x - 0.5, 0)
                let sampleY = max(tap.y - 0.5, 0)
                let x0 = Int(sampleX)
                let x1 = min(x0 + 1, sourceWidth - 1)
                let fx = sampleX - Float(x0)
                let y0 = Int(sampleY)
                let y1 = min(y0 + 1, sourceHeight - 1)
                let fy = sampleY - Float(y0)
                let a = (y0 * sourceWidth + x0) * 4
                let b = (y0 * sourceWidth + x1) * 4
                let c = (y1 * sourceWidth + x0) * 4
                let d = (y1 * sourceWidth + x1) * 4
                let offset = (y * width + x) * 4
                for channel in 0..<4 {
                    let top = Float(source[a + channel]) * (1 - fx) + Float(source[b + channel]) * fx
                    let bottom = Float(source[c + channel]) * (1 - fx) + Float(source[d + channel]) * fx
                    destination[offset + channel] = clampedByte((top * (1 - fy) + bottom * fy) / 255)
                }
            }
        }
    }

    /// Two-pass separable Gaussian over an isolated image, with taps beyond
    /// the image clamped to its outermost texel.
    ///
    /// Clamp-to-edge rather than truncated-kernel renormalisation, because
    /// clamping is what the GPU pass does (the shader clamps every tap into
    /// the region's texel-centre range). The two policies agree to within
    /// rounding while the kernel is narrower than the image and diverge
    /// completely once it is wider — which is exactly what a
    /// `.blur(radius: 80)` on a 2× display produces.
    static func blurAtFullResolution(_ image: inout [UInt8], width: Int, height: Int, radius: Int) {
        guard radius > 0, width > 0, height > 0 else { return }
        let kernel = gaussianBlurKernel(radius: radius)
        // Prefix sums so the taps that all clamp to the same edge texel cost
        // one multiply instead of `radius` of them: without this a radius
        // wider than the image turns every pixel into a full-kernel walk
        // over a handful of distinct samples.
        var prefix = [Float](repeating: 0, count: kernel.count + 1)
        for index in 0..<kernel.count {
            prefix[index + 1] = prefix[index] + kernel[index]
        }
        var temp = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            let rowOffset = y * width
            for x in 0..<width {
                let firstTap = max(-radius, -x)
                let lastTap = min(radius, width - 1 - x)
                let leadingWeight = prefix[min(kernel.count, max(0, radius - x))]
                let trailingWeight = prefix[kernel.count] - prefix[min(kernel.count, max(0, radius + width - x))]
                var sumBlue = Float(image[rowOffset * 4]) * leadingWeight
                var sumGreen = Float(image[rowOffset * 4 + 1]) * leadingWeight
                var sumRed = Float(image[rowOffset * 4 + 2]) * leadingWeight
                var sumAlpha = Float(image[rowOffset * 4 + 3]) * leadingWeight
                let lastOffset = (rowOffset + width - 1) * 4
                sumBlue += Float(image[lastOffset]) * trailingWeight
                sumGreen += Float(image[lastOffset + 1]) * trailingWeight
                sumRed += Float(image[lastOffset + 2]) * trailingWeight
                sumAlpha += Float(image[lastOffset + 3]) * trailingWeight
                if firstTap <= lastTap {
                    for tap in firstTap...lastTap {
                        let weight = kernel[tap + radius]
                        let offset = (rowOffset + x + tap) * 4
                        sumBlue += Float(image[offset]) * weight
                        sumGreen += Float(image[offset + 1]) * weight
                        sumRed += Float(image[offset + 2]) * weight
                        sumAlpha += Float(image[offset + 3]) * weight
                    }
                }
                let destination = (rowOffset + x) * 4
                temp[destination] = clampedByte(sumBlue / 255)
                temp[destination + 1] = clampedByte(sumGreen / 255)
                temp[destination + 2] = clampedByte(sumRed / 255)
                temp[destination + 3] = clampedByte(sumAlpha / 255)
            }
        }

        for y in 0..<height {
            let firstTap = max(-radius, -y)
            let lastTap = min(radius, height - 1 - y)
            let leadingWeight = prefix[min(kernel.count, max(0, radius - y))]
            let trailingWeight = prefix[kernel.count] - prefix[min(kernel.count, max(0, radius + height - y))]
            for x in 0..<width {
                let topOffset = x * 4
                let bottomOffset = ((height - 1) * width + x) * 4
                var sumBlue = Float(temp[topOffset]) * leadingWeight + Float(temp[bottomOffset]) * trailingWeight
                var sumGreen =
                    Float(temp[topOffset + 1]) * leadingWeight + Float(temp[bottomOffset + 1]) * trailingWeight
                var sumRed =
                    Float(temp[topOffset + 2]) * leadingWeight + Float(temp[bottomOffset + 2]) * trailingWeight
                var sumAlpha =
                    Float(temp[topOffset + 3]) * leadingWeight + Float(temp[bottomOffset + 3]) * trailingWeight
                if firstTap <= lastTap {
                    for tap in firstTap...lastTap {
                        let weight = kernel[tap + radius]
                        let offset = ((y + tap) * width + x) * 4
                        sumBlue += Float(temp[offset]) * weight
                        sumGreen += Float(temp[offset + 1]) * weight
                        sumRed += Float(temp[offset + 2]) * weight
                        sumAlpha += Float(temp[offset + 3]) * weight
                    }
                }
                let destination = (y * width + x) * 4
                image[destination] = clampedByte(sumBlue / 255)
                image[destination + 1] = clampedByte(sumGreen / 255)
                image[destination + 2] = clampedByte(sumRed / 255)
                image[destination + 3] = clampedByte(sumAlpha / 255)
            }
        }
    }

    // MARK: - Whole-surface blur

    /// Blurs a straight-alpha BGRA surface — the format
    /// `GPUIRawSceneRasterizer` produces — and returns it in the same
    /// format.
    ///
    /// The blur itself runs premultiplied, which is not a detail: blurring
    /// straight-alpha bytes bleeds the colour of fully transparent texels
    /// into their neighbours, so an isolated subtree over a transparent
    /// margin would blur towards black rather than towards nothing.
    public static func blurred(_ surface: BitmapSurface, radius: Int) -> BitmapSurface {
        let width = Int(surface.width)
        let height = Int(surface.height)
        let stride = Int(surface.bytesPerRow)
        guard radius > 0, width > 0, height > 0, stride >= width * 4 else { return surface }
        guard surface.pixels.count >= (height - 1) * stride + width * 4 else { return surface }

        var image = [UInt8](repeating: 0, count: width * height * 4)
        surface.pixels.withUnsafeBytes { source in
            for y in 0..<height {
                for x in 0..<width {
                    let read = y * stride + x * 4
                    let write = (y * width + x) * 4
                    let alpha = Float(source[read + 3]) / 255
                    image[write] = clampedByte(Float(source[read]) * alpha / 255)
                    image[write + 1] = clampedByte(Float(source[read + 1]) * alpha / 255)
                    image[write + 2] = clampedByte(Float(source[read + 2]) * alpha / 255)
                    image[write + 3] = source[read + 3]
                }
            }
        }

        blur(&image, width: width, height: height, radius: radius)

        var output = surface
        var pixels = [UInt8](repeating: 0, count: height * stride)
        for y in 0..<height {
            for x in 0..<width {
                let read = (y * width + x) * 4
                let write = y * stride + x * 4
                let alpha = Float(image[read + 3]) / 255
                guard alpha > 0 else { continue }
                pixels[write] = clampedByte(Float(image[read]) / alpha / 255)
                pixels[write + 1] = clampedByte(Float(image[read + 1]) / alpha / 255)
                pixels[write + 2] = clampedByte(Float(image[read + 2]) / alpha / 255)
                pixels[write + 3] = image[read + 3]
            }
        }
        output.pixels = Data(pixels)
        return output
    }

    /// Saturating byte conversion, rounding exactly as the rasterizer's own
    /// `byte(_:)` does — these bytes are compared against its output at a
    /// one-unit tolerance, so a truncation here would be a systematic
    /// half-unit bias. A NaN is a trap in `UInt8(_:)`, and a blur weight
    /// arriving as NaN is a bug in the caller, not a reason to kill the
    /// process mid-frame.
    private static func clampedByte(_ value: Float) -> UInt8 {
        guard value.isFinite else { return 0 }
        return UInt8((min(max(value, 0), 1) * 255).rounded())
    }
}
