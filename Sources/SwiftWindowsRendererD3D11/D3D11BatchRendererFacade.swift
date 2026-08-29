import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX

/// Actor-facing compatibility facade for the owner-confined batch renderer.
/// Existing callers retain synchronous rendering and explicit teardown.
/// Native presentation creates its own kernel instead of moving this one.
@MainActor
public final class D3D11BatchRenderer: BatchRenderBackend {
    public typealias OffscreenDriver = D3D11BatchOffscreenDriver
    public typealias AtlasSource = D3D11BatchAtlasSource
    public typealias CachedResources = D3D11BatchCachedResources
    public typealias RenderStep = D3D11BatchRenderStep
    public typealias RenderPlan = D3D11BatchRenderPlan
    typealias QuadBatchSegment = D3D11BatchKernel.QuadBatchSegment

    private let kernel = D3D11BatchKernel()

    public init() {}

    public var isAttached: Bool { kernel.isAttached }
    public var backendDisplayName: String { kernel.backendDisplayName }
    public var backendDiagnostics: BatchBackendDiagnostics? { kernel.backendDiagnostics }
    public var lastFrameSubmission: BackendFrameSubmission? { kernel.lastFrameSubmission }
    public var gpuFrameTimingDiagnostics: GPUFrameTimingDiagnostics? { kernel.gpuFrameTimingDiagnostics }
    public var presentationState: PresentationState { kernel.presentationState }
    public var presentPacing: PresentPacingStatus { kernel.presentPacing }

    public func attach(to surface: SurfaceDescriptor) throws {
        try kernel.attach(to: surface)
    }

    public func resize(to size: IntSize) throws {
        try kernel.resize(to: size)
    }

    public func bindImageResource(_ bitmap: BitmapSurface, for textureID: Int32) {
        kernel.bindImageResource(bitmap, for: textureID)
    }

    public func bindResources(for scene: GPUIScene) {
        kernel.bindResources(for: scene)
    }

    public func render(scene: GPUIScene) throws {
        // Tests can change these after construction or attach. Keep that
        // behavior without letting native kernels read actor-owned state.
        kernel.pathCacheByteBudgetOverrideForTesting = Self.pathCacheByteBudgetOverrideForTesting
        kernel.pathWholeRasterByteBudgetOverrideForTesting = Self.pathWholeRasterByteBudgetOverrideForTesting
        try kernel.render(scene: scene)
    }

    public func detach() {
        kernel.detach()
    }

    @discardableResult
    public func setGPUFrameTimingEnabled(_ enabled: Bool) -> Bool {
        kernel.setGPUFrameTimingEnabled(enabled)
    }

    public func takeCompletedGPUFrameTimings() -> [GPUFrameTimingResult] {
        kernel.takeCompletedGPUFrameTimings()
    }

    @discardableResult
    public func setPresentsWithVSync(_ enabled: Bool) -> Bool {
        kernel.setPresentsWithVSync(enabled)
    }

    @discardableResult
    public func setCapturesPresentedFrames(_ enabled: Bool) -> Bool {
        kernel.setCapturesPresentedFrames(enabled)
    }

    public func takeCapturedPresentedFrame() -> BitmapSurface? {
        kernel.takeCapturedPresentedFrame()
    }

    public func setDisplayFrameInterval(_ seconds: Double) {
        kernel.setDisplayFrameInterval(seconds)
    }

    public func adoptRememberedSelfPacing() {
        kernel.adoptRememberedSelfPacing()
    }

    public static func makeRenderPlan(
        for scene: GPUIScene,
        cachedResources: CachedResources = CachedResources()
    ) throws -> RenderPlan {
        try D3D11BatchKernel.makeRenderPlan(for: scene, cachedResources: cachedResources)
    }

    public static func validateBatchShadersForTesting() throws {
        try D3D11BatchKernel.validateBatchShadersForTesting()
    }

    static func cachedAdapterIsSoftware(
        forDeviceGeneration generation: UInt64,
        cachedGeneration: UInt64?,
        cachedIsSoftware: Bool?
    ) -> Bool? {
        D3D11BatchKernel.cachedAdapterIsSoftware(
            forDeviceGeneration: generation,
            cachedGeneration: cachedGeneration,
            cachedIsSoftware: cachedIsSoftware)
    }

    static func splitQuadRangeForBackdropBlur(
        _ quads: [QuadPrimitive],
        range: Range<Int>
    ) -> [QuadBatchSegment] {
        D3D11BatchKernel.splitQuadRangeForBackdropBlur(quads, range: range)
    }

