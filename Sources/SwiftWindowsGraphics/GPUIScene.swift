import Foundation
import SwiftWindowsCore

// MARK: - GPUILayer

public enum GPUIPaintPrimitiveKind: Equatable, Sendable {
    case shadow
    case quad
    case glyph
    case pixelGlyph
    case image
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

/// A rendering layer containing typed, contiguous primitive arrays.
/// `paintOperations` preserves the source paint order across primitive families
/// while sidecar draw-order metadata enables Zed-style sorted batching.
public struct GPUILayer: Equatable, Sendable {
    public var shadows: [ShadowPrimitive]
    public var quads: [QuadPrimitive]
    public var glyphs: [GlyphPrimitive]
    public var pixelGlyphs: [GlyphPrimitive]
    public var images: [ImagePrimitive]
    public var paintOperations: [GPUIPaintOperation]

    private var shadowOrderings: [GPUIPrimitiveOrdering]
    private var quadOrderings: [GPUIPrimitiveOrdering]
    private var glyphOrderings: [GPUIPrimitiveOrdering]
    private var pixelGlyphOrderings: [GPUIPrimitiveOrdering]
    private var imageOrderings: [GPUIPrimitiveOrdering]
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
        paintOperations: [GPUIPaintOperation] = []
    ) {
        self.shadows = shadows
        self.quads = quads
        self.glyphs = glyphs
        self.pixelGlyphs = pixelGlyphs
        self.images = images
        self.paintOperations = paintOperations
        self.shadowOrderings = shadows.indices.map { GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0)) }
        self.quadOrderings = quads.indices.map { GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0)) }
        self.glyphOrderings = glyphs.indices.map { GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0)) }
        self.pixelGlyphOrderings = pixelGlyphs.indices.map { GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0)) }
        self.imageOrderings = images.indices.map { GPUIPrimitiveOrdering(primitiveIndex: $0, order: 0, paintIndex: UInt32($0)) }
        self.nextPaintIndex = UInt32(shadows.count + quads.count + glyphs.count + pixelGlyphs.count + images.count)
    }

    public var primitiveCount: Int {
        shadows.count + quads.count + glyphs.count + pixelGlyphs.count + images.count
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

    public mutating func finish() {
        Self.sortFamily(&shadows, orderings: &shadowOrderings)
        Self.sortFamily(&quads, orderings: &quadOrderings)
        Self.sortFamily(&glyphs, orderings: &glyphOrderings)
        Self.sortFamily(&pixelGlyphs, orderings: &pixelGlyphOrderings)
        Self.sortFamily(&images, orderings: &imageOrderings)
    }

    public func orderedBatches() -> GPUILayerBatchIterator {
        GPUILayerBatchIterator(
            shadowOrderings: shadowOrderings,
            quadOrderings: quadOrderings,
            glyphOrderings: glyphOrderings,
            pixelGlyphOrderings: pixelGlyphOrderings,
            imageOrderings: imageOrderings
        )
    }

    private mutating func appendPaintOperation(kind: GPUIPaintPrimitiveKind, startIndex: Int) {
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

    private static func sortFamily<T>(_ primitives: inout [T], orderings: inout [GPUIPrimitiveOrdering]) {
        guard primitives.count == orderings.count, primitives.count > 1 else {
            for index in orderings.indices {
                orderings[index].primitiveIndex = index
            }
            return
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
        }

        primitives = sortedPrimitives
        orderings = sortedOrderings
    }

    public static func == (lhs: GPUILayer, rhs: GPUILayer) -> Bool {
        lhs.shadows == rhs.shadows &&
        lhs.quads == rhs.quads &&
        lhs.glyphs == rhs.glyphs &&
        lhs.pixelGlyphs == rhs.pixelGlyphs &&
        lhs.images == rhs.images &&
        lhs.paintOperations == rhs.paintOperations
    }
}

// MARK: - GPUIScene

/// Top-level GPUI-style scene container that organizes primitives by type into
/// contiguous arrays within layers. This structure replaces the flat
/// `[RenderCommand]` list with typed arrays suitable for instanced draw calls.
public struct GPUIScene: Equatable, Sendable {
    public var clearColor: Color
    public var layers: [GPUILayer]
    public var paintRecords: [GPUIScenePaintRecord]
    public var glyphAtlas: GlyphAtlasSnapshot?
    public var pixelGlyphAtlas: GlyphAtlasSnapshot?
    private var isFinished = false

    public init(
        clearColor: Color = .black,
        glyphAtlas: GlyphAtlasSnapshot? = nil,
        pixelGlyphAtlas: GlyphAtlasSnapshot? = nil
    ) {
        self.clearColor = clearColor
        self.layers = [GPUILayer()]
        self.paintRecords = []
        self.glyphAtlas = glyphAtlas
        self.pixelGlyphAtlas = pixelGlyphAtlas
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
    /// A balanced range has matching startLayer/endLayer markers for each layer.
    private func validateReplayRange(_ range: Range<Int>, in scene: GPUIScene) -> (
        isBalanced: Bool,
        layerIndex: Int?,
        depth: Int,
        reason: GPUISceneReplayResult.UnbalancedReason?
    ) {
        // Track per-layer scope depth
        var layerDepths: [Int: Int] = [:]
        var maxLayerIndex = -1
        
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
                let reason: GPUISceneReplayResult.UnbalancedReason = depth > 0
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
        lhs.clearColor == rhs.clearColor &&
        lhs.layers == rhs.layers &&
        lhs.paintRecords == rhs.paintRecords &&
        lhs.glyphAtlas == rhs.glyphAtlas &&
        lhs.pixelGlyphAtlas == rhs.pixelGlyphAtlas
    }
}

private extension QuadPrimitive {
    var contentMaskedBounds: Rect? {
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

private extension GlyphPrimitive {
    var contentMaskedBounds: Rect? {
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

private extension ImagePrimitive {
    var contentMaskedBounds: Rect? {
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

private extension ShadowPrimitive {
    var contentMaskedBounds: Rect? {
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
