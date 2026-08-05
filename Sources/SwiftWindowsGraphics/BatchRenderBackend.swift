import SwiftWindowsCore

/// What a batch backend can say about the device it is actually running on,
/// in renderer-neutral terms.
///
/// `RendererHealthSnapshot` answers "which backend is presenting"; this
/// answers the question underneath it, which health could not: *what is
/// presenting it*. A `D3D11 BATCH` backend running on the WARP software
/// rasterizer and one running on a discrete GPU report the same display name,
/// the same selection reason and the same `.available` probe — and differ by
/// two orders of magnitude in frame time. Until the adapter itself is
/// observable, "the GPU path engaged" is an unfalsifiable claim.
///
/// Every field is optional or zero-defaulted so a backend reports only what it
/// can actually determine.
public struct BatchBackendDiagnostics: Equatable, Sendable {
    /// Adapter description string as the driver reports it (e.g.
    /// "NVIDIA GeForce RTX 4070 Laptop GPU", "Microsoft Basic Render Driver").
    public var adapterDescription: String?
    /// `true` when the adapter is flagged as a software rasterizer (WARP /
    /// Basic Render Driver). This is the field that falsifies "the GPU path
    /// engaged": a software adapter behind a batch backend is a CPU renderer
    /// wearing the GPU backend's name.
    public var adapterIsSoftware: Bool?
    /// Dedicated VRAM the adapter reports, in bytes. Zero on WARP and on
    /// integrated parts that report only shared memory.
    public var adapterDedicatedVideoMemoryBytes: UInt64?
    /// Feature level the device was created at, as a display string
    /// (e.g. "11_1").
    public var featureLevel: String?
    /// Full-atlas uploads since the backend was constructed.
    public var atlasFullUploadCount: UInt64 = 0
    /// Dirty-region atlas uploads since the backend was constructed.
    public var atlasRegionUploadCount: UInt64 = 0
    /// Atlas binds that uploaded nothing because the snapshot was unchanged.
    public var atlasSkippedUploadCount: UInt64 = 0
    /// Total bytes handed to the driver for atlas uploads since construction.
    /// The number that matters for steady-state cost: a static text screen
    /// must stop adding to this after its first frame.
    public var atlasUploadedByteCount: UInt64 = 0
    /// Seconds the last frame spent building the render plan and issuing draw
    /// calls, excluding the present.
    public var lastSubmitSeconds: Double = 0
    /// Seconds the last frame spent inside the swap chain's present.
    ///
    /// Split from submission because the two have opposite meanings: submit
    /// time is work this process is doing, present time is this process
    /// waiting — for vblank, for the driver's present queue, or for the
    /// compositor. A frame budget blown on submission and one blown on
    /// waiting look identical from outside the backend and need opposite
    /// fixes.
    public var lastPresentSeconds: Double = 0
    /// Instanced draw calls the last frame issued.
    ///
    /// The observable half of `presentationOrder()` coalescing. Family batches
    /// only pay off if a run of same-family primitives collapses into one
    /// draw; a scene whose draw count tracks its primitive count is a scene
    /// where interleaving has defeated the batcher, and no amount of GPU
    /// headroom hides per-draw state changes at that rate.
    public var lastDrawCallCount: Int = 0
    /// Primitives those draws covered between them. `lastDrawnInstanceCount /
    /// lastDrawCallCount` is the coalescing ratio — the number that says
    /// whether batching happened, which neither figure says alone.
    public var lastDrawnInstanceCount: Int = 0

    public init(
        adapterDescription: String? = nil,
        adapterIsSoftware: Bool? = nil,
        adapterDedicatedVideoMemoryBytes: UInt64? = nil,
        featureLevel: String? = nil,
        atlasFullUploadCount: UInt64 = 0,
        atlasRegionUploadCount: UInt64 = 0,
        atlasSkippedUploadCount: UInt64 = 0,
        atlasUploadedByteCount: UInt64 = 0,
        lastSubmitSeconds: Double = 0,
        lastPresentSeconds: Double = 0,
        lastDrawCallCount: Int = 0,
        lastDrawnInstanceCount: Int = 0
    ) {
        self.adapterDescription = adapterDescription
        self.adapterIsSoftware = adapterIsSoftware
        self.adapterDedicatedVideoMemoryBytes = adapterDedicatedVideoMemoryBytes
        self.featureLevel = featureLevel
        self.atlasFullUploadCount = atlasFullUploadCount
        self.atlasRegionUploadCount = atlasRegionUploadCount
        self.atlasSkippedUploadCount = atlasSkippedUploadCount
        self.atlasUploadedByteCount = atlasUploadedByteCount
        self.lastSubmitSeconds = lastSubmitSeconds
        self.lastPresentSeconds = lastPresentSeconds
        self.lastDrawCallCount = lastDrawCallCount
        self.lastDrawnInstanceCount = lastDrawnInstanceCount
    }
}

