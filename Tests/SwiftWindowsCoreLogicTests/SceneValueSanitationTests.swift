import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Non-finite and absurd-magnitude values reaching the scene contract.
///
/// `Int(_: Float)` is a Swift *trap* on NaN and ±infinity, and those
/// conversions sit on the hottest paths in both backends — the blur
/// splitter runs one per quad per frame before any culling. A trap is
/// the one failure class the host's documented fallback policy cannot
/// degrade: the process dies instead of downgrading to the frame
/// renderer. Every value below is reachable from ordinary app code
/// (`.blur(radius: a / b)` with `b == 0`, a frame that collapses to NaN
/// during layout, an animation interpolating through infinity).
///
/// The contract is: no trap, no hang, and a degenerate-but-sane result.
final class SceneValueSanitationTests: XCTestCase {

    // MARK: - Saturating conversions

    func testSaturatingIntConversionsDoNotTrap() {
        XCTAssertEqual(GPUISceneValue.int(Float.nan), 0)
        XCTAssertEqual(GPUISceneValue.int(Double.nan), 0)
        XCTAssertEqual(GPUISceneValue.int(Float.infinity), GPUISceneValue.intBound)
        XCTAssertEqual(GPUISceneValue.int(-Float.infinity), -GPUISceneValue.intBound)
        XCTAssertEqual(GPUISceneValue.int(Float(1e30)), GPUISceneValue.intBound)
        XCTAssertEqual(GPUISceneValue.int(Double(-1e300)), -GPUISceneValue.intBound)
        // Finite in-range values still truncate exactly as `Int(_:)` did.
        XCTAssertEqual(GPUISceneValue.int(Float(7.9)), 7)
        XCTAssertEqual(GPUISceneValue.int(Double(-7.9)), -7)
    }

    func testClampingPreservesWellFormedValuesExactly() {
        XCTAssertEqual(GPUISceneValue.clamped(Float(0.25), to: 1_000), 0.25)
        XCTAssertEqual(GPUISceneValue.clamped(Float(-0.25), to: 1_000), -0.25)
        XCTAssertEqual(GPUISceneValue.clamped(Float(-0.0), to: 1_000).sign, .minus)
        XCTAssertEqual(GPUISceneValue.clamped(Float.nan, to: 1_000), 0)
        XCTAssertEqual(GPUISceneValue.clamped(Float.infinity, lower: 0, upper: 4), 4)
        XCTAssertEqual(GPUISceneValue.clamped(-Float.infinity, lower: 0, upper: 4), 0)
    }

    // MARK: - Quad sanitation at the add* boundary

