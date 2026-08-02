import Foundation
import SwiftWindowsCore
import Synchronization

// MARK: - Content versions

/// One process-wide monotonic source for render-resource content versions.
///
/// Every atlas snapshot and every bitmap buffer draws its identity from
/// here, so a version identifies content across *producers*, not just
/// within one. That is what lets a consumer cache on the version alone: a
/// renderer holding "uploaded version 41" cannot be fooled by a second
/// atlas that reached 41 on a counter of its own — which is exactly the
/// shape of the multi-window bug this protocol exists to close.
public enum RenderContentVersion {
    private static let counter = Atomic<UInt64>(0)

    /// The next version. Never returns 0, so 0 stays available as "nothing
    /// has been produced yet" / "nothing has been uploaded yet".
    public static func next() -> UInt64 {
        counter.wrappingAdd(1, ordering: .relaxed).newValue
    }
}

// MARK: - Atlas update protocol

/// What changed in an atlas since the version a consumer already holds.
///
/// This replaces an `Optional<GlyphAtlasRegion>` that carried three
/// meanings at once — `nil` meant "upload everything", a zero-size rect
/// meant "nothing changed", a real rect meant "upload this much" — and
/// whose middle meaning the producer and the D3D11 consumer read in
/// opposite directions, so every frame containing text re-uploaded the
/// whole 2048×2048×4 = 16 MiB atlas with nothing to show for it.
public enum AtlasUpdate: Equatable, Sendable {
    /// Nothing was written since the last snapshot. A consumer already at
    /// `contentVersion` has nothing to do; one at any other version still
    /// has to take the full upload, because "unchanged" is a claim about
    /// the previous snapshot, not about that consumer's texture.
    case unchanged

    /// Only `region` differs from the pixels as they stood at `since`.
    ///
    /// The base version is part of the claim, not decoration: a consumer
    /// whose texture sits at any other version must not apply the region,
    /// because the writes it missed are not in it. Two windows share one
    /// process-wide glyph atlas and consume its dirty region independently,
    /// so "the region since *someone's* last read" is never enough.
    case region(GlyphAtlasRegion, since: UInt64)

    /// No incremental claim at all — a fresh atlas, a clear, a resize.
    /// Upload everything regardless of what the consumer holds.
    case full
}

/// What a consumer's atlas texture currently holds.
///
/// `isInitialized` is tracked explicitly and never inferred from `size`: a
/// freshly created texture of exactly the right dimensions still holds
/// undefined texels, and inferring "initialized" from matching dimensions
/// is what let a partial upload land in a brand-new texture and flash a
/// frame of garbage text whenever a second window opened against a warm
/// atlas.
public struct AtlasTextureState: Equatable, Sendable {
    /// True once a full upload has landed in this texture.
    public var isInitialized: Bool
    /// The snapshot version whose pixels the texture holds. Meaningless
    /// while `isInitialized` is false.
    public var uploadedVersion: UInt64
    /// The texture's allocated size.
    public var size: IntSize

    public init(isInitialized: Bool = false, uploadedVersion: UInt64 = 0, size: IntSize = .zero) {
        self.isInitialized = isInitialized
        self.uploadedVersion = uploadedVersion
        self.size = size
    }

    /// No texture, or a texture whose contents cannot be relied on.
    public static let uninitialized = AtlasTextureState()
}

/// What a consumer has to do this frame to be current with a snapshot.
public enum AtlasUploadDecision: Equatable, Sendable {
    /// The texture already holds this snapshot's pixels.
    case skip
    /// Upload this rect only. Always inside the atlas rect.
    case region(GlyphAtlasRegion)
    /// Upload every texel.
    case full
}

extension GlyphAtlasSnapshot {
    /// `region` clamped into the atlas rect, or `nil` when nothing of it
    /// lands inside.
    ///
    /// Producer-supplied regions are unvalidated: a negative origin traps
    /// at `UINT(_:)` on the D3D11 upload path and a region past the atlas
    /// edge is a heap over-read. A region that clamps to nothing degrades
    /// to a full upload rather than to a skip — uploading more than needed
    /// is wasteful, uploading less than needed ships undefined texels.
    public func clampedRegion(_ region: GlyphAtlasRegion) -> GlyphAtlasRegion? {
        guard width > 0, height > 0 else { return nil }
        let x0 = max(0, min(region.x, width))
        let y0 = max(0, min(region.y, height))
        let x1 = max(x0, min(region.x &+ max(0, region.width), width))
        let y1 = max(y0, min(region.y &+ max(0, region.height), height))
        guard x1 > x0, y1 > y0 else { return nil }
        return GlyphAtlasRegion(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// What a texture in `state` has to upload to be current with this
    /// snapshot. The whole protocol is this one function; both backends
    /// and every test go through it rather than re-deriving the rules.
    public func uploadDecision(for state: AtlasTextureState) -> AtlasUploadDecision {
        // An uninitialized or differently-sized texture holds nothing this
        // snapshot can be incremental against.
        guard state.isInitialized, state.size.width == width, state.size.height == height else {
            return .full
        }

        switch update {
        case .full:
            return .full
        case .unchanged:
            return state.uploadedVersion == contentVersion ? .skip : .full
        case .region(let region, let baseVersion):
            if state.uploadedVersion == contentVersion {
                return .skip
            }
            guard state.uploadedVersion == baseVersion, let clamped = clampedRegion(region) else {
                return .full
            }
            return .region(clamped)
        }
    }

    /// The state a texture reaches once an upload for this snapshot has
    /// landed. A `skip` leaves the consumer's state alone; anything
    /// uploaded advances it to this version and marks the texture
    /// initialized.
    public var uploadedState: AtlasTextureState {
        AtlasTextureState(
            isInitialized: true,
            uploadedVersion: contentVersion,
            size: IntSize(width: width, height: height)
        )
    }
}
