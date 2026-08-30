import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics

/// Paint values from one completed scene, without a retained view or app callback.
/// The caller owns the proof that the ranges belong to this exact scene namespace.
struct RetainedLazyListPaintSource: Sendable {
    let scene: GPUIScene
    /// Original device coordinates. The stored scene is relative to this origin.
    let bounds: Rect
    let size: IntSize
    let input: GPUISceneImageRenderPassInput
    /// Retained primitive storage and canonical resource buffers, including padding.
    let resourceBytes: Int
    /// Primitive records in this namespace and its referenced child namespaces.
    let recordCount: Int
    /// The added source pass and all of its actual nested occurrences.
    let executionPassCount: Int
    let executionPixelCount: Int64
    /// An explicit mask may already have removed pixels in the root namespace.
    /// Internal child masks move with their image and do not set this flag.
    let wasClipped: Bool

    struct ExecutionCost: Equatable, Sendable {
        let passCount: Int
        let pixelCount: Int64
    }

    enum CaptureResult: Sendable {
        case empty
        case captured(RetainedLazyListPaintSource)
        case unsupported
    }

    static let maximumRecordCount = 65_536
    static let maximumResourceBytes = 64 * 1024 * 1024
    static let maximumRangeCount = 1_024
    static let maximumInspectedEntries = 262_144
    static let maximumSourcePixels = GPUISceneLimits.maxImageRenderPassPixels

    /// Extracts already painted records. This never repaints, resolves a live
    /// atlas, or treats a missing resource as an empty subtree. Scope markers
    /// bracket replay only; primitive clips already contain their paint state.
    static func capture(scene: GPUIScene, ranges: [Range<Int>], surfaceSize: IntSize) -> CaptureResult {
        guard validSurface(surfaceSize), ranges.count <= maximumRangeCount else { return .unsupported }
        let builder = CaptureBuilder()
        guard let selected = builder.selection(in: scene, ranges: ranges) else { return .unsupported }
        guard !selected.isEmpty else { return .empty }
        guard let recorded = builder.copyNamespace(scene, selected: selected, depth: 1, clearColor: .clear) else {
            return .unsupported
        }

        let bounds: Rect
        let size: IntSize
        let input: GPUISceneImageRenderPassInput
        let frozen: GPUIScene
        if recorded.readsBackdrop || recorded.requiresOriginalSurface {
            // A material samples beyond its own painted bounds. Preserve the
            // original target domain, including nested current-target extents,
            // rather than introducing a new crop edge into its backdrop reads.
            bounds = Rect(x: 0, y: 0, width: Double(surfaceSize.width), height: Double(surfaceSize.height))
            size = surfaceSize
            input = recorded.readsBackdrop ? .isolatedBackdrop : .independent
            frozen = recorded.scene
        } else {
            guard let painted = recorded.scene.paintedBounds, let crop = croppedBounds(painted) else {
                return .unsupported
            }
            bounds = crop.0
            size = crop.1
            input = .independent
            frozen = recorded.scene.translatedPrimitives(by: Point(x: -bounds.minX, y: -bounds.minY))
            guard frozen.primitiveCount == recorded.scene.primitiveCount else { return .unsupported }
        }
        guard validSourceSize(size), let cost = wrapperExecutionCost(frozen, size: size, input: input) else {
            return .unsupported
        }
        return .captured(
            RetainedLazyListPaintSource(
                scene: frozen, bounds: bounds, size: size, input: input,
                resourceBytes: builder.resourceBytes, recordCount: builder.recordCount,
                executionPassCount: cost.passCount, executionPixelCount: cost.pixelCount,
                wasClipped: recorded.wasClipped))
    }

    /// Freeze a normal paint before an external pixel owner can mutate its
    /// storage. Record, layer, primitive and resource indices stay unchanged,
    /// including resources not selected by a later departure. Failure makes
    /// that paint unavailable for capture; it does not establish empty paint.
    static func freezingResources(in scene: GPUIScene) -> GPUIScene? {
        let builder = CaptureBuilder()
        guard let frozen = builder.preservingNamespace(scene, depth: 0), frozen.validate().isEmpty else { return nil }
        return frozen
    }

