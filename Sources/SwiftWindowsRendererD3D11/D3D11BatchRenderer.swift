import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import WinSDK

// MARK: - D3D11BatchRenderer

/// Instanced batch renderer using StructuredBuffer-based instanced draw calls.
/// Instead of one draw call per rectangle, all primitives of the same type are
/// uploaded to a single GPU buffer and drawn in one DrawInstanced call.
import WinSDK.DirectX

// MARK: - Error Type

// MARK: - Private Helpers

@MainActor
public final class D3D11BatchRenderer: BatchRenderBackend {
    public private(set) var isAttached = false {
        didSet { isAttachedMirror = isAttached }
    }

    /// Sendable mirror of ``isAttached`` so `deinit` — which is nonisolated
    /// and therefore cannot read main-actor state — can still tell whether
    /// the owner forgot to call ``detach()``.
    private nonisolated(unsafe) var isAttachedMirror = false

    public var backendDisplayName: String { "D3D11 BATCH" }

    // MARK: - D3D11 Core State

    private var device: UnsafeMutablePointer<ID3D11Device>?
    private var deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>?
    private var dxgiFactory: UnsafeMutablePointer<IDXGIFactory2>?
    private var swapChain: UnsafeMutablePointer<IDXGISwapChain1>?
    private var renderTargetView: UnsafeMutablePointer<ID3D11RenderTargetView>?

    /// Process-wide source of device generations. Every `ID3D11Device` this
    /// module creates gets a number no other device ever had.
    private static var nextDeviceGeneration: UInt64 = 1

    /// Identity token for the device currently held, or `0` when detached.
    ///
    /// Device-owned caches key on this rather than on the device pointer:
    /// after a device-loss rebuild the allocator may reuse the removed
    /// device's address, and pointer equality would then claim resources
    /// built for a dead device still belong to the live one.
    private(set) var deviceGeneration: UInt64 = 0

    // MARK: - Render Target

    /// Where a frame lands. `.swapChain` is the shipping windowed path;
    /// `.offscreen` renders into a plain B8G8R8A8 texture with no HWND and
    /// no DXGI presentation. Everything after the target — device,
    /// pipeline, instance buffers, atlases, blur engine and the whole of
    /// `render(scene:)` — is identical for both, so the frame path stays
    /// target-agnostic: it asks for a render target view, a back buffer
    /// and a present, and never branches on the kind itself.
    private enum RenderTargetKind: Equatable {
        case swapChain
        case offscreen
    }

    private var renderTargetKind: RenderTargetKind = .swapChain
    private var offscreenTexture: UnsafeMutablePointer<ID3D11Texture2D>?
    /// Driver preference the current offscreen attach was made with, so a
    /// device-loss rebuild recreates the same kind of device.
    private var offscreenDriver: OffscreenDriver = .hardwareFirst

    /// Which D3D11 driver an offscreen attach creates its device with.
    public enum OffscreenDriver: Equatable, Sendable {
        /// Prefer the GPU, fall back to the software rasterizer.
        case hardwareFirst
        /// Prefer WARP. The software rasterizer is present on every
        /// Windows install and produces the same pixels on every machine,
        /// which is what cross-backend pixel assertions need.
        case warpFirst

        fileprivate var driverTypes: [D3D_DRIVER_TYPE] {
            switch self {
            case .hardwareFirst:
                return [D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP]
            case .warpFirst:
                return [D3D_DRIVER_TYPE_WARP, D3D_DRIVER_TYPE_HARDWARE]
            }
        }
    }

    // MARK: - Shader Pipeline State

    private var quadVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var quadPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var imageVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var imagePS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var glyphVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var glyphPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var shadowVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var shadowPS: UnsafeMutablePointer<ID3D11PixelShader>?

    // MARK: - Shared GPU Resources

    private var frameUniformBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var blendState: UnsafeMutablePointer<ID3D11BlendState>?
    private var rasterizerState: UnsafeMutablePointer<ID3D11RasterizerState>?
    private var samplerState: UnsafeMutablePointer<ID3D11SamplerState>?

    // MARK: - Dynamic Instance Buffers

    // Capacities grow with the scene and are restored to these on detach,
    // so a re-attached renderer starts from the same footprint a fresh one
    // would rather than inheriting the peak of the previous session.
    private static let initialQuadInstanceCapacity = 256
    private static let initialImageInstanceCapacity = 256
    private static let initialGlyphInstanceCapacity = 512
    private static let initialShadowInstanceCapacity = 256

    private var quadInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var quadInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var quadInstanceCapacity = D3D11BatchRenderer.initialQuadInstanceCapacity

    private var imageInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var imageInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var imageInstanceCapacity = D3D11BatchRenderer.initialImageInstanceCapacity

    private var glyphInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var glyphInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var glyphInstanceCapacity = D3D11BatchRenderer.initialGlyphInstanceCapacity

    private var shadowInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var shadowInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var shadowInstanceCapacity = D3D11BatchRenderer.initialShadowInstanceCapacity

    private var glyphAtlasTexture: UnsafeMutablePointer<ID3D11Texture2D>?
    private var glyphAtlasSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var glyphAtlasSize = IntSize.zero
    private var pixelGlyphAtlasTexture: UnsafeMutablePointer<ID3D11Texture2D>?
    private var pixelGlyphAtlasSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var pixelGlyphAtlasSize = IntSize.zero

    private struct ImageResourceEntry {
        var bitmap: BitmapSurface
        var texture: UnsafeMutablePointer<ID3D11Texture2D>?
        var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    }

    private var imageResources: [Int32: ImageResourceEntry] = [:]

    // Path rasterization is CPU-bound (we don't yet have a real GPU
    // tessellator), so caching the resulting bitmap + GPU texture across
    // frames is the difference between "redo every frame" and "upload once
    // per path shape". Keys are normalized to a (0,0) origin so translating
    // the path doesn't bust the cache; the draw call still positions the
    // resulting texture at the original bounds.origin.
    private struct CachedPathRender {
        let key: PathPrimitive
        var texture: UnsafeMutablePointer<ID3D11Texture2D>
        var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>
        var bitmapSize: IntSize
        var lastUsedFrame: UInt64
    }

    private var pathRenderCache: [CachedPathRender] = []
    private var frameCounter: UInt64 = 0
    private static let pathCacheStaleFrames: UInt64 = 60
    private static let pathCacheMaxEntries = 256
    // Test-observable counters so we can verify the cache is actually being
    // hit across frames.
    internal private(set) var pathCacheHits: UInt64 = 0
    internal private(set) var pathCacheMisses: UInt64 = 0

    internal var pathCacheEntryCountForTesting: Int { pathRenderCache.count }

    // Backdrop blur engine for Material quads (quads carrying a blurRadius).
    // Created lazily on the first blurred quad and recreated whenever the
    // D3D11 device changes so device-loss reattach can't leave it bound to
    // a dead device.
    private var blurEngine: D3D11BackdropBlurEngine?

    /// Set when a blurred quad failed for a reason that is not device loss
    /// — most plausibly a mid-frame ping-pong texture allocation under
    /// memory pressure, which is the largest allocation the renderer makes
    /// and the one most likely to fail on a 4K surface. Material quads then
    /// take the plain quad path (edge-softening instead of a real frost)
    /// until the surface size changes, so a failing effect costs frostiness
    /// rather than every subsequent frame's `Present`.
    private var blurDegraded = false

    /// True once a blur failure has downgraded materials to the plain path.
    internal var blurDegradedForTesting: Bool { blurDegraded }

    /// Test seam: forces every blurred quad to fail the way an
    /// out-of-memory ping-pong allocation would, so the containment path
    /// is reachable without exhausting video memory.
    internal var failBlurredQuadsForTesting = false

    // MARK: - Surface State

    /// The window surface this renderer is attached to, or nil when it is
    /// attached offscreen. `targetPixelSize` — not this — is what the
    /// frame path sizes itself from, so both targets share one code path.
    private var surface: SurfaceDescriptor?
    private var targetPixelSize: IntSize = .zero
    private var hwnd: HWND?

    // MARK: - Device Loss

    public private(set) var presentationState = PresentationState()

    /// Consecutive device rebuilds without an intervening present that
    /// reached the screen. Only a clean present clears it, so it bounds a
    /// device-loss storm rather than a session.
    private var deviceLostRecoveryAttempts = 0

    /// Set by a successful rebuild so the next `render` returns without
    /// drawing. GPUI does the same: presenting immediately after recreating
    /// a device tends to produce a blank frame.
    private var skipNextFrameAfterDeviceLoss = false

