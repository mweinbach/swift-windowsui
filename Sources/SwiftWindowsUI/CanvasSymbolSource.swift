import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics

/// A resolved Canvas symbol owns an isolated retained tree. Its measured size
/// is in logical points and is independent of every destination it is drawn in.
/// The tree is never attached to the window's interaction or accessibility tree.
@MainActor
public final class CanvasSymbolSource {
    public let size: Size
    public let displayScale: Double

    internal let runtime: RetainedViewRuntime
    internal let pixelSize: IntSize

    private static var preparationDepth = 0
    private static var hasReportedRejection = false
    internal private(set) static var rejectionCount = 0

    /// Builds and measures one symbol without starting a paint or glyph-atlas
    /// frame. The caller supplies the inherited environment while building.
    public init?(displayScale: Double, build: (RetainedViewRuntime) -> ViewNode?) {
        guard displayScale.isFinite, displayScale > 0 else {
            Self.reportRejection("the display scale must be finite and positive")
            return nil
        }
        guard Self.preparationDepth < GPUISceneLimits.maxImageRenderPassDepth else {
            Self.reportRejection("nested symbol construction exceeds the image-pass depth limit")
            return nil
        }
        Self.preparationDepth += 1
        defer { Self.preparationDepth -= 1 }

        // ScenePainter applies this same lower bound when points become pixels.
        let scale = max(1, displayScale)
        let runtime = RetainedViewRuntime(clearColor: .clear, displayScale: scale)
        guard let content = build(runtime) else { return nil }
        guard let size = runtime.prepareCanvasSymbolLayout(content: content),
            let pixelSize = Self.pixelSize(for: size, displayScale: scale)
        else {
            Self.reportRejection("the measured symbol exceeds the supported image-pass extent")
            return nil
        }
        self.runtime = runtime
        self.size = size
        self.displayScale = scale
        self.pixelSize = pixelSize
    }

    /// An empty tagged view is still a resolved symbol. No source allocation
    /// is needed until both axes have positive extent.
    internal static func pixelSize(for size: Size, displayScale: Double) -> IntSize? {
        guard size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0,
            displayScale.isFinite, displayScale > 0
        else { return nil }
        let width = (size.width * displayScale).rounded(.up)
        let height = (size.height * displayScale).rounded(.up)
        guard width.isFinite, height.isFinite,
            width <= Double(GPUISceneLimits.maxSurfaceDimension),
            height <= Double(GPUISceneLimits.maxSurfaceDimension),
            width * height <= Double(GPUISceneLimits.maxImageRenderPassPixels)
        else { return nil }
        if width == 0 || height == 0 { return .zero }
        return IntSize(width: Int32(width), height: Int32(height))
    }

    internal static func reportRejection(_ reason: String) {
        rejectionCount &+= 1
        guard !hasReportedRejection else { return }
        hasReportedRejection = true
        FileHandle.standardError.write(Data("[SwiftWindowsUI] Canvas symbol rejected: \(reason).\n".utf8))
    }
}

/// Cropped retained paint, including pixels outside the symbol's layout box.
/// `scene` is translated to zero; `pixelBounds` retains the original device
/// coordinate crop so that a destination mapping also places shadows correctly.
internal struct CanvasSymbolSceneSnapshot: Sendable {
    let scene: GPUIScene
    let pixelBounds: Rect
    let pixelSize: IntSize
    let rejectionReason: String?

    init(scene: GPUIScene, pixelBounds: Rect, pixelSize: IntSize, rejectionReason: String? = nil) {
        self.scene = scene
        self.pixelBounds = pixelBounds
        self.pixelSize = pixelSize
        self.rejectionReason = rejectionReason
    }
}

/// The legacy frame contract carries bitmaps, not retained image passes. This
/// value scopes its source cache and allocation budget to one Canvas recording.
/// The normal scene path never enters this renderer.
@MainActor
internal struct CanvasSymbolFrameRenderer {
    private enum Source {
        case empty
        case rejected
        case bitmap(BitmapSurface, pixelBounds: Rect)
    }

