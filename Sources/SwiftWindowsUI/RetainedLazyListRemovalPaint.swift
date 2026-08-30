import SwiftWindowsCore
import SwiftWindowsGraphics

/// One completed ordinary paint attempt. The shared holder owns only renderer
/// values; it does not own any node, Canvas source, callback, or view context.
@MainActor
final class RetainedLazyListPaintSnapshot {
    enum Content {
        case scene(GPUIScene)
        case frame(RenderFrame)
    }

    let content: Content
    let identity: PaintSnapshotIdentity
    let surfaceSize: IntSize
    let displayScale: Double

    init(content: Content, identity: PaintSnapshotIdentity, surfaceSize: IntSize, displayScale: Double) {
        self.content = content
        self.identity = identity
        self.surfaceSize = surfaceSize
        self.displayScale = displayScale
    }

    func capture(_ ranges: [Range<Int>]) -> RetainedLazyListPaintSource.CaptureResult {
        switch content {
        case .scene(let scene):
            return RetainedLazyListPaintSource.capture(scene: scene, ranges: ranges, surfaceSize: surfaceSize)
        case .frame(let frame):
            guard let commands = Self.selectedFrameCommands(frame.commands, ranges: ranges) else {
                return .unsupported
            }
            // Lower already-issued renderer commands, not a ViewNode. This
            // cannot run Canvas, layout, lifecycle, or application builders.
            let selected = RenderFrame(clearColor: .clear, commands: commands)
            guard Self.permitsFrameSceneLowering(selected) else { return .unsupported }
            let scene = GPUIScene(
                from: selected,
                surfaceSize: Size(width: Double(surfaceSize.width), height: Double(surfaceSize.height)))
            return RetainedLazyListPaintSource.capture(
                scene: scene, ranges: [0..<scene.paintRecordCount], surfaceSize: surfaceSize)
        }
    }

    /// This bridge is used for completed paint, so a scene lowering that
    /// soft-skips a reserved command or changes a clip is not a valid capture.
    /// It must not make a later live frame lose content while adding a tail.
    static func permitsFrameSceneLowering(_ frame: RenderFrame) -> Bool {
        guard frame.admittingBitmapPlacements().failures.isEmpty else { return false }
        return frame.commands.allSatisfy { command in
            switch command {
            case .drawText, .applyBlur:
                return false
            case .pushClip(let clip):
                guard case .rect(_, let cornerRadius) = clip.shape else { return false }
                return cornerRadius == 0
            case .fillRect, .drawBitmap, .fillPath, .strokePath, .popClip:
                return true
            }
        }
    }

    /// Each selected span starts with the actual surrounding clip stack. A
    /// separate deferred span must neither inherit a sibling's clip nor lose
    /// the clip that was active when its first command was emitted.
    private static func selectedFrameCommands(
        _ commands: [RenderCommand], ranges: [Range<Int>]
    ) -> [RenderCommand]? {
        guard ranges.allSatisfy({ $0.lowerBound >= 0 && $0.upperBound <= commands.count }) else { return nil }
        let ranges = mergedRanges(ranges)
        var result: [RenderCommand] = []
        var clips: [ClipCommand] = []
        var cursor = 0
        for range in ranges {
            while cursor < range.lowerBound {
                switch commands[cursor] {
                case .pushClip(let clip): clips.append(clip)
                case .popClip: if !clips.isEmpty { clips.removeLast() }
                default: break
                }
                cursor += 1
            }
            result.append(contentsOf: clips.map(RenderCommand.pushClip))
            while cursor < range.upperBound {
                let command = commands[cursor]
                result.append(command)
                switch command {
                case .pushClip(let clip): clips.append(clip)
                case .popClip: if !clips.isEmpty { clips.removeLast() }
                default: break
                }
                cursor += 1
            }
            result.append(contentsOf: repeatElement(RenderCommand.popClip, count: clips.count))
        }
        return result
    }

