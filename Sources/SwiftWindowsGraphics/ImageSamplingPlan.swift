import SwiftWindowsCore

/// Bitmap resizing policies understood by the renderer-neutral image sampler.
public enum ImageSamplingMode: Equatable, Sendable {
    case stretch
    case tile
}

/// An unsupported plan is diagnosed rather than changed into a different image.
public enum ImageSamplingFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidSourceSize
    case invalidSourceScale
    case invalidDestinationSize
    case nonfiniteCapInsets
    case negativeCapInsets
    case fractionalCapInsets
    case sourceCenterNotPositive
    case destinationCenterNotPositive
    case phaseLimitExceeded
    case unrepresentableDescriptor
    case unsupportedSourceUV
    case invalidDescriptor(String)

    public var description: String {
        switch self {
        case .invalidSourceSize:
            return "bitmap sampling requires positive source dimensions within the source-size limit"
        case .invalidSourceScale:
            return "bitmap sampling requires finite positive source pixels per logical point"
        case .invalidDestinationSize:
            return "bitmap sampling requires finite positive local destination dimensions"
        case .nonfiniteCapInsets:
            return "bitmap cap insets must be finite"
        case .negativeCapInsets:
            return "negative bitmap cap insets are not supported"
        case .fractionalCapInsets:
            return "bitmap cap insets must be aligned to whole source texels"
        case .sourceCenterNotPositive:
            return "bitmap cap insets must leave a positive source center on both axes"
        case .destinationCenterNotPositive:
            return "bitmap cap insets must leave a positive destination center on both axes"
        case .phaseLimitExceeded:
            return "bitmap tile phase exceeds the 4096 source-texel or repeat-count limit"
        case .unrepresentableDescriptor:
            return "bitmap sampling partitions cannot be represented by the scene descriptor"
        case .unsupportedSourceUV:
            return "capped and tiled bitmap sampling currently requires the full source UV rectangle"
        case .invalidDescriptor(let reason):
            return reason
        }
    }
}

/// Fixed-size sampling metadata. Fractions refer to the untransformed local
/// destination and full source image; display scale does not change tile count.
///
/// This is an explicitly bounded Windows policy, not a native parity claim.
/// Source caps are whole texels, centers are positive, and leading/trailing
/// mean the physical left/right edges. Already-composited images use `legacy`.
@frozen
public struct ImageSamplingDescriptor: Equatable, Sendable {
    public var sourceCapLeft: Float
    public var sourceCapTop: Float
    public var sourceCapRight: Float
    public var sourceCapBottom: Float
    public var destinationCapLeft: Float
    public var destinationCapTop: Float
    public var destinationCapRight: Float
    public var destinationCapBottom: Float
    public var centerRepeatX: Float
    public var centerRepeatY: Float
    /// 0: original full-image sampler; 1: capped stretch; 2: capped/full tile.
    public var samplingKind: Int32
    public var samplingPadding: Float

    public init(
        sourceCapLeft: Float = 0, sourceCapTop: Float = 0,
        sourceCapRight: Float = 0, sourceCapBottom: Float = 0,
        destinationCapLeft: Float = 0, destinationCapTop: Float = 0,
        destinationCapRight: Float = 0, destinationCapBottom: Float = 0,
        centerRepeatX: Float = 1, centerRepeatY: Float = 1,
        samplingKind: Int32 = 0, samplingPadding: Float = 0
    ) {
        self.sourceCapLeft = sourceCapLeft
        self.sourceCapTop = sourceCapTop
        self.sourceCapRight = sourceCapRight
        self.sourceCapBottom = sourceCapBottom
        self.destinationCapLeft = destinationCapLeft
        self.destinationCapTop = destinationCapTop
        self.destinationCapRight = destinationCapRight
        self.destinationCapBottom = destinationCapBottom
        self.centerRepeatX = centerRepeatX
        self.centerRepeatY = centerRepeatY
        self.samplingKind = samplingKind
        self.samplingPadding = samplingPadding
    }

    public static let legacy = ImageSamplingDescriptor()

    public var isLegacy: Bool { samplingKind == 0 }