    /// The frame fallback has its own command namespace. Only bitmap storage
    /// is replaced, so a previously recorded command range retains its meaning.
    static func freezingResources(in frame: RenderFrame) -> RenderFrame? {
        CaptureBuilder().preservingFrame(frame)
    }

    private static func validSurface(_ size: IntSize) -> Bool {
        size.width > 0 && size.height > 0
            && Int(size.width) <= GPUISceneLimits.maxSurfaceDimension
            && Int(size.height) <= GPUISceneLimits.maxSurfaceDimension
    }

    private static func validSourceSize(_ size: IntSize) -> Bool {
        validSurface(size) && Int64(size.width) * Int64(size.height) <= Int64(maximumSourcePixels)
    }

    private static func croppedBounds(_ bounds: Rect) -> (Rect, IntSize)? {
        guard bounds.minX.isFinite, bounds.minY.isFinite, bounds.maxX.isFinite, bounds.maxY.isFinite,
            !bounds.isEmpty
        else { return nil }
        // An even translation preserves the original two-by-two coverage grid.
        let left = floor(bounds.minX / 2) * 2
        let top = floor(bounds.minY / 2) * 2
        let width = ceil(bounds.maxX) - left
        let height = ceil(bounds.maxY) - top
        guard width > 0, height > 0,
            width <= Double(GPUISceneLimits.maxSurfaceDimension),
            height <= Double(GPUISceneLimits.maxSurfaceDimension),
            width * height <= Double(maximumSourcePixels)
        else { return nil }
        return (
            Rect(x: left, y: top, width: width, height: height),
            IntSize(width: Int32(width), height: Int32(height))
        )
    }

    /// Admission includes the added wrapper, its depth, and the execution cost
    /// of every occurrence. Dependent children reserve eight scratch planes;
    /// an independent child starts a separate backdrop domain.
    private static func wrapperExecutionCost(
        _ source: GPUIScene, size: IntSize, input: GPUISceneImageRenderPassInput
    ) -> ExecutionCost? {
        let wrapper = GPUISceneImageRenderPass(textureID: 0, scene: source, size: size, input: input)
        var validation = GPUIScene(clearColor: .clear, imageRenderPasses: [wrapper])
        validation.addImage(ImagePrimitive(screenW: Float(size.width), screenH: Float(size.height), textureID: 0))
        return executionCost(scene: validation, surfaceSize: size)
    }

    /// Execution reservation for the live graph, without adding a capture
    /// wrapper or charging the main surface. Each occurrence is charged even
    /// where one backend can reuse an independent image; this admits both
    /// renderers. Unpresented declarations still reserve structural capacity.
    /// Structural inspection is bounded before validate() recurses.
    static func executionCost(scene: GPUIScene, surfaceSize: IntSize) -> ExecutionCost? {
        let builder = CaptureBuilder(copyResourceBytes: false)
        guard validSurface(surfaceSize),
            let bounded = builder.preservingNamespace(scene, depth: 0),
            bounded.validate().isEmpty
        else { return nil }
        var budget = GPUISceneImageRenderPassBudget()
        var inspectedEntries = 0
        var pending = [(scene: bounded, size: surfaceSize, depth: 0, isolated: false)]
        while let entry = pending.popLast() {
            let passes = Dictionary(uniqueKeysWithValues: entry.scene.imageRenderPasses.map { ($0.textureID, $0) })
            for run in entry.scene.presentationOrder() where run.kind == .image {
                guard run.range.count <= maximumInspectedEntries - inspectedEntries else { return nil }
                inspectedEntries += run.range.count
                for index in run.range {
                    let image = entry.scene.layers[run.layerIndex].images[index]
                    guard let pass = passes[image.textureID] else { continue }
                    guard entry.depth < GPUISceneLimits.maxImageRenderPassDepth,
                        budget.consume(pass, inBackdropIsolation: entry.isolated)
                    else { return nil }
                    switch pass.input {
                    case .independent:
                        break
                    case .currentTarget:
                        guard pass.currentTargetRegion(for: image, parentSize: entry.size) != nil else { return nil }
                    case .isolatedBackdrop:
                        guard pass.isolatedBackdropMapping(for: image, parentSize: entry.size) != nil else {
                            return nil
                        }
                    }
                    pending.append(
                        (
                            scene: pass.scene, size: pass.size, depth: entry.depth + 1,
                            isolated: pass.input == .isolatedBackdrop
                                || (pass.input == .currentTarget && entry.isolated)
                        ))
                }
            }
        }
        return ExecutionCost(
            passCount: max(
                builder.declaredCost.passCount, GPUISceneLimits.maxImageRenderPassCount - budget.remainingPasses),
            pixelCount: max(
                builder.declaredCost.pixelCount,
                Int64(GPUISceneLimits.maxImageRenderPassTotalPixels) - budget.remainingPixels))
    }

