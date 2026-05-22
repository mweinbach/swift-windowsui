import Foundation

// MARK: - GPUILayer

import SwiftWindowsCore

/// A rendering layer containing typed, contiguous primitive arrays.
/// `paintOperations` preserves the source paint order across primitive families
/// while sidecar draw-order metadata enables Zed-style sorted batching.

// MARK: - GPUIScene

/// Top-level GPUI-style scene container that organizes primitives by type into
/// contiguous arrays within layers. This structure replaces the flat
/// `[RenderCommand]` list with typed arrays suitable for instanced draw calls.

public enum GPUIPaintPrimitiveKind: Equatable, Sendable {
    case shadow
    case quad
    case glyph
    case pixelGlyph
    case image
    case path
}
public struct GPUIPaintOperation: Equatable, Sendable {
    public var kind: GPUIPaintPrimitiveKind
    public var startIndex: Int
    public var count: Int

    public init(kind: GPUIPaintPrimitiveKind, startIndex: Int, count: Int = 1) {
        self.kind = kind
        self.startIndex = startIndex
        self.count = count
    }
}
public enum GPUIScenePrimitive: Equatable, Sendable {
    case shadow(ShadowPrimitive)
    case quad(QuadPrimitive)
    case glyph(GlyphPrimitive)
    case pixelGlyph(GlyphPrimitive)
    case image(ImagePrimitive)
    case path(PathPrimitive)
}
public enum GPUIScenePaintRecord: Equatable, Sendable {
    case primitive(layerIndex: Int, primitive: GPUIScenePrimitive)
    case startLayer(layerIndex: Int, bounds: Rect)
    case endLayer(layerIndex: Int)
}
public struct GlyphAtlasRegion: Equatable, Sendable {
    public var x: Int32
    public var y: Int32
    public var width: Int32
    public var height: Int32

    public init(x: Int32, y: Int32, width: Int32, height: Int32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
public struct GlyphAtlasSnapshot: Equatable, Sendable {
    public var width: Int32
    public var height: Int32
    public var pixels: Data
    public var dirtyRegion: GlyphAtlasRegion?

    public init(width: Int32, height: Int32, pixels: Data, dirtyRegion: GlyphAtlasRegion? = nil) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.dirtyRegion = dirtyRegion
    }
}
public struct ImageResourceBinding: Equatable, Sendable {
    public var textureID: Int32
    public var bitmap: BitmapSurface

    public init(textureID: Int32, bitmap: BitmapSurface) {
        self.textureID = textureID
        self.bitmap = bitmap
    }
}
public struct GPUILayer: Equatable, Sendable {
    public var shadows: [ShadowPrimitive]
    public var quads: [QuadPrimitive]
    public var glyphs: [GlyphPrimitive]
    public var pixelGlyphs: [GlyphPrimitive]
    public var images: [ImagePrimitive]
    public var paths: [PathPrimitive]
    public var paintOperations: [GPUIPaintOperation]

    private var shadowOrderings: [GPUIPrimitiveOrdering]
    private var quadOrderings: [GPUIPrimitiveOrdering]
    private var glyphOrderings: [GPUIPrimitiveOrdering]
    private var pixelGlyphOrderings: [GPUIPrimitiveOrdering]
    private var imageOrderings: [GPUIPrimitiveOrdering]
    private var pathOrderings: [GPUIPrimitiveOrdering]
    private var primitiveBounds = GPUIBoundsTree()
    private var layerStack: [GPUIDrawOrder] = []
    private var nextPaintIndex: UInt32 = 0
    private var maxAssignedOrder: GPUIDrawOrder = 0

