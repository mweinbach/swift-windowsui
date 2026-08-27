import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public Canvas symbols are reusable drawing sources, not children in the
/// window's interaction tree. Fixed frames keep these tests independent of
/// native SwiftUI's unconstrained symbol measurement policy.
@MainActor
final class WinSwiftUICanvasSymbolTests: XCTestCase {
    private static let logicalSize = IntSize(width: 128, height: 80)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
    private static let yellow = Color(red: 1, green: 1, blue: 0, alpha: 1)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let white = Color(red: 1, green: 1, blue: 1, alpha: 1)

    private struct OpaqueTag: Hashable, CustomStringConvertible {
        let value: Int
        var description: String { "same-description" }
    }

    private struct TaggedBody: View {
        var body: some View {
            Color(red: 0, green: 0, blue: 1, alpha: 1)
                .frame(width: 8, height: 8)
                .tag("custom-body")
        }
    }

    private struct AppearanceSymbol: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            Color(
                red: colorScheme == .light ? 1 : 0,
                green: displayScale > 1 ? 1 : 0,
                blue: colorScheme == .dark ? 1 : 0,
                alpha: 1
            )
            .frame(width: 12, height: 8)
        }
    }

    private func snapshot<V: View>(_ view: V, displayScale: Double = 1) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: Self.logicalSize, displayScale: displayScale, clearColor: .clear)
    }

    private func pixelSize(displayScale: Double = 1) -> IntSize {
        IntSize(
            width: Int32(Double(Self.logicalSize.width) * displayScale),
            height: Int32(Double(Self.logicalSize.height) * displayScale))
    }

    private func raster(_ result: WinSwiftUIRenderSnapshot) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(result.scene, size: pixelSize(displayScale: result.displayScale))
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, color: Color,
        tolerance: Float = 3 / 255, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
            XCTFail("Pixel (\(x), \(y)) lies outside the test surface", file: file, line: line)
            return
        }
        let premultiplied = bitmap.premultipliedAlpha()
        let offset = y * Int(premultiplied.bytesPerRow) + x * 4
        XCTAssertEqual(
            Float(premultiplied.pixels[offset + 2]) / 255, color.red * color.alpha,
            accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(
            Float(premultiplied.pixels[offset + 1]) / 255, color.green * color.alpha,
            accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(
            Float(premultiplied.pixels[offset]) / 255, color.blue * color.alpha,
            accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(
            Float(premultiplied.pixels[offset + 3]) / 255, color.alpha,
            accuracy: tolerance, file: file, line: line)
    }

    private func sourceScenes(in scene: GPUIScene) -> [GPUIScene] {
        scene.imageRenderPasses.flatMap { [$0.scene] + sourceScenes(in: $0.scene) }
    }

    private func descendants(of root: ViewNode) -> [ViewNode] {
        var nodes: [ViewNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            nodes.append(node)
            pending.append(contentsOf: node.children)
        }
        return nodes
    }

    func testMissingTagsReturnNilAndUndrawnSymbolsPaintNothing() async {
        var resolvedKnownTag = false
        let view = Canvas { context, _ in
            XCTAssertNil(context.resolveSymbol(id: "missing"))
            XCTAssertNil(context.resolveSymbol(id: "identity-only"), "View identity is not a symbol tag")
            resolvedKnownTag = context.resolveSymbol(id: "unused") != nil
        } symbols: {
            Self.blue.frame(width: 24, height: 16).tag("unused")
            Self.yellow.frame(width: 24, height: 16).id("identity-only")
        }
        .frame(width: 128, height: 80)
        let result = snapshot(view)
        XCTAssertTrue(resolvedKnownTag)
        XCTAssertNil(GraphicsContext().resolveSymbol(id: "unused"), "A standalone context has no symbol source")
        let pixels = raster(result)
        XCTAssertTrue(stride(from: 3, to: pixels.pixels.count, by: 4).allSatisfy { pixels.pixels[$0] == 0 })
        XCTAssertTrue(result.scene.validate().isEmpty)
    }

    func testTypedTagsSurviveGroupCustomBodyAndRepeatedTypeErasure() async {
        let firstTag = OpaqueTag(value: 1)
        let secondTag = OpaqueTag(value: 2)
        let view = Canvas { context, _ in
            if let first = context.resolveSymbol(id: firstTag) {
                context.draw(first, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
            } else {
                XCTFail("The first opaque tag was lost")
            }
            if let second = context.resolveSymbol(id: secondTag) {
                context.draw(second, at: CGPoint(x: 24, y: 8), anchor: .topLeading)
            } else {
                XCTFail("The second opaque tag was lost or confused with its description")
            }
            for (tag, x) in [("custom-body", 40.0), ("erased", 56.0), ("conditional", 72.0)] {
                if let symbol = context.resolveSymbol(id: tag) {
                    context.draw(symbol, at: CGPoint(x: x, y: 8), anchor: .topLeading)
                } else {
                    XCTFail("Missing symbol \(tag)")
                }
            }
        } symbols: {
            Group {
                Self.red.frame(width: 8, height: 8).tag(firstTag)
                Self.green.frame(width: 8, height: 8).tag(secondTag)
            }
            TaggedBody()
            AnyView(AnyView(Self.yellow.frame(width: 8, height: 8).tag("erased")))
            if firstTag != secondTag {
                Self.white.frame(width: 8, height: 8).tag("conditional")
            }
        }
        .frame(width: 128, height: 80)
        let pixels = raster(snapshot(view))
        assertPixel(pixels, x: 12, y: 12, color: Self.red)
        assertPixel(pixels, x: 28, y: 12, color: Self.green)
        assertPixel(pixels, x: 44, y: 12, color: Self.blue)
        assertPixel(pixels, x: 60, y: 12, color: Self.yellow)
        assertPixel(pixels, x: 76, y: 12, color: Self.white)
    }

    func testForEachUsesTypedImplicitIDsAndKeepsExplicitTagPrecedence() async {
        let view = Canvas { context, _ in
            XCTAssertNil(context.resolveSymbol(id: 1), "An explicit tag overrides the element's default tag")
            guard let implicit = context.resolveSymbol(id: 0), let explicit = context.resolveSymbol(id: 42) else {
                XCTFail("ForEach symbols must resolve both implicit IDs and explicit tags")
                return
            }
            context.draw(implicit, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
            context.draw(explicit, at: CGPoint(x: 24, y: 8), anchor: .topLeading)
        } symbols: {
            ForEach(0..<2, id: \.self) { index in
                if index == 0 {
                    Self.blue.frame(width: 8, height: 8)
                } else {
                    Self.yellow.frame(width: 8, height: 8).tag(42)
                }
            }
        }
        .frame(width: 128, height: 80)
        let pixels = raster(snapshot(view))
        assertPixel(pixels, x: 12, y: 12, color: Self.blue)
        assertPixel(pixels, x: 28, y: 12, color: Self.yellow)
    }

    func testResolvedSizeAndPointAnchorsStayInLogicalCoordinates() async {
        for scale in [1.0, 1.5] {
            var resolvedSizes: [CGSize] = []
            let view = Canvas { context, _ in
                guard let symbol = context.resolveSymbol(id: "mark") else {
                    XCTFail("Missing fixed-size symbol")
                    return
                }
                resolvedSizes.append(symbol.size)
                context.draw(symbol, at: CGPoint(x: 16, y: 16))
                context.draw(symbol, at: CGPoint(x: 32, y: 12), anchor: .topLeading)
                context.draw(symbol, at: CGPoint(x: 64, y: 20), anchor: .bottomTrailing)
                context.draw(symbol, at: CGPoint(x: 78, y: 18), anchor: UnitPoint(x: 0.25, y: 0.75))
            } symbols: {
                Self.blue.frame(width: 12, height: 8).tag("mark")
            }
            .frame(width: 128, height: 80)
            let result = snapshot(view, displayScale: scale)
            XCTAssertFalse(resolvedSizes.isEmpty)
            XCTAssertTrue(resolvedSizes.allSatisfy { $0 == CGSize(width: 12, height: 8) })
            let pixels = raster(result)
            for (x, y) in [(11, 13), (33, 13), (53, 13), (76, 13)] {
                assertPixel(pixels, x: Int(Double(x) * scale), y: Int(Double(y) * scale), color: Self.blue)
            }
            for (x, y) in [(8, 13), (30, 13), (66, 13), (73, 13)] {
                assertPixel(pixels, x: Int(Double(x) * scale), y: Int(Double(y) * scale), color: .clear)
            }
            if scale == 1 {
                let framePixels = GPUIRawSceneRasterizer.rasterize(result.frame, size: Self.logicalSize)
                let report = comparePixels(framePixels, pixels, tolerance: 2)
                XCTAssertEqual(report.matchRatio, 1, "The legacy frame fallback must place symbols at the same anchors")
            }
        }
    }

    func testResolvedSourceKeepsQuadsGlyphsImagesAndPathsForSceneRendering() async throws {
        let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 255, 0, 255]))
        let view = Canvas { context, _ in
            guard let symbol = context.resolveSymbol(id: "mixed") else {
                XCTFail("Missing composite symbol")
                return
            }
            context.draw(symbol, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
        } symbols: {
            HStack(spacing: 0) {
                Self.red.frame(width: 8, height: 16)
                Text("X").font(.system(size: 16)).foregroundStyle(Self.white).frame(width: 16, height: 16)
                Image(bitmap: bitmap).resizable().frame(width: 8, height: 8)
                Canvas { context, _ in
                    var path = SwiftWindowsCore.Path()
                    path.moveTo(Point(x: 0, y: 16))
                    path.quadraticCurveTo(control: Point(x: 0, y: 0), end: Point(x: 8, y: 0))
                    path.quadraticCurveTo(control: Point(x: 16, y: 0), end: Point(x: 16, y: 16))
                    path.close()
                    // Two contours intentionally retain an arbitrary path;
                    // a single convex contour is promoted to GPU quads.
                    path.moveTo(Point(x: 0, y: 0))
                    path.lineTo(Point(x: 2, y: 0))
                    path.lineTo(Point(x: 0, y: 2))
                    path.close()
                    context.fill(path, with: .color(Self.yellow))
                }
                .frame(width: 16, height: 16)
            }
            .frame(width: 48, height: 16)
            .tag("mixed")
        }
        .frame(width: 128, height: 80)
        let result = snapshot(view)
        XCTAssertFalse(result.scene.imageRenderPasses.isEmpty)
        XCTAssertTrue(result.scene.imageResources.isEmpty, "A symbol must not become an eager whole-view CPU bitmap")
        let sources = sourceScenes(in: result.scene)
        XCTAssertFalse(sources.flatMap(\.layers).flatMap(\.quads).isEmpty)
        XCTAssertGreaterThan(sources.flatMap(\.layers).reduce(0) { $0 + $1.glyphs.count + $1.pixelGlyphs.count }, 0)
        XCTAssertFalse(sources.flatMap(\.layers).flatMap(\.images).isEmpty)
        XCTAssertFalse(sources.flatMap(\.layers).flatMap(\.paths).isEmpty)
        XCTAssertEqual(sources.flatMap(\.imageResources).count, 1, "Only the authored image needs a bitmap binding")
        XCTAssertTrue(result.scene.validate().isEmpty)
        let pixels = raster(result)
        assertPixel(pixels, x: 12, y: 16, color: Self.red)
        assertPixel(pixels, x: 36, y: 16, color: Self.green)
        assertPixel(pixels, x: 48, y: 20, color: Self.yellow)
        let ink = (8..<24).flatMap { y in (16..<32).map { x in (x, y) } }.first { x, y in
            pixels.pixels[y * Int(pixels.bytesPerRow) + x * 4 + 3] > 250
        }
        let (glyphX, glyphY) = try XCTUnwrap(ink, "The text source must paint real glyph ink")
        assertPixel(pixels, x: glyphX, y: glyphY, color: Self.white)
    }

    func testContextCopiesAndDrawLayerKeepTheSymbolResolver() async {
        let view = Canvas { context, _ in
            var copy = context
            guard let first = copy.resolveSymbol(id: "mark") else {
                XCTFail("A context copy lost its symbol source")
                return
            }
            copy.draw(first, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
            context.drawLayer { layer in
                guard let second = layer.resolveSymbol(id: "mark") else {
                    XCTFail("drawLayer lost its inherited symbol source")
                    return
                }
                layer.opacity = 0.5
                layer.draw(second, at: CGPoint(x: 24, y: 8), anchor: .topLeading)
            }
            XCTAssertEqual(context.opacity, 1, "Layer drawing state must not leak into the parent")
            context.draw(first, at: CGPoint(x: 40, y: 8), anchor: .topLeading)
        } symbols: {
            // Opacity belongs to the completed symbol. Applying it to both
            // overlapping children would yield alpha 0.75 in the half-opacity draw.
            ZStack {
                Self.yellow.frame(width: 8, height: 8)
                Self.blue.frame(width: 8, height: 8)
            }
            .frame(width: 8, height: 8)
            .tag("mark")
        }
        .frame(width: 128, height: 80)
        let pixels = raster(snapshot(view))
        assertPixel(pixels, x: 12, y: 12, color: Self.blue)
        assertPixel(pixels, x: 28, y: 12, color: Color(red: 0, green: 0, blue: 1, alpha: 0.5))
        assertPixel(pixels, x: 44, y: 12, color: Self.blue)
    }

    func testInterleavedContextCopiesShareDrawingOrderButKeepIndependentState() async {
        let destination = CGRect(x: 8, y: 8, width: 16, height: 8)
        let view = Canvas { context, _ in
            guard let symbol = context.resolveSymbol(id: "mark") else {
                XCTFail("Missing copied-context fixture symbol")
                return
            }
            var left = context
            left.clip(to: CGRect(x: 8, y: 8, width: 8, height: 8))
            var right = context
            right.clip(to: CGRect(x: 16, y: 8, width: 8, height: 8))
            right.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 32, ty: 0))
            right.opacity = 0.5

            left.draw(symbol, in: destination)
            context.fill(CGRect(x: 8, y: 8, width: 8, height: 8), with: .color(Self.red))
            right.draw(symbol, in: destination)
            left.draw(symbol, in: destination)

            context.drawLayer { layer in
                layer.clip(to: CGRect(x: 8, y: 32, width: 8, height: 8))
                layer.translateBy(x: 0, y: 24)
                layer.opacity = 0.5
                layer.draw(symbol, in: destination)
            }
            XCTAssertEqual(context.opacity, 1)
            XCTAssertEqual(context.transform, .identity)
            context.draw(symbol, in: CGRect(x: 40, y: 32, width: 16, height: 8))
        } symbols: {
            HStack(spacing: 0) {
                Self.blue.frame(width: 8, height: 8)
                Self.yellow.frame(width: 8, height: 8)
            }
            .frame(width: 16, height: 8)
            .tag("mark")
        }
        .frame(width: 128, height: 80)
        let result = snapshot(view)
        let scenePixels = raster(result)
        let framePixels = GPUIRawSceneRasterizer.rasterize(result.frame, size: Self.logicalSize)
        for pixels in [scenePixels, framePixels] {
            // The last left-context draw must overwrite the intervening red
            // parent draw. The reflected right copy shows blue at half alpha.
            assertPixel(pixels, x: 12, y: 12, color: Self.blue)
            assertPixel(pixels, x: 20, y: 12, color: Color(red: 0, green: 0, blue: 1, alpha: 0.5))
            assertPixel(pixels, x: 12, y: 36, color: Color(red: 0, green: 0, blue: 1, alpha: 0.5))
            assertPixel(pixels, x: 20, y: 36, color: .clear)
            assertPixel(pixels, x: 44, y: 36, color: Self.blue)
            assertPixel(pixels, x: 52, y: 36, color: Self.yellow)
        }
        XCTAssertEqual(comparePixels(framePixels, scenePixels, tolerance: 3).matchRatio, 1)
    }

    func testUniformAncestorScaleKeepsCanvasCallbackSizeLogicalAndScalesSymbolsOnce() async throws {
        var callbackSizes: [CGSize] = []
        let view = ZStack(alignment: .topLeading) {
            Canvas { context, size in
                callbackSizes.append(size)
                guard let symbol = context.resolveSymbol(id: "mark") else {
                    XCTFail("Missing scaled symbol")
                    return
                }
                context.draw(
                    symbol, at: CGPoint(x: size.width / 4, y: size.height / 4), anchor: .topLeading)
                context.fill(
                    CGRect(x: size.width - 4, y: size.height - 4, width: 4, height: 4),
                    with: .color(Self.yellow))
            } symbols: {
                Self.blue.frame(width: 8, height: 8).tag("mark")
            }
            .frame(width: 40, height: 40)
            .scaleEffect(2, anchor: .topLeading)
        }
        .frame(width: 128, height: 80, alignment: .topLeading)
        let result = snapshot(view)
        XCTAssertFalse(callbackSizes.isEmpty)
        XCTAssertTrue(callbackSizes.allSatisfy { $0 == CGSize(width: 40, height: 40) })
        let symbolImage = try XCTUnwrap(result.scene.layers.flatMap(\.images).first)
        XCTAssertEqual(symbolImage.screenW, 16, accuracy: 0.001)
        XCTAssertEqual(symbolImage.screenH, 16, accuracy: 0.001)
        let scenePixels = raster(result)
        let framePixels = GPUIRawSceneRasterizer.rasterize(result.frame, size: Self.logicalSize)
        for pixels in [scenePixels, framePixels] {
            assertPixel(pixels, x: 22, y: 22, color: Self.blue)
            assertPixel(pixels, x: 34, y: 34, color: Self.blue)
            assertPixel(pixels, x: 18, y: 26, color: .clear)
            assertPixel(pixels, x: 38, y: 26, color: .clear)
            assertPixel(pixels, x: 74, y: 74, color: Self.yellow)
        }
        XCTAssertEqual(comparePixels(framePixels, scenePixels, tolerance: 3).matchRatio, 1)
    }

    func testSymbolBodiesReadTheInheritedAppearanceAndDisplayScale() async {
        let view = Canvas { context, _ in
            guard let symbol = context.resolveSymbol(id: "appearance") else {
                XCTFail("Missing appearance symbol")
                return
            }
            XCTAssertEqual(symbol.size, CGSize(width: 12, height: 8))
            context.draw(symbol, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
        } symbols: {
            AppearanceSymbol().tag("appearance")
        }
        .frame(width: 128, height: 80)
        let dark = snapshot(view)
        assertPixel(raster(dark), x: 12, y: 12, color: Self.blue)
        let light = snapshot(view.environment(\.colorScheme, .light), displayScale: 1.5)
        assertPixel(raster(light), x: 18, y: 18, color: Self.yellow)
    }

    func testSymbolStateInvalidatesAndUpdatesAReconciledCanvasNode() async throws {
        let expanded = State(wrappedValue: false)
        var invalidations = 0
        let view = Canvas { context, _ in
            guard let symbol = context.resolveSymbol(id: "state") else {
                XCTFail("Missing state symbol")
                return
            }
            context.draw(symbol, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
        } symbols: {
            (expanded.wrappedValue ? Self.yellow : Self.blue)
                .frame(width: expanded.wrappedValue ? 16 : 8, height: 8)
                .tag("state")
        }
        .frame(width: 128, height: 80)
        let runtime = RetainedViewRuntime(clearColor: .clear)
        runtime.setRootSize(Self.logicalSize)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 128, height: 80) },
            invalidateHandler: { invalidations += 1 })
        host.setComponents { [view.makeComponent(context: context)] }
        let firstNode = try XCTUnwrap(runtime.root.children.first)
        let first = GPUIRawSceneRasterizer.rasterize(runtime.renderScene(), size: Self.logicalSize)
        assertPixel(first, x: 12, y: 12, color: Self.blue)
        assertPixel(first, x: 20, y: 12, color: .clear)

        expanded.wrappedValue = true
        XCTAssertGreaterThan(invalidations, 0, "The symbol's state read must retain the enclosing invalidation context")
        host.reload()
        XCTAssertTrue(runtime.root.children.first === firstNode, "The fixture must reconcile the existing Canvas")
        let second = GPUIRawSceneRasterizer.rasterize(runtime.renderScene(), size: Self.logicalSize)
        assertPixel(second, x: 12, y: 12, color: Self.yellow)
        assertPixel(second, x: 20, y: 12, color: Self.yellow)
    }

    func testButtonSymbolsDoNotJoinTheParentFocusHitTestOrAccessibilityTree() async {
        var activations = 0
        let view = Canvas { context, _ in
            guard let symbol = context.resolveSymbol(id: "button") else {
                XCTFail("Missing button symbol")
                return
            }
            context.draw(symbol, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
        } symbols: {
            Button(action: { activations += 1 }) {
                Self.blue.frame(width: 24, height: 16)
            }
            .buttonStyle(.plain)
            .focusable(true)
            .accessibilityIdentifier("symbol-only-button")
            .tag("button")
        }
        .frame(width: 128, height: 80)
        let result = snapshot(view)
        assertPixel(raster(result), x: 20, y: 16, color: Self.blue)
        XCTAssertFalse(
            descendants(of: result.runtime.root).contains { $0.accessibilityIdentifier == "symbol-only-button" })
        result.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertNil(result.runtime.focusedNode)
        result.runtime.pointerDown(at: Point(x: 20, y: 16))
        result.runtime.pointerUp(at: Point(x: 20, y: 16))
        XCTAssertEqual(activations, 0, "A symbol contributes drawing operations, not a live button")
    }

    func testPublicSymbolCompositionMatchesWARPWithAffineTransformsAndFractionalScale() async throws {
        let view = Canvas { context, _ in
            guard let symbol = context.resolveSymbol(id: "two-colors") else {
                XCTFail("Missing affine fixture symbol")
                return
            }
            context.draw(symbol, at: CGPoint(x: 16, y: 16), anchor: .topLeading)
            context.fill(CGRect(x: 24, y: 12, width: 8, height: 24), with: .color(Self.yellow))
            context.draw(symbol, in: CGRect(x: 32, y: 20, width: 24, height: 12))
            context.drawLayer { layer in
                layer.translateBy(x: 96, y: 12)
                layer.rotate(by: .degrees(90))
                layer.draw(symbol, at: .zero, anchor: .topLeading)
            }
            context.drawLayer { layer in
                layer.translateBy(x: 76, y: 52)
                layer.scaleBy(x: -1, y: 1)
                layer.draw(symbol, at: .zero, anchor: .topLeading)
            }
            context.drawLayer { layer in
                layer.concatenate(CGAffineTransform(a: 1, b: 0, c: 0.5, d: 1, tx: 8, ty: 56))
                layer.draw(symbol, at: .zero, anchor: .topLeading)
            }
            context.drawLayer { layer in
                layer.opacity = 0.5
                layer.clip(to: CGRect(x: 104, y: 52, width: 12, height: 12))
                layer.draw(symbol, at: CGPoint(x: 104, y: 52), anchor: .topLeading)
            }
        } symbols: {
            HStack(spacing: 0) {
                Self.blue.frame(width: 12, height: 12)
                Self.yellow.frame(width: 12, height: 12)
            }
            .frame(width: 24, height: 12)
            .tag("two-colors")
        }
        .frame(width: 128, height: 80)

        for scale in [1.0, 1.5] {
            let result = snapshot(view, displayScale: scale)
            XCTAssertTrue(result.scene.validate().isEmpty)
            XCTAssertFalse(result.scene.imageRenderPasses.isEmpty)
            XCTAssertTrue(result.scene.imageResources.isEmpty)
            let cpu = raster(result).premultipliedAlpha()
            let gpu = try WARPBatchRenderer.render(result.scene, size: pixelSize(displayScale: scale))
            let report = comparePixels(gpu, cpu, tolerance: 4)
            XCTAssertGreaterThanOrEqual(
                report.matchRatio, 0.995,
                "Canvas symbol parity at \(scale)x: ratio \(report.matchRatio), max delta \(report.maxChannelDelta), first \(String(describing: report.firstFailure))"
            )
            // Interior samples establish actual drawing and ordering, so
            // two empty or uniformly wrong renderers cannot satisfy parity.
            for (x, y, color) in [
                (20, 20, Self.blue), (26, 18, Self.yellow),
                (36, 24, Self.blue), (50, 24, Self.yellow),
                (68, 58, Self.blue), (56, 58, Self.yellow),
                (88, 18, Self.blue), (88, 30, Self.yellow),
                (18, 62, Self.blue), (30, 62, Self.yellow),
            ] {
                assertPixel(cpu, x: Int(Double(x) * scale), y: Int(Double(y) * scale), color: color)
                assertPixel(gpu, x: Int(Double(x) * scale), y: Int(Double(y) * scale), color: color)
            }
            let halfBlue = Color(red: 0, green: 0, blue: 1, alpha: 0.5)
            assertPixel(cpu, x: Int(110 * scale), y: Int(58 * scale), color: halfBlue)
            assertPixel(gpu, x: Int(110 * scale), y: Int(58 * scale), color: halfBlue)
            assertPixel(cpu, x: Int(122 * scale), y: Int(58 * scale), color: .clear)
            assertPixel(gpu, x: Int(122 * scale), y: Int(58 * scale), color: .clear)
            assertPixel(cpu, x: Int(9 * scale), y: Int(66 * scale), color: .clear)
            assertPixel(gpu, x: Int(9 * scale), y: Int(66 * scale), color: .clear)
        }
    }
}
