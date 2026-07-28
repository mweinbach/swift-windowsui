import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX
import XCTest

@testable import SwiftWindowsRendererD3D11

/// The one WARP harness every GPU-backed test in this target shares.
///
/// WARP first, hardware second: the software rasterizer ships with every
/// Windows install and produces the same pixels on every machine, which is
/// what pixel assertions need; a real GPU is only a fallback. When neither
/// exists the helpers throw `XCTSkip`, so a machine without D3D11 reports
/// skipped GPU tests rather than failures.
///
/// Two levels are available:
///
/// - ``WARPDevice`` plus ``makeWARPOffscreenTarget(device:width:height:pixels:)``
///   and ``readWARPPixels(device:target:)`` for tests that drive a single
///   component against a bare `ID3D11Device` (the backdrop blur engine, the
///   glyph draw).
/// - ``WARPBatchRenderer`` for tests that need the real
///   `D3D11BatchRenderer` frame path — attach, resize, render, present,
///   readback — with no HWND anywhere.

// MARK: - Headless Device

/// Owns a headless D3D11 device + context and releases them explicitly
/// (COM teardown stays on the main actor).
@MainActor
final class WARPDevice {
    var device: UnsafeMutablePointer<ID3D11Device>?
    var context: UnsafeMutablePointer<ID3D11DeviceContext>?

    func release() {
        if let context {
            let unknown = UnsafeMutableRawPointer(context).assumingMemoryBound(to: IUnknown.self)
            _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
            self.context = nil
        }
        if let device {
            let unknown = UnsafeMutableRawPointer(device).assumingMemoryBound(to: IUnknown.self)
            _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
            self.device = nil
        }
    }
}

@MainActor
func makeWARPDevice() throws -> WARPDevice {
    let result = WARPDevice()
    var featureLevel = D3D_FEATURE_LEVEL(0)
    let featureLevels: [D3D_FEATURE_LEVEL] = [D3D_FEATURE_LEVEL_11_0]
    let flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)

    for driverType in [D3D_DRIVER_TYPE_WARP, D3D_DRIVER_TYPE_HARDWARE] {
        let hr = featureLevels.withUnsafeBufferPointer { buffer in
            D3D11CreateDevice(
                nil,
                driverType,
                nil,
                flags,
                buffer.baseAddress,
                UINT(buffer.count),
                UINT(D3D11_SDK_VERSION),
                &result.device,
                &featureLevel,
                &result.context
            )
        }
        if hr >= 0, result.device != nil, result.context != nil {
            return result
        }
    }

    throw XCTSkip("No D3D11 device (WARP or hardware) is available on this machine")
}

// MARK: - Offscreen Target

/// An offscreen render target standing in for the swap-chain backbuffer
/// (same B8G8R8A8 format), pre-filled with caller pixels.
struct WARPOffscreenTarget {
    var texture: UnsafeMutablePointer<ID3D11Texture2D>?
    var rtv: UnsafeMutablePointer<ID3D11RenderTargetView>?
    let width: Int
    let height: Int

    func release() {
        if let rtv {
            let unknown = UnsafeMutableRawPointer(rtv).assumingMemoryBound(to: IUnknown.self)
            _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        }
        if let texture {
            let unknown = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: IUnknown.self)
            _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        }
    }
}

@MainActor
func makeWARPOffscreenTarget(
    device: WARPDevice,
    width: Int,
    height: Int,
    pixels: [UInt8]
) throws -> WARPOffscreenTarget {
    guard let d3dDevice = device.device, let context = device.context else {
        throw XCTSkip("Headless device unavailable")
    }
    XCTAssertEqual(pixels.count, width * height * 4, "BGRA pixel buffer size mismatch")

    var descriptor = D3D11_TEXTURE2D_DESC()
    descriptor.Width = UINT(width)
    descriptor.Height = UINT(height)
    descriptor.MipLevels = 1
    descriptor.ArraySize = 1
    descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
    descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
    descriptor.Usage = D3D11_USAGE_DEFAULT
    descriptor.BindFlags = UINT(D3D11_BIND_RENDER_TARGET.rawValue)

    var target = WARPOffscreenTarget(texture: nil, rtv: nil, width: width, height: height)
    let textureHR = d3dDevice.pointee.lpVtbl.pointee.CreateTexture2D(d3dDevice, &descriptor, nil, &target.texture)
    XCTAssertGreaterThanOrEqual(
        textureHR, 0, "CreateTexture2D failed: 0x\(String(UInt32(bitPattern: textureHR), radix: 16))")
    let texture = try XCTUnwrap(target.texture)

    pixels.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return }
        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        context.pointee.lpVtbl.pointee.UpdateSubresource(
            context, resource, 0, nil, baseAddress, UINT(width * 4), 0)
    }

    let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
    let rtvHR = d3dDevice.pointee.lpVtbl.pointee.CreateRenderTargetView(d3dDevice, resource, nil, &target.rtv)
    XCTAssertGreaterThanOrEqual(rtvHR, 0, "CreateRenderTargetView failed")
    _ = try XCTUnwrap(target.rtv)
    return target
}

