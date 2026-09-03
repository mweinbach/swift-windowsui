import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
/// Instanced batch renderer using StructuredBuffer-based instanced draw calls.
/// Instead of one draw call per rectangle, all primitives of the same type are
/// uploaded to a single GPU buffer and drawn in one DrawInstanced call.
import WinSDK.DirectX

/// Native batch implementation, confined to one execution owner.
/// The actor facade and the native presenter each create their own kernel;
/// no kernel or borrowed COM pointer is transferred between those owners.
final class D3D11BatchKernel {
    public typealias OffscreenDriver = D3D11BatchOffscreenDriver
    public typealias AtlasSource = D3D11BatchAtlasSource
    public typealias CachedResources = D3D11BatchCachedResources
    public typealias RenderStep = D3D11BatchRenderStep
    public typealias RenderPlan = D3D11BatchRenderPlan

    public private(set) var isAttached = false

    public var backendDisplayName: String { "D3D11 BATCH" }

    public private(set) var lastFrameSubmission: BackendFrameSubmission?
    private var gpuFrameTimingCollector: D3D11GPUFrameTimingCollector?

    public var gpuFrameTimingDiagnostics: GPUFrameTimingDiagnostics? {
        gpuFrameTimingCollector?.diagnostics
            ?? GPUFrameTimingDiagnostics(isEnabled: false, isSupported: false)
    }

    @discardableResult
    public func setGPUFrameTimingEnabled(_ enabled: Bool) -> Bool {
        if enabled, gpuFrameTimingCollector == nil {
            gpuFrameTimingCollector = D3D11GPUFrameTimingCollector()
            attachGPUFrameTimingCollectorIfNeeded()
        }
        return gpuFrameTimingCollector?.setEnabled(enabled) ?? true
    }

    public func takeCompletedGPUFrameTimings() -> [GPUFrameTimingResult] {
        gpuFrameTimingCollector?.takeCompletedResults() ?? []
    }

    private func attachGPUFrameTimingCollectorIfNeeded() {
        guard let gpuFrameTimingCollector, let device, let deviceContext else { return }
        gpuFrameTimingCollector.attach(
            transport: D3D11TimestampQueryTransport(device: device, context: deviceContext),
            deviceGeneration: deviceGeneration)
    }

    /// Selects only metadata already resolved for the issuing device. This
    /// pure check cannot issue a COM query or reuse a replaced device's flag.
    static func cachedAdapterIsSoftware(
        forDeviceGeneration generation: UInt64,
        cachedGeneration: UInt64?,
        cachedIsSoftware: Bool?
    ) -> Bool? {
        guard generation != 0, generation == cachedGeneration else { return nil }
        return cachedIsSoftware
    }

    /// What this backend is actually running on, plus its cumulative atlas
    /// upload cost. The adapter half is resolved once per device and cached
    /// against `deviceGeneration`, so a caller may read this every frame.
    public var backendDiagnostics: BatchBackendDiagnostics? {
        let adapter = resolvedAdapterDiagnostics()
        return BatchBackendDiagnostics(
            adapterDescription: adapter?.description,
            adapterIsSoftware: adapter?.isSoftware,
            adapterDedicatedVideoMemoryBytes: adapter?.dedicatedVRAM,
            featureLevel: createdFeatureLevel.map(Self.featureLevelDisplayName(_:)),
            atlasFullUploadCount: atlasFullUploadsForTesting,
            atlasRegionUploadCount: atlasRegionUploadsForTesting,
            atlasSkippedUploadCount: atlasSkippedUploadsForTesting,
            atlasUploadedByteCount: atlasUploadedByteCount,
            lastSubmitSeconds: lastSubmitSeconds,
            lastPresentSeconds: lastPresentSeconds,
            lastDrawCallCount: lastDrawCallCount,
            lastDrawnInstanceCount: lastDrawnInstanceCount
        )
    }

    @discardableResult
    public func setPresentsWithVSync(_ enabled: Bool) -> Bool {
        presentPacingPolicy.setUnsynchronizedByRequest(!enabled)
        return true
    }

    @discardableResult
    public func setCapturesPresentedFrames(_ enabled: Bool) -> Bool {
        capturesPresentedFrames = enabled
        if !enabled {
            capturedPresentedFrame = nil
        }
        return true
    }

    public func takeCapturedPresentedFrame() -> BitmapSurface? {
        defer { capturedPresentedFrame = nil }
        return capturedPresentedFrame
    }

    public var presentPacing: PresentPacingStatus {
        presentPacingPolicy.status
    }

    public func setDisplayFrameInterval(_ seconds: Double) {
        presentPacingPolicy.setDisplayFrameInterval(seconds)
    }

    public func adoptRememberedSelfPacing() {
        presentPacingPolicy.adoptRememberedSelfPacing()
    }

    /// QPC seconds. Only called around the two phases of `render(scene:)`, so
    /// the cost is two counter reads per frame.
    private static func nowSeconds() -> Double {
        var counter = LARGE_INTEGER()
        var frequency = LARGE_INTEGER()
        QueryPerformanceCounter(&counter)
        QueryPerformanceFrequency(&frequency)
        guard frequency.QuadPart != 0 else {
            return 0
        }
        return Double(counter.QuadPart) / Double(frequency.QuadPart)
    }

    private static func featureLevelDisplayName(_ level: D3D_FEATURE_LEVEL) -> String {
        switch level {
        case D3D_FEATURE_LEVEL_12_1: return "12_1"
        case D3D_FEATURE_LEVEL_12_0: return "12_0"
        case D3D_FEATURE_LEVEL_11_1: return "11_1"
        case D3D_FEATURE_LEVEL_11_0: return "11_0"
        case D3D_FEATURE_LEVEL_10_1: return "10_1"
        case D3D_FEATURE_LEVEL_10_0: return "10_0"
        default: return "0x\(String(UInt32(level.rawValue), radix: 16))"
        }
    }

    /// Walks device → `IDXGIDevice` → adapter → `GetDesc1`.
    ///
    /// Deliberately not `IDXGIFactory.EnumAdapters(0)`: on a hybrid laptop
    /// adapter 0 is routinely the integrated part while the device was created
    /// on the discrete one, and reporting the wrong adapter is worse than
    /// reporting none. Asking the device which adapter it is on cannot be
    /// wrong.
    private func resolvedAdapterDiagnostics() -> (description: String, isSoftware: Bool, dedicatedVRAM: UInt64)? {
        if let cachedAdapterDiagnostics, cachedAdapterDiagnosticsGeneration == deviceGeneration {
            return cachedAdapterDiagnostics
        }

        guard let device, deviceGeneration != 0 else {
            return nil
        }

        var dxgiDeviceRaw: UnsafeMutableRawPointer?
        var dxgiDeviceIID = dxgiDeviceInterfaceID
        let unknownDevice = UnsafeMutableRawPointer(device).assumingMemoryBound(to: IUnknown.self)
        let queryHR = unknownDevice.pointee.lpVtbl.pointee.QueryInterface(
            unknownDevice, &dxgiDeviceIID, &dxgiDeviceRaw)
        guard queryHR >= 0, let dxgiDevice = dxgiDeviceRaw?.assumingMemoryBound(to: IDXGIDevice.self) else {
            return nil
        }
        defer {
            var releasable: UnsafeMutablePointer<IDXGIDevice>? = dxgiDevice
            releaseCOM(&releasable)
        }

        var adapterPointer: UnsafeMutablePointer<IDXGIAdapter>?
        let adapterHR = dxgiDevice.pointee.lpVtbl.pointee.GetAdapter(dxgiDevice, &adapterPointer)
        guard adapterHR >= 0, let adapter = adapterPointer else {
            return nil
        }
        defer {
            var releasable: UnsafeMutablePointer<IDXGIAdapter>? = adapter
            releaseCOM(&releasable)
        }

        // `IDXGIAdapter1.GetDesc1` carries the software flag; `IDXGIAdapter`
        // alone does not, and that flag is the whole point of this query.
        var adapter1Raw: UnsafeMutableRawPointer?
        var adapter1IID = dxgiAdapter1InterfaceID
        let unknownAdapter = UnsafeMutableRawPointer(adapter).assumingMemoryBound(to: IUnknown.self)
        let adapter1HR = unknownAdapter.pointee.lpVtbl.pointee.QueryInterface(
            unknownAdapter, &adapter1IID, &adapter1Raw)
        guard adapter1HR >= 0, let adapter1 = adapter1Raw?.assumingMemoryBound(to: IDXGIAdapter1.self) else {
            return nil
        }
        defer {
            var releasable: UnsafeMutablePointer<IDXGIAdapter1>? = adapter1
            releaseCOM(&releasable)
        }

        var descriptor = DXGI_ADAPTER_DESC1()
        let descHR = adapter1.pointee.lpVtbl.pointee.GetDesc1(adapter1, &descriptor)
        guard descHR >= 0 else {
            return nil
        }

        let description = withUnsafeBytes(of: descriptor.Description) { raw -> String in
            let units = raw.bindMemory(to: UInt16.self)
            var scalars = String.UnicodeScalarView()
            for unit in units {
                guard unit != 0 else { break }
                guard let scalar = Unicode.Scalar(UInt32(unit)) else { continue }
                scalars.append(scalar)
            }
            return String(String.UnicodeScalarView(scalars))
        }

        let isSoftware = (descriptor.Flags & UINT(DXGI_ADAPTER_FLAG_SOFTWARE.rawValue)) != 0
        let resolved = (
            description: description,
            isSoftware: isSoftware,
            dedicatedVRAM: UInt64(descriptor.DedicatedVideoMemory)
        )
        cachedAdapterDiagnostics = resolved
        cachedAdapterDiagnosticsGeneration = deviceGeneration
        return resolved
    }

    // MARK: - D3D11 Core State

    private var device: UnsafeMutablePointer<ID3D11Device>?
    private var deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>?
    private var dxgiFactory: UnsafeMutablePointer<IDXGIFactory2>?
    private var swapChain: UnsafeMutablePointer<IDXGISwapChain1>?
    private var displayAcquisition: NativeDisplayAcquisition.Context?
    private var displayAcquisitionEpoch: NativeDisplayAcquisition.EpochToken?
    private var displayAcquisitionRendered = false
    private var renderTargetView: UnsafeMutablePointer<ID3D11RenderTargetView>?

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

    /// Whether every frame is copied back to the CPU on its way to the
    /// screen, and the copy the last frame left. See
    /// `setCapturesPresentedFrames(_:)` — off in every shipping run.
    private var capturesPresentedFrames = false
    private var capturedPresentedFrame: BitmapSurface?

    private var offscreenTexture: UnsafeMutablePointer<ID3D11Texture2D>?
    /// Driver preference the current offscreen attach was made with, so a
    /// device-loss rebuild recreates the same kind of device.
    private var offscreenDriver: OffscreenDriver = .hardwareFirst
    /// Only the exact WARP test attachment refuses automatic driver recovery.
    private var strictWARPForTesting = false

    // MARK: - Shader Pipeline State

    private var quadVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var quadPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var separableBlendQuadPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var separableBlendUniformBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var separableBlendDestinationSnapshot: D3D11BlendDestinationSnapshot?
    internal var failSeparableBlendAfterDestinationBindingForTesting = false
    private var imageVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var imagePS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var imageColorEffectPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var imageReplacementPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var imageIsolatedReplacementPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var imageIsolatedCoveragePS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var isolatedBackdropComposeVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var isolatedBackdropComposePS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var isolatedBackdropBoundsBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var colorEffectUniformBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var glyphVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var glyphPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var shadowVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var shadowPS: UnsafeMutablePointer<ID3D11PixelShader>?

    // MARK: - Shared GPU Resources

    private var frameUniformBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var blendState: UnsafeMutablePointer<ID3D11BlendState>?
    private var imageReplacementBlendState: UnsafeMutablePointer<ID3D11BlendState>?
    private var isolatedCoverageBlendState: UnsafeMutablePointer<ID3D11BlendState>?
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
    private var quadInstanceCapacity = D3D11BatchKernel.initialQuadInstanceCapacity

    private var imageInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var imageInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var imageInstanceCapacity = D3D11BatchKernel.initialImageInstanceCapacity

    private var glyphInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var glyphInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var glyphInstanceCapacity = D3D11BatchKernel.initialGlyphInstanceCapacity

    private var shadowInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var shadowInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var shadowInstanceCapacity = D3D11BatchKernel.initialShadowInstanceCapacity

    /// One atlas texture plus the upload bookkeeping the atlas protocol
    /// needs. `state` is the whole point: it records what this texture
    /// actually holds — including whether anything has been uploaded into
    /// it at all — instead of inferring it from the size, which is how a
    /// partial upload used to land in a brand-new texture.
    private struct AtlasTextureSlot {
        var texture: UnsafeMutablePointer<ID3D11Texture2D>?
        var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        var state = AtlasTextureState.uninitialized

        mutating func release() {
            releaseCOM(&srv)
            releaseCOM(&texture)
            state = .uninitialized
        }
    }

    private var glyphAtlas = AtlasTextureSlot()
    private var pixelGlyphAtlas = AtlasTextureSlot()

    /// Atlas uploads since construction, split by branch. A static text
    /// screen must add nothing to the first two after its first frame; it
    /// used to add a full 16 MiB upload to `full` on every frame.
    internal private(set) var atlasFullUploadsForTesting: UInt64 = 0
    internal private(set) var atlasRegionUploadsForTesting: UInt64 = 0
    internal private(set) var atlasSkippedUploadsForTesting: UInt64 = 0
    /// Bytes handed to the driver for atlas uploads. Counts alongside the
    /// branch counters above because the branches do not imply the cost: a
    /// region upload of 1900 rows and a full upload differ by a rounding
    /// error, and the branch counter reports them as different kinds of frame.
    internal private(set) var atlasUploadedByteCount: UInt64 = 0
    /// Submit-vs-present split of the most recent `render(scene:)`.
    private var lastSubmitSeconds: Double = 0
    private var lastPresentSeconds: Double = 0
    /// Instanced draws the most recent `render(scene:)` issued, and the number
    /// of primitives they covered between them.
    ///
    /// These are the two halves of "is `presentationOrder()` coalescing?".
    /// A scene of N primitives that draws in N calls is presentation order
    /// defeating the batcher — the family batches exist so a run of same-family
    /// primitives collapses into one `DrawInstanced`. Only the ratio is
    /// meaningful, so both are reported; a draw count alone cannot distinguish
    /// a well-batched heavy frame from a badly batched light one.
    internal private(set) var lastDrawCallCount = 0
    internal private(set) var lastDrawnInstanceCount = 0
    /// Presents are vblank-paced by default; a diagnostics run turns this off
    /// to measure the app's own frame cost without the compositor's wait, and
    /// the pacing watchdog below turns it off when the compositor proves it is
    /// not a usable clock.
    private var presentPacingPolicy = PresentPacingPolicy()
    /// Feature level `createDeviceIfNeeded` settled on, and the adapter the
    /// device landed on. Queried once per device, not per frame: `GetDesc1`
    /// is a driver round-trip.
    private var createdFeatureLevel: D3D_FEATURE_LEVEL?
    private var cachedAdapterDiagnostics: (description: String, isSoftware: Bool, dedicatedVRAM: UInt64)?
    private var cachedAdapterDiagnosticsGeneration: UInt64?

    /// The GPU side of one image, keyed by content rather than by texture
    /// ID. Texture IDs are positional within a frame's registration order,
    /// so a scene that gains or loses one image renumbers the rest; keying
    /// the textures on ``BitmapContentKey`` means that renumbering costs
    /// nothing, and the same bitmap keeps its texture across frames.
    private struct ImageTextureEntry {
        var texture: UnsafeMutablePointer<ID3D11Texture2D>?
        var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        var byteCount: Int
        var lastUsedFrame: UInt64
    }

    private var imageTextures: [BitmapContentKey: ImageTextureEntry] = [:]
    private var imageTextureByteCount = 0
    /// This frame's ID → bitmap bindings. Holds no GPU resources: the
    /// textures live in `imageTextures` and outlive any one binding.
    private var imageBindings: [Int32: BitmapSurface] = [:]
    /// IDs installed by the previous explicit scene-resource synchronization.
    /// Bindings installed directly through `bindImageResource` remain valid
    /// until replaced or detached; scene-owned IDs follow their scene instead.
    private var sceneImageTextureIDs: Set<Int32> = []
    /// Child scenes have independent texture IDs, but their immutable bitmap
    /// content still participates in the shared upload cache across frames.
    private var imageRenderPassBitmapKeys: Set<BitmapContentKey> = []
    private var imageRenderPassExecutionBudget = GPUISceneImageRenderPassBudget()
    /// Exercises actual source resolutions independently of structural scene
    /// validation. This instance-only override cannot raise the shared limits.
    internal var imageRenderPassExecutionBudgetOverrideForTesting: GPUISceneImageRenderPassBudget?

    /// Directly owned temporary target objects, including partial allocations.
    /// This is not a COM-reference count or a driver/GPU lifetime observation.
    private var directlyOwnedImagePassTargetCount = 0
    internal var directlyOwnedImagePassTargetCountForTesting: Int { directlyOwnedImagePassTargetCount }

    /// One temporary target owned by a scene-backed image draw. It is never
    /// installed in the bitmap cache and never read back to the CPU.
    private struct ImageRenderPassTarget {
        var texture: UnsafeMutablePointer<ID3D11Texture2D>?
        var view: UnsafeMutablePointer<ID3D11RenderTargetView>?
        var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        var countedOwner = false

        mutating func release() {
            releaseCOM(&srv)
            releaseCOM(&view)
            releaseCOM(&texture)
        }
    }

    /// Borrowed views into targets owned by one synchronous image occurrence.
    /// A material reads `foreground + (1 - coverage) * backdrop`; the frozen
    /// backdrop never becomes part of the foreground outside actual coverage.
    /// The four targets and this occurrence's two blur targets fit inside the
    /// shared eight-plane execution reservation. Nothing enters a frame cache.
    private final class BackdropIsolationState {
        let foreground: ImageRenderPassTarget
        let coverage: ImageRenderPassTarget
        let backdrop: ImageRenderPassTarget
        let composed: ImageRenderPassTarget
        let size: IntSize
        let validBackdropRegion: SubTextureRegion?
        var blurEngine: D3D11BackdropBlurEngine?

