import Foundation
import SwiftWindowsCore

/// Ordered color operations on an isolated scene image. Values are authored
/// SwiftUI amounts: contrast and saturation use 1 for identity, not 0.
/// Effects run on straight color; render targets and image sampling remain
/// premultiplied. Each operation clamps its result before the next operation.
public enum SceneColorEffect: Equatable, Sendable {
    case brightness(Double)
    case contrast(Double)
    case saturation(Double)
    case grayscale(Double)
    case colorInvert
    case hueRotation(Double)
    case colorMultiply(Color)
    case luminanceToAlpha

    public var sanitized: SceneColorEffect {
        func amount(_ value: Double, identity: Double = 0) -> Double {
            guard value.isFinite else { return identity }
            return min(max(value, -1_000_000), 1_000_000)
        }
        switch self {
        case .brightness(let value): return .brightness(amount(value))
        case .contrast(let value): return .contrast(amount(value, identity: 1))
        case .saturation(let value): return .saturation(amount(value, identity: 1))
        case .grayscale(let value): return .grayscale(min(max(amount(value), 0), 1))
        case .hueRotation(let value):
            return .hueRotation(value.isFinite ? value.truncatingRemainder(dividingBy: 2 * .pi) : 0)
        case .colorMultiply(let color): return .colorMultiply(SceneColorEffects.clamped(color))
        case .colorInvert, .luminanceToAlpha: return self
        }
    }
}

public enum SceneColorEffects {
    /// Filters texels before image interpolation, matching the GPU's
    /// same-size offscreen filter target. Quantization occurs at the two
    /// premultiplied BGRA8 render targets, not between individual effects.
    public static func applying(_ effects: [SceneColorEffect], to bitmap: BitmapSurface) -> BitmapSurface {
        guard !effects.isEmpty, (try? bitmap.validate()) != nil else { return bitmap }
        let source = bitmap.premultipliedAlpha()
        var pixels = [UInt8](source.pixels)
        let stride = Int(source.bytesPerRow)
        for y in 0..<Int(source.height) {
            for x in 0..<Int(source.width) {
                let offset = y * stride + x * 4
                let alphaByte = Float(pixels[offset + 3])
                guard alphaByte > 0 else {
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    continue
                }
                let input = Color(
                    red: Float(pixels[offset + 2]) / alphaByte,
                    green: Float(pixels[offset + 1]) / alphaByte,
                    blue: Float(pixels[offset]) / alphaByte,
                    alpha: alphaByte / 255)
                let color = applying(effects, to: input)
                pixels[offset] = UInt8((color.blue * color.alpha * 255).rounded())
                pixels[offset + 1] = UInt8((color.green * color.alpha * 255).rounded())
                pixels[offset + 2] = UInt8((color.red * color.alpha * 255).rounded())
                pixels[offset + 3] = UInt8((color.alpha * 255).rounded())
            }
        }
        return BitmapSurface(
            width: source.width, height: source.height, bytesPerRow: source.bytesPerRow,
            pixels: Data(pixels), format: .bgra8Premultiplied)
    }

    /// The CPU spelling of the D3D11 image-effect shader. Keeping this in
    /// Graphics makes a scene-backed image meaningful to every backend.
    public static func applying(_ effects: [SceneColorEffect], to input: Color) -> Color {
        var color = clamped(input)
        for effect in effects {
            let r = color.red
            let g = color.green
            let b = color.blue
            let a = color.alpha
            switch effect.sanitized {
            case .brightness(let value):
                let amount = Float(value)
                color = Color(red: r + amount, green: g + amount, blue: b + amount, alpha: a)
            case .contrast(let value):
                let amount = Float(value)
                color = Color(
                    red: (r - 0.5) * amount + 0.5, green: (g - 0.5) * amount + 0.5,
                    blue: (b - 0.5) * amount + 0.5, alpha: a)
            case .saturation(let value):
                let amount = Float(value)
                let luminance: Float = 0.299 * r + 0.587 * g + 0.114 * b
                color = Color(
                    red: luminance + (r - luminance) * amount,
                    green: luminance + (g - luminance) * amount,
                    blue: luminance + (b - luminance) * amount, alpha: a)
            case .grayscale(let value):
                let amount = Float(value)
                let luminance: Float = 0.299 * r + 0.587 * g + 0.114 * b
                color = Color(
                    red: r + (luminance - r) * amount, green: g + (luminance - g) * amount,
                    blue: b + (luminance - b) * amount, alpha: a)
            case .colorInvert:
                color = Color(red: 1 - r, green: 1 - g, blue: 1 - b, alpha: a)
            case .hueRotation(let angle):
                if angle == 0 { continue }
                let cosine = Float(cos(angle))
                let sine = Float(sin(angle))
                color = Color(
                    red: (0.299 + 0.701 * cosine + 0.168 * sine) * r
                        + (0.587 - 0.587 * cosine + 0.330 * sine) * g
                        + (0.114 - 0.114 * cosine - 0.497 * sine) * b,
                    green: (0.299 - 0.299 * cosine - 0.328 * sine) * r
                        + (0.587 + 0.413 * cosine + 0.035 * sine) * g
                        + (0.114 - 0.114 * cosine + 0.292 * sine) * b,
                    blue: (0.299 - 0.300 * cosine + 1.250 * sine) * r
                        + (0.587 - 0.588 * cosine - 1.050 * sine) * g
                        + (0.114 + 0.886 * cosine - 0.203 * sine) * b,
                    alpha: a)
            case .colorMultiply(let multiplier):
                color = Color(
                    red: r * multiplier.red, green: g * multiplier.green,
                    blue: b * multiplier.blue, alpha: a * multiplier.alpha)
            case .luminanceToAlpha:
                // A luminance mask has black RGB. Multiplying the source
                // alpha retains transparent texels and geometric coverage.
                let luminance: Float = 0.2126 * r + 0.7152 * g + 0.0722 * b
                color = Color(red: 0, green: 0, blue: 0, alpha: a * luminance)
            }
            color = clamped(color)
        }
        return color
    }