    static func mergedRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) where !range.isEmpty {
            if let last = result.last, last.upperBound >= range.lowerBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }
}

/// A normal paint visit records this small native witness on a managed node.
/// Missing isolated ranges are not empty paint. Revocation clears the witness
/// before cleanup callbacks, so a later attachment cannot inherit old pixels.
@MainActor
struct RetainedLazyListPresentedPaint {
    let attachment: RetainedLazyListAttachmentProof
    let identity: RetainedLazyListViewIdentityProof
    let snapshot: RetainedLazyListPaintSnapshot?
    let ranges: [Range<Int>]
    let pose: RetainedLazyListPaintPose?
    let isUnavailable: Bool

    var isCurrent: Bool { attachment.isCurrent && identity.isCurrent }
}

/// The pose that produced the frozen primitives, not the latest authored
/// values. A removal interrupting insertion starts with these exact pixels.
struct RetainedLazyListPaintPose {
    let opacity: Double
    let transform: Transform2D
    let pivot: Point
    let clip: RuntimeClipShape?
    let displayScale: Double
    let rootOpacityIsInPrimitives: Bool
}

/// The only object kept after managed departure. It is deliberately a value:
/// no node, owner, admission, callback, task, or weak executable reference can
/// be consulted by animation completion, rendering, or host shutdown.
struct RetainedLazyListRemovalPaint {
    let source: RetainedLazyListPaintSource
    private let pose: RetainedLazyListPaintPose
    private let states: [AnimatableProperty: AnimationState]
    private let projectsPrimitiveOpacity: Bool
    private let deadline: Double
    private var timestamp: Double

    init?(
        source: RetainedLazyListPaintSource, pose: RetainedLazyListPaintPose,
        animation: RetainedRemovalTransitionAnimation
    ) {
        guard animation.resolvedAt.isFinite, pose.opacity.isFinite, pose.displayScale.isFinite,
            pose.displayScale > 0, pose.pivot.x.isFinite, pose.pivot.y.isFinite,
            animation.states.values.allSatisfy({
                $0.startValue.isFinite && $0.endValue.isFinite && $0.startTime.isFinite
                    && $0.duration.isFinite && ($0.startTime + $0.duration).isFinite
            })
        else { return nil }

        var states: [AnimatableProperty: AnimationState] = [:]
        for (property, state) in animation.states {
            guard !state.isComplete(at: animation.resolvedAt) else { continue }
            guard let start = Self.value(of: property, pose: pose) else {
                // The frozen primitive contract has no frame/outline/color
                // provenance. Do not silently freeze a still-running tween.
                return nil
            }
            if animation.removalProperties.contains(property) {
                states[property] = AnimationState(
                    startValue: start, endValue: state.endValue, startTime: state.startTime,
                    duration: state.duration, easing: state.easing)
            } else {
                // An existing tween keeps its original easing phase. Restarting
                // it over the remaining duration changes an interrupted view.
                states[property] = state
            }
        }
        guard !states.isEmpty else { return nil }
        func changes(_ property: AnimatableProperty, _ state: AnimationState) -> Bool {
            guard let value = Self.value(of: property, pose: pose) else { return false }
            return state.startValue != value || state.endValue != value
        }
        let movesGeometry = states.contains { property, state in
            property != .opacity && changes(property, state)
        }
        let changesNonTranslationGeometry = states.contains { property, state in
            switch property {
            case .transformScaleX, .transformScaleY, .transformRotation:
                return changes(property, state)
            default:
                return false
            }
        }
        // Current placement lowering can reflow text or change the way it
        // paints corners, strokes and transformed descendants under scale or
        // rotation. One combined source cannot reconstruct that provenance.
        if changesNonTranslationGeometry { return nil }
        if source.input == .isolatedBackdrop, movesGeometry { return nil }
        if source.wasClipped, movesGeometry { return nil }
        if movesGeometry, let clip = pose.clip, clip.rotation != 0 || clip.uniformRadius > 0 { return nil }
        let projectsOpacity = states[.opacity] != nil
        if projectsOpacity {
            guard pose.opacity > 0, pose.opacity <= 1, pose.rootOpacityIsInPrimitives,
                source.sceneApplyingInheritedOpacity(
                    1, permitsInheritedEffectOpacity: true, permitsInheritedBackdropOpacity: true) != nil
            else { return nil }
        }
        let matrix = pose.transform.matrix
        guard [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty].allSatisfy(\.isFinite) else {
            return nil
        }
        // An already collapsed transform has no inverse from which a new
        // affine pose can recover pixels. Opacity-only playback is still exact.
        if movesGeometry, abs(matrix.a * matrix.d - matrix.b * matrix.c) < 1e-12 { return nil }
        self.source = source
        self.pose = pose
        self.states = states
        projectsPrimitiveOpacity = projectsOpacity
        deadline = states.values.map { $0.startTime + $0.duration }.max() ?? animation.resolvedAt
        timestamp = animation.resolvedAt
    }