        init(
            foreground: ImageRenderPassTarget, coverage: ImageRenderPassTarget,
            backdrop: ImageRenderPassTarget, composed: ImageRenderPassTarget,
            size: IntSize, validBackdropRegion: SubTextureRegion?
        ) {
            self.foreground = foreground
            self.coverage = coverage
            self.backdrop = backdrop
            self.composed = composed
            self.size = size
            self.validBackdropRegion = validBackdropRegion
        }
    }

    private struct IsolatedImageRenderPassResult {
        var foreground: ImageRenderPassTarget
        var coverage: ImageRenderPassTarget
    }

    private var backdropIsolation: BackdropIsolationState?
    /// A generation-scoped pipeline template with no pixel targets. Scratch
    /// engines retain its shaders and fully re-upload shared mutable buffers
    /// on every synchronous use, while owning their own A/B textures.
    private var isolatedBlurPipeline: D3D11BackdropBlurEngine?
    internal private(set) var isolatedBlurPipelineCreationCountForTesting: UInt64 = 0
    internal var isolatedBlurPipelineHasTargetsForTesting: Bool {
        isolatedBlurPipeline?.hasAllocatedBlurTargetsForTesting ?? false
    }
    internal var isolatedBlurPipelineOwnsResourcesForTesting: Bool { isolatedBlurPipeline != nil }

    /// Exercises unwind after F has changed and local blur targets exist,
    /// before C is updated. It is confined to dependent isolation and cannot
    /// switch ordinary materials into their persistent degradation policy.
    internal var failIsolatedCoverageForTesting = false

    /// The image-effect cbuffer is a float4 count followed by one eight-float
    /// stage per supported effect, exactly as in the image-effect HLSL.
    private static let colorEffectUniformFloatCount = 4 + GPUISceneLimits.maxColorEffects * 8

    /// Image textures are large (a 4K background is 33 MB), so the cache is
    /// bounded twice: by bytes, and by how long an entry may go unused.
    /// Both bounds evict least-recently-used first, so eviction is a
    /// function of the frames that ran, not of allocator luck.
    private static let imageCacheStaleFrames: UInt64 = 30
    private static let imageCacheByteBudget = 96 * 1024 * 1024

    /// Bitmap uploads through `createImageTextureResource` since this
    /// renderer was constructed — bound images and cached path renders both
    /// go through it. An unchanged image must not add to this once per
    /// frame; that is the whole point of keying the cache on content.
    internal private(set) var imageTextureUploadsForTesting: UInt64 = 0

    // Path rasterization is CPU-bound (we don't yet have a real GPU
    // tessellator), so caching the resulting bitmap + GPU texture across
    // frames is the difference between "redo every frame" and "upload once
    // per path shape". Keys are normalized to a (0,0) origin so translating
    // the path doesn't bust the cache; the draw call still positions the
    // resulting texture at the original bounds.origin.
    /// What identifies a cached path *raster*: a digest of its shape and its
    /// paint, its extent, and the sub-rect of it that was rasterized — and
    /// nothing about where it is on screen or what is clipping it. The clip
    /// is applied at draw time (see `renderPathBatch`), so a chart scrolling
    /// inside a `ScrollView` keeps one entry and one upload instead of
    /// missing on every frame the clip moves.
    ///
    /// Every field is a scalar, so a lookup hashes and compares in constant
    /// time. It used to hold a whole `PathPrimitive`, normalized to a (0, 0)
    /// origin — which meant building `path.translated(by: -origin)` on every
    /// frame for every path just to have something to hash, and a full
    /// element-array `==` on every *hit*. The exact comparison survives as
    /// `CachedPathRender.path` + `matchesShapeAndPaint`, run only when the
    /// digest matches, so a collision still costs one comparison and never a
    /// wrong texture.
    private struct PathRasterKey: Hashable {
        let shapeHash: Int
        let elementCount: Int
        let extentWidth: Double
        let extentHeight: Double
        /// The path-local window that was rasterized. `windowed` is false for
        /// the common whole-path raster, where the other three are zero.
        let windowed: Bool
        let windowX: Double
        let windowY: Double
        let windowWidth: Double
        let windowHeight: Double

        init(path: PathPrimitive, window: Rect?) {
            shapeHash = path.shapeHash
            elementCount = path.elements.count
            extentWidth = path.bounds.size.width
            extentHeight = path.bounds.size.height
            windowed = window != nil
            windowX = window?.origin.x ?? 0
            windowY = window?.origin.y ?? 0
            windowWidth = window?.size.width ?? 0
            windowHeight = window?.size.height ?? 0
        }
    }

    private struct CachedPathRender {
        var texture: UnsafeMutablePointer<ID3D11Texture2D>
        var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>
        var bitmapSize: IntSize
        var lastUsedFrame: UInt64
        var memoryBytes: Int
        /// The normalized path this raster was made from, kept as the exact
        /// tie-break behind the digest key. Its element array is a fraction
        /// of the raster it describes.
        var path: PathPrimitive
    }

    /// One frame's answer for one path: the texture to draw, its size, and
    /// where its top-left sits inside the path's own bounds.
    private struct PathRaster {
        var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        var bitmapSize: IntSize
        /// Offset of the raster's top-left from `path.bounds.origin`. Zero
        /// unless the raster is a window onto a larger path.
        var originOffset: Point
        /// Set when the raster was too large for the cache to ever hold: the
        /// caller owns it and releases it after the draw.
        var owned:
            (
                texture: UnsafeMutablePointer<ID3D11Texture2D>,
                srv: UnsafeMutablePointer<ID3D11ShaderResourceView>
            )?

        /// Nothing to draw: the path rasterized to no pixels.
        static var nothing: PathRaster {
            PathRaster(srv: nil, bitmapSize: .zero, originOffset: .zero, owned: nil)
        }
    }

    private var pathRenderCache: [PathRasterKey: CachedPathRender] = [:]
    private var pathRenderCacheBytes = 0
    private var frameCounter: UInt64 = 0
    private static let pathCacheStaleFrames: UInt64 = 60
    private static let pathCacheMaxEntries = 256
    /// Path rasters are bounded by count *and* by bytes for the same reason
    /// image textures are: dropping the clip from the key means an entry now
    /// covers the path's whole extent, so one off-screen 4K chart is a 64 MB
    /// entry that 256 of would be unbounded in any useful sense.
    private var pathCacheByteBudget: Int { pathCacheByteBudgetOverrideForTesting ?? 64 * 1024 * 1024 }
    /// Largest whole-path raster the renderer will make, in bytes.
    ///
    /// Below this the raster covers the entire path and the key stays
    /// translation- *and* clip-invariant, which is what makes a scrolling
    /// chart one entry and one upload. Above it — a tall `Canvas` inside a
    /// short `ScrollView`, whose bounds run to thousands of points — the
    /// raster follows what can actually be seen instead, because sizing it
    /// off the unclipped bounds allocated coverage, bitmap and texture for
    /// every row the viewport will never show, up to the 16 384 px surface
    /// clamp.
    private var pathWholeRasterByteBudget: Int {
        pathWholeRasterByteBudgetOverrideForTesting ?? 8 * 1024 * 1024
    }
    /// Grid, in device pixels, that a windowed raster snaps out to. A scroll
    /// of one pixel must not be a new cache entry; a scroll of a tile is.
    internal static let pathRasterWindowTile: Double = 128

    /// Test seams for the two byte budgets. "One outlier does not flush the
    /// cache" is a property of the budget, not of its value, and reaching a
    /// 64 MB entry for real would mean rasterizing 16 megapixels in a unit
    /// test. The actor facade copies its current overrides before each
    /// render. Native kernels keep their own defaults and never read actor
    /// state. Both are `nil` outside tests.
    internal var pathCacheByteBudgetOverrideForTesting: Int?
    internal var pathWholeRasterByteBudgetOverrideForTesting: Int?
    // Test-observable counters so we can verify the cache is actually being
    // hit across frames.
    internal private(set) var pathCacheHits: UInt64 = 0
    internal private(set) var pathCacheMisses: UInt64 = 0
    /// Rasters denied a cache slot because one entry would have exhausted the
    /// whole byte budget. Test-observable so "an outlier does not flush the
    /// cache" is checkable.
    internal private(set) var pathCacheOversizedDenials: UInt64 = 0
    /// Largest raster this renderer has made, in pixels. Test-observable so
    /// "a huge path inside a small clip rasterizes bounded" is checkable.
    internal private(set) var largestPathRasterPixelsForTesting: Int = 0

    internal var pathCacheEntryCountForTesting: Int { pathRenderCache.count }
    internal var pathCacheByteCountForTesting: Int { pathRenderCacheBytes }

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

    /// Test seam for the recovery wait. Production blocks this owner for
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
    /// holdings through `blurEngineOwnsResourcesForTesting`,
    /// `isolatedBlurPipelineOwnsResourcesForTesting` and `pathCacheEntryCountForTesting`.
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
        tally(separableBlendQuadPS.map(UnsafeMutableRawPointer.init))
        tally(separableBlendUniformBuffer.map(UnsafeMutableRawPointer.init))
        if let snapshot = separableBlendDestinationSnapshot {
            tally(snapshot.texture.map(UnsafeMutableRawPointer.init))
            tally(snapshot.srv.map(UnsafeMutableRawPointer.init))
        }
        tally(imageVS.map(UnsafeMutableRawPointer.init))
        tally(imagePS.map(UnsafeMutableRawPointer.init))
        tally(imageColorEffectPS.map(UnsafeMutableRawPointer.init))
        tally(imageReplacementPS.map(UnsafeMutableRawPointer.init))
        tally(imageIsolatedReplacementPS.map(UnsafeMutableRawPointer.init))
        tally(imageIsolatedCoveragePS.map(UnsafeMutableRawPointer.init))
        tally(isolatedBackdropComposeVS.map(UnsafeMutableRawPointer.init))
        tally(isolatedBackdropComposePS.map(UnsafeMutableRawPointer.init))
        tally(isolatedBackdropBoundsBuffer.map(UnsafeMutableRawPointer.init))
        tally(colorEffectUniformBuffer.map(UnsafeMutableRawPointer.init))
        tally(glyphVS.map(UnsafeMutableRawPointer.init))
        tally(glyphPS.map(UnsafeMutableRawPointer.init))
        tally(shadowVS.map(UnsafeMutableRawPointer.init))
        tally(shadowPS.map(UnsafeMutableRawPointer.init))

        tally(frameUniformBuffer.map(UnsafeMutableRawPointer.init))
        tally(blendState.map(UnsafeMutableRawPointer.init))
        tally(imageReplacementBlendState.map(UnsafeMutableRawPointer.init))
        tally(isolatedCoverageBlendState.map(UnsafeMutableRawPointer.init))
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

        tally(glyphAtlas.texture.map(UnsafeMutableRawPointer.init))
        tally(glyphAtlas.srv.map(UnsafeMutableRawPointer.init))
        tally(pixelGlyphAtlas.texture.map(UnsafeMutableRawPointer.init))
        tally(pixelGlyphAtlas.srv.map(UnsafeMutableRawPointer.init))

        for entry in imageTextures.values {
            tally(entry.texture.map(UnsafeMutableRawPointer.init))
            tally(entry.srv.map(UnsafeMutableRawPointer.init))
        }
        for entry in pathRenderCache.values {
            tally(UnsafeMutableRawPointer(entry.texture))
            tally(UnsafeMutableRawPointer(entry.srv))
        }

        count += gpuFrameTimingCollector?.ownedQueryCount ?? 0

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

    /// The live device, for the one test that has to talk to it directly:
    /// the debug layer's live-object check queries `ID3D11Debug` off it.
    internal var deviceForTesting: UnsafeMutablePointer<ID3D11Device>? { device }

    /// Test seam: adds `D3D11_CREATE_DEVICE_DEBUG` to the next device
    /// creation, so `ID3D11Debug` can be queried and live objects counted
    /// across attach/detach cycles. Off in production — the debug layer
    /// costs an order of magnitude in draw-call overhead and needs the
    /// Graphics Tools feature installed, which a user machine need not
    /// have.
    internal var createsDebugDeviceForTesting = false

    /// One piece of a quad batch after splitting around Material quads.
    /// Normal runs keep the single instanced draw; each blurred quad is
    /// drawn individually through the backdrop blur engine so the blur
    /// samples the scene exactly as painted before that quad.
    enum QuadBatchSegment: Equatable, Sendable {
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
            // Saturating: this predicate runs for every quad in every
            // scene before any culling, so a single NaN blur radius here
            // is a process kill on the hottest path in the backend.
            let isBlurred = GPUISceneValue.int(quad.blurRadius) > 0
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

    /// Records which bitmap a texture ID refers to this frame.
    ///
    /// Binding is pure bookkeeping — no conversion, no upload, no release.
    /// `bindResources(for:)` runs every frame, and this used to release the
    /// texture and SRV of every bound image on every one of them, so an
    /// unchanged `Image` (or a `.drawingGroup()` compositing bitmap) paid a
    /// full-surface premultiply plus a `CreateTexture2D` per frame. The
    /// texture is resolved from the bitmap's content key at draw time
    /// instead, so re-binding the same content — under this ID or any
    /// other — costs nothing.
    ///
    /// A texture the bindings have walked away from is retired by
    /// `collectUnreferencedImageTextures()` at the top of the next frame,
    /// not here: within a frame the bindings are mid-rewrite, and a scene
    /// that renumbers its texture IDs would otherwise release a texture the
    /// binding two lines further down is about to ask for again.
    public func bindImageResource(_ bitmap: BitmapSurface, for textureID: Int32) {
        guard textureID >= 0 else {
            return
        }
        imageBindings[textureID] = bitmap
    }

    public func bindResources(for scene: GPUIScene) {
        var currentSceneTextureIDs = Set<Int32>(minimumCapacity: scene.imageResources.count)
        for binding in scene.imageResources {
            guard binding.textureID >= 0 else {
                continue
            }
            currentSceneTextureIDs.insert(binding.textureID)
            bindImageResource(binding.bitmap, for: binding.textureID)
        }

        // The scene owns these bindings, so an image removed from a later
        // frame must not keep its bitmap alive or silently satisfy an image
        // primitive that forgot to supply its own resource. Prune only IDs
        // synchronized from an earlier scene: standalone manual bindings
        // remain valid, and content-keyed textures survive ID renumbering.
        for textureID in sceneImageTextureIDs where !currentSceneTextureIDs.contains(textureID) {
            imageBindings.removeValue(forKey: textureID)
        }
        sceneImageTextureIDs = currentSceneTextureIDs

        imageRenderPassBitmapKeys.removeAll(keepingCapacity: true)
        var budget = GPUISceneImageRenderPassBudget()
        func collectImageRenderPassBitmapKeys(in namespace: GPUIScene, depth: Int, inBackdropIsolation: Bool) {
            // Match validation's depth-first namespace order. Count values at
            // every occurrence; shared child arrays do not make sources free.
            var textureIDs = Set(namespace.imageResources.map(\.textureID))
            for pass in namespace.imageRenderPasses {
                guard budget.consume(pass, inBackdropIsolation: inBackdropIsolation) else { return }
                guard pass.textureID >= 0, textureIDs.insert(pass.textureID).inserted,
                    pass.colorEffects.count <= GPUISceneLimits.maxColorEffects,
                    depth < GPUISceneLimits.maxImageRenderPassDepth
                else { continue }
                for binding in pass.scene.imageResources {
                    imageRenderPassBitmapKeys.insert(binding.bitmap.contentKey)
                }
                let childIsolation =
                    pass.input == .isolatedBackdrop || (pass.input == .currentTarget && inBackdropIsolation)
                collectImageRenderPassBitmapKeys(
                    in: pass.scene, depth: depth + 1, inBackdropIsolation: childIsolation)
            }
        }
        // Binding precedes validation. Stop each rejected namespace walk;
        // makeRenderPlan will report its invalid scene before any drawing.
        collectImageRenderPassBitmapKeys(in: scene, depth: 0, inBackdropIsolation: false)
    }

    /// Releases the GPU side of every cached image and forgets the
    /// bindings. The bitmaps themselves are re-supplied by
    /// `bindResources(for:)` on the next frame, so nothing is lost by
    /// dropping them with the device.
    private func releaseAllImageResources() {
        // Snapshot the keys: the loop body mutates the dictionary.
        for key in Array(imageTextures.keys) {
            releaseImageTexture(forKey: key)
        }
        imageBindings.removeAll()
        sceneImageTextureIDs.removeAll()
        imageRenderPassBitmapKeys.removeAll()
    }

    private func releaseImageTexture(forKey key: BitmapContentKey) {
        guard var entry = imageTextures.removeValue(forKey: key) else {
            return
        }
        imageTextureByteCount -= entry.byteCount
        releaseCOM(&entry.srv)
        releaseCOM(&entry.texture)
    }

    /// Releases every cached texture no live binding refers to any more.
    ///
    /// The cache is keyed on content and the bindings are keyed on texture
    /// ID, so rebinding an ID to different pixels orphans the old entry
    /// rather than replacing it. Without this, content that changes every
    /// frame — an animating `.drawingGroup()` re-rasterizes its bitmap, and
    /// every rasterization mints a new content token — piled dead textures
    /// up until the 30-frame sweep or the 96 MB budget caught them, which
    /// for a full-window group is hundreds of megabytes of live GPU memory
    /// standing in for one visible image.
    ///
    /// Runs at the top of the frame, after `bindResources(for:)` has applied
    /// every binding this frame asks for, so "unreferenced" means what it
    /// says: a scene that renumbers texture IDs has finished renumbering by
    /// the time this looks. Scene-owned bindings disappear when their images
    /// leave the next scene, so their GPU resources are reclaimed on that
    /// same frame; explicitly installed manual bindings continue to persist.
    private func collectUnreferencedImageTextures() {
        guard !imageTextures.isEmpty else {
            return
        }
        var referenced = imageRenderPassBitmapKeys
        for bitmap in imageBindings.values {
            referenced.insert(bitmap.contentKey)
        }
        // Snapshot the keys: the loop body mutates the dictionary.
        for key in Array(imageTextures.keys) where !referenced.contains(key) {
            releaseImageTexture(forKey: key)
        }
    }

