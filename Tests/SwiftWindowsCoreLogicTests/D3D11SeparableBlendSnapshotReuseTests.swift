import Foundation
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Frozen after the first CPU/batch implementation, before destination reuse.
/// These tests exercise capture ownership directly, not rendering or blend math.
@MainActor
final class D3D11SeparableBlendSnapshotReuseTests: XCTestCase {
    func testRecaptureReusesTextureAndViewAndCopiesFreshShiftedPixelsAtOrigin() async throws {
        let owner = try makeStrictWARPDevice()
        defer { owner.release() }
        let device = try XCTUnwrap(owner.device)
        let context = try XCTUnwrap(owner.context)
        let original = pattern(seed: 16)
        var sourceOwner: UnsafeMutablePointer<ID3D11Texture2D>? = try makeSource(owner, pixels: original)
        defer { releaseRaw(&sourceOwner) }
        let source = try XCTUnwrap(sourceOwner)
        let initial = SubTextureRegion(
            originX: 1, originY: 1, width: 4, height: 3, textureWidth: 8, textureHeight: 6)
        let snapshot = try D3D11BlendDestinationSnapshot(
            device: device, context: context, source: source, region: initial)
        defer { snapshot.release() }
        let texture = try XCTUnwrap(snapshot.texture)
        let view = try XCTUnwrap(snapshot.srv)
        // Keep both original objects alive so replacement cannot recycle their addresses.
        var retainedTexture: UnsafeMutablePointer<ID3D11Texture2D>? = retainRaw(texture)
        var retainedView: UnsafeMutablePointer<ID3D11ShaderResourceView>? = retainRaw(view)
        defer {
            releaseRaw(&retainedView)
            releaseRaw(&retainedTexture)
        }
        XCTAssertEqual(try readPixels(owner, texture: texture), cropped(original, to: initial))

        let shifted = SubTextureRegion(
            originX: 3, originY: 2, width: 4, height: 3, textureWidth: 8, textureHeight: 6)
        try snapshot.capture(context: context, source: source, region: shifted)
        XCTAssertEqual(snapshot.texture, texture)
        XCTAssertEqual(snapshot.srv, view)
        XCTAssertEqual(snapshot.region, shifted)
        let shiftedPixels = try readPixels(owner, texture: XCTUnwrap(snapshot.texture))
        XCTAssertEqual(shiftedPixels, cropped(original, to: shifted))
        XCTAssertNotEqual(shiftedPixels, cropped(original, to: initial))

        let replacement = pattern(seed: 80)
        try updateSource(owner, source: source, pixels: replacement)
        try snapshot.capture(context: context, source: source, region: shifted)
        XCTAssertEqual(snapshot.texture, texture)
        XCTAssertEqual(snapshot.srv, view)
        XCTAssertEqual(snapshot.region, shifted)
        let refreshed = try readPixels(owner, texture: XCTUnwrap(snapshot.texture))
        XCTAssertEqual(refreshed, cropped(replacement, to: shifted))
        XCTAssertNotEqual(refreshed, shiftedPixels, "The same region must copy again after the source changes.")
    }