    var isComplete: Bool { timestamp >= deadline }

    /// Reserve the live graph first, then choose the newest visual tails that
    /// fit both native render-pass limits. The returned values retain their
    /// chronological draw order; omitted tails are complete, not postponed.
    static func fittingSceneBudget(
        _ paints: [RetainedLazyListRemovalPaint],
        liveCost: RetainedLazyListPaintSource.ExecutionCost?,
        surfaceSize: IntSize, displayScale: Double
    ) -> [RetainedLazyListRemovalPaint] {
        guard let liveCost, liveCost.passCount >= 0, liveCost.pixelCount >= 0,
            liveCost.passCount <= GPUISceneLimits.maxImageRenderPassCount,
            liveCost.pixelCount <= Int64(GPUISceneLimits.maxImageRenderPassTotalPixels)
        else { return [] }
        var remainingPasses = GPUISceneLimits.maxImageRenderPassCount - liveCost.passCount
        var remainingPixels = Int64(GPUISceneLimits.maxImageRenderPassTotalPixels) - liveCost.pixelCount
        var selected: [RetainedLazyListRemovalPaint] = []
        for paint in paints.reversed() {
            guard !paint.isComplete, paint.permitsDisplayScale(displayScale), paint.permitsTargetSize(surfaceSize),
                paint.source.executionPassCount <= remainingPasses,
                paint.source.executionPixelCount <= remainingPixels
            else { continue }
            remainingPasses -= paint.source.executionPassCount
            remainingPixels -= paint.source.executionPixelCount
            selected.append(paint)
        }
        return Array(selected.reversed())
    }

    func permitsDisplayScale(_ displayScale: Double) -> Bool {
        displayScale.isFinite && displayScale > 0
            && (source.input != .isolatedBackdrop || displayScale == pose.displayScale)
    }

    func permitsTargetSize(_ targetSize: IntSize) -> Bool {
        targetSize.width > 0 && targetSize.height > 0
            && (source.input != .isolatedBackdrop || targetSize == source.size)
    }

    mutating func advance(to timestamp: Double) {
        guard timestamp.isFinite else { return }
        self.timestamp = max(self.timestamp, timestamp)
    }

    func append(to scene: inout GPUIScene, targetSize: IntSize, displayScale: Double) {
        guard !isComplete, permitsTargetSize(targetSize), var image = image(displayScale: displayScale) else {
            return
        }
        let paint: GPUIScene
        if projectsPrimitiveOpacity {
            guard
                let projected = source.sceneApplyingInheritedOpacity(
                    image.opacity, permitsInheritedEffectOpacity: true, permitsInheritedBackdropOpacity: true)
            else { return }
            paint = projected
            image.opacity = 1
        } else {
            paint = source.scene
        }
        let textureID = scene.registerImageRenderPass(paint, size: source.size, input: source.input)
        image.textureID = textureID
        scene.addImage(image, toLayer: max(0, scene.layers.count - 1))
    }

