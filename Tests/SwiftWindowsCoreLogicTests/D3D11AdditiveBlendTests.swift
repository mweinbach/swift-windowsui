import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Actual offscreen batch execution on strict WARP. Oracles use the clamped
/// premultiplied sum, not either production blend helper. No skips or fallback.
@MainActor
final class D3D11AdditiveBlendTests: XCTestCase {
    func testPremultipliedAdditionAcrossAlphaExtremesAndSaturation() async throws {
        let size = IntSize(width: 16, height: 16)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        let destinations = [
            Color(red: 0.2, green: 0.8, blue: 0.45, alpha: 1),
            Color(red: 0.75, green: 0.25, blue: 0.6, alpha: 0.5),
            Color(red: 0.8, green: 0.2, blue: 0.7, alpha: 0.125),
            Color(red: 0.9, green: 0.6, blue: 0.3, alpha: 0),
        ]
        var saturatedPixels = 0
        var differsFromSourceOver = 0
        for destination in destinations {
            let control = try render(GPUIScene(clearColor: destination), using: renderer)
            let initial = rgba(control, x: 0, y: 0)
            assertClear(initial, color: destination)
            for alpha in [Float(0), 0.25, 0.6, 1] {
                let source = Color(red: 0.8, green: 0.4, blue: 0.7, alpha: alpha)
                var scene = GPUIScene(clearColor: destination)
                scene.addQuad(quad(source, x: 2, y: 2, width: 12, height: 12))
                let actual = try render(scene, using: renderer)
                let expected = adding(premultiplied(source), to: initial)
                assertPixel(actual, x: 8, y: 8, equals: expected, tolerance: 2)
                assertPixel(actual, x: 0, y: 0, equals: initial, tolerance: 0)
                if alpha == 0 { XCTAssertEqual(actual.pixels, control.pixels) }
                if expected.prefix(3).contains(1) { saturatedPixels += 1 }
                if zip(expected, sourceOver(premultiplied(source), over: initial)).contains(where: {
                    abs($0.0 - $0.1) > 0.05
                }) {
                    differsFromSourceOver += 1
                }
                assertCPUParity(actual, scene: scene, size: size, tolerance: 3)
            }
        }
        XCTAssertGreaterThan(saturatedPixels, 0)
        XCTAssertGreaterThan(differsFromSourceOver, 4)
    }