    static func clamped(_ color: Color) -> Color {
        Color(
            red: GPUISceneValue.clamped(color.red, lower: 0, upper: 1),
            green: GPUISceneValue.clamped(color.green, lower: 0, upper: 1),
            blue: GPUISceneValue.clamped(color.blue, lower: 0, upper: 1),
            alpha: GPUISceneValue.clamped(color.alpha, lower: 0, upper: 1))
    }
}

/// How a scene-backed image obtains its initial pixels and composites its result.
public enum GPUISceneImageRenderPassInput: Equatable, Sendable {
    /// Clear to the child scene's color and composite the result source-over.
    case independent
    /// Copy the current enclosing target at this image occurrence, then replace
    /// destination coverage with the composed result, including its alpha.
    case currentTarget
    /// Read the current enclosing target while drawing foreground color and
    /// replacement coverage into separate transparent targets. Content blur
    /// filters those targets, never the untouched enclosing backdrop.
    case isolatedBackdrop
}

/// A renderer-neutral image source drawn from another scene. The image ID
/// belongs to its enclosing scene; the child owns its own resource namespace.
/// Backends resolve the source at the ImagePrimitive's presentation position.
/// This is an offscreen pass, not a pre-rasterized CPU bitmap.
public struct GPUISceneImageRenderPass: Equatable, Sendable {
    public var textureID: Int32
    public var scene: GPUIScene
    public var size: IntSize
    public var colorEffects: [SceneColorEffect]
    public var input: GPUISceneImageRenderPassInput
    public var contentBlurRadius: Int32

    public init(
        textureID: Int32, scene: GPUIScene, size: IntSize, colorEffects: [SceneColorEffect] = [],
        input: GPUISceneImageRenderPassInput = .independent, contentBlurRadius: Int32 = 0
    ) {
        self.textureID = textureID
        self.scene = scene
        self.size = size
        self.colorEffects = colorEffects.map(\.sanitized)
        self.input = input
        self.contentBlurRadius = contentBlurRadius
    }

    /// Checked before allocation by both renderers. Invalid sources remain
    /// in the scene for validation to report, rather than losing the effect.
    public var hasValidExtent: Bool {
        size.width > 0 && size.height > 0
            && Int(size.width) <= GPUISceneLimits.maxSurfaceDimension
            && Int(size.height) <= GPUISceneLimits.maxSurfaceDimension
            && Int64(size.width) * Int64(size.height) <= Int64(GPUISceneLimits.maxImageRenderPassPixels)
    }

    /// Straight-color post-filters cannot preserve RGB above alpha. Ordinary
    /// additive composition remains representable, but reachable isolated
    /// content blur can expose its separate foreground delta outside alpha.
    /// Used premultiplied bitmaps can retain that emission after CPU caching.
    /// Refuse either source explicitly instead of silently clamping it away.
    public var additiveEmissionColorEffectDefect: String? {
        guard input == .independent, !colorEffects.isEmpty else { return nil }
        let analysis = SceneAdditiveEmissionAnalysis.inspect(scene)
        if let defect = analysis.invalidBitmapDefect { return defect }
        if analysis.exceedsLimit {
            return "post-filter source exceeds the additive-emission dependency analysis limit"
        }
        if analysis.escapedEmission {
            return
                "post-filter chains do not support escaped additive emission from isolated content blur or premultiplied bitmap payloads"
        }
        return nil
    }

    /// The same admission runs before CPU allocation and GPU copy. A crop is
    /// relative to its consuming image and immediate target, never a cached
    /// enclosing-frame rectangle. No clamping, resampling or padded reads are
    /// admitted: each child pixel must have exactly one available parent pixel.
    public func currentTargetRegion(for image: ImagePrimitive, parentSize: IntSize) -> SubTextureRegion? {
        guard input == .currentTarget, hasValidExtent,
            currentTargetSourceDefect == nil, currentTargetImageDefect(image) == nil,
            parentSize.width > 0, parentSize.height > 0,
            Int(parentSize.width) <= GPUISceneLimits.maxSurfaceDimension,
            Int(parentSize.height) <= GPUISceneLimits.maxSurfaceDimension,
            image.screenX + image.screenW <= Float(parentSize.width),
            image.screenY + image.screenH <= Float(parentSize.height)
        else { return nil }

        // The image check bounds these exact even integers before conversion.
        return SubTextureRegion(
            originX: Int(image.screenX), originY: Int(image.screenY),
            width: Int(size.width), height: Int(size.height),
            textureWidth: Int(parentSize.width), textureHeight: Int(parentSize.height))
    }

