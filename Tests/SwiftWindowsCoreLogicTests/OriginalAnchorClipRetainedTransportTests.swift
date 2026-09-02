import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Original shape S and full physical corners C survive retained emission,
/// rectangular rejection R, path promotion and immutable departure capture.
@MainActor
final class OriginalAnchorClipRetainedTransportTests: XCTestCase {
    private let anchor = Rect(x: 0, y: 0, width: 100, height: 100)
    private let corners = RetainedCornerRadii(topLeft: 40, topRight: 4, bottomRight: 8, bottomLeft: 0)

    private func croppedTree(
        crop: Rect, shape: Rect = Rect(x: 0, y: 0, width: 100, height: 100),
        radii: RetainedCornerRadii? = nil, uniformRadius: Double = 0,
        cropAboveShape: Bool = false, deferred: Bool = false
    ) -> (root: ViewNode, rounded: ViewNode) {
        let localCrop = crop.offsetBy(dx: -shape.minX, dy: -shape.minY)
        let leafFrame =
            cropAboveShape
            ? Rect(origin: .zero, size: shape.size)
            : Rect(x: -localCrop.minX, y: -localCrop.minY, width: shape.size.width, height: shape.size.height)
        let leaf = ViewNode(
            frame: leafFrame, backgroundColor: .white,
            paintsInDeferredPhase: deferred)
        if cropAboveShape {
            let rounded = ViewNode(
                frame: shape.offsetBy(dx: -crop.minX, dy: -crop.minY),
                cornerRadius: uniformRadius, cornerRadii: radii, clipsToBounds: true, children: [leaf])
            return (ViewNode(frame: crop, clipsToBounds: true, children: [rounded]), rounded)
        }
        let cropNode = ViewNode(frame: localCrop, clipsToBounds: true, children: [leaf])
        let rounded = ViewNode(
            frame: shape, cornerRadius: uniformRadius, cornerRadii: radii,
            clipsToBounds: true, children: [cropNode])
        return (rounded, rounded)
    }

    private func paint(_ root: ViewNode, size: Size = Size(width: 100, height: 100), scale: Double = 1) -> GPUIScene {
        ScenePainter.paint(root: root, clearColor: .clear, surfaceSize: size, displayScale: scale)
    }