    func testRoundedRotatedClipCoveragePrecedesAdditiveClamping() async throws {
        let size = IntSize(width: 32, height: 28)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        let destination = Color(red: 0.85, green: 0.2, blue: 0.6, alpha: 1)
        let source = Color(red: 1, green: 0.5, blue: 0.25, alpha: 0.8)
        let control = try render(GPUIScene(clearColor: destination), using: renderer)
        let initial = rgba(control, x: 0, y: 0)
        assertClear(initial, color: destination)
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
            let mask = try render(maskScene, using: renderer)
            shape.startR = source.red
            shape.startG = source.green
            shape.startB = source.blue
            shape.startA = source.alpha
            shape.endR = source.red
            shape.endG = source.green
            shape.endB = source.blue
            shape.endA = source.alpha
            shape.blendMode = Float(BlendMode.additive.rawValue)
            var scene = GPUIScene(clearColor: destination)
            scene.addQuad(shape)
            let actual = try render(scene, using: renderer)
            var fractional = 0
            var distinguishesPostClampCoverage = 0
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) {
                    let coverage = rgba(mask, x: x, y: y)[3]
                    let expected = adding(premultiplied(source).map { $0 * coverage }, to: initial)
                    assertPixel(actual, x: x, y: y, equals: expected, tolerance: 3)
                    if coverage > 0 && coverage < 1 {
                        fractional += 1
                        let wrong = initial[0] + coverage * (min(1, initial[0] + Double(source.alpha)) - initial[0])
                        if abs(expected[0] - wrong) > 0.04 { distinguishesPostClampCoverage += 1 }
                    }
                }
            }
            XCTAssertGreaterThan(fractional, 8)
            XCTAssertGreaterThan(distinguishesPostClampCoverage, 4)
        }
    }

    func testEachAdditiveDrawSeesPriorFamiliesAndRestoresSourceOver() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        let destination = Color(red: 0.3, green: 0.2, blue: 0.1, alpha: 0.5)
        let first = Color(red: 0.6, green: 0.2, blue: 0.4, alpha: 0.4)
        let second = Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.3)
        let final = Color(red: 0.9, green: 0.1, blue: 0.2, alpha: 0.35)
        let bitmapID: Int32 = 88_401
        let bitmapValue = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([77, 179, 26, 255]), format: .bgra8Straight)
        var scene = GPUIScene(clearColor: destination)
        scene.addQuad(quad(first, width: 32, height: 24))
        scene.bindImageResource(bitmapValue, for: bitmapID)
        scene.addImage(image(bitmapID, x: 8, y: 4, width: 16, height: 16))
        scene.addQuad(quad(second, x: 4, y: 2, width: 24, height: 20))
        scene.addQuad(quad(final, mode: .normal, x: 12, y: 8, width: 8, height: 8))
        let actual = try render(scene, using: renderer)
        let firstValue = quantized(adding(premultiplied(first), to: quantized(premultiplied(destination))))
        assertPixel(actual, x: 2, y: 12, equals: firstValue, tolerance: 2)
        let afterBitmap = adding(premultiplied(second), to: rgba(bitmapValue, x: 0, y: 0))
        assertPixel(actual, x: 10, y: 12, equals: afterBitmap, tolerance: 2)
        assertPixel(
            actual, x: 16, y: 12, equals: sourceOver(premultiplied(final), over: quantized(afterBitmap)), tolerance: 3)
        assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
    }

    func testRepeatedCurrentTargetChildrenReadTheirImmediateDestination() async throws {
        let size = IntSize(width: 40, height: 24)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        let destination = Color(red: 0.7, green: 0.2, blue: 0.4, alpha: 0.5)
        let source = Color(red: 0.8, green: 0.3, blue: 0.2, alpha: 0.5)
        let middle = Color(red: 0.2, green: 0.6, blue: 0.3, alpha: 0.4)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(source, width: 12, height: 12))
        var scene = GPUIScene(clearColor: destination)
        let id = scene.registerImageRenderPass(child, size: IntSize(width: 12, height: 12), input: .currentTarget)
        let occurrence = image(id, x: 18, y: 6, width: 12, height: 12)
        scene.addImage(occurrence)
        scene.addQuad(quad(middle, mode: .normal, x: 18, y: 6, width: 12, height: 12))
        scene.addImage(occurrence)
        let actual = try render(scene, using: renderer)
        var expected = quantized(adding(premultiplied(source), to: quantized(premultiplied(destination))))
        expected = quantized(sourceOver(premultiplied(middle), over: expected))
        expected = adding(premultiplied(source), to: expected)
        assertPixel(actual, x: 24, y: 12, equals: expected, tolerance: 3)
        assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
    }

    func testIndependentChildAdditionUsesItsOwnClear() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        let destination = Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.6)
        let childClear = Color(red: 0.1, green: 0.4, blue: 0.8, alpha: 0.5)
        let source = Color(red: 0.7, green: 0.3, blue: 0.25, alpha: 0.3)
        var child = GPUIScene(clearColor: childClear)
        child.addQuad(quad(source, width: 12, height: 12))
        var scene = GPUIScene(clearColor: destination)
        let id = scene.registerImageRenderPass(child, size: IntSize(width: 12, height: 12))
        scene.addImage(image(id, x: 10, y: 6, width: 12, height: 12))
        let actual = try render(scene, using: renderer)
        let childValue = quantized(adding(premultiplied(source), to: quantized(premultiplied(childClear))))
        assertPixel(
            actual, x: 16, y: 12, equals: sourceOver(childValue, over: quantized(premultiplied(destination))),
            tolerance: 3)
        assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
    }

    func testIsolatedAdditionPreservesZeroAlphaEmissionAndClampsBeforeGroupOpacity() async throws {
        let size = IntSize(width: 24, height: 24)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        let source = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        for destination in [
            Color(red: 0, green: 1, blue: 0, alpha: 1), Color(red: 0.8, green: 0.2, blue: 0.4, alpha: 1),
            Color(red: 0.75, green: 0.25, blue: 0.5, alpha: 0.8),
        ] {
            let control = try render(GPUIScene(clearColor: destination), using: renderer)
            let initial = rgba(control, x: 0, y: 0)
            assertClear(initial, color: destination)
            for opacity in [Float(0.5), 1] {
                var child = GPUIScene(clearColor: .clear)
                child.addQuad(quad(source, width: 12, height: 12))
                var scene = GPUIScene(clearColor: destination)
                let id = scene.registerImageRenderPass(
                    child, size: IntSize(width: 12, height: 12), input: .isolatedBackdrop)
                scene.addImage(image(id, x: 6, y: 6, width: 12, height: 12, opacity: opacity))
                let actual = try render(scene, using: renderer)
                let complete = adding(premultiplied(source), to: initial)
                let expected = zip(complete, initial).map { Double(opacity) * $0.0 + (1 - Double(opacity)) * $0.1 }
                assertPixel(actual, x: 12, y: 12, equals: expected, tolerance: 3)
                assertPixel(actual, x: 0, y: 0, equals: initial, tolerance: 0)
                assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
            }
        }
    }

    func testNestedCurrentTargetAndIsolatedChildrenCarryEmissionWithoutCoverage() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        let destination = Color(red: 0.8, green: 0.2, blue: 0.4, alpha: 1)
        let source = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        for input in [GPUISceneImageRenderPassInput.currentTarget, .isolatedBackdrop] {
            var inner = GPUIScene(clearColor: .clear)
            inner.addQuad(quad(source, width: 8, height: 8))
            var outer = GPUIScene(clearColor: .clear)
            let innerID = outer.registerImageRenderPass(inner, size: IntSize(width: 8, height: 8), input: input)
            outer.addImage(image(innerID, x: 4, y: 4, width: 8, height: 8, opacity: 0.5))
            var scene = GPUIScene(clearColor: destination)
            let outerID = scene.registerImageRenderPass(
                outer, size: IntSize(width: 16, height: 16), input: .isolatedBackdrop)
            scene.addImage(image(outerID, x: 8, y: 4, width: 16, height: 16, opacity: 0.5))
            let actual = try render(scene, using: renderer)
            assertPixel(actual, x: 16, y: 12, equals: [0.85, 0.2, 0.4, 1], tolerance: 3)
            assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
            XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
        }
    }

    func testContentBlurFiltersEmissionWithoutFilteringUntouchedBackdropChannels() async throws {
        let size = IntSize(width: 40, height: 32)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0.2, blue: 0.4, alpha: 1))
        for x in stride(from: 0, to: 40, by: 4) {
            scene.addQuad(
                quad(Color(red: 0, green: 0.8, blue: 0.4, alpha: 1), mode: .normal, x: Float(x), width: 2, height: 32))
        }
        let before = try render(scene, using: renderer)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5), x: 6, y: 6, width: 12, height: 8))
        let id = scene.registerImageRenderPass(
            child, size: IntSize(width: 24, height: 20), input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(image(id, x: 8, y: 6, width: 24, height: 20, opacity: 0.5))
        let actual = try render(scene, using: renderer)
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                let original = rgba(before, x: x, y: y)
                let result = rgba(actual, x: x, y: y)
                XCTAssertEqual(Array(result[1...3]), Array(original[1...3]), "Untouched G/B/A at (\(x),\(y))")
                if x < 8 || x >= 32 || y < 6 || y >= 26 { XCTAssertEqual(result, original) }
            }
        }
        XCTAssertGreaterThan(rgba(actual, x: 20, y: 16)[0], 0.2)
        XCTAssertGreaterThan(rgba(actual, x: 13, y: 16)[0], 0, "An additive red halo must survive alpha-zero filtering")
        assertCPUParity(actual, scene: scene, size: size, tolerance: 5)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
    }

    func testMaterialAndUnknownSelectorsStayUnchangedWhileFollowingAdditiveReadsMaterial() async throws {
        let size = IntSize(width: 24, height: 24)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        let destination = Color(red: 0.2, green: 0.4, blue: 0.7, alpha: 0.5)
        let tint = Color(red: 0.6, green: 0.2, blue: 0.4, alpha: 0.3)
        var material = quad(tint, mode: .normal, x: 2, y: 2, width: 20, height: 20)
        material.blurRadius = 3
        var baselineScene = GPUIScene(clearColor: destination)
        baselineScene.addQuad(material)
        let baseline = try render(baselineScene, using: renderer)
        material.blendMode = Float(BlendMode.additive.rawValue)
        var scene = GPUIScene(clearColor: destination)
        scene.addQuad(material)
        XCTAssertEqual(try render(scene, using: renderer).pixels, baseline.pixels)
        let source = Color(red: 0.3, green: 0.5, blue: 0.2, alpha: 0.4)
        scene.addQuad(quad(source, x: 4, y: 4, width: 16, height: 16))
        let actual = try render(scene, using: renderer)
        assertPixel(
            actual, x: 12, y: 12, equals: adding(premultiplied(source), to: rgba(baseline, x: 12, y: 12)), tolerance: 2)
        // Scene admission clamps the encoding to 0...4. Fractional values
        // inside that interval must not be truncated into supported modes.
        for selector in [Float(0.25), 1.25, 2.25, 3.25, 3.999] {
            var ordinary = quad(tint, mode: .normal, width: 24, height: 24)
            var normalScene = GPUIScene(clearColor: destination)
            normalScene.addQuad(ordinary)
            let normal = try render(normalScene, using: renderer)
            ordinary.blendMode = selector
            var unknownScene = GPUIScene(clearColor: destination)
            unknownScene.addQuad(ordinary)
            XCTAssertEqual(try render(unknownScene, using: renderer).pixels, normal.pixels)
        }
    }

    func testFailureAfterAdditiveBindingsRestoresNestedTargetsAndNextFrame() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        var recovery = GPUIScene(clearColor: Color(red: 0.4, green: 0.2, blue: 0.6, alpha: 0.5))
        recovery.addQuad(quad(Color(red: 0.8, green: 0.3, blue: 0.1, alpha: 0.4), width: 20, height: 20))
        recovery.addQuad(
            quad(Color(red: 0.2, green: 0.7, blue: 0.4, alpha: 0.5), mode: .normal, x: 8, y: 4, width: 20, height: 16))
        let baseline = try render(recovery, using: renderer)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5), width: 12, height: 12))
        for input in [GPUISceneImageRenderPassInput.currentTarget, .isolatedBackdrop] {
            var scene = GPUIScene(clearColor: .white)
            let id = scene.registerImageRenderPass(child, size: IntSize(width: 12, height: 12), input: input)
            scene.addImage(image(id, x: 10, y: 6, width: 12, height: 12))
            _ = try render(scene, using: renderer)
            let warmed = renderer.liveCOMObjectCountForTesting
            renderer.failSeparableBlendAfterDestinationBindingForTesting = true
            renderer.bindResources(for: scene)
            XCTAssertThrowsError(try renderer.render(scene: scene))
            XCTAssertEqual(renderer.lastFrameSubmission?.outcome, .aborted)
            XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmed)
            renderer.failSeparableBlendAfterDestinationBindingForTesting = false
            XCTAssertEqual(try render(recovery, using: renderer).pixels, baseline.pixels)
        }
    }

    func testRepeatedFramesResizeAndDetachReleaseAdditiveResources() async throws {
        let initialSize = IntSize(width: 32, height: 24)
        let renderer = try makeRenderer(initialSize)
        defer { renderer.detach() }
        var scene = GPUIScene(clearColor: Color(red: 0.7, green: 0.25, blue: 0.5, alpha: 0.6))
        scene.addQuad(quad(Color(red: 0.8, green: 0.2, blue: 0.4, alpha: 0.4), x: 2, y: 2, width: 20, height: 18))
        _ = try render(scene, using: renderer)
        let warmed = renderer.liveCOMObjectCountForTesting
        for index in 0..<6 {
            let size = index % 2 == 0 ? IntSize(width: 40, height: 32) : initialSize
            try renderer.resize(to: size)
            scene.clearColor = Color(red: Float(index) / 10, green: 0.4, blue: 0.7, alpha: 0.55)
            let actual = try render(scene, using: renderer)
            assertCPUParity(actual, scene: scene, size: size, tolerance: 3)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmed)
        }
        renderer.detach()
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, 0)
        XCTAssertFalse(renderer.isAttached)
    }

    func testEscapedEmissionSurvivesTransparentOutputAndLaterSourceOver() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        var scene = escapedEmissionScene()
        let escaped = try render(scene, using: renderer)
        // Radius 1, sigma .5 has normalized side weight .106506979.
        // The half-alpha red stripe therefore emits .05325349 at its sides,
        // where the frozen green stripe has no alpha at all.
        assertPixel(escaped, x: 15, y: 16, equals: [0.05325349, 0, 0, 0], tolerance: 2)
        assertPixel(escaped, x: 16, y: 16, equals: [0.39349302, 1, 0, 1], tolerance: 3)
        XCTAssertEqual(rgba(escaped, x: 15, y: 16)[3], 0)
        assertCPUParity(escaped, scene: scene, size: size, tolerance: 4)
        scene.addQuad(quad(Color(red: 0, green: 0, blue: 1, alpha: 0.5), mode: .normal, width: 32, height: 32))
        let after = try render(scene, using: renderer)
        assertPixel(after, x: 15, y: 16, equals: [0.02662675, 0, 0.5, 0.5], tolerance: 3)
        assertPixel(after, x: 16, y: 16, equals: [0.19674651, 0.5, 0.5, 1], tolerance: 3)
        assertCPUParity(after, scene: scene, size: size, tolerance: 4)
    }

    func testCurrentTargetPartialReplacementPreservesEscapedEmission() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        var scene = escapedEmissionScene()
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 0, green: 0, blue: 1, alpha: 0.5), mode: .normal, width: 32, height: 32))
        let id = scene.registerImageRenderPass(child, size: size, input: .currentTarget)
        scene.addImage(image(id, width: 32, height: 32, opacity: 0.5))
        let actual = try render(scene, using: renderer)
        // The child attenuates red by .5; replacement opacity .5 retains
        // half the original destination, for a total red factor of .75.
        assertPixel(actual, x: 15, y: 16, equals: [0.03994012, 0, 0.25, 0.25], tolerance: 3)
        assertPixel(actual, x: 16, y: 16, equals: [0.29511977, 0.75, 0.25, 1], tolerance: 3)
        assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
    }

    func testNestedIndependentImagesPreserveAlphaZeroEmissionAndOpacity() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        var middle = GPUIScene(clearColor: .clear)
        let innerID = middle.registerImageRenderPass(escapedEmissionScene(), size: size)
        middle.addImage(image(innerID, width: 32, height: 32, opacity: 0.5))
        var scene = GPUIScene(clearColor: .clear)
        let middleID = scene.registerImageRenderPass(middle, size: size)
        scene.addImage(image(middleID, width: 32, height: 32, opacity: 0.5))
        let actual = try render(scene, using: renderer)
        assertPixel(actual, x: 15, y: 16, equals: [0.01331337, 0, 0, 0], tolerance: 2)
        assertPixel(actual, x: 16, y: 16, equals: [0.09837326, 0.25, 0, 0.25], tolerance: 3)
        XCTAssertEqual(rgba(actual, x: 15, y: 16)[3], 0)
        XCTAssertGreaterThan(rgba(actual, x: 15, y: 16)[0], 0)
        assertCPUParity(actual, scene: scene, size: size, tolerance: 4)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
    }

    func testSeparableModesClampImportedBackdropColorWhileRetainingEmission() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try makeRenderer(size)
        defer { renderer.detach() }
        // Fixed premultiplied RGBA oracles, independent of the CPU renderer.
        // For D=(.6,0,0,.2), clamp only Cd to (1,0,0) inside B(Cs,Cd);
        // keep the raw retained term .5*D. Alpha-zero emission and ordinary
        // premultiplied input are controls for the same three modes.
        let cases: [(pixel: [UInt8], mode: BlendMode, expected: [Double])] = [
            ([0, 0, 153, 51], .multiply, [0.55, 0.2, 0.2, 0.6]),
            ([0, 0, 153, 51], .screen, [0.6, 0.25, 0.25, 0.6]),
            ([0, 0, 153, 51], .overlay, [0.6, 0.2, 0.2, 0.6]),
            ([0, 0, 153, 0], .multiply, [0.55, 0.25, 0.25, 0.5]),
            ([0, 0, 153, 0], .screen, [0.55, 0.25, 0.25, 0.5]),
            ([0, 0, 153, 0], .overlay, [0.55, 0.25, 0.25, 0.5]),
            ([0, 0, 51, 102], .multiply, [0.3, 0.15, 0.15, 0.7]),
            ([0, 0, 51, 102], .screen, [0.4, 0.25, 0.25, 0.7]),
            ([0, 0, 51, 102], .overlay, [0.35, 0.15, 0.15, 0.7]),
        ]
        for vector in cases {
            let bitmap = BitmapSurface(
                width: 1, height: 1, bytesPerRow: 4,
                pixels: Data(vector.pixel), format: .bgra8Premultiplied)
            var scene = GPUIScene(clearColor: .clear)
            let texture: Int32 = 88_403
            scene.bindImageResource(bitmap, for: texture)
            scene.addImage(image(texture, width: 32, height: 32))
            scene.addQuad(
                quad(
                    Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5),
                    mode: vector.mode, x: 8, y: 8, width: 16, height: 16))
            let actual = try render(scene, using: renderer)
            assertPixel(actual, x: 16, y: 16, equals: vector.expected, tolerance: 2)
            // No color effect pass or CPU oracle participates in this test.
            XCTAssertEqual((0..<4).map { actual.pixels[$0] }, vector.pixel)
        }
    }

    private func escapedEmissionScene() -> GPUIScene {
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 1), mode: .normal, x: 16, width: 1, height: 32))
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5), x: 16, width: 1, height: 32))
        let id = scene.registerImageRenderPass(
            child, size: IntSize(width: 32, height: 32), input: .isolatedBackdrop, contentBlurRadius: 1)
        scene.addImage(image(id, width: 32, height: 32))
        return scene
    }

    private func makeRenderer(_ size: IntSize) throws -> D3D11BatchKernel {
        let renderer = D3D11BatchKernel()
        do { try renderer.attachOffscreenWARPForTesting(size: size) } catch {
            renderer.detach()
            throw error
        }
        guard renderer.backendDiagnostics?.adapterIsSoftware == true else {
            renderer.detach()
            throw BatchRendererError(
                operation: "Validate additive WARP device", hresult: HRESULT(bitPattern: 0x8000_4005))
        }
        return renderer
    }

    private func render(_ scene: GPUIScene, using renderer: D3D11BatchKernel) throws -> BitmapSurface {
        var finished = scene
        finished.finish()
        XCTAssertTrue(finished.validate().isEmpty)
        renderer.bindResources(for: finished)
        try renderer.render(scene: finished)
        XCTAssertEqual(renderer.lastFrameSubmission?.outcome, .offscreen)
        let result = try renderer.readOffscreenPixels()
        XCTAssertEqual(result.format, .bgra8Premultiplied)
        return result
    }

    private func quad(
        _ color: Color, mode: BlendMode = .additive, x: Float = 0, y: Float = 0, width: Float, height: Float
    ) -> QuadPrimitive {
        QuadPrimitive(
            x: x, y: y, width: width, height: height, startR: color.red, startG: color.green, startB: color.blue,
            startA: color.alpha, endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha,
            blendMode: Float(mode.rawValue))
    }

    private func image(_ id: Int32, x: Float = 0, y: Float = 0, width: Float, height: Float, opacity: Float = 1)
        -> ImagePrimitive
    {
        ImagePrimitive(screenX: x, screenY: y, screenW: width, screenH: height, opacity: opacity, textureID: id)
    }

    private func premultiplied(_ color: Color) -> [Double] {
        let alpha = Double(color.alpha)
        return [Double(color.red) * alpha, Double(color.green) * alpha, Double(color.blue) * alpha, alpha]
    }

    private func adding(_ source: [Double], to destination: [Double]) -> [Double] {
        zip(source, destination).map { min(1, $0.0 + $0.1) }
    }

    private func sourceOver(_ source: [Double], over destination: [Double]) -> [Double] {
        zip(source, destination).map { $0.0 + (1 - source[3]) * $0.1 }
    }

    private func quantized(_ value: [Double]) -> [Double] {
        value.map { (min(1, max(0, $0)) * 255).rounded() / 255 }
    }

    private func rgba(_ bitmap: BitmapSurface, x: Int, y: Int) -> [Double] {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        return [2, 1, 0, 3].map { Double(bitmap.pixels[offset + $0]) / 255 }
    }

    private func assertClear(_ actual: [Double], color: Color, file: StaticString = #filePath, line: UInt = #line) {
        let input: [Float] = [
            color.red * color.alpha, color.green * color.alpha, color.blue * color.alpha, color.alpha,
        ]
        for channel in 0..<4 {
            XCTAssertLessThanOrEqual(
                abs(actual[channel] * 255 - Double(input[channel]) * 255), Double(Float(0.6)), file: file, line: line)
        }
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, equals expected: [Double], tolerance: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = rgba(bitmap, x: x, y: y)
        for channel in 0..<4 {
            XCTAssertEqual(
                (actual[channel] * 255).rounded(), (expected[channel] * 255).rounded(), accuracy: tolerance,
                "Pixel (\(x),\(y)) RGBA channel \(channel)", file: file, line: line)
        }
    }

    private func assertCPUParity(
        _ actual: BitmapSurface, scene: GPUIScene, size: IntSize, tolerance: Int, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let reference = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        let report = comparePixels(actual, reference, tolerance: tolerance)
        XCTAssertEqual(report.matchRatio, 1, "Maximum channel delta \(report.maxChannelDelta)", file: file, line: line)
    }
}
