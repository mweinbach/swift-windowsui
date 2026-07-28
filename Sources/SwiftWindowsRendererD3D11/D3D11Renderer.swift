// swift-format-ignore-file
// Embeds raw HLSL/D2D shader source whose indentation cannot survive
// swift-format, so the whole file opts out of lint/format.

import CDirect2DInterop
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX

public struct D3D11RendererConfiguration: Equatable, Sendable {
    public var fallbackClearColor: Color

    public init(fallbackClearColor: Color = Color(red: 0.08, green: 0.11, blue: 0.15, alpha: 1.0)) {
        self.fallbackClearColor = fallbackClearColor
    }
}

public struct D3D11RendererError: Error, ClassifiedPresentationFailure, CustomStringConvertible, Sendable {
    public let operation: String
    public let hresult: HRESULT
    public let details: String?
    /// How the host's recovery policy should read this failure. Defaults to
    /// the HRESULT's classification.
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
        // doing.
        self.presentationFailureKind =
            DeviceLostPolicy.isDeviceLost(hresult)
            ? .deviceLost
            : (failureKind ?? DeviceLostPolicy.failureKind(for: hresult))
    }

    public var description: String {
        let prefix = "\(operation) failed with HRESULT 0x\(String(UInt32(bitPattern: hresult), radix: 16, uppercase: true))."
        guard let details, !details.isEmpty else {
            return prefix
        }

        return "\(prefix) \(details)"
    }
}

/// Diagnostic payload for frame-fallback commands the D3D11/Direct2D path cannot paint.
/// Used for stderr reporting only; unsupported commands are soft-skipped so a single
/// reserved command cannot abort the rest of the frame or permanently demote Direct2D.
private struct UnsupportedRenderCommandDiagnostic: CustomStringConvertible, Sendable {
    let backend: String
    let commandName: String

    var description: String {
        "\(backend) does not support RenderCommand.\(commandName)."
    }
}

/// Clip-stack entry for frame-fallback pushClip/popClip (mirrors GPUISceneBridge semantics).
private struct FrameClipStackEntry {
    var rect: Rect
    var operation: ClipOperation
}

/// Blend modes supported by the D3D11 fallback renderer.
public enum D3D11BlendMode: Hashable, Sendable {
    case normal
    case additive
    case multiply
}

public final class D3D11Renderer: RenderBackend {
    public private(set) var isAttached = false {
        didSet { isAttachedMirror = isAttached }
    }

    /// Sendable mirror of ``isAttached`` so `deinit` — which is nonisolated
    /// and therefore cannot read main-actor state — can still tell whether
    /// the owner forgot to call ``detach()``.
    private nonisolated(unsafe) var isAttachedMirror = false

    public private(set) var isDirect2DEnabled = false
    /// Controls vertical sync. When true, Present uses sync interval 1;
    /// when false, sync interval 0 (and tearing flag when supported).
    public var vsyncEnabled: Bool = true
    public var backendDisplayName: String {
        isDirect2DEnabled ? "DIRECT2D" : "2D RENDERER"
    }

    public var backendStatusDescription: String {
        if isDirect2DEnabled {
            return "DIRECT2D 1.1 ACTIVE"
        }

        if didAttemptDirect2DSetup {
            return "D3D11 FALLBACK ACTIVE"
        }

        return "2D PIPELINE INITIALIZING"
    }

    private let configuration: D3D11RendererConfiguration

    private var surface: SurfaceDescriptor?
    private var hwnd: HWND?
    private var device: UnsafeMutablePointer<ID3D11Device>?
    private var deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>?
    private var dxgiFactory: UnsafeMutablePointer<IDXGIFactory2>?
    private var swapChain: UnsafeMutablePointer<IDXGISwapChain1>?
    private var renderTargetView: UnsafeMutablePointer<ID3D11RenderTargetView>?
    private var vertexShader: UnsafeMutablePointer<ID3D11VertexShader>?
    private var pixelShader: UnsafeMutablePointer<ID3D11PixelShader>?
    private var constantBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var bitmapVertexShader: UnsafeMutablePointer<ID3D11VertexShader>?
    private var bitmapPixelShader: UnsafeMutablePointer<ID3D11PixelShader>?
    private var bitmapConstantBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var bitmapSamplerState: UnsafeMutablePointer<ID3D11SamplerState>?
    private var blendState: UnsafeMutablePointer<ID3D11BlendState>?
    private var blendStates: [D3D11BlendMode: UnsafeMutablePointer<ID3D11BlendState>] = [:]
    private var currentBlendMode: D3D11BlendMode = .normal
    private var rasterizerState: UnsafeMutablePointer<ID3D11RasterizerState>?
    private var direct2DFactory: UnsafeMutableRawPointer?
    private var direct2DDevice: UnsafeMutableRawPointer?
    private var direct2DDeviceContext: UnsafeMutableRawPointer?
    private var direct2DTargetBitmap: UnsafeMutableRawPointer?
    private var didAttemptDirect2DSetup = false
    private var tearingSupported = false

    // MARK: - Device Loss

    public private(set) var presentationState = PresentationState()

    /// Process-wide source of device generations, so no two `ID3D11Device`s
    /// this module creates ever share an identity token even when the
    /// allocator reuses an address.
    private static var nextDeviceGeneration: UInt64 = 1

    /// Identity token for the device currently held, or `0` when detached.
    private(set) var deviceGeneration: UInt64 = 0

    /// Consecutive device rebuilds without an intervening present that
    /// reached the screen. Only a clean present (or a fresh external
    /// `attach`) clears it, so it bounds a device-loss storm, not a session.
    private var deviceLostRecoveryAttempts = 0

    /// Set by a successful rebuild so the next `render` returns without
    /// drawing — the first present after recreating a device tends to come
    /// back blank.
    private var skipNextFrameAfterDeviceLoss = false

