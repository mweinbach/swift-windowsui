import Foundation
import SwiftWindowsCore

// MARK: - GPUILayer

/// A rendering layer containing typed, contiguous primitive arrays.
/// `paintOperations` is the layer's presentation order — it preserves the
/// source paint order across primitive families, and the family arrays are a
/// data layout for instanced draws, never a draw order of their own.

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

/// One entry in the scene's replay log.
///
/// `primitive` is a *reference* — `(layerIndex, kind, index)` — into the
/// family array that already holds the value, not a second copy of it.
/// The copy cost the largest primitive's stride per entry (~152 B for a
/// 64-byte glyph) and doubled again while `previousScene` was retained for
/// replay; the reference is stable because nothing reorders a family array
/// after insertion (see `GPUIScene.presentationOrder()`).
public enum GPUIScenePaintRecord: Equatable, Sendable {
    case primitive(layerIndex: Int, kind: GPUIPaintPrimitiveKind, index: Int)
    case startLayer(layerIndex: Int, bounds: Rect)
    case endLayer(layerIndex: Int)
}

/// One run of same-family primitives in presentation order: `range` of
/// `layers[layerIndex]`'s `kind` array, drawn in index order.
public struct GPUIPresentationRun: Equatable, Sendable {
    public var layerIndex: Int
    public var kind: GPUIPaintPrimitiveKind
    public var range: Range<Int>

    public init(layerIndex: Int, kind: GPUIPaintPrimitiveKind, range: Range<Int>) {
        self.layerIndex = layerIndex
        self.kind = kind
        self.range = range
    }
}

/// The scene's presentation order, as one sequence.
///
/// The cross-layer rule, which used to exist only as an accident of both
/// backends agreeing: **layers are z-order groups — every primitive in
/// `layers[i]` paints before every primitive in `layers[i+1]` — and within
/// a layer `paintOperations` is the presentation order.** The CPU
/// rasterizer used to walk the flat `paintRecords` log instead, discarding
/// `layerIndex` entirely, so a scene that interleaved layers rendered in a
/// different order on each backend and no screenshot could show it.
///
/// A paint operation that `GPUIScene.validate()` would flag as
/// out-of-range is skipped rather than clamped: a malformed scene loses
/// that run on the CPU (and is refused outright by the D3D11 plan
/// builder), which is the one behaviour that neither traps nor invents
/// pixels.
public struct GPUIPresentationOrder: Sequence, IteratorProtocol, Sendable {
    private let layers: [GPUILayer]
    private var layerIndex = 0
    private var operationIndex = 0

    init(layers: [GPUILayer]) {
        self.layers = layers
    }

    public mutating func next() -> GPUIPresentationRun? {
        while layerIndex < layers.count {
            let layer = layers[layerIndex]
            while operationIndex < layer.paintOperations.count {
                let operation = layer.paintOperations[operationIndex]
                operationIndex += 1
                if let range = layer.presentationRange(of: operation) {
                    return GPUIPresentationRun(layerIndex: layerIndex, kind: operation.kind, range: range)
                }
            }
            layerIndex += 1
            operationIndex = 0
        }
        return nil
    }
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
/// The atlas pixels as they stood when a frame was painted, plus what a
/// consumer has to upload to be current with them.
///
/// Consumers without a texture of their own (the CPU rasterizer, the
/// snapshot tool) read `pixels` and ignore the rest; consumers that own a
/// texture ask ``uploadDecision(for:)`` instead of interpreting
/// `contentVersion` and `update` themselves.
public struct GlyphAtlasSnapshot: Equatable, Sendable {
    public var width: Int32
    public var height: Int32
    public var pixels: Data
    /// Identifies these exact pixels, process-wide and monotonically (see
    /// `RenderContentVersion`). Two snapshots with the same version hold
    /// the same bytes; a consumer that already uploaded this version can
    /// skip the upload entirely.
    public var contentVersion: UInt64
    /// How these pixels relate to the previous snapshot of the same atlas.
    /// Defaults to `.full`, which claims nothing and always uploads — the
    /// safe default for a producer that does not track versions.
    public var update: AtlasUpdate

    public init(
        width: Int32,
        height: Int32,
        pixels: Data,
        contentVersion: UInt64 = 0,
        update: AtlasUpdate = .full
    ) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.contentVersion = contentVersion
        self.update = update
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
    // Readable everywhere, writable only here. `add*` sanitizes every field
    // it accepts and keeps the family arrays and `paintOperations` in step;
    // an `append` from outside did neither, so the sanitation the whole
    // scene contract rests on was one line of app code away from being
    // skipped.
    //
    // Residual hole, deliberately left open: `init` below still takes the
    // arrays wholesale, because a hand-built layer is how the malformed
    // scenes that prove `validate()` works get made. Direct construction is
    // therefore still unsanitized — `validate()` covers its structural
    // shape and the saturating conversions in `GPUISceneValue` cover its
    // field values, which is what keeps a bad one from trapping a backend.
    public private(set) var shadows: [ShadowPrimitive]
    public private(set) var quads: [QuadPrimitive]
    public private(set) var glyphs: [GlyphPrimitive]
    public private(set) var pixelGlyphs: [GlyphPrimitive]
    public private(set) var images: [ImagePrimitive]
    public private(set) var paths: [PathPrimitive]
    public private(set) var paintOperations: [GPUIPaintOperation]

