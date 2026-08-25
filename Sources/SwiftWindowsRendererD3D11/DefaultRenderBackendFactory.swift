import Foundation

// MARK: - D3D11 Render Backend Factory

/// Factory that produces D3D11 graphics-device renderers. The Windows product
/// selects it in its executable composition root; the app-facing facade stays
/// renderer-neutral and defaults to its presenting software factory.
import SwiftWindowsGraphics
import WinSDK

// MARK: - Legacy Default Factory (deprecated, use D3D11RenderBackendFactory)

@MainActor
public struct D3D11RenderBackendFactory: RenderBackendFactory {
    public init() {}

    public var factoryName: String { "D3D11 GPU" }

    /// A graphics-device API is not proof of hardware acceleration: when the
    /// hardware adapter is unavailable this same factory can run through WARP.
    public var capabilities: RenderBackendCapabilities { .graphicsDeviceWindow }

    public func makeRenderBackend() -> any RenderBackend {
        D3D11Renderer()
    }

    /// Create a batch-capable renderer, if one is available.
    ///
    /// The scene/batch renderer is the promoted default presenter. The host
    /// keeps the frame renderer attached as an explicit debug/fallback path.
    public func makeBatchRenderBackend() -> (any BatchRenderBackend)? {
        D3D11BatchRenderer()
    }

    /// Asks D3D11 whether a device *could* be created, without creating one:
    /// passing `nil` for the device out-param is the documented capability
    /// query. Hardware first, then WARP — the same order the renderers
    /// themselves use — so the answer matches what `attach` will do.
    public func probeAvailability() -> RenderBackendAvailability {
        if Self.canCreateDevice(driverType: D3D_DRIVER_TYPE_HARDWARE) {
            return .available
        }

        if Self.canCreateDevice(driverType: D3D_DRIVER_TYPE_WARP) {
            return .degraded(
                reason: "No D3D11 hardware adapter is usable; presentation would run on the WARP software rasterizer."
            )
        }

        return .unavailable(reason: "D3D11CreateDevice failed for both the hardware adapter and WARP.")
    }

    private static func canCreateDevice(driverType: D3D_DRIVER_TYPE) -> Bool {
        let flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)
        var featureLevels: [D3D_FEATURE_LEVEL] = [D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0]
        let hr = featureLevels.withUnsafeMutableBufferPointer { buffer in
            D3D11CreateDevice(
                nil,
                driverType,
                nil,
                flags,
                buffer.baseAddress,
                UINT(buffer.count),
                UINT(D3D11_SDK_VERSION),
                nil,
                nil,
                nil
            )
        }

        if hr >= 0 {
            return true
        }

        // A pre-11_1 driver rejects the whole call rather than negotiating
        // down, exactly as in `createDeviceIfNeeded`.
        guard hr == HRESULT(bitPattern: 0x8007_0057) else {
            return false
        }

        var legacyLevels: [D3D_FEATURE_LEVEL] = [D3D_FEATURE_LEVEL_11_0]
        let legacyHR = legacyLevels.withUnsafeMutableBufferPointer { buffer in
            D3D11CreateDevice(
                nil,
                driverType,
                nil,
                flags,
                buffer.baseAddress,
                UINT(buffer.count),
                UINT(D3D11_SDK_VERSION),
                nil,
                nil,
                nil
            )
        }
        return legacyHR >= 0
    }
}
@MainActor
public enum DefaultRenderBackendFactory {
    public static func make() -> any RenderBackend {
        D3D11Renderer()
    }

    public static func makeBatchBackend() -> (any BatchRenderBackend)? {
        D3D11BatchRenderer()
    }
}