    public init(
        shadows: [ShadowPrimitive] = [],
        quads: [QuadPrimitive] = [],
        glyphs: [GlyphPrimitive] = [],
        pixelGlyphs: [GlyphPrimitive] = [],
        images: [ImagePrimitive] = [],
        paths: [PathPrimitive] = [],
        paintOperations: [GPUIPaintOperation] = []
    ) {
        self.shadows = shadows
        self.quads = quads
        self.glyphs = glyphs
        self.pixelGlyphs = pixelGlyphs
        self.images = images
        self.paths = paths
        self.paintOperations = paintOperations
        self.shadowOrderings = shadows.indices.map {
            GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0))
        }
        self.quadOrderings = quads.indices.map {
            GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0))
        }
        self.glyphOrderings = glyphs.indices.map {
            GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0))
        }
        self.pixelGlyphOrderings = pixelGlyphs.indices.map {
            GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0))
        }
        self.imageOrderings = images.indices.map {
            GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0))
        }
        self.pathOrderings = paths.indices.map {
            GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0))
        }
        self.nextPaintIndex = UInt32(
            shadows.count + quads.count + glyphs.count + pixelGlyphs.count + images.count + paths.count)
    }

    public var primitiveCount: Int {
        shadows.count + quads.count + glyphs.count + pixelGlyphs.count + images.count + paths.count
    }

    public var isEmpty: Bool {
        primitiveCount == 0
    }

    public var paintOperationCount: Int {
        paintOperations.count
    }

    public mutating func pushScopedLayer(_ bounds: Rect) -> Bool {
        guard !bounds.isEmpty else {
            return false
        }

        let order = primitiveBounds.insert(bounds)
        maxAssignedOrder = max(maxAssignedOrder, order)
        layerStack.append(order)
        return true
    }

    public mutating func popScopedLayer() -> Bool {
        layerStack.popLast() != nil
    }

    mutating func addShadow(_ shadow: ShadowPrimitive) -> Bool {
        guard let maskedBounds = shadow.contentMaskedBounds else {
            return false
        }

        let startIndex = shadows.count
        shadows.append(shadow)
        shadowOrderings.append(reserveOrdering(for: maskedBounds, primitiveIndex: startIndex))
        appendPaintOperation(kind: .shadow, startIndex: startIndex)
        return true
    }

    mutating func addQuad(_ quad: QuadPrimitive) -> Bool {
        guard let maskedBounds = quad.contentMaskedBounds else {
            return false
        }

        let startIndex = quads.count
        quads.append(quad)
        quadOrderings.append(reserveOrdering(for: maskedBounds, primitiveIndex: startIndex))
        appendPaintOperation(kind: .quad, startIndex: startIndex)
        return true
    }

    mutating func addGlyph(_ glyph: GlyphPrimitive) -> Bool {
        guard let maskedBounds = glyph.contentMaskedBounds else {
            return false
        }

        let startIndex = glyphs.count
        glyphs.append(glyph)
        glyphOrderings.append(reserveOrdering(for: maskedBounds, primitiveIndex: startIndex))
        appendPaintOperation(kind: .glyph, startIndex: startIndex)
        return true
    }

    mutating func addPixelGlyph(_ glyph: GlyphPrimitive) -> Bool {
        guard let maskedBounds = glyph.contentMaskedBounds else {
            return false
        }

        let startIndex = pixelGlyphs.count
        pixelGlyphs.append(glyph)
        pixelGlyphOrderings.append(reserveOrdering(for: maskedBounds, primitiveIndex: startIndex))
        appendPaintOperation(kind: .pixelGlyph, startIndex: startIndex)
        return true
    }

    mutating func addImage(_ image: ImagePrimitive) -> Bool {
        guard let maskedBounds = image.contentMaskedBounds else {
            return false
        }

        let startIndex = images.count
        images.append(image)
        imageOrderings.append(reserveOrdering(for: maskedBounds, primitiveIndex: startIndex))
        appendPaintOperation(kind: .image, startIndex: startIndex)
        return true
    }

    mutating func addPath(_ path: PathPrimitive) -> Bool {
        guard let maskedBounds = path.contentMaskedBounds else {
            return false
        }

        let startIndex = paths.count
        paths.append(path)
        pathOrderings.append(reserveOrdering(for: maskedBounds, primitiveIndex: startIndex))
        appendPaintOperation(kind: .path, startIndex: startIndex)
        return true
    }

    public mutating func finish() {
        let shadowIndexMap = Self.sortFamily(&shadows, orderings: &shadowOrderings)
        let quadIndexMap = Self.sortFamily(&quads, orderings: &quadOrderings)
        let glyphIndexMap = Self.sortFamily(&glyphs, orderings: &glyphOrderings)
        let pixelGlyphIndexMap = Self.sortFamily(&pixelGlyphs, orderings: &pixelGlyphOrderings)
        let imageIndexMap = Self.sortFamily(&images, orderings: &imageOrderings)
        let pathIndexMap = Self.sortFamily(&paths, orderings: &pathOrderings)

        remapPaintOperations(
            shadowIndexMap: shadowIndexMap,
            quadIndexMap: quadIndexMap,
            glyphIndexMap: glyphIndexMap,
            pixelGlyphIndexMap: pixelGlyphIndexMap,
            imageIndexMap: imageIndexMap,
            pathIndexMap: pathIndexMap
        )
    }

    public func orderedBatches() -> GPUILayerBatchIterator {
        GPUILayerBatchIterator(
            shadowOrderings: shadowOrderings,
            quadOrderings: quadOrderings,
            glyphOrderings: glyphOrderings,
            pixelGlyphOrderings: pixelGlyphOrderings,
            imageOrderings: imageOrderings,
            pathOrderings: pathOrderings
        )
    }

    private mutating func appendPaintOperation(kind: GPUIPaintPrimitiveKind, startIndex: Int) {
        Self.appendPaintOperation(kind: kind, startIndex: startIndex, to: &paintOperations)
    }

    private mutating func reserveOrdering(for bounds: Rect?, primitiveIndex: Int) -> GPUIPrimitiveOrdering {
        let order: GPUIDrawOrder
        if let scopedOrder = layerStack.last {
            order = scopedOrder
        } else if let bounds, !bounds.isEmpty {
            order = primitiveBounds.insert(bounds)
        } else {
            order = maxAssignedOrder &+ 1
        }

        maxAssignedOrder = max(maxAssignedOrder, order)
        let ordering = GPUIPrimitiveOrdering(
            primitiveIndex: primitiveIndex,
            order: order,
            paintIndex: nextPaintIndex
        )
        nextPaintIndex &+= 1
        return ordering
    }

    private static func sortFamily<T>(_ primitives: inout [T], orderings: inout [GPUIPrimitiveOrdering]) -> [Int] {
        var oldIndexToNewIndex = Array(primitives.indices)
        guard primitives.count == orderings.count, primitives.count > 1 else {
            for index in orderings.indices {
                orderings[index].primitiveIndex = index
            }
            return oldIndexToNewIndex
        }

        let sortedEntries = orderings.enumerated().sorted { lhs, rhs in
            let lhsOrdering = lhs.element
            let rhsOrdering = rhs.element
            if lhsOrdering.order != rhsOrdering.order {
                return lhsOrdering.order < rhsOrdering.order
            }
            if lhsOrdering.paintIndex != rhsOrdering.paintIndex {
                return lhsOrdering.paintIndex < rhsOrdering.paintIndex
            }
            return lhs.offset < rhs.offset
        }

        var sortedPrimitives: [T] = []
        sortedPrimitives.reserveCapacity(primitives.count)
        var sortedOrderings: [GPUIPrimitiveOrdering] = []
        sortedOrderings.reserveCapacity(orderings.count)

        for (newIndex, entry) in sortedEntries.enumerated() {
            sortedPrimitives.append(primitives[entry.offset])
            var ordering = entry.element
            ordering.primitiveIndex = newIndex
            sortedOrderings.append(ordering)
            oldIndexToNewIndex[entry.offset] = newIndex
        }

        primitives = sortedPrimitives
        orderings = sortedOrderings
        return oldIndexToNewIndex
    }

    private mutating func remapPaintOperations(
        shadowIndexMap: [Int],
        quadIndexMap: [Int],
        glyphIndexMap: [Int],
        pixelGlyphIndexMap: [Int],
        imageIndexMap: [Int],
        pathIndexMap: [Int]
    ) {
        var remappedOperations: [GPUIPaintOperation] = []
        remappedOperations.reserveCapacity(paintOperations.count)

        for operation in paintOperations {
            let indexMap: [Int]
            switch operation.kind {
            case .shadow:
                indexMap = shadowIndexMap
            case .quad:
                indexMap = quadIndexMap
            case .glyph:
                indexMap = glyphIndexMap
            case .pixelGlyph:
                indexMap = pixelGlyphIndexMap
            case .image:
                indexMap = imageIndexMap
            case .path:
                indexMap = pathIndexMap
            }

            let upperBound = operation.startIndex + operation.count
            guard operation.startIndex >= 0, upperBound <= indexMap.count else {
                continue
            }

            for oldIndex in operation.startIndex..<upperBound {
                Self.appendPaintOperation(
                    kind: operation.kind,
                    startIndex: indexMap[oldIndex],
                    to: &remappedOperations
                )
            }
        }

        paintOperations = remappedOperations
    }

    private static func appendPaintOperation(
        kind: GPUIPaintPrimitiveKind,
        startIndex: Int,
        to paintOperations: inout [GPUIPaintOperation]
    ) {
        guard var lastOperation = paintOperations.last else {
            paintOperations.append(GPUIPaintOperation(kind: kind, startIndex: startIndex))
            return
        }

        let expectedNextIndex = lastOperation.startIndex + lastOperation.count
        if lastOperation.kind == kind, expectedNextIndex == startIndex {
            lastOperation.count += 1
            paintOperations[paintOperations.count - 1] = lastOperation
            return
        }

        paintOperations.append(GPUIPaintOperation(kind: kind, startIndex: startIndex))
    }

    public static func == (lhs: GPUILayer, rhs: GPUILayer) -> Bool {
        lhs.shadows == rhs.shadows && lhs.quads == rhs.quads && lhs.glyphs == rhs.glyphs
            && lhs.pixelGlyphs == rhs.pixelGlyphs && lhs.images == rhs.images && lhs.paths == rhs.paths
            && lhs.paintOperations == rhs.paintOperations
    }
}
/// Per-scene paint metrics. Tracks GPU-vs-CPU rendering decisions made
/// during scene painting so apps can observe how often paths take the
/// GPU fast lane (PathToQuadTessellator promotion) vs the CPU
/// rasterization fallback. Updated by the scene painter as it emits
/// primitives.
public struct ScenePaintMetrics: Equatable, Sendable {
    /// Path primitives that fell through to the CPU rasterizer.
    public var pathsRasterizedOnCPU: Int = 0
    /// Path primitives that the tessellator promoted to GPU quads.
    public var pathsPromotedToGPU: Int = 0
    /// Total quad instances emitted by GPU-promoted paths (one path can
    /// produce multiple quads — e.g. a closed stroked rect emits 4).
    public var quadInstancesFromPromotedPaths: Int = 0