/// Reads the target's pixels back through a staging texture.
@MainActor
func readWARPPixels(
    device: WARPDevice,
    target: WARPOffscreenTarget
) throws -> [UInt8] {
    guard let d3dDevice = device.device, let context = device.context, let texture = target.texture else {
        throw XCTSkip("Headless device unavailable")
    }

    var descriptor = D3D11_TEXTURE2D_DESC()
    descriptor.Width = UINT(target.width)
    descriptor.Height = UINT(target.height)
    descriptor.MipLevels = 1
    descriptor.ArraySize = 1
    descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
    descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
    descriptor.Usage = D3D11_USAGE_STAGING
    descriptor.BindFlags = 0
    descriptor.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_READ.rawValue)

    var staging: UnsafeMutablePointer<ID3D11Texture2D>?
    let createHR = d3dDevice.pointee.lpVtbl.pointee.CreateTexture2D(d3dDevice, &descriptor, nil, &staging)
    XCTAssertGreaterThanOrEqual(createHR, 0, "CreateTexture2D(staging) failed")
    let stagingTexture = try XCTUnwrap(staging)
    defer {
        let unknown = UnsafeMutableRawPointer(stagingTexture).assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    }

    let dstResource = UnsafeMutableRawPointer(stagingTexture).assumingMemoryBound(to: ID3D11Resource.self)
    let srcResource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
    context.pointee.lpVtbl.pointee.CopyResource(context, dstResource, srcResource)

    var mapped = D3D11_MAPPED_SUBRESOURCE()
    let mapHR = context.pointee.lpVtbl.pointee.Map(context, dstResource, 0, D3D11_MAP_READ, 0, &mapped)
    XCTAssertGreaterThanOrEqual(mapHR, 0, "Map(staging) failed")
    let pData = try XCTUnwrap(mapped.pData)
    var pixels = [UInt8](repeating: 0, count: target.width * target.height * 4)
    for row in 0..<target.height {
        let sourceRow = pData.advanced(by: row * Int(mapped.RowPitch))
        let destination = row * target.width * 4
        pixels.withUnsafeMutableBufferPointer { buffer in
            memcpy(buffer.baseAddress!.advanced(by: destination), sourceRow, target.width * 4)
        }
    }
    context.pointee.lpVtbl.pointee.Unmap(context, dstResource, 0)
    return pixels
}

// MARK: - Batch Renderer on WARP

/// One WARP-attached `D3D11BatchRenderer`, shared by every test that needs
/// the real GPU frame path.
///
/// Attaching compiles a dozen shaders and creates a device, and the
/// renderer has no `detach()` yet, so tests reuse a single instance and
/// resize it per scene instead of creating one per test. Bound resources
/// (image textures, atlases, the path cache) therefore persist across
/// tests — scenes that bind images must use distinct texture IDs.
@MainActor
enum WARPBatchRenderer {
    private static var cached: D3D11BatchRenderer?
    private static var attachFailure: String?

    /// The shared renderer, attached offscreen at `size`. Throws `XCTSkip`
    /// when no D3D11 device can be created here.
    static func shared(size: IntSize) throws -> D3D11BatchRenderer {
        if let attachFailure {
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(attachFailure)")
        }

        if let cached {
            try cached.resize(to: size)
            return cached
        }

        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            attachFailure = String(describing: error)
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(attachFailure ?? "")")
        }
        cached = renderer
        return renderer
    }

    /// Renders `scene` through the real D3D11 batch frame path — bind,
    /// render, present — and reads the result back as BGRA, the same byte
    /// order `GPUIRawSceneRasterizer` produces.
    static func render(_ scene: GPUIScene, size: IntSize) throws -> BitmapSurface {
        let renderer = try shared(size: size)
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        return try renderer.readOffscreenPixels()
    }
}

// MARK: - Pixel Comparison

/// The result of comparing two BGRA surfaces channel by channel.
struct PixelDiffReport {
    var totalPixels: Int
    var withinTolerance: Int
    var maxChannelDelta: Int
    /// The first pixel that exceeded the tolerance, for the failure message.
    var firstFailure: (x: Int, y: Int, expected: (Int, Int, Int, Int), actual: (Int, Int, Int, Int))?

    var matchRatio: Double {
        totalPixels == 0 ? 0 : Double(withinTolerance) / Double(totalPixels)
    }
}

/// Compares two BGRA surfaces of the same size, counting how many pixels
/// agree on every channel within `tolerance`. This is the same tolerance
/// shape `scripts/gallery-compare.ps1` uses: a small per-channel delta over
/// a large majority of pixels, so rounding and antialiasing noise pass while
/// structural divergence does not.
func comparePixels(
    _ actual: BitmapSurface,
    _ expected: BitmapSurface,
    tolerance: Int
) -> PixelDiffReport {
    let width = min(Int(actual.width), Int(expected.width))
    let height = min(Int(actual.height), Int(expected.height))
    var report = PixelDiffReport(totalPixels: width * height, withinTolerance: 0, maxChannelDelta: 0)

    for y in 0..<height {
        for x in 0..<width {
            let actualOffset = y * Int(actual.bytesPerRow) + x * 4
            let expectedOffset = y * Int(expected.bytesPerRow) + x * 4
            guard actualOffset + 3 < actual.pixels.count, expectedOffset + 3 < expected.pixels.count else {
                continue
            }

            var worst = 0
            for channel in 0..<4 {
                let delta = abs(
                    Int(actual.pixels[actualOffset + channel]) - Int(expected.pixels[expectedOffset + channel]))
                worst = max(worst, delta)
            }
            report.maxChannelDelta = max(report.maxChannelDelta, worst)

            if worst <= tolerance {
                report.withinTolerance += 1
            } else if report.firstFailure == nil {
                report.firstFailure = (
                    x: x, y: y,
                    expected: (
                        Int(expected.pixels[expectedOffset]), Int(expected.pixels[expectedOffset + 1]),
                        Int(expected.pixels[expectedOffset + 2]), Int(expected.pixels[expectedOffset + 3])
                    ),
                    actual: (
                        Int(actual.pixels[actualOffset]), Int(actual.pixels[actualOffset + 1]),
                        Int(actual.pixels[actualOffset + 2]), Int(actual.pixels[actualOffset + 3])
                    )
                )
            }
        }
    }

    return report
}