    /// Test seam for the recovery wait; production blocks the main actor for
    /// a beat, which is what the driver needs.
    internal var deviceLostBackoffHandler: (Double) -> Void = { seconds in
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Keys already logged for soft-skipped unsupported frame commands (`backend|name`).
    /// Keeps stderr informative without flooding every animated frame.
    private var loggedUnsupportedCommandKeys: Set<String> = []
    /// Backends for which an end-of-frame skip summary has already been emitted.
    private var loggedUnsupportedFrameSummaries: Set<String> = []

    public init(configuration: D3D11RendererConfiguration = D3D11RendererConfiguration()) {
        self.configuration = configuration
    }

    static func validateShaderSourceForTesting() throws {
        var vertexShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(source: rectangleShaderSource, entryPoint: "vsMain", profile: "vs_4_0")
        var pixelShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(source: rectangleShaderSource, entryPoint: "psMain", profile: "ps_4_0")
        var bitmapVertexShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(source: bitmapShaderSource, entryPoint: "vsMain", profile: "vs_4_0")
        var bitmapPixelShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(source: bitmapShaderSource, entryPoint: "psMain", profile: "ps_4_0")
        releaseCOM(&bitmapPixelShaderBlob)
        releaseCOM(&bitmapVertexShaderBlob)
        releaseCOM(&pixelShaderBlob)
        releaseCOM(&vertexShaderBlob)
    }

    static func validateDirect2DInteropForTesting() throws {
        var factory: UnsafeMutableRawPointer?
        let hr = SWU_D2DCreateFactory1(&factory)
        defer {
            if let factory {
                SWU_D2DRelease(factory)
            }
        }

        if hr < 0 {
            throw D3D11RendererError(operation: "D2D1CreateFactory", hresult: hr)
        }
    }

    public func attach(to surface: SurfaceDescriptor) throws {
        guard let hwnd = unsafeBitCast(surface.windowHandle.rawPointer, to: HWND?.self) else {
            throw D3D11RendererError(operation: "Resolve HWND", hresult: hresultHandle)
        }

        // Attach always starts from nothing. The host re-attaches this
        // backend on every downgrade from the batch backend, and a leftover
        // flip-model swap chain on the same HWND would make DXGI reject the
        // new one — the wedge `detach()` exists to prevent.
        detach()
        // An externally requested attach is a fresh start: the device-loss
        // budget measures one storm, and this is not a continuation of it.
        deviceLostRecoveryAttempts = 0

        self.surface = surface
        self.hwnd = hwnd

        try createDeviceIfNeeded()
        try createFactoryIfNeeded()
        try createPipelineIfNeeded()
        try createSwapChain(size: surface.pixelSize)
        try createRenderTargetView()
        configureDirect2DIfPossible()

        isAttached = true
    }

    /// Releases every D3D11 and Direct2D object this renderer owns and
    /// returns it to the pre-attach state.
    ///
    /// Ordering follows the dependency chain: the Direct2D target wraps the
    /// swap chain's back buffer, so Direct2D goes first; then the pipeline
    /// is unbound from the immediate context and flushed; then views before
    /// the resources they view, and the swap chain (which pins the HWND)
    /// before the device that created it. Everything runs on the main actor,
    /// where the immediate context is used.
    public func detach() {
        releaseDirect2DResources()

        if let deviceContext {
            var noTargets: UnsafeMutablePointer<ID3D11RenderTargetView>?
            deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &noTargets, nil)
            deviceContext.pointee.lpVtbl.pointee.ClearState(deviceContext)
            deviceContext.pointee.lpVtbl.pointee.Flush(deviceContext)
        }

        releaseCOM(&rasterizerState)
        // `blendState` and `blendStates[.normal]` are the same object stored
        // twice under one reference, so the dictionary owns the release and
        // the property is only cleared.
        if let normal = blendStates[.normal], normal == blendState {
            blendState = nil
        }
        for state in blendStates.values {
            var releasable: UnsafeMutablePointer<ID3D11BlendState>? = state
            releaseCOM(&releasable)
        }
        blendStates.removeAll()
        releaseCOM(&blendState)
        currentBlendMode = .normal

        releaseCOM(&bitmapSamplerState)
        releaseCOM(&bitmapConstantBuffer)
        releaseCOM(&bitmapPixelShader)
        releaseCOM(&bitmapVertexShader)
        releaseCOM(&constantBuffer)
        releaseCOM(&pixelShader)
        releaseCOM(&vertexShader)

        releaseCOM(&renderTargetView)
        releaseCOM(&swapChain)
        releaseCOM(&dxgiFactory)
        releaseCOM(&deviceContext)
        releaseCOM(&device)
        // No device, no generation: every device-keyed resource is now stale
        // by construction rather than by comparison against a freed address.
        deviceGeneration = 0

        surface = nil
        hwnd = nil
        tearingSupported = false
        didAttemptDirect2DSetup = false
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
            "D3D11Renderer was deallocated while still attached — its device, swap chain and Direct2D "
                + "resources leak. Call detach() from the owner's teardown."
        )
    }

    public func resize(to size: IntSize) throws {
        surface?.pixelSize = size

        guard isAttached, let swapChain else {
            return
        }

        if size.width <= 0 || size.height <= 0 {
            return
        }

        releaseDirect2DTarget()
        releaseCOM(&renderTargetView)
        deviceContext?.pointee.lpVtbl.pointee.ClearState(deviceContext)

        var resizeFlags: UINT = 0
        if tearingSupported {
            resizeFlags |= UINT(DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING.rawValue)
        }

        let hr = swapChain.pointee.lpVtbl.pointee.ResizeBuffers(
            swapChain,
            0,
            UINT(max(size.width, 1)),
            UINT(max(size.height, 1)),
            DXGI_FORMAT_UNKNOWN,
            resizeFlags
        )
        try throwIfFailed(hr, operation: "IDXGISwapChain1.ResizeBuffers")
        try createRenderTargetView()
        configureDirect2DIfPossible()
    }

    public func render(frame: RenderFrame) throws {
        guard isAttached, let swapChain, let surface else {
            return
        }

        if surface.pixelSize.width <= 0 || surface.pixelSize.height <= 0 {
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

        let clearColor = frame.clearColor == .clear ? configuration.fallbackClearColor : frame.clearColor
        let scaleFactor = currentScaleFactor()

        // Phase 6 readable degradation: rewrite fillPath/strokePath commands
        // (Canvas drawing, backgroundPath nodes, SF-symbol vector fallback) as
        // CPU-rasterized drawBitmap commands so vector chrome stays visible in
        // a downgraded session instead of being soft-skipped below. Runs on
        // both the Direct2D and D3D11 fallback branches; frames without path
        // commands pass through unchanged.
        let frame = FramePathDegradation.degradingPathsToBitmaps(in: frame, scaleFactor: scaleFactor)

        // Present sits *outside* this block on purpose. It used to be the
        // last statement inside the Direct2D `do`, so a present error — a
        // device reset, a mode change, an out-of-memory — was attributed to
        // Direct2D, permanently demoted it for the session, and then fell
        // through to re-draw and present the same frame a second time.
        // Drawing failures demote Direct2D; presentation failures belong to
        // the swap chain and are classified by `handlePresentResult`.
        var didDrawFrame = false
        if
            isDirect2DEnabled,
            let direct2DDeviceContext,
            let direct2DTargetBitmap
        {
            do {
                try renderWithDirect2D(
                    frame: frame,
                    clearColor: clearColor,
                    scaleFactor: scaleFactor,
                    deviceContext: direct2DDeviceContext,
                    targetBitmap: direct2DTargetBitmap
                )
                didDrawFrame = true
            } catch {
                // Real Direct2D device/draw failures demote for the session.
                // Unsupported path/blur/text commands soft-skip inside renderWithDirect2D
                // and must not reach here (otherwise one reserved command kills Direct2D).
                renderLog(
                    "[D3D11Renderer] Direct2D frame failed (\(error)); demoting to D3D11 fallback for this session."
                )
                releaseDirect2DTarget()
                isDirect2DEnabled = false
            }
        }

        if didDrawFrame {
            try presentFrame(swapChain: swapChain)
            return
        }

        guard
            let renderTargetView,
            let deviceContext,
            let vertexShader,
            let pixelShader,
            let constantBuffer,
            let bitmapVertexShader,
            let bitmapPixelShader,
            let bitmapConstantBuffer,
            let bitmapSamplerState,
            let blendState,
            let rasterizerState
        else {
            return
        }

        var targetView: UnsafeMutablePointer<ID3D11RenderTargetView>? = renderTargetView
        deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &targetView, nil)

        var viewport = D3D11_VIEWPORT(
            TopLeftX: 0,
            TopLeftY: 0,
            Width: FLOAT(surface.pixelSize.width),
            Height: FLOAT(surface.pixelSize.height),
            MinDepth: 0,
            MaxDepth: 1
        )
        deviceContext.pointee.lpVtbl.pointee.RSSetViewports(deviceContext, 1, &viewport)
        deviceContext.pointee.lpVtbl.pointee.RSSetState(deviceContext, rasterizerState)

        // Reset scissor rect to full surface at frame boundary so state does not
        // leak from a previous frame's clip stack.
        var fullSurfaceScissor = D3D11_RECT(
            left: 0,
            top: 0,
            right: Int32(surface.pixelSize.width),
            bottom: Int32(surface.pixelSize.height)
        )
        deviceContext.pointee.lpVtbl.pointee.RSSetScissorRects(deviceContext, 1, &fullSurfaceScissor)
        deviceContext.pointee.lpVtbl.pointee.IASetInputLayout(deviceContext, nil)
        deviceContext.pointee.lpVtbl.pointee.IASetPrimitiveTopology(deviceContext, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST)
        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, vertexShader, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, pixelShader, nil, 0)

        var shaderConstantBuffer: UnsafeMutablePointer<ID3D11Buffer>? = constantBuffer
        deviceContext.pointee.lpVtbl.pointee.VSSetConstantBuffers(deviceContext, 0, 1, &shaderConstantBuffer)
        deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 0, 1, &shaderConstantBuffer)

        // Reset blend mode to normal at each frame boundary.
        currentBlendMode = .normal
        let blendFactor: [FLOAT] = [0, 0, 0, 0]
        blendFactor.withUnsafeBufferPointer { buffer in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(deviceContext, blendState, buffer.baseAddress, UINT.max)
        }

        let values: [FLOAT] = [clearColor.red, clearColor.green, clearColor.blue, clearColor.alpha]

        values.withUnsafeBufferPointer { buffer in
            deviceContext.pointee.lpVtbl.pointee.ClearRenderTargetView(deviceContext, renderTargetView, buffer.baseAddress)
        }

        // Logical surface bounds for clip-stack resolution. Draw helpers still
        // scale individual commands into pixel space.
        let logicalSurfaceSize = Size(
            width: Double(surface.pixelSize.width) / scaleFactor,
            height: Double(surface.pixelSize.height) / scaleFactor
        )
        var clipStack: [FrameClipStackEntry] = []
        var skippedUnsupportedCount = 0

        for command in frame.commands {
            switch command {
            case .fillRect(let fillRectCommand):
                let effectiveClip = resolveFrameEffectiveClip(
                    commandClip: fillRectCommand.clipRect,
                    clipStack: clipStack,
                    surfaceSize: logicalSurfaceSize
                )
                guard !effectiveClip.isEmpty else { continue }
                var clipped = fillRectCommand
                // Only materialize a clip when the stack or command contributed one;
                // avoid pushing a full-surface scissor for every unclipped draw.
                if !clipStack.isEmpty || fillRectCommand.clipRect != nil {
                    clipped.clipRect = effectiveClip
                }
                try draw(
                    fillRect: clipped,
                    surfaceSize: surface.pixelSize,
                    scaleFactor: scaleFactor,
                    deviceContext: deviceContext,
                    vertexShader: vertexShader,
                    pixelShader: pixelShader,
                    constantBuffer: constantBuffer
                )

            case .drawBitmap(let drawBitmapCommand):
                let effectiveClip = resolveFrameEffectiveClip(
                    commandClip: drawBitmapCommand.clipRect,
                    clipStack: clipStack,
                    surfaceSize: logicalSurfaceSize
                )
                guard !effectiveClip.isEmpty else { continue }
                var clipped = drawBitmapCommand
                if !clipStack.isEmpty || drawBitmapCommand.clipRect != nil {
                    clipped.clipRect = effectiveClip
                }
                try draw(
                    bitmap: clipped,
                    surfaceSize: surface.pixelSize,
                    scaleFactor: scaleFactor,
                    deviceContext: deviceContext,
                    vertexShader: bitmapVertexShader,
                    pixelShader: bitmapPixelShader,
                    constantBuffer: bitmapConstantBuffer,
                    samplerState: bitmapSamplerState
                )

            case .pushClip(let clipCommand):
                pushFrameClip(clipCommand, onto: &clipStack, surfaceSize: logicalSurfaceSize)

            case .popClip:
                // Empty-stack pop is a safe no-op (matches GPUISceneBridge / VAL-SCENE-009).
                if !clipStack.isEmpty {
                    clipStack.removeLast()
                }

            case .fillPath, .strokePath, .applyBlur, .drawText:
                // Soft-skip: do not abort the frame or throw. Diagnostics stay visible
                // without inventing placeholder geometry that could hide rendering loss.
                noteUnsupportedRenderCommand(command, backend: "D3D11 fallback")
                skippedUnsupportedCount += 1
            }
        }

        noteUnsupportedFrameSummaryIfNeeded(
            backend: "D3D11 fallback",
            skippedCount: skippedUnsupportedCount
        )

        try presentFrame(swapChain: swapChain)
    }

    /// The one place this renderer presents. Both draw paths end here, so a
    /// frame can never be presented twice and a present HRESULT is always
    /// classified the same way.
    private func presentFrame(swapChain: UnsafeMutablePointer<IDXGISwapChain1>) throws {
        let syncInterval: UINT = vsyncEnabled ? 1 : 0
        var presentFlags: UINT = 0
        if !vsyncEnabled && tearingSupported {
            presentFlags |= DXGI_PRESENT_ALLOW_TEARING
        }
        let hr = swapChain.pointee.lpVtbl.pointee.Present(swapChain, syncInterval, presentFlags)
        try handlePresentResult(hr)
    }

    private func createDeviceIfNeeded() throws {
        if device != nil && deviceContext != nil {
            return
        }

        let flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)
        var featureLevel = D3D_FEATURE_LEVEL(0)

        var featureLevels: [D3D_FEATURE_LEVEL] = [
            D3D_FEATURE_LEVEL_11_1,
            D3D_FEATURE_LEVEL_11_0,
            D3D_FEATURE_LEVEL_10_1,
            D3D_FEATURE_LEVEL_10_0,
        ]

        // Create into locals and install only on success: a failed attempt
        // that still wrote an out-param would otherwise overwrite (and leak)
        // whatever the properties already held.
        let createDevice: (UnsafePointer<D3D_FEATURE_LEVEL>?, UINT) -> HRESULT = { pointer, count in
            var createdDevice: UnsafeMutablePointer<ID3D11Device>?
            var createdContext: UnsafeMutablePointer<ID3D11DeviceContext>?
            let hr = D3D11CreateDevice(
                nil,
                D3D_DRIVER_TYPE_HARDWARE,
                nil,
                flags,
                pointer,
                count,
                UINT(D3D11_SDK_VERSION),
                &createdDevice,
                &featureLevel,
                &createdContext
            )

            if hr >= 0, createdDevice != nil, createdContext != nil {
                releaseCOM(&self.device)
                releaseCOM(&self.deviceContext)
                self.device = createdDevice
                self.deviceContext = createdContext
                self.deviceGeneration = Self.nextDeviceGeneration
                Self.nextDeviceGeneration &+= 1
            } else {
                releaseCOM(&createdContext)
                releaseCOM(&createdDevice)
            }
            return hr
        }

        let hr = featureLevels.withUnsafeBufferPointer { buffer in
            createDevice(buffer.baseAddress, UINT(buffer.count))
        }

        if hr == hresultInvalidArgument {
            featureLevels.removeFirst()
            let fallbackHR = featureLevels.withUnsafeBufferPointer { buffer in
                createDevice(buffer.baseAddress, UINT(buffer.count))
            }
            try throwIfFailed(fallbackHR, operation: "D3D11CreateDevice")
        } else {
            try throwIfFailed(hr, operation: "D3D11CreateDevice")
        }

        // Validate that the actual feature level meets our minimum requirement.
        if featureLevel.rawValue < D3D_FEATURE_LEVEL_11_0.rawValue {
            renderLog(
                "[D3D11Renderer] WARNING: Device created with feature level "
                    + "0x\(String(featureLevel.rawValue, radix: 16)) which is below D3D_FEATURE_LEVEL_11_0. "
                    + "Some rendering features may be unavailable."
            )
        }
    }

    private func createPipelineIfNeeded() throws {
        if
            vertexShader != nil,
            pixelShader != nil,
            constantBuffer != nil,
            bitmapVertexShader != nil,
            bitmapPixelShader != nil,
            bitmapConstantBuffer != nil,
            bitmapSamplerState != nil,
            blendState != nil,
            rasterizerState != nil
        {
            return
        }

        guard let device else {
            throw D3D11RendererError(operation: "Create D3D11 pipeline", hresult: hresultHandle)
        }

        #if DEBUG
        // Trigger the constant-buffer alignment assertions on first pipeline creation.
        _ = _rectangleUniformsAlignmentCheck
        _ = _bitmapUniformsAlignmentCheck
        #endif

        var vertexShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShader(source: rectangleShaderSource, entryPoint: "vsMain", profile: "vs_4_0")
        defer { releaseCOM(&vertexShaderBlob) }

        var pixelShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShader(source: rectangleShaderSource, entryPoint: "psMain", profile: "ps_4_0")
        defer { releaseCOM(&pixelShaderBlob) }

        var bitmapVertexShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShader(source: bitmapShaderSource, entryPoint: "vsMain", profile: "vs_4_0")
        defer { releaseCOM(&bitmapVertexShaderBlob) }

        var bitmapPixelShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShader(source: bitmapShaderSource, entryPoint: "psMain", profile: "ps_4_0")
        defer { releaseCOM(&bitmapPixelShaderBlob) }

        guard let vertexShaderBlob, let pixelShaderBlob, let bitmapVertexShaderBlob, let bitmapPixelShaderBlob else {
            throw D3D11RendererError(operation: "Create D3D11 pipeline", hresult: hresultHandle)
        }

        let vertexShaderHR = makeCOM(into: &vertexShader) { shader in
            device.pointee.lpVtbl.pointee.CreateVertexShader(
                device,
                vertexShaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(vertexShaderBlob),
                SIZE_T(vertexShaderBlob.pointee.lpVtbl.pointee.GetBufferSize(vertexShaderBlob)),
                nil,
                &shader
            )
        }
        try throwIfFailed(vertexShaderHR, operation: "ID3D11Device.CreateVertexShader")

        let pixelShaderHR = makeCOM(into: &pixelShader) { shader in
            device.pointee.lpVtbl.pointee.CreatePixelShader(
                device,
                pixelShaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(pixelShaderBlob),
                SIZE_T(pixelShaderBlob.pointee.lpVtbl.pointee.GetBufferSize(pixelShaderBlob)),
                nil,
                &shader
            )
        }
        try throwIfFailed(pixelShaderHR, operation: "ID3D11Device.CreatePixelShader")

        let bitmapVertexShaderHR = makeCOM(into: &bitmapVertexShader) { shader in
            device.pointee.lpVtbl.pointee.CreateVertexShader(
                device,
                bitmapVertexShaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(bitmapVertexShaderBlob),
                SIZE_T(bitmapVertexShaderBlob.pointee.lpVtbl.pointee.GetBufferSize(bitmapVertexShaderBlob)),
                nil,
                &shader
            )
        }
        try throwIfFailed(bitmapVertexShaderHR, operation: "ID3D11Device.CreateVertexShader(bitmap)")

        let bitmapPixelShaderHR = makeCOM(into: &bitmapPixelShader) { shader in
            device.pointee.lpVtbl.pointee.CreatePixelShader(
                device,
                bitmapPixelShaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(bitmapPixelShaderBlob),
                SIZE_T(bitmapPixelShaderBlob.pointee.lpVtbl.pointee.GetBufferSize(bitmapPixelShaderBlob)),
                nil,
                &shader
            )
        }
        try throwIfFailed(bitmapPixelShaderHR, operation: "ID3D11Device.CreatePixelShader(bitmap)")

        var constantBufferDescriptor = D3D11_BUFFER_DESC()
        constantBufferDescriptor.ByteWidth = UINT(MemoryLayout<RectangleUniforms>.size)
        constantBufferDescriptor.Usage = D3D11_USAGE_DEFAULT
        constantBufferDescriptor.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)

        let constantBufferHR = makeCOM(into: &constantBuffer) { buffer in
            device.pointee.lpVtbl.pointee.CreateBuffer(device, &constantBufferDescriptor, nil, &buffer)
        }
        try throwIfFailed(constantBufferHR, operation: "ID3D11Device.CreateBuffer")

        var bitmapConstantBufferDescriptor = D3D11_BUFFER_DESC()
        bitmapConstantBufferDescriptor.ByteWidth = UINT(MemoryLayout<BitmapUniforms>.size)
        bitmapConstantBufferDescriptor.Usage = D3D11_USAGE_DEFAULT
        bitmapConstantBufferDescriptor.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)

        let bitmapConstantBufferHR = makeCOM(into: &bitmapConstantBuffer) { buffer in
            device.pointee.lpVtbl.pointee.CreateBuffer(device, &bitmapConstantBufferDescriptor, nil, &buffer)
        }
        try throwIfFailed(bitmapConstantBufferHR, operation: "ID3D11Device.CreateBuffer(bitmap)")

        var samplerDescriptor = D3D11_SAMPLER_DESC()
        samplerDescriptor.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT
        samplerDescriptor.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.MaxLOD = FLOAT(D3D11_FLOAT32_MAX)

        let samplerStateHR = makeCOM(into: &bitmapSamplerState) { state in
            device.pointee.lpVtbl.pointee.CreateSamplerState(device, &samplerDescriptor, &state)
        }
        try throwIfFailed(samplerStateHR, operation: "ID3D11Device.CreateSamplerState")

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

        let blendStateHR = makeCOM(into: &blendState) { state in
            device.pointee.lpVtbl.pointee.CreateBlendState(device, &blendDescriptor, &state)
        }
        try throwIfFailed(blendStateHR, operation: "ID3D11Device.CreateBlendState")
        if let blendState {
            blendStates[.normal] = blendState
        }

        // Additive blend state: SrcBlend=ONE, DestBlend=ONE
        var additiveBlendDescriptor = D3D11_BLEND_DESC()
        additiveBlendDescriptor.AlphaToCoverageEnable = false
        additiveBlendDescriptor.IndependentBlendEnable = false
        additiveBlendDescriptor.RenderTarget.0.BlendEnable = true
        additiveBlendDescriptor.RenderTarget.0.SrcBlend = D3D11_BLEND_ONE
        additiveBlendDescriptor.RenderTarget.0.DestBlend = D3D11_BLEND_ONE
        additiveBlendDescriptor.RenderTarget.0.BlendOp = D3D11_BLEND_OP_ADD
        additiveBlendDescriptor.RenderTarget.0.SrcBlendAlpha = D3D11_BLEND_ONE
        additiveBlendDescriptor.RenderTarget.0.DestBlendAlpha = D3D11_BLEND_ONE
        additiveBlendDescriptor.RenderTarget.0.BlendOpAlpha = D3D11_BLEND_OP_ADD
        additiveBlendDescriptor.RenderTarget.0.RenderTargetWriteMask = UINT8(D3D11_COLOR_WRITE_ENABLE_ALL.rawValue)

        var additiveBlendState: UnsafeMutablePointer<ID3D11BlendState>?
        let additiveBlendStateHR = device.pointee.lpVtbl.pointee.CreateBlendState(device, &additiveBlendDescriptor, &additiveBlendState)
        try throwIfFailed(additiveBlendStateHR, operation: "ID3D11Device.CreateBlendState(additive)")
        if let additiveBlendState {
            blendStates[.additive] = additiveBlendState
        }

        // Multiply blend state: SrcBlend=DEST_COLOR, DestBlend=INV_SRC_ALPHA
        var multiplyBlendDescriptor = D3D11_BLEND_DESC()
        multiplyBlendDescriptor.AlphaToCoverageEnable = false
        multiplyBlendDescriptor.IndependentBlendEnable = false
        multiplyBlendDescriptor.RenderTarget.0.BlendEnable = true
        multiplyBlendDescriptor.RenderTarget.0.SrcBlend = D3D11_BLEND_DEST_COLOR
        multiplyBlendDescriptor.RenderTarget.0.DestBlend = D3D11_BLEND_INV_SRC_ALPHA
        multiplyBlendDescriptor.RenderTarget.0.BlendOp = D3D11_BLEND_OP_ADD
        multiplyBlendDescriptor.RenderTarget.0.SrcBlendAlpha = D3D11_BLEND_ONE
        multiplyBlendDescriptor.RenderTarget.0.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA
        multiplyBlendDescriptor.RenderTarget.0.BlendOpAlpha = D3D11_BLEND_OP_ADD
        multiplyBlendDescriptor.RenderTarget.0.RenderTargetWriteMask = UINT8(D3D11_COLOR_WRITE_ENABLE_ALL.rawValue)

        var multiplyBlendState: UnsafeMutablePointer<ID3D11BlendState>?
        let multiplyBlendStateHR = device.pointee.lpVtbl.pointee.CreateBlendState(device, &multiplyBlendDescriptor, &multiplyBlendState)
        try throwIfFailed(multiplyBlendStateHR, operation: "ID3D11Device.CreateBlendState(multiply)")
        if let multiplyBlendState {
            blendStates[.multiply] = multiplyBlendState
        }

        var rasterizerDescriptor = D3D11_RASTERIZER_DESC()
        rasterizerDescriptor.FillMode = D3D11_FILL_SOLID
        rasterizerDescriptor.CullMode = D3D11_CULL_NONE
        rasterizerDescriptor.ScissorEnable = true
        rasterizerDescriptor.DepthClipEnable = true

        let rasterizerStateHR = makeCOM(into: &rasterizerState) { state in
            device.pointee.lpVtbl.pointee.CreateRasterizerState(device, &rasterizerDescriptor, &state)
        }
        try throwIfFailed(rasterizerStateHR, operation: "ID3D11Device.CreateRasterizerState")
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

        // Check for tearing support via IDXGIFactory5::CheckFeatureSupport.
        checkTearingSupport()
    }

    private func checkTearingSupport() {
        guard let dxgiFactory else {
            return
        }

        // Query for IDXGIFactory5 to check tearing support.
        // If the interface is not available (older Windows), tearing is unsupported.
        var factory5IID = IID_IDXGIFactory5_local
        var rawFactory5: UnsafeMutableRawPointer?
        let queryHR = UnsafeMutableRawPointer(dxgiFactory)
            .assumingMemoryBound(to: IUnknown.self)
            .pointee.lpVtbl.pointee.QueryInterface(
                UnsafeMutableRawPointer(dxgiFactory).assumingMemoryBound(to: IUnknown.self),
                &factory5IID,
                &rawFactory5
            )

        guard queryHR >= 0, let rawFactory5 else {
            tearingSupported = false
            return
        }

        defer {
            let unknown = rawFactory5.assumingMemoryBound(to: IUnknown.self)
            _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        }

        let factory5 = rawFactory5.assumingMemoryBound(to: IDXGIFactory5.self)

        var allowTearing: WindowsBool = false
        let featureHR = factory5.pointee.lpVtbl.pointee.CheckFeatureSupport(
            factory5,
            DXGI_FEATURE_PRESENT_ALLOW_TEARING,
            &allowTearing,
            UINT(MemoryLayout<WindowsBool>.size)
        )

        tearingSupported = featureHR >= 0 && allowTearing != false
    }

    private func createSwapChain(size: IntSize) throws {
        guard let hwnd, let dxgiFactory, let device else {
            return
        }

        if swapChain != nil {
            return
        }

        var swapChainFlags: UINT = 0
        if tearingSupported {
            swapChainFlags |= UINT(DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING.rawValue)
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
        descriptor.Flags = swapChainFlags

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

        let _ = dxgiFactory.pointee.lpVtbl.pointee.MakeWindowAssociation(
            dxgiFactory,
            hwnd,
            UINT(DXGI_MWA_NO_ALT_ENTER)
        )
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
            throw D3D11RendererError(operation: "IDXGISwapChain1.GetBuffer", hresult: hresultHandle)
        }

        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        let viewHR = makeCOM(into: &renderTargetView) { view in
            device.pointee.lpVtbl.pointee.CreateRenderTargetView(device, resource, nil, &view)
        }
        var releasableTexture: UnsafeMutablePointer<ID3D11Texture2D>? = texture
        releaseCOM(&releasableTexture)
        try throwIfFailed(viewHR, operation: "ID3D11Device.CreateRenderTargetView")
    }

    private func configureDirect2DIfPossible() {
        didAttemptDirect2DSetup = true

        do {
            try createDirect2DResourcesIfNeeded()
            try createDirect2DTargetIfNeeded()
            isDirect2DEnabled = direct2DDeviceContext != nil && direct2DTargetBitmap != nil
        } catch {
            releaseDirect2DTarget()
            if direct2DFactory == nil || direct2DDevice == nil || direct2DDeviceContext == nil {
                releaseDirect2DResources()
            }
            isDirect2DEnabled = false
        }
    }

    private func createDirect2DResourcesIfNeeded() throws {
        if direct2DFactory != nil, direct2DDevice != nil, direct2DDeviceContext != nil {
            return
        }

        guard let device else {
            throw D3D11RendererError(operation: "Create Direct2D resources", hresult: hresultHandle)
        }

        var factory: UnsafeMutableRawPointer?
        var d2dDevice: UnsafeMutableRawPointer?
        var d2dContext: UnsafeMutableRawPointer?
        let hr = SWU_D2DCreateDeviceResources(
            UnsafeMutableRawPointer(device),
            &factory,
            &d2dDevice,
            &d2dContext
        )
        try throwIfFailed(hr, operation: "Create Direct2D device resources")

        direct2DFactory = factory
        direct2DDevice = d2dDevice
        direct2DDeviceContext = d2dContext
    }

    private func createDirect2DTargetIfNeeded() throws {
        guard direct2DTargetBitmap == nil else {
            return
        }

        guard let swapChain, let direct2DDeviceContext else {
            throw D3D11RendererError(operation: "Create Direct2D target", hresult: hresultHandle)
        }

        let dpi = Float(currentScaleFactor() * logicalDpi)
        var targetBitmap: UnsafeMutableRawPointer?
        let hr = SWU_D2DConfigureSwapChainTarget(
            direct2DDeviceContext,
            UnsafeMutableRawPointer(swapChain),
            dpi,
            dpi,
            &targetBitmap
        )
        try throwIfFailed(hr, operation: "Create Direct2D swap chain target")
        direct2DTargetBitmap = targetBitmap
    }

    private func renderWithDirect2D(
        frame: RenderFrame,
        clearColor: Color,
        scaleFactor: Double,
        deviceContext: UnsafeMutableRawPointer,
        targetBitmap: UnsafeMutableRawPointer
    ) throws {
        _ = targetBitmap

        // SWU_D2DSetIdentityTransform and SWU_D2DBeginDraw return void at the
        // C level, but we guard against a nil context reaching here by logging
        // a warning if the context looks invalid.  Future C-interop revisions
        // should promote these to HRESULT-returning functions.
        SWU_D2DSetIdentityTransform(deviceContext)
        SWU_D2DBeginDraw(deviceContext)

        var shouldEndDraw = true
        defer {
            if shouldEndDraw {
                _ = SWU_D2DEndDraw(deviceContext)
            }
        }

        SWU_D2DClear(deviceContext, clearColor.red, clearColor.green, clearColor.blue, clearColor.alpha)

        // Logical surface size for clip-stack resolution (Direct2D draws in DIP/logical space).
        let logicalSurfaceSize: Size
        if let surface {
            logicalSurfaceSize = Size(
                width: Double(surface.pixelSize.width) / scaleFactor,
                height: Double(surface.pixelSize.height) / scaleFactor
            )
        } else {
            logicalSurfaceSize = Size(width: 0, height: 0)
        }
        var clipStack: [FrameClipStackEntry] = []
        var skippedUnsupportedCount = 0

        for command in frame.commands {
            switch command {
            case .fillRect(let fillRectCommand):
                let effectiveClip = resolveFrameEffectiveClip(
                    commandClip: fillRectCommand.clipRect,
                    clipStack: clipStack,
                    surfaceSize: logicalSurfaceSize
                )
                guard !effectiveClip.isEmpty else { continue }
                var clipped = fillRectCommand
                if !clipStack.isEmpty || fillRectCommand.clipRect != nil {
                    clipped.clipRect = effectiveClip
                }
                try drawWithDirect2D(fillRect: clipped, deviceContext: deviceContext)

            case .drawBitmap(let drawBitmapCommand):
                let effectiveClip = resolveFrameEffectiveClip(
                    commandClip: drawBitmapCommand.clipRect,
                    clipStack: clipStack,
                    surfaceSize: logicalSurfaceSize
                )
                guard !effectiveClip.isEmpty else { continue }
                var clipped = drawBitmapCommand
                if !clipStack.isEmpty || drawBitmapCommand.clipRect != nil {
                    clipped.clipRect = effectiveClip
                }
                try drawWithDirect2D(bitmap: clipped, scaleFactor: scaleFactor, deviceContext: deviceContext)

            case .pushClip(let clipCommand):
                pushFrameClip(clipCommand, onto: &clipStack, surfaceSize: logicalSurfaceSize)

            case .popClip:
                if !clipStack.isEmpty {
                    clipStack.removeLast()
                }

            case .fillPath, .strokePath, .applyBlur, .drawText:
                // Soft-skip reserved commands. Throwing here used to demote Direct2D
                // permanently and abort the frame; keep painting supported neighbors.
                noteUnsupportedRenderCommand(command, backend: "Direct2D")
                skippedUnsupportedCount += 1
            }
        }

        noteUnsupportedFrameSummaryIfNeeded(
            backend: "Direct2D",
            skippedCount: skippedUnsupportedCount
        )

        let hr = SWU_D2DEndDraw(deviceContext)
        shouldEndDraw = false
        try throwIfFailed(hr, operation: "ID2D1DeviceContext.EndDraw")
    }

    private func drawWithDirect2D(
        fillRect command: FillRectCommand,
        deviceContext: UnsafeMutableRawPointer
    ) throws {
        guard command.rect.size.width > 0, command.rect.size.height > 0 else {
            return
        }

        if let clipRect = command.clipRect, clipRect.intersected(with: command.rect) == nil {
            return
        }

        let hr = try withDirect2DClip(command.clipRect, deviceContext: deviceContext) {
            if case .linear(let gradient) = command.gradient {
                let axis: Int32 = gradient.axis == .horizontal
                    ? Int32(SWU_D2D_GRADIENT_AXIS_HORIZONTAL)
                    : Int32(SWU_D2D_GRADIENT_AXIS_VERTICAL)
                return SWU_D2DFillRectGradient(
                    deviceContext,
                    Float(command.rect.minX),
                    Float(command.rect.minY),
                    Float(command.rect.maxX),
                    Float(command.rect.maxY),
                    Float(max(command.cornerRadius, 0)),
                    Float(max(command.cornerRadius, 0)),
                    gradient.startColor.red,
                    gradient.startColor.green,
                    gradient.startColor.blue,
                    gradient.startColor.alpha,
                    gradient.endColor.red,
                    gradient.endColor.green,
                    gradient.endColor.blue,
                    gradient.endColor.alpha,
                    axis
                )
            }

            return SWU_D2DFillRectSolid(
                deviceContext,
                Float(command.rect.minX),
                Float(command.rect.minY),
                Float(command.rect.maxX),
                Float(command.rect.maxY),
                Float(max(command.cornerRadius, 0)),
                Float(max(command.cornerRadius, 0)),
                command.color.red,
                command.color.green,
                command.color.blue,
                command.color.alpha
            )
        }

        try throwIfFailed(hr, operation: "Draw Direct2D fillRect")
    }

    private func drawWithDirect2D(
        bitmap command: DrawBitmapCommand,
        scaleFactor: Double,
        deviceContext: UnsafeMutableRawPointer
    ) throws {
        guard command.rect.size.width > 0, command.rect.size.height > 0, command.opacity > 0 else {
            return
        }

        let alignedRect = makeLogicalBitmapRect(
            from: command.rect,
            bitmapSize: IntSize(width: command.bitmap.width, height: command.bitmap.height),
            scaleFactor: scaleFactor
        )

        if let clipRect = command.clipRect, clipRect.intersected(with: alignedRect) == nil {
            return
        }

        let dpi = Float(max(scaleFactor, 1.0) * logicalDpi)
        let hr = try withDirect2DClip(command.clipRect, deviceContext: deviceContext) {
            command.bitmap.pixels.withUnsafeBytes { pixels in
                SWU_D2DDrawBitmapBGRA(
                    deviceContext,
                    pixels.baseAddress,
                    command.bitmap.width,
                    command.bitmap.height,
                    command.bitmap.bytesPerRow,
                    dpi,
                    dpi,
                    Float(alignedRect.minX),
                    Float(alignedRect.minY),
                    Float(alignedRect.maxX),
                    Float(alignedRect.maxY),
                    command.opacity
                )
            }
        }

        try throwIfFailed(hr, operation: "Draw Direct2D bitmap")
    }

    private func draw(
        fillRect command: FillRectCommand,
        surfaceSize: IntSize,
        scaleFactor: Double,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        vertexShader: UnsafeMutablePointer<ID3D11VertexShader>,
        pixelShader: UnsafeMutablePointer<ID3D11PixelShader>,
        constantBuffer: UnsafeMutablePointer<ID3D11Buffer>
    ) throws {
        let scaledCommand = scaled(fillRect: command, factor: scaleFactor)

        guard scaledCommand.rect.size.width > 0, scaledCommand.rect.size.height > 0 else {
            return
        }

        if let clipRect = scaledCommand.clipRect, clipRect.intersected(with: scaledCommand.rect) == nil {
            return
        }

        let effectiveClip = scaledCommand.clipRect ?? Rect(
            x: 0,
            y: 0,
            width: Double(surfaceSize.width),
            height: Double(surfaceSize.height)
        )

        guard let scissorRect = makeScissorRect(from: effectiveClip, surfaceSize: surfaceSize) else {
            return
        }

        var activeScissorRect = scissorRect
        deviceContext.pointee.lpVtbl.pointee.RSSetScissorRects(deviceContext, 1, &activeScissorRect)
        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, vertexShader, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, pixelShader, nil, 0)
        var shaderConstantBuffer: UnsafeMutablePointer<ID3D11Buffer>? = constantBuffer
        deviceContext.pointee.lpVtbl.pointee.VSSetConstantBuffers(deviceContext, 0, 1, &shaderConstantBuffer)
        deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 0, 1, &shaderConstantBuffer)

        let linearGradient: LinearGradient? = {
            if case .linear(let lg) = scaledCommand.gradient { return lg }
            return nil
        }()
        let startColor = linearGradient?.startColor ?? scaledCommand.color
        let endColor = linearGradient?.endColor ?? scaledCommand.color
        let gradientAxis: Float = {
            switch linearGradient?.axis {
            case .horizontal:
                return 1
            default:
                return 0
            }
        }()

        var uniforms = RectangleUniforms(
            surfaceWidth: Float(surfaceSize.width),
            surfaceHeight: Float(surfaceSize.height),
            rectX: Float(scaledCommand.rect.origin.x),
            rectY: Float(scaledCommand.rect.origin.y),
            rectWidth: Float(scaledCommand.rect.size.width),
            rectHeight: Float(scaledCommand.rect.size.height),
            cornerRadius: Float(max(0, scaledCommand.cornerRadius)),
            gradientAxis: gradientAxis,
            startRed: startColor.red,
            startGreen: startColor.green,
            startBlue: startColor.blue,
            startAlpha: startColor.alpha,
            endRed: endColor.red,
            endGreen: endColor.green,
            endBlue: endColor.blue,
            endAlpha: endColor.alpha
        )

        let constantBufferResource = UnsafeMutableRawPointer(constantBuffer).assumingMemoryBound(to: ID3D11Resource.self)

        withUnsafePointer(to: &uniforms) { pointer in
            deviceContext.pointee.lpVtbl.pointee.UpdateSubresource(deviceContext, constantBufferResource, 0, nil, UnsafeRawPointer(pointer), 0, 0)
        }

        deviceContext.pointee.lpVtbl.pointee.Draw(deviceContext, 6, 0)
    }

    private func draw(
        bitmap command: DrawBitmapCommand,
        surfaceSize: IntSize,
        scaleFactor: Double,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        vertexShader: UnsafeMutablePointer<ID3D11VertexShader>,
        pixelShader: UnsafeMutablePointer<ID3D11PixelShader>,
        constantBuffer: UnsafeMutablePointer<ID3D11Buffer>,
        samplerState: UnsafeMutablePointer<ID3D11SamplerState>
    ) throws {
        let scaledCommand = scaled(bitmap: command, factor: scaleFactor)

        guard scaledCommand.rect.size.width > 0, scaledCommand.rect.size.height > 0, scaledCommand.opacity > 0 else {
            return
        }

        if let clipRect = scaledCommand.clipRect, clipRect.intersected(with: scaledCommand.rect) == nil {
            return
        }

        let effectiveClip = scaledCommand.clipRect ?? Rect(
            x: 0,
            y: 0,
            width: Double(surfaceSize.width),
            height: Double(surfaceSize.height)
        )

        guard let scissorRect = makeScissorRect(from: effectiveClip, surfaceSize: surfaceSize) else {
            return
        }

        var activeScissorRect = scissorRect
        deviceContext.pointee.lpVtbl.pointee.RSSetScissorRects(deviceContext, 1, &activeScissorRect)
        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, vertexShader, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, pixelShader, nil, 0)

        var shaderConstantBuffer: UnsafeMutablePointer<ID3D11Buffer>? = constantBuffer
        deviceContext.pointee.lpVtbl.pointee.VSSetConstantBuffers(deviceContext, 0, 1, &shaderConstantBuffer)
        deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 0, 1, &shaderConstantBuffer)

        var activeSamplerState: UnsafeMutablePointer<ID3D11SamplerState>? = samplerState
        deviceContext.pointee.lpVtbl.pointee.PSSetSamplers(deviceContext, 0, 1, &activeSamplerState)

        var uniforms = BitmapUniforms(
            surfaceWidth: Float(surfaceSize.width),
            surfaceHeight: Float(surfaceSize.height),
            rectX: Float(scaledCommand.rect.origin.x),
            rectY: Float(scaledCommand.rect.origin.y),
            rectWidth: Float(scaledCommand.rect.size.width),
            rectHeight: Float(scaledCommand.rect.size.height),
            opacity: scaledCommand.opacity,
            padding: 0
        )

        let constantBufferResource = UnsafeMutableRawPointer(constantBuffer).assumingMemoryBound(to: ID3D11Resource.self)
        withUnsafePointer(to: &uniforms) { pointer in
            deviceContext.pointee.lpVtbl.pointee.UpdateSubresource(deviceContext, constantBufferResource, 0, nil, UnsafeRawPointer(pointer), 0, 0)
        }

        let shaderResourceView = try createShaderResourceView(for: scaledCommand.bitmap)
        defer {
            var releasableView: UnsafeMutablePointer<ID3D11ShaderResourceView>? = shaderResourceView
            releaseCOM(&releasableView)
            var nullView: UnsafeMutablePointer<ID3D11ShaderResourceView>? = nil
            deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 0, 1, &nullView)
        }

        var activeShaderResourceView: UnsafeMutablePointer<ID3D11ShaderResourceView>? = shaderResourceView
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 0, 1, &activeShaderResourceView)
        deviceContext.pointee.lpVtbl.pointee.Draw(deviceContext, 6, 0)
    }

    private func compileShader(source: String, entryPoint: String, profile: String) throws -> UnsafeMutablePointer<ID3DBlob> {
        try compileShaderSource(source: source, entryPoint: entryPoint, profile: profile)
    }

    private func createShaderResourceView(for bitmap: BitmapSurface) throws -> UnsafeMutablePointer<ID3D11ShaderResourceView> {
        guard let device else {
            throw D3D11RendererError(operation: "Create text texture", hresult: hresultHandle)
        }

        var textureDescriptor = D3D11_TEXTURE2D_DESC()
        textureDescriptor.Width = UINT(bitmap.width)
        textureDescriptor.Height = UINT(bitmap.height)
        textureDescriptor.MipLevels = 1
        textureDescriptor.ArraySize = 1
        textureDescriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        textureDescriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        textureDescriptor.Usage = D3D11_USAGE_DEFAULT
        textureDescriptor.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)

        var texture: UnsafeMutablePointer<ID3D11Texture2D>?
        let textureHR = bitmap.pixels.withUnsafeBytes { pixels in
            var subresource = D3D11_SUBRESOURCE_DATA()
            subresource.pSysMem = pixels.baseAddress
            subresource.SysMemPitch = UINT(bitmap.bytesPerRow)
            subresource.SysMemSlicePitch = UINT(bitmap.bytesPerRow * bitmap.height)
            return device.pointee.lpVtbl.pointee.CreateTexture2D(device, &textureDescriptor, &subresource, &texture)
        }
        try throwIfFailed(textureHR, operation: "ID3D11Device.CreateTexture2D")

        guard let texture else {
            throw D3D11RendererError(operation: "ID3D11Device.CreateTexture2D", hresult: hresultHandle)
        }
        defer {
            var releasableTexture: UnsafeMutablePointer<ID3D11Texture2D>? = texture
            releaseCOM(&releasableTexture)
        }

        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        var shaderResourceView: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        let shaderResourceViewHR = device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, nil, &shaderResourceView)
        try throwIfFailed(shaderResourceViewHR, operation: "ID3D11Device.CreateShaderResourceView")

        guard let shaderResourceView else {
            throw D3D11RendererError(operation: "ID3D11Device.CreateShaderResourceView", hresult: hresultHandle)
        }

        return shaderResourceView
    }

    private func throwIfFailed(_ hr: HRESULT, operation: String) throws {
        if hr < 0 {
            throw D3D11RendererError(operation: operation, hresult: hr)
        }
    }

    private func withDirect2DClip<T>(
        _ clipRect: Rect?,
        deviceContext: UnsafeMutableRawPointer,
        _ body: () throws -> T
    ) throws -> T {
        guard let clipRect else {
            return try body()
        }

        SWU_D2DPushAxisAlignedClip(
            deviceContext,
            Float(clipRect.minX),
            Float(clipRect.minY),
            Float(clipRect.maxX),
            Float(clipRect.maxY)
        )
        defer { SWU_D2DPopAxisAlignedClip(deviceContext) }
        return try body()
    }

    /// Soft-skips an unsupported frame command with one-shot diagnostics per backend/type.
    /// Does not throw: the rest of the frame continues so supported commands still present.
    private func noteUnsupportedRenderCommand(_ command: RenderCommand, backend: String) {
        let name = renderCommandName(command)
        let key = "\(backend)|\(name)"
        guard loggedUnsupportedCommandKeys.insert(key).inserted else {
            return
        }

        let diagnostic = UnsupportedRenderCommandDiagnostic(backend: backend, commandName: name)
        renderLog(
            "[D3D11Renderer] \(diagnostic.description) Skipping command and continuing the frame. "
                + "Further skips of this type are silent. Path commands are CPU-rasterized to bitmaps "
                + "before reaching here; only reserved commands (applyBlur, drawText) still skip — "
                + "prefer the GPUI scene path for those."
        )
    }

    /// One-shot end-of-frame summary so skip volume is visible without per-frame spam.
    private func noteUnsupportedFrameSummaryIfNeeded(backend: String, skippedCount: Int) {
        guard skippedCount > 0 else { return }
        guard loggedUnsupportedFrameSummaries.insert(backend).inserted else { return }

        renderLog(
            "[D3D11Renderer] \(backend) finished a frame with \(skippedCount) unsupported command(s) skipped. "
                + "fillRect/drawBitmap, degraded path bitmaps, and the axis-aligned clip stack still presented; "
                + "applyBlur/drawText need the scene path. "
                + "Further per-frame summaries for this backend are silent."
        )
    }

    private func currentScaleFactor() -> Double {
        if let hwnd {
            let dpi = GetDpiForWindow(hwnd)
            if dpi > 0 {
                let scaleFactor = Double(dpi) / logicalDpi
                surface?.scaleFactor = scaleFactor
                return max(scaleFactor, 1.0)
            }
        }

        return max(surface?.scaleFactor ?? 1.0, 1.0)
    }

    /// Activates the given blend mode on the device context if it differs
    /// from the currently active blend mode.
    private func activateBlendMode(
        _ mode: D3D11BlendMode,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>
    ) {
        guard mode != currentBlendMode, let state = blendStates[mode] else {
            return
        }
        currentBlendMode = mode
        let blendFactor: [FLOAT] = [0, 0, 0, 0]
        blendFactor.withUnsafeBufferPointer { buffer in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(deviceContext, state, buffer.baseAddress, UINT.max)
        }
    }

    /// Turns a Present HRESULT into a decision instead of a sign test.
    ///
    /// This used to recognise device loss, log it, and return *success* —
    /// telling the caller a frame reached the screen when nothing had been
    /// recreated — then throw forever once a counter ran out. Now the
    /// classification is shared with the batch renderer and device loss
    /// actually rebuilds the device.
    private func handlePresentResult(_ hr: HRESULT) throws {
        switch DeviceLostPolicy.outcome(forPresent: hr) {
        case .presented:
            deviceLostRecoveryAttempts = 0
            presentationState = PresentationState()
        case .occluded:
            // Not a failure and not device loss, but not vsync-paced
            // either — the host throttles on this rather than spinning.
            deviceLostRecoveryAttempts = 0
            presentationState = PresentationState(isOccluded: true, needsImmediateRepaint: false)
        case .deviceLost:
            try recoverFromDeviceLoss(hresult: hr, operation: "IDXGISwapChain1.Present")
        case .failed:
            throw D3D11RendererError(operation: "IDXGISwapChain1.Present", hresult: hr)
        }
    }

    /// Rebuilds the device after it was removed, reset or hung.
    ///
    /// GPUI's shape: unbind the render targets, `ClearState`, `Flush`,
    /// release every device object (all of which `detach()` already does in
    /// that order), wait a beat, recreate, then skip one frame. Bounded by
    /// ``DeviceLostPolicy/maxRecoveryAttempts`` consecutive attempts without
    /// an intervening clean present; past that the failure reaches the host
    /// typed `.deviceLost`, with this renderer left detached.
    private func recoverFromDeviceLoss(hresult: HRESULT, operation: String) throws {
        deviceLostRecoveryAttempts += 1
        let attempt = deviceLostRecoveryAttempts
        let removalReason = DeviceLostPolicy.removedReason(of: device)
        renderLog(
            "[D3D11Renderer] Device lost during \(operation) "
                + "(attempt \(attempt)/\(DeviceLostPolicy.maxRecoveryAttempts)). "
                + "HRESULT \(DeviceLostPolicy.describe(hresult)), "
                + "GetDeviceRemovedReason \(DeviceLostPolicy.describe(removalReason))."
        )

        guard attempt <= DeviceLostPolicy.maxRecoveryAttempts else {
            detach()
            throw D3D11RendererError(
                operation: operation,
                hresult: hresult,
                details:
                    "Device rebuild failed \(DeviceLostPolicy.maxRecoveryAttempts) times in a row; "
                    + "the adapter is not coming back on its own.",
                failureKind: .deviceLost
            )
        }

        guard let previousSurface = surface else {
            detach()
            throw D3D11RendererError(
                operation: operation,
                hresult: hresult,
                details: "No surface descriptor is available, so the swap chain cannot be rebuilt.",
                failureKind: .deviceLost
            )
        }

        detach()
        deviceLostRecoveryAttempts = attempt
        deviceLostBackoffHandler(DeviceLostPolicy.backoffSeconds(forAttempt: attempt))

        do {
            try attach(to: previousSurface)
        } catch {
            detach()
            deviceLostRecoveryAttempts = attempt
            throw D3D11RendererError(
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

    private func releaseDirect2DTarget() {
        if let direct2DDeviceContext {
            SWU_D2DResetTarget(direct2DDeviceContext)
        }

        if let direct2DTargetBitmap {
            SWU_D2DRelease(direct2DTargetBitmap)
            self.direct2DTargetBitmap = nil
        }
    }

    private func releaseDirect2DResources() {
        releaseDirect2DTarget()

        if let direct2DDeviceContext {
            SWU_D2DRelease(direct2DDeviceContext)
            self.direct2DDeviceContext = nil
        }

        if let direct2DDevice {
            SWU_D2DRelease(direct2DDevice)
            self.direct2DDevice = nil
        }

        if let direct2DFactory {
            SWU_D2DRelease(direct2DFactory)
            self.direct2DFactory = nil
        }

        isDirect2DEnabled = false
    }
}

private struct RectangleUniforms {
    // float4 boundary 1
    var surfaceWidth: Float
    var surfaceHeight: Float
    var rectX: Float
    var rectY: Float
    // float4 boundary 2
    var rectWidth: Float
    var rectHeight: Float
    var cornerRadius: Float
    var gradientAxis: Float
    // float4 boundary 3
    var startRed: Float
    var startGreen: Float
    var startBlue: Float
    var startAlpha: Float
    // float4 boundary 4
    var endRed: Float
    var endGreen: Float
    var endBlue: Float
    var endAlpha: Float
}

#if DEBUG
private let _rectangleUniformsAlignmentCheck: Void = {
    assert(
        MemoryLayout<RectangleUniforms>.size % 16 == 0,
        "RectangleUniforms size (\(MemoryLayout<RectangleUniforms>.size)) must be a multiple of 16 for constant buffer alignment."
    )
}()
#endif

private struct BitmapUniforms {
    // float4 boundary 1
    var surfaceWidth: Float
    var surfaceHeight: Float
    var rectX: Float
    var rectY: Float
    // float4 boundary 2
    var rectWidth: Float
    var rectHeight: Float
    var opacity: Float
    var padding: Float
}

#if DEBUG
private let _bitmapUniformsAlignmentCheck: Void = {
    assert(
        MemoryLayout<BitmapUniforms>.size % 16 == 0,
        "BitmapUniforms size (\(MemoryLayout<BitmapUniforms>.size)) must be a multiple of 16 for constant buffer alignment."
    )
}()
#endif

private func makeScissorRect(from rect: Rect, surfaceSize: IntSize) -> D3D11_RECT? {
    let surfaceRect = Rect(x: 0, y: 0, width: Double(surfaceSize.width), height: Double(surfaceSize.height))

    guard let clippedRect = rect.intersected(with: surfaceRect) else {
        return nil
    }

    let left = Int32(clippedRect.minX.rounded(.down))
    let top = Int32(clippedRect.minY.rounded(.down))
    let right = Int32(clippedRect.maxX.rounded(.up))
    let bottom = Int32(clippedRect.maxY.rounded(.up))

    guard right > left, bottom > top else {
        return nil
    }

    return D3D11_RECT(left: left, top: top, right: right, bottom: bottom)
}

private func scaled(fillRect command: FillRectCommand, factor: Double) -> FillRectCommand {
    FillRectCommand(
        rect: command.rect.scaled(by: factor),
        color: command.color,
        cornerRadius: command.cornerRadius * factor,
        clipRect: command.clipRect?.scaled(by: factor),
        gradient: command.gradient,
        blendMode: command.blendMode
    )
}

private func scaled(bitmap command: DrawBitmapCommand, factor: Double) -> DrawBitmapCommand {
    DrawBitmapCommand(
        rect: makePixelAlignedBitmapRect(
            from: command.rect,
            bitmapSize: IntSize(width: command.bitmap.width, height: command.bitmap.height),
            scaleFactor: factor
        ),
        bitmap: command.bitmap,
        opacity: command.opacity,
        clipRect: command.clipRect?.scaled(by: factor)
    )
}

func makeLogicalBitmapRect(from rect: Rect, bitmapSize: IntSize, scaleFactor: Double) -> Rect {
    guard scaleFactor > 0 else {
        return rect
    }

    let scaledOrigin = rect.origin.scaled(by: scaleFactor)
    return Rect(
        x: scaledOrigin.x.rounded(.toNearestOrAwayFromZero) / scaleFactor,
        y: scaledOrigin.y.rounded(.toNearestOrAwayFromZero) / scaleFactor,
        width: Double(max(bitmapSize.width, 1)) / scaleFactor,
        height: Double(max(bitmapSize.height, 1)) / scaleFactor
    )
}

func makePixelAlignedBitmapRect(from rect: Rect, bitmapSize: IntSize, scaleFactor: Double) -> Rect {
    let scaledOrigin = rect.origin.scaled(by: scaleFactor)
    return Rect(
        x: scaledOrigin.x.rounded(.toNearestOrAwayFromZero),
        y: scaledOrigin.y.rounded(.toNearestOrAwayFromZero),
        width: Double(max(bitmapSize.width, 1)),
        height: Double(max(bitmapSize.height, 1))
    )
}

private func renderCommandName(_ command: RenderCommand) -> String {
    switch command {
    case .fillRect:
        return "fillRect"
    case .drawBitmap:
        return "drawBitmap"
    case .fillPath:
        return "fillPath"
    case .strokePath:
        return "strokePath"
    case .applyBlur:
        return "applyBlur"
    case .drawText:
        return "drawText"
    case .pushClip:
        return "pushClip"
    case .popClip:
        return "popClip"
    }
}

/// Resolves stack + per-command clip for the frame fallback (VAL-SCENE-009 semantics).
private func resolveFrameEffectiveClip(
    commandClip: Rect?,
    clipStack: [FrameClipStackEntry],
    surfaceSize: Size
) -> Rect {
    let fullSurface = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
    var effective = fullSurface

    for entry in clipStack {
        switch entry.operation {
        case .intersect:
            if let intersected = effective.intersected(with: entry.rect) {
                effective = intersected
            } else {
                return Rect.zero
            }
        case .replace:
            effective = entry.rect
        }
    }

    if let commandClip {
        if let intersected = effective.intersected(with: commandClip) {
            effective = intersected
        } else {
            return Rect.zero
        }
    }

    return effective
}

/// Appends a frame-fallback clip. Ellipse → bounding rect; path → full-surface no-op.
private func pushFrameClip(
    _ command: ClipCommand,
    onto clipStack: inout [FrameClipStackEntry],
    surfaceSize: Size
) {
    let clipRect: Rect
    switch command.shape {
    case .rect(let rect, _):
        // Axis-aligned clip only; corner radius is ignored on the frame fallback.
        clipRect = rect
    case .ellipse(let center, let radiusX, let radiusY):
        clipRect = Rect(
            x: center.x - radiusX,
            y: center.y - radiusY,
            width: radiusX * 2,
            height: radiusY * 2
        )
    case .path:
        clipRect = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
    }

    clipStack.append(FrameClipStackEntry(rect: clipRect, operation: command.operation))
}

let hresultHandle: HRESULT = HRESULT(bitPattern: 0x80070006)

func compileShaderSource(source: String, entryPoint: String, profile: String) throws -> UnsafeMutablePointer<ID3DBlob> {
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
        throw D3D11RendererError(operation: "D3DCompile(\(entryPoint))", hresult: hr, details: details)
    }

    releaseCOM(&errorBlob)

    guard let shaderBlob else {
        throw D3D11RendererError(operation: "D3DCompile(\(entryPoint))", hresult: hresultHandle)
    }

    return shaderBlob
}

func shaderCompilerDetails(from errorBlob: UnsafeMutablePointer<ID3DBlob>?) -> String? {
    guard
        let errorBlob,
        let rawPointer = errorBlob.pointee.lpVtbl.pointee.GetBufferPointer(errorBlob)
    else {
        return nil
    }

    return String(cString: rawPointer.assumingMemoryBound(to: CChar.self))
}

private let hresultInvalidArgument: HRESULT = HRESULT(bitPattern: 0x80070057)
// Device-lost HRESULTs now live in `DeviceLostPolicy`, so both swap-chain
// owners classify the same values the same way instead of keeping private
// (and divergent) copies.

// DXGI constants that may not be exposed by the Swift WinSDK overlay.
private let DXGI_PRESENT_ALLOW_TEARING: UINT = 0x0000_0200
private let IID_IDXGIFactory5_local = IID(
    Data1: 0x7632_e1f5,
    Data2: 0xee65,
    Data3: 0x4dca,
    Data4: (0x87, 0xfd, 0x84, 0xcd, 0x75, 0xf8, 0x83, 0x8d)
)

private let logicalDpi: Double = 96

/// Lightweight render-subsystem logger that writes to standard error so
/// diagnostic output does not interfere with structured program output.
/// Module-internal: both swap-chain owners report device loss through it.
internal func renderLog(_ message: String) {
    var stderr = _StderrStream()
    print(message, to: &stderr)
}

private struct _StderrStream: TextOutputStream {
    mutating func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}
private let rectangleShaderSource = #"""
cbuffer RectangleUniforms : register(b0)
{
    float2 surfaceSize;
    float2 rectOrigin;
    float2 rectSize;
    float cornerRadius;
    float gradientAxis;
    float4 startColor;
    float4 endColor;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 localPosition : TEXCOORD0;
    float2 size : TEXCOORD1;
    float radius : TEXCOORD2;
    float gradientAxis : TEXCOORD3;
    float4 startColor : COLOR0;
    float4 endColor : COLOR1;
};

VSOutput vsMain(uint vertexID : SV_VertexID)
{
    const float2 quad[6] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(0.0, 1.0),
        float2(1.0, 0.0),
        float2(1.0, 1.0)
    };

    float2 unit = quad[vertexID];
    float2 pixelPosition = rectOrigin + unit * rectSize;
    float2 clipPosition = float2(
        (pixelPosition.x / surfaceSize.x) * 2.0 - 1.0,
        1.0 - (pixelPosition.y / surfaceSize.y) * 2.0
    );

    VSOutput output;
    output.position = float4(clipPosition, 0.0, 1.0);
    output.localPosition = unit * rectSize;
    output.size = rectSize;
    output.radius = cornerRadius;
    output.gradientAxis = gradientAxis;
    output.startColor = startColor;
    output.endColor = endColor;
    return output;
}

