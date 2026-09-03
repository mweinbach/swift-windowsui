import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Ordinary quad blend pixels, using the real owner-confined batch kernel.
/// Device, shader, copy, attach and draw errors all remain failures, with no
/// driver fallback or skip. Additive and material-plus-blend are not
/// implemented by this slice and retain their previous source-over behavior.
@MainActor
final class D3D11SeparableBlendTests: XCTestCase {
    private let modes: [BlendMode] = [.multiply, .screen, .overlay]

    func testSeparableModesMatchIndependentValuesAcrossAlphaExtremes() async throws {
        let size = IntSize(width: 16, height: 16)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destinations = [
            Color(red: 0.2, green: 0.8, blue: 0.45, alpha: 1),
            Color(red: 0.75, green: 0.25, blue: 0.6, alpha: 0.5),
            Color(red: 0.8, green: 0.2, blue: 0.7, alpha: 0.125),
            Color(red: 0.9, green: 0.6, blue: 0.3, alpha: 0),
        ]
        for mode in modes {
            var differsFromNormal = false
            for destination in destinations {
                let clearOnly = try render(
                    GPUIScene(clearColor: destination), using: renderer, size: size)
                let untouched = rgba(clearOnly, x: 0, y: 0)
                // D3D11 sections 3.2.3.6 and 5.2.3.1 permit 0.6 integer-ULP
                // for clear-to-UNORM conversion. Validate this separate control
                // before requiring exact preservation outside the blend quad.
                let clearInput: [Float] = [
                    destination.red * destination.alpha,
                    destination.green * destination.alpha,
                    destination.blue * destination.alpha,
                    destination.alpha,
                ]
                for channel in 0..<4 {
                    XCTAssertLessThanOrEqual(
                        abs(untouched[channel] * 255 - Double(clearInput[channel]) * 255),
                        Double(Float(0.6)),
                        "Clear-only channel \(channel) exceeds the D3D11 UNORM conversion bound")
                }
                for alpha in [Float(0), 0.35, 1] {
                    let source = Color(red: 0.7, green: 0.3, blue: 0.85, alpha: alpha)
                    var scene = GPUIScene(clearColor: destination)
                    scene.addQuad(quad(source, mode: mode, x: 2, y: 2, width: 12, height: 12))
                    let actual = try render(scene, using: renderer, size: size)
                    let initial = quantized(premultiplied(destination))
                    let expected = oracle(source, over: initial, mode: mode)
                    assertPixel(actual, x: 8, y: 8, equals: expected, tolerance: 2)
                    assertPixel(actual, x: 0, y: 0, equals: untouched, tolerance: 0)
                    assertCPUParity(actual, scene: scene, size: size, tolerance: 3)
                    let normal = quantized(oracle(source, over: initial, mode: .normal))
                    if zip(quantized(expected), normal).contains(where: { pair in abs(pair.0 - pair.1) > 4.0 / 255 }) {
                        differsFromNormal = true
                    }
                }
            }
            XCTAssertTrue(differsFromNormal, "Each mode must have a nondegenerate oracle")
        }
    }

    func testOverlayBranchesOnStraightDestinationRatherThanPremultipliedChannels() async throws {
        let size = IntSize(width: 16, height: 16)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destination = Color(red: 0.8, green: 0.2, blue: 0.5, alpha: 0.25)
        let source = Color(red: 0.25, green: 0.75, blue: 0.3, alpha: 0.8)
        var scene = GPUIScene(clearColor: destination)
        scene.addQuad(quad(source, mode: .overlay, width: 16, height: 16))
        let actual = try render(scene, using: renderer, size: size)
        let expected = oracle(source, over: quantized(premultiplied(destination)), mode: .overlay)
        assertPixel(actual, x: 8, y: 8, equals: expected, tolerance: 2)
        assertCPUParity(actual, scene: scene, size: size, tolerance: 3)
    }

