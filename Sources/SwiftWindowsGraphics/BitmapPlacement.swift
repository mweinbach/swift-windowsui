import Foundation
import SwiftWindowsCore

/// How a native frame presenter places a bitmap's pixels. This is independent
/// of the image sampler: a legacy full-image sampler can still stretch into an
/// authored destination, and a cached or native-rasterized source can too.
public enum BitmapPlacement: Equatable, Sendable {
    /// The entire source occupies the command's logical destination rectangle.
    /// Display scale transforms that rectangle without replacing its extent.
    case destinationRect
    /// The source is already rasterized for this destination's display scale.
    /// Native frame presenters round the scaled origin and blit its physical
    /// pixel dimensions. The CPU frame preview keeps the logical command rect.
    /// Only canonical legacy sampling can accompany a completed raster.
    case devicePixelRaster
}

/// A placement refusal is not a sampler phase or source-dimension failure.
public enum BitmapPlacementFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case devicePixelRasterRequiresCanonicalLegacySampling
    case nonfiniteDestinationGeometry
    case unrepresentableDestinationGeometry

    public var description: String {
        switch self {
        case .devicePixelRasterRequiresCanonicalLegacySampling:
            return "devicePixelRaster placement requires canonical legacy sampling"
        case .nonfiniteDestinationGeometry:
            return "bitmap destination geometry is nonfinite"
        case .unrepresentableDestinationGeometry:
            return "bitmap destination geometry cannot be represented by the renderer"
        }
    }

    /// A representability check, not the cap/tile coordinate or phase budget.
    /// Ordinary finite subpixel and oversized legacy destinations remain valid
    /// while their coordinates, extents, and endpoints can be sent as Floats.
    package static func validatingDestination(_ rect: Rect) -> BitmapPlacementFailure? {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
            rect.maxX.isFinite, rect.maxY.isFinite
        else { return .nonfiniteDestinationGeometry }
        let x = Float(rect.minX)
        let y = Float(rect.minY)
        let width = Float(rect.width)
        let height = Float(rect.height)
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
            Float(rect.maxX).isFinite, Float(rect.maxY).isFinite,
            (x + width).isFinite, (y + height).isFinite,
            rect.width == 0 || width != 0, rect.height == 0 || height != 0
        else { return .unrepresentableDestinationGeometry }
        return nil
    }
}

/// Identifies a rejected bitmap in the original frame, before path degradation
/// or any removal changes command indices. Contains no source pixels or paths.
public struct FrameBitmapPlacementFailure: Error, Equatable, Sendable, CustomStringConvertible {
    public let commandIndex: Int
    public let reason: BitmapPlacementFailure

    public init(commandIndex: Int, reason: BitmapPlacementFailure) {
        self.commandIndex = commandIndex
        self.reason = reason
    }

    public var description: String {
        "RenderFrame command \(commandIndex) rejected: \(reason)."
    }
}

/// An explicit partial-frame result. Rejected commands have no paint or image
/// resources; valid siblings keep their original order. The input frame remains
/// unchanged, and the typed failures retain its command indices.
public struct FrameBitmapPlacementAdmission: Equatable, Sendable {
    public let frame: RenderFrame
    public let failures: [FrameBitmapPlacementFailure]

    /// Reports once at a consuming boundary. A synchronous observer can retain
    /// typed failures; callers without one receive an unconditional stderr
    /// diagnostic in both debug and release builds. No global UI state is used.
    public func reportFailures(to observer: ((FrameBitmapPlacementFailure) -> Void)? = nil) {
        for failure in failures {
            if let observer {
                observer(failure)
            } else {
                FileHandle.standardError.write(Data("[SwiftWindowsGraphics] \(failure)\n".utf8))
            }
        }
    }
}

extension DrawBitmapCommand {
    public var placementFailure: BitmapPlacementFailure? {
        if placement == .devicePixelRaster, sampling != .legacy {
            return .devicePixelRasterRequiresCanonicalLegacySampling
        }
        return BitmapPlacementFailure.validatingDestination(rect)
    }
}

extension RenderFrame {
    /// Validates placement before any bitmap resource is registered or uploaded.
    /// This does not reinterpret the sampler or impose cap/tile limits on
    /// ordinary destination-rectangle images. A valid frame keeps its command
    /// array without allocating another array for the common path.
    public func admittingBitmapPlacements() -> FrameBitmapPlacementAdmission {
        admittingBitmapPlacements(validatingDestination: { _ in nil })
    }

    /// Native consumers add validation after their actual coordinate transform,
    /// retaining the same original indices and reporting boundary as the bridge.
    package func admittingBitmapPlacements(
        validatingDestination: (DrawBitmapCommand) -> BitmapPlacementFailure?
    ) -> FrameBitmapPlacementAdmission {
        var failures: [FrameBitmapPlacementFailure] = []
        for (index, command) in commands.enumerated() {
            guard case .drawBitmap(let bitmap) = command else { continue }
            guard let reason = bitmap.placementFailure ?? validatingDestination(bitmap) else { continue }
            failures.append(FrameBitmapPlacementFailure(commandIndex: index, reason: reason))
        }
        guard !failures.isEmpty else {
            return FrameBitmapPlacementAdmission(frame: self, failures: [])
        }

        var accepted: [RenderCommand] = []
        accepted.reserveCapacity(commands.count - failures.count)
        var failureIndex = 0
        for (index, command) in commands.enumerated() {
            if failureIndex < failures.count, failures[failureIndex].commandIndex == index {
                failureIndex += 1
            } else {
                accepted.append(command)
            }
        }
        return FrameBitmapPlacementAdmission(
            frame: RenderFrame(clearColor: clearColor, commands: accepted), failures: failures)
    }
}