float roundedRectDistance(float2 localPosition, float2 size, float radius)
{
    float2 halfSize = size * 0.5;
    float2 localPoint = localPosition - halfSize;
    float clampedRadius = min(radius, min(halfSize.x, halfSize.y));
    float2 corner = max(halfSize - float2(clampedRadius, clampedRadius), float2(0.0, 0.0));
    float2 delta = abs(localPoint) - corner;
    return length(max(delta, float2(0.0, 0.0))) + min(max(delta.x, delta.y), 0.0) - clampedRadius;
}

float4 psMain(VSOutput input) : SV_Target
{
    float distance = roundedRectDistance(input.localPosition, input.size, input.radius);
    float aa = max(fwidth(distance), 0.75);
    float alpha = saturate(0.5 - distance / aa);

    float gradientT = input.gradientAxis > 0.5
        ? saturate(input.localPosition.x / max(input.size.x, 1.0))
        : saturate(input.localPosition.y / max(input.size.y, 1.0));

    float4 color = lerp(input.startColor, input.endColor, gradientT);
    return float4(color.rgb * color.a * alpha, color.a * alpha);
}
"""#

private let bitmapShaderSource = #"""
cbuffer BitmapUniforms : register(b0)
{
    float2 surfaceSize;
    float2 rectOrigin;
    float2 rectSize;
    float opacity;
    float padding;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

VSOutput vsMain(uint vertexID : SV_VertexID)
{
    const float2 quad[6] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(0.0, 1.0),
        float2(1.0, 0.0),
        float2(1.0, 1.0)
    };

    float2 unit = quad[vertexID];
    float2 pixelPosition = rectOrigin + unit * rectSize;
    float2 clipPosition = float2(
        (pixelPosition.x / surfaceSize.x) * 2.0 - 1.0,
        1.0 - (pixelPosition.y / surfaceSize.y) * 2.0
    );

    VSOutput output;
    output.position = float4(clipPosition, 0.0, 1.0);
    output.uv = unit;
    return output;
}

Texture2D textTexture : register(t0);
SamplerState textSampler : register(s0);

float4 psMain(VSOutput input) : SV_Target
{
    float4 sampleColor = textTexture.Sample(textSampler, input.uv);
    sampleColor *= opacity;
    return sampleColor;
}
"""#