    func testRoundedRotatedAndFractionalClipCoverageIsAppliedExactlyOnce() async throws {
        let size = IntSize(width: 32, height: 28)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destination = Color(red: 0.75, green: 0.2, blue: 0.6, alpha: 0.45)
        let source = Color(red: 0.2, green: 0.8, blue: 0.35, alpha: 0.6)
        for rotation in [Float(0), 0.23] {
            var shape = quad(.white, mode: .normal, x: 2.25, y: 1.75, width: 25.5, height: 23.5)
            shape.cornerRadius = 6
            shape.rotationRadians = rotation
            shape.clipX = 4.5
            shape.clipY = 2.5
            shape.clipWidth = 22
            shape.clipHeight = 21
            shape.clipCornerRadius = 4
            var maskScene = GPUIScene(clearColor: .clear)
            maskScene.addQuad(shape)
            let mask = try render(maskScene, using: renderer, size: size)
            var fractionalPixels = 0
            for mode in modes {
                var colored = shape
                colored.startR = source.red
                colored.startG = source.green
                colored.startB = source.blue
                colored.startA = source.alpha
                colored.endR = source.red
                colored.endG = source.green
                colored.endB = source.blue
                colored.endA = source.alpha
                colored.blendMode = Float(mode.rawValue)
                var scene = GPUIScene(clearColor: destination)
                scene.addQuad(colored)
                let actual = try render(scene, using: renderer, size: size)
                let initial = quantized(premultiplied(destination))
                for y in 0..<Int(size.height) {
                    for x in 0..<Int(size.width) {
                        let coverage = rgba(mask, x: x, y: y)[3]
                        if coverage > 0 && coverage < 1 { fractionalPixels += 1 }
                        let expected = oracle(source, over: initial, mode: mode, coverage: coverage)
                        assertPixel(actual, x: x, y: y, equals: expected, tolerance: 3)
                    }
                }
            }
            XCTAssertGreaterThan(fractionalPixels, 8, "The fixture must exercise antialiased coverage")
        }
    }