    public init() {}

    /// GPU promotion rate in [0, 1]. Returns 1.0 when there were no
    /// paths in the scene (nothing to demote).
    public var gpuPromotionRate: Double {
        let total = pathsRasterizedOnCPU + pathsPromotedToGPU
        guard total > 0 else { return 1.0 }
        return Double(pathsPromotedToGPU) / Double(total)
    }
}

public struct GPUIScene: Equatable, Sendable {
    public var clearColor: Color
    public var layers: [GPUILayer]
    public var paintRecords: [GPUIScenePaintRecord]
    public var glyphAtlas: GlyphAtlasSnapshot?
    public var pixelGlyphAtlas: GlyphAtlasSnapshot?
    public var imageResources: [ImageResourceBinding]
    /// Paint-time observability counters (CPU vs GPU path routing).
    public var paintMetrics: ScenePaintMetrics = ScenePaintMetrics()
    private var isFinished = false

    public init(
        clearColor: Color = .black,
        glyphAtlas: GlyphAtlasSnapshot? = nil,
        pixelGlyphAtlas: GlyphAtlasSnapshot? = nil,
        imageResources: [ImageResourceBinding] = []
    ) {
        self.clearColor = clearColor
        self.layers = [GPUILayer()]
        self.paintRecords = []
        self.glyphAtlas = glyphAtlas
        self.pixelGlyphAtlas = pixelGlyphAtlas
        self.imageResources = imageResources
    }