    /// One entry per live scoped layer: `true` when the push was accepted
    /// and recorded, `false` for a rejected push. The sentinel is what
    /// lets `popScopedLayer` refuse to pop somebody else's scope — a
    /// caller that pairs push/pop unconditionally used to close the
    /// *enclosing* scope after a rejected push, permanently unbalancing
    /// `paintRecords` and blanking every replayed subtree after it.
    private var scopeStack: [Bool] = []

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

    /// Opens a scoped layer. Returns `false` — and pushes a rejection
    /// sentinel so the matching `popScopedLayer` is a no-op — when the
    /// bounds are empty.
    public mutating func pushScopedLayer(_ bounds: Rect) -> Bool {
        guard !bounds.isEmpty else {
            scopeStack.append(false)
            return false
        }

        scopeStack.append(true)
        return true
    }

    /// Closes the innermost scoped layer. Returns `false` when there is
    /// nothing to close, or when the matching push was rejected.
    public mutating func popScopedLayer() -> Bool {
        guard let wasAccepted = scopeStack.popLast() else {
            return false
        }
        return wasAccepted
    }

    mutating func addShadow(_ shadow: ShadowPrimitive) -> Int? {
        guard shadow.contentMaskedBounds != nil else {
            return nil
        }

        let startIndex = shadows.count
        shadows.append(shadow)
        appendPaintOperation(kind: .shadow, startIndex: startIndex)
        return startIndex
    }

    mutating func addQuad(_ quad: QuadPrimitive) -> Int? {
        guard quad.contentMaskedBounds != nil else {
            return nil
        }

        let startIndex = quads.count
        quads.append(quad)
        appendPaintOperation(kind: .quad, startIndex: startIndex)
        return startIndex
    }

    mutating func addGlyph(_ glyph: GlyphPrimitive) -> Int? {
        guard glyph.contentMaskedBounds != nil else {
            return nil
        }

        let startIndex = glyphs.count
        glyphs.append(glyph)
        appendPaintOperation(kind: .glyph, startIndex: startIndex)
        return startIndex
    }

    mutating func addPixelGlyph(_ glyph: GlyphPrimitive) -> Int? {
        guard glyph.contentMaskedBounds != nil else {
            return nil
        }

        let startIndex = pixelGlyphs.count
        pixelGlyphs.append(glyph)
        appendPaintOperation(kind: .pixelGlyph, startIndex: startIndex)
        return startIndex
    }

    mutating func addImage(_ image: ImagePrimitive) -> Int? {
        guard image.contentMaskedBounds != nil else {
            return nil
        }

        let startIndex = images.count
        images.append(image)
        appendPaintOperation(kind: .image, startIndex: startIndex)
        return startIndex
    }

    mutating func addPath(_ path: PathPrimitive) -> Int? {
        guard path.contentMaskedBounds != nil else {
            return nil
        }

        let startIndex = paths.count
        paths.append(path)
        appendPaintOperation(kind: .path, startIndex: startIndex)
        return startIndex
    }

    /// Seals the layer. Presentation order is fixed at insertion, so this
    /// only re-coalesces `paintOperations` into canonical run-length form
    /// — which `add*` already maintains, and which a hand-built layer may
    /// not. It deliberately reorders nothing: `finish()` used to sort each
    /// family by a bounds-tree draw order and remap the operations back,
    /// which cost ~12 heap allocations per primitive per frame to produce
    /// an ordering only `orderedBatches()` read and nothing in production
    /// called.
    public mutating func finish() {
        guard paintOperations.count > 1 else {
            return
        }

        var coalesced: [GPUIPaintOperation] = []
        coalesced.reserveCapacity(paintOperations.count)
        for operation in paintOperations {
            if var last = coalesced.last, last.kind == operation.kind,
                last.count >= 0, operation.count >= 0
            {
                // Hand-built layers are validated after sealing, so their
                // public index/count fields cannot be trusted here. Leave an
                // overflowing run untouched for `validate()` to diagnose.
                let (nextIndex, nextIndexOverflowed) = last.startIndex.addingReportingOverflow(last.count)
                let (mergedCount, mergedCountOverflowed) = last.count.addingReportingOverflow(operation.count)
                if !nextIndexOverflowed, !mergedCountOverflowed, nextIndex == operation.startIndex {
                    last.count = mergedCount
                    coalesced[coalesced.count - 1] = last
                    continue
                }
            }
            coalesced.append(operation)
        }
        paintOperations = coalesced
    }

    /// The primitive index range `operation` presents, or `nil` when the
    /// operation does not describe a real range of its family array. The
    /// predicate is `GPUIScene.validate()`'s, so what the CPU rasterizer
    /// silently skips is exactly what the D3D11 plan builder refuses.
    func presentationRange(of operation: GPUIPaintOperation) -> Range<Int>? {
        let familyCount = count(of: operation.kind)
        guard operation.count > 0, operation.startIndex >= 0,
            operation.startIndex <= familyCount - operation.count
        else {
            return nil
        }
        return operation.startIndex..<(operation.startIndex + operation.count)
    }

    func count(of kind: GPUIPaintPrimitiveKind) -> Int {
        switch kind {
        case .shadow: return shadows.count
        case .quad: return quads.count
        case .glyph: return glyphs.count
        case .pixelGlyph: return pixelGlyphs.count
        case .image: return images.count
        case .path: return paths.count
        }
    }