    private struct Reference: Hashable {
        let layer: Int
        let kind: GPUIPaintPrimitiveKind
        let index: Int

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.layer == rhs.layer && lhs.kind == rhs.kind && lhs.index == rhs.index
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(layer)
            hasher.combine(index)
            switch kind {
            case .shadow: hasher.combine(0)
            case .quad: hasher.combine(1)
            case .glyph: hasher.combine(2)
            case .pixelGlyph: hasher.combine(3)
            case .image: hasher.combine(4)
            case .path: hasher.combine(5)
            }
        }
    }

    private struct AtlasKey: Hashable {
        let version: UInt64
        let width: Int32
        let height: Int32
    }

    private struct RecordedNamespace {
        var scene: GPUIScene
        var readsBackdrop = false
        var requiresOriginalSurface = false
        var wasClipped = false
    }

    /// Recording state is local to this call. Canonicalization ensures equal
    /// resource identities retain the buffer charged to the budget, not several
    /// separately allocated copies claiming the same identity.
    private final class CaptureBuilder {
        var resourceBytes = 0
        var recordCount = 0
        private var inspectedEntries = 0
        private var namespaceCount = 0
        private var bitmaps: [BitmapContentKey: BitmapSurface] = [:]
        private var atlases: [AtlasKey: GlyphAtlasSnapshot] = [:]
        private let copyResourceBytes: Bool
        private var declaredBudget = GPUISceneImageRenderPassBudget()

        var declaredCost: ExecutionCost {
            ExecutionCost(
                passCount: GPUISceneLimits.maxImageRenderPassCount - declaredBudget.remainingPasses,
                pixelCount: Int64(GPUISceneLimits.maxImageRenderPassTotalPixels) - declaredBudget.remainingPixels)
        }

        init(copyResourceBytes: Bool = true) {
            self.copyResourceBytes = copyResourceBytes
        }

        func selection(in scene: GPUIScene, ranges: [Range<Int>]) -> Set<Reference>? {
            guard scene.layers.count <= GPUISceneLimits.maxLayers, inspect(scene.paintRecords.count) else { return nil }
            var merged: [Range<Int>] = []
            for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                guard range.lowerBound >= 0, range.upperBound <= scene.paintRecords.count else { return nil }
                if let previous = merged.last, range.lowerBound <= previous.upperBound {
                    merged[merged.count - 1] = previous.lowerBound..<max(previous.upperBound, range.upperBound)
                } else {
                    merged.append(range)
                }
            }
            var depths = [Int](repeating: 0, count: scene.layers.count)
            var selected: Set<Reference> = []
            var rangeIndex = 0
            for (index, record) in scene.paintRecords.enumerated() {
                while rangeIndex < merged.count, merged[rangeIndex].upperBound <= index { rangeIndex += 1 }
                let includes = rangeIndex < merged.count && merged[rangeIndex].contains(index)
                switch record {
                case .primitive(let layer, let kind, let primitiveIndex):
                    guard scene.primitive(kind: kind, inLayer: layer, at: primitiveIndex) != nil else { return nil }
                    if includes {
                        selected.insert(Reference(layer: layer, kind: kind, index: primitiveIndex))
                        guard selected.count <= maximumRecordCount else { return nil }
                    }
                case .startLayer(let layer, let bounds):
                    guard depths.indices.contains(layer), bounds.minX.isFinite, bounds.minY.isFinite,
                        bounds.maxX.isFinite, bounds.maxY.isFinite, !bounds.isEmpty
                    else { return nil }
                    depths[layer] += 1
                case .endLayer(let layer):
                    guard depths.indices.contains(layer), depths[layer] > 0 else { return nil }
                    depths[layer] -= 1
                }
            }
            return depths.allSatisfy { $0 == 0 } ? selected : nil
        }

        /// Unlike extraction, a normal-paint snapshot must keep every address,
        /// scope marker and operation boundary. Only resource values change.
        func preservingNamespace(_ source: GPUIScene, depth: Int, isolated: Bool = false) -> GPUIScene? {
            guard depth <= GPUISceneLimits.maxImageRenderPassDepth,
                namespaceCount <= GPUISceneLimits.maxImageRenderPassCount,
                selection(in: source, ranges: []) != nil,
                let order = selectedPresentation(in: source, selected: nil),
                chargeBytes(MemoryLayout<GPUIScene>.stride),
                chargeArray(source.layers.capacity, stride: MemoryLayout<GPUILayer>.stride),
                chargeArray(source.paintRecords.capacity, stride: MemoryLayout<GPUIScenePaintRecord>.stride),
                inspect(source.imageResources.count), inspect(source.imageRenderPasses.count),
                chargeArray(source.imageResources.capacity, stride: MemoryLayout<ImageResourceBinding>.stride),
                chargeArray(source.imageRenderPasses.capacity, stride: MemoryLayout<GPUISceneImageRenderPass>.stride)
            else { return nil }
            namespaceCount += 1
            for layer in source.layers {
                for count in [
                    layer.shadows.count, layer.quads.count, layer.glyphs.count,
                    layer.pixelGlyphs.count, layer.images.count, layer.paths.count,
                ] {
                    guard inspect(count), count <= maximumRecordCount - recordCount else { return nil }
                }
                guard chargeArray(layer.paintOperations.capacity, stride: MemoryLayout<GPUIPaintOperation>.stride),
                    chargeSparePrimitiveCapacity(in: layer)
                else { return nil }
                for value in layer.shadows where !charge(.shadow(value)) { return nil }
                for value in layer.quads where !charge(.quad(value)) { return nil }
                for value in layer.glyphs where !charge(.glyph(value)) { return nil }
                for value in layer.pixelGlyphs where !charge(.pixelGlyph(value)) { return nil }
                for value in layer.images where !charge(.image(value)) { return nil }
                for value in layer.paths where !charge(.path(value)) { return nil }
            }

            guard source.imageResources.allSatisfy({ $0.textureID >= 0 }) else { return nil }
            let imageIDs = Set(source.imageResources.map(\.textureID) + source.imageRenderPasses.map(\.textureID))
            for reference in order {
                switch reference.kind {
                case .glyph:
                    guard source.glyphAtlas != nil else { return nil }
                case .pixelGlyph:
                    guard source.pixelGlyphAtlas != nil else { return nil }
                case .image:
                    guard imageIDs.contains(source.layers[reference.layer].images[reference.index].textureID) else {
                        return nil
                    }
                case .shadow, .quad, .path:
                    break
                }
            }

            var frozen = source
            if let atlas = source.glyphAtlas {
                guard let pixels = freeze(atlas, preservingUpdate: true) else { return nil }
                if copyResourceBytes { frozen.glyphAtlas = pixels }
            }
            if let atlas = source.pixelGlyphAtlas {
                guard let pixels = freeze(atlas, preservingUpdate: true) else { return nil }
                if copyResourceBytes { frozen.pixelGlyphAtlas = pixels }
            }
            for index in source.imageResources.indices {
                guard let bitmap = freeze(source.imageResources[index].bitmap) else { return nil }
                if copyResourceBytes { frozen.imageResources[index].bitmap = bitmap }
            }
            for index in source.imageRenderPasses.indices {
                let pass = source.imageRenderPasses[index]
                guard pass.hasValidExtent, pass.colorEffects.count <= GPUISceneLimits.maxColorEffects,
                    chargeArray(pass.colorEffects.capacity, stride: MemoryLayout<SceneColorEffect>.stride),
                    declaredBudget.consume(pass, inBackdropIsolation: isolated),
                    let child = preservingNamespace(
                        pass.scene, depth: depth + 1,
                        isolated: pass.input == .isolatedBackdrop || (pass.input == .currentTarget && isolated))
                else { return nil }
                if copyResourceBytes { frozen.imageRenderPasses[index].scene = child }
            }
            return frozen
        }

        func preservingFrame(_ frame: RenderFrame) -> RenderFrame? {
            guard frame.commands.count <= maximumRecordCount, inspect(frame.commands.count),
                chargeBytes(MemoryLayout<RenderFrame>.stride),
                chargeArray(frame.commands.capacity, stride: MemoryLayout<RenderCommand>.stride)
            else { return nil }
            var frozen = frame
            for index in frame.commands.indices {
                switch frame.commands[index] {
                case .drawBitmap(var command):
                    guard let bitmap = freeze(command.bitmap) else { return nil }
                    command.bitmap = bitmap
                    frozen.commands[index] = .drawBitmap(command)
                case .fillRect(let command):
                    guard charge(command.gradient) else { return nil }
                case .fillPath(let command):
                    guard charge(command.path), charge(command.gradient) else { return nil }
                case .strokePath(let command):
                    guard charge(command.path),
                        chargeArray(command.style.dashPattern.capacity, stride: MemoryLayout<Double>.stride)
                    else { return nil }
                case .drawText(let command):
                    guard chargeArray(command.text.utf8.count, stride: 2),
                        chargeArray(command.fontName.utf8.count, stride: 2)
                    else { return nil }
                case .pushClip(let command):
                    if case .path(let path) = command.shape, !charge(path) { return nil }
                case .applyBlur, .popClip:
                    break
                }
            }
            return frozen
        }

        private func charge(_ path: RenderPath) -> Bool {
            inspect(path.segments.count)
                && chargeArray(path.segments.capacity, stride: MemoryLayout<RenderPath.Segment>.stride)
        }

        private func charge(_ gradient: GradientType?) -> Bool {
            let capacity: Int
            switch gradient {
            case .linear(let value): capacity = value.stops.capacity
            case .radial(let value): capacity = value.stops.capacity
            case .conic(let value): capacity = value.stops.capacity
            case nil: return true
            }
            return chargeArray(capacity, stride: MemoryLayout<GradientStop>.stride)
        }

        func copyNamespace(
            _ source: GPUIScene, selected: Set<Reference>?, depth: Int, clearColor: Color? = nil
        ) -> RecordedNamespace? {
            guard depth <= GPUISceneLimits.maxImageRenderPassDepth,
                namespaceCount < GPUISceneLimits.maxImageRenderPassCount,
                source.layers.count <= GPUISceneLimits.maxLayers
            else { return nil }
            namespaceCount += 1
            guard let order = selectedPresentation(in: source, selected: selected) else { return nil }
            let imageIDs = Set(
                order.compactMap { reference -> Int32? in
                    guard
                        let primitive = source.primitive(
                            kind: reference.kind, inLayer: reference.layer, at: reference.index),
                        case .image(let image) = primitive
                    else { return nil }
                    return image.textureID
                })
            guard inspect(source.imageResources.count), inspect(source.imageRenderPasses.count) else { return nil }
            var bindings: [Int32: BitmapSurface] = [:]
            for binding in source.imageResources where imageIDs.contains(binding.textureID) {
                bindings[binding.textureID] = binding.bitmap
            }
            var passes: [Int32: GPUISceneImageRenderPass] = [:]
            for pass in source.imageRenderPasses where imageIDs.contains(pass.textureID) {
                guard passes[pass.textureID] == nil, bindings[pass.textureID] == nil else { return nil }
                passes[pass.textureID] = pass
            }
            var result = RecordedNamespace(scene: GPUIScene(clearColor: clearColor ?? source.clearColor))
            var installedImages: Set<Int32> = []
            for reference in order {
                guard
                    let primitive = source.primitive(
                        kind: reference.kind, inLayer: reference.layer, at: reference.index), charge(primitive)
                else { return nil }
                switch primitive {
                case .glyph:
                    if result.scene.glyphAtlas == nil {
                        guard let atlas = source.glyphAtlas, let frozen = freeze(atlas) else { return nil }
                        result.scene.glyphAtlas = frozen
                    }
                case .pixelGlyph:
                    if result.scene.pixelGlyphAtlas == nil {
                        guard let atlas = source.pixelGlyphAtlas, let frozen = freeze(atlas) else { return nil }
                        result.scene.pixelGlyphAtlas = frozen
                    }
                case .quad(let quad):
                    // The current contract reserves this field but only defines
                    // source-over. Do not promise authored destination blending.
                    guard quad.blendMode == 0 else { return nil }
                    result.readsBackdrop = result.readsBackdrop || GPUISceneValue.int(quad.blurRadius) > 0
                case .image(let image):
                    guard image.textureID >= 0 else { return nil }
                    if installedImages.insert(image.textureID).inserted {
                        if let pass = passes[image.textureID] {
                            guard pass.hasValidExtent, pass.colorEffects.count <= GPUISceneLimits.maxColorEffects,
                                chargeBytes(MemoryLayout<GPUISceneImageRenderPass>.stride),
                                chargeArray(pass.colorEffects.capacity, stride: MemoryLayout<SceneColorEffect>.stride),
                                let child = copyNamespace(pass.scene, selected: nil, depth: depth + 1)
                            else { return nil }
                            var frozen = pass
                            frozen.scene = child.scene
                            result.scene.bindImageRenderPass(frozen)
                            result.readsBackdrop = result.readsBackdrop || pass.input != .independent
                        } else if let bitmap = bindings[image.textureID], let frozen = freeze(bitmap) {
                            guard chargeBytes(MemoryLayout<ImageResourceBinding>.stride) else { return nil }
                            result.scene.bindImageResource(frozen, for: image.textureID)
                        } else {
                            return nil
                        }
                    }
                case .path(let path):
                    // With no explicit rect, path rounding uses its target.
                    // A root crop must not introduce different rounded edges.
                    if depth == 1, path.clipBounds == nil, path.clipCornerRadius > 0 {
                        result.requiresOriginalSurface = true
                    }
                case .shadow:
                    break
                }
                guard append(primitive, to: &result.scene, layer: reference.layer) else { return nil }
                if depth == 1, !result.wasClipped { result.wasClipped = isClipped(primitive) }
            }
            guard chargeBytes(MemoryLayout<GPUIScene>.stride),
                chargeArray(result.scene.layers.capacity, stride: MemoryLayout<GPUILayer>.stride),
                chargeArray(
                    result.scene.paintRecords.capacity - result.scene.paintRecords.count,
                    stride: MemoryLayout<GPUIScenePaintRecord>.stride),
                chargeArray(
                    result.scene.imageResources.capacity - result.scene.imageResources.count,
                    stride: MemoryLayout<ImageResourceBinding>.stride),
                chargeArray(
                    result.scene.imageRenderPasses.capacity - result.scene.imageRenderPasses.count,
                    stride: MemoryLayout<GPUISceneImageRenderPass>.stride)
            else { return nil }
            for layer in result.scene.layers {
                guard chargeSparePrimitiveCapacity(in: layer),
                    chargeArray(
                        layer.paintOperations.capacity - layer.paintOperations.count,
                        stride: MemoryLayout<GPUIPaintOperation>.stride)
                else { return nil }
            }
            result.scene.finish()
            return result
        }

        private func isClipped(_ primitive: GPUIScenePrimitive) -> Bool {
            let mask: Rect?
            let radius: Double
            var unmasked = GPUIScene(clearColor: .clear)
            switch primitive {
            case .shadow(var value):
                mask = value.contentMask.bounds
                radius = Double(value.clipCornerRadius)
                value.contentMask = GPUIContentMask()
                value.clipCornerRadius = 0
                unmasked.addShadow(value)
            case .quad(var value):
                mask = value.contentMask.bounds
                radius = Double(value.clipCornerRadius)
                value.contentMask = GPUIContentMask()
                value.clipCornerRadius = 0
                unmasked.addQuad(value)
            case .glyph(var value), .pixelGlyph(var value):
                mask = value.contentMask.bounds
                radius = Double(value.clipCornerRadius)
                value.contentMask = GPUIContentMask()
                value.clipCornerRadius = 0
                unmasked.addGlyph(value)
            case .image(var value):
                mask = value.contentMask.bounds
                radius = Double(value.clipCornerRadius)
                value.contentMask = GPUIContentMask()
                value.clipCornerRadius = 0
                unmasked.addImage(value)
            case .path(var value):
                // A path can round the target boundary without clipBounds.
                if value.clipCornerRadius > 0 { return true }
                mask = value.clipBounds
                radius = value.clipCornerRadius
                value.clipBounds = nil
                value.clipCornerRadius = 0
                unmasked.addPath(value)
            }
            guard let mask else { return false }
            guard radius <= 0, let bounds = unmasked.paintedBounds else { return true }
            // Coverage can occupy the whole boundary pixel, particularly for
            // paths. Fractional masks may cut it even when geometry just fits.
            return floor(bounds.minX) < mask.minX || floor(bounds.minY) < mask.minY
                || ceil(bounds.maxX) > mask.maxX || ceil(bounds.maxY) > mask.maxY
        }

        private func selectedPresentation(in scene: GPUIScene, selected: Set<Reference>?) -> [Reference]? {
            for layer in scene.layers {
                guard inspect(layer.paintOperations.count) else { return nil }
                for operation in layer.paintOperations {
                    let count: Int
                    switch operation.kind {
                    case .shadow: count = layer.shadows.count
                    case .quad: count = layer.quads.count
                    case .glyph: count = layer.glyphs.count
                    case .pixelGlyph: count = layer.pixelGlyphs.count
                    case .image: count = layer.images.count
                    case .path: count = layer.paths.count
                    }
                    guard operation.startIndex >= 0, operation.count > 0,
                        operation.count <= count, operation.startIndex <= count - operation.count,
                        inspect(operation.count)
                    else { return nil }
                }
            }
            var result: [Reference] = []
            var seen: Set<Reference> = []
            for run in scene.presentationOrder() {
                for index in run.range {
                    let reference = Reference(layer: run.layerIndex, kind: run.kind, index: index)
                    guard selected?.contains(reference) != false else { continue }
                    // Normal painter output presents each address once. Refuse
                    // malformed duplicate occurrences instead of dropping one.
                    guard seen.insert(reference).inserted, result.count < maximumRecordCount else { return nil }
                    result.append(reference)
                }
            }
            guard selected.map({ $0 == seen }) ?? true else { return nil }
            return result
        }

        private func append(_ primitive: GPUIScenePrimitive, to scene: inout GPUIScene, layer: Int) -> Bool {
            let before = scene.paintRecordCount
            switch primitive {
            case .shadow(let value): scene.addShadow(value, toLayer: layer)
            case .quad(let value): scene.addQuad(value, toLayer: layer)
            case .glyph(let value): scene.addGlyph(value, toLayer: layer)
            case .pixelGlyph(let value): scene.addPixelGlyph(value, toLayer: layer)
            case .image(let value): scene.addImage(value, toLayer: layer)
            case .path(let value): scene.addPath(value, toLayer: layer)
            }
            guard scene.paintRecordCount == before + 1,
                let last = scene.paintRecords.last,
                case .primitive(let actualLayer, let kind, let index) = last
            else { return false }
            // Hand-built malformed primitives must not become altered pixels
            // merely because add* sanitized them during extraction.
            return scene.primitive(kind: kind, inLayer: actualLayer, at: index) == primitive
        }

        private func freeze(_ bitmap: BitmapSurface) -> BitmapSurface? {
            guard validSurface(IntSize(width: bitmap.width, height: bitmap.height)) else { return nil }
            do { try bitmap.validate() } catch { return nil }
            if let existing = bitmaps[bitmap.contentKey] { return existing }
            guard chargeBytes(bitmap.pixels.count) else { return nil }
            var frozen = bitmap
            if copyResourceBytes { frozen.pixels = ownedBytes(bitmap.pixels) }
            bitmaps[bitmap.contentKey] = frozen
            return frozen
        }

        private func freeze(_ atlas: GlyphAtlasSnapshot, preservingUpdate: Bool = false) -> GlyphAtlasSnapshot? {
            guard validSurface(IntSize(width: atlas.width, height: atlas.height)) else { return nil }
            let required = Int64(atlas.width) * Int64(atlas.height) * 4
            guard required <= Int64(atlas.pixels.count) else { return nil }
            let key = AtlasKey(version: atlas.contentVersion, width: atlas.width, height: atlas.height)
            if atlas.contentVersion != 0, var existing = atlases[key] {
                guard existing.pixels == atlas.pixels else { return nil }
                if preservingUpdate { existing.update = atlas.update }
                return existing
            }
            guard chargeBytes(atlas.pixels.count), chargeBytes(MemoryLayout<GlyphAtlasSnapshot>.stride) else {
                return nil
            }
            var frozen = atlas
            if copyResourceBytes { frozen.pixels = ownedBytes(atlas.pixels) }
            // A frozen source makes no dirty-region claim about a live atlas.
            // Known versions can still share an exact already-uploaded texture.
            frozen.update = atlas.contentVersion == 0 ? .full : .unchanged
            if atlas.contentVersion != 0 { atlases[key] = frozen }
            if preservingUpdate { frozen.update = atlas.update }
            return frozen
        }

        private func ownedBytes(_ data: Data) -> Data {
            // Data can borrow mutable external memory or a custom deallocator.
            // Retired paint owns ordinary immutable byte storage, not that owner.
            data.withUnsafeBytes { bytes in
                guard let address = bytes.baseAddress, !bytes.isEmpty else { return Data() }
                return Data(bytes: address, count: bytes.count)
            }
        }

        private func charge(_ primitive: GPUIScenePrimitive) -> Bool {
            guard recordCount < maximumRecordCount,
                chargeBytes(MemoryLayout<GPUIScenePaintRecord>.stride),
                chargeBytes(MemoryLayout<GPUIPaintOperation>.stride)
            else { return false }
            recordCount += 1
            switch primitive {
            case .shadow: return chargeBytes(MemoryLayout<ShadowPrimitive>.stride)
            case .quad: return chargeBytes(MemoryLayout<QuadPrimitive>.stride)
            case .glyph, .pixelGlyph: return chargeBytes(MemoryLayout<GlyphPrimitive>.stride)
            case .image: return chargeBytes(MemoryLayout<ImagePrimitive>.stride)
            case .path(let path):
                return chargeBytes(MemoryLayout<PathPrimitive>.stride)
                    && chargeArray(path.elements.capacity, stride: MemoryLayout<PathElement>.stride)
                    && chargeArray(path.fillGradient?.stops.capacity ?? 0, stride: MemoryLayout<GradientStop>.stride)
                    && chargeArray(path.strokeGradient?.stops.capacity ?? 0, stride: MemoryLayout<GradientStop>.stride)
            }
        }

        private func chargeSparePrimitiveCapacity(in layer: GPUILayer) -> Bool {
            chargeArray(layer.shadows.capacity - layer.shadows.count, stride: MemoryLayout<ShadowPrimitive>.stride)
                && chargeArray(layer.quads.capacity - layer.quads.count, stride: MemoryLayout<QuadPrimitive>.stride)
                && chargeArray(layer.glyphs.capacity - layer.glyphs.count, stride: MemoryLayout<GlyphPrimitive>.stride)
                && chargeArray(
                    layer.pixelGlyphs.capacity - layer.pixelGlyphs.count, stride: MemoryLayout<GlyphPrimitive>.stride)
                && chargeArray(layer.images.capacity - layer.images.count, stride: MemoryLayout<ImagePrimitive>.stride)
                && chargeArray(layer.paths.capacity - layer.paths.count, stride: MemoryLayout<PathPrimitive>.stride)
        }

        private func chargeArray(_ count: Int, stride: Int) -> Bool {
            guard count >= 0, stride > 0, count <= maximumResourceBytes / stride else { return false }
            return chargeBytes(count * stride)
        }

        private func chargeBytes(_ count: Int) -> Bool {
            guard count >= 0, count <= maximumResourceBytes - resourceBytes else { return false }
            resourceBytes += count
            return true
        }

        private func inspect(_ count: Int) -> Bool {
            guard count >= 0, count <= maximumInspectedEntries - inspectedEntries else { return false }
            inspectedEntries += count
            return true
        }
    }
}