    // MARK: - Layer management

    /// Push a new empty layer onto the stack.
    @discardableResult
    public mutating func pushLayer() -> Int {
        layers.append(GPUILayer())
        isFinished = false
        return layers.count - 1
    }

    /// Ensures the scene contains a layer for the given index.
    public mutating func ensureLayer(_ layerIndex: Int) {
        guard layerIndex >= 0 else {
            return
        }

        while layers.count <= layerIndex {
            layers.append(GPUILayer())
        }
        isFinished = false
    }

    public mutating func pushScopedLayer(_ bounds: Rect, toLayer layerIndex: Int) {
        ensureLayer(layerIndex)
        if layers[layerIndex].pushScopedLayer(bounds) {
            paintRecords.append(.startLayer(layerIndex: layerIndex, bounds: bounds))
            isFinished = false
        }
    }

    @discardableResult
    public mutating func registerImageResource(_ bitmap: BitmapSurface) -> Int32 {
        if let existing = imageResources.first(where: { $0.bitmap == bitmap }) {
            return existing.textureID
        }

        let nextTextureID = (imageResources.map(\.textureID).max() ?? -1) + 1
        imageResources.append(ImageResourceBinding(textureID: nextTextureID, bitmap: bitmap))
        return nextTextureID
    }

    public mutating func bindImageResource(_ bitmap: BitmapSurface, for textureID: Int32) {
        guard textureID >= 0 else {
            return
        }

        if let index = imageResources.firstIndex(where: { $0.textureID == textureID }) {
            imageResources[index].bitmap = bitmap
            return
        }

        imageResources.append(ImageResourceBinding(textureID: textureID, bitmap: bitmap))
    }