    /// Drops image textures nothing has drawn for `imageCacheStaleFrames`,
    /// then trims the least recently used until the byte budget is met.
    ///
    /// Runs once per frame, before any of the frame's draws, so an entry
    /// this frame will use — touched no later than the previous frame —
    /// is never the one evicted.
    private func evictStaleImageTextures() {
        if frameCounter > Self.imageCacheStaleFrames {
            let staleThreshold = frameCounter - Self.imageCacheStaleFrames
            let stale = imageTextures.filter { $0.value.lastUsedFrame < staleThreshold }
            for (key, _) in stale {
                releaseImageTexture(forKey: key)
            }
        }

        guard imageTextureByteCount > Self.imageCacheByteBudget else {
            return
        }
        let leastRecentlyUsedFirst = imageTextures.sorted { $0.value.lastUsedFrame < $1.value.lastUsedFrame }
        for (key, _) in leastRecentlyUsedFirst {
            guard imageTextureByteCount > Self.imageCacheByteBudget else { break }
            releaseImageTexture(forKey: key)
        }
    }

    internal var cachedResourcesForTesting: CachedResources {
        CachedResources(
            hasGlyphAtlas: glyphAtlas.srv != nil,
            hasPixelGlyphAtlas: pixelGlyphAtlas.srv != nil,
            boundImageTextureIDs: Set(imageBindings.keys)
        )
    }

    /// Test seam: the texture and SRV addresses backing `textureID`, or
    /// `nil` when nothing is cached for it. Pointer identity is how a test
    /// tells "reused the texture" from "recreated an identical one".
    internal func imageTextureIdentityForTesting(for textureID: Int32) -> (texture: UInt, srv: UInt)? {
        guard let bitmap = imageBindings[textureID], let entry = imageTextures[bitmap.contentKey],
            let texture = entry.texture, let srv = entry.srv
        else {
            return nil
        }
        return (UInt(bitPattern: texture), UInt(bitPattern: srv))
    }

    internal var imageTextureCacheCountForTesting: Int {
        imageTextures.count
    }

    /// Scene validation can see inline resources and render passes, but a
    /// caller can also bind a bitmap directly. Validate those actual source
    /// dimensions before uploading or issuing any image sampling commands.
    func validateBoundImageSampling(in scene: GPUIScene) throws {
        let passTextureIDs = Set(scene.imageRenderPasses.map(\.textureID))
        for layer in scene.layers {
            for image in layer.images where image.sampling != .legacy {
                guard !passTextureIDs.contains(image.textureID), let bitmap = imageBindings[image.textureID] else {
                    continue
                }
                if let failure = image.sampling.validationFailure(
                    sourceSize: IntSize(width: bitmap.width, height: bitmap.height),
                    uvX: image.uvX, uvY: image.uvY, uvW: image.uvW, uvH: image.uvH
                ) {
                    throw BatchRendererError(
                        operation: "Validate image sampling",
                        hresult: batchHresultInvalidArgument,
                        details: "Texture \(image.textureID): \(failure)",
                        failureKind: .sceneContent
                    )
                }
            }
        }
    }

