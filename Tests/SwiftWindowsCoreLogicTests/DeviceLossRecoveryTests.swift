import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import XCTest

@testable import SwiftWindowsRendererD3D11

/// WS-02: device loss is recoverable, and the caches keyed on a device know
/// when their device stopped existing.
///
/// The audit's finding was that `attach` dropped only the path cache and the
/// blur engine, so `createDeviceIfNeeded`'s `if device != nil { return }`
/// re-bound the *removed* device forever: the host's 5s→60s recovery loop
/// either failed for the life of the process or "succeeded" onto a corpse and
/// flapped. WS-01 made `attach` tear down first; this suite proves the
/// rebuild actually produces a new device, that it is bounded, and that the
/// blur engine cannot be handed back for a device that no longer exists.
///
/// Runs on the offscreen seam, so no HWND and no real TDR are involved: the
/// rebuild path is entered through `simulateDeviceLossForTesting`, which is
/// the same call `Present` makes when it returns `DXGI_ERROR_DEVICE_REMOVED`.
@MainActor
final class DeviceLossRecoveryTests: XCTestCase {

    private func makeSolidQuadScene(size: IntSize) -> GPUIScene {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: Float(size.width), height: Float(size.height),
                startR: 0.2, startG: 0.4, startB: 0.8, startA: 1,
                endR: 0.2, endG: 0.4, endB: 0.8, endA: 1
            )
        )
        return scene
    }

    /// A renderer of its own (not the shared WARP one) attached offscreen,
    /// with the recovery wait stubbed out so the suite does not sleep.
    private func makeRecoverableRenderer(size: IntSize) throws -> D3D11BatchRenderer {
        let renderer = D3D11BatchRenderer()
        renderer.deviceLostBackoffHandler = { _ in }
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        return renderer
    }

    // MARK: - Rebuild

    func testDeviceLossRebuildsTheDeviceAndKeepsRendering() async throws {
        let size = IntSize(width: 48, height: 32)
        let renderer = try makeRecoverableRenderer(size: size)
        defer { renderer.detach() }

        try renderer.render(scene: makeSolidQuadScene(size: size))
        let originalGeneration = renderer.deviceGeneration
        XCTAssertGreaterThan(originalGeneration, 0, "An attached renderer must hold a device generation")

        try renderer.simulateDeviceLossForTesting()

        XCTAssertTrue(renderer.isAttached, "A successful rebuild leaves the renderer attached")
        XCTAssertGreaterThan(
            renderer.deviceGeneration, originalGeneration,
            "Recovery must create a *new* device, not re-bind the removed one")
        XCTAssertTrue(
            renderer.presentationState.needsImmediateRepaint,
            "The rebuilt device owes the screen the frame it skipped")

        // The skipped frame: one render that deliberately draws nothing.
        try renderer.render(scene: makeSolidQuadScene(size: size))
        // ...and then the frame that actually lands, on the new device.
        try renderer.render(scene: makeSolidQuadScene(size: size))
        let bitmap = try renderer.readOffscreenPixels()
        let centre = (Int(bitmap.height) / 2) * Int(bitmap.bytesPerRow) + (Int(bitmap.width) / 2) * 4
        XCTAssertEqual(Int(bitmap.pixels[centre]), 204, accuracy: 2, "blue channel after rebuild")
        XCTAssertEqual(Int(bitmap.pixels[centre + 1]), 102, accuracy: 2, "green channel after rebuild")
        XCTAssertEqual(Int(bitmap.pixels[centre + 2]), 51, accuracy: 2, "red channel after rebuild")
    }

    func testRebuildRestoresTheRenderTargetSize() async throws {
        let size = IntSize(width: 40, height: 24)
        let renderer = try makeRecoverableRenderer(size: size)
        defer { renderer.detach() }

        try renderer.simulateDeviceLossForTesting()
        try renderer.render(scene: makeSolidQuadScene(size: size))
        try renderer.render(scene: makeSolidQuadScene(size: size))

        let bitmap = try renderer.readOffscreenPixels()
        XCTAssertEqual(Int(bitmap.width), 40, "The rebuilt target must keep the surface size")
        XCTAssertEqual(Int(bitmap.height), 24)
    }

    // MARK: - Bounded retries

    func testRecoveryIsBoundedAndSurfacesATypedDeviceLostFailure() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try makeRecoverableRenderer(size: size)
        defer { renderer.detach() }

        // Each rebuild succeeds but no frame ever presents cleanly, so the
        // budget is never refunded — a device-loss storm, not a session.
        for attempt in 1...DeviceLostPolicy.maxRecoveryAttempts {
            try renderer.simulateDeviceLossForTesting()
            XCTAssertTrue(renderer.isAttached, "Rebuild \(attempt) must succeed")
        }

        XCTAssertThrowsError(try renderer.simulateDeviceLossForTesting()) { error in
            guard let batchError = error as? BatchRendererError else {
                XCTFail("Exhausted recovery must be a typed BatchRendererError, got \(error)")
                return
            }
            XCTAssertEqual(
                batchError.presentationFailureKind, .deviceLost,
                "The host has to be able to tell this from a scene-content failure")
        }
        XCTAssertFalse(
            renderer.isAttached,
            "Giving up must leave nothing half-built for the host's downgrade to inherit")
        XCTAssertEqual(renderer.deviceGeneration, 0, "A detached renderer holds no device generation")
    }

    func testACleanPresentRefundsTheRecoveryBudget() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try makeRecoverableRenderer(size: size)
        defer { renderer.detach() }

        for _ in 1...DeviceLostPolicy.maxRecoveryAttempts {
            try renderer.simulateDeviceLossForTesting()
            // Two renders: the deliberate post-rebuild skip, then a frame
            // that presents cleanly and clears the storm counter.
            try renderer.render(scene: makeSolidQuadScene(size: size))
            try renderer.render(scene: makeSolidQuadScene(size: size))
            XCTAssertFalse(
                renderer.presentationState.needsImmediateRepaint,
                "A frame that reached the target clears the repaint debt")
        }

        // Well past `maxRecoveryAttempts` cumulative losses, but never that
        // many *consecutive* ones, so recovery is still available.
        try renderer.simulateDeviceLossForTesting()
        XCTAssertTrue(renderer.isAttached)
    }

    func testFrameRendererSurfacesATypedFailureWhenItCannotRebuild() async {
        // The frame renderer's rebuild needs a surface to attach to. With
        // none, recovery must give up with a *typed* failure rather than do
        // what the old handler did: log, return, and tell the caller the
        // frame presented while nothing had been recreated.
        let renderer = D3D11Renderer()
        renderer.deviceLostBackoffHandler = { _ in }

        XCTAssertThrowsError(try renderer.simulateDeviceLossForTesting()) { error in
            guard let rendererError = error as? D3D11RendererError else {
                XCTFail("Unrecoverable device loss must be a typed D3D11RendererError, got \(error)")
                return
            }
            XCTAssertEqual(rendererError.presentationFailureKind, .deviceLost)
        }
        XCTAssertFalse(renderer.isAttached, "A renderer that gave up must leave nothing half-built")
    }

    // MARK: - Generation tokens

    func testBlurEngineIsKeyedOnGenerationNotAddress() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let engine = D3D11BackdropBlurEngine()
        defer { engine.detach() }

        try engine.attach(device: try XCTUnwrap(device.device), generation: 7)

        XCTAssertTrue(engine.matches(deviceGeneration: 7))
        // The whole point: after a rebuild the allocator may hand the new
        // device the address the removed one just released, so identity has
        // to come from a token the renderer bumps, not from the pointer.
        XCTAssertFalse(
            engine.matches(deviceGeneration: 8),
            "A new device generation must invalidate resources built on the old one")
        XCTAssertFalse(
            engine.matches(deviceGeneration: 0),
            "Generation 0 means 'no device', which nothing may match")

        engine.detach()
        XCTAssertFalse(engine.matches(deviceGeneration: 7), "A detached engine matches nothing")
    }

    func testDeviceGenerationIsUniquePerDeviceAndZeroWhenDetached() async throws {
        let size = IntSize(width: 16, height: 16)
        let first = try makeRecoverableRenderer(size: size)
        let firstGeneration = first.deviceGeneration
        first.detach()
        XCTAssertEqual(first.deviceGeneration, 0)

        let second = try makeRecoverableRenderer(size: size)
        defer { second.detach() }
        XCTAssertNotEqual(
            second.deviceGeneration, firstGeneration,
            "Generations are process-wide, so a reused address cannot look like the same device")
    }

    func testBlurEngineIsRebuiltAcrossADeviceRebuild() async throws {
        let size = IntSize(width: 64, height: 64)
        let renderer = try makeRecoverableRenderer(size: size)
        defer { renderer.detach() }

        var scene = GPUIScene(clearColor: Color(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: 48, height: 48,
                startR: 1, startG: 1, startB: 1, startA: 0.4,
                endR: 1, endG: 1, endB: 1, endA: 0.4,
                blurRadius: 12
            )
        )
        try renderer.render(scene: scene)
        XCTAssertTrue(renderer.blurEngineOwnsResourcesForTesting, "The material quad must have built a blur engine")

        try renderer.simulateDeviceLossForTesting()
        XCTAssertFalse(
            renderer.blurEngineOwnsResourcesForTesting,
            "Teardown must drop the blur engine with the device it was built on")

        // Rendering the same material again on the new device must work
        // rather than reuse resources from the device that went away.
        try renderer.render(scene: scene)
        try renderer.render(scene: scene)
        XCTAssertTrue(renderer.blurEngineOwnsResourcesForTesting)
    }
}