    public mutating func popScopedLayer(fromLayer layerIndex: Int) {
        ensureLayer(layerIndex)
        if layers[layerIndex].popScopedLayer() {
            paintRecords.append(.endLayer(layerIndex: layerIndex))
            isFinished = false
        }
    }

    // MARK: - Primitive insertion (appends to last layer)

    public mutating func addQuad(_ quad: QuadPrimitive) {
        addQuad(quad, toLayer: layers.count - 1)
    }

    public mutating func addGlyph(_ glyph: GlyphPrimitive) {
        addGlyph(glyph, toLayer: layers.count - 1)
    }

    public mutating func addImage(_ image: ImagePrimitive) {
        addImage(image, toLayer: layers.count - 1)
    }

    public mutating func addShadow(_ shadow: ShadowPrimitive) {
        addShadow(shadow, toLayer: layers.count - 1)
    }

    public mutating func addPixelGlyph(_ glyph: GlyphPrimitive) {
        addPixelGlyph(glyph, toLayer: layers.count - 1)
    }

    public mutating func addQuad(_ quad: QuadPrimitive, toLayer layerIndex: Int) {
        ensureLayer(layerIndex)
        if layers[layerIndex].addQuad(quad) {
            paintRecords.append(.primitive(layerIndex: layerIndex, primitive: .quad(quad)))
            isFinished = false
        }
    }

    public mutating func addGlyph(_ glyph: GlyphPrimitive, toLayer layerIndex: Int) {
        ensureLayer(layerIndex)
        if layers[layerIndex].addGlyph(glyph) {
            paintRecords.append(.primitive(layerIndex: layerIndex, primitive: .glyph(glyph)))
            isFinished = false
        }
    }

    public mutating func addImage(_ image: ImagePrimitive, toLayer layerIndex: Int) {
        ensureLayer(layerIndex)
        if layers[layerIndex].addImage(image) {
            paintRecords.append(.primitive(layerIndex: layerIndex, primitive: .image(image)))
            isFinished = false
        }
    }

    public mutating func addShadow(_ shadow: ShadowPrimitive, toLayer layerIndex: Int) {
        ensureLayer(layerIndex)
        if layers[layerIndex].addShadow(shadow) {
            paintRecords.append(.primitive(layerIndex: layerIndex, primitive: .shadow(shadow)))
            isFinished = false
        }
    }

    public mutating func addPixelGlyph(_ glyph: GlyphPrimitive, toLayer layerIndex: Int) {
        ensureLayer(layerIndex)
        if layers[layerIndex].addPixelGlyph(glyph) {
            paintRecords.append(.primitive(layerIndex: layerIndex, primitive: .pixelGlyph(glyph)))
            isFinished = false
        }
    }

    public mutating func addPath(_ path: PathPrimitive, toLayer layerIndex: Int) {
        ensureLayer(layerIndex)
        if layers[layerIndex].addPath(path) {
            paintRecords.append(.primitive(layerIndex: layerIndex, primitive: .path(path)))
            isFinished = false
        }
    }

    /// Represents the result of a replay operation.
    public enum GPUISceneReplayResult: Equatable, Sendable {
        /// Replay succeeded and reconstructed equivalent scene content.
        case success
        /// Replay was rejected because the range is structurally unbalanced.
        /// Contains details about the validation failure.
        case unbalanced(layerIndex: Int?, depth: Int, reason: UnbalancedReason)

        /// Reason why a range is unbalanced.
        public enum UnbalancedReason: Equatable, Sendable {
            /// Range starts inside a scoped layer without the matching startLayer marker.
            case startsInsideScope
            /// Range ends inside a scoped layer without the matching endLayer marker.
            case endsInsideScope
            /// Layer stack depth mismatch at end of replay.
            case depthMismatch
        }
    }

