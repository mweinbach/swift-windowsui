import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// WARP readback for one original rounded shape intersected with rectangular
/// rejection bounds. The independent probes distinguish this geometry from a
/// maximum scalar radius, squared cut corners, and radii capped to the crop.
/// These tests do not qualify hardware adapters or native SwiftUI semantics.
@MainActor
final class OriginalAnchorClipD3D11Tests: XCTestCase {
    private static let surface = IntSize(width: 128, height: 128)
    private static let body = Rect(x: 0, y: 0, width: 100, height: 100)

    private enum Family: CaseIterable {
        case quad, glyph, pixelGlyph, image, shadow, path
    }

    private struct Clip {
        var rejection: Rect?
        var shape: Rect?
        var corners: [Double]
        var scalar: Double = 0

        func scaled(by scale: Double) -> Clip {
            Clip(
                rejection: rejection?.scaled(by: scale), shape: shape?.scaled(by: scale),
                corners: corners.map { $0 * scale }, scalar: scalar * scale)
        }
    }

    private var partialArc: Clip {
        Clip(
            rejection: Rect(x: 0, y: 4, width: 100, height: 96), shape: Self.body,
            corners: [40, 4, 8, 0])
    }

    private var tinyCrop: Clip {
        Clip(
            rejection: Rect(x: 1, y: 1, width: 1, height: 1),
            shape: Rect(x: 0, y: 0, width: 20, height: 20), corners: [5, 5, 5, 5])
    }

    private var tinyCropCoverage: Double {
        // Geometric helper samples (.5,.5), (1.5,.5), (.5,1.5) are outside R.
        // This oracle is independent of GPUIClipRegion and shader helpers.
        0.5 - (sqrt(24.5) - 5) / (2 * (sqrt(40.5) - sqrt(32.5)))
    }

