import SwiftWindowsCore

/// Pixel-plane reservation for a backdrop-dependent isolation. This includes
/// the parent copy, foreground, coverage, composed material input and bounded
/// filter scratch. It is conservative rather than a total renderer-memory cap.
public enum GPUISceneBackdropIsolationLimits {
    public static let scratchPlaneCount = 8
}

/// An exact pixel mapping between an isolation buffer and its immediate parent.
/// The buffer may extend outside the parent to retain a transparent foreground
/// blur halo. `parentCopyRegion` identifies the physical parent pixels to copy.
/// Backends clamp backdrop D to that copy (or use zero when none exists), then
/// form S = F + (1 - C)D from foreground F and coverage C across the full canvas.
/// Material filters sample S; nested children read their fully defined immediate
/// parent S without inheriting a narrower grandparent copy region.
public struct GPUISceneBackdropIsolationMapping: Equatable, Sendable {
    public let originX: Int
    public let originY: Int
    public let size: IntSize
    public let parentCopyRegion: SubTextureRegion?
    /// Destination of the parent copy in the child buffer; zero for no overlap.
    public let childOffsetX: Int
    public let childOffsetY: Int

    init(originX: Int, originY: Int, size: IntSize, parentSize: IntSize) {
        self.originX = originX
        self.originY = originY
        self.size = size

        // The descriptor and target checks bound every operand before this
        // initializer runs. Intersect before constructing the clamping region
        // type so it cannot silently change the requested pixel correspondence.
        let left = max(0, originX)
        let top = max(0, originY)
        let right = min(Int(parentSize.width), originX + Int(size.width))
        let bottom = min(Int(parentSize.height), originY + Int(size.height))
        if left < right, top < bottom {
            parentCopyRegion = SubTextureRegion(
                originX: left, originY: top, width: right - left, height: bottom - top,
                textureWidth: Int(parentSize.width), textureHeight: Int(parentSize.height))
            childOffsetX = left - originX
            childOffsetY = top - originY
        } else {
            parentCopyRegion = nil
            childOffsetX = 0
            childOffsetY = 0
        }
    }

    /// The physical parent copy in child coordinates. Only backdrop D clamps
    /// to this region; the composed material input S is defined across the full
    /// child canvas and uses the material's normal scan window.
    public var validChildRegion: SubTextureRegion? {
        guard let parentCopyRegion else { return nil }
        return SubTextureRegion(
            originX: childOffsetX, originY: childOffsetY,
            width: parentCopyRegion.width, height: parentCopyRegion.height,
            textureWidth: Int(size.width), textureHeight: Int(size.height))
    }
}

extension GPUISceneImageRenderPass {
    /// Material-dependent isolation starts transparent and carries foreground
    /// separately from replacement coverage. General post-filter chains do not
    /// have the same coverage algebra and are outside this contract.
    public var isolatedBackdropSourceDefect: String? {
        guard input == .isolatedBackdrop else { return nil }
        guard scene.clearColor == .clear else {
            return "isolated-backdrop sources must declare a transparent clear color"
        }
        guard colorEffects.isEmpty else {
            return "isolated-backdrop sources do not support post-filter chains"
        }
        return contentBlurRadiusDefect
    }

    var contentBlurRadiusDefect: String? {
        if input == .isolatedBackdrop {
            guard contentBlurRadius >= 0, contentBlurRadius <= Int32(GPUISceneLimits.maxBlurRadius) else {
                return "isolated-backdrop content blur radius must be in 0...\(Int(GPUISceneLimits.maxBlurRadius))"
            }
        } else if contentBlurRadius != 0 {
            return "content blur radius requires isolated-backdrop input"
        }
        return nil
    }

    /// Structural validation knows placement, not the actual parent's extent.
    /// Negative even origins allow a transparent halo beyond viewport edges
    /// while retaining the parent's two-by-two derivative phase.
    public func isolatedBackdropImageDefect(_ image: ImagePrimitive) -> String? {
        guard input == .isolatedBackdrop else { return nil }
        guard image.sampling == .legacy else {
            return "isolated-backdrop images require legacy sampling without caps or tiling"
        }
        guard textureID >= 0, image.textureID == textureID,
            image.screenW == Float(size.width), image.screenH == Float(size.height),
            image.uvX == 0, image.uvY == 0, image.uvW == 1, image.uvH == 1,
            image.rotationRadians == 0, image.hasIdentityAffineTransform
        else {
            return "isolated-backdrop images require a matching source, full UVs and identity 1:1 placement"
        }
        let limit = Float(GPUISceneLimits.maxSurfaceDimension)
        guard image.screenX.isFinite, image.screenY.isFinite,
            image.screenX >= -limit, image.screenY >= -limit,
            image.screenX <= limit, image.screenY <= limit,
            image.screenX.truncatingRemainder(dividingBy: 2) == 0,
            image.screenY.truncatingRemainder(dividingBy: 2) == 0
        else {
            return "isolated-backdrop images require bounded even pixel origins"
        }
        return nil
    }

    /// Called at each consuming image occurrence before allocating or copying.
    /// No overlap means zero backdrop D, not an invalid placement. The returned
    /// intersection bounds the physical copy and D-only clamp, not the composed
    /// material scan window. Each mapping uses its actual immediate parent.
    public func isolatedBackdropMapping(
        for image: ImagePrimitive, parentSize: IntSize
    ) -> GPUISceneBackdropIsolationMapping? {
        guard input == .isolatedBackdrop, hasValidExtent,
            isolatedBackdropSourceDefect == nil, isolatedBackdropImageDefect(image) == nil,
            parentSize.width > 0, parentSize.height > 0,
            Int(parentSize.width) <= GPUISceneLimits.maxSurfaceDimension,
            Int(parentSize.height) <= GPUISceneLimits.maxSurfaceDimension
        else { return nil }
        return GPUISceneBackdropIsolationMapping(
            originX: Int(image.screenX), originY: Int(image.screenY), size: size, parentSize: parentSize)
    }
}