    public mutating func replay(_ range: Range<Int>, from previousScene: GPUIScene) -> GPUISceneReplayResult {
        // Validate that the range is structurally balanced
        let validation = validateReplayRange(range, in: previousScene)
        guard validation.isBalanced else {
            return .unbalanced(
                layerIndex: validation.layerIndex,
                depth: validation.depth,
                reason: validation.reason!
            )
        }

        for binding in previousScene.imageResources {
            bindImageResource(binding.bitmap, for: binding.textureID)
        }

        for record in previousScene.paintRecords[range] {
            switch record {
            case .primitive(let layerIndex, let primitive):
                switch primitive {
                case .shadow(let shadow):
                    addShadow(shadow, toLayer: layerIndex)
                case .quad(let quad):
                    addQuad(quad, toLayer: layerIndex)
                case .glyph(let glyph):
                    addGlyph(glyph, toLayer: layerIndex)
                case .pixelGlyph(let glyph):
                    addPixelGlyph(glyph, toLayer: layerIndex)
                case .image(let image):
                    addImage(image, toLayer: layerIndex)
                case .path(let path):
                    addPath(path, toLayer: layerIndex)
                }
            case .startLayer(let layerIndex, let bounds):
                pushScopedLayer(bounds, toLayer: layerIndex)
            case .endLayer(let layerIndex):
                popScopedLayer(fromLayer: layerIndex)
            }
        }

        return .success
    }

    /// Validates that a replay range is structurally balanced.
    /// A balanced range has matching startLayer/endLayer markers for each layer,
    /// AND the range must start at depth 0 (no unclosed scoped layers before the range).
    private func validateReplayRange(_ range: Range<Int>, in scene: GPUIScene) -> (
        isBalanced: Bool,
        layerIndex: Int?,
        depth: Int,
        reason: GPUISceneReplayResult.UnbalancedReason?
    ) {
        // Calculate the scoped-layer depth at the start of the range
        // by scanning records before range.lowerBound
        var initialLayerDepths: [Int: Int] = [:]
        var maxLayerIndex = -1

        for recordIndex in 0..<range.lowerBound {
            let record = scene.paintRecords[recordIndex]
            switch record {
            case .startLayer(let layerIndex, _):
                initialLayerDepths[layerIndex, default: 0] += 1
                maxLayerIndex = max(maxLayerIndex, layerIndex)
            case .endLayer(let layerIndex):
                initialLayerDepths[layerIndex, default: 0] -= 1
                maxLayerIndex = max(maxLayerIndex, layerIndex)
            case .primitive(let layerIndex, _):
                maxLayerIndex = max(maxLayerIndex, layerIndex)
            }
        }

        // Check if any layer has non-zero depth at the range boundary
        // This means the range starts inside a scoped layer without its marker
        for (layerIndex, depth) in initialLayerDepths {
            if depth != 0 {
                return (false, layerIndex, depth, .startsInsideScope)
            }
        }

        // Track per-layer scope depth within the range
        var layerDepths: [Int: Int] = [:]

        // First pass: check for starting inside a scope and track depths
        for record in scene.paintRecords[range] {
            switch record {
            case .startLayer(let layerIndex, _):
                layerDepths[layerIndex, default: 0] += 1
                maxLayerIndex = max(maxLayerIndex, layerIndex)
            case .endLayer(let layerIndex):
                layerDepths[layerIndex, default: 0] -= 1
                maxLayerIndex = max(maxLayerIndex, layerIndex)
                // If we pop below zero, we started inside a scope
                if layerDepths[layerIndex]! < 0 {
                    return (false, layerIndex, -1, .startsInsideScope)
                }
            case .primitive(let layerIndex, _):
                maxLayerIndex = max(maxLayerIndex, layerIndex)
            }
        }

        // Check that all layers end at depth 0
        for (layerIndex, depth) in layerDepths {
            if depth != 0 {
                let reason: GPUISceneReplayResult.UnbalancedReason =
                    depth > 0
                    ? .endsInsideScope
                    : .depthMismatch
                return (false, layerIndex, depth, reason)
            }
        }

        return (true, nil, 0, nil)
    }

    public var paintRecordCount: Int {
        paintRecords.count
    }

    public mutating func finish() {
        guard !isFinished else {
            return
        }

        for index in layers.indices {
            layers[index].finish()
        }
        isFinished = true
    }