    /// Test seam for the recovery wait. Production blocks the main actor for
    /// a beat, which is what the driver needs and what GPUI does; tests
    /// substitute a no-op so a recovery suite does not sleep for seconds.
    internal var deviceLostBackoffHandler: (Double) -> Void = { seconds in
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - Init

    public init() {}

    /// Every COM object this renderer currently owns, counted one stored
    /// property at a time. `detach()` must bring this to zero; a new field
    /// that forgets to release itself shows up here rather than as a leak
    /// nobody can see. The blur engine and the path cache report their own
    /// holdings through `blurEngineOwnsResourcesForTesting` and
    /// `pathCacheEntryCountForTesting`.
    internal var liveCOMObjectCountForTesting: Int {
        var count = 0
        func tally(_ pointer: UnsafeMutableRawPointer?) {
            if pointer != nil {
                count += 1
            }
        }

        tally(device.map(UnsafeMutableRawPointer.init))
        tally(deviceContext.map(UnsafeMutableRawPointer.init))
        tally(dxgiFactory.map(UnsafeMutableRawPointer.init))
        tally(swapChain.map(UnsafeMutableRawPointer.init))
        tally(renderTargetView.map(UnsafeMutableRawPointer.init))
        tally(offscreenTexture.map(UnsafeMutableRawPointer.init))

        tally(quadVS.map(UnsafeMutableRawPointer.init))
        tally(quadPS.map(UnsafeMutableRawPointer.init))
        tally(imageVS.map(UnsafeMutableRawPointer.init))
        tally(imagePS.map(UnsafeMutableRawPointer.init))
        tally(glyphVS.map(UnsafeMutableRawPointer.init))
        tally(glyphPS.map(UnsafeMutableRawPointer.init))
        tally(shadowVS.map(UnsafeMutableRawPointer.init))
        tally(shadowPS.map(UnsafeMutableRawPointer.init))

        tally(frameUniformBuffer.map(UnsafeMutableRawPointer.init))
        tally(blendState.map(UnsafeMutableRawPointer.init))
        tally(rasterizerState.map(UnsafeMutableRawPointer.init))
        tally(samplerState.map(UnsafeMutableRawPointer.init))

        tally(quadInstanceBuffer.map(UnsafeMutableRawPointer.init))
        tally(quadInstanceSRV.map(UnsafeMutableRawPointer.init))
        tally(imageInstanceBuffer.map(UnsafeMutableRawPointer.init))
        tally(imageInstanceSRV.map(UnsafeMutableRawPointer.init))
        tally(glyphInstanceBuffer.map(UnsafeMutableRawPointer.init))
        tally(glyphInstanceSRV.map(UnsafeMutableRawPointer.init))
        tally(shadowInstanceBuffer.map(UnsafeMutableRawPointer.init))
        tally(shadowInstanceSRV.map(UnsafeMutableRawPointer.init))

        tally(glyphAtlasTexture.map(UnsafeMutableRawPointer.init))
        tally(glyphAtlasSRV.map(UnsafeMutableRawPointer.init))
        tally(pixelGlyphAtlasTexture.map(UnsafeMutableRawPointer.init))
        tally(pixelGlyphAtlasSRV.map(UnsafeMutableRawPointer.init))

        for entry in imageResources.values {
            tally(entry.texture.map(UnsafeMutableRawPointer.init))
            tally(entry.srv.map(UnsafeMutableRawPointer.init))
        }
        for entry in pathRenderCache {
            tally(UnsafeMutableRawPointer(entry.texture))
            tally(UnsafeMutableRawPointer(entry.srv))
        }

        return count
    }

    /// True while a backdrop-blur engine is alive and holding device
    /// resources of its own.
    internal var blurEngineOwnsResourcesForTesting: Bool { blurEngine != nil }

    /// The `ID3D11Device` address this renderer is currently bound to, so a
    /// test can tell a genuine device recreation from a re-used one.
    internal var deviceAddressForTesting: UInt {
        device.map { UInt(bitPattern: $0) } ?? 0
    }

    public enum AtlasSource: Equatable {
        case snapshot
        case cached
    }

    public struct CachedResources: Equatable {
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

    public enum RenderStep: Equatable {
        case shadows(layerIndex: Int, range: Range<Int>)
        case quads(layerIndex: Int, range: Range<Int>)
        case glyphs(layerIndex: Int, range: Range<Int>, atlasSource: AtlasSource)
        case pixelGlyphs(layerIndex: Int, range: Range<Int>, atlasSource: AtlasSource)
        case images(layerIndex: Int, range: Range<Int>, textureID: Int32)
        case paths(layerIndex: Int, range: Range<Int>)
    }

    /// One piece of a quad batch after splitting around Material quads.
    /// Normal runs keep the single instanced draw; each blurred quad is
    /// drawn individually through the backdrop blur engine so the blur
    /// samples the scene exactly as painted before that quad.
    enum QuadBatchSegment: Equatable {
        case normal(range: Range<Int>)
        case blurred(index: Int)
    }

    /// Splits a quad range into normal runs and individual blurred quads,
    /// preserving presentation order. A quad takes the blurred path when
    /// its blurRadius truncates to ≥ 1 (same predicate as the CPU
    /// rasterizer's `Int(quad.blurRadius) > 0`). Rotated blur quads take
    /// the blurred path too: the engine blurs the axis-aligned bounding
    /// box of the rotated footprint (the same window the CPU rasterizer
    /// blurs), so both backends produce a real backdrop blur instead of
    /// the historic edge-softening fallback.
    static func splitQuadRangeForBackdropBlur(
        _ quads: [QuadPrimitive],
        range: Range<Int>
    ) -> [QuadBatchSegment] {
        var segments: [QuadBatchSegment] = []
        var runStart = range.lowerBound
        for index in range {
            guard quads.indices.contains(index) else { continue }
            let quad = quads[index]
            let isBlurred = Int(quad.blurRadius) > 0
            if isBlurred {
                if runStart < index {
                    segments.append(.normal(range: runStart..<index))
                }
                segments.append(.blurred(index: index))
                runStart = index + 1
            }
        }
        if runStart < range.upperBound {
            segments.append(.normal(range: runStart..<range.upperBound))
        }
        return segments
    }

    public struct RenderPlan: Equatable {
        public var glyphAtlasSource: AtlasSource?
        public var pixelGlyphAtlasSource: AtlasSource?
        public var steps: [RenderStep]
        public var resultingResources: CachedResources

        public init(
            glyphAtlasSource: AtlasSource? = nil,
            pixelGlyphAtlasSource: AtlasSource? = nil,
            steps: [RenderStep] = [],
            resultingResources: CachedResources = CachedResources()
        ) {
            self.glyphAtlasSource = glyphAtlasSource
            self.pixelGlyphAtlasSource = pixelGlyphAtlasSource
            self.steps = steps
            self.resultingResources = resultingResources
        }
    }

    public func bindImageResource(_ bitmap: BitmapSurface, for textureID: Int32) {
        guard textureID >= 0 else {
            return
        }

        if var existing = imageResources.removeValue(forKey: textureID) {
            releaseCOM(&existing.srv)
            releaseCOM(&existing.texture)
        }

        imageResources[textureID] = ImageResourceEntry(bitmap: bitmap, texture: nil, srv: nil)
    }

    public func bindResources(for scene: GPUIScene) {
        for binding in scene.imageResources {
            bindImageResource(binding.bitmap, for: binding.textureID)
        }
    }

    /// Releases the GPU side of every bound image and forgets the bindings.
    /// The bitmaps themselves are re-supplied by `bindResources(for:)` on
    /// the next frame, so nothing is lost by dropping them with the device.
    private func releaseAllImageResources() {
        while let (textureID, _) = imageResources.first {
            guard var entry = imageResources.removeValue(forKey: textureID) else {
                continue
            }
            releaseCOM(&entry.srv)
            releaseCOM(&entry.texture)
        }
    }

    internal var cachedResourcesForTesting: CachedResources {
        CachedResources(
            hasGlyphAtlas: glyphAtlasSRV != nil,
            hasPixelGlyphAtlas: pixelGlyphAtlasSRV != nil,
            boundImageTextureIDs: Set(imageResources.keys)
        )
    }

    public static func makeRenderPlan(
        for scene: GPUIScene,
        cachedResources: CachedResources = CachedResources()
    ) throws -> RenderPlan {
        let usesGlyphs = scene.layers.contains { !$0.glyphs.isEmpty }
        let usesPixelGlyphs = scene.layers.contains { !$0.pixelGlyphs.isEmpty }

        let glyphAtlasSource: AtlasSource?
        if usesGlyphs {
            if scene.glyphAtlas != nil {
                glyphAtlasSource = .snapshot
            } else if cachedResources.hasGlyphAtlas {
                glyphAtlasSource = .cached
            } else {
                throw BatchRendererError(
                    operation: "Resolve glyph atlas resources",
                    hresult: batchHresultInvalidArgument,
                    details:
                        "Scene contains glyph primitives but no native glyph atlas snapshot or cached upload is available.",
                    failureKind: .sceneContent
                )
            }
        } else {
            glyphAtlasSource = nil
        }

        let pixelGlyphAtlasSource: AtlasSource?
        if usesPixelGlyphs {
            if scene.pixelGlyphAtlas != nil {
                pixelGlyphAtlasSource = .snapshot
            } else if cachedResources.hasPixelGlyphAtlas {
                pixelGlyphAtlasSource = .cached
            } else {
                throw BatchRendererError(
                    operation: "Resolve pixel glyph atlas resources",
                    hresult: batchHresultInvalidArgument,
                    details:
                        "Scene contains pixel glyph primitives but no pixel glyph atlas snapshot or cached upload is available.",
                    failureKind: .sceneContent
                )
            }
        } else {
            pixelGlyphAtlasSource = nil
        }

        var unresolvedTextureIDs = Set<Int32>()
        for layer in scene.layers {
            for image in layer.images
            where image.textureID < 0 || !cachedResources.boundImageTextureIDs.contains(image.textureID) {
                unresolvedTextureIDs.insert(image.textureID)
            }
        }

        if !unresolvedTextureIDs.isEmpty {
            let sortedIDs = unresolvedTextureIDs.sorted()
            let joinedIDs = sortedIDs.map(String.init).joined(separator: ", ")
            throw BatchRendererError(
                operation: "Resolve image resources",
                hresult: batchHresultInvalidArgument,
                details: "Scene contains image primitives without valid bound resources for texture IDs: \(joinedIDs).",
                failureKind: .sceneContent
            )
        }

        var steps: [RenderStep] = []
        for (layerIndex, layer) in scene.layers.enumerated() {
            for operation in layer.paintOperations {
                let range = operation.startIndex..<(operation.startIndex + operation.count)
                switch operation.kind {
                case .shadow:
                    steps.append(.shadows(layerIndex: layerIndex, range: range))
                case .quad:
                    steps.append(.quads(layerIndex: layerIndex, range: range))
                case .glyph:
                    if let glyphAtlasSource {
                        steps.append(.glyphs(layerIndex: layerIndex, range: range, atlasSource: glyphAtlasSource))
                    }
                case .pixelGlyph:
                    if let pixelGlyphAtlasSource {
                        steps.append(
                            .pixelGlyphs(layerIndex: layerIndex, range: range, atlasSource: pixelGlyphAtlasSource))
                    }
                case .image:
                    var runStart = range.lowerBound
                    while runStart < range.upperBound {
                        let textureID = layer.images[runStart].textureID
                        var runEnd = runStart + 1
                        while runEnd < range.upperBound, layer.images[runEnd].textureID == textureID {
                            runEnd += 1
                        }
                        steps.append(.images(layerIndex: layerIndex, range: runStart..<runEnd, textureID: textureID))
                        runStart = runEnd
                    }
                case .path:
                    steps.append(.paths(layerIndex: layerIndex, range: range))
                }
            }
        }

        var resultingResources = cachedResources
        resultingResources.hasGlyphAtlas = cachedResources.hasGlyphAtlas || scene.glyphAtlas != nil
        resultingResources.hasPixelGlyphAtlas = cachedResources.hasPixelGlyphAtlas || scene.pixelGlyphAtlas != nil
        return RenderPlan(
            glyphAtlasSource: glyphAtlasSource,
            pixelGlyphAtlasSource: pixelGlyphAtlasSource,
            steps: steps,
            resultingResources: resultingResources
        )
    }

    // MARK: - BatchRenderBackend

    public func attach(to surface: SurfaceDescriptor) throws {
        guard let hwnd = unsafeBitCast(surface.windowHandle.rawPointer, to: HWND?.self) else {
            throw BatchRendererError(operation: "Resolve HWND", hresult: batchHresultHandle)
        }

        // Attach always starts from nothing. Re-attach is how the host
        // recovers from a failed backend, so keeping the previous device
        // would re-bind a possibly-removed one, and keeping the previous
        // swap chain would leave a second flip-model chain on this HWND —
        // the two wedges this teardown exists to prevent.
        detach()
        // An externally requested attach is a fresh start: the device-loss
        // budget measures one storm, and this is not a continuation of it.
        deviceLostRecoveryAttempts = 0

        self.surface = surface
        self.targetPixelSize = surface.pixelSize
        self.hwnd = hwnd

        try createDeviceIfNeeded()
        try createFactoryIfNeeded()
        try createPipelineIfNeeded()
        try createSwapChain(size: surface.pixelSize)
        try createRenderTargetView()

        isAttached = true
    }

    /// Attaches to an offscreen render target instead of a window swap
    /// chain, so `render` / `resize` / present run without an HWND.
    ///
    /// The device, pipeline, instance buffers, atlases and blur engine are
    /// exactly the windowed path's; only the destination differs, and the
    /// offscreen texture uses the same `B8G8R8A8_UNORM` format as the swap
    /// chain so readback bytes match what a window would have shown.
    /// `readOffscreenPixels()` returns the result.
    public func attachOffscreen(size: IntSize, driver: OffscreenDriver = .hardwareFirst) throws {
        // Same contract as the windowed attach: start from nothing, so a
        // swap chain left over from a previous windowed attach cannot keep
        // pinning an HWND this renderer no longer draws to.
        detach()
        deviceLostRecoveryAttempts = 0

        self.targetPixelSize = size
        renderTargetKind = .offscreen
        offscreenDriver = driver

        try createDeviceIfNeeded(driverTypes: driver.driverTypes)
        try createPipelineIfNeeded()
        try createOffscreenTarget(size: size)

        isAttached = true
    }

    /// Releases every D3D11 object this renderer owns and returns it to the
    /// pre-attach state.
    ///
    /// Ordering follows the dependency chain: unbind the pipeline from the
    /// immediate context and flush so the driver stops referencing the
    /// views, then release views before the resources they view, then the
    /// swap chain (which pins the HWND) before the device that created it.
    /// Everything runs on the main actor, where the immediate context is
    /// used — there is no thread on which a deferred release would be safe.
    public func detach() {
        if let deviceContext {
            var noTargets: UnsafeMutablePointer<ID3D11RenderTargetView>?
            deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &noTargets, nil)
            deviceContext.pointee.lpVtbl.pointee.ClearState(deviceContext)
            deviceContext.pointee.lpVtbl.pointee.Flush(deviceContext)
        }

        blurEngine?.detach()
        blurEngine = nil
        releaseAllCachedPaths()
        releaseAllImageResources()

        releaseCOM(&glyphAtlasSRV)
        releaseCOM(&glyphAtlasTexture)
        glyphAtlasSize = .zero
        releaseCOM(&pixelGlyphAtlasSRV)
        releaseCOM(&pixelGlyphAtlasTexture)
        pixelGlyphAtlasSize = .zero

        releaseCOM(&quadInstanceSRV)
        releaseCOM(&quadInstanceBuffer)
        quadInstanceCapacity = Self.initialQuadInstanceCapacity
        releaseCOM(&imageInstanceSRV)
        releaseCOM(&imageInstanceBuffer)
        imageInstanceCapacity = Self.initialImageInstanceCapacity
        releaseCOM(&glyphInstanceSRV)
        releaseCOM(&glyphInstanceBuffer)
        glyphInstanceCapacity = Self.initialGlyphInstanceCapacity
        releaseCOM(&shadowInstanceSRV)
        releaseCOM(&shadowInstanceBuffer)
        shadowInstanceCapacity = Self.initialShadowInstanceCapacity

        releaseCOM(&samplerState)
        releaseCOM(&rasterizerState)
        releaseCOM(&blendState)
        releaseCOM(&frameUniformBuffer)

        releaseCOM(&shadowPS)
        releaseCOM(&shadowVS)
        releaseCOM(&glyphPS)
        releaseCOM(&glyphVS)
        releaseCOM(&imagePS)
        releaseCOM(&imageVS)
        releaseCOM(&quadPS)
        releaseCOM(&quadVS)

        releaseCOM(&renderTargetView)
        releaseCOM(&offscreenTexture)
        releaseCOM(&swapChain)
        releaseCOM(&dxgiFactory)
        releaseCOM(&deviceContext)
        releaseCOM(&device)
        // No device, no generation: every device-keyed cache is now stale by
        // construction rather than by comparison against a freed address.
        deviceGeneration = 0

        renderTargetKind = .swapChain
        surface = nil
        hwnd = nil
        targetPixelSize = .zero
        blurDegraded = false
        skipNextFrameAfterDeviceLoss = false
        presentationState = PresentationState()
        isAttached = false
        // `deviceLostRecoveryAttempts` deliberately survives: detach is a
        // *step* of device-loss recovery, and resetting the budget here
        // would make the bounded retry unbounded.
    }

    deinit {
        // Backstop, not a teardown path: `detach()` has to run on the main
        // actor because it drives the immediate context, and a nonisolated
        // deinit cannot. The host calls `detach()` from `windowWillClose`
        // and on every presenter switch; reaching here still attached means
        // one of those call sites was missed, so say so loudly in debug
        // builds instead of leaking silently.
        assert(
            !isAttachedMirror,
            "D3D11BatchRenderer was deallocated while still attached — its device, swap chain and "
                + "atlases leak. Call detach() from the owner's teardown."
        )
    }

    public func resize(to size: IntSize) throws {
        surface?.pixelSize = size
        targetPixelSize = size
        // A new surface size means new ping-pong allocations, so the
        // condition that degraded the blur may no longer hold: give the
        // real effect another chance rather than staying plain for the rest
        // of the session.
        blurDegraded = false

        guard isAttached else {
            return
        }

        if size.width <= 0 || size.height <= 0 {
            return
        }

        switch renderTargetKind {
        case .swapChain:
            guard let swapChain else {
                return
            }

            releaseCOM(&renderTargetView)
            deviceContext?.pointee.lpVtbl.pointee.ClearState(deviceContext)

            let hr = swapChain.pointee.lpVtbl.pointee.ResizeBuffers(
                swapChain,
                0,
                UINT(max(size.width, 1)),
                UINT(max(size.height, 1)),
                DXGI_FORMAT_UNKNOWN,
                0
            )
            try throwIfFailed(hr, operation: "IDXGISwapChain1.ResizeBuffers")
            try createRenderTargetView()
        case .offscreen:
            releaseCOM(&renderTargetView)
            releaseCOM(&offscreenTexture)
            deviceContext?.pointee.lpVtbl.pointee.ClearState(deviceContext)
            try createOffscreenTarget(size: size)
        }
    }

    public func render(scene: GPUIScene) throws {
        guard isAttached, hasRenderTarget else {
            return
        }

        // One frame is skipped after a device rebuild: a present issued
        // immediately after recreating the device tends to come back blank.
        // `needsImmediateRepaint` stays set, so the host schedules the frame
        // that actually lands.
        if skipNextFrameAfterDeviceLoss {
            skipNextFrameAfterDeviceLoss = false
            return
        }

        let surfacePixelSize = targetPixelSize
        if surfacePixelSize.width <= 0 || surfacePixelSize.height <= 0 {
            return
        }

        frameCounter &+= 1
        evictStaleCachedPaths()
        // Re-fetch the render-target guards: the eviction call above is
        // pure local work but a future hook (e.g. device-loss recovery) might
        // teardown the render target mid-frame and we want to fail safe.
        guard isAttached, hasRenderTarget else {
            return
        }

        // `blendState` / `rasterizerState` / `frameUniformBuffer` are read
        // by `bindFramePipelineState`; they are checked here so a partially
        // created pipeline never reaches a draw.
        guard
            let renderTargetView,
            let deviceContext,
            blendState != nil,
            rasterizerState != nil,
            frameUniformBuffer != nil
        else {
            return
        }

        var finishedScene = scene
        finishedScene.finish()
        let renderPlan = try Self.makeRenderPlan(for: finishedScene, cachedResources: cachedResourcesForTesting)

        bindFramePipelineState(deviceContext: deviceContext, surfaceSize: surfacePixelSize)

        let cc = finishedScene.clearColor
        let clearValues: [FLOAT] = [cc.red, cc.green, cc.blue, cc.alpha]
        clearValues.withUnsafeBufferPointer { buffer in
            deviceContext.pointee.lpVtbl.pointee.ClearRenderTargetView(
                deviceContext, renderTargetView, buffer.baseAddress)
        }

        try updateFrameUniforms(surfaceSize: surfacePixelSize)
        if renderPlan.glyphAtlasSource == .snapshot, let glyphAtlas = finishedScene.glyphAtlas {
            try updateGlyphAtlasTexture(
                glyphAtlas,
                texture: &glyphAtlasTexture,
                srv: &glyphAtlasSRV,
                size: &glyphAtlasSize
            )
        }
        if renderPlan.pixelGlyphAtlasSource == .snapshot, let pixelGlyphAtlas = finishedScene.pixelGlyphAtlas {
            try updateGlyphAtlasTexture(
                pixelGlyphAtlas,
                texture: &pixelGlyphAtlasTexture,
                srv: &pixelGlyphAtlasSRV,
                size: &pixelGlyphAtlasSize
            )
        }

        for step in renderPlan.steps {
            switch step {
            case .shadows(let layerIndex, let range):
                let layer = finishedScene.layers[layerIndex]
                try renderBatch(
                    layer.shadows,
                    range: range,
                    capacity: &shadowInstanceCapacity,
                    buffer: &shadowInstanceBuffer,
                    srv: &shadowInstanceSRV,
                    vs: shadowVS, ps: shadowPS,
                    label: "shadow",
                    deviceContext: deviceContext
                )
            case .quads(let layerIndex, let range):
                let layer = finishedScene.layers[layerIndex]
                // Material quads (blurRadius ≥ 1) need the real backdrop
                // blur, which breaks batching: each one snapshots the
                // scene-so-far, blurs it, and composites its tint before
                // any later primitive draws. Split the range into normal
                // runs (still one instanced draw each) around them so
                // paintOperations order is preserved exactly.
                for segment in Self.splitQuadRangeForBackdropBlur(layer.quads, range: range) {
                    switch segment {
                    case .normal(let subRange):
                        try renderBatch(
                            layer.quads,
                            range: subRange,
                            capacity: &quadInstanceCapacity,
                            buffer: &quadInstanceBuffer,
                            srv: &quadInstanceSRV,
                            vs: quadVS, ps: quadPS,
                            label: "quad",
                            deviceContext: deviceContext
                        )
                    case .blurred(let index):
                        try renderMaterialQuad(
                            layer.quads,
                            index: index,
                            deviceContext: deviceContext,
                            surfaceSize: surfacePixelSize
                        )
                    }
                }
            case .glyphs(let layerIndex, let range, _):
                let layer = finishedScene.layers[layerIndex]
                try renderGlyphBatch(
                    layer.glyphs,
                    range: range,
                    atlasSRV: glyphAtlasSRV,
                    deviceContext: deviceContext
                )
            case .pixelGlyphs(let layerIndex, let range, _):
                let layer = finishedScene.layers[layerIndex]
                try renderGlyphBatch(
                    layer.pixelGlyphs,
                    range: range,
                    atlasSRV: pixelGlyphAtlasSRV,
                    deviceContext: deviceContext
                )
            case .images(let layerIndex, let range, let textureID):
                let layer = finishedScene.layers[layerIndex]
                let imageSRV = try ensureImageResourceSRV(for: textureID)
                try renderImageBatch(
                    layer.images,
                    range: range,
                    deviceContext: deviceContext,
                    textureSRV: imageSRV
                )
            case .paths(let layerIndex, let range):
                let layer = finishedScene.layers[layerIndex]
                try renderPathBatch(
                    layer.paths,
                    range: range,
                    deviceContext: deviceContext
                )
            }
        }

        try presentFrame()
    }

    /// Binds every piece of pipeline state the batched draws assume: the
    /// frame's render target, the full-surface viewport, the rasterizer and
    /// input-assembler state, the premultiplied source-over blend state and
    /// the frame-uniform buffer at VS `b0`.
    ///
    /// Called once before the step loop and again after every blurred quad.
    /// The backdrop blur engine replaces all five while it works — its own
    /// ping-pong render targets, region-sized viewports, a null blend state
    /// for the blur passes, and its own byte-identical frame-uniform buffer
    /// — and cannot restore them, because only this type knows what they
    /// were. Re-binding here makes that a real invariant instead of a prose
    /// post-condition that happens to hold while the two frame-uniform
    /// layouts stay identical.
    private func bindFramePipelineState(
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        surfaceSize: IntSize
    ) {
        var targetView: UnsafeMutablePointer<ID3D11RenderTargetView>? = renderTargetView
        deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &targetView, nil)

        var viewport = D3D11_VIEWPORT(
            TopLeftX: 0,
            TopLeftY: 0,
            Width: FLOAT(surfaceSize.width),
            Height: FLOAT(surfaceSize.height),
            MinDepth: 0,
            MaxDepth: 1
        )
        deviceContext.pointee.lpVtbl.pointee.RSSetViewports(deviceContext, 1, &viewport)
        deviceContext.pointee.lpVtbl.pointee.RSSetState(deviceContext, rasterizerState)
        deviceContext.pointee.lpVtbl.pointee.IASetInputLayout(deviceContext, nil)
        deviceContext.pointee.lpVtbl.pointee.IASetPrimitiveTopology(
            deviceContext, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST)

        let blendFactor: [FLOAT] = [0, 0, 0, 0]
        blendFactor.withUnsafeBufferPointer { buffer in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(
                deviceContext, blendState, buffer.baseAddress, UINT.max)
        }

        var cbuf: UnsafeMutablePointer<ID3D11Buffer>? = frameUniformBuffer
        deviceContext.pointee.lpVtbl.pointee.VSSetConstantBuffers(deviceContext, 0, 1, &cbuf)
    }