    func testInvalidRecapturesAndReleasedOwnerPreserveRegionPixelsAndResources() async throws {
        let owner = try makeStrictWARPDevice()
        defer { owner.release() }
        let device = try XCTUnwrap(owner.device)
        let context = try XCTUnwrap(owner.context)
        let original = pattern(seed: 16)
        var sourceOwner: UnsafeMutablePointer<ID3D11Texture2D>? = try makeSource(owner, pixels: original)
        defer { releaseRaw(&sourceOwner) }
        let source = try XCTUnwrap(sourceOwner)
        let initial = SubTextureRegion(
            originX: 1, originY: 1, width: 4, height: 3, textureWidth: 8, textureHeight: 6)
        let snapshot = try D3D11BlendDestinationSnapshot(
            device: device, context: context, source: source, region: initial)
        defer { snapshot.release() }
        let texture = try XCTUnwrap(snapshot.texture)
        let view = try XCTUnwrap(snapshot.srv)
        // These references prevent address reuse and keep released-owner pixel checks safe.
        var retainedTexture: UnsafeMutablePointer<ID3D11Texture2D>? = retainRaw(texture)
        var retainedView: UnsafeMutablePointer<ID3D11ShaderResourceView>? = retainRaw(view)
        defer {
            releaseRaw(&retainedView)
            releaseRaw(&retainedTexture)
        }
        let expected = cropped(original, to: initial)
        XCTAssertEqual(try readPixels(owner, texture: texture), expected)

        try updateSource(owner, source: source, pixels: pattern(seed: 80))

        let rejected = [
            SubTextureRegion(
                originX: 1, originY: 1, width: 4, height: 3, textureWidth: 7, textureHeight: 6),
            SubTextureRegion(
                originX: 2, originY: 1, width: 5, height: 3, textureWidth: 8, textureHeight: 6),
            SubTextureRegion(
                originX: 1, originY: 1, width: 4, height: 4, textureWidth: 8, textureHeight: 6),
        ]
        for region in rejected {
            XCTAssertFalse(region.isEmpty)
            XCTAssertLessThanOrEqual(region.maxX, 8)
            XCTAssertLessThanOrEqual(region.maxY, 6)
            XCTAssertThrowsError(try snapshot.capture(context: context, source: source, region: region))
            XCTAssertEqual(snapshot.region, initial)
            XCTAssertEqual(snapshot.texture, texture)
            XCTAssertEqual(snapshot.srv, view)
            XCTAssertEqual(try readPixels(owner, texture: texture), expected)
        }

        // Matching source dimensions isolate the same-subresource rejection.
        let selfAlias = SubTextureRegion(textureWidth: 4, textureHeight: 3)
        XCTAssertThrowsError(try snapshot.capture(context: context, source: texture, region: selfAlias))
        XCTAssertEqual(snapshot.region, initial)
        XCTAssertEqual(snapshot.texture, texture)
        XCTAssertEqual(snapshot.srv, view)
        XCTAssertEqual(try readPixels(owner, texture: texture), expected)

        snapshot.release()
        XCTAssertNil(snapshot.texture)
        XCTAssertNil(snapshot.srv)
        XCTAssertThrowsError(try snapshot.capture(context: context, source: source, region: initial))
        XCTAssertEqual(snapshot.region, initial)
        XCTAssertNil(snapshot.texture, "A released owner must not allocate replacement resources.")
        XCTAssertNil(snapshot.srv)
        XCTAssertEqual(try readPixels(owner, texture: texture), expected)
    }

