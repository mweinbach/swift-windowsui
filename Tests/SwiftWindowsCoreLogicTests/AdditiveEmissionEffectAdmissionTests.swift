import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Post-filter chains have straight-color semantics. Escaped additive emission
/// must be refused explicitly until those chains can carry RGB above alpha.
@MainActor
final class AdditiveEmissionEffectAdmissionTests: XCTestCase {
    private let size = IntSize(width: 32, height: 32)

    func testEscapedEmissionWithIdentityEffectHasAnExplicitDiagnosticAndCPUTile() async throws {
        let scene = filtered(escapedScene())
        let pass = try XCTUnwrap(scene.imageRenderPasses.first)
        XCTAssertTrue(try XCTUnwrap(pass.additiveEmissionColorEffectDefect).contains("escaped additive emission"))
        XCTAssertTrue(
            scene.validate().contains { defect in
                if case .invalidImageRenderPass(let id, let reason) = defect.kind {
                    return id == pass.textureID && reason.contains("escaped additive emission")
                }
                return false
            })
        assertUnsupportedTile(scene)
    }

    func testWARPRejectsEscapedEmissionEffectsBeforeDrawingAndRecovers() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        var good = GPUIScene(clearColor: Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        good.finish()
        let baseline = try render(good, using: renderer)
        let warmCount = renderer.liveCOMObjectCountForTesting
        var rejected = filtered(escapedScene())
        rejected.finish()
        renderer.bindResources(for: rejected)
        XCTAssertThrowsError(try renderer.render(scene: rejected)) { error in
            XCTAssertEqual((error as? BatchRendererError)?.presentationFailureKind, .sceneContent)
            XCTAssertTrue(String(describing: error).contains("escaped additive emission"))
        }
        XCTAssertEqual(renderer.lastFrameSubmission?.outcome, .aborted)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmCount)
        XCTAssertEqual(try render(good, using: renderer).pixels, baseline.pixels)
    }

    func testRepresentableAdditiveWithEffectsRemainsAdmittedOnCPUAndWARP() async throws {
        var child = GPUIScene(clearColor: Color(red: 0, green: 0.4, blue: 0.8, alpha: 0.5))
        child.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5)))
        let scene = filtered(child)
        XCTAssertNil(scene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(scene.validate().isEmpty)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        assertPixel(cpu, x: 16, y: 16, rgba: [0.5, 0.2, 0.4, 1], tolerance: 3)
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let gpu = try render(scene, using: renderer)
        assertPixel(gpu, x: 16, y: 16, rgba: [0.5, 0.2, 0.4, 1], tolerance: 3)
        XCTAssertEqual(comparePixels(gpu, cpu, tolerance: 4).matchRatio, 1)
    }

    func testNoEffectsAndUnblurredAdditiveIsolationRemainAdmitted() async throws {
        let noEffects = wrapped(escapedScene(), input: .independent)
        XCTAssertNil(noEffects.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(noEffects.validate().isEmpty)
        let noBlur = filtered(escapedScene(radius: 0))
        XCTAssertNil(noBlur.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(noBlur.validate().isEmpty)
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let emitted = try render(noEffects, using: renderer)
        assertPixel(emitted, x: 15, y: 16, rgba: [0.05325349, 0, 0, 0], tolerance: 2)
        let ordinary = try render(noBlur, using: renderer)
        assertPixel(ordinary, x: 16, y: 16, rgba: [0.5, 1, 0, 1], tolerance: 3)
    }

    func testUnusedPassAndExplicitBitmapOverrideDoNotCauseFalseRefusal() async throws {
        var unused = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
        _ = unused.registerImageRenderPass(escapedScene(), size: size)
        let unusedScene = filtered(unused)
        XCTAssertNil(unusedScene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(unusedScene.validate().isEmpty)
        assertPixel(
            GPUIRawSceneRasterizer.rasterize(unusedScene, size: size).premultipliedAlpha(), x: 16, y: 16,
            rgba: [0, 0, 1, 1], tolerance: 0)

        var replaced = wrapped(escapedScene(), input: .independent)
        let id = try XCTUnwrap(replaced.imageRenderPasses.first?.textureID)
        let blue = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([255, 0, 0, 255]), format: .bgra8Straight)
        replaced.bindImageResource(blue, for: id)
        XCTAssertTrue(replaced.imageRenderPasses.isEmpty)
        let replacedScene = filtered(replaced)
        XCTAssertNil(replacedScene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(replacedScene.validate().isEmpty)
        assertPixel(
            GPUIRawSceneRasterizer.rasterize(replacedScene, size: size).premultipliedAlpha(), x: 16, y: 16,
            rgba: [0, 0, 1, 1], tolerance: 0)
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        assertPixel(try render(unusedScene, using: renderer), x: 16, y: 16, rgba: [0, 0, 1, 1], tolerance: 0)
        assertPixel(try render(replacedScene, using: renderer), x: 16, y: 16, rgba: [0, 0, 1, 1], tolerance: 0)
    }

    func testIndependentBoundaryStopsSharedDeltaButCarriesAlreadyEscapedEmission() async throws {
        var direct = GPUIScene(clearColor: .clear)
        direct.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5)))
        let independent = wrapped(direct, input: .independent)
        let safe = filtered(wrapped(independent, input: .isolatedBackdrop, radius: 1))
        XCTAssertNil(safe.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(safe.validate().isEmpty)
        let escaped = filtered(wrapped(escapedScene(), input: .independent))
        XCTAssertNotNil(escaped.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        assertUnsupportedTile(escaped)
    }

    func testNestedDependentDeltaInsideOuterBlurIsRejected() async throws {
        var direct = GPUIScene(clearColor: .clear)
        direct.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5)))
        for input in [GPUISceneImageRenderPassInput.currentTarget, .isolatedBackdrop] {
            let nested = wrapped(direct, input: input)
            let scene = filtered(wrapped(nested, input: .isolatedBackdrop, radius: 1))
            XCTAssertNotNil(scene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
            assertUnsupportedTile(scene)
        }
    }

    func testMaterialAndFractionalSelectorsDoNotCountAsOrdinaryAdditive() async throws {
        for material in [false, true] {
            var child = GPUIScene(clearColor: .clear)
            var value = quad(Color(red: 0.5, green: 0.2, blue: 0.4, alpha: 0.5))
            if material { value.blurRadius = 2 } else { value.blendMode = 3.999 }
            child.addQuad(value)
            let scene = filtered(wrapped(child, input: .isolatedBackdrop, radius: 1))
            XCTAssertNil(scene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
            XCTAssertTrue(scene.validate().isEmpty)
        }
    }

    func testNamespaceLocalIDsAndRepeatedConsumersHaveIndependentBoundedAnalysis() async throws {
        var safeLeaf = GPUIScene(clearColor: .clear)
        safeLeaf.addQuad(quad(Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)))
        let safeBranch = wrapped(safeLeaf, input: .independent)
        let hazardBranch = wrapped(escapedScene(), input: .independent)
        XCTAssertEqual(safeBranch.imageRenderPasses.first?.textureID, hazardBranch.imageRenderPasses.first?.textureID)
        var combined = GPUIScene(clearColor: .clear)
        let safeID = combined.registerImageRenderPass(safeBranch, size: size)
        combined.addImage(image(safeID))
        let hazardID = combined.registerImageRenderPass(hazardBranch, size: size)
        combined.addImage(image(hazardID))
        XCTAssertNotNil(filtered(combined).imageRenderPasses.first?.additiveEmissionColorEffectDefect)

        var repeated = GPUIScene(clearColor: .clear)
        let repeatedID = repeated.registerImageRenderPass(safeLeaf, size: size)
        for _ in 0...GPUISceneLimits.maxImageRenderPassCount { repeated.addImage(image(repeatedID)) }
        let repeatedScene = filtered(repeated)
        // This is structural analysis, not permission to exceed the separate
        // execution budget by rendering the repeated occurrences.
        XCTAssertNil(repeatedScene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(repeatedScene.validate().isEmpty)
    }

    func testAnalysisDepthAndDeclaredSourceCountHaveExplicitLimits() async throws {
        var deep = GPUIScene(clearColor: .clear)
        for _ in 0..<GPUISceneLimits.maxImageRenderPassDepth { deep = wrapped(deep, input: .independent) }
        let deepScene = filtered(deep)
        let deepReason = try XCTUnwrap(deepScene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(deepReason.contains("dependency analysis limit"))
        assertUnsupportedTile(deepScene)

        var wide = GPUIScene(clearColor: .clear)
        for _ in 0...GPUISceneLimits.maxImageRenderPassCount {
            _ = wide.registerImageRenderPass(GPUIScene(clearColor: .clear), size: IntSize(width: 1, height: 1))
        }
        let wideScene = filtered(wide)
        let wideReason = try XCTUnwrap(wideScene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(wideReason.contains("dependency analysis limit"))
        assertUnsupportedTile(wideScene)
    }

    func testUsedPremultipliedEmissionIsRejectedButNoEffectTransportIsPreserved() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let pixels: [[UInt8]] = [[0, 0, 96, 0], [65, 0, 0, 64], [0, 65, 0, 64], [0, 0, 65, 64]]
        for pixel in pixels {
            let bitmap = BitmapSurface(
                width: 1, height: 1, bytesPerRow: 4, pixels: Data(pixel), format: .bgra8Premultiplied)
            let source = bitmapScene(bitmap)
            let scene = filtered(source)
            XCTAssertNotNil(scene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
            XCTAssertTrue(
                scene.validate().contains { defect in
                    if case .invalidImageRenderPass(_, let reason) = defect.kind {
                        return reason.contains("premultiplied bitmap")
                    }
                    return false
                })
            assertUnsupportedTile(scene)
            renderer.bindResources(for: scene)
            XCTAssertThrowsError(try renderer.render(scene: scene)) { error in
                XCTAssertEqual((error as? BatchRendererError)?.presentationFailureKind, .sceneContent)
                XCTAssertTrue(String(describing: error).contains("premultiplied bitmap"))
            }
            let transported = try render(source, using: renderer)
            let expected = [pixel[2], pixel[1], pixel[0], pixel[3]].map { Double($0) / 255 }
            assertPixel(transported, x: 16, y: 16, rgba: expected, tolerance: 0)
            assertPixel(
                GPUIRawSceneRasterizer.rasterize(source, size: size).premultipliedAlpha(), x: 16, y: 16, rgba: expected,
                tolerance: 0)
        }
    }

    func testRasterizedEscapedEmissionRemainsRejectedAfterBitmapCaching() async throws {
        let cached = GPUIRawSceneRasterizer.rasterize(escapedScene(), size: size)
        XCTAssertEqual(cached.format.alphaMode, .premultiplied)
        let side = 16 * Int(cached.bytesPerRow) + 15 * 4
        XCTAssertGreaterThan(cached.pixels[side + 2], cached.pixels[side + 3])
        let source = bitmapScene(cached)
        XCTAssertTrue(source.imageRenderPasses.isEmpty)
        let scene = filtered(source)
        XCTAssertNotNil(scene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        assertUnsupportedTile(scene)
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        renderer.bindResources(for: scene)
        XCTAssertThrowsError(try renderer.render(scene: scene)) { error in
            XCTAssertEqual((error as? BatchRendererError)?.presentationFailureKind, .sceneContent)
        }
    }

    func testSafePremultipliedOverridesPaddingStraightAndUnusedEmissionStayAdmitted() async throws {
        let emitted = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 96, 0]), format: .bgra8Premultiplied)
        // Padding and trailing storage are not texels. Both deliberately carry RGB > A.
        let safe = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 8, pixels: Data([0, 64, 128, 128, 255, 255, 255, 0, 255, 255, 255, 0]),
            format: .bgra8Premultiplied)
        var replaced = wrapped(escapedScene(), input: .independent)
        let id = try XCTUnwrap(replaced.imageRenderPasses.first?.textureID)
        replaced.bindImageResource(safe, for: id)
        _ = replaced.registerImageResource(emitted)
        XCTAssertTrue(replaced.imageRenderPasses.isEmpty)
        let safeScene = filtered(replaced)
        XCTAssertNil(safeScene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(safeScene.validate().isEmpty)
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let expected = [128.0 / 255, 64.0 / 255, 0, 128.0 / 255]
        assertPixel(try render(safeScene, using: renderer), x: 16, y: 16, rgba: expected, tolerance: 1)
        assertPixel(
            GPUIRawSceneRasterizer.rasterize(safeScene, size: size).premultipliedAlpha(), x: 16, y: 16, rgba: expected,
            tolerance: 1)

        let straight = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([255, 255, 255, 0]), format: .bgra8Straight)
        let straightScene = filtered(bitmapScene(straight))
        XCTAssertNil(straightScene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(straightScene.validate().isEmpty)
        assertPixel(try render(straightScene, using: renderer), x: 16, y: 16, rgba: [0, 0, 0, 0], tolerance: 0)
        assertPixel(
            GPUIRawSceneRasterizer.rasterize(straightScene, size: size).premultipliedAlpha(), x: 16, y: 16,
            rgba: [0, 0, 0, 0], tolerance: 0)
    }

    func testBitmapPayloadAnalysisUsesLastBindingNamespaceAndContentVersion() async throws {
        let safe = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 64, 64]), format: .bgra8Premultiplied)
        var emitted = safe
        emitted.pixels[2] = 65
        XCTAssertNotEqual(safe.contentKey, emitted.contentKey)
        var duplicate = bitmapScene(safe)
        let id = try XCTUnwrap(duplicate.imageResources.first?.textureID)
        duplicate.imageResources.insert(ImageResourceBinding(textureID: id, bitmap: emitted), at: 0)
        // Hand-built duplicate bitmap records follow the renderer's last
        // binding; they do not make the earlier payload reachable.
        XCTAssertNil(filtered(duplicate).imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        duplicate.imageResources.reverse()
        XCTAssertNotNil(filtered(duplicate).imageRenderPasses.first?.additiveEmissionColorEffectDefect)

        var parent = GPUIScene(clearColor: .clear)
        for bitmap in [safe, emitted] {
            let child = bitmapScene(bitmap)
            XCTAssertEqual(child.imageResources.first?.textureID, id)
            let passID = parent.registerImageRenderPass(child, size: size)
            parent.addImage(image(passID))
        }
        let scene = filtered(parent)
        XCTAssertNotNil(scene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        assertUnsupportedTile(scene)
    }

    func testBitmapPayloadScanBudgetCountsContentOnceAndRefusesExhaustion() async throws {
        // Admission-only test: at most 64 MiB of actual texel bytes
        // are scanned per query, without allocating a GPU texture this large.
        let dimension: Int32 = 4096
        XCTAssertEqual(Int(dimension) * Int(dimension), GPUISceneLimits.maxImageRenderPassTotalPixels)
        let bytes = Int(dimension) * Int(dimension) * 4
        let bitmap = BitmapSurface(
            width: dimension, height: dimension, bytesPerRow: dimension * 4, pixels: Data(repeating: 0, count: bytes),
            format: .bgra8Premultiplied)
        var source = bitmapScene(bitmap)
        let nested = source.registerImageRenderPass(bitmapScene(bitmap), size: size)
        source.addImage(image(nested))
        XCTAssertNil(filtered(source).imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        let extra = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 0, 0]), format: .bgra8Premultiplied)
        let extraID = source.registerImageResource(extra)
        source.addImage(image(extraID))
        let reason = try XCTUnwrap(filtered(source).imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(reason.contains("dependency analysis limit"))
    }

    func testUnusedFilteredDeclarationsAncestorsAndUnpaintedImagesStayAdmitted() async throws {
        let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
        var direct = GPUIScene(clearColor: blue)
        _ = direct.registerImageRenderPass(escapedScene(), size: size, colorEffects: [.brightness(0)])
        var ancestor = GPUIScene(clearColor: blue)
        _ = ancestor.registerImageRenderPass(filtered(escapedScene()), size: size)
        var unpainted = GPUIScene(clearColor: blue)
        let id = unpainted.registerImageRenderPass(escapedScene(), size: size, colorEffects: [.brightness(0)])
        unpainted.addImage(image(id))
        // The family array is storage; only the explicit paint order draws it.
        unpainted.installHandBuiltLayers([GPUILayer(images: [image(id)], paintOperations: [])])
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        for scene in [direct, ancestor, unpainted] {
            XCTAssertTrue(scene.validate().isEmpty)
            assertPixel(
                GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha(), x: 16, y: 16,
                rgba: [0, 0, 1, 1], tolerance: 0)
            assertPixel(try render(scene, using: renderer), x: 16, y: 16, rgba: [0, 0, 1, 1], tolerance: 0)
        }
    }

    func testUnusedEmissionContextStillValidatesOrdinaryDeclarationStructure() async throws {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
        var child = GPUIScene(clearColor: .clear)
        _ = child.registerImageRenderPass(
            escapedScene(), size: IntSize(width: 0, height: 1), colorEffects: [.brightness(0)])
        _ = scene.registerImageRenderPass(child, size: size)
        XCTAssertTrue(
            scene.validate().contains { defect in
                if case .invalidImageRenderPass(_, let reason) = defect.kind {
                    return reason.contains("extent exceeds")
                }
                return false
            })
        XCTAssertFalse(
            scene.validate().contains { defect in
                if case .invalidImageRenderPass(_, let reason) = defect.kind {
                    return reason.contains("escaped additive emission")
                }
                return false
            })
    }

    func testUsedMalformedPremultipliedEffectSourceHasExplicitDiagnosticAndCPUTile() async throws {
        // The valid first texel emits at alpha zero, but the second texel is
        // absent. A CPU prefix read must not let the effect silently erase it.
        let malformed = BitmapSurface(
            width: 2, height: 1, bytesPerRow: 8, pixels: Data([0, 0, 96, 0]), format: .bgra8Premultiplied)
        let source = bitmapScene(malformed)
        let scene = filtered(source)
        let reason = try XCTUnwrap(scene.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        XCTAssertTrue(reason.contains("invalid premultiplied bitmap"))
        XCTAssertFalse(reason.contains("analysis limit"))
        XCTAssertTrue(
            scene.validate().contains { defect in
                if case .invalidImageRenderPass(_, let reason) = defect.kind {
                    return reason.contains("invalid premultiplied bitmap")
                }
                return false
            })
        assertUnsupportedTile(scene)
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        renderer.bindResources(for: scene)
        XCTAssertThrowsError(try renderer.render(scene: scene)) { error in
            XCTAssertEqual((error as? BatchRendererError)?.presentationFailureKind, .sceneContent)
            XCTAssertTrue(String(describing: error).contains("invalid premultiplied bitmap"))
        }
        XCTAssertEqual(renderer.lastFrameSubmission?.outcome, .aborted)

        let noEffect = wrapped(source, input: .independent)
        XCTAssertNil(noEffect.imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        var unused = GPUIScene(clearColor: .clear)
        _ = unused.registerImageResource(malformed)
        XCTAssertNil(filtered(unused).imageRenderPasses.first?.additiveEmissionColorEffectDefect)
        var straight = malformed
        straight.format = .bgra8Straight
        XCTAssertNil(filtered(bitmapScene(straight)).imageRenderPasses.first?.additiveEmissionColorEffectDefect)
    }

    private func bitmapScene(_ bitmap: BitmapSurface) -> GPUIScene {
        var scene = GPUIScene(clearColor: .clear)
        let id = scene.registerImageResource(bitmap)
        scene.addImage(image(id))
        return scene
    }

    private func escapedScene(radius: Int32 = 1) -> GPUIScene {
        var parent = GPUIScene(clearColor: .clear)
        parent.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 1), mode: .normal, x: 16, width: 1))
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5), x: 16, width: 1))
        let id = parent.registerImageRenderPass(child, size: size, input: .isolatedBackdrop, contentBlurRadius: radius)
        parent.addImage(image(id))
        return parent
    }

    private func filtered(_ child: GPUIScene) -> GPUIScene {
        var parent = GPUIScene(clearColor: .clear)
        let id = parent.registerImageRenderPass(child, size: size, colorEffects: [.brightness(0)])
        parent.addImage(image(id))
        return parent
    }

    private func wrapped(_ child: GPUIScene, input: GPUISceneImageRenderPassInput, radius: Int32 = 0) -> GPUIScene {
        var parent = GPUIScene(clearColor: .clear)
        let id = parent.registerImageRenderPass(child, size: size, input: input, contentBlurRadius: radius)
        parent.addImage(image(id))
        return parent
    }

    private func quad(_ color: Color, mode: BlendMode = .additive, x: Float = 0, width: Float = 32) -> QuadPrimitive {
        QuadPrimitive(
            x: x, y: 0, width: width, height: 32, startR: color.red, startG: color.green, startB: color.blue,
            startA: color.alpha, endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha,
            blendMode: Float(mode.rawValue))
    }

    private func image(_ id: Int32) -> ImagePrimitive {
        ImagePrimitive(screenX: 0, screenY: 0, screenW: 32, screenH: 32, textureID: id)
    }

    private func assertUnsupportedTile(_ scene: GPUIScene, file: StaticString = #filePath, line: UInt = #line) {
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        let offset = 8 * Int(bitmap.bytesPerRow) + 8 * 4
        XCTAssertGreaterThan(bitmap.pixels[offset], 0, file: file, line: line)
        XCTAssertEqual(bitmap.pixels[offset], bitmap.pixels[offset + 2], file: file, line: line)
        XCTAssertEqual(bitmap.pixels[offset + 1], 0, file: file, line: line)
        XCTAssertEqual(bitmap.pixels[offset + 3], 255, file: file, line: line)
    }

    private func makeRenderer() throws -> D3D11BatchKernel {
        let renderer = D3D11BatchKernel()
        do { try renderer.attachOffscreenWARPForTesting(size: size) } catch {
            renderer.detach()
            throw error
        }
        guard renderer.backendDiagnostics?.adapterIsSoftware == true else {
            renderer.detach()
            throw BatchRendererError(
                operation: "Validate effect-admission WARP device", hresult: HRESULT(bitPattern: 0x8000_4005))
        }
        return renderer
    }

    private func render(_ scene: GPUIScene, using renderer: D3D11BatchKernel) throws -> BitmapSurface {
        var finished = scene
        finished.finish()
        renderer.bindResources(for: finished)
        try renderer.render(scene: finished)
        XCTAssertEqual(renderer.lastFrameSubmission?.outcome, .offscreen)
        return try renderer.readOffscreenPixels()
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, rgba: [Double], tolerance: Double, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        for (channel, component) in [2, 1, 0, 3].enumerated() {
            XCTAssertEqual(
                Double(bitmap.pixels[offset + component]), (rgba[channel] * 255).rounded(), accuracy: tolerance,
                file: file, line: line)
        }
    }
}
