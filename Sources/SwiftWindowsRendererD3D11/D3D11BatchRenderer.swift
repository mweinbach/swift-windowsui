import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX

// MARK: - D3D11BatchRenderer

/// Instanced batch renderer using StructuredBuffer-based instanced draw calls.
/// Instead of one draw call per rectangle, all primitives of the same type are
/// uploaded to a single GPU buffer and drawn in one DrawInstanced call.
@MainActor
public final class D3D11BatchRenderer: BatchRenderBackend {
    public private(set) var isAttached = false

    public var backendDisplayName: String { "D3D11 BATCH" }

    // MARK: - D3D11 Core State

    private var device: UnsafeMutablePointer<ID3D11Device>?
    private var deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>?
    private var dxgiFactory: UnsafeMutablePointer<IDXGIFactory2>?
    private var swapChain: UnsafeMutablePointer<IDXGISwapChain1>?
    private var renderTargetView: UnsafeMutablePointer<ID3D11RenderTargetView>?

    // MARK: - Shader Pipeline State

    private var quadVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var quadPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var imageVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var imagePS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var shadowVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var shadowPS: UnsafeMutablePointer<ID3D11PixelShader>?

    // MARK: - Shared GPU Resources

    private var frameUniformBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var blendState: UnsafeMutablePointer<ID3D11BlendState>?
    private var rasterizerState: UnsafeMutablePointer<ID3D11RasterizerState>?
    private var samplerState: UnsafeMutablePointer<ID3D11SamplerState>?

    // MARK: - Dynamic Instance Buffers

    private var quadInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var quadInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var quadInstanceCapacity: Int = 256

    private var imageInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var imageInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var imageInstanceCapacity: Int = 256

    private var shadowInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var shadowInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var shadowInstanceCapacity: Int = 256

    // MARK: - Surface State

    private var surface: SurfaceDescriptor?
    private var hwnd: HWND?

    // MARK: - Init

    public init() {}

    // MARK: - BatchRenderBackend

    public func attach(to surface: SurfaceDescriptor) throws {
        guard let hwnd = unsafeBitCast(surface.windowHandle.rawPointer, to: HWND?.self) else {
            throw BatchRendererError(operation: "Resolve HWND", hresult: batchHresultHandle)
        }

        self.surface = surface
        self.hwnd = hwnd

        try createDeviceIfNeeded()
        try createFactoryIfNeeded()
        try createPipelineIfNeeded()
        try createSwapChain(size: surface.pixelSize)
        try createRenderTargetView()

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

        releaseCOMPointer(&renderTargetView)
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
    }

    public func render(scene: GPUIScene) throws {
        guard isAttached, let swapChain, let surface else {
            return
        }

        if surface.pixelSize.width <= 0 || surface.pixelSize.height <= 0 {
            return
        }

        guard
            let renderTargetView,
            let deviceContext,
            let blendState,
            let rasterizerState,
            let frameUniformBuffer
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
        deviceContext.pointee.lpVtbl.pointee.IASetInputLayout(deviceContext, nil)
        deviceContext.pointee.lpVtbl.pointee.IASetPrimitiveTopology(deviceContext, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST)

        let blendFactor: [FLOAT] = [0, 0, 0, 0]
        blendFactor.withUnsafeBufferPointer { buffer in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(deviceContext, blendState, buffer.baseAddress, UINT.max)
        }

        let cc = scene.clearColor
        let clearValues: [FLOAT] = [cc.red, cc.green, cc.blue, cc.alpha]
        clearValues.withUnsafeBufferPointer { buffer in
            deviceContext.pointee.lpVtbl.pointee.ClearRenderTargetView(deviceContext, renderTargetView, buffer.baseAddress)
        }

        try updateFrameUniforms(surfaceSize: surface.pixelSize)

        var cbuf: UnsafeMutablePointer<ID3D11Buffer>? = frameUniformBuffer
        deviceContext.pointee.lpVtbl.pointee.VSSetConstantBuffers(deviceContext, 0, 1, &cbuf)

        for layer in scene.layers {
            if !layer.shadows.isEmpty {
                try renderBatch(
                    layer.shadows,
                    capacity: &shadowInstanceCapacity,
                    buffer: &shadowInstanceBuffer,
                    srv: &shadowInstanceSRV,
                    vs: shadowVS, ps: shadowPS,
                    label: "shadow",
                    deviceContext: deviceContext
                )
            }
            if !layer.quads.isEmpty {
                try renderBatch(
                    layer.quads,
                    capacity: &quadInstanceCapacity,
                    buffer: &quadInstanceBuffer,
                    srv: &quadInstanceSRV,
                    vs: quadVS, ps: quadPS,
                    label: "quad",
                    deviceContext: deviceContext
                )
            }
            if !layer.images.isEmpty {
                try renderBatch(
                    layer.images,
                    capacity: &imageInstanceCapacity,
                    buffer: &imageInstanceBuffer,
                    srv: &imageInstanceSRV,
                    vs: imageVS, ps: imagePS,
                    label: "image",
                    deviceContext: deviceContext,
                    bindSampler: true
                )
            }
        }

        let hr = swapChain.pointee.lpVtbl.pointee.Present(swapChain, 1, 0)
        if hr < 0 {
            throw BatchRendererError(operation: "IDXGISwapChain1.Present", hresult: hr)
        }
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
        releaseCOMPointer(&shadowPSBlob)
        releaseCOMPointer(&shadowVSBlob)
        releaseCOMPointer(&imagePSBlob)
        releaseCOMPointer(&imageVSBlob)
        releaseCOMPointer(&quadPSBlob)
        releaseCOMPointer(&quadVSBlob)
    }