    // MARK: - Render Target Plumbing

    /// True once a target exists to draw into, whichever kind is attached.
    private var hasRenderTarget: Bool {
        switch renderTargetKind {
        case .swapChain:
            return swapChain != nil
        case .offscreen:
            return offscreenTexture != nil
        }
    }

    /// Ends the frame on whichever target is attached: a real DXGI present
    /// for the windowed swap chain, a context flush for the offscreen
    /// target (which has nothing to present, but must have its draws
    /// submitted before anything reads the texture back).
    private func presentFrame() throws {
        switch renderTargetKind {
        case .swapChain:
            guard let swapChain else {
                return
            }
            let hr = swapChain.pointee.lpVtbl.pointee.Present(swapChain, 1, 0)
            try handlePresentResult(hr)
        case .offscreen:
            deviceContext?.pointee.lpVtbl.pointee.Flush(deviceContext)
            // An offscreen target has no swap chain to fail, but a removed
            // device still shows up here, and the readback that follows
            // would otherwise return whatever the staging copy left behind.
            let removalReason = DeviceLostPolicy.removedReason(of: device)
            if DeviceLostPolicy.isDeviceLost(removalReason) {
                try recoverFromDeviceLoss(hresult: removalReason, operation: "ID3D11DeviceContext.Flush")
            } else {
                noteCleanPresent()
            }
        }
    }