/// Protocol for renderers that consume GPUIScene (batched rendering).
///
/// This sits alongside the existing ``RenderBackend`` protocol. A batch
/// renderer groups primitives by type and issues fewer, larger draw calls
/// instead of one draw per command. Concrete implementations (e.g. the
/// D3D11BatchRenderer) will conform to both ``RenderBackend``
/// and ``BatchRenderBackend``.
@MainActor
public protocol BatchRenderBackend: AnyObject {
    /// Human-readable name shown in debug overlays.
    var backendDisplayName: String { get }

    /// What this backend can report about the device it is running on and the
    /// upload work it has done. `nil` from backends that own no device.
    var backendDiagnostics: BatchBackendDiagnostics? { get }

    /// What the last render left the presentation path in — occluded, or
    /// owing the screen a repaint after a device rebuild. Backends that
    /// cannot lose a device inherit the neutral value.
    var presentationState: PresentationState { get }

    /// Which clock is pacing this backend's presents, and what the watchdog
    /// that decided it has seen. See ``PresentPacingPolicy``.
    var presentPacing: PresentPacingStatus { get }

    /// Tells the backend what one display period costs, so its pacing
    /// watchdog has something to judge present costs against. Called whenever
    /// the host's idea of the refresh rate changes — including a monitor move,
    /// which is the case the watchdog most needs to hear about.
    func setDisplayFrameInterval(_ seconds: Double)

    /// Attach to a platform window surface.
    func attach(to surface: SurfaceDescriptor) throws

    /// Handle surface resize.
    func resize(to size: IntSize) throws

    /// Bind any scene-owned resources needed before rendering.
    func bindResources(for scene: GPUIScene)

    /// Render a complete GPUIScene.
    func render(scene: GPUIScene) throws

    /// Asks the backend to stop (or resume) pacing presents to the display's
    /// vblank. Returns whether the backend honoured the request.
    ///
    /// Exists for measurement, not for tuning. A vsync-paced present blocks
    /// for however long the compositor decides, and that wait is indwelling
    /// in every frame-time figure taken from a live window — so a frame time
    /// of 250 ms says nothing about whether the app is slow until the pacing
    /// is removed and the number taken again. On a headless or virtual
    /// display the difference between the two is the entire measurement.
    func setPresentsWithVSync(_ enabled: Bool) -> Bool

    /// Releases every resource this backend acquired for its surface and
    /// returns it to the pre-attach state.
    ///
    /// The counterpart to ``attach(to:)``: a GPU backend holds a swap chain
    /// that pins its HWND, plus a device, pipeline objects, atlases and
    /// caches that nothing else in the process can release. Callers must
    /// invoke this when the window closes and before handing the same
    /// surface to a different backend, since flip-model presentation is
    /// exclusive per window. Detaching an unattached backend is a no-op,
    /// and a detached backend must be re-attachable.
    ///
    /// Deliberately has no protocol-extension default: a backend that owns
    /// a device and a swap chain used to satisfy this requirement by
    /// inheriting an empty implementation and leak exactly as it did before
    /// the requirement existed. Backends that own nothing write their own
    /// one-line no-op, where a reader can see that it is a decision.
    func detach()
}

extension BatchRenderBackend {
    public var presentationState: PresentationState { PresentationState() }

    /// A backend with no swap chain never waits on a display, so nothing is
    /// pacing it and nothing needs to be.
    public var presentPacing: PresentPacingStatus { PresentPacingStatus() }

    public func setDisplayFrameInterval(_ seconds: Double) {}

    public func bindResources(for scene: GPUIScene) {}

    /// A backend with no device has nothing to report. Unlike `detach()`, a
    /// silent default is right here: absence of diagnostics is honest, and
    /// forcing every fake in the test suite to write `nil` buys nothing.
    public var backendDiagnostics: BatchBackendDiagnostics? { nil }

    /// A backend with no swap chain has no pacing to disable.
    @discardableResult
    public func setPresentsWithVSync(_ enabled: Bool) -> Bool { false }
}