    private func image(displayScale: Double) -> ImagePrimitive? {
        guard displayScale.isFinite, displayScale > 0 else { return nil }
        var opacity = pose.opacity
        var transform = pose.transform
        for (property, state) in states {
            guard timestamp >= state.startTime else { continue }
            let value = state.interpolatedValue(at: timestamp)
            switch property {
            case .opacity: opacity = min(1, max(0, value))
            case .transformScaleX: transform.scaleX = value
            case .transformScaleY: transform.scaleY = value
            case .transformRotation: transform.rotation = value
            case .transformTranslationX: transform.translationX = value
            case .transformTranslationY: transform.translationY = value
            default: break
            }
        }
        // A zero-opacity root is culled by the ordinary painter. A material
        // quad with zero tint alpha can still replace the backdrop, so that
        // culling must happen before projecting alphas into a visible wrapper.
        guard pose.opacity > 0, opacity > 0 else { return nil }
        let relativeOpacity = Float(max(0, opacity / pose.opacity))
        let scale = displayScale / pose.displayScale
        // Dependent sources are explicitly the original parent pixel domain.
        // The current backdrop-pair API cannot transport a DPI/affine change.
        guard source.input != .isolatedBackdrop || scale == 1 else { return nil }
        let before = Self.centered(pose.transform.matrix, pivot: pose.pivot, displayScale: pose.displayScale)
        let after = Self.centered(transform.matrix, pivot: pose.pivot, displayScale: pose.displayScale)
        let delta = before == after ? AffineMatrix.identity : before.inverted().concatenating(after)
        let placement = delta.concatenating(AffineMatrix(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: 0))
        let center = Self.applying(
            placement, to: Point(x: source.bounds.midX, y: source.bounds.midY))
        guard [center.x, center.y, placement.a, placement.b, placement.c, placement.d].allSatisfy(\.isFinite) else {
            return nil
        }
        var image = ImagePrimitive(
            screenX: Float(center.x - source.bounds.size.width / 2),
            screenY: Float(center.y - source.bounds.size.height / 2),
            screenW: Float(source.bounds.size.width), screenH: Float(source.bounds.size.height),
            opacity: relativeOpacity,
            affineA: Float(placement.a), affineB: Float(placement.b),
            affineC: Float(placement.c), affineD: Float(placement.d))
        if let clip = pose.clip {
            image.contentMask = GPUIContentMask(bounds: clip.rect.scaled(by: displayScale))
        } else {
            image.contentMask = GPUIContentMask()
        }
        return image
    }

    private static func value(of property: AnimatableProperty, pose: RetainedLazyListPaintPose) -> Double? {
        switch property {
        case .opacity: return pose.opacity
        case .transformScaleX: return pose.transform.scaleX
        case .transformScaleY: return pose.transform.scaleY
        case .transformRotation: return pose.transform.rotation
        case .transformTranslationX: return pose.transform.translationX
        case .transformTranslationY: return pose.transform.translationY
        default: return nil
        }
    }

    private static func centered(_ matrix: AffineMatrix, pivot: Point, displayScale: Double) -> AffineMatrix {
        let x = pivot.x * displayScale
        let y = pivot.y * displayScale
        let transform = AffineMatrix(
            a: matrix.a, b: matrix.b, c: matrix.c, d: matrix.d,
            tx: matrix.tx * displayScale, ty: matrix.ty * displayScale)
        return AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: -x, ty: -y)
            .concatenating(transform)
            .concatenating(AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y))
    }

    private static func applying(_ matrix: AffineMatrix, to point: Point) -> Point {
        Point(
            x: point.x * matrix.a + point.y * matrix.c + matrix.tx,
            y: point.x * matrix.b + point.y * matrix.d + matrix.ty)
    }
}