    func testNonFiniteBlurRadiusIsClampedAtTheSceneBoundary() {
        for radius in [Float.nan, .infinity, -.infinity, 1e30, -1] {
            var scene = GPUIScene()
            scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: radius))
            XCTAssertEqual(scene.layers[0].quads.count, 1, "radius \(radius) should not reject the quad")
            let stored = scene.layers[0].quads[0].blurRadius
            XCTAssertTrue(stored.isFinite, "radius \(radius) survived as \(stored)")
            XCTAssertGreaterThanOrEqual(stored, 0)
            XCTAssertLessThanOrEqual(stored, GPUISceneLimits.maxBlurRadius)
        }
    }

    func testBlurRadiusIsCappedToTheBackendsBlurLimit() {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: 4_096))
        // The D3D11 engine clamps at 128; clamping here makes both
        // backends agree instead of diverging above the cap.
        XCTAssertEqual(scene.layers[0].quads[0].blurRadius, GPUISceneLimits.maxBlurRadius)
    }

    func testNonFiniteQuadGeometryIsRejected() {
        for value in [Float.nan, .infinity, -.infinity] {
            var scene = GPUIScene()
            scene.addQuad(QuadPrimitive(x: value, y: 0, width: 10, height: 10))
            scene.addQuad(QuadPrimitive(x: 0, y: value, width: 10, height: 10))
            scene.addQuad(QuadPrimitive(x: 0, y: 0, width: value, height: 10))
            scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: value))
            XCTAssertTrue(scene.layers[0].quads.isEmpty, "\(value) geometry must be dropped")
            XCTAssertEqual(scene.paintRecordCount, 0)
        }
    }

    func testNonFiniteClipIsRejectedRatherThanTreatedAsUnclipped() {
        // Dropping is the only answer that cannot let a clipped subtree
        // paint across the whole window.
        var scene = GPUIScene()
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 10, height: 10,
                clipX: 0, clipY: 0, clipWidth: .nan, clipHeight: 100))
        scene.addGlyph(
            GlyphPrimitive(
                screenX: 0, screenY: 0, screenW: 10, screenH: 10,
                clipX: .infinity, clipY: 0, clipWidth: 100, clipHeight: 100))
        XCTAssertTrue(scene.layers[0].quads.isEmpty)
        XCTAssertTrue(scene.layers[0].glyphs.isEmpty)
        XCTAssertEqual(scene.paintRecordCount, 0)
    }

    func testHugeCoordinatesAreClampedIntoRange() throws {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 1e30, y: -1e30, width: 1e30, height: 10))
        let quad = try XCTUnwrap(scene.layers[0].quads.first)
        XCTAssertEqual(quad.x, GPUISceneLimits.maxCoordinate)
        XCTAssertEqual(quad.y, -GPUISceneLimits.maxCoordinate)
        XCTAssertEqual(quad.width, GPUISceneLimits.maxCoordinate)
    }

    func testWellFormedQuadIsStoredByteIdentically() {
        // Sanitation must be an identity transform for real scenes, or
        // every pinned pixel baseline in the repo moves.
        let quad = QuadPrimitive(
            x: 12.5, y: -3.25, width: 100, height: 40,
            cornerRadius: 8,
            startR: 0.2, startG: 0.4, startB: 0.6, startA: 1,
            endR: 0.3, endG: 0.5, endB: 0.7, endA: 0.8,
            gradientAxis: 1,
            clipX: 0, clipY: 0, clipWidth: 200, clipHeight: 200,
            clipCornerRadius: 4,
            blendMode: 2,
            effectType: 3,
            effectIntensity: 0.5,
            blurRadius: 12,
            blurOpaque: 1,
            rotationRadians: 0.25,
            cornerRadiusTopLeft: 1, cornerRadiusTopRight: 2,
            cornerRadiusBottomRight: 3, cornerRadiusBottomLeft: 4)
        var scene = GPUIScene()
        scene.addQuad(quad)
        XCTAssertEqual(scene.layers[0].quads.first, quad)
    }

    func testNonFiniteGlyphUVsAreClampedNotTrapped() {
        var scene = GPUIScene()
        scene.addGlyph(
            GlyphPrimitive(
                screenX: 0, screenY: 0, screenW: 8, screenH: 8,
                atlasU0: .nan, atlasV0: -.infinity, atlasU1: 1e30, atlasV1: 1))
        let glyph = scene.layers[0].glyphs.first
        XCTAssertNotNil(glyph)
        XCTAssertTrue(glyph?.atlasU0.isFinite ?? false)
        XCTAssertTrue(glyph?.atlasV0.isFinite ?? false)
        XCTAssertTrue(glyph?.atlasU1.isFinite ?? false)
    }

    /// WS-16 gave every family a rounded clip, but only `sanitized(quad:)`
    /// learned to clamp the radius it added. The other four copied it
    /// verbatim, and `clipIsRepresentable` — which is what rejects an
    /// unrepresentable clip — never looked at it, so a NaN or negative
    /// rounding reached both backends' distance term unchallenged.
    func testClipCornerRadiusIsClampedInEveryFamily() throws {
        for radius in [Float.nan, .infinity, -.infinity, -8, 1e30] {
            var scene = GPUIScene()
            scene.addQuad(
                QuadPrimitive(
                    x: 0, y: 0, width: 10, height: 10,
                    clipX: 0, clipY: 0, clipWidth: 100, clipHeight: 100,
                    clipCornerRadius: radius))
            scene.addGlyph(
                GlyphPrimitive(
                    screenX: 0, screenY: 0, screenW: 10, screenH: 10,
                    clipX: 0, clipY: 0, clipWidth: 100, clipHeight: 100,
                    clipCornerRadius: radius))
            scene.addImage(
                ImagePrimitive(
                    screenX: 0, screenY: 0, screenW: 10, screenH: 10,
                    clipX: 0, clipY: 0, clipWidth: 100, clipHeight: 100,
                    clipCornerRadius: radius))
            scene.addShadow(
                ShadowPrimitive(
                    x: 0, y: 0, width: 10, height: 10,
                    clipX: 0, clipY: 0, clipWidth: 100, clipHeight: 100,
                    clipCornerRadius: radius))
            scene.addPath(
                PathPrimitive(
                    elements: [.moveTo(Point(x: 0, y: 0)), .lineTo(Point(x: 10, y: 10)), .close],
                    bounds: Rect(x: 0, y: 0, width: 10, height: 10),
                    fillColor: .white,
                    clipBounds: Rect(x: 0, y: 0, width: 100, height: 100),
                    clipCornerRadius: Double(radius)
                ), toLayer: 0)

            let layer = scene.layers[0]
            let stored: [Double] = [
                Double(try XCTUnwrap(layer.quads.first).clipCornerRadius),
                Double(try XCTUnwrap(layer.glyphs.first).clipCornerRadius),
                Double(try XCTUnwrap(layer.images.first).clipCornerRadius),
                Double(try XCTUnwrap(layer.shadows.first).clipCornerRadius),
                try XCTUnwrap(layer.paths.first).clipCornerRadius,
            ]
            for value in stored {
                XCTAssertTrue(value.isFinite, "clipCornerRadius \(radius) survived as \(value)")
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, Double(GPUISceneLimits.maxCoordinate))
            }
        }
    }

    // MARK: - Path sanitation

    func testInfiniteAndNaNPathGeometryIsClampedAndRasterizesWithoutHanging() {
        var scene = GPUIScene()
        scene.addPath(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 0, y: 0)),
                    .lineTo(Point(x: .infinity, y: 0)),
                    .cubicCurveTo(
                        control1: Point(x: .nan, y: .nan),
                        control2: Point(x: 20, y: 20),
                        end: Point(x: 30, y: 30)),
                    .quadraticCurveTo(control: Point(x: -.infinity, y: 5), end: Point(x: 10, y: 10)),
                    .close,
                ],
                bounds: Rect(x: 0, y: 0, width: 40, height: 40),
                fillColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                strokeColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
                lineWidth: 2
            ), toLayer: 0)
        XCTAssertEqual(scene.layers[0].paths.count, 1)
        for element in scene.layers[0].paths[0].elements {
            XCTAssertTrue(Self.elementIsFinite(element), "\(element) survived sanitation")
        }
        scene.finish()
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 40, height: 40))
        XCTAssertEqual(Int(bitmap.width), 40)
    }

    func testInfiniteArcRadiusDoesNotHangOrTrap() {
        var scene = GPUIScene()
        scene.addPath(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 10, y: 10)),
                    .arc(
                        center: Point(x: 20, y: 20), radius: .infinity,
                        startAngle: 0, endAngle: .nan, clockwise: true),
                    .close,
                ],
                bounds: Rect(x: 0, y: 0, width: 40, height: 40),
                fillColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
            ), toLayer: 0)
        scene.finish()
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 40, height: 40))
        XCTAssertEqual(Int(bitmap.width), 40)
    }

    func testPathElementCountAboveTheLimitIsRejected() {
        var elements: [PathElement] = [.moveTo(.zero)]
        elements.append(
            contentsOf: (0...GPUISceneLimits.maxPathElements).map { index in
                PathElement.lineTo(Point(x: Double(index % 32), y: 1))
            })
        var scene = GPUIScene()
        scene.addPath(
            PathPrimitive(
                elements: elements,
                bounds: Rect(x: 0, y: 0, width: 32, height: 32),
                fillColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
            ), toLayer: 0)
        XCTAssertTrue(scene.layers[0].paths.isEmpty)
        XCTAssertEqual(scene.paintRecordCount, 0)
    }

    func testPathOutsideItsClipIsDropped() {
        // The exact analogue of `testFullyClippedPrimitiveOutsideContentMaskIsOmitted`
        // for the one family that used to fall back to its unclipped bounds.
        var scene = GPUIScene()
        scene.addPath(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 0, y: 0)),
                    .lineTo(Point(x: 50, y: 0)),
                    .lineTo(Point(x: 25, y: 50)),
                    .close,
                ],
                bounds: Rect(x: 0, y: 0, width: 50, height: 50),
                fillColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
                clipBounds: Rect(x: 200, y: 200, width: 50, height: 50)
            ), toLayer: 0)
        XCTAssertTrue(scene.layers[0].paths.isEmpty)
        XCTAssertEqual(scene.paintRecordCount, 0)
    }

    func testPathClipThatOverlapsIsStillAccepted() {
        var scene = GPUIScene()
        scene.addPath(
            PathPrimitive(
                elements: [.moveTo(.zero), .lineTo(Point(x: 50, y: 50)), .close],
                bounds: Rect(x: 0, y: 0, width: 50, height: 50),
                fillColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
                clipBounds: Rect(x: 25, y: 25, width: 50, height: 50)
            ), toLayer: 0)
        XCTAssertEqual(scene.layers[0].paths.count, 1)
    }

    func testRasterizePathRejectsNonFiniteBounds() {
        let path = PathPrimitive(
            elements: [.moveTo(.zero), .lineTo(Point(x: 10, y: 10)), .close],
            bounds: Rect(x: 0, y: 0, width: .infinity, height: 10),
            fillColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
        )
        XCTAssertNil(GPUIRawSceneRasterizer.rasterizePath(path))
    }

    // MARK: - Rasterizer survival

    func testRasterizerSurvivesNonFiniteFieldsAcrossEveryFamily() {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 5, y: 5, width: 20, height: 20,
                blendMode: .nan, effectType: .infinity, effectIntensity: .nan,
                blurRadius: .infinity, rotationRadians: .nan))
        scene.addShadow(
            ShadowPrimitive(x: 5, y: 5, width: 20, height: 20, blurRadius: .infinity, offsetX: 0, offsetY: 0))
        scene.addImage(
            ImagePrimitive(
                screenX: 0, screenY: 0, screenW: 20, screenH: 20,
                uvX: .nan, uvY: -.infinity, uvW: 1e30, uvH: 1, opacity: .nan))
        scene.finish()
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 40, height: 40))
        XCTAssertEqual(Int(bitmap.width), 40)
        XCTAssertEqual(Int(bitmap.height), 40)
    }

    func testRasterizerToleratesDuplicateImageTextureIDs() {
        // `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key;
        // a producer bug must not be a process kill.
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([255, 255, 255, 255]))
        scene.imageResources = [
            ImageResourceBinding(textureID: 7, bitmap: bitmap),
            ImageResourceBinding(textureID: 7, bitmap: bitmap),
        ]
        _ = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 8, height: 8))
    }

    func testRasterizerClampsAbsurdSurfaceSizes() {
        let scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: Int32.max, height: 1))
        XCTAssertLessThanOrEqual(Int(bitmap.width), GPUISceneLimits.maxSurfaceDimension)
        XCTAssertGreaterThan(Int(bitmap.width), 0)
    }

    // MARK: - Backend conversion sites

    func testSplitQuadRangeForBackdropBlurSurvivesNonFiniteRadii() async {
        await MainActor.run {
            for radius in [Float.nan, .infinity, -.infinity, 1e30] {
                let quads = [
                    QuadPrimitive(x: 0, y: 0, width: 10, height: 10),
                    QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: radius),
                    QuadPrimitive(x: 0, y: 0, width: 10, height: 10),
                ]
                let segments = D3D11BatchRenderer.splitQuadRangeForBackdropBlur(quads, range: 0..<3)
                XCTAssertFalse(segments.isEmpty, "radius \(radius) produced no segments")
            }
        }
    }

    func testSplitQuadRangeTreatsNaNRadiusAsUnblurred() async {
        await MainActor.run {
            let quads = [QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: .nan)]
            XCTAssertEqual(
                D3D11BatchRenderer.splitQuadRangeForBackdropBlur(quads, range: 0..<1),
                [.normal(range: 0..<1)])
        }
    }

    func testBlurRegionCollapsesForNonFiniteGeometry() async {
        await MainActor.run {
            for value in [Float.nan, .infinity, -.infinity] {
                let quad = QuadPrimitive(x: value, y: 0, width: 40, height: 40, blurRadius: 8)
                let region = D3D11BackdropBlurEngine.blurRegion(for: quad, surfaceWidth: 128, surfaceHeight: 128)
                XCTAssertGreaterThanOrEqual(region.x1, region.x0, "\(value) produced an inverted region")
                XCTAssertGreaterThanOrEqual(region.y1, region.y0)
                XCTAssertGreaterThanOrEqual(region.x0, 0)
                XCTAssertLessThanOrEqual(region.x1, 128)
            }
        }
    }

    func testBlurRegionSurvivesNonFiniteRotation() async {
        await MainActor.run {
            let quad = QuadPrimitive(x: 10, y: 10, width: 40, height: 40, blurRadius: 8, rotationRadians: .nan)
            let region = D3D11BackdropBlurEngine.blurRegion(for: quad, surfaceWidth: 128, surfaceHeight: 128)
            XCTAssertGreaterThanOrEqual(region.x1, region.x0)
            XCTAssertGreaterThanOrEqual(region.y1, region.y0)
        }
    }

    func testMakeRenderPlanSurvivesNonFiniteQuadFields() async throws {
        try await MainActor.run {
            var scene = GPUIScene()
            scene.addQuad(
                QuadPrimitive(
                    x: 0, y: 0, width: 10, height: 10,
                    blendMode: .infinity, effectType: .nan, blurRadius: .nan))
            scene.finish()
            let plan = try D3D11BatchRenderer.makeRenderPlan(for: scene)
            XCTAssertEqual(plan.steps.count, 1)
        }
    }

    private static func elementIsFinite(_ element: PathElement) -> Bool {
        func ok(_ point: Point) -> Bool { point.x.isFinite && point.y.isFinite }
        switch element {
        case .moveTo(let point), .lineTo(let point):
            return ok(point)
        case .quadraticCurveTo(let control, let end):
            return ok(control) && ok(end)
        case .cubicCurveTo(let control1, let control2, let end):
            return ok(control1) && ok(control2) && ok(end)
        case .arc(let center, let radius, let start, let end, _):
            return ok(center) && radius.isFinite && start.isFinite && end.isFinite
        case .close:
            return true
        }
    }
}

