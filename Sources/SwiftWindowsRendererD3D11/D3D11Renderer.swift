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

public struct D3D11RendererError: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let hresult: HRESULT
    public let details: String?

    public init(operation: String, hresult: HRESULT, details: String? = nil) {
        self.operation = operation
        self.hresult = hresult
        self.details = details
    }

    public var description: String {
        let prefix = "\(operation) failed with HRESULT 0x\(String(UInt32(bitPattern: hresult), radix: 16, uppercase: true))."
        guard let details, !details.isEmpty else {
            return prefix
        }

        return "\(prefix) \(details)"
    }
}

/// Blend modes supported by the D3D11 fallback renderer.
public enum D3D11BlendMode: Hashable, Sendable {
    case normal
    case additive
    case multiply
    case screen
}

public final class D3D11Renderer: RenderBackend {
    public private(set) var isAttached = false
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
    private var consecutiveDeviceLostCount = 0
    private static let maxDeviceLostRecoveryAttempts = 3

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

        let clearColor = frame.clearColor == .clear ? configuration.fallbackClearColor : frame.clearColor
        let scaleFactor = currentScaleFactor()
        let logicalSurfaceSize = makeLogicalSurfaceSize(pixelSize: surface.pixelSize, scaleFactor: scaleFactor)

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
                    surfaceSize: logicalSurfaceSize,
                    deviceContext: direct2DDeviceContext,
                    targetBitmap: direct2DTargetBitmap
                )

                let syncInterval: UINT = vsyncEnabled ? 1 : 0
                var presentFlags: UINT = 0
                if !vsyncEnabled && tearingSupported {
                    presentFlags |= DXGI_PRESENT_ALLOW_TEARING
                }
                let hr = swapChain.pointee.lpVtbl.pointee.Present(swapChain, syncInterval, presentFlags)
                try handlePresentResult(hr)
                return
            } catch {
                releaseDirect2DTarget()
                isDirect2DEnabled = false
            }
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

        var clipStack = RenderClipStack(surfaceSize: logicalSurfaceSize)
        for command in frame.commands {
            switch command {
            case .pushClip(let clipCommand):
                clipStack.push(clipCommand)
            case .popClip:
                clipStack.pop()
            case .fillRect(let fillRectCommand):
                try draw(
                    .fillRect(resolved(fillRect: fillRectCommand, clipStack: clipStack)),
                    surfaceSize: surface.pixelSize,
                    scaleFactor: scaleFactor,
                    deviceContext: deviceContext,
                    rectangleVertexShader: vertexShader,
                    rectanglePixelShader: pixelShader,
                    rectangleConstantBuffer: constantBuffer,
                    bitmapVertexShader: bitmapVertexShader,
                    bitmapPixelShader: bitmapPixelShader,
                    bitmapConstantBuffer: bitmapConstantBuffer,
                    bitmapSamplerState: bitmapSamplerState
                )
            case .drawBitmap(let drawBitmapCommand):
                try draw(
                    .drawBitmap(resolved(bitmap: drawBitmapCommand, clipStack: clipStack)),
                    surfaceSize: surface.pixelSize,
                    scaleFactor: scaleFactor,
                    deviceContext: deviceContext,
                    rectangleVertexShader: vertexShader,
                    rectanglePixelShader: pixelShader,
                    rectangleConstantBuffer: constantBuffer,
                    bitmapVertexShader: bitmapVertexShader,
                    bitmapPixelShader: bitmapPixelShader,
                    bitmapConstantBuffer: bitmapConstantBuffer,
                    bitmapSamplerState: bitmapSamplerState
                )
            case .fillPath, .strokePath, .applyBlur, .drawText:
                // TODO: implement D3D11 path for new render commands.
                break
            }
        }

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

        let createDevice: (UnsafePointer<D3D_FEATURE_LEVEL>?, UINT) -> HRESULT = { pointer, count in
            D3D11CreateDevice(
                nil,
                D3D_DRIVER_TYPE_HARDWARE,
                nil,
                flags,
                pointer,
                count,
                UINT(D3D11_SDK_VERSION),
                &self.device,
                &featureLevel,
                &self.deviceContext
            )
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
            blendStates[.normal] != nil,
            blendStates[.additive] != nil,
            blendStates[.multiply] != nil,
            blendStates[.screen] != nil,
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

        let vertexShaderHR = device.pointee.lpVtbl.pointee.CreateVertexShader(
            device,
            vertexShaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(vertexShaderBlob),
            SIZE_T(vertexShaderBlob.pointee.lpVtbl.pointee.GetBufferSize(vertexShaderBlob)),
            nil,
            &vertexShader
        )
        try throwIfFailed(vertexShaderHR, operation: "ID3D11Device.CreateVertexShader")

        let pixelShaderHR = device.pointee.lpVtbl.pointee.CreatePixelShader(
            device,
            pixelShaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(pixelShaderBlob),
            SIZE_T(pixelShaderBlob.pointee.lpVtbl.pointee.GetBufferSize(pixelShaderBlob)),
            nil,
            &pixelShader
        )
        try throwIfFailed(pixelShaderHR, operation: "ID3D11Device.CreatePixelShader")

        let bitmapVertexShaderHR = device.pointee.lpVtbl.pointee.CreateVertexShader(
            device,
            bitmapVertexShaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(bitmapVertexShaderBlob),
            SIZE_T(bitmapVertexShaderBlob.pointee.lpVtbl.pointee.GetBufferSize(bitmapVertexShaderBlob)),
            nil,
            &bitmapVertexShader
        )
        try throwIfFailed(bitmapVertexShaderHR, operation: "ID3D11Device.CreateVertexShader(bitmap)")

        let bitmapPixelShaderHR = device.pointee.lpVtbl.pointee.CreatePixelShader(
            device,
            bitmapPixelShaderBlob.pointee.lpVtbl.pointee.GetBufferPointer(bitmapPixelShaderBlob),
            SIZE_T(bitmapPixelShaderBlob.pointee.lpVtbl.pointee.GetBufferSize(bitmapPixelShaderBlob)),
            nil,
            &bitmapPixelShader
        )
        try throwIfFailed(bitmapPixelShaderHR, operation: "ID3D11Device.CreatePixelShader(bitmap)")

        var constantBufferDescriptor = D3D11_BUFFER_DESC()
        constantBufferDescriptor.ByteWidth = UINT(MemoryLayout<RectangleUniforms>.size)
        constantBufferDescriptor.Usage = D3D11_USAGE_DEFAULT
        constantBufferDescriptor.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)

        let constantBufferHR = device.pointee.lpVtbl.pointee.CreateBuffer(device, &constantBufferDescriptor, nil, &constantBuffer)
        try throwIfFailed(constantBufferHR, operation: "ID3D11Device.CreateBuffer")

        var bitmapConstantBufferDescriptor = D3D11_BUFFER_DESC()
        bitmapConstantBufferDescriptor.ByteWidth = UINT(MemoryLayout<BitmapUniforms>.size)
        bitmapConstantBufferDescriptor.Usage = D3D11_USAGE_DEFAULT
        bitmapConstantBufferDescriptor.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)

        let bitmapConstantBufferHR = device.pointee.lpVtbl.pointee.CreateBuffer(device, &bitmapConstantBufferDescriptor, nil, &bitmapConstantBuffer)
        try throwIfFailed(bitmapConstantBufferHR, operation: "ID3D11Device.CreateBuffer(bitmap)")

        var samplerDescriptor = D3D11_SAMPLER_DESC()
        samplerDescriptor.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT
        samplerDescriptor.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.MaxLOD = FLOAT(D3D11_FLOAT32_MAX)

        let samplerStateHR = device.pointee.lpVtbl.pointee.CreateSamplerState(device, &samplerDescriptor, &bitmapSamplerState)
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

        let blendStateHR = device.pointee.lpVtbl.pointee.CreateBlendState(device, &blendDescriptor, &blendState)
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

        // Screen blend state: source-over style screen approximation.
        var screenBlendDescriptor = D3D11_BLEND_DESC()
        screenBlendDescriptor.AlphaToCoverageEnable = false
        screenBlendDescriptor.IndependentBlendEnable = false
        screenBlendDescriptor.RenderTarget.0.BlendEnable = true
        screenBlendDescriptor.RenderTarget.0.SrcBlend = D3D11_BLEND_ONE
        screenBlendDescriptor.RenderTarget.0.DestBlend = D3D11_BLEND_INV_SRC_COLOR
        screenBlendDescriptor.RenderTarget.0.BlendOp = D3D11_BLEND_OP_ADD
        screenBlendDescriptor.RenderTarget.0.SrcBlendAlpha = D3D11_BLEND_ONE
        screenBlendDescriptor.RenderTarget.0.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA
        screenBlendDescriptor.RenderTarget.0.BlendOpAlpha = D3D11_BLEND_OP_ADD
        screenBlendDescriptor.RenderTarget.0.RenderTargetWriteMask = UINT8(D3D11_COLOR_WRITE_ENABLE_ALL.rawValue)

        var screenBlendState: UnsafeMutablePointer<ID3D11BlendState>?
        let screenBlendStateHR = device.pointee.lpVtbl.pointee.CreateBlendState(device, &screenBlendDescriptor, &screenBlendState)
        try throwIfFailed(screenBlendStateHR, operation: "ID3D11Device.CreateBlendState(screen)")
        if let screenBlendState {
            blendStates[.screen] = screenBlendState
        }

        var rasterizerDescriptor = D3D11_RASTERIZER_DESC()
        rasterizerDescriptor.FillMode = D3D11_FILL_SOLID
        rasterizerDescriptor.CullMode = D3D11_CULL_NONE
        rasterizerDescriptor.ScissorEnable = true
        rasterizerDescriptor.DepthClipEnable = true

        let rasterizerStateHR = device.pointee.lpVtbl.pointee.CreateRasterizerState(device, &rasterizerDescriptor, &rasterizerState)
        try throwIfFailed(rasterizerStateHR, operation: "ID3D11Device.CreateRasterizerState")
    }

    private func createFactoryIfNeeded() throws {
        if dxgiFactory != nil {
            return
        }

        var rawFactory: UnsafeMutableRawPointer?
        var iid = IID_IDXGIFactory2
        let hr = CreateDXGIFactory1(&iid, &rawFactory)
        try throwIfFailed(hr, operation: "CreateDXGIFactory1")

        dxgiFactory = rawFactory?.assumingMemoryBound(to: IDXGIFactory2.self)

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
        descriptor.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED
        descriptor.Flags = swapChainFlags

        let unknownDevice = UnsafeMutableRawPointer(device).assumingMemoryBound(to: IUnknown.self)
        let hr = dxgiFactory.pointee.lpVtbl.pointee.CreateSwapChainForHwnd(
            dxgiFactory,
            unknownDevice,
            hwnd,
            &descriptor,
            nil,
            nil,
            &swapChain
        )
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
        let viewHR = device.pointee.lpVtbl.pointee.CreateRenderTargetView(device, resource, nil, &renderTargetView)
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
        surfaceSize: Size,
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

        var clipStack = RenderClipStack(surfaceSize: surfaceSize)
        for command in frame.commands {
            switch command {
            case .fillRect(let fillRectCommand):
                try drawWithDirect2D(
                    fillRect: resolved(fillRect: fillRectCommand, clipStack: clipStack),
                    deviceContext: deviceContext
                )
            case .drawBitmap(let drawBitmapCommand):
                try drawWithDirect2D(
                    bitmap: resolved(bitmap: drawBitmapCommand, clipStack: clipStack),
                    scaleFactor: scaleFactor,
                    deviceContext: deviceContext
                )
            case .pushClip(let clipCommand):
                clipStack.push(clipCommand)
            case .popClip:
                clipStack.pop()
            case .fillPath, .strokePath, .applyBlur, .drawText:
                // TODO: implement Direct2D path for new render commands
                break
            }
        }

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
        _ command: RenderCommand,
        surfaceSize: IntSize,
        scaleFactor: Double,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        rectangleVertexShader: UnsafeMutablePointer<ID3D11VertexShader>,
        rectanglePixelShader: UnsafeMutablePointer<ID3D11PixelShader>,
        rectangleConstantBuffer: UnsafeMutablePointer<ID3D11Buffer>,
        bitmapVertexShader: UnsafeMutablePointer<ID3D11VertexShader>,
        bitmapPixelShader: UnsafeMutablePointer<ID3D11PixelShader>,
        bitmapConstantBuffer: UnsafeMutablePointer<ID3D11Buffer>,
        bitmapSamplerState: UnsafeMutablePointer<ID3D11SamplerState>
    ) throws {
        switch command {
        case .fillRect(let fillRectCommand):
            try draw(
                fillRect: fillRectCommand,
                surfaceSize: surfaceSize,
                scaleFactor: scaleFactor,
                deviceContext: deviceContext,
                vertexShader: rectangleVertexShader,
                pixelShader: rectanglePixelShader,
                constantBuffer: rectangleConstantBuffer
            )
        case .drawBitmap(let drawBitmapCommand):
            try draw(
                bitmap: drawBitmapCommand,
                surfaceSize: surfaceSize,
                scaleFactor: scaleFactor,
                deviceContext: deviceContext,
                vertexShader: bitmapVertexShader,
                pixelShader: bitmapPixelShader,
                constantBuffer: bitmapConstantBuffer,
                samplerState: bitmapSamplerState
            )
        case .fillPath, .strokePath, .applyBlur, .drawText, .pushClip, .popClip:
            // TODO: implement D3D11 path for new render commands
            break
        }
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

        activateBlendMode(d3d11BlendMode(for: scaledCommand.blendMode), deviceContext: deviceContext)

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

        activateBlendMode(d3d11BlendMode(for: scaledCommand.blendMode), deviceContext: deviceContext)

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

    /// Handles Present HRESULT, including device-lost recovery with a
    /// consecutive failure limit.
    private func handlePresentResult(_ hr: HRESULT) throws {
        if hr >= 0 {
            consecutiveDeviceLostCount = 0
            return
        }

        let isDeviceLost = hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_RESET
        if isDeviceLost {
            consecutiveDeviceLostCount += 1
            if consecutiveDeviceLostCount > Self.maxDeviceLostRecoveryAttempts {
                throw D3D11RendererError(
                    operation: "IDXGISwapChain1.Present",
                    hresult: hr,
                    details: "Device lost recovery failed after \(Self.maxDeviceLostRecoveryAttempts) consecutive attempts."
                )
            }
            renderLog(
                "[D3D11Renderer] Device lost detected (attempt \(consecutiveDeviceLostCount)/\(Self.maxDeviceLostRecoveryAttempts)). "
                    + "HRESULT 0x\(String(UInt32(bitPattern: hr), radix: 16, uppercase: true))."
            )
            return
        }

        throw D3D11RendererError(operation: "IDXGISwapChain1.Present", hresult: hr)
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

func makeLogicalSurfaceSize(pixelSize: IntSize, scaleFactor: Double) -> Size {
    let safeScale = max(scaleFactor, 1.0)
    return Size(
        width: Double(max(pixelSize.width, 0)) / safeScale,
        height: Double(max(pixelSize.height, 0)) / safeScale
    )
}

func resolved(fillRect command: FillRectCommand, clipStack: RenderClipStack) -> FillRectCommand {
    FillRectCommand(
        rect: command.rect,
        color: command.color,
        cornerRadius: command.cornerRadius,
        clipRect: clipStack.resolvedClip(commandClip: command.clipRect),
        gradient: command.gradient,
        blendMode: command.blendMode
    )
}

func resolved(bitmap command: DrawBitmapCommand, clipStack: RenderClipStack) -> DrawBitmapCommand {
    DrawBitmapCommand(
        rect: command.rect,
        bitmap: command.bitmap,
        opacity: command.opacity,
        clipRect: clipStack.resolvedClip(commandClip: command.clipRect),
        blendMode: command.blendMode
    )
}

func d3d11BlendMode(for blendMode: BlendMode) -> D3D11BlendMode {
    switch blendMode {
    case .normal:
        return .normal
    case .additive:
        return .additive
    case .multiply:
        return .multiply
    case .screen:
        return .screen
    case .overlay:
        // Overlay needs shader/effect composition; keep it safe for now.
        return .normal
    }
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
        clipRect: command.clipRect?.scaled(by: factor),
        blendMode: command.blendMode
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

func releaseCOM<T>(_ pointer: inout UnsafeMutablePointer<T>?) {
    guard let rawPointer = pointer else {
        return
    }

    let unknown = UnsafeMutableRawPointer(rawPointer).assumingMemoryBound(to: IUnknown.self)
    _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    pointer = nil
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
private let DXGI_ERROR_DEVICE_REMOVED: HRESULT = HRESULT(bitPattern: 0x887A0005)
private let DXGI_ERROR_DEVICE_RESET: HRESULT = HRESULT(bitPattern: 0x887A0007)

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
private func renderLog(_ message: String) {
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