    private var sources: [ObjectIdentifier: Source] = [:]
    private var budget = GPUISceneImageRenderPassBudget()

    mutating func append(
        _ symbol: CanvasSymbolSource,
        in rect: Rect,
        transform: CGAffineTransform,
        origin: Point,
        clipRect: Rect?,
        opacity: Float,
        displayScale: Double,
        to commands: inout [RenderCommand]
    ) {
        guard opacity.isFinite, opacity > 0, !rect.isEmpty,
            symbol.size.width > 0, symbol.size.height > 0
        else { return }
        if let clipRect, clipRect.isEmpty { return }
        guard displayScale.isFinite, displayScale > 0,
            Self.isFinite(rect), Self.isValid(transform),
            origin.x.isFinite, origin.y.isFinite
        else {
            appendRejection(
                in: nil, origin: origin, clipRect: clipRect, opacity: opacity, displayScale: displayScale, to: &commands
            )
            return
        }

        let source: Source
        let key = ObjectIdentifier(symbol)
        if let cached = sources[key] {
            source = cached
        } else if sources.count >= GPUISceneLimits.maxImageRenderPassCount {
            source = .rejected
        } else {
            source = resolve(symbol)
            sources[key] = source
        }
        switch source {
        case .empty:
            return
        case .rejected:
            let bounds = Self.transformedBounds(rect, by: transform).offsetBy(dx: origin.x, dy: origin.y)
            appendRejection(
                in: bounds, origin: origin, clipRect: clipRect, opacity: opacity, displayScale: displayScale,
                to: &commands)
            return
        case .bitmap(let bitmap, let sourceBounds):
            let scale = max(1, displayScale)
            let destinationScaleX = rect.width / symbol.size.width
            let destinationScaleY = rect.height / symbol.size.height
            let crop = Rect(
                x: rect.minX + sourceBounds.minX / symbol.displayScale * destinationScaleX,
                y: rect.minY + sourceBounds.minY / symbol.displayScale * destinationScaleY,
                width: sourceBounds.width / symbol.displayScale * destinationScaleX,
                height: sourceBounds.height / symbol.displayScale * destinationScaleY)
            guard Self.isFinite(crop) else {
                appendRejection(
                    in: nil, origin: origin, clipRect: clipRect, opacity: opacity, displayScale: displayScale,
                    to: &commands)
                return
            }
            let transformed = Self.transformedBounds(crop, by: transform)
                .offsetBy(dx: origin.x, dy: origin.y)
            guard Self.isFinite(transformed) else {
                appendRejection(
                    in: nil, origin: origin, clipRect: clipRect, opacity: opacity, displayScale: displayScale,
                    to: &commands)
                return
            }
            let visible: Rect
            if let clipRect {
                guard let intersection = transformed.intersected(with: clipRect) else { return }
                visible = intersection
            } else {
                visible = transformed
            }
            if transform.a == 1, transform.b == 0, transform.c == 0, transform.d == 1 {
                let deviceRect = transformed.scaled(by: scale)
                let limit = Double(GPUISceneLimits.maxCoordinate)
                guard Self.isFinite(deviceRect),
                    [
                        deviceRect.minX, deviceRect.minY, deviceRect.maxX, deviceRect.maxY, deviceRect.width,
                        deviceRect.height,
                    ]
                    .allSatisfy({ abs($0) <= limit })
                else {
                    appendRejection(
                        in: visible, origin: origin, clipRect: clipRect, opacity: opacity, displayScale: displayScale,
                        to: &commands)
                    return
                }
                // The command already supports axis-aligned scaling and clips.
                // Reuse the source bitmap without allocating a second surface.
                commands.append(
                    .drawBitmap(
                        DrawBitmapCommand(
                            rect: transformed, bitmap: bitmap, opacity: min(1, opacity), clipRect: clipRect)))
                return
            }
            // The even device-grid origin preserves the reference rasterizer's
            // 2x2 coverage derivatives in this small transient image scene.
            let deviceBounds = Self.deviceBounds(visible, scale: scale)
            var candidateBudget = budget
            guard let outputSize = CanvasSymbolSource.pixelSize(for: deviceBounds.size, displayScale: 1),
                outputSize.width > 0, outputSize.height > 0,
                candidateBudget.consume(size: outputSize)
            else {
                appendRejection(
                    in: visible, origin: origin, clipRect: clipRect, opacity: opacity, displayScale: displayScale,
                    to: &commands)
                return
            }

            let centre = transform.apply(Point(x: crop.midX, y: crop.midY))
            let width = crop.width * scale
            let height = crop.height * scale
            let imageX = (centre.x + origin.x) * scale - deviceBounds.minX - width / 2
            let imageY = (centre.y + origin.y) * scale - deviceBounds.minY - height / 2
            let coordinateLimit = Double(GPUISceneLimits.maxCoordinate)
            guard [imageX, imageY, width, height].allSatisfy({ $0.isFinite && abs($0) <= coordinateLimit })
            else {
                appendRejection(
                    in: visible, origin: origin, clipRect: clipRect, opacity: opacity, displayScale: displayScale,
                    to: &commands)
                return
            }
            let image = ImagePrimitive(
                screenX: Float(imageX), screenY: Float(imageY),
                screenW: Float(width), screenH: Float(height),
                affineA: Float(transform.a), affineB: Float(transform.b),
                affineC: Float(transform.c), affineD: Float(transform.d))
            guard let image = GPUISceneSanitizer.sanitized(image) else {
                appendRejection(
                    in: visible, origin: origin, clipRect: clipRect, opacity: opacity, displayScale: displayScale,
                    to: &commands)
                return
            }
            var scene = GPUIScene(clearColor: .clear)
            var placedImage = image
            placedImage.textureID = scene.registerImageResource(bitmap)
            scene.addImage(placedImage, toLayer: 0)
            scene.finish()
            budget = candidateBudget
            let composed = GPUIRawSceneRasterizer.rasterize(scene, size: outputSize)
            commands.append(
                .drawBitmap(
                    DrawBitmapCommand(
                        rect: deviceBounds.scaled(by: 1 / scale), bitmap: composed,
                        opacity: min(1, opacity), clipRect: clipRect)))
        }
    }