    /// New sampling modes cannot clamp or replace their destination without
    /// changing cap sizes or tile phase. Validate again after a frame consumer
    /// applies display scale, before converting the destination to GPU Floats.
    /// The original sampler retains its existing placement policy.
    public func placementValidationFailure(rect: Rect) -> ImageSamplingFailure? {
        if isLegacy { return nil }
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
            rect.size.width.isFinite, rect.size.height.isFinite,
            rect.size.width > 0, rect.size.height > 0
        else { return .invalidDestinationSize }
        let limit = Double(GPUISceneLimits.maxCoordinate)
        guard abs(rect.origin.x) <= limit, abs(rect.origin.y) <= limit,
            rect.size.width <= limit, rect.size.height <= limit,
            Float(rect.size.width) > 0, Float(rect.size.height) > 0
        else { return .unrepresentableDescriptor }
        return nil
    }

    /// With no source size, validates only the descriptor and UV admission.
    /// Backends must also validate against the actual bound bitmap before
    /// sampling: fractions alone cannot establish source-texel alignment.
    public func validationFailure(
        sourceSize: IntSize? = nil,
        uvX: Float = 0, uvY: Float = 0, uvW: Float = 1, uvH: Float = 1
    ) -> ImageSamplingFailure? {
        if isLegacy {
            return self == .legacy ? nil : .invalidDescriptor("legacy image sampling fields must be canonical")
        }
        guard samplingKind == 1 || samplingKind == 2 else {
            return .invalidDescriptor("unknown image sampling kind")
        }
        guard uvX == 0, uvY == 0, uvW == 1, uvH == 1 else { return .unsupportedSourceUV }
        let caps = [
            sourceCapLeft, sourceCapTop, sourceCapRight, sourceCapBottom,
            destinationCapLeft, destinationCapTop, destinationCapRight, destinationCapBottom,
        ]
        guard caps.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 1 }),
            centerRepeatX.isFinite, centerRepeatY.isFinite,
            centerRepeatX > 0, centerRepeatY > 0, samplingPadding == 0
        else { return .unrepresentableDescriptor }
        guard 1 - sourceCapLeft - sourceCapRight > 0,
            1 - sourceCapTop - sourceCapBottom > 0,
            1 - destinationCapLeft - destinationCapRight > 0,
            1 - destinationCapTop - destinationCapBottom > 0
        else { return .unrepresentableDescriptor }
        guard (sourceCapLeft == 0) == (destinationCapLeft == 0),
            (sourceCapTop == 0) == (destinationCapTop == 0),
            (sourceCapRight == 0) == (destinationCapRight == 0),
            (sourceCapBottom == 0) == (destinationCapBottom == 0)
        else { return .invalidDescriptor("source and destination cap bands must correspond") }
        if samplingKind == 1 {
            guard centerRepeatX == 1, centerRepeatY == 1,
                sourceCapLeft + sourceCapTop + sourceCapRight + sourceCapBottom > 0
            else { return .invalidDescriptor("capped stretch requires caps and canonical repeat counts") }
        } else if !ImageSamplingPlan.phaseIsRepresentable(centerRepeatX)
            || !ImageSamplingPlan.phaseIsRepresentable(centerRepeatY)
        {
            return .phaseLimitExceeded
        }
        guard let sourceSize else { return nil }
        guard ImageSamplingPlan.admitsSourceSize(sourceSize) else { return .invalidSourceSize }
        guard let left = sourceCapCount(sourceCapLeft, length: Int(sourceSize.width)),
            let right = sourceCapCount(sourceCapRight, length: Int(sourceSize.width)),
            let top = sourceCapCount(sourceCapTop, length: Int(sourceSize.height)),
            let bottom = sourceCapCount(sourceCapBottom, length: Int(sourceSize.height))
        else { return .fractionalCapInsets }
        let centerWidth = Int(sourceSize.width) - left - right
        let centerHeight = Int(sourceSize.height) - top - bottom
        guard centerWidth > 0, centerHeight > 0 else { return .sourceCenterNotPositive }
        if samplingKind == 2 {
            guard ImageSamplingPlan.phaseIsRepresentable(centerRepeatX * Float(centerWidth)),
                ImageSamplingPlan.phaseIsRepresentable(centerRepeatY * Float(centerHeight))
            else { return .phaseLimitExceeded }
        }
        return nil
    }
}

public enum ImageSamplingPlan {
    /// The tile coordinate is computed in Float by both samplers. Bounding
    /// phase in source-texel units (not only cycles) prevents large repeat
    /// counts from discarding the fractional texel position. This interim
    /// admission limit is independent of the visible clip or tile count.
    public static let maximumTilePhase: Float = 4_096