    private func raster(_ scene: GPUIScene, size: IntSize = IntSize(width: 100, height: 100)) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(scene, size: size)
    }

    private func alpha(_ bitmap: BitmapSurface, x: Int, y: Int) -> Int {
        Int(bitmap.pixels[y * Int(bitmap.bytesPerRow) + x * 4 + 3])
    }

    private func assertClip(
        shape: Rect?, radii: [Float], expectedShape: Rect, expectedRadii: RetainedCornerRadii,
        scale: Double = 1, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(shape, expectedShape.scaled(by: scale), file: file, line: line)
        XCTAssertEqual(
            radii,
            [expectedRadii.topLeft, expectedRadii.topRight, expectedRadii.bottomRight, expectedRadii.bottomLeft]
                .map { Float($0 * scale) },
            file: file, line: line)
    }

    private func assertClip(
        _ quad: QuadPrimitive, shape: Rect, radii: RetainedCornerRadii, scale: Double = 1,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertClip(
            shape: quad.clipShapeBounds,
            radii: [
                quad.clipCornerRadiusTopLeft, quad.clipCornerRadiusTopRight,
                quad.clipCornerRadiusBottomRight, quad.clipCornerRadiusBottomLeft,
            ],
            expectedShape: shape, expectedRadii: radii, scale: scale, file: file, line: line)
    }

    private func assertClip(
        _ image: ImagePrimitive, shape: Rect, radii: RetainedCornerRadii, scale: Double = 1,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertClip(
            shape: image.clipShapeBounds,
            radii: [
                image.clipCornerRadiusTopLeft, image.clipCornerRadiusTopRight,
                image.clipCornerRadiusBottomRight, image.clipCornerRadiusBottomLeft,
            ],
            expectedShape: shape, expectedRadii: radii, scale: scale, file: file, line: line)
    }

    private func assertClip(
        _ path: PathPrimitive, shape: Rect, radii: RetainedCornerRadii, scale: Double = 1,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(path.clipShapeBounds, shape.scaled(by: scale), file: file, line: line)
        XCTAssertEqual(
            [
                path.clipCornerRadiusTopLeft, path.clipCornerRadiusTopRight,
                path.clipCornerRadiusBottomRight, path.clipCornerRadiusBottomLeft,
            ],
            [radii.topLeft, radii.topRight, radii.bottomRight, radii.bottomLeft].map { $0 * scale },
            file: file, line: line)
    }

    func testRectangularCropAboveAndBelowRoundedShapeKeepsPartialArcs() async throws {
        let crop = Rect(x: 0, y: 4, width: 100, height: 96)
        for scale in [1.0, 1.25, 1.5, 2.0] {
            var previousPixels: Data?
            for cropAbove in [false, true] {
                let tree = croppedTree(crop: crop, radii: corners, cropAboveShape: cropAbove)
                let scene = paint(tree.root, scale: scale)
                let quad = try XCTUnwrap(scene.layers.flatMap(\.quads).first)
                XCTAssertEqual(scene.primitiveCount, 1)
                XCTAssertEqual(quad.contentMask.bounds, crop.scaled(by: scale))
                assertClip(quad, shape: anchor, radii: corners, scale: scale)
                let bitmap = raster(scene, size: IntSize(width: Int32(100 * scale), height: Int32(100 * scale)))
                // Distances from TL's original centre are safely outside its
                // radius, while the deliberately square BL is wholly inside.
                XCTAssertEqual(alpha(bitmap, x: Int(4.5 * scale), y: Int(8.5 * scale)), 0)
                XCTAssertEqual(alpha(bitmap, x: Int(1.5 * scale), y: Int(98.5 * scale)), 255)
                if let previousPixels { XCTAssertEqual(bitmap.pixels, previousPixels) }
                previousPixels = bitmap.pixels
            }
        }
    }

    func testThinCropUsesOriginalRadiusCapAndDoesNotBiteInteriorSquareCrop() async throws {
        let thin = croppedTree(
            crop: Rect(x: 0, y: 0, width: 100, height: 4), radii: RetainedCornerRadii(topLeft: 40))
        let thinScene = paint(thin.root)
        let quad = try XCTUnwrap(thinScene.layers.flatMap(\.quads).first)
        XCTAssertEqual(quad.clipCornerRadiusTopLeft, 40)
        XCTAssertEqual(quad.clipShapeBounds, anchor)
        let thinPixels = raster(thinScene)
        XCTAssertEqual(alpha(thinPixels, x: 2, y: 1), 0)
        XCTAssertEqual(alpha(thinPixels, x: 60, y: 1), 255)

        let inside = croppedTree(crop: Rect(x: 45, y: 45, width: 10, height: 10), radii: corners)
        let insidePixels = raster(paint(inside.root))
        for (x, y) in [(45, 45), (54, 45), (54, 54), (45, 54)] {
            XCTAssertEqual(alpha(insidePixels, x: x, y: y), 255)
        }
    }

    func testUniformTinyCropExportsFullRadiiAndUngatedDerivativeCoverage() async throws {
        let shape = Rect(x: 0, y: 0, width: 20, height: 20)
        let tree = croppedTree(crop: Rect(x: 1, y: 1, width: 1, height: 1), shape: shape, uniformRadius: 5)
        let scene = paint(tree.root, size: shape.size)
        let quad = try XCTUnwrap(scene.layers.flatMap(\.quads).first)
        XCTAssertEqual(quad.clipCornerRadius, 0, "The legacy cut-corner projection remains unchanged")
        assertClip(quad, shape: shape, radii: RetainedCornerRadii(uniform: 5))
        let pixels = raster(scene, size: IntSize(width: 20, height: 20))
        let expected = 0.5 - (sqrt(24.5) - 5) / (2 * (sqrt(40.5) - sqrt(32.5)))
        XCTAssertEqual(Double(alpha(pixels, x: 1, y: 1)), expected * 255, accuracy: 1.5)
        XCTAssertEqual(alpha(pixels, x: 0, y: 1), 0)
        XCTAssertEqual(alpha(pixels, x: 2, y: 1), 0)
    }

    func testOwnDecorationUsesBodyCoverageOnceIncludingBackgroundPathStroke() async throws {
        let shape = Rect(x: 0, y: 0, width: 20, height: 20)
        let node = ViewNode(frame: shape, backgroundColor: .white, cornerRadius: 5, clipsToBounds: true)
        let scene = paint(node, size: shape.size)
        let quad = try XCTUnwrap(scene.layers.flatMap(\.quads).first)
        XCTAssertEqual(quad.clipCornerRadius, 0)
        assertClip(quad, shape: shape, radii: RetainedCornerRadii(uniform: 0))
        var reference = GPUIScene(clearColor: .clear)
        reference.addQuad(
            QuadPrimitive(
                width: 20, height: 20, cornerRadius: 5,
                startR: 1, startG: 1, startB: 1, endR: 1, endG: 1, endB: 1))
        XCTAssertEqual(
            raster(scene, size: IntSize(width: 20, height: 20)).pixels,
            raster(reference, size: IntSize(width: 20, height: 20)).pixels)

        var unitPath = RenderPath()
        unitPath.move(to: .zero)
        unitPath.addLine(to: Point(x: 1, y: 0))
        unitPath.addLine(to: Point(x: 1, y: 1))
        unitPath.addLine(to: Point(x: 0, y: 1))
        unitPath.close()
        node.backgroundPath = unitPath
        node.borderColor = .white
        node.borderWidth = 2
        let clippedPath = paint(node, size: shape.size)
        node.clipsToBounds = false
        let plainPath = paint(node, size: shape.size)
        XCTAssertGreaterThan(clippedPath.primitiveCount, 1, "Exercise both fill and stroke emitters")
        XCTAssertTrue(clippedPath.layers.flatMap(\.quads).allSatisfy { $0.clipCornerRadius == 0 })
        XCTAssertEqual(
            raster(clippedPath, size: IntSize(width: 20, height: 20)).pixels,
            raster(plainPath, size: IntSize(width: 20, height: 20)).pixels)
    }

    func testCacheReplaysThenRebuildsWhenAnOriginalRadiusChanges() async throws {
        let tree = croppedTree(crop: Rect(x: 0, y: 4, width: 100, height: 96), radii: corners)
        let textSystem = WindowTextSystem()
        var deferred: [DeferredDrawState] = []
        var replayCount = 0
        var deferredReplayCount = 0
        func snapshot(_ previous: ScenePaintSnapshot?) -> ScenePaintSnapshot {
            ScenePainter.paintSnapshot(
                root: tree.root, clearColor: .clear, surfaceSize: anchor.size, textSystem: textSystem,
                previousSnapshot: previous, deferredDraws: &deferred,
                replayCount: &replayCount, deferredReplayCount: &deferredReplayCount)
        }
        let first = snapshot(nil)
        let warm = snapshot(first)
        XCTAssertGreaterThan(replayCount, 0)
        XCTAssertEqual(first.scene.layers.flatMap(\.quads), warm.scene.layers.flatMap(\.quads))
        tree.rounded.cornerRadii = RetainedCornerRadii(topLeft: 4, topRight: 4, bottomRight: 8, bottomLeft: 0)
        let changed = snapshot(warm)
        XCTAssertEqual(changed.scene.primitiveCount, first.scene.primitiveCount)
        XCTAssertEqual(changed.scene.layers.flatMap(\.quads).first?.clipCornerRadiusTopLeft, 4)
        XCTAssertEqual(alpha(raster(first.scene), x: 4, y: 8), 0)
        XCTAssertEqual(alpha(raster(changed.scene), x: 4, y: 8), 255)
    }

    func testDeferredSubtreeMatchesInlineOriginalAnchorPixels() async throws {
        var firstPixels: Data?
        for deferred in [false, true] {
            let tree = croppedTree(
                crop: Rect(x: 0, y: 4, width: 100, height: 96), radii: corners, deferred: deferred)
            let runtime = RetainedViewRuntime(clearColor: .clear, root: tree.root, displayScale: 1.5)
            let scene = runtime.renderScene()
            let quad = try XCTUnwrap(scene.layers.flatMap(\.quads).first)
            assertClip(quad, shape: anchor, radii: corners, scale: 1.5)
            let pixels = raster(scene, size: IntSize(width: 150, height: 150)).pixels
            if let firstPixels { XCTAssertEqual(pixels, firstPixels) }
            firstPixels = pixels
        }
    }

    private func indicatorScene(clip: RuntimeClipShape, effects: [RetainedColorEffect] = []) -> GPUIScene {
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100))
        node.colorEffects = effects
        var deferred = [
            DeferredDrawState(
                priority: 0, parentDispatchIndex: 0, contentMask: clip,
                payload: .scrollIndicator(
                    ScrollIndicatorDeferredDrawPayload(
                        node: node, dispatchIndex: 0,
                        track: ScrollIndicatorTrack(
                            axis: .vertical, origin: 0, travel: 1, indicatorRect: clip.shapeRect),
                        color: .white, cornerRadius: 0)))
        ]
        var replay = 0
        var deferredReplay = 0
        return ScenePainter.paintSnapshot(
            root: node, clearColor: .clear, surfaceSize: anchor.size, textSystem: WindowTextSystem(),
            previousSnapshot: nil, deferredDraws: &deferred, replayCount: &replay,
            deferredReplayCount: &deferredReplay
        ).scene
    }

    func testDeferredIndicatorAndColorEffectCaptureRetainAnchorWithoutOutputRemask() async throws {
        let clip = RuntimeClipShape(
            rect: Rect(x: 0, y: 4, width: 100, height: 96), shapeRect: anchor, radii: corners, space: .painted)
        let ordinary = indicatorScene(clip: clip)
        assertClip(try XCTUnwrap(ordinary.layers.flatMap(\.quads).first), shape: anchor, radii: corners)
        let filtered = indicatorScene(clip: clip, effects: [.brightness(0)])
        let pass = try XCTUnwrap(filtered.imageRenderPasses.first)
        let image = try XCTUnwrap(filtered.layers.flatMap(\.images).first)
        let sourceQuad = try XCTUnwrap(pass.scene.layers.flatMap(\.quads).first)
        assertClip(
            sourceQuad, shape: anchor.offsetBy(dx: -Double(image.screenX), dy: -Double(image.screenY)), radii: corners)
        XCTAssertNil(image.clipShapeBounds, "The source already owns its clip coverage")
        XCTAssertEqual(image.clipCornerRadiusTopLeft, 0)
        XCTAssertEqual(raster(filtered).pixels, raster(ordinary).pixels)
    }

    func testMixedRetainedEmittersCarryOneClipWithoutChangingPresentation() async throws {
        let crop = Rect(x: 0, y: 4, width: 100, height: 96)
        let contentFrame = Rect(x: 0, y: -4, width: 100, height: 100)
        let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data(repeating: 255, count: 4))
        let label = ViewNode(
            frame: contentFrame, text: "Clipped", textStyle: PixelTextStyle(color: .white, underline: true))
        let pixelLabel = ViewNode(
            frame: contentFrame, text: "\u{E000}", textStyle: PixelTextStyle(color: .white, strikethrough: true))
        let shadow = ViewNode(frame: contentFrame)
        shadow.shadowColor = .white
        shadow.shadowSpread = 2
        let canvas = ViewNode(
            frame: contentFrame,
            canvasDraw: { context, _ in
                context.clip(to: Rect(x: 0, y: 4, width: 100, height: 96))
                context.fill(Rect(x: 0, y: 0, width: 100, height: 100), with: .color(.white))
                var path = Path()
                path.moveTo(Point(x: 10, y: 10))
                path.lineTo(Point(x: 60, y: 10))
                path.lineTo(Point(x: 60, y: 60))
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 6, lineJoin: .bevel))
                context.draw(bitmap, in: Rect(x: 0, y: 0, width: 100, height: 100))
                context.popClip()
            })
        let cropNode = ViewNode(
            frame: crop, clipsToBounds: true,
            children: [
                ViewNode(frame: contentFrame, backgroundColor: .white), label, pixelLabel,
                ViewNode(frame: contentFrame, bitmapSurface: bitmap), shadow, canvas,
            ])
        let root = ViewNode(frame: anchor, cornerRadii: corners, clipsToBounds: true, children: [cropNode])
        let scene = paint(root, scale: 1.25)
        let quads = scene.layers.flatMap(\.quads)
        let glyphs = scene.layers.flatMap(\.glyphs) + scene.layers.flatMap(\.pixelGlyphs)
        let shadows = scene.layers.flatMap(\.shadows)
        let images = scene.layers.flatMap(\.images)
        let paths = scene.layers.flatMap(\.paths)
        XCTAssertFalse(quads.isEmpty)
        XCTAssertFalse(glyphs.isEmpty)
        XCTAssertFalse(scene.layers.flatMap(\.pixelGlyphs).isEmpty)
        XCTAssertFalse(shadows.isEmpty)
        XCTAssertFalse(images.isEmpty)
        XCTAssertFalse(paths.isEmpty, "The bevel join retains a residual path")
        for quad in quads { assertClip(quad, shape: anchor, radii: corners, scale: 1.25) }
        for image in images { assertClip(image, shape: anchor, radii: corners, scale: 1.25) }
        for path in paths { assertClip(path, shape: anchor, radii: corners, scale: 1.25) }
        for glyph in glyphs {
            assertClip(
                shape: glyph.clipShapeBounds,
                radii: [
                    glyph.clipCornerRadiusTopLeft, glyph.clipCornerRadiusTopRight,
                    glyph.clipCornerRadiusBottomRight, glyph.clipCornerRadiusBottomLeft,
                ],
                expectedShape: anchor, expectedRadii: corners, scale: 1.25)
        }
        for shadow in shadows {
            assertClip(
                shape: shadow.clipShapeBounds,
                radii: [
                    shadow.clipCornerRadiusTopLeft, shadow.clipCornerRadiusTopRight,
                    shadow.clipCornerRadiusBottomRight, shadow.clipCornerRadiusBottomLeft,
                ],
                expectedShape: anchor, expectedRadii: corners, scale: 1.25)
        }
        root.cornerRadii = nil
        let square = paint(root, scale: 1.25)
        XCTAssertEqual(scene.primitiveCount, square.primitiveCount)
        XCTAssertEqual(scene.presentationOrder().map(\.kind), square.presentationOrder().map(\.kind))
        XCTAssertEqual(scene.presentationOrder().map(\.layerIndex), square.presentationOrder().map(\.layerIndex))
    }

    func testMaterialContentBlurClipsOnlyItsFinalImage() async throws {
        let material = ViewNode(
            frame: anchor, backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 0.25), blurRadius: 2)
        let blurred = ViewNode(
            frame: Rect(x: 0, y: -4, width: 100, height: 100), contentBlurRadius: 3, children: [material])
        let crop = ViewNode(
            frame: Rect(x: 0, y: 4, width: 100, height: 96), clipsToBounds: true, children: [blurred])
        let root = ViewNode(frame: anchor, cornerRadii: corners, clipsToBounds: true, children: [crop])
        let scene = paint(root, scale: 1.5)
        let pass = try XCTUnwrap(scene.imageRenderPasses.first { $0.contentBlurRadius > 0 })
        let image = try XCTUnwrap(scene.layers.flatMap(\.images).first { $0.textureID == pass.textureID })
        assertClip(image, shape: anchor, radii: corners, scale: 1.5)
        XCTAssertEqual(image.contentMask.bounds, Rect(x: 0, y: 6, width: 150, height: 144))
        let sourceMaterial = try XCTUnwrap(pass.scene.layers.flatMap(\.quads).first { $0.blurRadius > 0 })
        XCTAssertNil(sourceMaterial.clipShapeBounds, "Filtering must not inherit the final output clip")
        XCTAssertEqual(sourceMaterial.clipCornerRadius, 0)
        XCTAssertEqual(sourceMaterial.clipCornerRadiusTopLeft, 0)
        XCTAssertEqual(pass.input, .isolatedBackdrop)
        XCTAssertEqual(pass.contentBlurRadius, 5)
    }

    func testCompositingAndRotatedClipImagesKeepOnlyTheirApplicableShape() async throws {
        let group = ViewNode(
            frame: anchor, isCompositingGroup: true,
            children: [ViewNode(frame: anchor, backgroundColor: .white)])
        let root = ViewNode(frame: anchor, cornerRadii: corners, clipsToBounds: true, children: [group])
        let composite = try XCTUnwrap(paint(root, scale: 1.25).layers.flatMap(\.images).first)
        assertClip(composite, shape: anchor, radii: corners, scale: 1.25)

        group.frame = Rect(x: 20, y: 20, width: 60, height: 60)
        group.cornerRadius = 12
        group.clipsToBounds = true
        group.transform = Transform2D(rotation: .pi / 4)
        group.children[0].frame = Rect(x: 0, y: 0, width: 60, height: 60)
        let rotated = try XCTUnwrap(paint(root, scale: 1.25).layers.flatMap(\.images).first)
        assertClip(rotated, shape: anchor, radii: corners, scale: 1.25)
        XCTAssertEqual(rotated.rotationRadians, Float.pi / 4, accuracy: 0.000_001)
    }

    private func polygon(_ points: [Point]) -> Path {
        var path = Path()
        if let first = points.first {
            path.moveTo(first)
            for point in points.dropFirst() { path.lineTo(point) }
            path.close()
        }
        return path
    }

    private func pathWithClip(_ path: Path, stroke: Bool = false) -> PathPrimitive {
        var result = PathPrimitive(
            elements: path.elements, bounds: path.boundingRect.outset(by: stroke ? 3 : 0),
            fillColor: stroke ? .clear : .white, strokeColor: stroke ? .white : .clear,
            lineWidth: stroke ? 6 : 0, lineJoin: .bevel,
            clipBounds: Rect(x: 0, y: 4, width: 100, height: 96))
        result.clipCornerRadiusTopLeft = corners.topLeft
        result.clipCornerRadiusTopRight = corners.topRight
        result.clipCornerRadiusBottomRight = corners.bottomRight
        result.clipCornerRadiusBottomLeft = corners.bottomLeft
        result.clipShapeBounds = anchor
        return result
    }

    func testAllPathPromotionHelpersPreserveOriginalClipAndBodyGeometry() async throws {
        var rectangle = Path()
        rectangle.addRect(anchor)
        var rounded = Path()
        rounded.addRoundedRect(anchor, cornerRadius: 6)
        let triangle = polygon([Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 50, y: 100)])
        let convex = polygon([Point(x: 10, y: 0), Point(x: 90, y: 0), Point(x: 100, y: 100), Point(x: 0, y: 100)])
        let concave = polygon([
            .zero, Point(x: 100, y: 0), Point(x: 100, y: 40), Point(x: 40, y: 40),
            Point(x: 40, y: 100), Point(x: 0, y: 100),
        ])
        var stroke = Path()
        stroke.moveTo(Point(x: 10, y: 10))
        stroke.lineTo(Point(x: 60, y: 10))
        stroke.lineTo(Point(x: 90, y: 40))
        var fixtures = [rectangle, rounded, triangle, convex, concave].map { pathWithClip($0) }
        fixtures.append(pathWithClip(stroke, stroke: true))
        var roundStroke = pathWithClip(stroke, stroke: true)
        roundStroke.lineJoin = .round
        roundStroke.lineCap = .round
        fixtures.append(roundStroke)
        for path in fixtures {
            let result = try XCTUnwrap(PathToQuadTessellator.tessellateMixed(path))
            var square = path
            square.clipCornerRadiusTopLeft = 0
            square.clipCornerRadiusTopRight = 0
            square.clipCornerRadiusBottomRight = 0
            square.clipCornerRadiusBottomLeft = 0
            square.clipShapeBounds = nil
            let originalGeometry = try XCTUnwrap(PathToQuadTessellator.tessellateMixed(square))
            XCTAssertEqual(result.quads.count, originalGeometry.quads.count)
            XCTAssertEqual(result.quads.map(\.x), originalGeometry.quads.map(\.x))
            XCTAssertEqual(result.quads.map(\.y), originalGeometry.quads.map(\.y))
            XCTAssertEqual(result.quads.map(\.width), originalGeometry.quads.map(\.width))
            XCTAssertEqual(result.quads.map(\.height), originalGeometry.quads.map(\.height))
            XCTAssertEqual(result.quads.map(\.rotationRadians), originalGeometry.quads.map(\.rotationRadians))
            XCTAssertEqual(result.quads.map(\.cornerRadius), originalGeometry.quads.map(\.cornerRadius))
            XCTAssertEqual(result.quads.map(\.clipCornerRadius), originalGeometry.quads.map(\.clipCornerRadius))
            for quad in result.quads { assertClip(quad, shape: anchor, radii: corners) }
            XCTAssertEqual(result.residualPath?.elements, originalGeometry.residualPath?.elements)
            if let residual = result.residualPath { assertClip(residual, shape: anchor, radii: corners) }
        }
    }

    func testPathEmissionScalesOriginalClipOnceThroughGradientAndResidualPromotion() async throws {
        var rectangle = Path()
        rectangle.addRect(anchor)
        var gradient = pathWithClip(rectangle)
        gradient.fillGradient = LinearGradient(
            stops: [
                GradientStop(color: .white, position: 0), GradientStop(color: .black, position: 0.4),
                GradientStop(color: .white, position: 1),
            ], axis: .horizontal)
        var scene = GPUIScene(clearColor: .clear)
        ScenePainter.emit(
            path: gradient, into: &scene, layerIndex: 0, displayScale: 1.5,
            surfaceSize: Size(width: 150, height: 150))
        XCTAssertEqual(scene.layers.flatMap(\.quads).count, 2)
        XCTAssertEqual(scene.paintMetrics.pathsPromotedToGPU, 1)
        for quad in scene.layers.flatMap(\.quads) {
            assertClip(quad, shape: anchor, radii: corners, scale: 1.5)
            XCTAssertEqual(quad.contentMask.bounds, Rect(x: 0, y: 6, width: 150, height: 144))
        }
        var stroke = Path()
        stroke.moveTo(Point(x: 10, y: 10))
        stroke.lineTo(Point(x: 60, y: 10))
        stroke.lineTo(Point(x: 90, y: 40))
        ScenePainter.emit(
            path: pathWithClip(stroke, stroke: true), into: &scene, layerIndex: 1, displayScale: 1.5,
            surfaceSize: Size(width: 150, height: 150))
        XCTAssertEqual(scene.layers[1].quads.count, 2)
        assertClip(try XCTUnwrap(scene.layers[1].paths.first), shape: anchor, radii: corners, scale: 1.5)
    }

    func testNilPathRejectionUsesCurrentTargetOnlyAfterPromotionDecision() async throws {
        var rectangle = Path()
        rectangle.addRect(Rect(x: -10, y: -10, width: 120, height: 120))
        var path = PathPrimitive(elements: rectangle.elements, bounds: rectangle.boundingRect, fillColor: .white)
        let plain = try XCTUnwrap(PathToQuadTessellator.tessellateMixed(path))
        path.clipCornerRadiusTopLeft = 40
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(path), "Without a target, retain the path's target clip")
        let promoted = try XCTUnwrap(PathToQuadTessellator.tessellateMixed(path, surfaceSize: anchor.size))
        XCTAssertEqual(promoted.quads.count, plain.quads.count)
        let quad = try XCTUnwrap(promoted.quads.first)
        XCTAssertEqual(quad.x, plain.quads[0].x)
        XCTAssertEqual(quad.width, plain.quads[0].width)
        XCTAssertEqual(quad.contentMask.bounds, anchor)
        XCTAssertNil(quad.clipShapeBounds, "An absent S still falls back to current target R")
        XCTAssertEqual(quad.clipCornerRadiusTopLeft, 40)
        var legacy = path
        legacy.clipCornerRadiusTopLeft = 0
        legacy.clipCornerRadius = 9
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(legacy))
        let uniform = try XCTUnwrap(
            PathToQuadTessellator.tessellateMixed(legacy, surfaceSize: anchor.size)?.quads.first)
        XCTAssertEqual(uniform.clipCornerRadius, 9)
        XCTAssertEqual(
            [
                uniform.clipCornerRadiusTopLeft, uniform.clipCornerRadiusTopRight,
                uniform.clipCornerRadiusBottomRight, uniform.clipCornerRadiusBottomLeft,
            ], [9, 9, 9, 9])
        var squareAnchor = path
        squareAnchor.clipCornerRadiusTopLeft = 0
        squareAnchor.clipShapeBounds = Rect(x: 10, y: 10, width: 80, height: 80)
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(squareAnchor))
        let anchored = try XCTUnwrap(
            PathToQuadTessellator.tessellateMixed(squareAnchor, surfaceSize: anchor.size)?.quads.first)
        XCTAssertEqual(anchored.contentMask.bounds, anchor)
        XCTAssertEqual(anchored.clipShapeBounds, squareAnchor.clipShapeBounds)
        var scene = GPUIScene(clearColor: .clear)
        ScenePainter.emit(path: path, into: &scene, layerIndex: 0, displayScale: 1.5)
        XCTAssertEqual(scene.layers.flatMap(\.paths).count, 1)
        XCTAssertNil(scene.layers.flatMap(\.paths).first?.clipBounds)
        var withTarget = GPUIScene(clearColor: .clear)
        ScenePainter.emit(
            path: path, into: &withTarget, layerIndex: 0, displayScale: 1.5,
            surfaceSize: Size(width: 150, height: 150))
        let device = try XCTUnwrap(withTarget.layers.flatMap(\.quads).first)
        XCTAssertEqual(device.contentMask.bounds, Rect(x: 0, y: 0, width: 150, height: 150))
        XCTAssertEqual(device.clipCornerRadiusTopLeft, 60)
    }

    func testPromotedTypedAnchorUnderflowCannotBecomeAbsent() async throws {
        var rectangle = Path()
        rectangle.addRect(anchor)
        var path = pathWithClip(rectangle)
        path.clipShapeBounds = Rect(x: 0, y: 0, width: 1e-100, height: 1e-100)
        let quad = try XCTUnwrap(PathToQuadTessellator.tessellateMixed(path)?.quads.first)
        XCTAssertNotNil(quad.clipShapeBounds)
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad)
        XCTAssertEqual(scene.primitiveCount, 0, "An explicit collapsed Float anchor is rejected, never replaced by R")

        // A positive Double radius selects C even when Float conversion loses
        // it. The resulting square limit must not revive the legacy scalar.
        let tinyCorners: [[Double]] = [
            [1e-100, 0, 0, 0],
            [-4, 1e-100, .nan, .infinity],
            [.nan, -.infinity, 1e-100, -7],
            [-3, .infinity, .nan, 1e-100],
        ]
        let rejectionRects: [Rect?] = [anchor, nil]
        func pixelAtOne(_ bitmap: BitmapSurface) -> [UInt8] {
            let offset = Int(bitmap.bytesPerRow) + 4
            return Array(bitmap.pixels[offset..<(offset + 4)])
        }
        for clipBounds in rejectionRects {
            for radii in tinyCorners {
                var tiny = PathPrimitive(
                    elements: rectangle.elements, bounds: anchor, fillColor: .white,
                    clipBounds: clipBounds, clipCornerRadius: 20)
                tiny.clipCornerRadiusTopLeft = radii[0]
                tiny.clipCornerRadiusTopRight = radii[1]
                tiny.clipCornerRadiusBottomRight = radii[2]
                tiny.clipCornerRadiusBottomLeft = radii[3]
                tiny.clipShapeBounds = anchor
                var cpuScene = GPUIScene(clearColor: .clear)
                cpuScene.addPath(tiny, toLayer: 0)
                let admitted = try XCTUnwrap(cpuScene.layers.flatMap(\.paths).first)
                XCTAssertEqual(admitted.clipCornerRadius, 20)
                XCTAssertTrue(
                    [
                        admitted.clipCornerRadiusTopLeft, admitted.clipCornerRadiusTopRight,
                        admitted.clipCornerRadiusBottomRight, admitted.clipCornerRadiusBottomLeft,
                    ]
                    .contains { $0.isFinite && $0 > 0 })
                if clipBounds == nil {
                    XCTAssertNil(PathToQuadTessellator.tessellateMixed(tiny))
                }
                let promoted = try XCTUnwrap(
                    PathToQuadTessellator.tessellateMixed(tiny, surfaceSize: anchor.size))
                XCTAssertNil(promoted.residualPath)
                XCTAssertEqual(promoted.quads.count, 1)
                var promotedScene = GPUIScene(clearColor: .clear)
                for quad in promoted.quads {
                    XCTAssertEqual(quad.contentMask.bounds, anchor)
                    XCTAssertEqual(quad.clipCornerRadius, 0)
                    XCTAssertEqual(
                        [
                            quad.clipCornerRadiusTopLeft, quad.clipCornerRadiusTopRight,
                            quad.clipCornerRadiusBottomRight, quad.clipCornerRadiusBottomLeft,
                        ], [0, 0, 0, 0])
                    promotedScene.addQuad(quad)
                }
                let cpuPixel = pixelAtOne(raster(cpuScene))
                let promotedPixel = pixelAtOne(raster(promotedScene))
                XCTAssertEqual(cpuPixel, [255, 255, 255, 255], "The admitted Path keeps the square limit")
                XCTAssertEqual(promotedPixel, [255, 255, 255, 255], "Tiny selected C must not become scalar 20")
                XCTAssertEqual(promotedPixel, cpuPixel)
            }
        }

        // Inactive raw fields do not select C; normal scalar fallback remains.
        var legacy = PathPrimitive(
            elements: rectangle.elements, bounds: anchor, fillColor: .white,
            clipBounds: anchor, clipCornerRadius: 20)
        legacy.clipCornerRadiusTopLeft = -1
        legacy.clipCornerRadiusTopRight = .nan
        legacy.clipCornerRadiusBottomRight = .infinity
        legacy.clipCornerRadiusBottomLeft = -.infinity
        let legacyQuad = try XCTUnwrap(PathToQuadTessellator.tessellateMixed(legacy)?.quads.first)
        XCTAssertEqual(legacyQuad.clipCornerRadius, 20)
        XCTAssertEqual(
            [
                legacyQuad.clipCornerRadiusTopLeft, legacyQuad.clipCornerRadiusTopRight,
                legacyQuad.clipCornerRadiusBottomRight, legacyQuad.clipCornerRadiusBottomLeft,
            ], [20, 20, 20, 20])
        var legacyCPUScene = GPUIScene(clearColor: .clear)
        legacyCPUScene.addPath(legacy, toLayer: 0)
        var legacyPromotedScene = GPUIScene(clearColor: .clear)
        legacyPromotedScene.addQuad(legacyQuad)
        XCTAssertEqual(pixelAtOne(raster(legacyCPUScene)), [0, 0, 0, 0])
        XCTAssertEqual(pixelAtOne(raster(legacyPromotedScene)), [0, 0, 0, 0])
    }

    private func captured(
        _ scene: GPUIScene, size: IntSize = IntSize(width: 100, height: 100),
        ranges: [Range<Int>]? = nil
    ) throws -> RetainedLazyListPaintSource {
        guard
            case .captured(let source) = RetainedLazyListPaintSource.capture(
                scene: scene, ranges: ranges ?? [0..<scene.paintRecordCount], surfaceSize: size)
        else {
            XCTFail("Expected a complete immutable source")
            throw CaptureFailure.expectedSource
        }
        return source
    }

    private enum CaptureFailure: Error { case expectedSource }

    private func removal(
        source: RetainedLazyListPaintSource, property: AnimatableProperty,
        start: Double, end: Double, clip: RuntimeClipShape? = nil
    ) -> RetainedLazyListRemovalPaint? {
        RetainedLazyListRemovalPaint(
            source: source,
            pose: RetainedLazyListPaintPose(
                opacity: 1, transform: .identity, pivot: .zero, clip: clip, displayScale: 1,
                rootOpacityIsInPrimitives: true),
            animation: RetainedRemovalTransitionAnimation(
                initialOpacity: 1, initialTransform: .identity, frame: source.bounds,
                states: [
                    property: AnimationState(
                        startValue: start, endValue: end, startTime: 0, duration: 1, easing: .linear)
                ],
                removalProperties: [property], resolvedAt: 0))
    }

    func testFrozenSquareAnchorGatePreservesSafeMovementAndRejectsLostPixels() async throws {
        var quad = QuadPrimitive(x: 10, y: 10, width: 12, height: 12)
        quad.contentMask = GPUIContentMask(bounds: anchor)
        quad.clipShapeBounds = anchor
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad)
        let full = try captured(scene)
        XCTAssertFalse(full.wasClipped)
        XCTAssertNotNil(removal(source: full, property: .transformTranslationX, start: 0, end: 10))

        quad.clipShapeBounds = Rect(x: 15, y: 10, width: 7, height: 12)
        scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad)
        let cut = try captured(scene)
        XCTAssertTrue(cut.wasClipped)
        XCTAssertNil(removal(source: cut, property: .transformTranslationX, start: 0, end: 10))

        quad.contentMask = GPUIContentMask()
        scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad)
        XCTAssertFalse(try captured(scene).wasClipped, "Packed absent R does not activate explicit S")
    }

    func testFrozenTinyCropReplaysWithoutApplyingClipAntialiasingTwice() async throws {
        let shape = Rect(x: 0, y: 0, width: 20, height: 20)
        let crop = Rect(x: 1, y: 1, width: 1, height: 1)
        let tree = croppedTree(crop: crop, shape: shape, uniformRadius: 5)
        let scene = paint(tree.root, size: shape.size)
        let source = try captured(scene, size: IntSize(width: 20, height: 20))
        XCTAssertTrue(source.wasClipped)
        let shifted = try XCTUnwrap(source.scene.layers.flatMap(\.quads).first)
        assertClip(
            shifted, shape: shape.offsetBy(dx: -source.bounds.minX, dy: -source.bounds.minY),
            radii: RetainedCornerRadii(uniform: 5))
        let clip = RuntimeClipShape(rect: crop, shapeRect: shape, uniformRadius: 5, space: .painted)
        var fade = try XCTUnwrap(removal(source: source, property: .opacity, start: 1, end: 0, clip: clip))
        var replay = GPUIScene(clearColor: .clear)
        fade.append(to: &replay, targetSize: IntSize(width: 20, height: 20), displayScale: 1)
        let image = try XCTUnwrap(replay.layers.flatMap(\.images).first)
        XCTAssertNil(image.clipShapeBounds)
        XCTAssertEqual(image.clipCornerRadius, 0)
        XCTAssertEqual(image.clipCornerRadiusTopLeft, 0)
        let original = raster(scene, size: IntSize(width: 20, height: 20))
        XCTAssertEqual(raster(replay, size: IntSize(width: 20, height: 20)).pixels, original.pixels)
        fade.advance(to: 0.5)
        var halfway = GPUIScene(clearColor: .clear)
        fade.append(to: &halfway, targetSize: IntSize(width: 20, height: 20), displayScale: 1)
        XCTAssertEqual(
            Double(alpha(raster(halfway, size: IntSize(width: 20, height: 20)), x: 1, y: 1)),
            Double(alpha(original, x: 1, y: 1)) * 0.5, accuracy: 1.5)
    }

    func testFrozenSquareAnchorGateIsRecognizedByEveryPrimitiveFamily() async throws {
        let bytes = Data(repeating: UInt8(255), count: 4)
        let atlas = GlyphAtlasSnapshot(width: 1, height: 1, pixels: bytes, contentVersion: 1, update: .full)
        var scene = GPUIScene(clearColor: .clear, glyphAtlas: atlas, pixelGlyphAtlas: atlas)
        let crop = Rect(x: 15, y: 10, width: 7, height: 12)
        var quad = QuadPrimitive(x: 10, y: 10, width: 12, height: 12)
        quad.contentMask = GPUIContentMask(bounds: anchor)
        quad.clipShapeBounds = crop
        scene.addQuad(quad)
        var glyph = GlyphPrimitive(screenX: 10, screenY: 10, screenW: 12, screenH: 12, atlasU1: 1, atlasV1: 1)
        glyph.contentMask = GPUIContentMask(bounds: anchor)
        glyph.clipShapeBounds = crop
        scene.addGlyph(glyph)
        scene.addPixelGlyph(glyph)
        var shadow = ShadowPrimitive(x: 10, y: 10, width: 12, height: 12)
        shadow.contentMask = GPUIContentMask(bounds: anchor)
        shadow.clipShapeBounds = crop
        scene.addShadow(shadow)
        let id = scene.registerImageResource(BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: bytes))
        var image = ImagePrimitive(screenX: 10, screenY: 10, screenW: 12, screenH: 12, textureID: id)
        image.contentMask = GPUIContentMask(bounds: anchor)
        image.clipShapeBounds = crop
        scene.addImage(image)
        var rectangle = Path()
        rectangle.addRect(Rect(x: 10, y: 10, width: 12, height: 12))
        var path = PathPrimitive(
            elements: rectangle.elements, bounds: rectangle.boundingRect,
            fillColor: .white, clipBounds: anchor)
        path.clipShapeBounds = crop
        scene.addPath(path, toLayer: 0)
        XCTAssertEqual(scene.paintRecordCount, 6)
        for index in 0..<scene.paintRecordCount {
            let source = try captured(scene, ranges: [index..<(index + 1)])
            XCTAssertEqual(source.recordCount, 1)
            XCTAssertTrue(source.wasClipped, "Square S cuts family record \(index) even though R does not")
            XCTAssertNil(removal(source: source, property: .transformTranslationX, start: 0, end: 10))
        }
    }

    func testFrozenPathWithoutRejectionRetainsOriginalTargetForRadiiAndExplicitShape() async throws {
        var rectangle = Path()
        rectangle.addRect(Rect(x: 10, y: 10, width: 12, height: 12))
        for explicitShape in [false, true] {
            var path = PathPrimitive(elements: rectangle.elements, bounds: rectangle.boundingRect, fillColor: .white)
            if explicitShape { path.clipShapeBounds = anchor } else { path.clipCornerRadiusTopRight = 7 }
            var scene = GPUIScene(clearColor: .clear)
            scene.addPath(path, toLayer: 0)
            let source = try captured(scene)
            XCTAssertTrue(source.wasClipped)
            XCTAssertEqual(source.bounds, anchor)
            XCTAssertEqual(source.size, IntSize(width: 100, height: 100))
            XCTAssertNil(source.scene.layers.flatMap(\.paths).first?.clipBounds)
            XCTAssertNil(removal(source: source, property: .transformTranslationX, start: 0, end: 10))
        }
    }
}