    func primitive(kind: GPUIPaintPrimitiveKind, at index: Int) -> GPUIScenePrimitive? {
        switch kind {
        case .shadow: return shadows.indices.contains(index) ? .shadow(shadows[index]) : nil
        case .quad: return quads.indices.contains(index) ? .quad(quads[index]) : nil
        case .glyph: return glyphs.indices.contains(index) ? .glyph(glyphs[index]) : nil
        case .pixelGlyph: return pixelGlyphs.indices.contains(index) ? .pixelGlyph(pixelGlyphs[index]) : nil
        case .image: return images.indices.contains(index) ? .image(images[index]) : nil
        case .path: return paths.indices.contains(index) ? .path(paths[index]) : nil
        }
    }

    private mutating func appendPaintOperation(kind: GPUIPaintPrimitiveKind, startIndex: Int) {
        Self.appendPaintOperation(kind: kind, startIndex: startIndex, to: &paintOperations)
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
/// Text-pipeline failure counters for one painted scene.
///
/// Every failure in the text stack used to be a `nil` that turned, several
/// frames up, into "draw the 5×7 bitmap font" — a severe, user-visible quality
/// cliff with no signal anywhere. These counters make the cliff observable
/// without changing what the pipeline draws.
public struct TextRenderDiagnostics: Equatable, Sendable {
    /// Text nodes that could not use the native glyph path and fell through to
    /// the 5×7 `PixelFont` atlas (which uppercases and maps most codepoints to
    /// `?`).
    public var pixelFontFallbacks: Int = 0
    /// Glyphs whose raster (DirectWrite or GDI) returned nothing, so no quad
    /// was emitted for them.
    public var glyphRasterFailures: Int = 0
    /// Paint attempts abandoned because the glyph atlas recycled its shelves
    /// mid-pass, invalidating already-captured UVs.
    public var atlasRecoveries: Int = 0
    /// Glyph runs resolved by DirectWrite shaping (glyph IDs + shaped
    /// positions).
    public var shapedGlyphRuns: Int = 0
    /// Glyph runs that fell back to the per-character hit-test walk, which has
    /// no ligatures and no complex-script forms.
    public var unshapedGlyphRuns: Int = 0
    /// Rasterizations that dropped a non-zero `letterSpacing` because the
    /// legacy bitmap raster path cannot express it.
    public var letterSpacingDroppedRasterizations: Int = 0

    public init() {}

    /// True when nothing in the text pipeline degraded during this scene.
    public var isClean: Bool {
        pixelFontFallbacks == 0 && glyphRasterFailures == 0 && atlasRecoveries == 0
            && unshapedGlyphRuns == 0 && letterSpacingDroppedRasterizations == 0
    }
}

public struct ScenePaintMetrics: Equatable, Sendable {
    /// Path primitives that fell through to the CPU rasterizer.
    public var pathsRasterizedOnCPU: Int = 0
    /// Path primitives that the tessellator promoted to GPU quads.
    public var pathsPromotedToGPU: Int = 0
    /// Total quad instances emitted by GPU-promoted paths (one path can
    /// produce multiple quads — e.g. a closed stroked rect emits 4).
    public var quadInstancesFromPromotedPaths: Int = 0
    /// Compositing groups (`.drawingGroup()`, `.compositingGroup()`) whose
    /// subtree was CPU-rasterized into an offscreen bitmap during this paint.
    public var compositingGroupsRasterized: Int = 0
    /// Compositing groups that reused the bitmap rasterized for an earlier
    /// paint because their key and subtree were unchanged. Rasterizing a group
    /// walks and rasterizes its whole subtree on the main actor, so this is the
    /// counter that says whether a `.drawingGroup()` is amortized or not.
    public var compositingGroupsReused: Int = 0
    /// `.blur(radius:)` subtrees resolved as an isolated offscreen pass —
    /// rendered into their own bitmap, blurred there, and composited — as
    /// opposed to the backdrop-quad fallback the painter takes when the
    /// isolation buffer cannot be sized. One per blurred subtree, however
    /// many descendants it has.
    public var contentBlurPasses: Int = 0
    /// Isolated content-blur passes that reused the bitmap an earlier paint
    /// produced. A blurred subtree costs a CPU rasterization plus a Gaussian
    /// when it changes and nothing at all when it does not, so this is the
    /// counter that says whether a `.blur()` is amortized.
    public var contentBlurPassesReused: Int = 0
    /// Color-effect subtrees recorded as renderer-owned offscreen passes.
    /// These retain scene primitives rather than baking a CPU bitmap.
    public var colorEffectPasses: Int = 0
    /// View nodes the paint traversal entered to produce this scene.
    ///
    /// The direct measure of how much of the tree a frame redid, and the one
    /// the animating frame budget is written against. A replayed subtree costs
    /// exactly one visit however many descendants it has — the traversal
    /// copies its cached paint range and never descends — so this number
    /// separates "one row is animating" from "the whole window repainted",
    /// which the replay count alone cannot: a frame that replays the entire
    /// root in a single range and a frame that replays nothing both report one
    /// replay, and they differ by the whole tree.
    ///
    /// Counts the main traversal only. Subtree paints that render into their
    /// own scene — a rasterized compositing group, an isolated `.blur()`
    /// bitmap — carry their own metrics with that scene.
    public var nodesVisited: Int = 0
    /// Text-pipeline degradations observed while painting this scene.
    public var textDiagnostics: TextRenderDiagnostics = TextRenderDiagnostics()

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
    /// The render target's straight-alpha clear colour. Like primitive
    /// colours, every channel is finite and stays in `[0, 1]`: this value
    /// bypasses `add*`, so it must enforce the same scene contract itself.
    /// Without that boundary a NaN channel reaches the CPU rasterizer's
    /// `Float -> UInt8` conversion and kills the process before fallback.
    public var clearColor: Color {
        didSet {
            clearColor = Self.sanitizedClearColor(clearColor)
        }
    }
    // Readable everywhere, writable only here, for the reason `GPUILayer`
    // spells out above: `add*` is the one door sanitation, the family
    // arrays and `paintRecords` all agree behind. `layers` being a `public
    // var` while the arrays inside it were `private(set)` reinstated the
    // whole bypass one subscript assignment at a time —
    // `scene.layers[0] = GPUILayer(...)` skips sanitation *and* leaves
    // `paintRecords` describing primitives that are no longer there.
    public private(set) var layers: [GPUILayer]
    public private(set) var paintRecords: [GPUIScenePaintRecord]
    public var glyphAtlas: GlyphAtlasSnapshot?
    public var pixelGlyphAtlas: GlyphAtlasSnapshot?
    public var imageResources: [ImageResourceBinding]
    /// Lazily rendered image sources, consumed in the same presentation order
    /// as bitmap-backed images. Each child scene owns its resource namespace.
    public var imageRenderPasses: [GPUISceneImageRenderPass]
    /// Paint-time observability counters (CPU vs GPU path routing).
    public var paintMetrics: ScenePaintMetrics = ScenePaintMetrics()
    private var isFinished = false

    public init(
        clearColor: Color = .black,
        glyphAtlas: GlyphAtlasSnapshot? = nil,
        pixelGlyphAtlas: GlyphAtlasSnapshot? = nil,
        imageResources: [ImageResourceBinding] = [],
        imageRenderPasses: [GPUISceneImageRenderPass] = []
    ) {
        self.clearColor = Self.sanitizedClearColor(clearColor)
        self.layers = [GPUILayer()]
        self.paintRecords = []
        self.glyphAtlas = glyphAtlas
        self.pixelGlyphAtlas = pixelGlyphAtlas
        self.imageResources = imageResources
        self.imageRenderPasses = imageRenderPasses
    }

    private static func sanitizedClearColor(_ color: Color) -> Color {
        Color(
            red: GPUISceneValue.clamped(color.red, lower: 0, upper: 1),
            green: GPUISceneValue.clamped(color.green, lower: 0, upper: 1),
            blue: GPUISceneValue.clamped(color.blue, lower: 0, upper: 1),
            alpha: GPUISceneValue.clamped(color.alpha, lower: 0, upper: 1)
        )
    }

    // MARK: - Layer management

    /// Installs hand-built layers wholesale, bypassing `add*`.
    ///
    /// The named door for the residual hole `GPUILayer.init` documents: a
    /// scene whose layers are built by hand is unsanitized, so `validate()`
    /// — not the type system — is what stands between one and a backend.
    /// That is exactly what the malformed-scene tests need and what nothing
    /// else should want, which is why it says so in its name.
    ///
    /// The replay log does not survive the swap. `paintRecords` is a list of
    /// *references* into the family arrays, so records kept across a layer
    /// replacement stay in bounds while pointing at primitives that are no
    /// longer the ones they described — the in-bounds-but-wrong replay class
    /// the painter's stale-range check closed on the other side. A hand-built
    /// layer set has no valid log for the layers it just installed, and an
    /// empty log replays as `.invalidRange` rather than as a wrong picture.
    public mutating func installHandBuiltLayers(_ newLayers: [GPUILayer]) {
        layers = newLayers
        paintRecords.removeAll(keepingCapacity: true)
        isFinished = false
    }

    /// `installHandBuiltLayers` for a single layer, leaving the rest alone.
    /// A no-op — log included — when `index` does not address an existing
    /// layer. The log is dropped for the same reason as the wholesale
    /// installer: every record naming this layer now references primitives
    /// that were replaced, and the records naming the other layers cannot be
    /// replayed on their own without the range spanning this one.
    public mutating func installHandBuiltLayer(_ layer: GPUILayer, at index: Int) {
        guard layers.indices.contains(index) else {
            return
        }
        layers[index] = layer
        paintRecords.removeAll(keepingCapacity: true)
        isFinished = false
    }

    /// Push a new empty layer onto the stack, or reuse the top layer once
    /// the shared scene limit is reached. `ensureLayer` already refuses to
    /// grow past this bound; pushing must obey the same rule so a deeply
    /// layered scene cannot invalidate itself or allocate without limit.
    @discardableResult
    public mutating func pushLayer() -> Int {
        guard layers.count < GPUISceneLimits.maxLayers else {
            return GPUISceneLimits.maxLayers - 1
        }
        layers.append(GPUILayer())
        isFinished = false
        return layers.count - 1
    }

    /// Ensures the scene contains a layer for the given index.
    ///
    /// Returns `false` — without allocating — for a negative index or one
    /// at/above `GPUISceneLimits.maxLayers`. The growth loop used to
    /// accept any non-negative index, so a single bad (or stale replayed)
    /// layer index appended layers until the process ran out of memory.
    @discardableResult
    public mutating func ensureLayer(_ layerIndex: Int) -> Bool {
        guard layerIndex >= 0, layerIndex < GPUISceneLimits.maxLayers else {
            return false
        }

        while layers.count <= layerIndex {
            layers.append(GPUILayer())
        }
        isFinished = false
        return true
    }

    /// Opens a scoped layer and records the marker replay validation pairs
    /// against. Returns `false` when the push was refused — the caller may
    /// still pop unconditionally, because the layer remembers the
    /// rejection and `popScopedLayer` declines to close somebody else's
    /// scope for it.
    @discardableResult
    public mutating func pushScopedLayer(_ bounds: Rect, toLayer layerIndex: Int) -> Bool {
        guard ensureLayer(layerIndex) else {
            return false
        }
        guard layers[layerIndex].pushScopedLayer(bounds) else {
            return false
        }
        paintRecords.append(.startLayer(layerIndex: layerIndex, bounds: bounds))
        isFinished = false
        return true
    }

    /// Texture ID for `bitmap`, reusing the one already registered for the
    /// same content.
    ///
    /// Deduplication is by ``BitmapContentKey`` — an O(1) token compare —
    /// not by `==`, which memcmp'd the whole buffer against every image
    /// already registered this frame (a 1920×1080 background cost 8 MB of
    /// comparison per registration). The trade is that two byte-identical
    /// buffers built independently now get two IDs and two textures; the
    /// common case, one buffer reused across frames and call sites, keeps
    /// its token through every copy and still dedupes.
    @discardableResult
    public mutating func registerImageResource(_ bitmap: BitmapSurface) -> Int32 {
        let key = bitmap.contentKey
        if let existing = imageResources.first(where: { $0.bitmap.contentKey == key }) {
            return existing.textureID
        }

        let nextTextureID = nextImageTextureID
        imageResources.append(ImageResourceBinding(textureID: nextTextureID, bitmap: bitmap))
        return nextTextureID
    }

    private var nextImageTextureID: Int32 {
        let highest = max(
            max(imageResources.map(\.textureID).max() ?? -1, imageRenderPasses.map(\.textureID).max() ?? -1),
            layers.flatMap { $0.images.map(\.textureID) }.max() ?? -1)
        // A manually bound Int32.max ID must not turn registration into a
        // conversion/overflow trap. Find a hole in that exceptional case.
        if highest < Int32.max { return highest + 1 }
        let occupied = Set(
            imageResources.map(\.textureID) + imageRenderPasses.map(\.textureID)
                + layers.flatMap { $0.images.map(\.textureID) })
        var candidate: Int32 = 0
        while occupied.contains(candidate), candidate < Int32.max { candidate += 1 }
        return candidate
    }

    @discardableResult
    public mutating func registerImageRenderPass(
        _ scene: GPUIScene, size: IntSize, colorEffects: [SceneColorEffect] = [],
        input: GPUISceneImageRenderPassInput = .independent
    ) -> Int32 {
        let textureID = nextImageTextureID
        imageRenderPasses.append(
            GPUISceneImageRenderPass(
                textureID: textureID, scene: scene, size: size, colorEffects: colorEffects, input: input))
        return textureID
    }

    public mutating func bindImageRenderPass(_ pass: GPUISceneImageRenderPass) {
        guard pass.textureID >= 0 else { return }
        imageResources.removeAll { $0.textureID == pass.textureID }
        if let index = imageRenderPasses.firstIndex(where: { $0.textureID == pass.textureID }) {
            imageRenderPasses[index] = pass
        } else {
            imageRenderPasses.append(pass)
        }
    }

    public mutating func bindImageResource(_ bitmap: BitmapSurface, for textureID: Int32) {
        guard textureID >= 0 else {
            return
        }

        imageRenderPasses.removeAll { $0.textureID == textureID }

        if let index = imageResources.firstIndex(where: { $0.textureID == textureID }) {
            imageResources[index].bitmap = bitmap
            return
        }

        imageResources.append(ImageResourceBinding(textureID: textureID, bitmap: bitmap))
    }

    /// Closes the innermost scoped layer of `layerIndex`. Returns `false`
    /// when there was no accepted push to close, in which case no
    /// `endLayer` marker is recorded and `paintRecords` stays balanced.
    @discardableResult
    public mutating func popScopedLayer(fromLayer layerIndex: Int) -> Bool {
        guard layers.indices.contains(layerIndex) else {
            return false
        }
        guard layers[layerIndex].popScopedLayer() else {
            return false
        }
        paintRecords.append(.endLayer(layerIndex: layerIndex))
        isFinished = false
        return true
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

    // Every `add*` runs its primitive through `GPUISceneSanitizer` first,
    // so the family arrays, `paintRecords` and every replay of them carry
    // only finite, in-range values. Both backends and the CPU rasterizer
    // read those arrays directly, so this is the one place the guarantee
    // has to hold. Sanitation is an identity transform for well-formed
    // primitives; a primitive whose geometry or clip cannot be
    // represented is dropped exactly like a fully-clipped one.

    public mutating func addQuad(_ quad: QuadPrimitive, toLayer layerIndex: Int) {
        guard let quad = GPUISceneSanitizer.sanitized(quad), ensureLayer(layerIndex) else {
            return
        }
        if let index = layers[layerIndex].addQuad(quad) {
            paintRecords.append(.primitive(layerIndex: layerIndex, kind: .quad, index: index))
            isFinished = false
        }
    }

    public mutating func addGlyph(_ glyph: GlyphPrimitive, toLayer layerIndex: Int) {
        guard let glyph = GPUISceneSanitizer.sanitized(glyph), ensureLayer(layerIndex) else {
            return
        }
        if let index = layers[layerIndex].addGlyph(glyph) {
            paintRecords.append(.primitive(layerIndex: layerIndex, kind: .glyph, index: index))
            isFinished = false
        }
    }

    public mutating func addImage(_ image: ImagePrimitive, toLayer layerIndex: Int) {
        guard let image = GPUISceneSanitizer.sanitized(image), ensureLayer(layerIndex) else {
            return
        }
        if !image.sampling.isLegacy {
            let sourceSize =
                imageResources.last(where: { $0.textureID == image.textureID }).map {
                    IntSize(width: $0.bitmap.width, height: $0.bitmap.height)
                } ?? imageRenderPasses.last(where: { $0.textureID == image.textureID })?.size
            guard image.sampling.validationFailure(sourceSize: sourceSize) == nil else { return }
        }
        if let index = layers[layerIndex].addImage(image) {
            paintRecords.append(.primitive(layerIndex: layerIndex, kind: .image, index: index))
            isFinished = false
        }
    }

    public mutating func addShadow(_ shadow: ShadowPrimitive, toLayer layerIndex: Int) {
        guard let shadow = GPUISceneSanitizer.sanitized(shadow), ensureLayer(layerIndex) else {
            return
        }
        if let index = layers[layerIndex].addShadow(shadow) {
            paintRecords.append(.primitive(layerIndex: layerIndex, kind: .shadow, index: index))
            isFinished = false
        }
    }

    public mutating func addPixelGlyph(_ glyph: GlyphPrimitive, toLayer layerIndex: Int) {
        guard let glyph = GPUISceneSanitizer.sanitized(glyph), ensureLayer(layerIndex) else {
            return
        }
        if let index = layers[layerIndex].addPixelGlyph(glyph) {
            paintRecords.append(.primitive(layerIndex: layerIndex, kind: .pixelGlyph, index: index))
            isFinished = false
        }
    }

    public mutating func addPath(_ path: PathPrimitive, toLayer layerIndex: Int) {
        guard let path = GPUISceneSanitizer.sanitized(path), ensureLayer(layerIndex) else {
            return
        }
        if let index = layers[layerIndex].addPath(path) {
            paintRecords.append(.primitive(layerIndex: layerIndex, kind: .path, index: index))
            isFinished = false
        }
    }

    /// The primitive a paint record or presentation run refers to, or
    /// `nil` when the reference does not resolve.
    public func primitive(kind: GPUIPaintPrimitiveKind, inLayer layerIndex: Int, at index: Int) -> GPUIScenePrimitive? {
        guard layers.indices.contains(layerIndex) else {
            return nil
        }
        return layers[layerIndex].primitive(kind: kind, at: index)
    }

    /// The scene's presentation order as one sequence, layer-major.
    /// Both backends consume this: it is the only draw-order authority.
    public func presentationOrder() -> GPUIPresentationOrder {
        GPUIPresentationOrder(layers: layers)
    }

    /// True when any layer draws from the native glyph atlas — which is the
    /// predicate that decides whether the scene has to *ship* one. It is a
    /// property of the primitives, not of what the painter rasterized this
    /// frame: a frame that replayed all of its text emitted no glyph and
    /// still draws every one of them.
    public var usesGlyphs: Bool {
        layers.contains { !$0.glyphs.isEmpty }
    }

    /// `usesGlyphs` for the pixel-font atlas.
    public var usesPixelGlyphs: Bool {
        layers.contains { !$0.pixelGlyphs.isEmpty }
    }

    /// Represents the result of a replay operation.
    public enum GPUISceneReplayResult: Equatable, Sendable {
        /// Replay succeeded and reconstructed equivalent scene content.
        case success
        /// The range does not address the source scene's paint records at
        /// all. A cached range outlives the scene it was measured against
        /// — a subtree that painted into a `drawingGroup` sub-scene, or a
        /// `previousScene` that was rebuilt shorter — and indexing the
        /// records with it traps rather than returning a bad picture.
        case invalidRange(Range<Int>, recordCount: Int)
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
        // Bounds first: `validateReplayRange` walks `paintRecords` with
        // this range and traps on one that outran the source scene.
        guard range.lowerBound >= 0, range.upperBound <= previousScene.paintRecords.count else {
            return .invalidRange(range, recordCount: previousScene.paintRecords.count)
        }

        // Validate that the range is structurally balanced
        let validation = validateReplayRange(range, in: previousScene)
        guard validation.isBalanced else {
            return .unbalanced(
                layerIndex: validation.layerIndex,
                depth: validation.depth,
                reason: validation.reason!
            )
        }

        // Image IDs are local to a scene. Replaying old bindings wholesale
        // could overwrite a newly painted sibling which reused an old ID.
        // Copy only referenced sources, remapping conflicts on the image
        // primitive as well as its binding. Pass children keep their own IDs.
        var replayedImageIDs: [Int32: Int32] = [:]

        for record in previousScene.paintRecords[range] {
            switch record {
            case .primitive(let layerIndex, let kind, let index):
                // A record that does not resolve is dropped rather than
                // faked: the family arrays are the primitive values, the
                // records are only references into them.
                switch previousScene.primitive(kind: kind, inLayer: layerIndex, at: index) {
                case .shadow(let shadow):
                    addShadow(shadow, toLayer: layerIndex)
                case .quad(let quad):
                    addQuad(quad, toLayer: layerIndex)
                case .glyph(let glyph):
                    addGlyph(glyph, toLayer: layerIndex)
                case .pixelGlyph(let glyph):
                    addPixelGlyph(glyph, toLayer: layerIndex)
                case .image(var image):
                    let oldID = image.textureID
                    if let mapped = replayedImageIDs[oldID] {
                        image.textureID = mapped
                    } else {
                        let occupied =
                            imageResources.contains { $0.textureID == oldID }
                            || imageRenderPasses.contains { $0.textureID == oldID }
                            || layers.contains { $0.images.contains { $0.textureID == oldID } }
                        if let pass = previousScene.imageRenderPasses.last(where: { $0.textureID == oldID }) {
                            var rebound = pass
                            if occupied { rebound.textureID = nextImageTextureID }
                            bindImageRenderPass(rebound)
                            image.textureID = rebound.textureID
                        } else if let binding = previousScene.imageResources.last(where: { $0.textureID == oldID }) {
                            if occupied {
                                image.textureID = registerImageResource(binding.bitmap)
                            } else {
                                bindImageResource(binding.bitmap, for: oldID)
                            }
                        }
                        replayedImageIDs[oldID] = image.textureID
                    }
                    addImage(image, toLayer: layerIndex)
                case .path(let path):
                    addPath(path, toLayer: layerIndex)
                case nil:
                    continue
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
            case .primitive(let layerIndex, _, _):
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
            case .primitive(let layerIndex, _, _):
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
            && lhs.imageRenderPasses == rhs.imageRenderPasses
    }
}
/// The single acceptance rule every primitive family shares: a primitive
/// is accepted only if it has positive extent and a non-empty
/// intersection with its effective clip.
///
/// The four float-clip families (quad, glyph, image, shadow) encode their
/// clip in band; `GPUIClipEncoding` owns that encoding and the three states
/// it has to express. Absent (all four fields zero) clips nothing; empty
/// (positioned but collapsed, or negative extent) clips everything and
/// rejects the primitive here. This used to reject only the *asymmetric*
/// collapse and read the symmetric one as "unclipped", so a container whose
/// clip collapsed to nothing released its children onto the whole window.
/// `PathPrimitive` needs none of it: it carries an optional `Rect`, where
/// `nil` already means unclipped, so a *present* collapsed clip there is an
/// empty clip and nothing else — see `PathPrimitive.contentMaskedBounds` in
/// `GPUIPrimitives.swift`.
func contentMaskedBounds(
    x: Float,
    y: Float,
    width: Float,
    height: Float,
    clipX: Float = 0,
    clipY: Float = 0,
    clipWidth: Float,
    clipHeight: Float,
    contentMask: GPUIContentMask
) -> Rect? {
    guard width > 0, height > 0 else {
        return nil
    }

    guard
        !GPUIClipEncoding.isEmpty(clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight)
    else {
        return nil
    }

    let bounds = Rect(x: Double(x), y: Double(y), width: Double(width), height: Double(height))
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
/// The axis-aligned footprint of a rect turned about its own centre.
///
/// WS-19 / R-ROT. A rotated primitive's footprint is the bounding box of the
/// turned rect, not the rect itself. Comparing the unrotated rect against the
/// clip dropped diagonal stroke segments and rotated node decoration whose
/// bodies were inside the clip all along — an origin/size pair describes a
/// primitive only before `rotationRadians` is applied. Four families carry the
/// angle now (quad, glyph, image, shadow), and one function is what keeps them
/// answering the same question the same way. Zero (or non-finite) rotation
/// returns the input unchanged, so every axis-aligned scene stays byte-identical.
@inline(__always)
func rotatedFootprint(x: Float, y: Float, width: Float, height: Float, rotationRadians: Float)
    -> (x: Float, y: Float, width: Float, height: Float)
{
    guard rotationRadians != 0, rotationRadians.isFinite else {
        return (x, y, width, height)
    }
    let angle = Double(rotationRadians)
    let halfW = Double(width) * 0.5
    let halfH = Double(height) * 0.5
    let extentX = abs(cos(angle)) * halfW + abs(sin(angle)) * halfH
    let extentY = abs(sin(angle)) * halfW + abs(cos(angle)) * halfH
    let centreX = Double(x) + halfW
    let centreY = Double(y) + halfH
    return (
        Float(centreX - extentX), Float(centreY - extentY),
        Float(extentX * 2), Float(extentY * 2)
    )
}

extension QuadPrimitive {
    fileprivate var contentMaskedBounds: Rect? {
        let box = rotatedFootprint(x: x, y: y, width: width, height: height, rotationRadians: rotationRadians)
        return SwiftWindowsGraphics.contentMaskedBounds(
            x: box.x, y: box.y, width: box.width, height: box.height,
            clipX: clipX, clipY: clipY,
            clipWidth: clipWidth, clipHeight: clipHeight, contentMask: contentMask)
    }
}
extension GlyphPrimitive {
    fileprivate var contentMaskedBounds: Rect? {
        let box = rotatedFootprint(
            x: screenX, y: screenY, width: screenW, height: screenH, rotationRadians: rotationRadians)
        return SwiftWindowsGraphics.contentMaskedBounds(
            x: box.x, y: box.y, width: box.width, height: box.height,
            clipX: clipX, clipY: clipY,
            clipWidth: clipWidth, clipHeight: clipHeight, contentMask: contentMask)
    }
}
extension ImagePrimitive {
    fileprivate var contentMaskedBounds: Rect? {
        guard let geometry = ImagePlacementGeometry(self) else { return nil }
        // Preserve the original Float footprint for identity-basis scenes.
        let box =
            hasIdentityAffineTransform
            ? rotatedFootprint(
                x: screenX, y: screenY, width: screenW, height: screenH, rotationRadians: rotationRadians)
            : (
                x: Float(geometry.bounds.minX), y: Float(geometry.bounds.minY),
                width: Float(geometry.bounds.size.width), height: Float(geometry.bounds.size.height)
            )
        return SwiftWindowsGraphics.contentMaskedBounds(
            x: box.x, y: box.y, width: box.width, height: box.height,
            clipX: clipX, clipY: clipY,
            clipWidth: clipWidth, clipHeight: clipHeight, contentMask: contentMask)
    }
}
extension ShadowPrimitive {
    fileprivate var contentMaskedBounds: Rect? {
        // A rotated shadow turns about the centre of the rect it *draws* —
        // the offset one — so the footprint has to be taken there. An
        // unrotated shadow keeps the historic acceptance rect (the unoffset
        // origin/size pair, which the painter has already gated the offset
        // rect against), so no pre-existing scene changes acceptance.
        guard rotationRadians != 0, rotationRadians.isFinite else {
            return SwiftWindowsGraphics.contentMaskedBounds(
                x: x, y: y, width: width, height: height,
                clipX: clipX, clipY: clipY,
                clipWidth: clipWidth, clipHeight: clipHeight, contentMask: contentMask)
        }
        let box = rotatedFootprint(
            x: x + offsetX, y: y + offsetY, width: width, height: height, rotationRadians: rotationRadians)
        return SwiftWindowsGraphics.contentMaskedBounds(
            x: box.x, y: box.y, width: box.width, height: box.height,
            clipX: clipX, clipY: clipY,
            clipWidth: clipWidth, clipHeight: clipHeight, contentMask: contentMask)
    }
}

extension GPUIScene {
    /// The footprint of presented primitives, including shadow falloff and
    /// overflow outside a view's layout frame. Offscreen effects must crop to
    /// painted content, not to the layout box, or they cut off that content.
    public var paintedBounds: Rect? {
        var result: Rect?
        func include(_ rect: Rect?) {
            guard let rect, !rect.isEmpty else { return }
            guard let previous = result else {
                result = rect
                return
            }
            let x = min(previous.minX, rect.minX)
            let y = min(previous.minY, rect.minY)
            result = Rect(
                x: x, y: y, width: max(previous.maxX, rect.maxX) - x,
                height: max(previous.maxY, rect.maxY) - y)
        }
        for run in presentationOrder() {
            for index in run.range {
                switch primitive(kind: run.kind, inLayer: run.layerIndex, at: index) {
                case .quad(let primitive): include(primitive.contentMaskedBounds)
                case .glyph(let primitive), .pixelGlyph(let primitive): include(primitive.contentMaskedBounds)
                case .image(let primitive): include(primitive.contentMaskedBounds)
                case .path(let primitive): include(primitive.contentMaskedBounds)
                case .shadow(let shadow):
                    let expansion = shadow.blurRadius * 2
                    let box = rotatedFootprint(
                        x: shadow.x + shadow.offsetX - expansion,
                        y: shadow.y + shadow.offsetY - expansion,
                        width: shadow.width + expansion * 2, height: shadow.height + expansion * 2,
                        rotationRadians: shadow.rotationRadians)
                    include(
                        contentMaskedBounds(
                            x: box.x, y: box.y, width: box.width, height: box.height,
                            clipX: shadow.clipX, clipY: shadow.clipY,
                            clipWidth: shadow.clipWidth, clipHeight: shadow.clipHeight,
                            contentMask: shadow.contentMask))
                case nil: break
                }
            }
        }
        return result
    }

    /// Re-expresses primitives in a cropped pass's coordinate system without
    /// rasterizing them. Gradient vectors are local to their primitives;
    /// nested image sources own separate coordinates and stay unchanged.
    public func translatedPrimitives(by offset: Point) -> GPUIScene {
        var result = GPUIScene(
            clearColor: clearColor, glyphAtlas: glyphAtlas, pixelGlyphAtlas: pixelGlyphAtlas,
            imageResources: imageResources, imageRenderPasses: imageRenderPasses)
        result.paintMetrics = paintMetrics
        let dx = Float(offset.x)
        let dy = Float(offset.y)
        func shifted(_ mask: GPUIContentMask) -> GPUIContentMask {
            guard let bounds = mask.bounds else { return mask }
            return GPUIContentMask(
                bounds: Rect(
                    x: bounds.minX + offset.x, y: bounds.minY + offset.y,
                    width: bounds.size.width, height: bounds.size.height))
        }
        for run in presentationOrder() {
            for index in run.range {
                switch primitive(kind: run.kind, inLayer: run.layerIndex, at: index) {
                case .quad(var value):
                    value.x += dx
                    value.y += dy
                    value.contentMask = shifted(value.contentMask)
                    result.addQuad(value, toLayer: run.layerIndex)
                case .glyph(var value):
                    value.screenX += dx
                    value.screenY += dy
                    value.contentMask = shifted(value.contentMask)
                    result.addGlyph(value, toLayer: run.layerIndex)
                case .pixelGlyph(var value):
                    value.screenX += dx
                    value.screenY += dy
                    value.contentMask = shifted(value.contentMask)
                    result.addPixelGlyph(value, toLayer: run.layerIndex)
                case .image(var value):
                    value.screenX += dx
                    value.screenY += dy
                    value.contentMask = shifted(value.contentMask)
                    result.addImage(value, toLayer: run.layerIndex)
                case .shadow(var value):
                    value.x += dx
                    value.y += dy
                    value.contentMask = shifted(value.contentMask)
                    result.addShadow(value, toLayer: run.layerIndex)
                case .path(let value): result.addPath(value.translated(by: offset), toLayer: run.layerIndex)
                case nil: break
                }
            }
        }
        result.finish()
        return result
    }
}