    public static func makeRenderPlan(
        for scene: GPUIScene,
        cachedResources: CachedResources = CachedResources()
    ) throws -> RenderPlan {
        // Structural validation runs unconditionally, not only in debug:
        // the plan builder below turns every paint operation into a
        // `Range` and indexes the family arrays with it, and both of
        // those *trap* on a malformed layer. A trap is the one failure
        // the host's fallback policy cannot downgrade; a thrown
        // `.sceneContent` error it can. `validate()` is O(layers + paint
        // operations) and allocates nothing when the scene is clean.
        if let defect = scene.validate().first {
            throw BatchRendererError(
                operation: "Validate scene",
                hresult: batchHresultInvalidArgument,
                details: defect.description,
                failureKind: .sceneContent
            )
        }

        let usesGlyphs = scene.usesGlyphs
        let usesPixelGlyphs = scene.usesPixelGlyphs

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

        let renderPassTextureIDs = Set(scene.imageRenderPasses.map(\.textureID))
        var unresolvedTextureIDs = Set<Int32>()
        for layer in scene.layers {
            for image in layer.images
            where image.textureID < 0
                || (!cachedResources.boundImageTextureIDs.contains(image.textureID)
                    && !renderPassTextureIDs.contains(image.textureID))
            {
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

        // `presentationOrder()` is the scene's single draw-order
        // authority: layers in index order, and within each layer
        // `layer.paintOperations` in order. The CPU rasterizer walks the
        // same sequence, so a plan step and a rasterized primitive are the
        // same primitive in the same position — which is what makes a
        // cross-backend pixel comparison mean anything.
        var steps: [RenderStep] = []
        for run in scene.presentationOrder() {
            let layerIndex = run.layerIndex
            let range = run.range
            switch run.kind {
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
                let images = scene.layers[layerIndex].images
                var runStart = range.lowerBound
                while runStart < range.upperBound {
                    let textureID = images[runStart].textureID
                    var runEnd = runStart + 1
                    while runEnd < range.upperBound, images[runEnd].textureID == textureID {
                        runEnd += 1
                    }
                    steps.append(.images(layerIndex: layerIndex, range: runStart..<runEnd, textureID: textureID))
                    runStart = runEnd
                }
            case .path:
                steps.append(.paths(layerIndex: layerIndex, range: range))
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
        guard let windowHandle = surface.windowHandle,
            let hwnd = unsafeBitCast(windowHandle.rawPointer, to: HWND?.self)
        else {
            throw BatchRendererError(
                operation: "Resolve HWND",
                hresult: batchHresultHandle,
                details: "Windowed D3D11 batch presentation requires a native window surface.",
                failureKind: .permanent
            )
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

        // Hardware first, then WARP: a machine with no usable hardware adapter
        // can still present through the software rasterizer, and a slow window
        // beats the blank one a hard failure here produces.
        try createDeviceIfNeeded(driverTypes: [D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP])
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
    ///
    /// Internal, like every other seam this renderer exposes for tests
    /// (`simulateDeviceLossForTesting`, `cachedResourcesForTesting`): the
    /// only callers are suites that already `@testable import` this module,
    /// and a render target that bypasses `attach(to:)` is not a surface the
    /// package supports.
    internal func attachOffscreen(size: IntSize, driver: OffscreenDriver = .hardwareFirst) throws {
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

    /// A strict setup seam for blend regressions. Existing attach/device
    /// negotiation stays unchanged; this path attempts only WARP at FL11_0,
    /// then executes the same real pipeline and offscreen target creation.
    internal func attachOffscreenWARPForTesting(size: IntSize) throws {
        detach()
        var succeeded = false
        defer { if !succeeded { detach() } }
        targetPixelSize = size
        renderTargetKind = .offscreen
        offscreenDriver = .warpFirst
        var createdDevice: UnsafeMutablePointer<ID3D11Device>?
        var createdContext: UnsafeMutablePointer<ID3D11DeviceContext>?
        var featureLevel = D3D_FEATURE_LEVEL(0)
        defer {
            releaseCOM(&createdContext)
            releaseCOM(&createdDevice)
        }
        let levels = [D3D_FEATURE_LEVEL_11_0]
        let flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)
        let result = levels.withUnsafeBufferPointer { requested in
            D3D11CreateDevice(
                nil, D3D_DRIVER_TYPE_WARP, nil, flags,
                requested.baseAddress, UINT(requested.count), UINT(D3D11_SDK_VERSION),
                &createdDevice, &featureLevel, &createdContext)
        }
        guard result >= 0, createdDevice != nil, createdContext != nil, featureLevel == D3D_FEATURE_LEVEL_11_0 else {
            throw BatchRendererError(
                operation: "D3D11CreateDevice(strict WARP)", hresult: result < 0 ? result : batchHresultHandle)
        }
        device = createdDevice
        deviceContext = createdContext
        createdDevice = nil
        createdContext = nil
        createdFeatureLevel = featureLevel
        deviceGeneration = RendererDeviceGeneration.next()
        attachGPUFrameTimingCollectorIfNeeded()
        try createPipelineIfNeeded()
        try createOffscreenTarget(size: size)
        strictWARPForTesting = true
        isAttached = true
        succeeded = true
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
        // Query handles belong to this context. Invalidation also leaves
        // terminal records available to the host after the context is gone.
        gpuFrameTimingCollector?.detach()
        lastFrameSubmission = nil
        if let deviceContext {
            var noTargets: UnsafeMutablePointer<ID3D11RenderTargetView>?
            deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &noTargets, nil)
            deviceContext.pointee.lpVtbl.pointee.ClearState(deviceContext)
            deviceContext.pointee.lpVtbl.pointee.Flush(deviceContext)
        }

        blurEngine?.detach()
        blurEngine = nil
        isolatedBlurPipeline?.detach()
        isolatedBlurPipeline = nil
        backdropIsolation = nil
        separableBlendDestinationSnapshot?.release()
        separableBlendDestinationSnapshot = nil
        releaseAllCachedPaths()
        releaseAllImageResources()

        glyphAtlas.release()
        pixelGlyphAtlas.release()

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
        releaseCOM(&imageReplacementBlendState)
        releaseCOM(&isolatedCoverageBlendState)
        releaseCOM(&frameUniformBuffer)
        releaseCOM(&separableBlendUniformBuffer)
        failSeparableBlendAfterDestinationBindingForTesting = false
        strictWARPForTesting = false
        releaseCOM(&colorEffectUniformBuffer)
        releaseCOM(&isolatedBackdropBoundsBuffer)

        releaseCOM(&shadowPS)
        releaseCOM(&shadowVS)
        releaseCOM(&glyphPS)
        releaseCOM(&glyphVS)
        releaseCOM(&imagePS)
        releaseCOM(&imageVS)
        releaseCOM(&imageColorEffectPS)
        releaseCOM(&imageReplacementPS)
        releaseCOM(&imageIsolatedReplacementPS)
        releaseCOM(&imageIsolatedCoveragePS)
        releaseCOM(&isolatedBackdropComposeVS)
        releaseCOM(&isolatedBackdropComposePS)
        releaseCOM(&separableBlendQuadPS)
        releaseCOM(&quadPS)
        releaseCOM(&quadVS)

        releaseCOM(&renderTargetView)
        releaseCOM(&offscreenTexture)
        let acquisitionRelease = displayAcquisitionEpoch?.sample()
        releaseCOM(&swapChain)
        displayAcquisitionEpoch?.didRelease(at: acquisitionRelease)
        displayAcquisitionEpoch = nil
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
        // The pacing window described a swap chain that no longer exists. The
        // *mode* survives — an explicit vsync override and a compositor that
        // was stalling us a moment ago both outlive one swap chain — but the
        // samples behind it do not.
        presentPacingPolicy.reset()
        isAttached = false
        // `deviceLostRecoveryAttempts` deliberately survives: detach is a
        // *step* of device-loss recovery, and resetting the budget here
        // would make the bounded retry unbounded.
    }

    deinit {
        // Native teardown remains explicit on the execution owner. The
        // facade has no second backstop, so one forgotten detach reports
        // exactly once when this kernel is released.
        if isAttached {
            RendererTeardownBackstop.reportUndetachedTeardown(
                "D3D11BatchRenderer was deallocated while still attached — its device, swap chain and "
                    + "atlases leak. Call detach() from the owner's teardown."
            )
        }
    }

    public func resize(to size: IntSize) throws {
        if size != targetPixelSize, size.width > 0, size.height > 0 {
            separableBlendDestinationSnapshot?.release()
            separableBlendDestinationSnapshot = nil
        }
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
        // Never let a skipped or failed attempt inherit a previous frame's
        // identity or phase counters. A phase not completed by this attempt
        // keeps zero; partial draws are not cleared on failure or occlusion.
        // Query completion is reported separately.
        lastSubmitSeconds = 0
        lastPresentSeconds = 0
        lastDrawCallCount = 0
        lastDrawnInstanceCount = 0
        lastFrameSubmission = BackendFrameSubmission(
            outcome: .skipped, gpuTimingStatus: gpuFrameTimingCollector?.currentStatus ?? .disabled)
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
        collectUnreferencedImageTextures()
        evictStaleImageTextures()
        // Re-fetch the render-target guards: the eviction calls above are
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

        let frameID = BackendFrameID(deviceGeneration: deviceGeneration, frameNumber: frameCounter)
        // Resolving adapter diagnostics can query COM and allocate. Keep
        // that work outside the legacy frame timers: this issuing snapshot
        // uses only an already resolved cache for this exact generation.
        // Capture it once so Present recovery cannot replace its device.
        let adapterIsSoftware = Self.cachedAdapterIsSoftware(
            forDeviceGeneration: frameID.deviceGeneration,
            cachedGeneration: cachedAdapterDiagnosticsGeneration,
            cachedIsSoftware: cachedAdapterDiagnostics?.isSoftware)
        var gpuTimingStatus = gpuFrameTimingCollector?.currentStatus ?? .disabled
        lastFrameSubmission = BackendFrameSubmission(
            id: frameID, outcome: .aborted, gpuTimingStatus: gpuTimingStatus, adapterIsSoftware: adapterIsSoftware)
        let submitStartedAt = Self.nowSeconds()
        imageRenderPassExecutionBudget =
            imageRenderPassExecutionBudgetOverrideForTesting ?? GPUISceneImageRenderPassBudget()

        do {
            var finishedScene = scene
            finishedScene.finish()
            try validateBoundImageSampling(in: finishedScene)
            let renderPlan = try Self.makeRenderPlan(for: finishedScene, cachedResources: cachedResourcesForTesting)

            gpuTimingStatus = gpuFrameTimingCollector?.beginFrame(frameID) ?? .disabled
            lastFrameSubmission = BackendFrameSubmission(
                id: frameID, outcome: .aborted, gpuTimingStatus: gpuTimingStatus, adapterIsSoftware: adapterIsSoftware)
            bindFramePipelineState(deviceContext: deviceContext, surfaceSize: surfacePixelSize)

            let cc = finishedScene.clearColor
            // Every draw and readback treats this render target as premultiplied.
            // ClearRenderTargetView writes its values directly, bypassing blending,
            // so a translucent straight-alpha clear must be converted first too.
            // Otherwise its RGB can exceed its alpha and later source-over draws
            // retain color from pixels that were meant to be partly transparent.
            let clearValues: [FLOAT] = [
                cc.red * cc.alpha,
                cc.green * cc.alpha,
                cc.blue * cc.alpha,
                cc.alpha,
            ]
            clearValues.withUnsafeBufferPointer { buffer in
                deviceContext.pointee.lpVtbl.pointee.ClearRenderTargetView(
                    deviceContext, renderTargetView, buffer.baseAddress)
            }

            try updateFrameUniforms(surfaceSize: surfacePixelSize)
            try renderSceneContents(
                finishedScene, renderPlan: renderPlan, deviceContext: deviceContext,
                surfaceSize: surfacePixelSize, imageRenderPassDepth: 0)
            // End before readback or Present: Present may replace the device,
            // so a function-level defer could touch a released context.
            gpuFrameTimingCollector?.endFrame(frameID)
        } catch {
            let lostDevice = PresentationFailureKind.classifying(error) == .deviceLost
            if gpuTimingStatus == .pending {
                gpuTimingStatus = lostDevice ? .deviceLost : .aborted
                gpuFrameTimingCollector?.abortFrame(
                    frameID, status: gpuTimingStatus, failureCode: (error as? BatchRendererError)?.hresult)
            }
            // abortFrame(.deviceLost) invalidates instead of ending queries;
            // this also handles losses on attempts that issued no interval.
            if lostDevice { gpuFrameTimingCollector?.detach(status: .deviceLost) }
            lastFrameSubmission = BackendFrameSubmission(
                id: frameID, outcome: .aborted, gpuTimingStatus: gpuTimingStatus, adapterIsSoftware: adapterIsSoftware)
            throw error
        }

        // Keep diagnostic readback outside submit/present timing; normal
        // presentation, including nested image passes, never reads back.
        lastSubmitSeconds = Self.nowSeconds() - submitStartedAt
        capturePresentedFrameIfRequested()

        let presentStartedAt = Self.nowSeconds()
        do {
            try presentFrame(frameID: frameID)
        } catch {
            if gpuTimingStatus == .pending {
                gpuTimingStatus = PresentationFailureKind.classifying(error) == .deviceLost ? .deviceLost : .aborted
                gpuFrameTimingCollector?.abortFrame(
                    frameID, status: gpuTimingStatus, failureCode: (error as? BatchRendererError)?.hresult)
            }
            lastFrameSubmission = BackendFrameSubmission(
                id: frameID, outcome: .failed, gpuTimingStatus: gpuTimingStatus, adapterIsSoftware: adapterIsSoftware)
            throw error
        }
        let presentEndedAt = Self.nowSeconds()
        lastPresentSeconds = presentEndedAt - presentStartedAt
        if renderTargetKind == .swapChain {
            presentPacingPolicy.recordPresent(
                seconds: lastPresentSeconds,
                frameCostSeconds: lastSubmitSeconds,
                at: presentEndedAt)
        }
        if deviceGeneration != frameID.deviceGeneration {
            // Recovery returns without presenting the old device's frame.
            lastFrameSubmission = BackendFrameSubmission(
                id: frameID, outcome: .failed,
                gpuTimingStatus: gpuTimingStatus == .pending ? .deviceLost : gpuTimingStatus,
                adapterIsSoftware: adapterIsSoftware)
        } else {
            let outcome: BackendFrameSubmissionOutcome =
                presentationState.isOccluded ? .occluded : (renderTargetKind == .offscreen ? .offscreen : .submitted)
            lastFrameSubmission = BackendFrameSubmission(
                id: frameID, outcome: outcome, gpuTimingStatus: gpuTimingStatus, adapterIsSoftware: adapterIsSoftware)
        }
    }

    /// Draws into the currently bound target without clearing, presenting,
    /// evicting resources or resetting frame diagnostics. Both the outer frame
    /// and a nested image source execute the same presentation-order steps.
    private func renderSceneContents(
        _ finishedScene: GPUIScene,
        renderPlan: RenderPlan,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        surfaceSize: IntSize,
        imageRenderPassDepth: Int
    ) throws {
        if renderPlan.glyphAtlasSource == .snapshot || !finishedScene.imageRenderPasses.isEmpty,
            let snapshot = finishedScene.glyphAtlas
        {
            try updateGlyphAtlasTexture(snapshot, slot: &glyphAtlas)
        }
        if renderPlan.pixelGlyphAtlasSource == .snapshot || !finishedScene.imageRenderPasses.isEmpty,
            let snapshot = finishedScene.pixelGlyphAtlas
        {
            try updateGlyphAtlasTexture(snapshot, slot: &pixelGlyphAtlas)
        }

        let imagePasses = Dictionary(
            finishedScene.imageRenderPasses.map { ($0.textureID, $0) },
            uniquingKeysWith: { _, latest in latest })
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
                        try renderOrdinaryQuadRange(
                            layer.quads, range: subRange, deviceContext: deviceContext, surfaceSize: surfaceSize)
                    case .blurred(let index):
                        try renderMaterialQuad(
                            layer.quads,
                            index: index,
                            deviceContext: deviceContext,
                            surfaceSize: surfaceSize
                        )
                    }
                }
            case .glyphs(let layerIndex, let range, _):
                let layer = finishedScene.layers[layerIndex]
                try renderGlyphBatch(
                    layer.glyphs,
                    range: range,
                    atlasSRV: glyphAtlas.srv,
                    deviceContext: deviceContext
                )
            case .pixelGlyphs(let layerIndex, let range, _):
                let layer = finishedScene.layers[layerIndex]
                try renderGlyphBatch(
                    layer.pixelGlyphs,
                    range: range,
                    atlasSRV: pixelGlyphAtlas.srv,
                    deviceContext: deviceContext
                )
            case .images(let layerIndex, let range, let textureID):
                let layer = finishedScene.layers[layerIndex]
                if let pass = imagePasses[textureID] {
                    if pass.input == .isolatedBackdrop || (pass.input == .currentTarget && backdropIsolation != nil) {
                        // The backdrop belongs to this exact occurrence in the
                        // presentation order. A repeated ID must not reuse its
                        // earlier foreground, coverage or frozen parent pixels.
                        for index in range {
                            var result = try renderIsolatedImageRenderPass(
                                pass, consumingImage: layer.images[index], deviceContext: deviceContext,
                                depth: imageRenderPassDepth + 1)
                            defer {
                                releaseImageRenderPassTarget(&result.coverage)
                                releaseImageRenderPassTarget(&result.foreground)
                            }
                            try renderIsolatedImage(
                                layer.images, index: index, result: result,
                                deviceContext: deviceContext, surfaceSize: surfaceSize)
                        }
                        continue
                    }
                    if pass.input == .currentTarget {
                        // Even adjacent consumers of one ID have different
                        // placement or scene-so-far dependencies. Realize each
                        // occurrence only after the preceding one composites.
                        for index in range {
                            var target = try renderImageRenderPass(
                                pass, consumingImage: layer.images[index], deviceContext: deviceContext,
                                depth: imageRenderPassDepth + 1)
                            defer { releaseImageRenderPassTarget(&target) }
                            guard let textureSRV = target.srv else {
                                throw BatchRendererError(
                                    operation: "Resolve current-target image render pass", hresult: batchHresultHandle)
                            }
                            try renderCurrentTargetImage(
                                layer.images, index: index, deviceContext: deviceContext,
                                textureSRV: textureSRV, surfaceSize: surfaceSize)
                        }
                        continue
                    }
                    var target = try renderImageRenderPass(
                        pass, deviceContext: deviceContext, depth: imageRenderPassDepth + 1)
                    defer { releaseImageRenderPassTarget(&target) }
                    guard let textureSRV = target.srv else {
                        throw BatchRendererError(operation: "Resolve image render pass", hresult: batchHresultHandle)
                    }
                    try renderImageBatch(
                        layer.images, range: range, deviceContext: deviceContext, textureSRV: textureSRV)
                    continue
                }
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
    }

    /// Renders a child on this device, preserving the parent's target and
    /// resource namespace. Only the returned target survives this call; its
    /// caller releases it immediately after the corresponding image run.
    private func renderImageRenderPass(
        _ pass: GPUISceneImageRenderPass,
        consumingImage: ImagePrimitive? = nil,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        depth: Int
    ) throws -> ImageRenderPassTarget {
        guard pass.hasValidExtent, depth <= GPUISceneLimits.maxImageRenderPassDepth,
            pass.colorEffects.count <= GPUISceneLimits.maxColorEffects
        else {
            throw BatchRendererError(
                operation: "Validate image render pass", hresult: batchHresultInvalidArgument,
                details: "The image pass exceeds the shared extent, nesting or effect-count limit.",
                failureKind: .sceneContent)
        }

        var parentBackdrop: UnsafeMutablePointer<ID3D11Texture2D>?
        defer { releaseCOM(&parentBackdrop) }
        var parentRegion: SubTextureRegion?
        if pass.input == .currentTarget {
            guard let consumingImage else {
                throw BatchRendererError(
                    operation: "Validate current-target image render pass", hresult: batchHresultInvalidArgument,
                    details: "A current-target source requires its consuming image occurrence.",
                    failureKind: .sceneContent)
            }
            parentBackdrop = try acquireBackBuffer()
            guard let parentBackdrop else {
                throw BatchRendererError(operation: "Resolve current-target parent", hresult: batchHresultHandle)
            }
            var descriptor = D3D11_TEXTURE2D_DESC()
            parentBackdrop.pointee.lpVtbl.pointee.GetDesc(parentBackdrop, &descriptor)
            guard descriptor.Width <= UINT(GPUISceneLimits.maxSurfaceDimension),
                descriptor.Height <= UINT(GPUISceneLimits.maxSurfaceDimension),
                let region = pass.currentTargetRegion(
                    for: consumingImage,
                    parentSize: IntSize(width: Int32(descriptor.Width), height: Int32(descriptor.Height)))
            else {
                throw BatchRendererError(
                    operation: "Validate current-target image render pass", hresult: batchHresultInvalidArgument,
                    details: "The image must map 1:1 from an even pixel origin wholly inside its actual parent target.",
                    failureKind: .sceneContent)
            }
            parentRegion = region
        }
        // Charge each realization, including repeated noncontiguous image
        // runs. This bounds nominal source payload, not driver or total GPU
        // memory; a filtered source also needs one same-size output target.
        guard imageRenderPassExecutionBudget.consume(pass) else {
            throw BatchRendererError(
                operation: "Execute image render pass", hresult: batchHresultInvalidArgument,
                details: "The frame exceeds the shared image-pass source-count or cumulative source-pixel budget.",
                failureKind: .sceneContent)
        }

        var target = try createImageRenderPassTarget(size: pass.size)
        var transfersTarget = false
        defer { if !transfersTarget { releaseImageRenderPassTarget(&target) } }

        if let parentRegion {
            guard let parentBackdrop, let texture = target.texture else {
                throw BatchRendererError(operation: "Copy current-target image source", hresult: batchHresultHandle)
            }
            // Admission happened before allocation. The copy fills the entire
            // separate child target: no clamping, padding or resampling can
            // invent pixels that a material might later include in its blur.
            var box = D3D11_BOX(
                left: UINT(parentRegion.originX), top: UINT(parentRegion.originY), front: 0,
                right: UINT(parentRegion.maxX), bottom: UINT(parentRegion.maxY), back: 1)
            let source = UnsafeMutableRawPointer(parentBackdrop).assumingMemoryBound(to: ID3D11Resource.self)
            let destination = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
            deviceContext.pointee.lpVtbl.pointee.CopySubresourceRegion(
                deviceContext, destination, 0, 0, 0, 0, source, 0, &box)
        }

        let parentTargetView = renderTargetView
        let parentTargetKind = renderTargetKind
        let parentOffscreenTexture = offscreenTexture
        let parentSize = targetPixelSize
        let parentBindings = imageBindings
        let parentGlyphAtlas = glyphAtlas
        let parentPixelGlyphAtlas = pixelGlyphAtlas
        let parentIsolation = backdropIsolation

        // Sharing is safe only when the atlas protocol says the child would
        // upload nothing. A different atlas gets a separate slot, so returning
        // from the child cannot silently change a later parent glyph run.
        let sharesGlyphAtlas =
            glyphAtlas.srv != nil
            && pass.scene.glyphAtlas?.uploadDecision(for: glyphAtlas.state) == .skip
        let sharesPixelGlyphAtlas =
            pixelGlyphAtlas.srv != nil
            && pass.scene.pixelGlyphAtlas?.uploadDecision(for: pixelGlyphAtlas.state) == .skip

        var parentStateRestored = false
        func restoreParentState() throws {
            guard !parentStateRestored else { return }
            if !sharesGlyphAtlas { glyphAtlas.release() }
            if !sharesPixelGlyphAtlas { pixelGlyphAtlas.release() }
            glyphAtlas = parentGlyphAtlas
            pixelGlyphAtlas = parentPixelGlyphAtlas
            imageBindings = parentBindings
            renderTargetView = parentTargetView
            renderTargetKind = parentTargetKind
            offscreenTexture = parentOffscreenTexture
            targetPixelSize = parentSize
            backdropIsolation = parentIsolation
            parentStateRestored = true
            defer { bindFramePipelineState(deviceContext: deviceContext, surfaceSize: parentSize) }
            // The same buffer object served the smaller target, so restoring
            // its binding alone is insufficient: restore its pixel dimensions.
            try updateFrameUniforms(surfaceSize: parentSize)
        }
        defer {
            // Preserve an existing child failure while unwinding. Successful
            // passes restore explicitly below so a restoration error propagates.
            if !parentStateRestored { try? restoreParentState() }
        }

        renderTargetView = target.view
        renderTargetKind = .offscreen
        offscreenTexture = target.texture
        targetPixelSize = pass.size
        // An independent child owns its own backdrop. In particular a Canvas
        // or color-filter source must never inherit a grandparent implicitly.
        backdropIsolation = nil
        imageBindings = Dictionary(
            pass.scene.imageResources.map { ($0.textureID, $0.bitmap) },
            uniquingKeysWith: { _, latest in latest })
        if !sharesGlyphAtlas { glyphAtlas = AtlasTextureSlot() }
        if !sharesPixelGlyphAtlas { pixelGlyphAtlas = AtlasTextureSlot() }

        var childScene = pass.scene
        childScene.finish()
        try validateBoundImageSampling(in: childScene)
        let plan = try Self.makeRenderPlan(for: childScene, cachedResources: cachedResourcesForTesting)
        bindFramePipelineState(deviceContext: deviceContext, surfaceSize: pass.size)
        try updateFrameUniforms(surfaceSize: pass.size)
        if parentRegion == nil {
            clearImageRenderPassTarget(target, color: childScene.clearColor, deviceContext: deviceContext)
        }
        try renderSceneContents(
            childScene, renderPlan: plan, deviceContext: deviceContext,
            surfaceSize: pass.size, imageRenderPassDepth: depth)

        if pass.colorEffects.isEmpty {
            try restoreParentState()
            transfersTarget = true
            return target
        }
        var filtered = try filterImageRenderPassTarget(
            target, size: pass.size, effects: pass.colorEffects, deviceContext: deviceContext)
        var transfersFilteredTarget = false
        defer { if !transfersFilteredTarget { releaseImageRenderPassTarget(&filtered) } }
        try restoreParentState()
        transfersFilteredTarget = true
        return filtered
    }

    /// Executes a transparent foreground/coverage pair while keeping the
    /// enclosing backdrop separate. Four full-size targets plus one local
    /// two-target blur engine are bounded by the shared eight-plane charge.
    private func renderIsolatedImageRenderPass(
        _ pass: GPUISceneImageRenderPass,
        consumingImage: ImagePrimitive,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        depth: Int
    ) throws -> IsolatedImageRenderPassResult {
        guard pass.hasValidExtent, depth <= GPUISceneLimits.maxImageRenderPassDepth else {
            throw BatchRendererError(
                operation: "Validate isolated-backdrop image pass", hresult: batchHresultInvalidArgument,
                details: "The isolated image exceeds the shared source extent or nesting limit.",
                failureKind: .sceneContent)
        }

        let parentIsolation = backdropIsolation
        var parentTexture: UnsafeMutablePointer<ID3D11Texture2D>? = try acquireBackBuffer()
        defer { releaseCOM(&parentTexture) }
        guard let actualParentTexture = parentTexture else {
            throw BatchRendererError(operation: "Resolve isolated-backdrop parent", hresult: batchHresultHandle)
        }
        var parentDescriptor = D3D11_TEXTURE2D_DESC()
        actualParentTexture.pointee.lpVtbl.pointee.GetDesc(actualParentTexture, &parentDescriptor)
        guard parentDescriptor.Width <= UINT(GPUISceneLimits.maxSurfaceDimension),
            parentDescriptor.Height <= UINT(GPUISceneLimits.maxSurfaceDimension),
            parentDescriptor.Format == DXGI_FORMAT_B8G8R8A8_UNORM,
            parentDescriptor.MipLevels == 1, parentDescriptor.ArraySize == 1,
            parentDescriptor.SampleDesc.Count == 1
        else {
            throw BatchRendererError(
                operation: "Validate isolated-backdrop parent", hresult: batchHresultInvalidArgument,
                details: "The actual parent must be a bounded single-sample BGRA8 surface.",
                failureKind: .sceneContent)
        }
        let actualParentSize = IntSize(
            width: Int32(parentDescriptor.Width), height: Int32(parentDescriptor.Height))
        var isolatedDescriptor = pass
        if pass.input == .currentTarget {
            // A plain group nested in F/C returns a pair too, but its original
            // fully-contained, even-origin contract is not broadened by that.
            guard parentIsolation != nil,
                pass.currentTargetRegion(for: consumingImage, parentSize: actualParentSize) != nil
            else {
                throw BatchRendererError(
                    operation: "Validate nested current-target image pass", hresult: batchHresultInvalidArgument,
                    details: "A nested current-target image must retain its original 1:1 contained mapping.",
                    failureKind: .sceneContent)
            }
            isolatedDescriptor.input = .isolatedBackdrop
            isolatedDescriptor.contentBlurRadius = 0
        }
        guard
            let mapping = isolatedDescriptor.isolatedBackdropMapping(
                for: consumingImage, parentSize: actualParentSize)
        else {
            throw BatchRendererError(
                operation: "Validate isolated-backdrop image pass", hresult: batchHresultInvalidArgument,
                details:
                    "The isolated source requires a transparent, unfiltered scene and an admitted 1:1 image mapping.",
                failureKind: .sceneContent)
        }
        // This is one atomic source-count and eight-plane pixel reservation,
        // performed before any child target or local blur engine is allocated.
        guard imageRenderPassExecutionBudget.consume(pass, inBackdropIsolation: parentIsolation != nil) else {
            throw BatchRendererError(
                operation: "Execute isolated-backdrop image pass", hresult: batchHresultInvalidArgument,
                details: "The frame exceeds the shared image-pass source-count or reserved-pixel budget.",
                failureKind: .sceneContent)
        }
        try ensureBackdropIsolationPipeline()

        if let parentIsolation {
            // S is fully defined across the immediate parent's own canvas.
            // Its D-only clamp has already been applied; do not carry a
            // narrower grandparent rectangle into this child's read policy.
            try composeIsolationBackdrop(parentIsolation, deviceContext: deviceContext)
            releaseCOM(&parentTexture)
            parentTexture = parentIsolation.composed.texture
            if let parentTexture { retainCOM(parentTexture) }
        }

        var foreground = try createImageRenderPassTarget(size: pass.size)
        var transfersPair = false
        defer { if !transfersPair { releaseImageRenderPassTarget(&foreground) } }
        var coverage = try createImageRenderPassTarget(size: pass.size)
        defer { if !transfersPair { releaseImageRenderPassTarget(&coverage) } }
        var backdrop = try createImageRenderPassTarget(size: pass.size)
        defer { releaseImageRenderPassTarget(&backdrop) }
        var composed = try createImageRenderPassTarget(size: pass.size)
        defer { releaseImageRenderPassTarget(&composed) }
        for target in [foreground, coverage, backdrop, composed] {
            clearImageRenderPassTarget(target, color: .clear, deviceContext: deviceContext)
        }

        if let copyRegion = mapping.parentCopyRegion {
            guard let sourceTexture = parentTexture, let destinationTexture = backdrop.texture else {
                throw BatchRendererError(operation: "Copy isolated-backdrop parent", hresult: batchHresultHandle)
            }
            var box = D3D11_BOX(
                left: UINT(copyRegion.originX), top: UINT(copyRegion.originY), front: 0,
                right: UINT(copyRegion.maxX), bottom: UINT(copyRegion.maxY), back: 1)
            let source = UnsafeMutableRawPointer(sourceTexture).assumingMemoryBound(to: ID3D11Resource.self)
            let destination = UnsafeMutableRawPointer(destinationTexture).assumingMemoryBound(to: ID3D11Resource.self)
            deviceContext.pointee.lpVtbl.pointee.CopySubresourceRegion(
                deviceContext, destination, 0, UINT(mapping.childOffsetX), UINT(mapping.childOffsetY), 0,
                source, 0, &box)
        }

        let isolation = BackdropIsolationState(
            foreground: foreground, coverage: coverage, backdrop: backdrop, composed: composed,
            size: pass.size, validBackdropRegion: mapping.validChildRegion)
        defer { isolation.blurEngine?.detach() }
        let parentTargetView = renderTargetView
        let parentTargetKind = renderTargetKind
        let parentOffscreenTexture = offscreenTexture
        let parentSize = targetPixelSize
        let parentBindings = imageBindings
        let parentGlyphAtlas = glyphAtlas
        let parentPixelGlyphAtlas = pixelGlyphAtlas
        let sharesGlyphAtlas =
            glyphAtlas.srv != nil
            && pass.scene.glyphAtlas?.uploadDecision(for: glyphAtlas.state) == .skip
        let sharesPixelGlyphAtlas =
            pixelGlyphAtlas.srv != nil
            && pass.scene.pixelGlyphAtlas?.uploadDecision(for: pixelGlyphAtlas.state) == .skip

        var parentStateRestored = false
        func restoreParentState() throws {
            guard !parentStateRestored else { return }
            if !sharesGlyphAtlas { glyphAtlas.release() }
            if !sharesPixelGlyphAtlas { pixelGlyphAtlas.release() }
            glyphAtlas = parentGlyphAtlas
            pixelGlyphAtlas = parentPixelGlyphAtlas
            imageBindings = parentBindings
            renderTargetView = parentTargetView
            renderTargetKind = parentTargetKind
            offscreenTexture = parentOffscreenTexture
            targetPixelSize = parentSize
            backdropIsolation = parentIsolation
            parentStateRestored = true
            unbindIsolationShaderResources(deviceContext: deviceContext)
            defer { bindFramePipelineState(deviceContext: deviceContext, surfaceSize: parentSize) }
            try updateFrameUniforms(surfaceSize: parentSize)
        }
        defer { if !parentStateRestored { try? restoreParentState() } }

        renderTargetView = foreground.view
        renderTargetKind = .offscreen
        offscreenTexture = foreground.texture
        targetPixelSize = pass.size
        backdropIsolation = isolation
        imageBindings = Dictionary(
            pass.scene.imageResources.map { ($0.textureID, $0.bitmap) },
            uniquingKeysWith: { _, latest in latest })
        if !sharesGlyphAtlas { glyphAtlas = AtlasTextureSlot() }
        if !sharesPixelGlyphAtlas { pixelGlyphAtlas = AtlasTextureSlot() }

        var childScene = pass.scene
        childScene.finish()
        try validateBoundImageSampling(in: childScene)
        let plan = try Self.makeRenderPlan(for: childScene, cachedResources: cachedResourcesForTesting)
        bindFramePipelineState(deviceContext: deviceContext, surfaceSize: pass.size)
        try updateFrameUniforms(surfaceSize: pass.size)
        try renderSceneContents(
            childScene, renderPlan: plan, deviceContext: deviceContext,
            surfaceSize: pass.size, imageRenderPassDepth: depth)

        if isolatedDescriptor.contentBlurRadius > 0 {
            let engine = try ensureIsolatedBlurEngine(isolation)
            let targetDescriptor = currentRenderTargetDescriptor
            guard let foregroundTexture = foreground.texture, let foregroundView = foreground.view,
                let coverageTexture = coverage.texture, let coverageView = coverage.view
            else {
                throw BatchRendererError(operation: "Filter isolated image pair", hresult: batchHresultHandle)
            }
            try engine.filterTextureInPlace(
                deviceContext: deviceContext, texture: foregroundTexture, renderTargetView: foregroundView,
                target: targetDescriptor, radius: Int(isolatedDescriptor.contentBlurRadius))
            if failIsolatedCoverageForTesting {
                throw BatchRendererError(
                    operation: "Filter isolated coverage", hresult: batchHresultOutOfMemory,
                    details: "Injected failure after filtering isolated foreground (test seam).")
            }
            try engine.filterTextureInPlace(
                deviceContext: deviceContext, texture: coverageTexture, renderTargetView: coverageView,
                target: targetDescriptor, radius: Int(isolatedDescriptor.contentBlurRadius))
        }
        try restoreParentState()
        transfersPair = true
        return IsolatedImageRenderPassResult(foreground: foreground, coverage: coverage)
    }

    private func createImageRenderPassTarget(size: IntSize) throws -> ImageRenderPassTarget {
        guard let device else {
            throw BatchRendererError(operation: "Create image render pass target", hresult: batchHresultHandle)
        }
        guard size.width > 0, size.height > 0,
            Int(size.width) <= GPUISceneLimits.maxSurfaceDimension,
            Int(size.height) <= GPUISceneLimits.maxSurfaceDimension,
            Int64(size.width) * Int64(size.height) <= Int64(GPUISceneLimits.maxImageRenderPassPixels)
        else {
            throw BatchRendererError(
                operation: "Create image render pass target", hresult: batchHresultInvalidArgument,
                details: "The scratch target exceeds the shared image-pass extent limit.",
                failureKind: .sceneContent)
        }

        var target = ImageRenderPassTarget()
        target.countedOwner = true
        directlyOwnedImagePassTargetCount += 1
        var transfersTarget = false
        defer { if !transfersTarget { releaseImageRenderPassTarget(&target) } }

        var descriptor = D3D11_TEXTURE2D_DESC()
        descriptor.Width = UINT(size.width)
        descriptor.Height = UINT(size.height)
        descriptor.MipLevels = 1
        descriptor.ArraySize = 1
        descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_RENDER_TARGET.rawValue | D3D11_BIND_SHADER_RESOURCE.rawValue)

        let textureHR = makeCOM(into: &target.texture) { texture in
            device.pointee.lpVtbl.pointee.CreateTexture2D(device, &descriptor, nil, &texture)
        }
        try throwIfFailed(textureHR, operation: "ID3D11Device.CreateTexture2D(image pass)")
        guard let texture = target.texture else {
            throw BatchRendererError(operation: "CreateTexture2D(image pass)", hresult: batchHresultHandle)
        }
        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        let viewHR = makeCOM(into: &target.view) { view in
            device.pointee.lpVtbl.pointee.CreateRenderTargetView(device, resource, nil, &view)
        }
        try throwIfFailed(viewHR, operation: "ID3D11Device.CreateRenderTargetView(image pass)")
        let srvHR = makeCOM(into: &target.srv) { srv in
            device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, nil, &srv)
        }
        try throwIfFailed(srvHR, operation: "ID3D11Device.CreateShaderResourceView(image pass)")
        transfersTarget = true
        return target
    }

    private func releaseImageRenderPassTarget(_ target: inout ImageRenderPassTarget) {
        target.release()
        if target.countedOwner {
            target.countedOwner = false
            directlyOwnedImagePassTargetCount -= 1
        }
    }

    private func clearImageRenderPassTarget(
        _ target: ImageRenderPassTarget,
        color: Color,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>
    ) {
        let values: [FLOAT] = [
            color.red * color.alpha, color.green * color.alpha, color.blue * color.alpha, color.alpha,
        ]
        values.withUnsafeBufferPointer { buffer in
            deviceContext.pointee.lpVtbl.pointee.ClearRenderTargetView(
                deviceContext, target.view, buffer.baseAddress)
        }
    }

    /// Filtering at 1:1 keeps per-effect clamping ahead of image interpolation,
    /// matching the CPU reference when the final image is scaled or rotated.
    private func filterImageRenderPassTarget(
        _ source: ImageRenderPassTarget,
        size: IntSize,
        effects: [SceneColorEffect],
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>
    ) throws -> ImageRenderPassTarget {
        try ensureImageColorEffectPipeline()
        guard let sourceSRV = source.srv, let imageColorEffectPS, let colorEffectUniformBuffer else {
            throw BatchRendererError(operation: "Resolve image color-effect pipeline", hresult: batchHresultHandle)
        }
        var target = try createImageRenderPassTarget(size: size)
        var transfersTarget = false
        defer { if !transfersTarget { releaseImageRenderPassTarget(&target) } }

        // renderImageRenderPass's defer restores the enclosing scene after
        // this filter, including when a buffer upload or draw throws.
        renderTargetView = target.view
        offscreenTexture = target.texture
        bindFramePipelineState(deviceContext: deviceContext, surfaceSize: size)
        clearImageRenderPassTarget(target, color: .clear, deviceContext: deviceContext)

        var uniforms = [Float](repeating: 0, count: Self.colorEffectUniformFloatCount)
        uniforms[0] = Float(effects.count)
        for (index, effect) in effects.enumerated() {
            let offset = 4 + index * 8
            switch effect.sanitized {
            case .brightness(let amount):
                uniforms[offset] = 1
                uniforms[offset + 1] = Float(amount)
            case .contrast(let amount):
                uniforms[offset] = 2
                uniforms[offset + 1] = Float(amount)
            case .saturation(let amount):
                uniforms[offset] = 3
                uniforms[offset + 1] = Float(amount)
            case .grayscale(let amount):
                uniforms[offset] = 4
                uniforms[offset + 1] = Float(amount)
            case .colorInvert:
                uniforms[offset] = 5
            case .hueRotation(let angle):
                uniforms[offset] = 6
                uniforms[offset + 2] = Float(angle)
            case .colorMultiply(let color):
                uniforms[offset] = 7
                uniforms[offset + 2] = color.red
                uniforms[offset + 3] = color.green
                uniforms[offset + 4] = color.blue
                uniforms[offset + 5] = color.alpha
            case .luminanceToAlpha:
                uniforms[offset] = 8
            }
        }
        let bufferResource = UnsafeMutableRawPointer(colorEffectUniformBuffer).assumingMemoryBound(
            to: ID3D11Resource.self)
        uniforms.withUnsafeBytes { bytes in
            deviceContext.pointee.lpVtbl.pointee.UpdateSubresource(
                deviceContext, bufferResource, 0, nil, bytes.baseAddress, 0, 0)
        }
        var constantBuffer: UnsafeMutablePointer<ID3D11Buffer>? = colorEffectUniformBuffer
        deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 1, 1, &constantBuffer)
        defer {
            var nullBuffer: UnsafeMutablePointer<ID3D11Buffer>? = nil
            deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 1, 1, &nullBuffer)
        }