    func testPartialArcAndSquareCornerAcrossEveryPrimitiveFamily() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        for family in Family.allCases {
            let pixels = try assertReadback(scene(family, clip: partialArc), using: renderer)
            for bitmap in [pixels.gpu, pixels.cpu] {
                // Original TL circle: (4.5-40)^2 + (8.5-40)^2 = 2252.5 > 1600.
                assertCoverage(bitmap, x: 4, y: 8, expected: 0, "\(family): original partial arc")
                assertCoverage(bitmap, x: 1, y: 98, expected: 1, "\(family): square BL corner")
            }
        }
    }

    func testThinCropDoesNotCapRadiusAgainstRejectionHeight() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let clip = Clip(
            rejection: Rect(x: 0, y: 0, width: 100, height: 4), shape: Self.body,
            corners: [40, 0, 0, 0])
        for family in Family.allCases {
            let pixels = try assertReadback(scene(family, clip: clip), using: renderer)
            for bitmap in [pixels.gpu, pixels.cpu] {
                // The original radius stays 40. Capping to the crop yields 2
                // and incorrectly fills this center (original distance^2=2888.5).
                assertCoverage(bitmap, x: 2, y: 1, expected: 0, "\(family): thin crop")
                assertCoverage(bitmap, x: 60, y: 1, expected: 1, "\(family): straight-edge control")
            }
        }
    }

    func testOnePixelCropKeepsUngatedDerivativeSamplesAndUniformCorners() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        for family in Family.allCases {
            let pixels = try assertReadback(scene(family, clip: tinyCrop), using: renderer)
            for bitmap in [pixels.gpu, pixels.cpu] {
                assertCoverage(
                    bitmap, x: 1, y: 1, expected: tinyCropCoverage,
                    "\(family): original radius 5, helper lanes outside the one-pixel crop")
                assertCoverage(bitmap, x: 0, y: 1, expected: 0, "\(family): left crop gate")
                assertCoverage(bitmap, x: 2, y: 1, expected: 0, "\(family): right crop gate")
            }
        }
    }

    func testExplicitAnchorGatesEvenWhenTheCurrentCornerIsSquare() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        for corners in [[Double](repeating: 0, count: 4), [0, 0, 8, 0]] {
            let clip = Clip(
                rejection: Self.body, shape: Rect(x: 20.75, y: 20, width: 60, height: 60),
                corners: corners)
            for family in Family.allCases {
                let pixels = try assertReadback(scene(family, clip: clip), using: renderer)
                for bitmap in [pixels.gpu, pixels.cpu] {
                    // R contains this center, but it is .25px left of S.
                    assertCoverage(bitmap, x: 20, y: 50, expected: 0, "\(family): explicit S gate")
                    assertCoverage(bitmap, x: 50, y: 50, expected: 1, "\(family): S interior")
                }
            }
        }
    }

    func testAbsentPackedRejectionAndNilPathRejectionRemainDistinct() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let clips = [
            Clip(rejection: nil, shape: nil, corners: [40, 0, 0, 0]),
            Clip(
                rejection: nil, shape: Rect(x: 20.75, y: 20, width: 60, height: 60),
                corners: [0, 0, 0, 0]),
        ]
        for (index, clip) in clips.enumerated() {
            let point = index == 0 ? (x: 4, y: 8) : (x: 20, y: 50)
            for family in Family.allCases {
                let pixels = try assertReadback(scene(family, clip: clip), using: renderer)
                for bitmap in [pixels.gpu, pixels.cpu] {
                    assertCoverage(
                        bitmap, x: point.x, y: point.y, expected: family == .path ? 0 : 1,
                        "\(family): a path uses target R; a packed absent R stays inactive")
                }
            }
        }
    }

    func testZeroPayloadUsesCurrentScalarAndRejectionBounds() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        // apply() mutates R/scalar after the primitive initializer and after
        // assigning absent S. A default payload must not freeze earlier values.
        let scalar = Clip(
            rejection: Rect(x: 8, y: 8, width: 40, height: 40), shape: nil,
            corners: [0, 0, 0, 0], scalar: 12)
        let explicit = Clip(
            rejection: scalar.rejection, shape: scalar.rejection, corners: [12, 12, 12, 12])
        for family in Family.allCases {
            let fallback = try assertReadback(scene(family, clip: scalar), using: renderer)
            let resolved = try assertReadback(scene(family, clip: explicit), using: renderer)
            XCTAssertEqual(fallback.gpu.pixels, resolved.gpu.pixels, "\(family): current scalar fallback")
            assertCoverage(fallback.gpu, x: 9, y: 9, expected: 0, "\(family): mutated rejection origin")
            assertCoverage(fallback.gpu, x: 24, y: 24, expected: 1, "\(family): interior")
        }
    }

    func testFractionalDeviceScalePreservesAnchorAndOriginalArcs() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let clip = Clip(
            rejection: Rect(x: 2.25, y: 6.5, width: 48, height: 44),
            shape: Rect(x: 2.25, y: 2.5, width: 48, height: 48), corners: [20, 3, 7, 0])
        for scale in [1.25, 1.5, 2.0] {
            for family in Family.allCases {
                let value = scene(
                    family, clip: clip, body: Rect(x: 0, y: 0, width: 64, height: 64), scale: scale)
                let pixels = try assertReadback(value, using: renderer)
                for bitmap in [pixels.gpu, pixels.cpu] {
                    assertCoverage(
                        bitmap, x: Int(4.25 * scale), y: Int(7.5 * scale), expected: 0,
                        "\(family) at \(scale)x: original TL arc")
                    assertCoverage(
                        bitmap, x: Int(3.75 * scale), y: Int(48.5 * scale), expected: 1,
                        "\(family) at \(scale)x: square BL corner")
                }
            }
        }
    }

    func testMixedFamilyOrderAndTranslucentCoverageAreUnchanged() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let families: [Family] = [.image, .quad, .glyph, .shadow, .path, .pixelGlyph]
        let colors = [
            Color(red: 1, green: 0, blue: 0, alpha: 0.5),
            Color(red: 0, green: 1, blue: 0, alpha: 0.5),
            Color(red: 0, green: 0, blue: 1, alpha: 0.5),
        ]
        var value = GPUIScene(clearColor: .clear)
        for (index, family) in families.enumerated() {
            append(family, clip: partialArc, color: colors[index % 3], into: &value)
        }
        value.finish()
        XCTAssertEqual(
            value.presentationOrder().map(\.kind), [.image, .quad, .glyph, .shadow, .path, .pixelGlyph])
        XCTAssertEqual(value.presentationOrder().map(\.layerIndex), [0, 0, 0, 0, 0, 0])
        XCTAssertEqual(value.presentationOrder().map { $0.range.count }, [1, 1, 1, 1, 1, 1])
        let pixels = try assertReadback(value, using: renderer)
        for bitmap in [pixels.gpu, pixels.cpu] {
            assertCoverage(bitmap, x: 4, y: 8, expected: 0, "Every family keeps the original arc")
            // Six successive half-alpha source-over operations, in the order above.
            assertPixel(
                bitmap, x: 1, y: 98, red: 0.140625, green: 0.28125, blue: 0.5625, alpha: 0.984375)
        }
    }

    func testMaterialReplacementAndIsolatedCoverageUseTheSameOriginalClip() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        for route in CompositeRoute.allCases {
            let pixels = try assertReadback(compositeScene(route, clip: partialArc), using: renderer)
            let opacity = route.imageOpacity
            for bitmap in [pixels.gpu, pixels.cpu] {
                assertPixel(bitmap, x: 4, y: 8, red: 0.5, green: 0, blue: 0, alpha: 0.5)
                // Untouched D=(.5,0,0,.5), material F=(.3,0,.4,.7), C=1.
                // Replacement uses coverage, not material alpha.
                assertPixel(
                    bitmap, x: 1, y: 98, red: 0.5 - 0.2 * opacity, green: 0,
                    blue: 0.4 * opacity, alpha: 0.5 + 0.2 * opacity)
            }
        }
    }

    func testOnePixelOutputClipIsAppliedOnceAfterSourceEffectsAndBlur() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(.white, body: Rect(x: 0, y: 0, width: 128, height: 128)))
        child.finish()
        var filteredChild = GPUIScene(clearColor: .clear)
        let filteredID = filteredChild.registerImageRenderPass(
            child, size: Self.surface, colorEffects: [.brightness(-0.25), .contrast(2)])
        filteredChild.addImage(image(filteredID, body: Rect(x: 0, y: 0, width: 128, height: 128)))
        filteredChild.finish()
        var value = GPUIScene(clearColor: .clear)
        let textureID = value.registerImageRenderPass(
            filteredChild, size: Self.surface, input: .isolatedBackdrop, contentBlurRadius: 3)
        var output = image(textureID, body: Rect(x: 0, y: 0, width: 128, height: 128))
        apply(tinyCrop, to: &output)
        value.addImage(output)
        value.finish()
        let pixels = try assertReadback(value, using: renderer)
        for bitmap in [pixels.gpu, pixels.cpu] {
            // White -> .75 -> 1.0 before final premultiplication. Clipping a
            // source before filtering, or applying final AA twice, loses this.
            assertPixel(
                bitmap, x: 1, y: 1, red: tinyCropCoverage, green: tinyCropCoverage,
                blue: tinyCropCoverage, alpha: tinyCropCoverage)
            assertCoverage(bitmap, x: 2, y: 1, expected: 0, "Output crop stays hard after source blur")
        }
    }

    func testPathCacheDoesNotBakeOriginalAnchorOrCornerCoverage() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        var outside = tinyCrop
        outside.shape = Rect(x: 40, y: 40, width: 20, height: 20)
        var square = tinyCrop
        square.corners = [0, 0, 0, 0]
        for (index, clip) in [tinyCrop, outside, square, tinyCrop].enumerated() {
            let pixels = try assertReadback(scene(.path, clip: clip), using: renderer)
            let expected = index == 1 ? 0 : (index == 2 ? 1 : tinyCropCoverage)
            assertCoverage(pixels.gpu, x: 1, y: 1, expected: expected, "Clip remains a final draw parameter")
            XCTAssertEqual(renderer.pathCacheMisses, 1)
            XCTAssertEqual(renderer.pathCacheHits, UInt64(index))
            XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 1)
        }

        // A finite positive Double corner selects the explicit payload even
        // when its Float representation is zero. Mixed inactive inputs enter
        // through scene.addPath, which maps negative/nonfinite radii to zero.
        let underflowCorners: [[Double]] = [
            [1e-100, 0, 0, 0],
            [1e-100, -4, .nan, .infinity],
            [-.infinity, 1e-100, -4, .nan],
            [.nan, -4, 1e-100, -.infinity],
            [.infinity, .nan, -4, 1e-100],
        ]
        for (index, corners) in underflowCorners.enumerated() {
            let value = scene(
                .path, clip: Clip(rejection: Self.body, shape: Self.body, corners: corners, scalar: 20))
            XCTAssertEqual(value.layers[0].paths.count, 1, "Exercise the residual path-to-image route")
            XCTAssertTrue(value.layers[0].quads.isEmpty, "Do not substitute path promotion for this regression")
            let pixels = try assertReadback(value, using: renderer)
            for bitmap in [pixels.gpu, pixels.cpu] {
                let offset = Int(bitmap.bytesPerRow) + 4  // Pixel (1,1), center (1.5,1.5).
                XCTAssertEqual(
                    Array(bitmap.pixels[offset..<(offset + 4)]), [255, 255, 255, 255],
                    "The tiny explicit corner has a square limit; scalar 20 would reject this pixel")
            }
            XCTAssertEqual(renderer.pathCacheMisses, 1)
            XCTAssertEqual(renderer.pathCacheHits, UInt64(index + 4))
            XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 1)
        }

        let scalarOnly = scene(
            .path,
            clip: Clip(
                rejection: Self.body, shape: Self.body,
                corners: [-.infinity, -4, .nan, .infinity], scalar: 20))
        let scalarPixels = try assertReadback(scalarOnly, using: renderer)
        for bitmap in [scalarPixels.gpu, scalarPixels.cpu] {
            assertCoverage(bitmap, x: 1, y: 1, expected: 0, "Without a finite positive C, scalar 20 stays active")
        }
        XCTAssertEqual(renderer.pathCacheMisses, 1)
        XCTAssertEqual(renderer.pathCacheHits, UInt64(underflowCorners.count + 4))
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 1)

        // Exercise the explicit admission bypass too: +infinity must not
        // masquerade as a surviving Float corner beside an underflowed one.
        var rawPath = path(.white, body: Self.body)
        apply(
            Clip(
                rejection: Self.body, shape: Self.body,
                corners: [1e-100, .infinity, .nan, -4], scalar: 20), to: &rawPath)
        var rawScene = GPUIScene(clearColor: .clear)
        rawScene.installHandBuiltLayers([
            GPUILayer(paths: [rawPath], paintOperations: [GPUIPaintOperation(kind: .path, startIndex: 0)])
        ])
        rawScene.finish()
        let installedPath = try XCTUnwrap(rawScene.layers.first?.paths.first)
        XCTAssertEqual(installedPath.clipCornerRadiusTopLeft, 1e-100)
        XCTAssertEqual(installedPath.clipCornerRadiusTopRight, Double.infinity)
        XCTAssertTrue(installedPath.clipCornerRadiusBottomRight.isNaN)
        XCTAssertEqual(installedPath.clipCornerRadiusBottomLeft, -4)
        XCTAssertEqual(installedPath.clipCornerRadius, 20)
        XCTAssertTrue(rawScene.validate().isEmpty)
        // Deliberately avoid raw-scene CPU parity: this pins the synthetic
        // image's local normalization without broadening CPU hand-built policy.
        renderer.bindResources(for: rawScene)
        try renderer.render(scene: rawScene)
        let rawPixels = try renderer.readOffscreenPixels()
        let rawOffset = Int(rawPixels.bytesPerRow) + 4  // Pixel (1,1).
        XCTAssertEqual(
            Array(rawPixels.pixels[rawOffset..<(rawOffset + 4)]), [255, 255, 255, 255],
            "Raw inactive corners must not restore scalar 20 after the selected tiny corner underflows")
        XCTAssertEqual(renderer.pathCacheMisses, 1)
        XCTAssertEqual(renderer.pathCacheHits, UInt64(underflowCorners.count + 5))
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 1)
    }

    func testWindowedTranslatedPathCacheKeepsOriginalAnchorWithoutLargerBudgets() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        var source = path(.white, body: Rect(x: 0, y: 0, width: 400, height: 20_000))
        apply(
            Clip(
                rejection: Rect(x: 0, y: 0, width: 100, height: 4), shape: Self.body,
                corners: [40, 0, 0, 0]), to: &source)
        for offset in [Point.zero, Point(x: 16, y: 8)] {
            var value = GPUIScene(clearColor: .clear)
            value.addPath(source.translated(by: offset), toLayer: 0)
            value.finish()
            let pixels = try assertReadback(value, using: renderer)
            assertCoverage(
                pixels.gpu, x: Int(offset.x) + 2, y: Int(offset.y) + 1, expected: 0,
                "Windowing must not replace the original shape anchor")
            assertCoverage(
                pixels.gpu, x: Int(offset.x) + 60, y: Int(offset.y) + 1, expected: 1,
                "Translated straight-edge control")
        }
        XCTAssertEqual(renderer.pathCacheMisses, 1)
        XCTAssertEqual(renderer.pathCacheHits, 1)
        let tile = Int(D3D11BatchRenderer.pathRasterWindowTile)
        let bound = (Int(Self.surface.width) + 2 * tile) * (Int(Self.surface.height) + 2 * tile)
        XCTAssertGreaterThan(renderer.largestPathRasterPixelsForTesting, 0)
        XCTAssertLessThanOrEqual(renderer.largestPathRasterPixelsForTesting, bound)
    }

    private func makeRenderer() throws -> D3D11BatchRenderer {
        // Only unavailable devices may skip. Shader/setup/readback errors
        // after this existing device probe propagate as test failures.
        let probe = try makeWARPDevice()
        probe.release()
        let renderer = D3D11BatchRenderer()
        var attached = false
        defer { if !attached { renderer.detach() } }
        try renderer.attachOffscreen(size: Self.surface, driver: .warpFirst)
        XCTAssertEqual(renderer.backendDiagnostics?.adapterIsSoftware, true)
        attached = true
        return renderer
    }

    private func assertReadback(
        _ value: GPUIScene, using renderer: D3D11BatchRenderer,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> (gpu: BitmapSurface, cpu: BitmapSurface) {
        XCTAssertTrue(value.validate().isEmpty, file: file, line: line)
        renderer.bindResources(for: value)
        try renderer.render(scene: value)
        let gpu = try renderer.readOffscreenPixels()
        let cpu = GPUIRawSceneRasterizer.rasterize(value, size: Self.surface).premultipliedAlpha()
        let report = comparePixels(gpu, cpu, tolerance: 4)
        XCTAssertGreaterThanOrEqual(
            report.matchRatio, 0.995,
            "CPU/WARP mismatch: max delta \(report.maxChannelDelta), first \(String(describing: report.firstFailure))",
            file: file, line: line)
        return (gpu, cpu)
    }

    private func assertCoverage(
        _ bitmap: BitmapSurface, x: Int, y: Int, expected: Double, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4 + 3
        XCTAssertEqual(
            Double(bitmap.pixels[offset]) / 255, expected, accuracy: 2.0 / 255, message, file: file, line: line)
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, red: Double, green: Double, blue: Double, alpha: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(bitmap.format.alphaMode, .premultiplied, file: file, line: line)
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        for (channel, expected) in [blue, green, red, alpha].enumerated() {
            XCTAssertEqual(
                Double(bitmap.pixels[offset + channel]) / 255, expected, accuracy: 3.0 / 255,
                "Pixel (\(x),\(y)) channel \(channel)", file: file, line: line)
        }
    }

    private func scene(
        _ family: Family, clip: Clip, body: Rect = Rect(x: 0, y: 0, width: 100, height: 100), scale: Double = 1
    ) -> GPUIScene {
        var value = GPUIScene(clearColor: .clear)
        append(family, clip: clip, body: body, scale: scale, into: &value)
        value.finish()
        return value
    }

    private func append(
        _ family: Family, clip: Clip, body: Rect = Rect(x: 0, y: 0, width: 100, height: 100),
        scale: Double = 1, color: Color = .white, into value: inout GPUIScene
    ) {
        let pixelBody = body.scaled(by: scale)
        let pixelClip = clip.scaled(by: scale)
        switch family {
        case .quad:
            var primitive = quad(color, body: pixelBody)
            apply(pixelClip, to: &primitive)
            value.addQuad(primitive)
        case .glyph, .pixelGlyph:
            var primitive = GlyphPrimitive(
                screenX: Float(pixelBody.minX), screenY: Float(pixelBody.minY),
                screenW: Float(pixelBody.size.width), screenH: Float(pixelBody.size.height),
                atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                colorR: color.red, colorG: color.green, colorB: color.blue, colorA: color.alpha)
            apply(pixelClip, to: &primitive)
            let atlas = GlyphAtlasSnapshot(
                width: 1, height: 1, pixels: Data([255, 255, 255, 255]),
                contentVersion: RenderContentVersion.next(), update: .full)
            if family == .glyph {
                value.glyphAtlas = atlas
                value.addGlyph(primitive)
            } else {
                value.pixelGlyphAtlas = atlas
                value.addPixelGlyph(primitive)
            }
        case .image:
            let bitmap = BitmapSurface(
                width: 1, height: 1, bytesPerRow: 4,
                pixels: Data([
                    UInt8((color.blue * 255).rounded()), UInt8((color.green * 255).rounded()),
                    UInt8((color.red * 255).rounded()), 255,
                ]))
            let textureID = value.registerImageResource(bitmap)
            var primitive = image(textureID, body: pixelBody, opacity: color.alpha)
            apply(pixelClip, to: &primitive)
            value.addImage(primitive)
        case .shadow:
            var primitive = ShadowPrimitive(
                x: Float(pixelBody.minX), y: Float(pixelBody.minY),
                width: Float(pixelBody.size.width), height: Float(pixelBody.size.height),
                colorR: color.red, colorG: color.green, colorB: color.blue, colorA: color.alpha, blurRadius: 0)
            apply(pixelClip, to: &primitive)
            value.addShadow(primitive)
        case .path:
            var primitive = path(color, body: body)
            apply(clip, to: &primitive)
            value.addPath(primitive.scaled(by: scale), toLayer: 0)
        }
    }

    private enum CompositeRoute: CaseIterable {
        case material, currentTargetImage, isolatedMaterial, isolatedImage, nestedIsolatedImage

        var imageOpacity: Double {
            switch self {
            case .material, .isolatedMaterial: return 1
            case .currentTargetImage, .isolatedImage, .nestedIsolatedImage: return 0.5
            }
        }
    }

    private func compositeScene(_ route: CompositeRoute, clip: Clip) -> GPUIScene {
        let body = Rect(x: 0, y: 0, width: 128, height: 128)
        var material = quad(Color(red: 0, green: 0, blue: 1, alpha: 0.4), body: body)
        material.blurRadius = 2
        var value = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 0.5))
        if route == .material || route == .isolatedMaterial { apply(clip, to: &material) }
        if route == .material {
            value.addQuad(material)
        } else {
            var child = GPUIScene(clearColor: .clear)
            child.addQuad(material)
            child.finish()
            if route == .nestedIsolatedImage {
                var middle = GPUIScene(clearColor: .clear)
                let leafID = middle.registerImageRenderPass(child, size: Self.surface, input: .isolatedBackdrop)
                var output = image(leafID, body: body, opacity: 0.5)
                apply(clip, to: &output)
                middle.addImage(output)
                middle.finish()
                let outerID = value.registerImageRenderPass(middle, size: Self.surface, input: .isolatedBackdrop)
                value.addImage(image(outerID, body: body))
            } else {
                let sourceID = value.registerImageRenderPass(
                    child, size: Self.surface,
                    input: route == .currentTargetImage ? .currentTarget : .isolatedBackdrop)
                var output = image(sourceID, body: body, opacity: Float(route.imageOpacity))
                if route != .isolatedMaterial { apply(clip, to: &output) }
                value.addImage(output)
            }
        }
        value.finish()
        return value
    }

    private func quad(_ color: Color, body: Rect) -> QuadPrimitive {
        QuadPrimitive(
            x: Float(body.minX), y: Float(body.minY), width: Float(body.size.width), height: Float(body.size.height),
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha)
    }

    private func image(_ textureID: Int32, body: Rect, opacity: Float = 1) -> ImagePrimitive {
        ImagePrimitive(
            screenX: Float(body.minX), screenY: Float(body.minY),
            screenW: Float(body.size.width), screenH: Float(body.size.height), opacity: opacity, textureID: textureID)
    }

    private func path(_ color: Color, body: Rect) -> PathPrimitive {
        PathPrimitive(
            elements: [
                .moveTo(Point(x: body.minX, y: body.minY)), .lineTo(Point(x: body.maxX, y: body.minY)),
                .lineTo(Point(x: body.maxX, y: body.maxY)), .lineTo(Point(x: body.minX, y: body.maxY)), .close,
            ], bounds: body, fillColor: color)
    }

    private func apply(_ clip: Clip, to value: inout QuadPrimitive) {
        value.clipShapeBounds = clip.shape
        value.clipCornerRadiusTopLeft = Float(clip.corners[0])
        value.clipCornerRadiusTopRight = Float(clip.corners[1])
        value.clipCornerRadiusBottomRight = Float(clip.corners[2])
        value.clipCornerRadiusBottomLeft = Float(clip.corners[3])
        value.clipCornerRadius = Float(clip.scalar)
        GPUIClipEncoding.encode(
            clip.rejection, into: &value.clipX, &value.clipY, &value.clipWidth, &value.clipHeight)
    }

    private func apply(_ clip: Clip, to value: inout GlyphPrimitive) {
        value.clipShapeBounds = clip.shape
        value.clipCornerRadiusTopLeft = Float(clip.corners[0])
        value.clipCornerRadiusTopRight = Float(clip.corners[1])
        value.clipCornerRadiusBottomRight = Float(clip.corners[2])
        value.clipCornerRadiusBottomLeft = Float(clip.corners[3])
        value.clipCornerRadius = Float(clip.scalar)
        GPUIClipEncoding.encode(
            clip.rejection, into: &value.clipX, &value.clipY, &value.clipWidth, &value.clipHeight)
    }

    private func apply(_ clip: Clip, to value: inout ImagePrimitive) {
        value.clipShapeBounds = clip.shape
        value.clipCornerRadiusTopLeft = Float(clip.corners[0])
        value.clipCornerRadiusTopRight = Float(clip.corners[1])
        value.clipCornerRadiusBottomRight = Float(clip.corners[2])
        value.clipCornerRadiusBottomLeft = Float(clip.corners[3])
        value.clipCornerRadius = Float(clip.scalar)
        GPUIClipEncoding.encode(
            clip.rejection, into: &value.clipX, &value.clipY, &value.clipWidth, &value.clipHeight)
    }

    private func apply(_ clip: Clip, to value: inout ShadowPrimitive) {
        value.clipShapeBounds = clip.shape
        value.clipCornerRadiusTopLeft = Float(clip.corners[0])
        value.clipCornerRadiusTopRight = Float(clip.corners[1])
        value.clipCornerRadiusBottomRight = Float(clip.corners[2])
        value.clipCornerRadiusBottomLeft = Float(clip.corners[3])
        value.clipCornerRadius = Float(clip.scalar)
        GPUIClipEncoding.encode(
            clip.rejection, into: &value.clipX, &value.clipY, &value.clipWidth, &value.clipHeight)
    }

    private func apply(_ clip: Clip, to value: inout PathPrimitive) {
        value.clipShapeBounds = clip.shape
        value.clipCornerRadiusTopLeft = clip.corners[0]
        value.clipCornerRadiusTopRight = clip.corners[1]
        value.clipCornerRadiusBottomRight = clip.corners[2]
        value.clipCornerRadiusBottomLeft = clip.corners[3]
        value.clipCornerRadius = clip.scalar
        value.clipBounds = clip.rejection
    }
}