    /// Turns a `Present` HRESULT into a decision instead of a sign test.
    private func handlePresentResult(_ hr: HRESULT) throws {
        switch DeviceLostPolicy.outcome(forPresent: hr) {
        case .presented:
            noteCleanPresent()
        case .occluded:
            // Not a failure and not device loss, but not vsync-paced
            // either — the host throttles on this rather than spinning.
            deviceLostRecoveryAttempts = 0
            presentationState = PresentationState(isOccluded: true, needsImmediateRepaint: false)
        case .deviceLost:
            try recoverFromDeviceLoss(hresult: hr, operation: "IDXGISwapChain1.Present")
        case .failed:
            throw BatchRendererError(operation: "IDXGISwapChain1.Present", hresult: hr)
        }
    }

    private func noteCleanPresent() {
        deviceLostRecoveryAttempts = 0
        presentationState = PresentationState()
    }

    /// Rebuilds the device after it was removed, reset or hung.
    ///
    /// GPUI's shape: unbind the render targets, `ClearState`, `Flush`,
    /// release every device object (all of which `detach()` already does in
    /// that order), wait a beat, recreate, then skip one frame. Bounded by
    /// ``DeviceLostPolicy/maxRecoveryAttempts`` consecutive attempts without
    /// an intervening clean present; past that the failure is the host's,
    /// typed `.deviceLost`, and this renderer is left detached so the host's
    /// downgrade does not inherit a half-built device.
    private func recoverFromDeviceLoss(hresult: HRESULT, operation: String) throws {
        deviceLostRecoveryAttempts += 1
        let attempt = deviceLostRecoveryAttempts
        let removalReason = DeviceLostPolicy.removedReason(of: device)
        renderLog(
            "[D3D11BatchRenderer] Device lost during \(operation) "
                + "(attempt \(attempt)/\(DeviceLostPolicy.maxRecoveryAttempts)). "
                + "HRESULT \(DeviceLostPolicy.describe(hresult)), "
                + "GetDeviceRemovedReason \(DeviceLostPolicy.describe(removalReason))."
        )

        guard attempt <= DeviceLostPolicy.maxRecoveryAttempts else {
            detach()
            throw BatchRendererError(
                operation: operation,
                hresult: hresult,
                details:
                    "Device rebuild failed \(DeviceLostPolicy.maxRecoveryAttempts) times in a row; "
                    + "the adapter is not coming back on its own.",
                failureKind: .deviceLost
            )
        }

        let kind = renderTargetKind
        let previousSurface = surface
        let previousSize = targetPixelSize
        let previousDriver = offscreenDriver

        detach()
        deviceLostRecoveryAttempts = attempt
        deviceLostBackoffHandler(DeviceLostPolicy.backoffSeconds(forAttempt: attempt))

        do {
            switch kind {
            case .swapChain:
                guard let previousSurface else {
                    throw BatchRendererError(
                        operation: operation,
                        hresult: hresult,
                        details: "No surface descriptor survived teardown, so the swap chain cannot be rebuilt.",
                        failureKind: .deviceLost
                    )
                }
                try attach(to: previousSurface)
                if previousSize != previousSurface.pixelSize {
                    try resize(to: previousSize)
                }
            case .offscreen:
                try attachOffscreen(size: previousSize, driver: previousDriver)
            }
        } catch {
            detach()
            deviceLostRecoveryAttempts = attempt
            throw BatchRendererError(
                operation: operation,
                hresult: hresult,
                details: "Device rebuild after device loss failed: \(error)",
                failureKind: .deviceLost
            )
        }

        // `attach` cleared the budget as an external attach would; this one
        // is a recovery step, so put the storm count back.
        deviceLostRecoveryAttempts = attempt
        skipNextFrameAfterDeviceLoss = true
        presentationState = PresentationState(isOccluded: false, needsImmediateRepaint: true)
    }

    /// Forces the device-loss path as if `Present` had returned
    /// `DXGI_ERROR_DEVICE_REMOVED`, so recovery is testable without a TDR.
    internal func simulateDeviceLossForTesting() throws {
        try recoverFromDeviceLoss(hresult: DeviceLostPolicy.deviceRemoved, operation: "SimulatedDeviceLoss")
    }

    /// The texture the current frame is drawing into, returned with a
    /// reference the caller owns (release it with `releaseCOMPointer`).
    /// The backdrop blur engine needs the pixels painted so far, and the
    /// swap chain hands those out only through `GetBuffer`.
    private func acquireBackBuffer() throws -> UnsafeMutablePointer<ID3D11Texture2D> {
        switch renderTargetKind {
        case .swapChain:
            guard let swapChain else {
                throw BatchRendererError(operation: "Resolve back buffer", hresult: batchHresultHandle)
            }
            var backBufferRaw: UnsafeMutableRawPointer?
            var iid = IID_ID3D11Texture2D
            let bufferHR = swapChain.pointee.lpVtbl.pointee.GetBuffer(swapChain, 0, &iid, &backBufferRaw)
            try throwIfFailed(bufferHR, operation: "IDXGISwapChain1.GetBuffer(backdropBlur)")
            guard let texture = backBufferRaw?.assumingMemoryBound(to: ID3D11Texture2D.self) else {
                throw BatchRendererError(
                    operation: "IDXGISwapChain1.GetBuffer(backdropBlur)", hresult: batchHresultHandle)
            }
            return texture
        case .offscreen:
            guard let offscreenTexture else {
                throw BatchRendererError(operation: "Resolve back buffer", hresult: batchHresultHandle)
            }
            // Balance the +1 `GetBuffer` hands back so both cases hand the
            // caller an owned reference.
            retainCOM(offscreenTexture)
            return offscreenTexture
        }
    }

    private func createOffscreenTarget(size: IntSize) throws {
        guard let device else {
            throw BatchRendererError(
                operation: "Create offscreen render target",
                hresult: batchHresultHandle,
                details: "D3D11 device is not available."
            )
        }

        var descriptor = D3D11_TEXTURE2D_DESC()
        descriptor.Width = UINT(max(size.width, 1))
        descriptor.Height = UINT(max(size.height, 1))
        descriptor.MipLevels = 1
        descriptor.ArraySize = 1
        // Same format as the swap chain, so the shader output path and the
        // readback byte order match the windowed path exactly.
        descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_RENDER_TARGET.rawValue)

        let textureHR = makeCOM(into: &offscreenTexture) { texture in
            device.pointee.lpVtbl.pointee.CreateTexture2D(device, &descriptor, nil, &texture)
        }
        try throwIfFailed(textureHR, operation: "ID3D11Device.CreateTexture2D(offscreen)")

        guard let offscreenTexture else {
            throw BatchRendererError(operation: "CreateTexture2D(offscreen)", hresult: batchHresultHandle)
        }