    public static func resolve(
        sourceSize: IntSize, destinationSize: Size, capInsets: EdgeInsets, mode: ImageSamplingMode,
        sourceScale: Double = 1
    ) -> Result<ImageSamplingDescriptor, ImageSamplingFailure> {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return .failure(.invalidSourceSize) }
        guard destinationSize.width.isFinite, destinationSize.height.isFinite,
            destinationSize.width > 0, destinationSize.height > 0
        else { return .failure(.invalidDestinationSize) }
        // Preserve the original default sampler, including its source sizes,
        // UV handling, and existing geometry admission outside this helper.
        // Its descriptor does not depend on source density; do not multiply
        // a valid point destination into overflow/underflow just to return it.
        if mode == .stretch && capInsets == .zero { return .success(.legacy) }
        guard sourceScale.isFinite, sourceScale > 0 else { return .failure(.invalidSourceScale) }
        guard admitsSourceSize(sourceSize) else { return .failure(.invalidSourceSize) }
        let caps = [capInsets.leading, capInsets.top, capInsets.trailing, capInsets.bottom]
        guard caps.allSatisfy(\.isFinite) else { return .failure(.nonfiniteCapInsets) }
        guard caps.allSatisfy({ $0 >= 0 }) else { return .failure(.negativeCapInsets) }
        let sourceCaps = caps.map { $0 * sourceScale }
        guard sourceCaps.allSatisfy(\.isFinite),
            zip(caps, sourceCaps).allSatisfy({ ($0.0 == 0) == ($0.1 == 0) })
        else { return .failure(.unrepresentableDescriptor) }
        guard sourceCaps.allSatisfy({ $0 == $0.rounded() }) else { return .failure(.fractionalCapInsets) }
        let width = Double(sourceSize.width)
        let height = Double(sourceSize.height)
        let centerWidth = width - sourceCaps[0] - sourceCaps[2]
        let centerHeight = height - sourceCaps[1] - sourceCaps[3]
        guard centerWidth > 0, centerHeight > 0 else { return .failure(.sourceCenterNotPositive) }
        let targetWidth = destinationSize.width - capInsets.leading - capInsets.trailing
        let targetHeight = destinationSize.height - capInsets.top - capInsets.bottom
        guard targetWidth > 0, targetHeight > 0 else { return .failure(.destinationCenterNotPositive) }
        let repeatX: Float
        let repeatY: Float
        if mode == .tile {
            // Only sampling distances use texels. Placement and destination
            // cap fractions below continue to use the actual logical points.
            let targetTexelWidth = targetWidth * sourceScale
            let targetTexelHeight = targetHeight * sourceScale
            guard targetTexelWidth <= Double(maximumTilePhase), targetTexelHeight <= Double(maximumTilePhase) else {
                return .failure(.phaseLimitExceeded)
            }
            repeatX = Float(targetTexelWidth / centerWidth)
            repeatY = Float(targetTexelHeight / centerHeight)
        } else {
            repeatX = 1
            repeatY = 1
        }
        let sampling = ImageSamplingDescriptor(
            sourceCapLeft: Float(sourceCaps[0] / width), sourceCapTop: Float(sourceCaps[1] / height),
            sourceCapRight: Float(sourceCaps[2] / width), sourceCapBottom: Float(sourceCaps[3] / height),
            destinationCapLeft: Float(capInsets.leading / destinationSize.width),
            destinationCapTop: Float(capInsets.top / destinationSize.height),
            destinationCapRight: Float(capInsets.trailing / destinationSize.width),
            destinationCapBottom: Float(capInsets.bottom / destinationSize.height),
            centerRepeatX: repeatX, centerRepeatY: repeatY,
            samplingKind: mode == .tile ? 2 : 1
        )
        if let failure = sampling.validationFailure(sourceSize: sourceSize) { return .failure(failure) }
        if let failure = sampling.placementValidationFailure(
            rect: Rect(x: 0, y: 0, width: destinationSize.width, height: destinationSize.height))
        {
            return .failure(failure)
        }
        return .success(sampling)
    }

    fileprivate static func admitsSourceSize(_ size: IntSize) -> Bool {
        size.width > 0 && size.height > 0
            && Int(size.width) <= GPUISceneLimits.maxSurfaceDimension
            && Int(size.height) <= GPUISceneLimits.maxSurfaceDimension
    }

    fileprivate static func phaseIsRepresentable(_ phase: Float) -> Bool {
        // A ratio rounded into the descriptor can reconstruct the exact limit
        // a ULP above it. This is only representation slack, not a larger
        // logical admission limit for resolve().
        phase.isFinite && phase > 0 && phase <= maximumTilePhase + 2 * maximumTilePhase.ulp
    }
}