    private func makeStrictWARPDevice() throws -> WARPDevice {
        let owner = WARPDevice()
        var transferred = false
        defer { if !transferred { owner.release() } }
        var level = D3D_FEATURE_LEVEL(0)
        let requested = [D3D_FEATURE_LEVEL_11_0]
        let flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)
        let result = requested.withUnsafeBufferPointer { levels in
            D3D11CreateDevice(
                nil, D3D_DRIVER_TYPE_WARP, nil, flags, levels.baseAddress, UINT(levels.count),
                UINT(D3D11_SDK_VERSION), &owner.device, &level, &owner.context)
        }
        guard result >= 0, owner.device != nil, owner.context != nil, level == D3D_FEATURE_LEVEL_11_0 else {
            throw failure("Create one strict WARP FL11_0 snapshot test device", result)
        }
        transferred = true
        return owner
    }

    private func makeSource(_ owner: WARPDevice, pixels: [UInt8]) throws -> UnsafeMutablePointer<ID3D11Texture2D> {
        let device = try XCTUnwrap(owner.device)
        var descriptor = D3D11_TEXTURE2D_DESC()
        descriptor.Width = 8
        descriptor.Height = 6
        descriptor.MipLevels = 1
        descriptor.ArraySize = 1
        descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_RENDER_TARGET.rawValue)
        var texture: UnsafeMutablePointer<ID3D11Texture2D>?
        var transferred = false
        defer { if !transferred { releaseRaw(&texture) } }
        let result = device.pointee.lpVtbl.pointee.CreateTexture2D(device, &descriptor, nil, &texture)
        guard result >= 0, let created = texture else {
            throw failure("Create snapshot test source", result)
        }
        try updateSource(owner, source: created, pixels: pixels)
        transferred = true
        return created
    }

    private func updateSource(
        _ owner: WARPDevice, source: UnsafeMutablePointer<ID3D11Texture2D>, pixels: [UInt8]
    ) throws {
        guard pixels.count == 8 * 6 * 4 else { throw failure("Validate snapshot test source byte count") }
        let context = try XCTUnwrap(owner.context)
        let resource = UnsafeMutableRawPointer(source).assumingMemoryBound(to: ID3D11Resource.self)
        pixels.withUnsafeBytes { bytes in
            context.pointee.lpVtbl.pointee.UpdateSubresource(
                context, resource, 0, nil, bytes.baseAddress, 8 * 4, 0)
        }
    }

    private func readPixels(
        _ owner: WARPDevice, texture: UnsafeMutablePointer<ID3D11Texture2D>
    ) throws -> [UInt8] {
        let device = try XCTUnwrap(owner.device)
        let context = try XCTUnwrap(owner.context)
        var descriptor = D3D11_TEXTURE2D_DESC()
        texture.pointee.lpVtbl.pointee.GetDesc(texture, &descriptor)
        guard descriptor.Width == 4, descriptor.Height == 3,
            descriptor.Format == DXGI_FORMAT_B8G8R8A8_UNORM,
            descriptor.MipLevels == 1, descriptor.ArraySize == 1,
            descriptor.SampleDesc.Count == 1, descriptor.SampleDesc.Quality == 0
        else { throw failure("Validate fixed snapshot capacity and BGRA8 readback format") }
        descriptor.Usage = D3D11_USAGE_STAGING
        descriptor.BindFlags = 0
        descriptor.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_READ.rawValue)
        descriptor.MiscFlags = 0
        var staging: UnsafeMutablePointer<ID3D11Texture2D>?
        defer { releaseRaw(&staging) }
        let createResult = device.pointee.lpVtbl.pointee.CreateTexture2D(device, &descriptor, nil, &staging)
        guard createResult >= 0, let destination = staging else {
            throw failure("Create snapshot test staging texture", createResult)
        }
        let sourceResource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        let destinationResource = UnsafeMutableRawPointer(destination).assumingMemoryBound(to: ID3D11Resource.self)
        context.pointee.lpVtbl.pointee.CopyResource(context, destinationResource, sourceResource)
        var mapped = D3D11_MAPPED_SUBRESOURCE()
        let mapResult = context.pointee.lpVtbl.pointee.Map(
            context, destinationResource, 0, D3D11_MAP_READ, 0, &mapped)
        guard mapResult >= 0 else { throw failure("Map snapshot test staging texture", mapResult) }
        defer { context.pointee.lpVtbl.pointee.Unmap(context, destinationResource, 0) }
        guard let data = mapped.pData, mapped.RowPitch >= 4 * 4 else {
            throw failure("Validate snapshot test mapping and row pitch")
        }
        var pixels: [UInt8] = []
        pixels.reserveCapacity(4 * 3 * 4)
        for row in 0..<3 {
            let start = data.advanced(by: row * Int(mapped.RowPitch)).assumingMemoryBound(to: UInt8.self)
            pixels.append(contentsOf: UnsafeBufferPointer(start: start, count: 4 * 4))
        }
        return pixels
    }

    private func pattern(seed: UInt8) -> [UInt8] {
        var pixels: [UInt8] = []
        for y in 0..<6 {
            for x in 0..<8 {
                pixels.append(contentsOf: [seed + UInt8(x * 3), seed + UInt8(y * 7), seed + UInt8(x + y * 11), 255])
            }
        }
        return pixels
    }

    private func cropped(_ pixels: [UInt8], to region: SubTextureRegion) -> [UInt8] {
        var result: [UInt8] = []
        for y in region.originY..<region.maxY {
            let start = (y * 8 + region.originX) * 4
            result.append(contentsOf: pixels[start..<(start + region.width * 4)])
        }
        return result
    }

    private func retainRaw<T>(_ value: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<T> {
        let unknown = UnsafeMutableRawPointer(value).assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.AddRef(unknown)
        return value
    }

    private func releaseRaw<T>(_ value: inout UnsafeMutablePointer<T>?) {
        guard let pointer = value else { return }
        let unknown = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        value = nil
    }

    private func failure(
        _ operation: String, _ result: HRESULT = HRESULT(bitPattern: 0x8000_4005)
    ) -> BatchRendererError {
        BatchRendererError(operation: operation, hresult: result < 0 ? result : HRESULT(bitPattern: 0x8000_4005))
    }
}