    func testEveryBlendObservesEarlierDrawsAcrossFamiliesAndRestoresNormal() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destination = Color(red: 0.7, green: 0.3, blue: 0.2, alpha: 0.45)
        let first = Color(red: 0.2, green: 0.8, blue: 0.6, alpha: 0.55)
        let second = Color(red: 0.85, green: 0.25, blue: 0.45, alpha: 0.4)
        let third = Color(red: 0.3, green: 0.6, blue: 0.9, alpha: 0.65)
        let final = Color(red: 0.9, green: 0.1, blue: 0.2, alpha: 0.35)
        let bitmapID: Int32 = 78_101
        let bitmapColor = Color(red: 0.1, green: 0.7, blue: 0.3, alpha: 0.5)
        var scene = GPUIScene(clearColor: destination)
        scene.addQuad(quad(first, mode: .multiply, width: 32, height: 24))
        scene.addQuad(quad(second, mode: .screen, x: 4, y: 2, width: 24, height: 20))
        scene.bindImageResource(bitmap(bitmapColor), for: bitmapID)
        scene.addImage(image(bitmapID, x: 8, y: 4, width: 16, height: 16))
        scene.addQuad(quad(third, mode: .overlay, x: 6, y: 4, width: 20, height: 16))
        scene.addQuad(quad(final, mode: .normal, x: 12, y: 8, width: 8, height: 8))
        let actual = try render(scene, using: renderer, size: size)
        var expected = quantized(premultiplied(destination))
        expected = quantized(oracle(first, over: expected, mode: .multiply))
        assertPixel(actual, x: 2, y: 12, equals: expected, tolerance: 2)
        expected = quantized(oracle(second, over: expected, mode: .screen))
        let sampledBitmap = bitmap(bitmapColor).premultipliedAlpha()
        let bitmapSample = rgba(sampledBitmap, x: 0, y: 0)
        expected = quantized(sourceOver(bitmapSample, over: expected))
        expected = quantized(oracle(third, over: expected, mode: .overlay))
        assertPixel(actual, x: 10, y: 12, equals: expected, tolerance: 3)
        expected = oracle(final, over: expected, mode: .normal)
        assertPixel(actual, x: 16, y: 12, equals: expected, tolerance: 3)
        assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
    }

    func testRepeatedTranslatedCurrentTargetPassReadsEachImmediateDestination() async throws {
        let size = IntSize(width: 40, height: 24)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destination = Color(red: 0.7, green: 0.2, blue: 0.4, alpha: 0.5)
        let source = Color(red: 0.2, green: 0.8, blue: 0.65, alpha: 0.55)
        let middle = Color(red: 0.85, green: 0.3, blue: 0.15, alpha: 0.4)
        for mode in modes {
            var child = GPUIScene(clearColor: .clear)
            child.addQuad(quad(source, mode: mode, width: 12, height: 12))
            var scene = GPUIScene(clearColor: destination)
            let sourceID = scene.registerImageRenderPass(
                child, size: IntSize(width: 12, height: 12), input: .currentTarget)
            let occurrence = image(sourceID, x: 18, y: 6, width: 12, height: 12)
            scene.addImage(occurrence)
            scene.addQuad(quad(middle, mode: .normal, x: 18, y: 6, width: 12, height: 12))
            scene.addImage(occurrence)
            let pass = try XCTUnwrap(scene.imageRenderPasses.first)
            XCTAssertNotNil(pass.currentTargetRegion(for: occurrence, parentSize: size))
            let actual = try render(scene, using: renderer, size: size)
            var expected = quantized(premultiplied(destination))
            expected = quantized(oracle(source, over: expected, mode: mode))
            expected = quantized(oracle(middle, over: expected, mode: .normal))
            expected = oracle(source, over: expected, mode: mode)
            assertPixel(actual, x: 24, y: 12, equals: expected, tolerance: 3)
            assertPixel(actual, x: 4, y: 12, equals: premultiplied(destination), tolerance: 1)
            assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
            XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
        }
    }

    func testIndependentChildUsesItsOwnClearInsteadOfTheEnclosingBackdrop() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destination = Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.6)
        let childClear = Color(red: 0.1, green: 0.4, blue: 0.8, alpha: 0.5)
        let source = Color(red: 0.7, green: 0.3, blue: 0.25, alpha: 0.6)
        for mode in modes {
            var child = GPUIScene(clearColor: childClear)
            child.addQuad(quad(source, mode: mode, width: 12, height: 12))
            var scene = GPUIScene(clearColor: destination)
            let sourceID = scene.registerImageRenderPass(child, size: IntSize(width: 12, height: 12))
            scene.addImage(image(sourceID, x: 10, y: 6, width: 12, height: 12))
            let actual = try render(scene, using: renderer, size: size)
            let childValue = quantized(oracle(source, over: quantized(premultiplied(childClear)), mode: mode))
            let expected = sourceOver(childValue, over: quantized(premultiplied(destination)))
            assertPixel(actual, x: 16, y: 12, equals: expected, tolerance: 3)
            assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
        }
    }

    func testIsolatedBackdropBlendsReadVirtualDestinationAndPreserveGroupOpacity() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destination = Color(red: 0.8, green: 0.15, blue: 0.5, alpha: 0.5)
        let first = Color(red: 0.15, green: 0.7, blue: 0.3, alpha: 0.3)
        let source = Color(red: 0.65, green: 0.25, blue: 0.8, alpha: 0.6)
        for mode in modes {
            for opacity in [Float(0.5), 1] {
                var child = GPUIScene(clearColor: .clear)
                child.addQuad(quad(first, mode: .normal, width: 16, height: 16))
                child.addQuad(quad(source, mode: mode, width: 16, height: 16))
                var scene = GPUIScene(clearColor: destination)
                let sourceID = scene.registerImageRenderPass(
                    child, size: IntSize(width: 16, height: 16), input: .isolatedBackdrop)
                scene.addImage(image(sourceID, x: 8, y: 4, width: 16, height: 16, opacity: opacity))
                let actual = try render(scene, using: renderer, size: size)
                let initial = quantized(premultiplied(destination))
                let firstValue = oracle(first, over: initial, mode: .normal)
                let complete = oracle(source, over: firstValue, mode: mode)
                let expected = zip(complete, initial).map { pair in
                    Double(opacity) * pair.0 + (1 - Double(opacity)) * pair.1
                }
                assertPixel(actual, x: 16, y: 12, equals: expected, tolerance: 4)
                assertPixel(actual, x: 2, y: 12, equals: initial, tolerance: 0)
                assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
                XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
            }
        }
    }

    func testNestedIndependentAndIsolatedChildrenRestoreTheCorrectBlendDestination() async throws {
        let size = IntSize(width: 40, height: 32)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destination = Color(red: 0.75, green: 0.2, blue: 0.4, alpha: 0.55)
        var independent = GPUIScene(clearColor: Color(red: 0.1, green: 0.7, blue: 0.3, alpha: 0.4))
        independent.addQuad(
            quad(
                Color(red: 0.7, green: 0.25, blue: 0.8, alpha: 0.65), mode: .overlay,
                width: 12, height: 12))
        var isolated = GPUIScene(clearColor: .clear)
        let innerID = isolated.registerImageRenderPass(independent, size: IntSize(width: 12, height: 12))
        isolated.addImage(image(innerID, x: 2, y: 2, width: 12, height: 12))
        isolated.addQuad(
            quad(
                Color(red: 0.8, green: 0.45, blue: 0.2, alpha: 0.4), mode: .multiply,
                x: 2, y: 2, width: 20, height: 16))
        var scene = GPUIScene(clearColor: destination)
        let outerID = scene.registerImageRenderPass(
            isolated, size: IntSize(width: 24, height: 20), input: .isolatedBackdrop)
        scene.addImage(image(outerID, x: 8, y: 6, width: 24, height: 20))
        scene.addQuad(
            quad(
                Color(red: 0.2, green: 0.8, blue: 0.6, alpha: 0.45), mode: .screen,
                x: 4, y: 4, width: 32, height: 24))
        scene.addQuad(quad(.white, mode: .normal, x: 34, y: 26, width: 4, height: 4))
        let actual = try render(scene, using: renderer, size: size)
        assertCPUParity(actual, scene: scene, size: size, tolerance: 5)
        assertPixel(actual, x: 36, y: 28, equals: [1, 1, 1, 1], tolerance: 0)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
    }

    func testContentBlurFiltersBlendForegroundAndCoverageWithoutBlurringUntouchedParent() async throws {
        let size = IntSize(width: 40, height: 32)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        var scene = GPUIScene(clearColor: Color(red: 0.15, green: 0.3, blue: 0.7, alpha: 0.55))
        for x in stride(from: 0, to: 40, by: 4) {
            scene.addQuad(
                quad(
                    Color(red: 0.8, green: 0.2, blue: 0.3, alpha: 0.4), mode: .normal,
                    x: Float(x), width: 2, height: 32))
        }
        let before = try render(scene, using: renderer, size: size)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(
            quad(
                Color(red: 0.2, green: 0.85, blue: 0.4, alpha: 0.6), mode: .multiply,
                x: 4, y: 4, width: 16, height: 12))
        child.addQuad(
            quad(
                Color(red: 0.9, green: 0.35, blue: 0.65, alpha: 0.45), mode: .screen,
                x: 8, y: 6, width: 12, height: 10))
        let sourceID = scene.registerImageRenderPass(
            child, size: IntSize(width: 24, height: 20), input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(image(sourceID, x: 8, y: 6, width: 24, height: 20, opacity: 0.7))
        let actual = try render(scene, using: renderer, size: size)
        assertCPUParity(actual, scene: scene, size: size, tolerance: 5)
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) where x < 8 || x >= 32 || y < 6 || y >= 26 {
                XCTAssertEqual(rgba(actual, x: x, y: y), rgba(before, x: x, y: y))
            }
        }
        XCTAssertNotEqual(actual.pixels, before.pixels)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
    }

    func testOrdinaryBlendAfterMaterialReadsFinishedMaterialAndRestoresFollowingImage() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        for mode in modes {
            var scene = GPUIScene(clearColor: Color(red: 0.75, green: 0.25, blue: 0.4, alpha: 0.5))
            var material = quad(
                Color(red: 0.15, green: 0.4, blue: 0.8, alpha: 0.3), mode: .normal,
                x: 2, y: 2, width: 24, height: 20)
            material.blurRadius = 3
            scene.addQuad(material)
            let before = try render(scene, using: renderer, size: size)
            let source = Color(red: 0.7, green: 0.8, blue: 0.2, alpha: 0.6)
            scene.addQuad(quad(source, mode: mode, x: 4, y: 4, width: 20, height: 16))
            let imageID: Int32 = 78_111
            scene.bindImageResource(bitmap(.white), for: imageID)
            scene.addImage(image(imageID, x: 26, y: 18, width: 4, height: 4))
            let actual = try render(scene, using: renderer, size: size)
            assertPixel(
                actual, x: 14, y: 12,
                equals: oracle(source, over: rgba(before, x: 14, y: 12), mode: mode), tolerance: 2)
            assertPixel(actual, x: 28, y: 20, equals: [1, 1, 1, 1], tolerance: 0)
            assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
        }
    }

    func testFailureAfterDestinationBindingUnwindsNestedTargetsAndNextFrame() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        var recovery = GPUIScene(clearColor: Color(red: 0.7, green: 0.2, blue: 0.4, alpha: 0.5))
        recovery.addQuad(
            quad(
                Color(red: 0.2, green: 0.8, blue: 0.6, alpha: 0.55), mode: .screen,
                x: 4, y: 4, width: 16, height: 16))
        recovery.addQuad(quad(.white, mode: .normal, x: 22, y: 14, width: 8, height: 8))
        let baseline = try render(recovery, using: renderer, size: size)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(
            quad(
                Color(red: 0.8, green: 0.25, blue: 0.6, alpha: 0.6), mode: .multiply,
                width: 12, height: 12))
        for input in [GPUISceneImageRenderPassInput.currentTarget, .isolatedBackdrop] {
            var scene = GPUIScene(clearColor: .black)
            let sourceID = scene.registerImageRenderPass(child, size: IntSize(width: 12, height: 12), input: input)
            scene.addImage(image(sourceID, x: 10, y: 6, width: 12, height: 12))
            _ = try render(scene, using: renderer, size: size)
            let warmed = renderer.liveCOMObjectCountForTesting
            renderer.failSeparableBlendAfterDestinationBindingForTesting = true
            renderer.bindResources(for: scene)
            XCTAssertThrowsError(try renderer.render(scene: scene)) { error in
                XCTAssertEqual((error as? BatchRendererError)?.operation, "Draw separable blend quad")
            }
            XCTAssertEqual(renderer.lastFrameSubmission?.outcome, .aborted)
            XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmed)
            renderer.failSeparableBlendAfterDestinationBindingForTesting = false
            let restored = try render(recovery, using: renderer, size: size)
            XCTAssertEqual(restored.pixels, baseline.pixels)
            assertCPUParity(restored, scene: recovery, size: size, tolerance: 4)
        }
    }

    func testRepeatedFramesResizeAndDetachReleaseBlendResources() async throws {
        let initialSize = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size: initialSize)
        defer { renderer.detach() }
        var scene = GPUIScene(clearColor: Color(red: 0.7, green: 0.25, blue: 0.5, alpha: 0.6))
        for (index, mode) in modes.enumerated() {
            scene.addQuad(
                quad(
                    Color(red: 0.2, green: 0.8, blue: 0.4, alpha: 0.4), mode: mode,
                    x: Float(index * 4), y: 2, width: 20, height: 18))
        }
        _ = try render(scene, using: renderer, size: initialSize)
        let warmed = renderer.liveCOMObjectCountForTesting
        for index in 0..<8 {
            let size = index % 2 == 0 ? IntSize(width: 40, height: 32) : initialSize
            try renderer.resize(to: size)
            scene.clearColor = Color(red: Float(index) / 10, green: 0.4, blue: 0.7, alpha: 0.55)
            let actual = try render(scene, using: renderer, size: size)
            assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmed)
            XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
        }
        renderer.detach()
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, 0)
        XCTAssertFalse(renderer.isAttached)
    }

    func testNormalAdditiveAndMaterialBlendModesKeepTheirExistingBehavior() async throws {
        let size = IntSize(width: 24, height: 24)
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destination = Color(red: 0.75, green: 0.2, blue: 0.4, alpha: 0.5)
        let source = Color(red: 0.2, green: 0.8, blue: 0.6, alpha: 0.55)
        var normal = GPUIScene(clearColor: destination)
        normal.addQuad(quad(source, mode: .normal, x: 2, y: 2, width: 20, height: 20))
        let baseline = try render(normal, using: renderer, size: size)
        var additive = GPUIScene(clearColor: destination)
        additive.addQuad(quad(source, mode: .additive, x: 2, y: 2, width: 20, height: 20))
        XCTAssertEqual(try render(additive, using: renderer, size: size).pixels, baseline.pixels)
        assertPixel(
            baseline, x: 12, y: 12,
            equals: oracle(source, over: quantized(premultiplied(destination)), mode: .normal), tolerance: 2)
        var material = quad(source, mode: .normal, x: 2, y: 2, width: 20, height: 20)
        material.blurRadius = 3
        var materialScene = GPUIScene(clearColor: destination)
        materialScene.addQuad(material)
        let materialBaseline = try render(materialScene, using: renderer, size: size)
        for mode in modes {
            material.blendMode = Float(mode.rawValue)
            var scene = GPUIScene(clearColor: destination)
            scene.addQuad(material)
            XCTAssertEqual(try render(scene, using: renderer, size: size).pixels, materialBaseline.pixels)
        }
    }

    func testLargeOrdinaryQuadDoesNotAcquireAnUnrelatedImagePassPixelLimit() async throws {
        let size = IntSize(width: 2050, height: 2050)
        XCTAssertGreaterThan(Int64(size.width) * Int64(size.height), Int64(GPUISceneLimits.maxImageRenderPassPixels))
        let renderer = try makeRenderer(size: size)
        defer { renderer.detach() }
        let destination = Color(red: 0.7, green: 0.2, blue: 0.5, alpha: 0.5)
        let source = Color(red: 0.2, green: 0.8, blue: 0.4, alpha: 0.6)
        var scene = GPUIScene(clearColor: destination)
        scene.addQuad(quad(source, mode: .multiply, width: Float(size.width), height: Float(size.height)))
        let actual = try render(scene, using: renderer, size: size)
        assertPixel(
            actual, x: 1025, y: 1025,
            equals: oracle(source, over: quantized(premultiplied(destination)), mode: .multiply), tolerance: 2)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
    }

    func testDestinationSnapshotValidatesActualDimensionsAndReleasesIdempotently() async throws {
        let owner = try makeStrictWARPDevice()
        defer { owner.release() }
        let device = try XCTUnwrap(owner.device)
        let context = try XCTUnwrap(owner.context)
        let pixels = [UInt8](repeating: 127, count: 8 * 6 * 4)
        let target = try makeStrictTarget(device: owner, width: 8, height: 6, pixels: pixels)
        defer { target.release() }
        let source = try XCTUnwrap(target.texture)
        let region = SubTextureRegion(originX: 2, originY: 1, width: 4, height: 3, textureWidth: 8, textureHeight: 6)
        let snapshot = try D3D11BlendDestinationSnapshot(
            device: device, context: context, source: source, region: region)
        XCTAssertNotNil(snapshot.srv)
        let copied = try XCTUnwrap(snapshot.texture)
        var description = D3D11_TEXTURE2D_DESC()
        copied.pointee.lpVtbl.pointee.GetDesc(copied, &description)
        XCTAssertEqual(description.Width, 4)
        XCTAssertEqual(description.Height, 3)
        XCTAssertEqual(description.Format, DXGI_FORMAT_B8G8R8A8_UNORM)
        XCTAssertEqual(snapshot.region, region)
        snapshot.release()
        XCTAssertNil(snapshot.srv)
        XCTAssertNil(snapshot.texture)
        snapshot.release()
        let mismatch = SubTextureRegion(textureWidth: 7, textureHeight: 6)
        XCTAssertThrowsError(
            try D3D11BlendDestinationSnapshot(device: device, context: context, source: source, region: mismatch))
        let empty = SubTextureRegion(originX: 8, originY: 0, width: 1, height: 1, textureWidth: 8, textureHeight: 6)
        XCTAssertThrowsError(
            try D3D11BlendDestinationSnapshot(device: device, context: context, source: source, region: empty))
        XCTAssertEqual(MemoryLayout<D3D11SeparableBlendUniforms>.stride, 32)
        XCTAssertEqual(MemoryLayout<D3D11SeparableBlendUniforms>.size, 32)
    }

    private func makeRenderer(size: IntSize) throws -> D3D11BatchKernel {
        let renderer = D3D11BatchKernel()
        do {
            try renderer.attachOffscreenWARPForTesting(size: size)
        } catch {
            renderer.detach()
            throw error
        }
        let adapter = renderer.backendDiagnostics
        guard adapter?.adapterIsSoftware == true else {
            renderer.detach()
            throw BatchRendererError(
                operation: "Validate strict WARP test device", hresult: HRESULT(bitPattern: 0x8000_4005))
        }
        print(
            "[D3D11SeparableBlendTests] adapter=\(adapter?.adapterDescription ?? "<unavailable>") "
                + "isSoftware=\(adapter?.adapterIsSoftware.map { String($0) } ?? "<unavailable>")")
        return renderer
    }

    private func makeStrictWARPDevice() throws -> WARPDevice {
        let owner = WARPDevice()
        var featureLevel = D3D_FEATURE_LEVEL(0)
        let requestedLevels = [D3D_FEATURE_LEVEL_11_0]
        let flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)
        let result = requestedLevels.withUnsafeBufferPointer { levels in
            D3D11CreateDevice(
                nil, D3D_DRIVER_TYPE_WARP, nil, flags,
                levels.baseAddress, UINT(levels.count), UINT(D3D11_SDK_VERSION),
                &owner.device, &featureLevel, &owner.context)
        }
        guard result >= 0, owner.device != nil, owner.context != nil else {
            owner.release()
            throw BatchRendererError(
                operation: "Create strict WARP test device",
                hresult: result < 0 ? result : HRESULT(bitPattern: 0x8000_4005))
        }
        return owner
    }

    private func makeStrictTarget(
        device owner: WARPDevice, width: Int, height: Int, pixels: [UInt8]
    ) throws -> WARPOffscreenTarget {
        let device = try XCTUnwrap(owner.device)
        let context = try XCTUnwrap(owner.context)
        XCTAssertEqual(pixels.count, width * height * 4)
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
        var transfersTarget = false
        defer { if !transfersTarget { target.release() } }
        let textureResult = device.pointee.lpVtbl.pointee.CreateTexture2D(device, &descriptor, nil, &target.texture)
        guard textureResult >= 0 else {
            throw BatchRendererError(operation: "Create strict WARP test texture", hresult: textureResult)
        }
        let texture = try XCTUnwrap(target.texture)
        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        pixels.withUnsafeBytes { bytes in
            context.pointee.lpVtbl.pointee.UpdateSubresource(
                context, resource, 0, nil,
                bytes.baseAddress, UINT(width * 4), 0)
        }
        let viewResult = device.pointee.lpVtbl.pointee.CreateRenderTargetView(device, resource, nil, &target.rtv)
        guard viewResult >= 0 else {
            throw BatchRendererError(operation: "Create strict WARP test view", hresult: viewResult)
        }
        _ = try XCTUnwrap(target.rtv)
        transfersTarget = true
        return target
    }

    private func render(_ scene: GPUIScene, using renderer: D3D11BatchKernel, size: IntSize) throws -> BitmapSurface {
        var finished = scene
        finished.finish()
        XCTAssertTrue(finished.validate().isEmpty)
        renderer.bindResources(for: finished)
        try renderer.render(scene: finished)
        XCTAssertEqual(renderer.lastFrameSubmission?.outcome, .offscreen)
        let result = try renderer.readOffscreenPixels()
        XCTAssertEqual(result.width, size.width)
        XCTAssertEqual(result.height, size.height)
        XCTAssertEqual(result.format.alphaMode, .premultiplied)
        return result
    }

    private func quad(
        _ color: Color, mode: BlendMode, x: Float = 0, y: Float = 0, width: Float, height: Float
    ) -> QuadPrimitive {
        QuadPrimitive(
            x: x, y: y, width: width, height: height,
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha,
            blendMode: Float(mode.rawValue))
    }

    private func image(
        _ id: Int32, x: Float = 0, y: Float = 0, width: Float, height: Float, opacity: Float = 1
    ) -> ImagePrimitive {
        ImagePrimitive(screenX: x, screenY: y, screenW: width, screenH: height, opacity: opacity, textureID: id)
    }

    private func bitmap(_ color: Color) -> BitmapSurface {
        let components = [color.blue, color.green, color.red, color.alpha]
        return BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4,
            pixels: Data(components.map { UInt8((Double($0) * 255).rounded()) }), format: .bgra8Straight)
    }

    private func premultiplied(_ color: Color) -> [Double] {
        let alpha = Double(color.alpha)
        return [Double(color.red) * alpha, Double(color.green) * alpha, Double(color.blue) * alpha, alpha]
    }

    private func quantized(_ value: [Double]) -> [Double] {
        value.map { (min(1, max(0, $0)) * 255).rounded() / 255 }
    }

    /// Independent scalar equation for test oracles, not the production
    /// adjusted-source helper: (1-as)D + (1-ad)S + as*ad*B(Cs,Cd).
    private func oracle(
        _ source: Color, over destination: [Double], mode: BlendMode, coverage: Double = 1
    ) -> [Double] {
        let sourceAlpha = Double(source.alpha) * coverage
        let destinationAlpha = destination[3]
        let sourceChannels = [Double(source.red), Double(source.green), Double(source.blue)]
        var result = [Double]()
        for index in 0..<3 {
            let sourceChannel = sourceChannels[index]
            let destinationChannel = destinationAlpha > 0 ? destination[index] / destinationAlpha : 0
            let blended: Double
            switch mode {
            case .multiply:
                blended = sourceChannel * destinationChannel
            case .screen:
                blended = sourceChannel + destinationChannel - sourceChannel * destinationChannel
            case .overlay:
                blended =
                    destinationChannel <= 0.5
                    ? 2 * sourceChannel * destinationChannel
                    : 1 - 2 * (1 - sourceChannel) * (1 - destinationChannel)
            case .normal, .additive:
                // Additive remains the prior source-over behavior in this slice.
                blended = sourceChannel
            }
            result.append(
                (1 - sourceAlpha) * destination[index]
                    + (1 - destinationAlpha) * sourceAlpha * sourceChannel
                    + sourceAlpha * destinationAlpha * blended)
        }
        result.append(sourceAlpha + destinationAlpha * (1 - sourceAlpha))
        return result
    }

    private func sourceOver(_ source: [Double], over destination: [Double]) -> [Double] {
        zip(source, destination).map { pair in pair.0 + (1 - source[3]) * pair.1 }
    }

    private func rgba(_ bitmap: BitmapSurface, x: Int, y: Int) -> [Double] {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        return [2, 1, 0, 3].map { Double(bitmap.pixels[offset + $0]) / 255 }
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, equals expected: [Double], tolerance: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = rgba(bitmap, x: x, y: y)
        for channel in 0..<4 {
            XCTAssertEqual(
                (actual[channel] * 255).rounded(), (expected[channel] * 255).rounded(), accuracy: tolerance,
                "Pixel (\(x),\(y)) channel \(channel)", file: file, line: line)
        }
    }

    private func assertCPUParity(
        _ actual: BitmapSurface, scene: GPUIScene, size: IntSize, tolerance: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let reference = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        XCTAssertEqual(actual.width, reference.width, file: file, line: line)
        XCTAssertEqual(actual.height, reference.height, file: file, line: line)
        XCTAssertEqual(actual.format.alphaMode, reference.format.alphaMode, file: file, line: line)
        let report = comparePixels(actual, reference, tolerance: tolerance)
        XCTAssertEqual(report.matchRatio, 1, "Maximum channel delta \(report.maxChannelDelta)", file: file, line: line)
    }
}