/// Recover only whole source bands. Two Float ULPs allow fractions produced
/// from an integer cap to round-trip; arbitrary fractional caps are rejected.
private func sourceCapCount(_ fraction: Float, length: Int) -> Int? {
    let texels = fraction * Float(length)
    let rounded = texels.rounded(.toNearestOrAwayFromZero)
    guard abs(texels - rounded) <= 2 * max(texels.ulp, Float.ulpOfOne) else { return nil }
    let count = Int(rounded)
    guard count >= 0, count < length, (count == 0) == (fraction == 0) else { return nil }
    return count
}

struct ImageSamplingAxisTap: Equatable {
    let low: Int
    let high: Int
    let fraction: Double
}

/// Prepared once per draw. The two independent axes represent nine regions
/// without allocating any regions, tiles, or destination-sized bitmaps.
struct ImageSamplingKernel {
    private let x: ImageSamplingAxis
    private let y: ImageSamplingAxis

    init?(sampling: ImageSamplingDescriptor, sourceSize: IntSize) {
        guard !sampling.isLegacy, sampling.validationFailure(sourceSize: sourceSize) == nil else { return nil }
        x = ImageSamplingAxis(
            length: Int(sourceSize.width), sourceLeading: sampling.sourceCapLeft,
            sourceTrailing: sampling.sourceCapRight,
            destinationLeading: sampling.destinationCapLeft, destinationTrailing: sampling.destinationCapRight,
            repeats: sampling.centerRepeatX, tiled: sampling.samplingKind == 2)
        y = ImageSamplingAxis(
            length: Int(sourceSize.height), sourceLeading: sampling.sourceCapTop,
            sourceTrailing: sampling.sourceCapBottom,
            destinationLeading: sampling.destinationCapTop, destinationTrailing: sampling.destinationCapBottom,
            repeats: sampling.centerRepeatY, tiled: sampling.samplingKind == 2)
    }

    func taps(unitX: Float, unitY: Float) -> (x: ImageSamplingAxisTap, y: ImageSamplingAxisTap) {
        (x.tap(unitX), y.tap(unitY))
    }
}

private struct ImageSamplingAxis {
    let length: Int
    let leading: Int
    let trailing: Int
    let destinationLeading: Float
    let destinationTrailing: Float
    let repeats: Float
    let tiled: Bool

    init(
        length: Int, sourceLeading: Float, sourceTrailing: Float,
        destinationLeading: Float, destinationTrailing: Float, repeats: Float, tiled: Bool
    ) {
        self.length = length
        leading = Int((sourceLeading * Float(length)).rounded(.toNearestOrAwayFromZero))
        trailing = Int((sourceTrailing * Float(length)).rounded(.toNearestOrAwayFromZero))
        self.destinationLeading = destinationLeading
        self.destinationTrailing = destinationTrailing
        self.repeats = repeats
        self.tiled = tiled
    }

    func tap(_ unit: Float) -> ImageSamplingAxisTap {
        let p = unit.isFinite ? min(max(unit, 0), 1) : 0
        let start: Int
        let count: Int
        let t: Float
        let wraps: Bool
        if destinationLeading > 0 && p < destinationLeading {
            start = 0
            count = leading
            t = p / destinationLeading
            wraps = false
        } else if destinationTrailing > 0 && p >= 1 - destinationTrailing {
            start = length - trailing
            count = trailing
            t = (p - (1 - destinationTrailing)) / destinationTrailing
            wraps = false
        } else {
            start = leading
            count = length - leading - trailing
            let centerUnit = (p - destinationLeading) / (1 - destinationLeading - destinationTrailing)
            let phase = centerUnit * repeats
            t = tiled ? phase - phase.rounded(.down) : centerUnit
            wraps = tiled
        }
        let texel = t * Float(count) - 0.5
        let floor = texel.rounded(.down)
        let low = Int(floor)
        let lowIndex = wraps ? ((low % count) + count) % count : min(max(low, 0), count - 1)
        let highIndex = wraps ? (((low + 1) % count) + count) % count : min(max(low + 1, 0), count - 1)
        return ImageSamplingAxisTap(low: start + lowIndex, high: start + highIndex, fraction: Double(texel - floor))
    }
}