    public var primitiveCount: Int {
        layers.reduce(0) { $0 + $1.primitiveCount }
    }

    public var totalPrimitiveCount: Int {
        primitiveCount
    }

    public static func == (lhs: GPUIScene, rhs: GPUIScene) -> Bool {
        lhs.clearColor == rhs.clearColor && lhs.layers == rhs.layers && lhs.paintRecords == rhs.paintRecords
            && lhs.glyphAtlas == rhs.glyphAtlas && lhs.pixelGlyphAtlas == rhs.pixelGlyphAtlas
            && lhs.imageResources == rhs.imageResources
    }
}
extension QuadPrimitive {
    fileprivate var contentMaskedBounds: Rect? {
        guard width > 0, height > 0 else {
            return nil
        }

        let bounds = Rect(x: Double(x), y: Double(y), width: Double(width), height: Double(height))

        // Check for zero-dimension effective clip: one dimension is 0, the other is > 0
        // If both are 0, it means "no clip" (unclipped). If both are > 0, it's a normal clip.
        let hasExplicitZeroDimensionClip = (clipWidth == 0 && clipHeight > 0) || (clipWidth > 0 && clipHeight == 0)
        guard !hasExplicitZeroDimensionClip else {
            return nil
        }

        guard let maskBounds = contentMask.bounds else {
            return bounds
        }
        guard let masked = bounds.intersected(with: maskBounds) else {
            return nil
        }
        // Reject if masked bounds are empty (zero width or height)
        guard masked.size.width > 0, masked.size.height > 0 else {
            return nil
        }
        return masked
    }
}
extension GlyphPrimitive {
    fileprivate var contentMaskedBounds: Rect? {
        guard screenW > 0, screenH > 0 else {
            return nil
        }

        let bounds = Rect(x: Double(screenX), y: Double(screenY), width: Double(screenW), height: Double(screenH))

        // Check for zero-dimension effective clip: one dimension is 0, the other is > 0
        let hasExplicitZeroDimensionClip = (clipWidth == 0 && clipHeight > 0) || (clipWidth > 0 && clipHeight == 0)
        guard !hasExplicitZeroDimensionClip else {
            return nil
        }

        guard let maskBounds = contentMask.bounds else {
            return bounds
        }
        guard let masked = bounds.intersected(with: maskBounds) else {
            return nil
        }
        // Reject if masked bounds are empty (zero width or height)
        guard masked.size.width > 0, masked.size.height > 0 else {
            return nil
        }
        return masked
    }
}
extension ImagePrimitive {
    fileprivate var contentMaskedBounds: Rect? {
        guard screenW > 0, screenH > 0 else {
            return nil
        }

        let bounds = Rect(x: Double(screenX), y: Double(screenY), width: Double(screenW), height: Double(screenH))

        // Check for zero-dimension effective clip: one dimension is 0, the other is > 0
        let hasExplicitZeroDimensionClip = (clipWidth == 0 && clipHeight > 0) || (clipWidth > 0 && clipHeight == 0)
        guard !hasExplicitZeroDimensionClip else {
            return nil
        }

        guard let maskBounds = contentMask.bounds else {
            return bounds
        }
        guard let masked = bounds.intersected(with: maskBounds) else {
            return nil
        }
        // Reject if masked bounds are empty (zero width or height)
        guard masked.size.width > 0, masked.size.height > 0 else {
            return nil
        }
        return masked
    }
}
extension ShadowPrimitive {
    fileprivate var contentMaskedBounds: Rect? {
        guard width > 0, height > 0 else {
            return nil
        }

        let bounds = Rect(x: Double(x), y: Double(y), width: Double(width), height: Double(height))

        // Check for zero-dimension effective clip: one dimension is 0, the other is > 0
        let hasExplicitZeroDimensionClip = (clipWidth == 0 && clipHeight > 0) || (clipWidth > 0 && clipHeight == 0)
        guard !hasExplicitZeroDimensionClip else {
            return nil
        }

        guard let maskBounds = contentMask.bounds else {
            return bounds
        }
        guard let masked = bounds.intersected(with: maskBounds) else {
            return nil
        }
        // Reject if masked bounds are empty (zero width or height)
        guard masked.size.width > 0, masked.size.height > 0 else {
            return nil
        }
        return masked
    }
}