    // MARK: - Device Creation

    private func createDeviceIfNeeded() throws {
        if device != nil && deviceContext != nil {
            return
        }

        let flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)
        var featureLevel = D3D_FEATURE_LEVEL(0)

        var featureLevels: [D3D_FEATURE_LEVEL] = [
            D3D_FEATURE_LEVEL_11_1,
            D3D_FEATURE_LEVEL_11_0,
        ]

        let hr = featureLevels.withUnsafeBufferPointer { buffer in
            D3D11CreateDevice(
                nil,
                D3D_DRIVER_TYPE_HARDWARE,
                nil,
                flags,
                buffer.baseAddress,
                UINT(buffer.count),
                UINT(D3D11_SDK_VERSION),
                &self.device,
                &featureLevel,
                &self.deviceContext
            )
        }

        if hr == batchHresultInvalidArgument {
            featureLevels.removeFirst()
            let fallbackHR = featureLevels.withUnsafeBufferPointer { buffer in
                D3D11CreateDevice(
                    nil,
                    D3D_DRIVER_TYPE_HARDWARE,
                    nil,
                    flags,
                    buffer.baseAddress,
                    UINT(buffer.count),
                    UINT(D3D11_SDK_VERSION),
                    &self.device,
                    &featureLevel,
                    &self.deviceContext
                )
            }
            try throwIfFailed(fallbackHR, operation: "D3D11CreateDevice")
        } else {
            try throwIfFailed(hr, operation: "D3D11CreateDevice")
        }
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
        descriptor.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED
        descriptor.Flags = 0

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
        let viewHR = device.pointee.lpVtbl.pointee.CreateRenderTargetView(device, resource, nil, &renderTargetView)
        var releasableTexture: UnsafeMutablePointer<ID3D11Texture2D>? = texture
        releaseCOMPointer(&releasableTexture)
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
            source: batchShadowShaderSource,
            vs: &shadowVS,
            ps: &shadowPS,
            label: "shadow"
        )

        var uniformDesc = D3D11_BUFFER_DESC()
        uniformDesc.ByteWidth = 16
        uniformDesc.Usage = D3D11_USAGE_DEFAULT
        uniformDesc.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)

        let uniformHR = device.pointee.lpVtbl.pointee.CreateBuffer(device, &uniformDesc, nil, &frameUniformBuffer)
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

        let blendHR = device.pointee.lpVtbl.pointee.CreateBlendState(device, &blendDescriptor, &blendState)
        try throwIfFailed(blendHR, operation: "ID3D11Device.CreateBlendState")

        var rasterizerDescriptor = D3D11_RASTERIZER_DESC()
        rasterizerDescriptor.FillMode = D3D11_FILL_SOLID
        rasterizerDescriptor.CullMode = D3D11_CULL_NONE
        rasterizerDescriptor.ScissorEnable = false
        rasterizerDescriptor.DepthClipEnable = true

        let rasterizerHR = device.pointee.lpVtbl.pointee.CreateRasterizerState(device, &rasterizerDescriptor, &rasterizerState)
        try throwIfFailed(rasterizerHR, operation: "ID3D11Device.CreateRasterizerState")

        var samplerDescriptor = D3D11_SAMPLER_DESC()
        samplerDescriptor.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR
        samplerDescriptor.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.MaxLOD = FLOAT(D3D11_FLOAT32_MAX)

        let samplerHR = device.pointee.lpVtbl.pointee.CreateSamplerState(device, &samplerDescriptor, &samplerState)
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
        defer { releaseCOMPointer(&vsBlob) }

        var psBlob: UnsafeMutablePointer<ID3DBlob>? = try Self.compileShaderSource(
            source: source, entryPoint: "psMain", profile: "ps_5_0")
        defer { releaseCOMPointer(&psBlob) }

        guard let vsBlob, let psBlob else {
            throw BatchRendererError(operation: "Compile \(label) shaders", hresult: batchHresultHandle)
        }

        let vsHR = device.pointee.lpVtbl.pointee.CreateVertexShader(
            device,
            vsBlob.pointee.lpVtbl.pointee.GetBufferPointer(vsBlob),
            SIZE_T(vsBlob.pointee.lpVtbl.pointee.GetBufferSize(vsBlob)),
            nil,
            &vs
        )
        try throwIfFailed(vsHR, operation: "ID3D11Device.CreateVertexShader(\(label))")

        let psHR = device.pointee.lpVtbl.pointee.CreatePixelShader(
            device,
            psBlob.pointee.lpVtbl.pointee.GetBufferPointer(psBlob),
            SIZE_T(psBlob.pointee.lpVtbl.pointee.GetBufferSize(psBlob)),
            nil,
            &ps
        )
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
            releaseCOMPointer(&errorBlob)
            throw BatchRendererError(operation: "D3DCompile(\(entryPoint))", hresult: hr, details: details)
        }

        releaseCOMPointer(&errorBlob)

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
        releaseCOMPointer(&srv)
        releaseCOMPointer(&buffer)

        var bufferDesc = D3D11_BUFFER_DESC()
        bufferDesc.ByteWidth = UINT(capacity * strideBytes)
        bufferDesc.Usage = D3D11_USAGE_DYNAMIC
        bufferDesc.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)
        bufferDesc.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_WRITE.rawValue)
        bufferDesc.MiscFlags = UINT(D3D11_RESOURCE_MISC_BUFFER_STRUCTURED.rawValue)
        bufferDesc.StructureByteStride = UINT(strideBytes)

        let bufHR = device.pointee.lpVtbl.pointee.CreateBuffer(device, &bufferDesc, nil, &buffer)
        try throwIfFailed(bufHR, operation: "ID3D11Device.CreateBuffer(\(label) instances)")

        guard let buffer else {
            throw BatchRendererError(operation: "CreateBuffer(\(label))", hresult: batchHresultHandle)
        }

        var srvDesc = D3D11_SHADER_RESOURCE_VIEW_DESC()
        srvDesc.Format = DXGI_FORMAT_UNKNOWN
        srvDesc.ViewDimension = D3D11_SRV_DIMENSION_BUFFER
        // Set Buffer.FirstElement and Buffer.NumElements via raw memory
        // (the union layout varies across WinSDK Swift overlay versions).
        withUnsafeMutableBytes(of: &srvDesc) { raw in
            let unionOffset = MemoryLayout<DXGI_FORMAT>.stride + MemoryLayout<D3D_SRV_DIMENSION>.stride
            raw.storeBytes(of: UINT(0), toByteOffset: unionOffset, as: UINT.self)
            raw.storeBytes(of: UINT(capacity), toByteOffset: unionOffset + MemoryLayout<UINT>.stride, as: UINT.self)
        }

        let resource = UnsafeMutableRawPointer(buffer).assumingMemoryBound(to: ID3D11Resource.self)
        let srvHR = device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, &srvDesc, &srv)
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
        buffer: UnsafeMutablePointer<ID3D11Buffer>,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>
    ) throws {
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

        _ = instances.withUnsafeBytes { source in
            memcpy(pData, source.baseAddress, source.count)
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

    // MARK: - Render Batches

    /// Unified batch draw: uploads instances to a structured buffer, binds
    /// shaders and SRV, issues a single DrawInstanced call, then unbinds.
    private func renderBatch<T>(
        _ instances: [T],
        capacity: inout Int,
        buffer: inout UnsafeMutablePointer<ID3D11Buffer>?,
        srv: inout UnsafeMutablePointer<ID3D11ShaderResourceView>?,
        vs: UnsafeMutablePointer<ID3D11VertexShader>?,
        ps: UnsafeMutablePointer<ID3D11PixelShader>?,
        label: String,
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        bindSampler: Bool = false
    ) throws {
        try ensureInstanceBufferCapacity(
            count: instances.count,
            capacity: &capacity,
            strideBytes: MemoryLayout<T>.stride,
            buffer: &buffer,
            srv: &srv,
            label: label
        )

        guard let buffer, let srv else { return }

        try uploadInstances(instances, buffer: buffer, deviceContext: deviceContext)

        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, vs, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, ps, nil, 0)

        var srvPtr: UnsafeMutablePointer<ID3D11ShaderResourceView>? = srv
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &srvPtr)

        if bindSampler {
            var samplerPtr: UnsafeMutablePointer<ID3D11SamplerState>? = samplerState
            deviceContext.pointee.lpVtbl.pointee.PSSetSamplers(deviceContext, 0, 1, &samplerPtr)
        }

        deviceContext.pointee.lpVtbl.pointee.DrawInstanced(deviceContext, 6, UINT(instances.count), 0, 0)

        var nullSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = nil
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &nullSRV)
    }

    // MARK: - Helpers

    private func throwIfFailed(_ hr: HRESULT, operation: String) throws {
        if hr < 0 {
            throw BatchRendererError(operation: operation, hresult: hr)
        }
    }
}

// MARK: - Error Type

public struct BatchRendererError: Error, CustomStringConvertible, Sendable {
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

// MARK: - Private Helpers

private func releaseCOMPointer<T>(_ pointer: inout UnsafeMutablePointer<T>?) {
    guard let rawPointer = pointer else {
        return
    }

    let unknown = UnsafeMutableRawPointer(rawPointer).assumingMemoryBound(to: IUnknown.self)
    _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    pointer = nil
}

private let batchHresultHandle: HRESULT = HRESULT(bitPattern: 0x80070006)
private let batchHresultInvalidArgument: HRESULT = HRESULT(bitPattern: 0x80070057)