    private mutating func resolve(_ symbol: CanvasSymbolSource) -> Source {
        guard budget.remainingPasses > 0, budget.remainingPixels > 0 else {
            CanvasSymbolSource.reportRejection("the legacy frame symbol allocation budget was exhausted")
            return .rejected
        }
        guard let snapshot = ScenePainter.canvasSymbolSnapshot(symbol) else { return .empty }
        if let reason = snapshot.rejectionReason {
            CanvasSymbolSource.reportRejection(reason)
            return .rejected
        }
        var candidateBudget = budget
        guard candidateBudget.consume(size: snapshot.pixelSize),
            Self.consumeNestedSources(of: snapshot.scene, budget: &candidateBudget)
        else {
            CanvasSymbolSource.reportRejection("the legacy frame symbol allocation budget was exhausted")
            return .rejected
        }
        budget = candidateBudget
        let bitmap = GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.pixelSize)
        return .bitmap(bitmap, pixelBounds: snapshot.pixelBounds)
    }

    /// Match the CPU renderer's once-per-namespace realization of referenced
    /// image passes, including nested sources, before any source rasterization.
    private static func consumeNestedSources(
        of scene: GPUIScene, budget: inout GPUISceneImageRenderPassBudget
    ) -> Bool {
        var pending: [(GPUIScene, Int)] = [(scene, 0)]
        while let (current, depth) = pending.popLast() {
            var resolved = Set(current.imageResources.map(\.textureID))
            let passes = Dictionary(
                current.imageRenderPasses.map { ($0.textureID, $0) }, uniquingKeysWith: { _, last in last })
            for run in current.presentationOrder() where run.kind == .image {
                for index in run.range {
                    let textureID = current.layers[run.layerIndex].images[index].textureID
                    guard resolved.insert(textureID).inserted, let pass = passes[textureID] else { continue }
                    guard depth < GPUISceneLimits.maxImageRenderPassDepth,
                        pass.colorEffects.count <= GPUISceneLimits.maxColorEffects,
                        budget.consume(size: pass.size)
                    else { return false }
                    pending.append((pass.scene, depth + 1))
                }
            }
        }
        return true
    }

    private mutating func appendRejection(
        in proposedRect: Rect?, origin: Point, clipRect: Rect?, opacity: Float, displayScale: Double,
        to commands: inout [RenderCommand]
    ) {
        CanvasSymbolSource.reportRejection("the legacy frame symbol placement or extent is unsupported")
        let scale = displayScale.isFinite && displayScale > 0 ? max(1, displayScale) : 1
        let limit = Double(GPUISceneLimits.maxCoordinate)
        func clipped(_ rect: Rect) -> Rect? {
            guard Self.isFinite(rect), !rect.isEmpty else { return nil }
            guard let clipRect else { return rect }
            guard Self.isFinite(clipRect), !clipRect.isEmpty else { return nil }
            return rect.intersected(with: clipRect)
        }
        func representable(_ rect: Rect) -> Bool {
            let device = rect.scaled(by: scale)
            return Self.isFinite(device)
                && [device.minX, device.minY, device.maxX, device.maxY, device.width, device.height]
                    .allSatisfy { abs($0) <= limit }
        }
        // An enormous but finite matrix can overflow the frame bridge's
        // Float coordinates. Its diagnostic must remain drawable: use the
        // visible proposal when representable, otherwise a 16-device-pixel
        // marker at a safe Canvas/clip origin, still inside the caller's clip.
        let proposed = proposedRect.flatMap(clipped).flatMap { representable($0) ? $0 : nil }
        let fallback = [clipRect?.origin, origin, Point.zero].compactMap { $0 }.compactMap { point in
            clipped(Rect(origin: point, size: Size(width: 16 / scale, height: 16 / scale)))
        }.first(where: representable)
        guard let visible = proposed ?? fallback else { return }
        let bitmap = BitmapSurface(
            width: 2, height: 2, bytesPerRow: 8,
            pixels: Data([255, 0, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 0, 255, 255]))
        commands.append(
            .drawBitmap(
                DrawBitmapCommand(rect: visible, bitmap: bitmap, opacity: min(1, opacity), clipRect: visible)))
    }

    private static func isFinite(_ rect: Rect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.maxX.isFinite && rect.maxY.isFinite
    }

    private static func isValid(_ transform: CGAffineTransform) -> Bool {
        let determinant = transform.a * transform.d - transform.b * transform.c
        return transform.a.isFinite && transform.b.isFinite && transform.c.isFinite && transform.d.isFinite
            && transform.tx.isFinite && transform.ty.isFinite && determinant.isFinite && determinant != 0
    }

    private static func transformedBounds(_ rect: Rect, by transform: CGAffineTransform) -> Rect {
        let points = [
            transform.apply(Point(x: rect.minX, y: rect.minY)),
            transform.apply(Point(x: rect.maxX, y: rect.minY)),
            transform.apply(Point(x: rect.minX, y: rect.maxY)),
            transform.apply(Point(x: rect.maxX, y: rect.maxY)),
        ]
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return Rect(x: .nan, y: .nan, width: .nan, height: .nan)
        }
        let left = points.map(\.x).min() ?? 0
        let top = points.map(\.y).min() ?? 0
        let right = points.map(\.x).max() ?? 0
        let bottom = points.map(\.y).max() ?? 0
        return Rect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func deviceBounds(_ rect: Rect, scale: Double) -> Rect {
        let left = (rect.minX * scale / 2).rounded(.down) * 2
        let top = (rect.minY * scale / 2).rounded(.down) * 2
        let right = (rect.maxX * scale).rounded(.up)
        let bottom = (rect.maxY * scale).rounded(.up)
        return Rect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