/// Structural bounds on the scene container itself: layer count, paint
/// operation ranges and atlas snapshot geometry.
///
/// Field-level sanitation happens at `add*`; this covers what the
/// scene's `public var` surface can still express — the shapes
/// `makeRenderPlan` used to index unchecked and *trap* on.
final class SceneStructuralValidationTests: XCTestCase {

    func testOutOfRangeLayerIndexIsRejectedWithoutAllocating() {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10), toLayer: Int.max)
        XCTAssertEqual(scene.layers.count, 1, "an absurd layer index must not grow the layer array")
        XCTAssertTrue(scene.layers[0].quads.isEmpty)
        XCTAssertEqual(scene.paintRecordCount, 0)

        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10), toLayer: GPUISceneLimits.maxLayers)
        XCTAssertEqual(scene.layers.count, 1)

        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10), toLayer: -1)
        XCTAssertEqual(scene.layers.count, 1)
    }

    func testLayerIndexInsideTheLimitStillExpandsTheScene() {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10), toLayer: 3)
        XCTAssertEqual(scene.layers.count, 4)
        XCTAssertEqual(scene.layers[3].quads.count, 1)
    }

    func testEnsureLayerReportsWhetherTheLayerExists() {
        var scene = GPUIScene()
        XCTAssertTrue(scene.ensureLayer(2))
        XCTAssertFalse(scene.ensureLayer(-1))
        XCTAssertFalse(scene.ensureLayer(GPUISceneLimits.maxLayers))
        XCTAssertEqual(scene.layers.count, 3)
    }

    func testValidateAcceptsAWellFormedScene() {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10))
        scene.addShadow(ShadowPrimitive(x: 0, y: 0, width: 10, height: 10))
        scene.finish()
        XCTAssertTrue(scene.validate().isEmpty)
    }

    /// A one-layer scene whose layer is hand-built rather than grown
    /// through `add*`. The family arrays are `public private(set)`, so this
    /// is the remaining way to produce a malformed scene — which is exactly
    /// the residual hole `validate()` exists to cover.
    private static func sceneWithHandBuiltLayer(_ layer: GPUILayer) -> GPUIScene {
        var scene = GPUIScene()
        scene.installHandBuiltLayer(layer, at: 0)
        return scene
    }

    private static let unitQuad = QuadPrimitive(x: 0, y: 0, width: 10, height: 10)

    func testValidateReportsNegativePaintOperationCount() {
        let scene = Self.sceneWithHandBuiltLayer(
            GPUILayer(
                quads: [Self.unitQuad],
                paintOperations: [GPUIPaintOperation(kind: .quad, startIndex: 0, count: -1)]))
        XCTAssertEqual(scene.validate().count, 1)
    }

    func testMakeRenderPlanThrowsOnNegativePaintOperationCount() async throws {
        try await MainActor.run {
            let scene = Self.sceneWithHandBuiltLayer(
                GPUILayer(
                    quads: [Self.unitQuad],
                    paintOperations: [GPUIPaintOperation(kind: .quad, startIndex: 0, count: -1)]))
            XCTAssertThrowsError(try D3D11BatchRenderer.makeRenderPlan(for: scene)) { error in
                guard let batchError = error as? BatchRendererError else {
                    return XCTFail("Expected BatchRendererError, got \(error)")
                }
                XCTAssertEqual(batchError.operation, "Validate scene")
            }
        }
    }

    func testMakeRenderPlanThrowsOnOutOfRangePaintOperation() async throws {
        try await MainActor.run {
            let scene = Self.sceneWithHandBuiltLayer(
                GPUILayer(
                    quads: [Self.unitQuad],
                    paintOperations: [GPUIPaintOperation(kind: .quad, startIndex: 0, count: 4)]))
            XCTAssertThrowsError(try D3D11BatchRenderer.makeRenderPlan(for: scene))

            let negativeStart = Self.sceneWithHandBuiltLayer(
                GPUILayer(
                    quads: [Self.unitQuad],
                    paintOperations: [GPUIPaintOperation(kind: .quad, startIndex: -1, count: 1)]))
            XCTAssertThrowsError(try D3D11BatchRenderer.makeRenderPlan(for: negativeStart))
        }
    }

    func testMakeRenderPlanThrowsOnAnImagePaintOperationPastItsFamily() async throws {
        // The image case walks `layer.images[runStart]` directly, so an
        // over-long run is an unchecked index, not just a wrong picture.
        try await MainActor.run {
            var scene = GPUIScene()
            let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([255, 255, 255, 255]))
            let textureID = scene.registerImageResource(bitmap)
            scene.installHandBuiltLayer(
                GPUILayer(
                    images: [ImagePrimitive(screenX: 0, screenY: 0, screenW: 4, screenH: 4, textureID: textureID)],
                    paintOperations: [GPUIPaintOperation(kind: .image, startIndex: 0, count: 3)]),
                at: 0)
            XCTAssertThrowsError(
                try D3D11BatchRenderer.makeRenderPlan(
                    for: scene,
                    cachedResources: D3D11BatchRenderer.CachedResources(boundImageTextureIDs: [textureID])))
        }
    }

    func testValidateReportsAShortGlyphAtlasBuffer() {
        var scene = GPUIScene()
        scene.glyphAtlas = GlyphAtlasSnapshot(width: 64, height: 64, pixels: Data(count: 16))
        XCTAssertEqual(scene.validate().count, 1)
    }

    private static func makeAtlas() -> GlyphAtlasSnapshot {
        GlyphAtlasSnapshot(width: 64, height: 64, pixels: Data(count: 64 * 64 * 4))
    }

    func testClampedRegionNormalisesNegativeAndOversizedRegions() {
        let atlas = Self.makeAtlas()
        let clamped = atlas.clampedRegion(GlyphAtlasRegion(x: -8, y: -8, width: 16, height: 16))
        XCTAssertEqual(clamped?.x, 0)
        XCTAssertEqual(clamped?.y, 0)
        XCTAssertEqual(clamped?.width, 8)
        XCTAssertEqual(clamped?.height, 8)

        let overhang = atlas.clampedRegion(GlyphAtlasRegion(x: 60, y: 60, width: 100, height: 100))
        XCTAssertEqual(overhang?.width, 4)
        XCTAssertEqual(overhang?.height, 4)

        XCTAssertNil(
            atlas.clampedRegion(GlyphAtlasRegion(x: 200, y: 200, width: 8, height: 8)),
            "a region outside the atlas degrades to a full upload")
        XCTAssertNil(atlas.clampedRegion(GlyphAtlasRegion(x: 0, y: 0, width: 0, height: 0)))
    }

    func testClampedRegionPassesAWellFormedRegionThrough() {
        XCTAssertEqual(
            Self.makeAtlas().clampedRegion(GlyphAtlasRegion(x: 8, y: 12, width: 16, height: 20)),
            GlyphAtlasRegion(x: 8, y: 12, width: 16, height: 20))
    }
}