        let resource = UnsafeMutableRawPointer(offscreenTexture).assumingMemoryBound(to: ID3D11Resource.self)
        let viewHR = makeCOM(into: &renderTargetView) { view in
            device.pointee.lpVtbl.pointee.CreateRenderTargetView(device, resource, nil, &view)
        }
        try throwIfFailed(viewHR, operation: "ID3D11Device.CreateRenderTargetView(offscreen)")
    }

    /// Reads the offscreen target back into a `BitmapSurface` — BGRA, the
    /// same byte order `GPUIRawSceneRasterizer` produces — so a rendered
    /// frame can be compared against the CPU reference pixel by pixel.
    ///
    /// The result is tagged premultiplied: it is the output of a
    /// premultiplied blend state. With the usual opaque clear colour the
    /// two conventions coincide byte for byte, which is why parity scenes
    /// clear to alpha 1.
    public func readOffscreenPixels() throws -> BitmapSurface {
        guard renderTargetKind == .offscreen, let offscreenTexture else {
            throw BatchRendererError(
                operation: "Read offscreen pixels",
                hresult: batchHresultInvalidArgument,
                details: "The renderer is not attached to an offscreen render target."
            )
        }
        guard let device, let deviceContext else {
            throw BatchRendererError(operation: "Read offscreen pixels", hresult: batchHresultHandle)
        }

        // Read the target's own dimensions rather than the requested size:
        // a zero-size resize leaves the previous texture in place, and a
        // staging copy has to match the source exactly.
        var descriptor = D3D11_TEXTURE2D_DESC()
        offscreenTexture.pointee.lpVtbl.pointee.GetDesc(offscreenTexture, &descriptor)
        let width = Int(descriptor.Width)
        let height = Int(descriptor.Height)
        descriptor.Usage = D3D11_USAGE_STAGING
        descriptor.BindFlags = 0
        descriptor.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_READ.rawValue)
        descriptor.MiscFlags = 0

        var staging: UnsafeMutablePointer<ID3D11Texture2D>?
        let stagingHR = device.pointee.lpVtbl.pointee.CreateTexture2D(device, &descriptor, nil, &staging)
        try throwIfFailed(stagingHR, operation: "ID3D11Device.CreateTexture2D(readback)")
        defer { releaseCOM(&staging) }
        guard let staging else {
            throw BatchRendererError(operation: "CreateTexture2D(readback)", hresult: batchHresultHandle)
        }

        let destination = UnsafeMutableRawPointer(staging).assumingMemoryBound(to: ID3D11Resource.self)
        let source = UnsafeMutableRawPointer(offscreenTexture).assumingMemoryBound(to: ID3D11Resource.self)
        deviceContext.pointee.lpVtbl.pointee.CopyResource(deviceContext, destination, source)

        var mapped = D3D11_MAPPED_SUBRESOURCE()
        let mapHR = deviceContext.pointee.lpVtbl.pointee.Map(deviceContext, destination, 0, D3D11_MAP_READ, 0, &mapped)
        try throwIfFailed(mapHR, operation: "ID3D11DeviceContext.Map(readback)")
        defer { deviceContext.pointee.lpVtbl.pointee.Unmap(deviceContext, destination, 0) }

        guard let mappedData = mapped.pData else {
            throw BatchRendererError(operation: "Map(readback)", hresult: batchHresultHandle)
        }

        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            for row in 0..<height {
                memcpy(
                    base.advanced(by: row * bytesPerRow),
                    mappedData.advanced(by: row * Int(mapped.RowPitch)),
                    bytesPerRow
                )
            }
        }

        return BitmapSurface(
            width: Int32(width),
            height: Int32(height),
            bytesPerRow: Int32(bytesPerRow),
            pixels: pixels,
            format: .bgra8Premultiplied
        )
    }

    // MARK: - Static Shader Validation (for testing)

    public static func validateBatchShadersForTesting() throws {
        var quadVSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchQuadShaderSource, entryPoint: "vsMain", profile: "vs_5_0")
        var quadPSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchQuadShaderSource, entryPoint: "psMain", profile: "ps_5_0")
        var imageVSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchImageShaderSource, entryPoint: "vsMain", profile: "vs_5_0")
        var imagePSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchImageShaderSource, entryPoint: "psMain", profile: "ps_5_0")
        var shadowVSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchShadowShaderSource, entryPoint: "vsMain", profile: "vs_5_0")
        var shadowPSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchShadowShaderSource, entryPoint: "psMain", profile: "ps_5_0")
        var glyphVSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: GlyphPipelineResources.vertexShaderSource,
            entryPoint: GlyphPipelineResources.vertexShaderEntryPoint, profile: "vs_5_0")
        var glyphPSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: GlyphPipelineResources.vertexShaderSource, entryPoint: GlyphPipelineResources.pixelShaderEntryPoint,
            profile: "ps_5_0")
        var materialVSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchMaterialQuadShaderSource, entryPoint: "vsMain", profile: "vs_5_0")
        var materialPSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchMaterialQuadShaderSource, entryPoint: "psMain", profile: "ps_5_0")
        var blurVSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchBackdropBlurShaderSource, entryPoint: "vsMain", profile: "vs_5_0")
        var blurPSBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: batchBackdropBlurShaderSource, entryPoint: "psMain", profile: "ps_5_0")
        releaseCOM(&blurPSBlob)
        releaseCOM(&blurVSBlob)
        releaseCOM(&materialPSBlob)
        releaseCOM(&materialVSBlob)
        releaseCOM(&glyphPSBlob)
        releaseCOM(&glyphVSBlob)
        releaseCOM(&shadowPSBlob)
        releaseCOM(&shadowVSBlob)
        releaseCOM(&imagePSBlob)
        releaseCOM(&imageVSBlob)
        releaseCOM(&quadPSBlob)
        releaseCOM(&quadVSBlob)
    }

    // MARK: - Device Creation

    /// Creates the device, trying each driver type in order. The windowed
    /// attach passes hardware only (unchanged behaviour); the offscreen
    /// attach chooses via `OffscreenDriver`.
    private func createDeviceIfNeeded(driverTypes: [D3D_DRIVER_TYPE] = [D3D_DRIVER_TYPE_HARDWARE]) throws {
        if device != nil && deviceContext != nil {
            return
        }

        let flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)
        // A driver that predates feature level 11_1 fails the whole call
        // with E_INVALIDARG instead of negotiating down, so that one
        // HRESULT — and only that one — earns a retry without 11_1.
        let featureLevelSets: [[D3D_FEATURE_LEVEL]] = [
            [D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0],
            [D3D_FEATURE_LEVEL_11_0],
        ]

        var lastHR: HRESULT = batchHresultInvalidArgument
        for driverType in driverTypes {
            for featureLevels in featureLevelSets {
                // Create into locals: a driver that fails part-way through
                // may still have written an out-param, and a retry writing
                // straight into the stored properties would leak it.
                var createdDevice: UnsafeMutablePointer<ID3D11Device>?
                var createdContext: UnsafeMutablePointer<ID3D11DeviceContext>?
                var featureLevel = D3D_FEATURE_LEVEL(0)
                let hr = featureLevels.withUnsafeBufferPointer { buffer in
                    D3D11CreateDevice(
                        nil,
                        driverType,
                        nil,
                        flags,
                        buffer.baseAddress,
                        UINT(buffer.count),
                        UINT(D3D11_SDK_VERSION),
                        &createdDevice,
                        &featureLevel,
                        &createdContext
                    )
                }

                if hr >= 0, createdDevice != nil, createdContext != nil {
                    releaseCOM(&device)
                    releaseCOM(&deviceContext)
                    device = createdDevice
                    deviceContext = createdContext
                    deviceGeneration = Self.nextDeviceGeneration
                    Self.nextDeviceGeneration &+= 1
                    return
                }

                releaseCOM(&createdContext)
                releaseCOM(&createdDevice)
                lastHR = hr < 0 ? hr : batchHresultHandle
                if hr != batchHresultInvalidArgument {
                    break
                }
            }
        }

        try throwIfFailed(lastHR, operation: "D3D11CreateDevice")
    }

    private func createFactoryIfNeeded() throws {
        if dxgiFactory != nil {
            return
        }

        let hr = makeCOM(into: &dxgiFactory) { factory in
            var rawFactory: UnsafeMutableRawPointer?
            var iid = IID_IDXGIFactory2
            let hr = CreateDXGIFactory1(&iid, &rawFactory)
            factory = rawFactory?.assumingMemoryBound(to: IDXGIFactory2.self)
            return hr
        }
        try throwIfFailed(hr, operation: "CreateDXGIFactory1")
    }

    private func createSwapChain(size: IntSize) throws {
        guard let hwnd, let dxgiFactory, let device else {
            return
        }

        if swapChain != nil {
            return
        }

        var descriptor = DXGI_SWAP_CHAIN_DESC1()
        descriptor.Width = UINT(max(size.width, 1))
        descriptor.Height = UINT(max(size.height, 1))
        descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        descriptor.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT
        descriptor.BufferCount = 2
        descriptor.Scaling = DXGI_SCALING_STRETCH
        descriptor.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD
        descriptor.AlphaMode = DXGI_ALPHA_MODE_IGNORE
        descriptor.Flags = 0

        let unknownDevice = UnsafeMutableRawPointer(device).assumingMemoryBound(to: IUnknown.self)
        let hr = makeCOM(into: &swapChain) { chain in
            dxgiFactory.pointee.lpVtbl.pointee.CreateSwapChainForHwnd(
                dxgiFactory,
                unknownDevice,
                hwnd,
                &descriptor,
                nil,
                nil,
                &chain
            )
        }
        try throwIfFailed(hr, operation: "IDXGIFactory2.CreateSwapChainForHwnd")
    }

    private func createRenderTargetView() throws {
        guard let swapChain, let device else {
            return
        }

        var backBufferRaw: UnsafeMutableRawPointer?
        var iid = IID_ID3D11Texture2D
        let bufferHR = swapChain.pointee.lpVtbl.pointee.GetBuffer(swapChain, 0, &iid, &backBufferRaw)
        try throwIfFailed(bufferHR, operation: "IDXGISwapChain1.GetBuffer")

        guard let texture = backBufferRaw?.assumingMemoryBound(to: ID3D11Texture2D.self) else {
            throw BatchRendererError(operation: "IDXGISwapChain1.GetBuffer", hresult: batchHresultHandle)
        }

        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        let viewHR = makeCOM(into: &renderTargetView) { view in
            device.pointee.lpVtbl.pointee.CreateRenderTargetView(device, resource, nil, &view)
        }
        var releasableTexture: UnsafeMutablePointer<ID3D11Texture2D>? = texture
        releaseCOM(&releasableTexture)
        try throwIfFailed(viewHR, operation: "ID3D11Device.CreateRenderTargetView")
    }

    // MARK: - Pipeline Creation

    private func createPipelineIfNeeded() throws {
        if quadVS != nil {
            return
        }

        guard let device else {
            throw BatchRendererError(operation: "Create batch pipeline", hresult: batchHresultHandle)
        }

        try createShaderPair(
            device: device,
            source: batchQuadShaderSource,
            vs: &quadVS,
            ps: &quadPS,
            label: "quad"
        )
        try createShaderPair(
            device: device,
            source: batchImageShaderSource,
            vs: &imageVS,
            ps: &imagePS,
            label: "image"
        )
        try createShaderPair(
            device: device,
            source: GlyphPipelineResources.vertexShaderSource,
            vs: &glyphVS,
            ps: &glyphPS,
            label: "glyph"
        )
        try createShaderPair(
            device: device,
            source: batchShadowShaderSource,
            vs: &shadowVS,
            ps: &shadowPS,
            label: "shadow"
        )

        var uniformDesc = D3D11_BUFFER_DESC()
        uniformDesc.ByteWidth = 16
        uniformDesc.Usage = D3D11_USAGE_DEFAULT
        uniformDesc.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)

        let uniformHR = makeCOM(into: &frameUniformBuffer) { buffer in
            device.pointee.lpVtbl.pointee.CreateBuffer(device, &uniformDesc, nil, &buffer)
        }
        try throwIfFailed(uniformHR, operation: "ID3D11Device.CreateBuffer(frameUniforms)")

        var blendDescriptor = D3D11_BLEND_DESC()
        blendDescriptor.AlphaToCoverageEnable = false
        blendDescriptor.IndependentBlendEnable = false
        blendDescriptor.RenderTarget.0.BlendEnable = true
        blendDescriptor.RenderTarget.0.SrcBlend = D3D11_BLEND_ONE
        blendDescriptor.RenderTarget.0.DestBlend = D3D11_BLEND_INV_SRC_ALPHA
        blendDescriptor.RenderTarget.0.BlendOp = D3D11_BLEND_OP_ADD
        blendDescriptor.RenderTarget.0.SrcBlendAlpha = D3D11_BLEND_ONE
        blendDescriptor.RenderTarget.0.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA
        blendDescriptor.RenderTarget.0.BlendOpAlpha = D3D11_BLEND_OP_ADD
        blendDescriptor.RenderTarget.0.RenderTargetWriteMask = UINT8(D3D11_COLOR_WRITE_ENABLE_ALL.rawValue)

        let blendHR = makeCOM(into: &blendState) { state in
            device.pointee.lpVtbl.pointee.CreateBlendState(device, &blendDescriptor, &state)
        }
        try throwIfFailed(blendHR, operation: "ID3D11Device.CreateBlendState")

        var rasterizerDescriptor = D3D11_RASTERIZER_DESC()
        rasterizerDescriptor.FillMode = D3D11_FILL_SOLID
        rasterizerDescriptor.CullMode = D3D11_CULL_NONE
        rasterizerDescriptor.ScissorEnable = false
        rasterizerDescriptor.DepthClipEnable = true

        let rasterizerHR = makeCOM(into: &rasterizerState) { state in
            device.pointee.lpVtbl.pointee.CreateRasterizerState(device, &rasterizerDescriptor, &state)
        }
        try throwIfFailed(rasterizerHR, operation: "ID3D11Device.CreateRasterizerState")

        var samplerDescriptor = D3D11_SAMPLER_DESC()
        samplerDescriptor.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR
        samplerDescriptor.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.MaxLOD = FLOAT(D3D11_FLOAT32_MAX)

        let samplerHR = makeCOM(into: &samplerState) { state in
            device.pointee.lpVtbl.pointee.CreateSamplerState(device, &samplerDescriptor, &state)
        }
        try throwIfFailed(samplerHR, operation: "ID3D11Device.CreateSamplerState")

        try createInstanceBuffer(
            device: device,
            capacity: quadInstanceCapacity,
            strideBytes: MemoryLayout<QuadPrimitive>.stride,
            buffer: &quadInstanceBuffer,
            srv: &quadInstanceSRV,
            label: "quad"
        )
        try createInstanceBuffer(
            device: device,
            capacity: imageInstanceCapacity,
            strideBytes: MemoryLayout<ImagePrimitive>.stride,
            buffer: &imageInstanceBuffer,
            srv: &imageInstanceSRV,
            label: "image"
        )
        try createInstanceBuffer(
            device: device,
            capacity: glyphInstanceCapacity,
            strideBytes: MemoryLayout<GlyphPrimitive>.stride,
            buffer: &glyphInstanceBuffer,
            srv: &glyphInstanceSRV,
            label: "glyph"
        )
        try createInstanceBuffer(
            device: device,
            capacity: shadowInstanceCapacity,
            strideBytes: MemoryLayout<ShadowPrimitive>.stride,
            buffer: &shadowInstanceBuffer,
            srv: &shadowInstanceSRV,
            label: "shadow"
        )
    }

    // MARK: - Shader Compilation

    private func createShaderPair(
        device: UnsafeMutablePointer<ID3D11Device>,
        source: String,
        vs: inout UnsafeMutablePointer<ID3D11VertexShader>?,
        ps: inout UnsafeMutablePointer<ID3D11PixelShader>?,
        label: String
    ) throws {
        var vsBlob: UnsafeMutablePointer<ID3DBlob>? = try Self.compileShaderSource(
            source: source, entryPoint: "vsMain", profile: "vs_5_0")
        defer { releaseCOM(&vsBlob) }

        var psBlob: UnsafeMutablePointer<ID3DBlob>? = try Self.compileShaderSource(
            source: source, entryPoint: "psMain", profile: "ps_5_0")
        defer { releaseCOM(&psBlob) }

        guard let vsBlob, let psBlob else {
            throw BatchRendererError(operation: "Compile \(label) shaders", hresult: batchHresultHandle)
        }

        let vsHR = makeCOM(into: &vs) { shader in
            device.pointee.lpVtbl.pointee.CreateVertexShader(
                device,
                vsBlob.pointee.lpVtbl.pointee.GetBufferPointer(vsBlob),
                SIZE_T(vsBlob.pointee.lpVtbl.pointee.GetBufferSize(vsBlob)),
                nil,
                &shader
            )
        }
        try throwIfFailed(vsHR, operation: "ID3D11Device.CreateVertexShader(\(label))")

        let psHR = makeCOM(into: &ps) { shader in
            device.pointee.lpVtbl.pointee.CreatePixelShader(
                device,
                psBlob.pointee.lpVtbl.pointee.GetBufferPointer(psBlob),
                SIZE_T(psBlob.pointee.lpVtbl.pointee.GetBufferSize(psBlob)),
                nil,
                &shader
            )
        }
        try throwIfFailed(psHR, operation: "ID3D11Device.CreatePixelShader(\(label))")
    }

    private static func compileShaderSource(
        source: String,
        entryPoint: String,
        profile: String
    ) throws -> UnsafeMutablePointer<ID3DBlob> {
        let sourceBytes = Array(source.utf8)
        var shaderBlob: UnsafeMutablePointer<ID3DBlob>?
        var errorBlob: UnsafeMutablePointer<ID3DBlob>?

        let hr = sourceBytes.withUnsafeBytes { source in
            entryPoint.withCString { entryPointCString in
                profile.withCString { profileCString in
                    D3DCompile(
                        source.baseAddress,
                        SIZE_T(sourceBytes.count),
                        nil,
                        nil,
                        nil,
                        entryPointCString,
                        profileCString,
                        0,
                        0,
                        &shaderBlob,
                        &errorBlob
                    )
                }
            }
        }

        if hr < 0 {
            let details = shaderCompilerDetails(from: errorBlob)
            releaseCOM(&errorBlob)
            throw BatchRendererError(operation: "D3DCompile(\(entryPoint))", hresult: hr, details: details)
        }

        releaseCOM(&errorBlob)

        guard let shaderBlob else {
            throw BatchRendererError(operation: "D3DCompile(\(entryPoint))", hresult: batchHresultHandle)
        }

        return shaderBlob
    }

    private static func shaderCompilerDetails(from errorBlob: UnsafeMutablePointer<ID3DBlob>?) -> String? {
        guard
            let errorBlob,
            let rawPointer = errorBlob.pointee.lpVtbl.pointee.GetBufferPointer(errorBlob)
        else {
            return nil
        }

        return String(cString: rawPointer.assumingMemoryBound(to: CChar.self))
    }

    // MARK: - Instance Buffer Management

    private func createInstanceBuffer(
        device: UnsafeMutablePointer<ID3D11Device>,
        capacity: Int,
        strideBytes: Int,
        buffer: inout UnsafeMutablePointer<ID3D11Buffer>?,
        srv: inout UnsafeMutablePointer<ID3D11ShaderResourceView>?,
        label: String
    ) throws {
        // The SRV views the buffer, so it goes first; the buffer itself is
        // replaced by `makeCOM`, which releases the old one only once the
        // new one exists.
        releaseCOM(&srv)

        var bufferDesc = D3D11_BUFFER_DESC()
        bufferDesc.ByteWidth = UINT(capacity * strideBytes)
        bufferDesc.Usage = D3D11_USAGE_DYNAMIC
        bufferDesc.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)
        bufferDesc.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_WRITE.rawValue)
        bufferDesc.MiscFlags = UINT(D3D11_RESOURCE_MISC_BUFFER_STRUCTURED.rawValue)
        bufferDesc.StructureByteStride = UINT(strideBytes)

        let bufHR = makeCOM(into: &buffer) { newBuffer in
            device.pointee.lpVtbl.pointee.CreateBuffer(device, &bufferDesc, nil, &newBuffer)
        }
        try throwIfFailed(bufHR, operation: "ID3D11Device.CreateBuffer(\(label) instances)")

        guard let buffer else {
            throw BatchRendererError(operation: "CreateBuffer(\(label))", hresult: batchHresultHandle)
        }

        var srvDesc = D3D11_SHADER_RESOURCE_VIEW_DESC()
        srvDesc.Format = DXGI_FORMAT_UNKNOWN
        srvDesc.ViewDimension = D3D11_SRV_DIMENSION_BUFFER
        withUnsafeMutablePointer(to: &srvDesc.Buffer) { bufferView in
            bufferView.pointee.FirstElement = 0
            bufferView.pointee.NumElements = UINT(capacity)
        }

        let resource = UnsafeMutableRawPointer(buffer).assumingMemoryBound(to: ID3D11Resource.self)
        let srvHR = makeCOM(into: &srv) { view in
            device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, &srvDesc, &view)
        }
        try throwIfFailed(srvHR, operation: "ID3D11Device.CreateShaderResourceView(\(label))")
    }

    private func ensureInstanceBufferCapacity(
        count: Int,
        capacity: inout Int,
        strideBytes: Int,
        buffer: inout UnsafeMutablePointer<ID3D11Buffer>?,
        srv: inout UnsafeMutablePointer<ID3D11ShaderResourceView>?,
        label: String
    ) throws {
        if count <= capacity {
            return
        }

        guard let device else {
            throw BatchRendererError(operation: "Grow \(label) buffer", hresult: batchHresultHandle)
        }

        while capacity < count {
            capacity *= 2
        }

        try createInstanceBuffer(
            device: device,
            capacity: capacity,
            strideBytes: strideBytes,
            buffer: &buffer,
            srv: &srv,
            label: label
        )
    }

    private func uploadInstances<T>(
        _ instances: [T],
        range: Range<Int>,
        buffer: UnsafeMutablePointer<ID3D11Buffer>,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>
    ) throws {
        let instanceCount = range.count
        guard instanceCount > 0 else {
            return
        }

        let resource = UnsafeMutableRawPointer(buffer).assumingMemoryBound(to: ID3D11Resource.self)
        var mapped = D3D11_MAPPED_SUBRESOURCE()
        let mapHR = deviceContext.pointee.lpVtbl.pointee.Map(
            deviceContext,
            resource,
            0,
            D3D11_MAP_WRITE_DISCARD,
            0,
            &mapped
        )
        try throwIfFailed(mapHR, operation: "ID3D11DeviceContext.Map")

        guard let pData = mapped.pData else {
            deviceContext.pointee.lpVtbl.pointee.Unmap(deviceContext, resource, 0)
            throw BatchRendererError(operation: "Map returned nil", hresult: batchHresultHandle)
        }

        instances.withUnsafeBytes { source in
            guard let baseAddress = source.baseAddress else {
                return
            }

            let byteOffset = range.lowerBound * MemoryLayout<T>.stride
            let byteCount = instanceCount * MemoryLayout<T>.stride
            memcpy(pData, baseAddress.advanced(by: byteOffset), byteCount)
        }

        deviceContext.pointee.lpVtbl.pointee.Unmap(deviceContext, resource, 0)
    }

    // MARK: - Frame Uniforms

    private struct FrameUniforms {
        var surfaceWidth: Float
        var surfaceHeight: Float
        var pad0: Float
        var pad1: Float
    }

    private func updateFrameUniforms(surfaceSize: IntSize) throws {
        guard let deviceContext, let frameUniformBuffer else {
            return
        }

        var uniforms = FrameUniforms(
            surfaceWidth: Float(surfaceSize.width),
            surfaceHeight: Float(surfaceSize.height),
            pad0: 0,
            pad1: 0
        )

        let resource = UnsafeMutableRawPointer(frameUniformBuffer).assumingMemoryBound(to: ID3D11Resource.self)
        withUnsafePointer(to: &uniforms) { ptr in
            deviceContext.pointee.lpVtbl.pointee.UpdateSubresource(
                deviceContext,
                resource,
                0,
                nil,
                UnsafeRawPointer(ptr),
                0,
                0
            )
        }
    }

    private func updateGlyphAtlasTexture(
        _ snapshot: GlyphAtlasSnapshot,
        texture: inout UnsafeMutablePointer<ID3D11Texture2D>?,
        srv: inout UnsafeMutablePointer<ID3D11ShaderResourceView>?,
        size: inout IntSize
    ) throws {
        guard let device, let deviceContext else {
            return
        }

        // `UpdateSubresource` below reads `width * height * 4` bytes out of
        // the snapshot; a short buffer is a heap over-read, so a malformed
        // atlas is rejected rather than uploaded.
        let requiredBytes = Int(snapshot.width) * Int(snapshot.height) * 4
        guard snapshot.width > 0, snapshot.height > 0, snapshot.pixels.count >= requiredBytes else {
            throw BatchRendererError(
                operation: "Upload glyph atlas",
                hresult: batchHresultInvalidArgument,
                details:
                    "Glyph atlas is \(snapshot.width)×\(snapshot.height) but holds \(snapshot.pixels.count) bytes "
                    + "(needs \(requiredBytes)).",
                failureKind: .sceneContent
            )
        }

        if texture == nil || size.width != snapshot.width || size.height != snapshot.height {
            releaseCOM(&srv)
            releaseCOM(&texture)

            var textureDesc = D3D11_TEXTURE2D_DESC()
            textureDesc.Width = UINT(snapshot.width)
            textureDesc.Height = UINT(snapshot.height)
            textureDesc.MipLevels = 1
            textureDesc.ArraySize = 1
            // The atlas bytes are BGRA like every other surface here, but
            // the glyph shader reads only `.a` — which sits at byte 3 in
            // either order — so the declared channel order is immaterial.
            // Kept as RGBA to avoid re-specifying a format nothing reads.
            textureDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM
            textureDesc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
            textureDesc.Usage = D3D11_USAGE_DEFAULT
            textureDesc.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)

            let textureHR = makeCOM(into: &texture) { newTexture in
                device.pointee.lpVtbl.pointee.CreateTexture2D(device, &textureDesc, nil, &newTexture)
            }
            try throwIfFailed(
                textureHR, operation: "ID3D11Device.CreateTexture2D(glyph atlas)", failureKind: .sceneContent)

            guard let texture else {
                throw BatchRendererError(
                    operation: "CreateTexture2D(glyph atlas)", hresult: batchHresultHandle, failureKind: .sceneContent)
            }

            var srvDesc = D3D11_SHADER_RESOURCE_VIEW_DESC()
            srvDesc.Format = textureDesc.Format
            srvDesc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D
            withUnsafeMutablePointer(to: &srvDesc.Texture2D) { textureView in
                textureView.pointee.MostDetailedMip = 0
                textureView.pointee.MipLevels = 1
            }

            let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
            let srvHR = makeCOM(into: &srv) { view in
                device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, &srvDesc, &view)
            }
            try throwIfFailed(srvHR, operation: "ID3D11Device.CreateShaderResourceView(glyph atlas)")
            size = IntSize(width: snapshot.width, height: snapshot.height)
        }

        guard let texture else {
            return
        }

        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        let rowPitch = UINT(snapshot.width * 4)
        snapshot.pixels.withUnsafeBytes { pixels in
            guard let baseAddress = pixels.baseAddress else {
                return
            }

            if let dirtyRegion = snapshot.dirtyRegion,
                dirtyRegion.width > 0,
                dirtyRegion.height > 0,
                size.width == snapshot.width,
                size.height == snapshot.height
            {
                let bytesOffset = Int((dirtyRegion.y * snapshot.width + dirtyRegion.x) * 4)
                var updateBox = D3D11_BOX(
                    left: UINT(dirtyRegion.x),
                    top: UINT(dirtyRegion.y),
                    front: 0,
                    right: UINT(dirtyRegion.x + dirtyRegion.width),
                    bottom: UINT(dirtyRegion.y + dirtyRegion.height),
                    back: 1
                )
                let regionPointer = UnsafeRawPointer(baseAddress.advanced(by: bytesOffset))
                deviceContext.pointee.lpVtbl.pointee.UpdateSubresource(
                    deviceContext,
                    resource,
                    0,
                    &updateBox,
                    regionPointer,
                    rowPitch,
                    0
                )
            } else {
                deviceContext.pointee.lpVtbl.pointee.UpdateSubresource(
                    deviceContext,
                    resource,
                    0,
                    nil,
                    baseAddress,
                    rowPitch,
                    0
                )
            }
        }
    }

    private func ensureImageResourceSRV(for textureID: Int32) throws -> UnsafeMutablePointer<ID3D11ShaderResourceView> {
        guard var entry = imageResources[textureID] else {
            throw BatchRendererError(
                operation: "Resolve image resource",
                hresult: batchHresultInvalidArgument,
                details: "No bound bitmap exists for texture ID \(textureID).",
                failureKind: .sceneContent
            )
        }

        if entry.srv == nil || entry.texture == nil {
            let (texture, srv) = try createImageTextureResource(for: entry.bitmap)
            entry.texture = texture
            entry.srv = srv
            imageResources[textureID] = entry
        }

        guard let srv = entry.srv else {
            throw BatchRendererError(
                operation: "Create image resource view",
                hresult: batchHresultHandle,
                details: "Image texture ID \(textureID) did not produce a shader resource view."
            )
        }
        return srv
    }

    private func createImageTextureResource(
        for bitmap: BitmapSurface
    ) throws -> (
        texture: UnsafeMutablePointer<ID3D11Texture2D>,
        srv: UnsafeMutablePointer<ID3D11ShaderResourceView>
    ) {
        guard let device else {
            throw BatchRendererError(
                operation: "Create image texture",
                hresult: batchHresultHandle,
                details: "D3D11 device is not available."
            )
        }

        // A surface whose buffer is shorter than `bytesPerRow * height`
        // would make `CreateTexture2D` read off the end of the heap, so the
        // geometry is checked before the pointer is handed to D3D.
        do {
            try bitmap.validate()
        } catch {
            throw BatchRendererError(
                operation: "Create image texture",
                hresult: batchHresultInvalidArgument,
                details: String(describing: error),
                failureKind: .sceneContent
            )
        }

        // `BitmapSurface` is BGRA — matching `B8G8R8A8_UNORM`, the swap
        // chain format and the legacy renderer — and every GPU upload is
        // normalized to premultiplied alpha, which is what the
        // ONE/INV_SRC_ALPHA blend state and the bilinear sampler both need.
        let upload = bitmap.premultipliedAlpha()

        var textureDescriptor = D3D11_TEXTURE2D_DESC()
        textureDescriptor.Width = UINT(upload.width)
        textureDescriptor.Height = UINT(upload.height)
        textureDescriptor.MipLevels = 1
        textureDescriptor.ArraySize = 1
        textureDescriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        textureDescriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        textureDescriptor.Usage = D3D11_USAGE_DEFAULT
        textureDescriptor.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)

        var texture: UnsafeMutablePointer<ID3D11Texture2D>?
        let textureHR = upload.pixels.withUnsafeBytes { pixels in
            guard let baseAddress = pixels.baseAddress else {
                return HRESULT(bitPattern: 0x8000_4005)
            }

            var subresource = D3D11_SUBRESOURCE_DATA()
            subresource.pSysMem = baseAddress
            subresource.SysMemPitch = UINT(upload.bytesPerRow)
            subresource.SysMemSlicePitch = UINT(upload.describedByteCount)
            return device.pointee.lpVtbl.pointee.CreateTexture2D(device, &textureDescriptor, &subresource, &texture)
        }
        try throwIfFailed(textureHR, operation: "ID3D11Device.CreateTexture2D(image)", failureKind: .sceneContent)

        guard let texture else {
            throw BatchRendererError(
                operation: "CreateTexture2D(image)", hresult: batchHresultHandle, failureKind: .sceneContent)
        }

        var srvDesc = D3D11_SHADER_RESOURCE_VIEW_DESC()
        srvDesc.Format = textureDescriptor.Format
        srvDesc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D
        withUnsafeMutablePointer(to: &srvDesc.Texture2D) { textureView in
            textureView.pointee.MostDetailedMip = 0
            textureView.pointee.MipLevels = 1
        }

        var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        let srvHR = device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, &srvDesc, &srv)
        do {
            try throwIfFailed(
                srvHR, operation: "ID3D11Device.CreateShaderResourceView(image)", failureKind: .sceneContent)
        } catch {
            var releasableTexture: UnsafeMutablePointer<ID3D11Texture2D>? = texture
            releaseCOM(&releasableTexture)
            throw error
        }

        guard let srv else {
            var releasableTexture: UnsafeMutablePointer<ID3D11Texture2D>? = texture
            releaseCOM(&releasableTexture)
            throw BatchRendererError(
                operation: "CreateShaderResourceView(image)", hresult: batchHresultHandle,
                failureKind: .sceneContent)
        }

        return (texture, srv)
    }

    // MARK: - Render Batches

    /// Unified batch draw: uploads instances to a structured buffer, binds
    /// shaders and SRV, issues a single DrawInstanced call, then unbinds.
    private func renderBatch<T>(
        _ instances: [T],
        range: Range<Int>,
        capacity: inout Int,
        buffer: inout UnsafeMutablePointer<ID3D11Buffer>?,
        srv: inout UnsafeMutablePointer<ID3D11ShaderResourceView>?,
        vs: UnsafeMutablePointer<ID3D11VertexShader>?,
        ps: UnsafeMutablePointer<ID3D11PixelShader>?,
        label: String,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        bindSampler: Bool = false
    ) throws {
        let instanceCount = range.count
        guard instanceCount > 0 else {
            return
        }

        try ensureInstanceBufferCapacity(
            count: instanceCount,
            capacity: &capacity,
            strideBytes: MemoryLayout<T>.stride,
            buffer: &buffer,
            srv: &srv,
            label: label
        )

        guard let buffer, let srv else { return }

        try uploadInstances(instances, range: range, buffer: buffer, deviceContext: deviceContext)

        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, vs, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, ps, nil, 0)

        var srvPtr: UnsafeMutablePointer<ID3D11ShaderResourceView>? = srv
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &srvPtr)

        if bindSampler {
            var samplerPtr: UnsafeMutablePointer<ID3D11SamplerState>? = samplerState
            deviceContext.pointee.lpVtbl.pointee.PSSetSamplers(deviceContext, 0, 1, &samplerPtr)
        }

        deviceContext.pointee.lpVtbl.pointee.DrawInstanced(deviceContext, 6, UINT(instanceCount), 0, 0)

        var nullSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = nil
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &nullSRV)
    }

    private func renderGlyphBatch(
        _ instances: [GlyphPrimitive],
        range: Range<Int>,
        atlasSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>
    ) throws {
        let instanceCount = range.count
        guard instanceCount > 0 else {
            return
        }

        try ensureInstanceBufferCapacity(
            count: instanceCount,
            capacity: &glyphInstanceCapacity,
            strideBytes: MemoryLayout<GlyphPrimitive>.stride,
            buffer: &glyphInstanceBuffer,
            srv: &glyphInstanceSRV,
            label: "glyph"
        )

        guard
            let glyphInstanceBuffer,
            let glyphInstanceSRV,
            let atlasSRV,
            let glyphVS,
            let glyphPS
        else {
            return
        }

        try uploadInstances(instances, range: range, buffer: glyphInstanceBuffer, deviceContext: deviceContext)

        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, glyphVS, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, glyphPS, nil, 0)

        var instanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = glyphInstanceSRV
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &instanceSRV)

        var glyphAtlasSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = atlasSRV
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &glyphAtlasSRV)

        var samplerPtr: UnsafeMutablePointer<ID3D11SamplerState>? = samplerState
        deviceContext.pointee.lpVtbl.pointee.PSSetSamplers(deviceContext, 0, 1, &samplerPtr)
        deviceContext.pointee.lpVtbl.pointee.DrawInstanced(deviceContext, 6, UINT(instanceCount), 0, 0)

        var nullSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = nil
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &nullSRV)
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &nullSRV)
    }

    private func renderImageBatch(
        _ instances: [ImagePrimitive],
        range: Range<Int>,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        textureSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>
    ) throws {
        let instanceCount = range.count
        guard instanceCount > 0 else {
            return
        }

        try ensureInstanceBufferCapacity(
            count: instanceCount,
            capacity: &imageInstanceCapacity,
            strideBytes: MemoryLayout<ImagePrimitive>.stride,
            buffer: &imageInstanceBuffer,
            srv: &imageInstanceSRV,
            label: "image"
        )

        guard
            let imageInstanceBuffer,
            let imageInstanceSRV,
            let imageVS,
            let imagePS
        else {
            return
        }

        try uploadInstances(instances, range: range, buffer: imageInstanceBuffer, deviceContext: deviceContext)

        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, imageVS, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, imagePS, nil, 0)

        var instanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = imageInstanceSRV
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &instanceSRV)

        var textureSRVPointer: UnsafeMutablePointer<ID3D11ShaderResourceView>? = textureSRV
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &textureSRVPointer)

        var samplerPtr: UnsafeMutablePointer<ID3D11SamplerState>? = samplerState
        deviceContext.pointee.lpVtbl.pointee.PSSetSamplers(deviceContext, 0, 1, &samplerPtr)
        deviceContext.pointee.lpVtbl.pointee.DrawInstanced(deviceContext, 6, UINT(instanceCount), 0, 0)

        var nullSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = nil
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &nullSRV)
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &nullSRV)
    }

    private func renderPathBatch(
        _ instances: [PathPrimitive],
        range: Range<Int>,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>
    ) throws {
        guard !range.isEmpty else { return }

        for index in range {
            let path = instances[index]
            let bounds = path.contentMaskedBounds ?? path.bounds
            // Normalize the path to its own origin so the cache key is
            // translation-invariant. A static path that simply moves with
            // its parent view stays a cache hit.
            let translation = Point(x: -path.bounds.origin.x, y: -path.bounds.origin.y)
            let normalizedPath = path.translated(by: translation)

            let (srv, bitmapSize) = try ensureCachedPathTexture(for: normalizedPath, fallbackBounds: bounds)
            guard let srv else { continue }

            let drawWidth = max(Float(bounds.size.width), Float(bitmapSize.width))
            let drawHeight = max(Float(bounds.size.height), Float(bitmapSize.height))
            let syntheticImage = ImagePrimitive(
                screenX: Float(bounds.origin.x),
                screenY: Float(bounds.origin.y),
                screenW: drawWidth,
                screenH: drawHeight,
                uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                opacity: 1,
                clipX: 0, clipY: 0, clipWidth: 0, clipHeight: 0,
                textureID: -1
            )

            try renderImageBatch(
                [syntheticImage],
                range: 0..<1,
                deviceContext: deviceContext,
                textureSRV: srv
            )
        }
    }

    /// Returns a GPU texture for `normalizedPath`. The path is normalized to
    /// origin (0, 0); the caller is responsible for placing the resulting
    /// quad at the original screen coordinates. Reuses cached textures when
    /// the path shape/colors/stroke match an entry from a recent frame.
    private func ensureCachedPathTexture(
        for normalizedPath: PathPrimitive,
        fallbackBounds: Rect
    ) throws -> (srv: UnsafeMutablePointer<ID3D11ShaderResourceView>?, bitmapSize: IntSize) {
        if let hitIndex = pathRenderCache.firstIndex(where: { $0.key == normalizedPath }) {
            pathRenderCache[hitIndex].lastUsedFrame = frameCounter
            pathCacheHits &+= 1
            return (pathRenderCache[hitIndex].srv, pathRenderCache[hitIndex].bitmapSize)
        }

        pathCacheMisses &+= 1
        guard let bitmap = GPUIRawSceneRasterizer.rasterizePath(normalizedPath) else {
            return (nil, IntSize.zero)
        }
        let (texture, srv) = try createImageTextureResource(for: bitmap)
        // Bound the cache so unbounded canvas content doesn't accumulate
        // textures forever. Evict the oldest entry when full.
        if pathRenderCache.count >= Self.pathCacheMaxEntries {
            evictOldestCachedPathEntry()
        }
        let entry = CachedPathRender(
            key: normalizedPath,
            texture: texture,
            srv: srv,
            bitmapSize: IntSize(width: Int32(bitmap.width), height: Int32(bitmap.height)),
            lastUsedFrame: frameCounter
        )
        pathRenderCache.append(entry)
        _ = fallbackBounds  // currently unused; kept for future debug instrumentation
        return (srv, entry.bitmapSize)
    }

    private func evictStaleCachedPaths() {
        guard frameCounter > Self.pathCacheStaleFrames else { return }
        let staleThreshold = frameCounter - Self.pathCacheStaleFrames
        var index = 0
        while index < pathRenderCache.count {
            if pathRenderCache[index].lastUsedFrame < staleThreshold {
                releaseCachedPathEntry(at: index)
            } else {
                index += 1
            }
        }
    }

    private func evictOldestCachedPathEntry() {
        guard
            let oldestIndex = pathRenderCache.indices.min(by: {
                pathRenderCache[$0].lastUsedFrame < pathRenderCache[$1].lastUsedFrame
            })
        else { return }
        releaseCachedPathEntry(at: oldestIndex)
    }

    private func releaseCachedPathEntry(at index: Int) {
        let entry = pathRenderCache.remove(at: index)
        var srvOpt: UnsafeMutablePointer<ID3D11ShaderResourceView>? = entry.srv
        releaseCOM(&srvOpt)
        var textureOpt: UnsafeMutablePointer<ID3D11Texture2D>? = entry.texture
        releaseCOM(&textureOpt)
    }

    private func releaseAllCachedPaths() {
        while !pathRenderCache.isEmpty {
            releaseCachedPathEntry(at: pathRenderCache.count - 1)
        }
    }

    // MARK: - Backdrop Blur (Material quads)

    private func ensureBlurEngine(
        device: UnsafeMutablePointer<ID3D11Device>
    ) throws -> D3D11BackdropBlurEngine {
        if let blurEngine, blurEngine.matches(deviceGeneration: deviceGeneration) {
            return blurEngine
        }
        blurEngine?.detach()
        let engine = D3D11BackdropBlurEngine()
        try engine.attach(device: device, generation: deviceGeneration)
        blurEngine = engine
        return engine
    }

    /// Draws one Material quad with a true backdrop blur: snapshot the
    /// backbuffer region under the quad, separable-Gaussian blur it, then
    /// composite the quad's tint over the blurred result.
    private func renderBlurredMaterialQuad(
        _ quad: QuadPrimitive,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        surfaceSize: IntSize
    ) throws {
        guard let device, let renderTargetView, hasRenderTarget else {
            return
        }

        if failBlurredQuadsForTesting {
            throw BatchRendererError(
                operation: "Draw blurred material quad",
                hresult: batchHresultOutOfMemory,
                details: "Injected blur failure (test seam).")
        }

        // Whatever happens below — success, a mid-pass throw, an early
        // return — the engine leaves its own targets, viewport, blend and
        // constant buffers bound. Put the frame's state back before the
        // batch loop draws anything else, including the fallback quad the
        // caller falls through to on failure.
        defer { bindFramePipelineState(deviceContext: deviceContext, surfaceSize: surfaceSize) }

        let engine = try ensureBlurEngine(device: device)

        var backBuffer: UnsafeMutablePointer<ID3D11Texture2D>? = try acquireBackBuffer()
        defer { releaseCOM(&backBuffer) }
        guard let backBuffer else {
            throw BatchRendererError(operation: "Resolve back buffer", hresult: batchHresultHandle)
        }

        try engine.drawBlurredQuad(
            deviceContext: deviceContext,
            backBuffer: backBuffer,
            backBufferRTV: renderTargetView,
            surfaceWidth: Int(surfaceSize.width),
            surfaceHeight: Int(surfaceSize.height),
            quad: quad
        )
    }

    /// Draws one Material quad, preferring the real backdrop blur and
    /// degrading to the plain quad path when the blur cannot run.
    ///
    /// The blur's ping-pong pair is the largest allocation the renderer
    /// makes — up to two full-surface textures, created lazily mid-frame —
    /// so it is the one most likely to fail under memory pressure. Letting
    /// that failure escape would abort the frame *before* `Present`, and
    /// the next frame would retry the identical allocation: a permanent
    /// visual wedge in exchange for an effect the plain shader can
    /// approximate with edge softening. So the failure is contained here,
    /// logged once, and remembered until the surface size changes (which is
    /// what changes the allocation).
    ///
    /// Device loss is deliberately not contained: it is not a blur problem,
    /// and `render` has a real recovery path for it.
    private func renderMaterialQuad(
        _ quads: [QuadPrimitive],
        index: Int,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        surfaceSize: IntSize
    ) throws {
        if !blurDegraded {
            do {
                try renderBlurredMaterialQuad(
                    quads[index], deviceContext: deviceContext, surfaceSize: surfaceSize)
                return
            } catch {
                if PresentationFailureKind.classifying(error) == .deviceLost {
                    throw error
                }
                blurDegraded = true
                FileHandle.standardError.write(
                    Data(
                        ("[SwiftWindowsUI] Backdrop blur failed; material quads fall back to the plain "
                            + "edge-softening path until the surface is resized: \(error)\n").utf8))
            }
        }

        try renderBatch(
            quads,
            range: index..<(index + 1),
            capacity: &quadInstanceCapacity,
            buffer: &quadInstanceBuffer,
            srv: &quadInstanceSRV,
            vs: quadVS, ps: quadPS,
            label: "quad",
            deviceContext: deviceContext
        )
    }

    // MARK: - Helpers

    private func throwIfFailed(
        _ hr: HRESULT,
        operation: String,
        failureKind: PresentationFailureKind? = nil
    ) throws {
        if hr < 0 {
            throw BatchRendererError(operation: operation, hresult: hr, failureKind: failureKind)
        }
    }

}
public struct BatchRendererError: Error, ClassifiedPresentationFailure, CustomStringConvertible, Sendable {
    public let operation: String
    public let hresult: HRESULT
    public let details: String?
    /// How the host's recovery policy should read this failure. Defaults to
    /// the HRESULT's classification; sites whose failure depends on *what*
    /// is being drawn rather than on the HRESULT pass `.sceneContent`.
    public let presentationFailureKind: PresentationFailureKind

    public init(
        operation: String,
        hresult: HRESULT,
        details: String? = nil,
        failureKind: PresentationFailureKind? = nil
    ) {
        self.operation = operation
        self.hresult = hresult
        self.details = details
        // A lost device outranks whatever the call site believed it was
        // doing: an atlas upload that fails with DEVICE_REMOVED is device
        // loss, not bad scene content.
        self.presentationFailureKind =
            DeviceLostPolicy.isDeviceLost(hresult)
            ? .deviceLost
            : (failureKind ?? DeviceLostPolicy.failureKind(for: hresult))
    }

    public var description: String {
        let prefix =
            "\(operation) failed with HRESULT 0x\(String(UInt32(bitPattern: hresult), radix: 16, uppercase: true))."
        guard let details, !details.isEmpty else {
            return prefix
        }

        return "\(prefix) \(details)"
    }
}
private let batchHresultHandle: HRESULT = HRESULT(bitPattern: 0x8007_0006)
private let batchHresultInvalidArgument: HRESULT = HRESULT(bitPattern: 0x8007_0057)
private let batchHresultOutOfMemory: HRESULT = HRESULT(bitPattern: 0x8007_000E)
