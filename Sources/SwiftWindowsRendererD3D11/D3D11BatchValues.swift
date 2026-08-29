import WinSDK
import WinSDK.DirectX

/// Which D3D11 driver an offscreen attach creates its device with.
/// Also available through `D3D11BatchRenderer.OffscreenDriver`.
public enum D3D11BatchOffscreenDriver: Equatable, Sendable {
    /// Prefer the GPU, fall back to the software rasterizer.
    case hardwareFirst
    /// Prefer WARP, whose deterministic pixels support backend comparisons.
    case warpFirst

    var driverTypes: [D3D_DRIVER_TYPE] {
        switch self {
        case .hardwareFirst:
            return [D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP]
        case .warpFirst:
            return [D3D_DRIVER_TYPE_WARP, D3D_DRIVER_TYPE_HARDWARE]
        }
    }
}

/// Where a render plan obtains one glyph atlas.
public enum D3D11BatchAtlasSource: Equatable, Sendable {
    case snapshot
    case cached
}

/// Value description of resources available to the batch plan builder.
public struct D3D11BatchCachedResources: Equatable, Sendable {
    public var hasGlyphAtlas: Bool
    public var hasPixelGlyphAtlas: Bool
    public var boundImageTextureIDs: Set<Int32>

    public init(
        hasGlyphAtlas: Bool = false,
        hasPixelGlyphAtlas: Bool = false,
        boundImageTextureIDs: Set<Int32> = []
    ) {
        self.hasGlyphAtlas = hasGlyphAtlas
        self.hasPixelGlyphAtlas = hasPixelGlyphAtlas
        self.boundImageTextureIDs = boundImageTextureIDs
    }
}

/// One contiguous family run in scene presentation order.
public enum D3D11BatchRenderStep: Equatable, Sendable {
    case shadows(layerIndex: Int, range: Range<Int>)
    case quads(layerIndex: Int, range: Range<Int>)
    case glyphs(layerIndex: Int, range: Range<Int>, atlasSource: D3D11BatchAtlasSource)
    case pixelGlyphs(layerIndex: Int, range: Range<Int>, atlasSource: D3D11BatchAtlasSource)
    case images(layerIndex: Int, range: Range<Int>, textureID: Int32)
    case paths(layerIndex: Int, range: Range<Int>)
}

/// Renderer-neutral values planned from the scene's presentation order.
public struct D3D11BatchRenderPlan: Equatable, Sendable {
    public var glyphAtlasSource: D3D11BatchAtlasSource?
    public var pixelGlyphAtlasSource: D3D11BatchAtlasSource?
    public var steps: [D3D11BatchRenderStep]
    public var resultingResources: D3D11BatchCachedResources

    public init(
        glyphAtlasSource: D3D11BatchAtlasSource? = nil,
        pixelGlyphAtlasSource: D3D11BatchAtlasSource? = nil,
        steps: [D3D11BatchRenderStep] = [],
        resultingResources: D3D11BatchCachedResources = D3D11BatchCachedResources()
    ) {
        self.glyphAtlasSource = glyphAtlasSource
        self.pixelGlyphAtlasSource = pixelGlyphAtlasSource
        self.steps = steps
        self.resultingResources = resultingResources
    }
}