    internal func attachOffscreen(size: IntSize, driver: OffscreenDriver = .hardwareFirst) throws {
        try kernel.attachOffscreen(size: size, driver: driver)
    }

    internal func readOffscreenPixels() throws -> BitmapSurface {
        try kernel.readOffscreenPixels()
    }

    internal func simulateDeviceLossForTesting() throws {
        try kernel.simulateDeviceLossForTesting()
    }

    internal func validateBoundImageSampling(in scene: GPUIScene) throws {
        try kernel.validateBoundImageSampling(in: scene)
    }

    internal func imageTextureIdentityForTesting(for textureID: Int32) -> (texture: UInt, srv: UInt)? {
        kernel.imageTextureIdentityForTesting(for: textureID)
    }

    internal var deviceGeneration: UInt64 { kernel.deviceGeneration }
    internal var atlasFullUploadsForTesting: UInt64 { kernel.atlasFullUploadsForTesting }
    internal var atlasRegionUploadsForTesting: UInt64 { kernel.atlasRegionUploadsForTesting }
    internal var atlasSkippedUploadsForTesting: UInt64 { kernel.atlasSkippedUploadsForTesting }
    internal var atlasUploadedByteCount: UInt64 { kernel.atlasUploadedByteCount }
    internal var lastDrawCallCount: Int { kernel.lastDrawCallCount }
    internal var lastDrawnInstanceCount: Int { kernel.lastDrawnInstanceCount }
    internal var imageTextureUploadsForTesting: UInt64 { kernel.imageTextureUploadsForTesting }
    internal var pathCacheHits: UInt64 { kernel.pathCacheHits }
    internal var pathCacheMisses: UInt64 { kernel.pathCacheMisses }
    internal var pathCacheOversizedDenials: UInt64 { kernel.pathCacheOversizedDenials }
    internal var largestPathRasterPixelsForTesting: Int { kernel.largestPathRasterPixelsForTesting }
    internal var directlyOwnedImagePassTargetCountForTesting: Int { kernel.directlyOwnedImagePassTargetCountForTesting }
    internal var pathCacheEntryCountForTesting: Int { kernel.pathCacheEntryCountForTesting }
    internal var pathCacheByteCountForTesting: Int { kernel.pathCacheByteCountForTesting }
    internal var blurDegradedForTesting: Bool { kernel.blurDegradedForTesting }
    internal var liveCOMObjectCountForTesting: Int { kernel.liveCOMObjectCountForTesting }
    internal var blurEngineOwnsResourcesForTesting: Bool { kernel.blurEngineOwnsResourcesForTesting }
    internal var deviceAddressForTesting: UInt { kernel.deviceAddressForTesting }
    internal var cachedResourcesForTesting: CachedResources { kernel.cachedResourcesForTesting }
    internal var imageTextureCacheCountForTesting: Int { kernel.imageTextureCacheCountForTesting }
    internal var currentRenderTargetDescriptor: RenderTargetDescriptor { kernel.currentRenderTargetDescriptor }

    /// Borrowed COM access remains confined to legacy actor tests.
    internal var deviceForTesting: UnsafeMutablePointer<ID3D11Device>? { kernel.deviceForTesting }

    internal var imageRenderPassExecutionBudgetOverrideForTesting: GPUISceneImageRenderPassBudget? {
        get { kernel.imageRenderPassExecutionBudgetOverrideForTesting }
        set { kernel.imageRenderPassExecutionBudgetOverrideForTesting = newValue }
    }

    internal var failBlurredQuadsForTesting: Bool {
        get { kernel.failBlurredQuadsForTesting }
        set { kernel.failBlurredQuadsForTesting = newValue }
    }

    internal var createsDebugDeviceForTesting: Bool {
        get { kernel.createsDebugDeviceForTesting }
        set { kernel.createsDebugDeviceForTesting = newValue }
    }

    internal var deviceLostBackoffHandler: (Double) -> Void {
        get { kernel.deviceLostBackoffHandler }
        set { kernel.deviceLostBackoffHandler = newValue }
    }

    internal static let pathRasterWindowTile: Double = D3D11BatchKernel.pathRasterWindowTile
    internal static var pathCacheByteBudgetOverrideForTesting: Int?
    internal static var pathWholeRasterByteBudgetOverrideForTesting: Int?
}