    var currentTargetSourceDefect: String? {
        guard input == .currentTarget else { return nil }
        guard scene.clearColor == .clear else {
            return "current-target sources must declare a transparent clear color"
        }
        guard colorEffects.isEmpty else {
            return "current-target sources do not support post-filter chains"
        }
        return contentBlurRadiusDefect
    }

    /// Checks the mapping without pretending that structural validation knows
    /// the root render target's dimensions. Actual containment is checked above.
    func currentTargetImageDefect(_ image: ImagePrimitive) -> String? {
        guard input == .currentTarget else { return nil }
        // Replacement copies each result pixel back to its original parent
        // pixel. Cap/tile remapping would violate that correspondence, and
        // neither replacement path applies the ordinary image sampler.
        guard image.sampling == .legacy else {
            return "current-target images require legacy sampling without caps or tiling"
        }
        guard image.textureID == textureID,
            image.screenW == Float(size.width), image.screenH == Float(size.height),
            image.uvX == 0, image.uvY == 0, image.uvW == 1, image.uvH == 1,
            image.rotationRadians == 0, image.hasIdentityAffineTransform
        else {
            return "current-target images require a matching source, full UVs and identity 1:1 placement"
        }
        // Preserve the two-by-two derivative phase of the enclosing target.
        let limit = Float(GPUISceneLimits.maxSurfaceDimension)
        guard image.screenX.isFinite, image.screenY.isFinite,
            image.screenX >= 0, image.screenY >= 0,
            image.screenX + image.screenW <= limit, image.screenY + image.screenH <= limit,
            image.screenX.truncatingRemainder(dividingBy: 2) == 0,
            image.screenY.truncatingRemainder(dividingBy: 2) == 0
        else {
            return "current-target images require bounded nonnegative even pixel origins"
        }
        return nil
    }
}

/// A cumulative budget for scene-backed image sources. Structural walks
/// charge each declared source in each child namespace; execution charges
/// each actual realization before allocating it. Reusing an independent
/// resolved CPU image spends nothing. Current-target sources realize and
/// spend again at every occurrence on both backends.
/// Ordinary sources account source pixels, not filter outputs or total process
/// memory. Backdrop isolation also reserves its bounded pass-local scratch
/// planes, including nested current-target sources that return coverage.
public struct GPUISceneImageRenderPassBudget: Sendable {
    public private(set) var remainingPasses: Int
    public private(set) var remainingPixels: Int64

    public init(
        maxPasses: Int = GPUISceneLimits.maxImageRenderPassCount,
        maxPixels: Int64 = Int64(GPUISceneLimits.maxImageRenderPassTotalPixels)
    ) {
        remainingPasses = min(max(0, maxPasses), GPUISceneLimits.maxImageRenderPassCount)
        remainingPixels = min(max(0, maxPixels), Int64(GPUISceneLimits.maxImageRenderPassTotalPixels))
    }

    /// Invalid or over-budget sources leave both counters unchanged. Callers
    /// report the rejection rather than allocating or silently dropping it.
    public mutating func consume(size: IntSize) -> Bool {
        guard size.width > 0, size.height > 0,
            Int(size.width) <= GPUISceneLimits.maxSurfaceDimension,
            Int(size.height) <= GPUISceneLimits.maxSurfaceDimension
        else { return false }
        let pixels = Int64(size.width) * Int64(size.height)
        guard pixels <= Int64(GPUISceneLimits.maxImageRenderPassPixels),
            remainingPasses > 0, pixels <= remainingPixels
        else { return false }
        remainingPasses -= 1
        remainingPixels -= pixels
        return true
    }

    /// Reserve the dependent pass's color, coverage and bounded scratch planes
    /// before any allocation. Independent children reset the isolation context;
    /// a current-target child inside isolation must return a color/coverage pair.
    /// Every actual dependent occurrence pays again, even for a repeated ID.
    public mutating func consume(
        _ pass: GPUISceneImageRenderPass, inBackdropIsolation: Bool = false
    ) -> Bool {
        guard pass.input == .isolatedBackdrop || (pass.input == .currentTarget && inBackdropIsolation) else {
            return consume(size: pass.size)
        }
        guard pass.hasValidExtent else { return false }
        let pixels = Int64(pass.size.width) * Int64(pass.size.height)
        let (reservedPixels, overflow) = pixels.multipliedReportingOverflow(
            by: Int64(GPUISceneBackdropIsolationLimits.scratchPlaneCount))
        guard !overflow, remainingPasses > 0, reservedPixels <= remainingPixels else { return false }
        remainingPasses -= 1
        remainingPixels -= reservedPixels
        return true
    }
}