        let image = ImagePrimitive(screenW: Float(size.width), screenH: Float(size.height))
        try renderImageBatch(
            [image], range: 0..<1, deviceContext: deviceContext, textureSRV: sourceSRV,
            pixelShader: imageColorEffectPS)
        transfersTarget = true
        return target
    }

    private func ensureImageColorEffectPipeline() throws {
        if imageColorEffectPS != nil, colorEffectUniformBuffer != nil { return }
        guard let device else {
            throw BatchRendererError(operation: "Create image color-effect pipeline", hresult: batchHresultHandle)
        }

        var shaderBlob: UnsafeMutablePointer<ID3DBlob>? = try Self.compileShaderSource(
            source: batchImageColorEffectShaderSource, entryPoint: "psMain", profile: "ps_5_0")
        defer { releaseCOM(&shaderBlob) }
        guard let shaderBlob else {
            throw BatchRendererError(operation: "Compile image color-effect shader", hresult: batchHresultHandle)
        }

        var shader: UnsafeMutablePointer<ID3D11PixelShader>?
        var buffer: UnsafeMutablePointer<ID3D11Buffer>?
        defer {
            releaseCOM(&shader)
            releaseCOM(&buffer)
        }
        let shaderHR = makeCOM(into: &shader) { value in
            device.pointee.lpVtbl.pointee.CreatePixelShader(
                device, shaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(shaderBlob),
                SIZE_T(shaderBlob.pointee.lpVtbl.pointee.GetBufferSize(shaderBlob)), nil, &value)
        }
        try throwIfFailed(shaderHR, operation: "ID3D11Device.CreatePixelShader(image color effects)")
        var descriptor = D3D11_BUFFER_DESC()
        descriptor.ByteWidth = UINT(Self.colorEffectUniformFloatCount * MemoryLayout<Float>.stride)
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)
        let bufferHR = makeCOM(into: &buffer) { value in
            device.pointee.lpVtbl.pointee.CreateBuffer(device, &descriptor, nil, &value)
        }
        try throwIfFailed(bufferHR, operation: "ID3D11Device.CreateBuffer(image color effects)")
        releaseCOM(&imageColorEffectPS)
        releaseCOM(&colorEffectUniformBuffer)
        imageColorEffectPS = shader
        colorEffectUniformBuffer = buffer
        shader = nil
        buffer = nil
    }

    private func renderSeparableBlendQuad(
        _ quads: [QuadPrimitive], index: Int, mode: BlendMode,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>, surfaceSize: IntSize
    ) throws {
        guard let region = Self.separableBlendDestinationRegion(quads[index], surfaceSize: surfaceSize) else {
            return
        }
        guard let device else {
            throw BatchRendererError(operation: "Resolve separable blend device", hresult: batchHresultHandle)
        }
        defer {
            var noResource: UnsafeMutablePointer<ID3D11ShaderResourceView>?
            deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &noResource)
            deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &noResource)
            var noConstants: UnsafeMutablePointer<ID3D11Buffer>?
            deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 2, 1, &noConstants)
            bindFramePipelineState(deviceContext: deviceContext, surfaceSize: surfaceSize)
        }
        try ensureSeparableBlendPipeline()
        guard let separableBlendQuadPS, let separableBlendUniformBuffer else {
            throw BatchRendererError(operation: "Resolve separable blend pipeline", hresult: batchHresultHandle)
        }

        // No destination remains bound for reading when the allocation is
        // copied again. Immediate-context ordering preserves earlier reads
        // before the next write; the pixels themselves are never cached.
        var noDestination: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &noDestination)
        let destinationSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>
        let destinationRegion: SubTextureRegion
        if let isolation = backdropIsolation {
            guard let texture = isolation.composed.texture, let view = isolation.composed.srv else {
                throw BatchRendererError(operation: "Resolve isolated blend destination", hresult: batchHresultHandle)
            }
            destinationRegion = SubTextureRegion(
                textureWidth: Int(surfaceSize.width), textureHeight: Int(surfaceSize.height))
            try D3D11BlendDestinationSnapshot.validateSource(texture, region: destinationRegion)
            // This existing scratch texture contains F + (1-K)B. Blending
            // against F alone would lose the frozen group's visible backdrop.
            try composeIsolationBackdrop(isolation, deviceContext: deviceContext)
            destinationSRV = view
        } else {
            var sourceOwner: UnsafeMutablePointer<ID3D11Texture2D>? = try acquireBackBuffer()
            defer { releaseCOM(&sourceOwner) }
            guard let source = sourceOwner else {
                throw BatchRendererError(operation: "Resolve blend destination target", hresult: batchHresultHandle)
            }
            try D3D11BlendDestinationSnapshot.validateSource(source, region: region)
            if separableBlendDestinationSnapshot == nil
                || region.width > (separableBlendDestinationSnapshot?.capacityWidth ?? 0)
                || region.height > (separableBlendDestinationSnapshot?.capacityHeight ?? 0)
            {
                var descriptor = D3D11_TEXTURE2D_DESC()
                source.pointee.lpVtbl.pointee.GetDesc(source, &descriptor)
                let fullTarget = SubTextureRegion(
                    textureWidth: Int(descriptor.Width), textureHeight: Int(descriptor.Height))
                // Allocate once for an actual target, not once per quad size.
                // The initializer also copies that full target on first use;
                // every draw below then recopies only its conservative region.
                let replacement = try D3D11BlendDestinationSnapshot(
                    device: device, context: deviceContext, source: source, region: fullTarget)
                separableBlendDestinationSnapshot?.release()
                separableBlendDestinationSnapshot = replacement
            }
            guard let snapshot = separableBlendDestinationSnapshot, let view = snapshot.srv else {
                throw BatchRendererError(operation: "Resolve blend destination snapshot", hresult: batchHresultHandle)
            }
            try snapshot.capture(context: deviceContext, source: source, region: region)
            destinationSRV = view
            destinationRegion = snapshot.region
        }

        var uniforms = D3D11SeparableBlendUniforms(region: destinationRegion, mode: mode)
        let uniformResource = UnsafeMutableRawPointer(separableBlendUniformBuffer)
            .assumingMemoryBound(to: ID3D11Resource.self)
        withUnsafeBytes(of: &uniforms) { bytes in
            deviceContext.pointee.lpVtbl.pointee.UpdateSubresource(
                deviceContext, uniformResource, 0, nil, bytes.baseAddress, 0, 0)
        }
        var constants: UnsafeMutablePointer<ID3D11Buffer>? = separableBlendUniformBuffer
        deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 2, 1, &constants)
        var destination: UnsafeMutablePointer<ID3D11ShaderResourceView>? = destinationSRV
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &destination)
        if failSeparableBlendAfterDestinationBindingForTesting {
            throw BatchRendererError(
                operation: "Draw separable blend quad", hresult: batchHresultOutOfMemory,
                details: "Injected failure after the destination and uniforms were bound.")
        }
        // The shader emits adjusted source Q, whose alpha is still source
        // coverage. Normal ONE/INV_SRC_ALPHA and the existing alpha-only
        // isolated coverage draw therefore remain the correct blend states.
        try renderBatch(
            quads, range: index..<(index + 1), capacity: &quadInstanceCapacity,
            buffer: &quadInstanceBuffer, srv: &quadInstanceSRV, vs: quadVS, ps: separableBlendQuadPS,
            label: "quad", deviceContext: deviceContext)
    }

    /// The result already contains its parent backdrop. Retain destination
    /// coverage, not (1 - result alpha), including on translucent targets.
    private func renderCurrentTargetImage(
        _ images: [ImagePrimitive], index: Int,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        textureSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>, surfaceSize: IntSize
    ) throws {
        defer { bindFramePipelineState(deviceContext: deviceContext, surfaceSize: surfaceSize) }
        try ensureImageReplacementPipeline()
        guard let imageReplacementPS, let imageReplacementBlendState else {
            throw BatchRendererError(operation: "Resolve image replacement pipeline", hresult: batchHresultHandle)
        }
        let blendFactor: [FLOAT] = [0, 0, 0, 0]
        blendFactor.withUnsafeBufferPointer { factor in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(
                deviceContext, imageReplacementBlendState, factor.baseAddress, UINT.max)
        }
        try renderImageBatch(
            images, range: index..<(index + 1), deviceContext: deviceContext, textureSRV: textureSRV,
            pixelShader: imageReplacementPS)
    }

    private func ensureImageReplacementPipeline() throws {
        if imageReplacementPS != nil, imageReplacementBlendState != nil { return }
        guard let device else {
            throw BatchRendererError(operation: "Create image replacement pipeline", hresult: batchHresultHandle)
        }
        var shaderBlob: UnsafeMutablePointer<ID3DBlob>? = try Self.compileShaderSource(
            source: batchImageReplacementShaderSource, entryPoint: "psMain", profile: "ps_5_0")
        defer { releaseCOM(&shaderBlob) }
        guard let shaderBlob else {
            throw BatchRendererError(operation: "Compile image replacement shader", hresult: batchHresultHandle)
        }

        var shader: UnsafeMutablePointer<ID3D11PixelShader>?
        var replacementBlend: UnsafeMutablePointer<ID3D11BlendState>?
        defer {
            releaseCOM(&shader)
            releaseCOM(&replacementBlend)
        }
        let shaderHR = makeCOM(into: &shader) { value in
            device.pointee.lpVtbl.pointee.CreatePixelShader(
                device, shaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(shaderBlob),
                SIZE_T(shaderBlob.pointee.lpVtbl.pointee.GetBufferSize(shaderBlob)), nil, &value)
        }
        try throwIfFailed(shaderHR, operation: "ID3D11Device.CreatePixelShader(image replacement)")
        var descriptor = D3D11_BLEND_DESC()
        descriptor.AlphaToCoverageEnable = false
        descriptor.IndependentBlendEnable = false
        descriptor.RenderTarget.0.BlendEnable = true
        descriptor.RenderTarget.0.SrcBlend = D3D11_BLEND_ONE
        descriptor.RenderTarget.0.DestBlend = D3D11_BLEND_INV_SRC1_ALPHA
        descriptor.RenderTarget.0.BlendOp = D3D11_BLEND_OP_ADD
        descriptor.RenderTarget.0.SrcBlendAlpha = D3D11_BLEND_ONE
        descriptor.RenderTarget.0.DestBlendAlpha = D3D11_BLEND_INV_SRC1_ALPHA
        descriptor.RenderTarget.0.BlendOpAlpha = D3D11_BLEND_OP_ADD
        descriptor.RenderTarget.0.RenderTargetWriteMask = UINT8(D3D11_COLOR_WRITE_ENABLE_ALL.rawValue)
        let blendHR = makeCOM(into: &replacementBlend) { value in
            device.pointee.lpVtbl.pointee.CreateBlendState(device, &descriptor, &value)
        }
        try throwIfFailed(blendHR, operation: "ID3D11Device.CreateBlendState(image replacement)")
        releaseCOM(&imageReplacementPS)
        releaseCOM(&imageReplacementBlendState)
        imageReplacementPS = shader
        imageReplacementBlendState = replacementBlend
        shader = nil
        replacementBlend = nil
    }

    /// Lazy resources belong to the renderer/device; pixels belong only to
    /// the current isolation. Ordinary image and material pipelines are not
    /// changed by enabling this path.
    private func ensureBackdropIsolationPipeline() throws {
        if imageIsolatedReplacementPS != nil, imageIsolatedCoveragePS != nil,
            isolatedBackdropComposeVS != nil, isolatedBackdropComposePS != nil,
            isolatedCoverageBlendState != nil, isolatedBackdropBoundsBuffer != nil
        {
            return
        }
        try ensureImageReplacementPipeline()
        guard let device else {
            throw BatchRendererError(operation: "Create backdrop-isolation pipeline", hresult: batchHresultHandle)
        }
        var replacementPS: UnsafeMutablePointer<ID3D11PixelShader>?
        var coveragePS: UnsafeMutablePointer<ID3D11PixelShader>?
        var unusedImageVS: UnsafeMutablePointer<ID3D11VertexShader>?
        var composeVS: UnsafeMutablePointer<ID3D11VertexShader>?
        var composePS: UnsafeMutablePointer<ID3D11PixelShader>?
        var coverageBlend: UnsafeMutablePointer<ID3D11BlendState>?
        var boundsBuffer: UnsafeMutablePointer<ID3D11Buffer>?
        defer {
            releaseCOM(&replacementPS)
            releaseCOM(&coveragePS)
            releaseCOM(&unusedImageVS)
            releaseCOM(&composeVS)
            releaseCOM(&composePS)
            releaseCOM(&coverageBlend)
            releaseCOM(&boundsBuffer)
        }
        try createShaderPair(
            device: device, source: batchImageIsolatedReplacementShaderSource,
            vs: &unusedImageVS, ps: &replacementPS, label: "isolated image replacement")
        releaseCOM(&unusedImageVS)
        try createShaderPair(
            device: device, source: batchImageIsolatedCoverageShaderSource,
            vs: &unusedImageVS, ps: &coveragePS, label: "isolated image coverage")
        try createShaderPair(
            device: device, source: batchIsolatedBackdropComposeShaderSource,
            vs: &composeVS, ps: &composePS, label: "isolated backdrop composition")

        var descriptor = D3D11_BLEND_DESC()
        descriptor.AlphaToCoverageEnable = false
        descriptor.IndependentBlendEnable = false
        descriptor.RenderTarget.0.BlendEnable = true
        descriptor.RenderTarget.0.SrcBlend = D3D11_BLEND_ONE
        descriptor.RenderTarget.0.DestBlend = D3D11_BLEND_INV_SRC_ALPHA
        descriptor.RenderTarget.0.BlendOp = D3D11_BLEND_OP_ADD
        descriptor.RenderTarget.0.SrcBlendAlpha = D3D11_BLEND_ONE
        descriptor.RenderTarget.0.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA
        descriptor.RenderTarget.0.BlendOpAlpha = D3D11_BLEND_OP_ADD
        descriptor.RenderTarget.0.RenderTargetWriteMask = UINT8(D3D11_COLOR_WRITE_ENABLE_ALPHA.rawValue)
        let blendHR = makeCOM(into: &coverageBlend) { value in
            device.pointee.lpVtbl.pointee.CreateBlendState(device, &descriptor, &value)
        }
        try throwIfFailed(blendHR, operation: "ID3D11Device.CreateBlendState(isolated coverage)")
        var bufferDescriptor = D3D11_BUFFER_DESC()
        bufferDescriptor.ByteWidth = 16
        bufferDescriptor.Usage = D3D11_USAGE_DEFAULT
        bufferDescriptor.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)
        let bufferHR = makeCOM(into: &boundsBuffer) { value in
            device.pointee.lpVtbl.pointee.CreateBuffer(device, &bufferDescriptor, nil, &value)
        }
        try throwIfFailed(bufferHR, operation: "ID3D11Device.CreateBuffer(isolated backdrop bounds)")

        releaseCOM(&imageIsolatedReplacementPS)
        releaseCOM(&imageIsolatedCoveragePS)
        releaseCOM(&isolatedBackdropComposeVS)
        releaseCOM(&isolatedBackdropComposePS)
        releaseCOM(&isolatedCoverageBlendState)
        releaseCOM(&isolatedBackdropBoundsBuffer)
        imageIsolatedReplacementPS = replacementPS
        imageIsolatedCoveragePS = coveragePS
        isolatedBackdropComposeVS = composeVS
        isolatedBackdropComposePS = composePS
        isolatedCoverageBlendState = coverageBlend
        isolatedBackdropBoundsBuffer = boundsBuffer
        replacementPS = nil
        coveragePS = nil
        composeVS = nil
        composePS = nil
        coverageBlend = nil
        boundsBuffer = nil
    }

    private func ensureIsolatedBlurEngine(_ isolation: BackdropIsolationState) throws -> D3D11BackdropBlurEngine {
        if let engine = isolation.blurEngine { return engine }
        guard let device else {
            throw BatchRendererError(operation: "Create isolated blur engine", hresult: batchHresultHandle)
        }
        if isolatedBlurPipeline?.matches(deviceGeneration: deviceGeneration) != true {
            isolatedBlurPipeline?.detach()
            isolatedBlurPipeline = nil
            let pipeline = D3D11BackdropBlurEngine()
            do {
                try pipeline.attach(device: device, generation: deviceGeneration)
                try pipeline.prepareIsolatedPipeline()
            } catch {
                pipeline.detach()
                throw error
            }
            isolatedBlurPipeline = pipeline
            isolatedBlurPipelineCreationCountForTesting &+= 1
        }
        guard let pipeline = isolatedBlurPipeline else {
            throw BatchRendererError(operation: "Resolve isolated blur pipeline", hresult: batchHresultHandle)
        }
        let engine = try pipeline.makeIsolatedScratchEngine()
        isolation.blurEngine = engine
        return engine
    }

    private func unbindIsolationShaderResources(deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>) {
        var resources: [UnsafeMutablePointer<ID3D11ShaderResourceView>?] = [nil, nil, nil]
        resources.withUnsafeMutableBufferPointer { values in
            deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 0, 3, values.baseAddress)
        }
        var noInstance: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &noInstance)
        var constants: [UnsafeMutablePointer<ID3D11Buffer>?] = [nil, nil]
        constants.withUnsafeMutableBufferPointer { values in
            deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 0, 2, values.baseAddress)
        }
    }

    /// Produces a material read source without importing backdrop pixels into
    /// F or C. Only D is clamped at a cropped viewport boundary; all local
    /// foreground and coverage in the transparent filter halo remain intact.
    private func composeIsolationBackdrop(
        _ isolation: BackdropIsolationState,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>
    ) throws {
        guard let composeVS = isolatedBackdropComposeVS, let composePS = isolatedBackdropComposePS,
            let boundsBuffer = isolatedBackdropBoundsBuffer, let targetView = isolation.composed.view,
            let foregroundSRV = isolation.foreground.srv, let coverageSRV = isolation.coverage.srv,
            let backdropSRV = isolation.backdrop.srv
        else {
            throw BatchRendererError(operation: "Compose isolated backdrop", hresult: batchHresultHandle)
        }
        defer {
            unbindIsolationShaderResources(deviceContext: deviceContext)
            bindFramePipelineState(deviceContext: deviceContext, surfaceSize: isolation.size)
        }
        unbindIsolationShaderResources(deviceContext: deviceContext)
        var view: UnsafeMutablePointer<ID3D11RenderTargetView>? = targetView
        deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &view, nil)
        let factors: [FLOAT] = [0, 0, 0, 0]
        factors.withUnsafeBufferPointer { values in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(
                deviceContext, nil, values.baseAddress, UINT.max)
        }
        var viewport = D3D11_VIEWPORT(
            TopLeftX: 0, TopLeftY: 0,
            Width: FLOAT(isolation.size.width), Height: FLOAT(isolation.size.height),
            MinDepth: 0, MaxDepth: 1)
        deviceContext.pointee.lpVtbl.pointee.RSSetViewports(deviceContext, 1, &viewport)
        deviceContext.pointee.lpVtbl.pointee.RSSetState(deviceContext, rasterizerState)
        deviceContext.pointee.lpVtbl.pointee.IASetInputLayout(deviceContext, nil)
        deviceContext.pointee.lpVtbl.pointee.IASetPrimitiveTopology(
            deviceContext, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST)
        let bounds: [Int32]
        if let valid = isolation.validBackdropRegion {
            bounds = [Int32(valid.originX), Int32(valid.originY), Int32(valid.maxX), Int32(valid.maxY)]
        } else {
            bounds = [0, 0, 0, 0]
        }
        let resource = UnsafeMutableRawPointer(boundsBuffer).assumingMemoryBound(to: ID3D11Resource.self)
        bounds.withUnsafeBytes { bytes in
            deviceContext.pointee.lpVtbl.pointee.UpdateSubresource(
                deviceContext, resource, 0, nil, bytes.baseAddress, 0, 0)
        }
        var constants: UnsafeMutablePointer<ID3D11Buffer>? = boundsBuffer
        deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 0, 1, &constants)
        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, composeVS, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, composePS, nil, 0)
        var inputs: [UnsafeMutablePointer<ID3D11ShaderResourceView>?] = [foregroundSRV, coverageSRV, backdropSRV]
        inputs.withUnsafeMutableBufferPointer { values in
            deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 0, 3, values.baseAddress)
        }
        noteDrawCall(instanceCount: 1)
        deviceContext.pointee.lpVtbl.pointee.Draw(deviceContext, 3, 0)
    }

    /// A pair composites with coverage, not foreground alpha. A parent pair
    /// receives the same coverage through a second, alpha-only image draw.
    private func renderIsolatedImage(
        _ images: [ImagePrimitive], index: Int, result: IsolatedImageRenderPassResult,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>, surfaceSize: IntSize
    ) throws {
        defer {
            unbindIsolationShaderResources(deviceContext: deviceContext)
            bindFramePipelineState(deviceContext: deviceContext, surfaceSize: surfaceSize)
        }
        guard let replacementPS = imageIsolatedReplacementPS, let coveragePS = imageIsolatedCoveragePS,
            let replacementBlend = imageReplacementBlendState, let coverageBlend = isolatedCoverageBlendState,
            let foregroundSRV = result.foreground.srv, let coverageSRV = result.coverage.srv
        else {
            throw BatchRendererError(operation: "Composite isolated image pair", hresult: batchHresultHandle)
        }
        let factors: [FLOAT] = [0, 0, 0, 0]
        factors.withUnsafeBufferPointer { values in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(
                deviceContext, replacementBlend, values.baseAddress, UINT.max)
        }
        var coverageInput: UnsafeMutablePointer<ID3D11ShaderResourceView>? = coverageSRV
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 2, 1, &coverageInput)
        try renderImageBatch(
            images, range: index..<(index + 1), deviceContext: deviceContext, textureSRV: foregroundSRV,
            pixelShader: replacementPS, mirrorsIsolationCoverage: false)

        if let isolation = backdropIsolation {
            var view = isolation.coverage.view
            deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &view, nil)
            factors.withUnsafeBufferPointer { values in
                deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(
                    deviceContext, coverageBlend, values.baseAddress, UINT.max)
            }
            try renderImageBatch(
                images, range: index..<(index + 1), deviceContext: deviceContext, textureSRV: coverageSRV,
                pixelShader: coveragePS, mirrorsIsolationCoverage: false)
        }
    }

    /// Repeat only the prepared GPU draw, not source resolution or path
    /// rasterization. Every ordinary family's alpha is its coverage, so the
    /// exact same PS, sampler and resources produce C with alpha-only writes.
    private func drawPreparedInstances(
        instanceCount: Int,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        mirrorsIsolationCoverage: Bool = true
    ) throws {
        noteDrawCall(instanceCount: instanceCount)
        deviceContext.pointee.lpVtbl.pointee.DrawInstanced(deviceContext, 6, UINT(instanceCount), 0, 0)
        guard mirrorsIsolationCoverage, let isolation = backdropIsolation else { return }
        guard let coverageBlend = isolatedCoverageBlendState, let coverageView = isolation.coverage.view else {
            throw BatchRendererError(operation: "Accumulate isolated coverage", hresult: batchHresultHandle)
        }
        defer { bindFramePipelineState(deviceContext: deviceContext, surfaceSize: isolation.size) }
        var view: UnsafeMutablePointer<ID3D11RenderTargetView>? = coverageView
        deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &view, nil)
        let factors: [FLOAT] = [0, 0, 0, 0]
        factors.withUnsafeBufferPointer { values in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(
                deviceContext, coverageBlend, values.baseAddress, UINT.max)
        }
        noteDrawCall(instanceCount: instanceCount)
        deviceContext.pointee.lpVtbl.pointee.DrawInstanced(deviceContext, 6, UINT(instanceCount), 0, 0)
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

    // Only the native presenter opts in. The compatibility facade leaves this
    // nil and performs no sampling or recorder updates. No COM owner is stored
    // in either the immutable request context or the independent lifetime token.
    func beginDisplayAcquisition(_ context: NativeDisplayAcquisition.Context) -> Bool {
        guard displayAcquisition == nil else {
            context.invalidate(.scopeMismatch)
            return false
        }
        guard context.beginScope() else { return false }
        displayAcquisition = context
        displayAcquisitionRendered = false
        return true
    }

    func endDisplayAcquisition(_ context: NativeDisplayAcquisition.Context) {
        guard let current = displayAcquisition, current.matches(context) else {
            context.invalidate(.scopeMismatch)
            return
        }
        if displayAcquisitionRendered { context.recordSubmission(lastFrameSubmission) }
        displayAcquisition = nil
        displayAcquisitionRendered = false
        context.endScope()
    }

    func displayAcquisitionWillRender() {
        guard let displayAcquisition else { return }
        displayAcquisitionRendered = true
        displayAcquisition.invokedRenderer()
    }

    func invalidateDisplayAcquisition(_ fault: NativeDisplayAcquisition.Fault) {
        displayAcquisition?.invalidate(fault)
    }

    func rebindDisplayAcquisitionSurface() {
        // This is the successful attachment-lease boundary, not a new COM
        // allocation. Keep the old lifetime token if the bounded recorder fails.
        if let displayAcquisition, let old = displayAcquisitionEpoch,
            let updated = old.rebound(to: displayAcquisition)
        {
            displayAcquisitionEpoch = updated
        }
    }

    /// Ends the frame on whichever target is attached: a real DXGI present
    /// for the windowed swap chain, a context flush for the offscreen
    /// target (which has nothing to present, but must have its draws
    /// submitted before anything reads the texture back).
    private func presentFrame(frameID: BackendFrameID) throws {
        switch renderTargetKind {
        case .swapChain:
            guard let swapChain else {
                return
            }
            // `sync = 0` here is a queued present, not a torn one: this chain
            // is `FLIP_DISCARD` without `ALLOW_TEARING`, so DWM still shows
            // whole frames — the call simply stops blocking on a compositor
            // that was never going to release it on time.
            let syncInterval: UINT = presentPacingPolicy.presentsOnVBlank ? 1 : 0
            let ticket = displayAcquisition?.preparePresent(
                epoch: displayAcquisitionEpoch, frame: frameID, address: UInt64(UInt(bitPattern: swapChain)),
                syncInterval: syncInterval, flags: 0)
            let acquisitionBegan = ticket?.sample()
            let hr = swapChain.pointee.lpVtbl.pointee.Present(swapChain, syncInterval, 0)
            let acquisitionEnded = ticket?.sample()
            ticket?.returned(hr, began: acquisitionBegan, ended: acquisitionEnded)
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
        if strictWARPForTesting {
            detach()
            throw BatchRendererError(
                operation: operation, hresult: hresult,
                details: "Strict WARP test device loss requires a new explicit attachment.",
                failureKind: .deviceLost)
        }
        gpuFrameTimingCollector?.detach(status: .deviceLost)
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

    /// The surface this renderer is currently drawing into, as the shared
    /// render-pass value. One statement of "what and how big", read by the
    /// backdrop blur engine instead of each caller passing its own idea of
    /// the surface size. The engine was already told the same *size* before
    /// this existed — what is new is that the kind travels with it and that
    /// there is one place to read it from.
    ///
    /// `clearColor` is nil — a frame's draws composite over what the clear
    /// already put there; the clear itself is not a pass in this model.
    internal var currentRenderTargetDescriptor: RenderTargetDescriptor {
        RenderTargetDescriptor(
            kind: renderTargetKind == .offscreen ? .offscreen : .presentation,
            width: Int(targetPixelSize.width),
            height: Int(targetPixelSize.height))
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
    ///
    /// Internal for the same reason as `attachOffscreen(size:driver:)`: it
    /// reads a target only a test can create.
    internal func readOffscreenPixels() throws -> BitmapSurface {
        guard renderTargetKind == .offscreen, let offscreenTexture else {
            throw BatchRendererError(
                operation: "Read offscreen pixels",
                hresult: batchHresultInvalidArgument,
                details: "The renderer is not attached to an offscreen render target."
            )
        }
        return try readPixels(of: offscreenTexture, operation: "Read offscreen pixels")
    }

    /// Copies the frame the swap chain is about to present into a
    /// `BitmapSurface`, so a diagnostics run can look at the pixels that go
    /// to the screen.
    ///
    /// Taken *before* `Present`, and that is not an optimisation: this chain
    /// is `FLIP_DISCARD`, where the back buffer's contents are undefined the
    /// moment the present is queued. A capture taken afterwards reads
    /// whatever the driver left behind, which on this machine is often the
    /// previous frame — the exact failure mode that would make a stuttering
    /// animation look smooth in the capture.
    private func capturePresentedFrameIfRequested() {
        guard capturesPresentedFrames, renderTargetKind == .swapChain else {
            return
        }
        guard let backBuffer = try? acquireBackBuffer() else {
            return
        }
        var owned: UnsafeMutablePointer<ID3D11Texture2D>? = backBuffer
        defer { releaseCOM(&owned) }
        capturedPresentedFrame = try? readPixels(of: backBuffer, operation: "Capture presented frame")
    }

    /// GPU-to-CPU readback of a render target, as BGRA in the same byte order
    /// `GPUIRawSceneRasterizer` produces.
    ///
    /// The result is tagged premultiplied: it is the output of a
    /// premultiplied blend state. With the usual opaque clear colour the two
    /// conventions coincide byte for byte, which is why parity scenes clear
    /// to alpha 1.
    private func readPixels(
        of texture: UnsafeMutablePointer<ID3D11Texture2D>,
        operation: String
    ) throws -> BitmapSurface {
        guard let device, let deviceContext else {
            throw BatchRendererError(operation: operation, hresult: batchHresultHandle)
        }

        // Read the target's own dimensions rather than the requested size:
        // a zero-size resize leaves the previous texture in place, and a
        // staging copy has to match the source exactly.
        var descriptor = D3D11_TEXTURE2D_DESC()
        texture.pointee.lpVtbl.pointee.GetDesc(texture, &descriptor)
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
        let source = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
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
        let shaders: [(source: String, vertex: String, pixel: String)] = [
            (batchQuadShaderSource, "vsMain", "psMain"),
            (batchSeparableBlendQuadShaderSource, "vsMain", "psMain"),
            (batchImageShaderSource, "vsMain", "psMain"),
            (batchImageColorEffectShaderSource, "vsMain", "psMain"),
            (batchImageReplacementShaderSource, "vsMain", "psMain"),
            (batchImageIsolatedReplacementShaderSource, "vsMain", "psMain"),
            (batchImageIsolatedCoverageShaderSource, "vsMain", "psMain"),
            (batchIsolatedBackdropComposeShaderSource, "vsMain", "psMain"),
            (batchShadowShaderSource, "vsMain", "psMain"),
            (
                GlyphPipelineResources.vertexShaderSource,
                GlyphPipelineResources.vertexShaderEntryPoint, GlyphPipelineResources.pixelShaderEntryPoint
            ),
            (batchMaterialQuadShaderSource, "vsMain", "psMain"),
            (batchMaterialCoverageShaderSource, "vsMain", "psMain"),
            (batchBackdropBlurShaderSource, "vsMain", "psMain"),
            (batchIsolatedBlurUpsampleShaderSource, "vsMain", "psMain"),
        ]
        for shader in shaders {
            for (entryPoint, profile) in [(shader.vertex, "vs_5_0"), (shader.pixel, "ps_5_0")] {
                var blob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
                    source: shader.source, entryPoint: entryPoint, profile: profile)
                // A later shader failing compilation must not leak the blobs
                // produced by earlier iterations of this validation.
                defer { releaseCOM(&blob) }
            }
        }
    }

    // MARK: - Device Creation

    /// Creates the device, trying each driver type in order. The windowed
    /// attach passes `[HARDWARE, WARP]` — a machine with no usable hardware
    /// adapter still presents, through the software rasterizer, rather than
    /// showing a blank window. The offscreen attach chooses via
    /// `OffscreenDriver`. The parameter default is hardware-only and applies
    /// to neither.
    private func createDeviceIfNeeded(driverTypes: [D3D_DRIVER_TYPE] = [D3D_DRIVER_TYPE_HARDWARE]) throws {
        if device != nil && deviceContext != nil {
            return
        }

        var flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)
        if createsDebugDeviceForTesting {
            flags |= UINT(bitPattern: D3D11_CREATE_DEVICE_DEBUG.rawValue)
        }
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
                    createdFeatureLevel = featureLevel
                    deviceGeneration = RendererDeviceGeneration.next()
                    attachGPUFrameTimingCollectorIfNeeded()
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
        if let displayAcquisition {
            if hr >= 0, let swapChain {
                displayAcquisitionEpoch = displayAcquisition.openEpoch(
                    address: UInt64(UInt(bitPattern: swapChain)), deviceGeneration: deviceGeneration)
            } else if swapChain != nil {
                // A failed API with a nonnil partial result is not a proven
                // creation epoch; cleanup stays unchanged and capture is invalid.
                displayAcquisition.invalidate(.epochIdentity)
            }
        }
        try throwIfFailed(hr, operation: "IDXGIFactory2.CreateSwapChainForHwnd")

        // Same contract as the frame backend: this stack handles its own
        // keyboard input, so DXGI must not install its default Alt+Enter
        // mode-switch and Print Screen hooks on the window it now presents to.
        let associationHR = dxgiFactory.pointee.lpVtbl.pointee.MakeWindowAssociation(
            dxgiFactory,
            hwnd,
            UINT(DXGI_MWA_NO_ALT_ENTER | DXGI_MWA_NO_PRINT_SCREEN)
        )
        if associationHR < 0 {
            renderLog(
                "[D3D11BatchRenderer] IDXGIFactory2.MakeWindowAssociation failed with "
                    + "0x\(String(UInt32(bitPattern: associationHR), radix: 16)); "
                    + "DXGI keeps its default Alt+Enter / Print Screen handling for this window."
            )
        }
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

    /// Brings `slot`'s texture up to date with `snapshot`, uploading as
    /// little as the atlas protocol allows.
    ///
    /// Three branches, decided by ``GlyphAtlasSnapshot/uploadDecision(for:)``
    /// rather than here: skip when the texture already holds this content
    /// version, upload one box when the snapshot's region is relative to
    /// exactly what the texture holds, upload everything otherwise. The
    /// last case covers every ambiguity — a fresh texture, a resize, a
    /// region whose base version this texture never had (a second window
    /// consuming the shared atlas), a region that clamps to nothing.
    private func updateGlyphAtlasTexture(
        _ snapshot: GlyphAtlasSnapshot,
        slot: inout AtlasTextureSlot
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

        // Decided against the state the texture is in *now*, before any
        // recreation below can change it.
        let decision: AtlasUploadDecision =
            slot.texture == nil ? .full : snapshot.uploadDecision(for: slot.state)
        if decision == .skip {
            atlasSkippedUploadsForTesting &+= 1
            return
        }

        if slot.texture == nil || slot.state.size.width != snapshot.width
            || slot.state.size.height != snapshot.height
        {
            releaseCOM(&slot.srv)
            releaseCOM(&slot.texture)
            // Nothing has been uploaded into the replacement yet; the state
            // says so explicitly rather than letting a matching size imply
            // otherwise.
            slot.state = .uninitialized

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

            let textureHR = makeCOM(into: &slot.texture) { newTexture in
                device.pointee.lpVtbl.pointee.CreateTexture2D(device, &textureDesc, nil, &newTexture)
            }
            try throwIfFailed(
                textureHR, operation: "ID3D11Device.CreateTexture2D(glyph atlas)", failureKind: .sceneContent)

            guard let texture = slot.texture else {
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
            let srvHR = makeCOM(into: &slot.srv) { view in
                device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, &srvDesc, &view)
            }
            try throwIfFailed(srvHR, operation: "ID3D11Device.CreateShaderResourceView(glyph atlas)")
        }

        guard let texture = slot.texture else {
            return
        }

        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        let rowPitch = UINT(snapshot.width * 4)
        snapshot.pixels.withUnsafeBytes { pixels in
            guard let baseAddress = pixels.baseAddress else {
                return
            }

            // The region is already clamped into the atlas rect by the
            // decision: a negative origin would trap at `UINT(_:)` below
            // (Swift does not wrap) and a region past the atlas edge would
            // make `UpdateSubresource` read past the end of `pixels`.
            if case .region(let region) = decision {
                let bytesOffset = Int((region.y * snapshot.width + region.x) * 4)
                var updateBox = D3D11_BOX(
                    left: UINT(region.x),
                    top: UINT(region.y),
                    front: 0,
                    right: UINT(region.x + region.width),
                    bottom: UINT(region.y + region.height),
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
                atlasRegionUploadsForTesting &+= 1
                // Rows are uploaded whole (`rowPitch` per row), so the cost is
                // the region's height times the atlas stride, not its area.
                atlasUploadedByteCount &+= UInt64(region.height) &* UInt64(rowPitch)
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
                atlasFullUploadsForTesting &+= 1
                atlasUploadedByteCount &+= UInt64(snapshot.height) &* UInt64(rowPitch)
            }
        }

        slot.state = snapshot.uploadedState
    }

    private func ensureImageResourceSRV(for textureID: Int32) throws -> UnsafeMutablePointer<ID3D11ShaderResourceView> {
        guard let bitmap = imageBindings[textureID] else {
            throw BatchRendererError(
                operation: "Resolve image resource",
                hresult: batchHresultInvalidArgument,
                details: "No bound bitmap exists for texture ID \(textureID).",
                failureKind: .sceneContent
            )
        }

        // Content key, not texture ID: the same bitmap keeps one texture
        // across frames however the frame's registration order renumbers
        // it, and a texture ID rebound to different pixels resolves to a
        // different entry rather than to a stale texture.
        let key = bitmap.contentKey
        if var cached = imageTextures[key], let srv = cached.srv {
            cached.lastUsedFrame = frameCounter
            imageTextures[key] = cached
            return srv
        }

        let (texture, srv) = try createImageTextureResource(for: bitmap)
        imageTextures[key] = ImageTextureEntry(
            texture: texture,
            srv: srv,
            byteCount: bitmap.describedByteCount,
            lastUsedFrame: frameCounter
        )
        imageTextureByteCount += bitmap.describedByteCount
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
        // Opaque surfaces convert without copying; the content-keyed cache
        // in `ensureImageResourceSRV` keeps an unchanged image from
        // reaching here at all.
        let upload = bitmap.premultipliedAlpha()
        imageTextureUploadsForTesting &+= 1

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

    /// Records one instanced draw against the current frame's totals. Called
    /// immediately before every `DrawInstanced` this backend issues, so the
    /// counters describe the frame that is being submitted rather than the
    /// plan that was built for it — a step that guards out before its draw
    /// (empty range, missing buffer) must not be counted as a draw.
    private func noteDrawCall(instanceCount: Int) {
        lastDrawCallCount &+= 1
        lastDrawnInstanceCount &+= instanceCount
    }

    private static func separableBlendMode(_ encoded: Float) -> BlendMode? {
        switch encoded {
        case Float(BlendMode.multiply.rawValue): return .multiply
        case Float(BlendMode.screen.rawValue): return .screen
        case Float(BlendMode.overlay.rawValue): return .overlay
        default: return nil
        }
    }

    /// Materials have already been separated by the caller. Every supported
    /// ordinary blend observes all earlier draws, including earlier instances
    /// in this run. Normal, additive and unrecognized modes retain batching.
    private func renderOrdinaryQuadRange(
        _ quads: [QuadPrimitive], range: Range<Int>,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>, surfaceSize: IntSize
    ) throws {
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            if let mode = Self.separableBlendMode(quads[cursor].blendMode) {
                try renderSeparableBlendQuad(
                    quads, index: cursor, mode: mode, deviceContext: deviceContext, surfaceSize: surfaceSize)
                cursor += 1
            } else {
                let runStart = cursor
                cursor += 1
                while cursor < range.upperBound, Self.separableBlendMode(quads[cursor].blendMode) == nil {
                    cursor += 1
                }
                try renderBatch(
                    quads, range: runStart..<cursor, capacity: &quadInstanceCapacity,
                    buffer: &quadInstanceBuffer, srv: &quadInstanceSRV, vs: quadVS, ps: quadPS,
                    label: "quad", deviceContext: deviceContext)
            }
        }
    }

    /// A conservative window of actual rasterized pixels, never a new image
    /// pass or its pixel-budget admission. The vertex shader does not expand
    /// ordinary geometry for AA or a subpixel blur radius. Rotated bounds use
    /// the sum of absolute half-extents so large finite angles cannot expose
    /// a CPU/HLSL trigonometry disagreement at the copy boundary. Signed
    /// dimensions are preserved: admission can retain a rotated signed quad.
    private static func separableBlendDestinationRegion(
        _ quad: QuadPrimitive, surfaceSize: IntSize
    ) -> SubTextureRegion? {
        guard surfaceSize.width > 0, surfaceSize.height > 0 else { return nil }
        guard
            !GPUIClipEncoding.isEmpty(
                clipX: quad.clipX, clipY: quad.clipY, clipWidth: quad.clipWidth, clipHeight: quad.clipHeight)
        else { return nil }

        let halfWidth = Double(quad.width) * 0.5
        let halfHeight = Double(quad.height) * 0.5
        let centerX = Double(quad.x) + halfWidth
        let centerY = Double(quad.y) + halfHeight
        let rotatedExtent = abs(halfWidth) + abs(halfHeight)
        let extentX = quad.rotationRadians == 0 ? abs(halfWidth) : rotatedExtent
        let extentY = quad.rotationRadians == 0 ? abs(halfHeight) : rotatedExtent
        // One pixel covers Float vertex arithmetic and raster rounding.
        var minX = centerX - extentX - 1
        var minY = centerY - extentY - 1
        var maxX = centerX + extentX + 1
        var maxY = centerY + extentY + 1
        if !GPUIClipEncoding.isAbsent(
            clipX: quad.clipX, clipY: quad.clipY, clipWidth: quad.clipWidth, clipHeight: quad.clipHeight)
        {
            minX = max(minX, Double(quad.clipX) - 1)
            minY = max(minY, Double(quad.clipY) - 1)
            maxX = min(maxX, Double(quad.clipX) + Double(quad.clipWidth) + 1)
            maxY = min(maxY, Double(quad.clipY) + Double(quad.clipHeight) + 1)
        }
        // Clamp floating values before integer conversion, even for geometry
        // spanning far outside the target. Scene admission rejects nonfinite
        // geometry; this guard also makes the helper safe in isolation.
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
        let width = Int(surfaceSize.width)
        let height = Int(surfaceSize.height)
        let left = Int(max(0, min(Double(width), floor(minX))))
        let top = Int(max(0, min(Double(height), floor(minY))))
        let right = Int(max(0, min(Double(width), ceil(maxX))))
        let bottom = Int(max(0, min(Double(height), ceil(maxY))))
        guard right > left, bottom > top else { return nil }
        return SubTextureRegion(
            originX: left, originY: top, width: right - left, height: bottom - top,
            textureWidth: width, textureHeight: height)
    }

    private func ensureSeparableBlendPipeline() throws {
        if separableBlendQuadPS != nil, separableBlendUniformBuffer != nil { return }
        guard let device else {
            throw BatchRendererError(operation: "Create separable blend pipeline", hresult: batchHresultHandle)
        }
        var shaderBlob: UnsafeMutablePointer<ID3DBlob>? = try Self.compileShaderSource(
            source: batchSeparableBlendQuadShaderSource, entryPoint: "psMain", profile: "ps_5_0")
        defer { releaseCOM(&shaderBlob) }
        guard let shaderBlob else {
            throw BatchRendererError(operation: "Compile separable blend shader", hresult: batchHresultHandle)
        }
        var shader: UnsafeMutablePointer<ID3D11PixelShader>?
        var buffer: UnsafeMutablePointer<ID3D11Buffer>?
        defer {
            releaseCOM(&shader)
            releaseCOM(&buffer)
        }
        let shaderHR = makeCOM(into: &shader) { value in
            device.pointee.lpVtbl.pointee.CreatePixelShader(
                device, shaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(shaderBlob),
                SIZE_T(shaderBlob.pointee.lpVtbl.pointee.GetBufferSize(shaderBlob)), nil, &value)
        }
        try throwIfFailed(shaderHR, operation: "ID3D11Device.CreatePixelShader(separable blend)")
        var descriptor = D3D11_BUFFER_DESC()
        descriptor.ByteWidth = UINT(MemoryLayout<D3D11SeparableBlendUniforms>.stride)
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)
        let bufferHR = makeCOM(into: &buffer) { value in
            device.pointee.lpVtbl.pointee.CreateBuffer(device, &descriptor, nil, &value)
        }
        try throwIfFailed(bufferHR, operation: "ID3D11Device.CreateBuffer(separable blend)")
        guard shader != nil, buffer != nil else {
            throw BatchRendererError(operation: "Resolve separable blend pipeline", hresult: batchHresultHandle)
        }
        releaseCOM(&separableBlendQuadPS)
        releaseCOM(&separableBlendUniformBuffer)
        separableBlendQuadPS = shader
        separableBlendUniformBuffer = buffer
        shader = nil
        buffer = nil
    }

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

        try drawPreparedInstances(
            instanceCount: instanceCount, deviceContext: deviceContext)

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
        try drawPreparedInstances(
            instanceCount: instanceCount, deviceContext: deviceContext)

        var nullSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = nil
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &nullSRV)
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &nullSRV)
    }

    private func renderImageBatch(
        _ instances: [ImagePrimitive],
        range: Range<Int>,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        textureSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>,
        pixelShader: UnsafeMutablePointer<ID3D11PixelShader>? = nil,
        mirrorsIsolationCoverage: Bool = true
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
            let selectedPixelShader = pixelShader ?? imagePS
        else {
            return
        }

        try uploadInstances(instances, range: range, buffer: imageInstanceBuffer, deviceContext: deviceContext)

        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, imageVS, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, selectedPixelShader, nil, 0)

        var instanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = imageInstanceSRV
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &instanceSRV)

        var textureSRVPointer: UnsafeMutablePointer<ID3D11ShaderResourceView>? = textureSRV
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &textureSRVPointer)

        var samplerPtr: UnsafeMutablePointer<ID3D11SamplerState>? = samplerState
        deviceContext.pointee.lpVtbl.pointee.PSSetSamplers(deviceContext, 0, 1, &samplerPtr)
        try drawPreparedInstances(
            instanceCount: instanceCount, deviceContext: deviceContext,
            mirrorsIsolationCoverage: mirrorsIsolationCoverage)

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

        let surfaceRect = Rect(
            origin: .zero,
            size: Size(width: Double(targetPixelSize.width), height: Double(targetPixelSize.height)))

        for index in range {
            let path = instances[index]
            guard let maskedBounds = path.contentMaskedBounds else { continue }
            // How much of the path is worth rasterizing. Normally all of it,
            // which is what keeps the cache key translation-invariant and the
            // clip a draw parameter: a static chart scrolling under a
            // viewport used to miss on every frame and CPU-rasterize on the
            // renderer owner. Past `pathWholeRasterByteBudget` the answer is the
            // visible window instead — the clip that was stripped from the
            // key still has to bound the buffer.
            let window: Rect?
            switch pathRasterWindow(
                bounds: path.bounds, maskedBounds: maskedBounds, surface: surfaceRect)
            {
            case .empty: continue
            case .whole: window = nil
            case .window(let rect): window = rect
            }

            let raster = try ensureCachedPathTexture(for: path, window: window)
            defer {
                if let owned = raster.owned {
                    var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>? = owned.srv
                    releaseCOM(&srv)
                    var texture: UnsafeMutablePointer<ID3D11Texture2D>? = owned.texture
                    releaseCOM(&texture)
                }
            }
            let bitmapSize = raster.bitmapSize
            guard let srv = raster.srv, bitmapSize.width > 0, bitmapSize.height > 0 else { continue }

            // The texture maps onto the screen rect anchored at the path's
            // own origin, offset by whatever window was rasterized. Drawing
            // only the visible sub-rect of it keeps a tall path inside a
            // short viewport from running a full-height pixel shader that
            // discards almost everything.
            let textureScreenRect = Rect(
                origin: Point(
                    x: path.bounds.origin.x + raster.originOffset.x,
                    y: path.bounds.origin.y + raster.originOffset.y),
                size: Size(width: Double(bitmapSize.width), height: Double(bitmapSize.height))
            )
            guard let visible = textureScreenRect.intersected(with: maskedBounds),
                visible.size.width > 0, visible.size.height > 0
            else { continue }

            let uvX = (visible.minX - textureScreenRect.minX) / textureScreenRect.size.width
            let uvY = (visible.minY - textureScreenRect.minY) / textureScreenRect.size.height
            let uvW = visible.size.width / textureScreenRect.size.width
            let uvH = visible.size.height / textureScreenRect.size.height

            var syntheticImage = ImagePrimitive(
                screenX: Float(visible.minX),
                screenY: Float(visible.minY),
                screenW: Float(visible.size.width),
                screenH: Float(visible.size.height),
                uvX: Float(uvX), uvY: Float(uvY), uvW: Float(uvW), uvH: Float(uvH),
                opacity: 1,
                clipX: 0, clipY: 0, clipWidth: 0, clipHeight: 0,
                clipCornerRadius: Float(path.clipCornerRadius),
                textureID: -1
            )
            // The original rounded shape remains a draw parameter. The
            // visible UV sub-rect only accounts for rectangular rejection.
            // Paths with nil bounds use the current target as R; packed
            // images instead treat all-zero R as inactive, so encode it here.
            GPUIClipEncoding.encode(
                path.clipBounds ?? surfaceRect,
                into: &syntheticImage.clipX, &syntheticImage.clipY,
                &syntheticImage.clipWidth, &syntheticImage.clipHeight)
            // addPath admits these values through Path sanitation. Hand-built
            // layers can bypass that door, so retain the same finite floor/cap
            // here without copying or sanitizing the path's geometry again.
            func normalizedClipRadius(_ radius: Double) -> Double {
                radius.isFinite ? min(max(0, radius), Double(GPUISceneLimits.maxCoordinate)) : 0
            }
            let clipRadii = (
                topLeft: normalizedClipRadius(path.clipCornerRadiusTopLeft),
                topRight: normalizedClipRadius(path.clipCornerRadiusTopRight),
                bottomRight: normalizedClipRadius(path.clipCornerRadiusBottomRight),
                bottomLeft: normalizedClipRadius(path.clipCornerRadiusBottomLeft)
            )
            syntheticImage.clipCornerRadiusTopLeft = Float(clipRadii.topLeft)
            syntheticImage.clipCornerRadiusTopRight = Float(clipRadii.topRight)
            syntheticImage.clipCornerRadiusBottomRight = Float(clipRadii.bottomRight)
            syntheticImage.clipCornerRadiusBottomLeft = Float(clipRadii.bottomLeft)
            let usesPathClipRadii =
                clipRadii.topLeft > 0 || clipRadii.topRight > 0
                || clipRadii.bottomRight > 0 || clipRadii.bottomLeft > 0
            let usesImageClipRadii =
                syntheticImage.clipCornerRadiusTopLeft > 0 || syntheticImage.clipCornerRadiusTopRight > 0
                || syntheticImage.clipCornerRadiusBottomRight > 0 || syntheticImage.clipCornerRadiusBottomLeft > 0
            if usesPathClipRadii && !usesImageClipRadii {
                // A selected Double corner can underflow to Float zero. Keep
                // its square limit instead of reviving the legacy scalar.
                syntheticImage.clipCornerRadius = 0
            }
            // The typed setter preserves explicit empty/underflowed anchors
            // rather than manufacturing the all-zero fallback sentinel.
            syntheticImage.clipShapeBounds = path.clipShapeBounds

            try renderImageBatch(
                [syntheticImage],
                range: 0..<1,
                deviceContext: deviceContext,
                textureSRV: srv
            )
        }
    }

    /// What of a path a frame rasterizes.
    private enum PathRasterWindow {
        /// Nothing of it can be seen; there is nothing to draw.
        case empty
        /// All of it. The cache key is translation- and clip-invariant, so a
        /// path that only moves keeps its entry.
        case whole
        /// A sub-rect in the path's own coordinates, snapped out to the tile
        /// grid so a small scroll still hits the entry it hit last frame.
        case window(Rect)
    }

    /// Decides how much of `bounds` to rasterize, given what the clip leaves
    /// of it (`maskedBounds`) and the surface it is being drawn onto.
    ///
    /// The whole path, whenever its raster fits `pathWholeRasterByteBudget` —
    /// which is every real shape, icon and `Canvas` drawing, and is what
    /// keeps one scrolling chart at one entry and one upload. Past the budget
    /// the raster covers the visible region only: a 400 × 20 000 chart inside
    /// a 600 px viewport is a 400 × 768 raster, not a 32 MB one.
    private func pathRasterWindow(
        bounds: Rect, maskedBounds: Rect, surface: Rect
    ) -> PathRasterWindow {
        let wholeWidth = max(1.0, bounds.size.width.rounded(.up))
        let wholeHeight = max(1.0, bounds.size.height.rounded(.up))
        guard wholeWidth * wholeHeight * 4 > Double(pathWholeRasterByteBudget) else {
            return .whole
        }
        guard let visible = maskedBounds.intersected(with: surface),
            visible.size.width > 0, visible.size.height > 0
        else {
            return .empty
        }

        let tile = Self.pathRasterWindowTile
        let localMinX = visible.minX - bounds.origin.x
        let localMinY = visible.minY - bounds.origin.y
        let minX = max(0, (localMinX / tile).rounded(.down) * tile)
        let minY = max(0, (localMinY / tile).rounded(.down) * tile)
        let maxX = min(bounds.size.width, ((localMinX + visible.size.width) / tile).rounded(.up) * tile)
        let maxY = min(bounds.size.height, ((localMinY + visible.size.height) / tile).rounded(.up) * tile)
        guard maxX > minX, maxY > minY, minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return .empty
        }
        return .window(Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    /// Returns a GPU texture for `path`, or for the `window` of it that is
    /// worth rasterizing. The raster is normalized to origin (0, 0) and
    /// carries no clip; the caller places the resulting quad at the original
    /// screen coordinates and applies the clip there. Reuses cached textures
    /// when the path's shape, paint and window match an entry from a recent
    /// frame.
    private func ensureCachedPathTexture(
        for path: PathPrimitive,
        window: Rect?
    ) throws -> PathRaster {
        let translation = Point(x: -path.bounds.origin.x, y: -path.bounds.origin.y)
        let originOffset = window?.origin ?? .zero
        let key = PathRasterKey(path: path, window: window)
        if let index = pathRenderCache.index(forKey: key) {
            let entry = pathRenderCache.values[index]
            if entry.path.matchesShapeAndPaint(of: path, translatedBy: translation) {
                pathRenderCache.values[index].lastUsedFrame = frameCounter
                pathCacheHits &+= 1
                return PathRaster(
                    srv: entry.srv, bitmapSize: entry.bitmapSize, originOffset: originOffset, owned: nil)
            }
            // A digest collision: same hash, same extent, same window,
            // different path. Drop the incumbent rather than draw its pixels.
            releaseCachedPathEntry(forKey: key)
        }

        pathCacheMisses &+= 1
        var normalizedPath = path.translated(by: translation)
        // The window *is* the clip for rasterization purposes: it is what
        // sizes the coverage buffer and the bitmap. Corner rounding stays a
        // draw parameter — an arc is not expressible as a sub-rect.
        normalizedPath.clipBounds = window
        normalizedPath.clipCornerRadius = 0
        normalizedPath.clipCornerRadiusTopLeft = 0
        normalizedPath.clipCornerRadiusTopRight = 0
        normalizedPath.clipCornerRadiusBottomRight = 0
        normalizedPath.clipCornerRadiusBottomLeft = 0
        normalizedPath.clipShapeBounds = nil
        guard let bitmap = GPUIRawSceneRasterizer.rasterizePath(normalizedPath) else {
            return .nothing
        }
        let bitmapSize = IntSize(width: Int32(bitmap.width), height: Int32(bitmap.height))
        let entryBytes = Int(bitmap.width) * Int(bitmap.height) * 4
        largestPathRasterPixelsForTesting = max(
            largestPathRasterPixelsForTesting, Int(bitmap.width) * Int(bitmap.height))

        // One entry bigger than the whole budget used to evict every other
        // entry — the `while` below cannot satisfy its condition — and then
        // be inserted anyway, so the next frame re-rasterized the emptied
        // cache and did it again. An outlier is drawn once and owned by the
        // caller instead; the cache it cannot fit is left alone.
        if entryBytes > pathCacheByteBudget {
            pathCacheOversizedDenials &+= 1
            let (texture, srv) = try createImageTextureResource(for: bitmap)
            return PathRaster(
                srv: srv, bitmapSize: bitmapSize, originOffset: originOffset,
                owned: (texture: texture, srv: srv))
        }

        // Bound the cache so unbounded canvas content doesn't accumulate
        // textures forever. Evict least-recently-used until both the entry
        // count and the byte budget hold with this entry counted — *before*
        // allocating, so a frame never peaks at budget + entry.
        while !pathRenderCache.isEmpty
            && (pathRenderCache.count >= Self.pathCacheMaxEntries
                || pathRenderCacheBytes + entryBytes > pathCacheByteBudget)
        {
            evictOldestCachedPathEntry()
        }
        let (texture, srv) = try createImageTextureResource(for: bitmap)
        let entry = CachedPathRender(
            texture: texture,
            srv: srv,
            bitmapSize: bitmapSize,
            lastUsedFrame: frameCounter,
            memoryBytes: entryBytes,
            path: normalizedPath
        )
        pathRenderCache[key] = entry
        pathRenderCacheBytes += entryBytes
        return PathRaster(
            srv: srv, bitmapSize: bitmapSize, originOffset: originOffset, owned: nil)
    }

    private func evictStaleCachedPaths() {
        guard frameCounter > Self.pathCacheStaleFrames else { return }
        let staleThreshold = frameCounter - Self.pathCacheStaleFrames
        let staleKeys = pathRenderCache.compactMap { element in
            element.value.lastUsedFrame < staleThreshold ? element.key : nil
        }
        for key in staleKeys {
            releaseCachedPathEntry(forKey: key)
        }
    }

    private func evictOldestCachedPathEntry() {
        guard let oldest = pathRenderCache.min(by: { $0.value.lastUsedFrame < $1.value.lastUsedFrame })
        else { return }
        releaseCachedPathEntry(forKey: oldest.key)
    }

    private func releaseCachedPathEntry(forKey key: PathRasterKey) {
        guard let entry = pathRenderCache.removeValue(forKey: key) else { return }
        pathRenderCacheBytes -= entry.memoryBytes
        var srvOpt: UnsafeMutablePointer<ID3D11ShaderResourceView>? = entry.srv
        releaseCOM(&srvOpt)
        var textureOpt: UnsafeMutablePointer<ID3D11Texture2D>? = entry.texture
        releaseCOM(&textureOpt)
    }

    private func releaseAllCachedPaths() {
        for key in pathRenderCache.keys {
            releaseCachedPathEntry(forKey: key)
        }
        pathRenderCacheBytes = 0
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
            // The renderer states which surface this is once, and the blur
            // engine reads that rather than a pair of loose ints. This is a
            // vocabulary consolidation, not a capability: the engine used to
            // be handed `surfaceWidth`/`surfaceHeight` off the same target,
            // so a material blurred inside an offscreen snapshot before this
            // too. What the descriptor buys is that the *kind* travels with
            // the size, so a consumer can no longer be told how big the
            // surface is without being told what it is.
            target: currentRenderTargetDescriptor,
            quad: quad
        )
    }

    /// Reads the current virtual composition, but replaces only the local
    /// foreground and coverage. A failure propagates so a dependent pass can
    /// never be cached or presented as an accidentally independent bitmap.
    private func renderIsolatedMaterialQuad(
        _ quad: QuadPrimitive, isolation: BackdropIsolationState,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>, surfaceSize: IntSize
    ) throws {
        defer {
            unbindIsolationShaderResources(deviceContext: deviceContext)
            bindFramePipelineState(deviceContext: deviceContext, surfaceSize: surfaceSize)
        }
        if failBlurredQuadsForTesting {
            throw BatchRendererError(
                operation: "Draw isolated material quad", hresult: batchHresultOutOfMemory,
                details: "Injected isolated material failure (test seam).")
        }
        try composeIsolationBackdrop(isolation, deviceContext: deviceContext)
        let engine = try ensureIsolatedBlurEngine(isolation)
        guard let readTexture = isolation.composed.texture, let foregroundView = isolation.foreground.view,
            let coverageView = isolation.coverage.view
        else {
            throw BatchRendererError(operation: "Resolve isolated material targets", hresult: batchHresultHandle)
        }
        let descriptor = currentRenderTargetDescriptor
        try engine.drawBlurredQuad(
            deviceContext: deviceContext, backBuffer: readTexture, backBufferRTV: foregroundView,
            target: descriptor, quad: quad)
        if failIsolatedCoverageForTesting {
            throw BatchRendererError(
                operation: "Draw isolated material coverage", hresult: batchHresultOutOfMemory,
                details: "Injected failure after drawing isolated foreground (test seam).")
        }
        try engine.drawMaterialCoverage(
            deviceContext: deviceContext, coverageRTV: coverageView, target: descriptor, quad: quad)
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
        if let isolation = backdropIsolation {
            try renderIsolatedMaterialQuad(
                quads[index], isolation: isolation, deviceContext: deviceContext, surfaceSize: surfaceSize)
            return
        }
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
// DXGI IIDs the Swift WinSDK overlay does not surface as constants, declared
// the same way `D3D11Renderer` declares `IID_IDXGIFactory5_local`.
private let dxgiDeviceInterfaceID = IID(
    Data1: 0x54ec_77fa,
    Data2: 0x1377,
    Data3: 0x44e6,
    Data4: (0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c)
)
private let dxgiAdapter1InterfaceID = IID(
    Data1: 0x2903_8f61,
    Data2: 0x3839,
    Data3: 0x4626,
    Data4: (0x91, 0xfd, 0x08, 0x68, 0x79, 0x01, 0x1a, 0x05)
)

private let batchHresultHandle: HRESULT = HRESULT(bitPattern: 0x8007_0006)
private let batchHresultInvalidArgument: HRESULT = HRESULT(bitPattern: 0x8007_0057)
private let batchHresultOutOfMemory: HRESULT = HRESULT(bitPattern: 0x8007_000E)
