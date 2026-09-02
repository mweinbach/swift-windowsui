import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public circular clip transport. Continuous corners, exact intersections of
/// multiple rounded shapes, and trim/inset clip-path geometry are not asserted.
@MainActor
final class WinSwiftUIOriginalAnchorClipTests: XCTestCase {
    private static let size = Size(width: 120, height: 80)
    private static let bounds = Rect(origin: .zero, size: size)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)

    func testPublicClipPreservesAllFourPhysicalRadiiAndPixels() async throws {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 28, bottomLeadingRadius: 0,
            bottomTrailingRadius: 12, topTrailingRadius: 0, style: .circular)
        let fixture = makeFixture(Rectangle().fill(Self.red).clipShape(shape))
        let expected = RetainedCornerRadii(topLeft: 28, bottomRight: 12)

        XCTAssertEqual(fixture.node.cornerRadius, 28)
        XCTAssertEqual(fixture.node.cornerRadii, expected)
        XCTAssertTrue(fixture.node.clipsToBounds)
        let quad = try redQuad(in: fixture.scene)
        assertClip(quad, radii: expected, anchor: Self.bounds)
        try assertPixel(fixture.scene, x: 2, y: 2, painted: false)
        try assertPixel(fixture.scene, x: 117, y: 2, painted: true)
        try assertPixel(fixture.scene, x: 117, y: 77, painted: false)
        try assertPixel(fixture.scene, x: 2, y: 77, painted: true)
        try assertPixel(fixture.scene, x: 60, y: 40, painted: true)
    }

    func testOneDoubleErasedShapeResolvesEachInheritedDirection() async throws {
        let shape = AnyShape(AnyShape(UnevenRoundedRectangle(topLeadingRadius: 24, style: .circular)))
        for direction in [LayoutDirection.leftToRight, .rightToLeft, .leftToRight] {
            let fixture = makeFixture(
                Rectangle().fill(Self.red).clipShape(shape).environment(\.layoutDirection, direction))
            let rtl = direction == .rightToLeft
            let expected = RetainedCornerRadii(topLeft: rtl ? 0 : 24, topRight: rtl ? 24 : 0)
            XCTAssertEqual(fixture.node.cornerRadii, expected)
            assertClip(try redQuad(in: fixture.scene), radii: expected, anchor: Self.bounds)
            try assertPixel(fixture.scene, x: 2, y: 2, painted: rtl)
            try assertPixel(fixture.scene, x: 117, y: 2, painted: !rtl)
        }
    }

    func testLiveRebuildUpdatesClipGeometryOnTheSameWrapper() async throws {
        let runtime = RetainedViewRuntime(
            clearColor: .clear, root: ViewNode(frame: Self.bounds, isHitTestVisible: false))
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Self.size }, invalidateHandler: {})
        var direction = LayoutDirection.leftToRight
        var radii = RectangleCornerRadii(topLeading: 24)
        host.setComponents {
            [
                Rectangle().fill(Self.red).frame(width: 120, height: 80)
                    .clipShape(AnyShape(AnyShape(UnevenRoundedRectangle(cornerRadii: radii, style: .circular))))
                    .environment(\.layoutDirection, direction)
                    .makeComponent(context: context)
            ]
        }
        let first = runtime.renderScene()
        let owner = try XCTUnwrap(runtime.root.children.first)
        XCTAssertTrue(owner.clipsToBounds)
        try assertPixel(first, x: 2, y: 2, painted: false)
        try assertPixel(first, x: 117, y: 2, painted: true)

        direction = .rightToLeft
        radii = RectangleCornerRadii(topLeading: 30)
        host.reload()
        let second = runtime.renderScene()
        XCTAssertTrue(runtime.root.children.first === owner)
        XCTAssertEqual(owner.cornerRadii, RetainedCornerRadii(topRight: 30))
        assertClip(try redQuad(in: second), radii: RetainedCornerRadii(topRight: 30), anchor: Self.bounds)
        try assertPixel(second, x: 2, y: 2, painted: true)
        try assertPixel(second, x: 117, y: 2, painted: false)

        direction = .leftToRight
        radii = RectangleCornerRadii(bottomTrailing: 26)
        host.reload()
        let third = runtime.renderScene()
        XCTAssertTrue(runtime.root.children.first === owner)
        assertClip(try redQuad(in: third), radii: RetainedCornerRadii(bottomRight: 26), anchor: Self.bounds)
        try assertPixel(third, x: 117, y: 2, painted: true)
        try assertPixel(third, x: 117, y: 77, painted: false)
    }

    func testVisualClipAndContentShapeKeepIndependentGeometry() async throws {
        var actions = 0
        let fixture = makeFixture(
            Rectangle().fill(Self.red)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, style: .circular))
                .contentShape(UnevenRoundedRectangle(bottomTrailingRadius: 24, style: .circular))
                .onTapGesture { actions += 1 })
        XCTAssertEqual(fixture.node.cornerRadii, RetainedCornerRadii(topLeft: 24))
        XCTAssertEqual(
            fixture.node.contentShapes,
            [
                RetainedContentShape(
                    kinds: .interaction, style: .unevenRoundedRectangle(RetainedCornerRadii(bottomRight: 24)))
            ])
        try assertPixel(fixture.scene, x: 117, y: 77, painted: true)
        fixture.runtime.pointerDown(at: Point(x: 118, y: 78))
        fixture.runtime.pointerUp(at: Point(x: 118, y: 78))
        XCTAssertEqual(actions, 0)
        fixture.runtime.pointerDown(at: Point(x: 2, y: 78))
        fixture.runtime.pointerUp(at: Point(x: 2, y: 78))
        XCTAssertEqual(actions, 1)
    }

    func testAllShapedDecorationOverloadsResolveLogicalCorners() async throws {
        let shape = AnyShape(AnyShape(UnevenRoundedRectangle(topLeadingRadius: 24, style: .circular)))
        let views = [
            AnyView(Rectangle().fill(Color.clear).background(Self.red, in: shape)),
            AnyView(Rectangle().fill(Color.clear).background(in: shape).backgroundStyle(Self.red)),
            AnyView(Rectangle().fill(Color.clear).overlay(Self.red, in: shape)),
        ]
        for view in views {
            let fixture = makeFixture(view.environment(\.layoutDirection, .rightToLeft))
            let decoration = try XCTUnwrap(firstNode(in: fixture.node) { $0.backgroundColor == Self.red })
            XCTAssertEqual(decoration.cornerRadii, RetainedCornerRadii(topRight: 24))
            XCTAssertTrue(decoration.clipsToBounds)
            let quad = try redQuad(in: fixture.scene)
            XCTAssertEqual(quad.cornerRadiusTopLeft, 0)
            XCTAssertEqual(quad.cornerRadiusTopRight, 24)
            // Its body owns the rounding; its own clip must not apply it again.
            XCTAssertEqual(quad.clipCornerRadiusTopLeft, 0)
            XCTAssertEqual(quad.clipCornerRadiusTopRight, 0)
            try assertPixel(fixture.scene, x: 2, y: 2, painted: true)
            try assertPixel(fixture.scene, x: 117, y: 2, painted: false)
        }
    }

    func testLegacyScalarElevenCoexistsWithFullInsetTrimClipDescriptor() async throws {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 8, bottomLeadingRadius: 10,
            bottomTrailingRadius: 12, topTrailingRadius: 14, style: .circular)
        let wrapped = AnyShape(AnyShape(shape.inset(by: 3).trim(from: 0.25, to: 0.75)))
        XCTAssertEqual(wrapped.retainedClipShapeStyle, .roundedRectangle(11))
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let fixture = makeFixture(
                Rectangle().fill(Self.red).clipShape(wrapped).environment(\.layoutDirection, direction))
            let rtl = direction == .rightToLeft
            let expected =
                rtl
                ? RetainedCornerRadii(topLeft: 11, topRight: 5, bottomRight: 7, bottomLeft: 9)
                : RetainedCornerRadii(topLeft: 5, topRight: 11, bottomRight: 9, bottomLeft: 7)
            XCTAssertEqual(fixture.node.cornerRadius, 11)
            XCTAssertEqual(fixture.node.cornerRadii, expected)
            assertClip(try redQuad(in: fixture.scene), radii: expected, anchor: Self.bounds)
            try assertPixel(fixture.scene, x: 2, y: 2, painted: !rtl)
            try assertPixel(fixture.scene, x: 117, y: 2, painted: rtl)
        }
        // These are circular descriptor checks, not partial-path clipping or
        // point-inset bounds qualification. The scalar remains a projection.
    }

    func testEqualFiniteRadiiMatchUniformClipPixelsAndOrder() async {
        for radius in [0.0, 0.125, 3.25, 20, 1000] {
            let uneven = UnevenRoundedRectangle(
                topLeadingRadius: radius, bottomLeadingRadius: radius,
                bottomTrailingRadius: radius, topTrailingRadius: radius, style: .circular)
            let a = makeFixture(Rectangle().fill(Self.red).clipShape(uneven))
            let b = makeFixture(
                Rectangle().fill(Self.red).clipShape(RoundedRectangle(cornerRadius: radius, style: .circular)))
            XCTAssertEqual(Array(a.scene.presentationOrder()), Array(b.scene.presentationOrder()))
            XCTAssertEqual(raster(a.scene).pixels, raster(b.scene).pixels)
        }
    }

    func testFractionalDisplayScaleScalesOriginalAnchorAndRadiiOnce() async throws {
        let expected = RetainedCornerRadii(topLeft: 8, topRight: 16, bottomRight: 20, bottomLeft: 4)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 8, bottomLeadingRadius: 4,
            bottomTrailingRadius: 20, topTrailingRadius: 16, style: .circular)
        for scale in [1.0, 1.25, 1.5, 2.0] {
            let fixture = makeFixture(Rectangle().fill(Self.red).clipShape(shape), scale: scale)
            let quad = try redQuad(in: fixture.scene)
            assertClip(
                quad,
                radii: RetainedCornerRadii(
                    topLeft: expected.topLeft * scale, topRight: expected.topRight * scale,
                    bottomRight: expected.bottomRight * scale, bottomLeft: expected.bottomLeft * scale),
                anchor: Rect(x: 0, y: 0, width: 120 * scale, height: 80 * scale))
            XCTAssertEqual(quad.clipWidth, Float(120 * scale))
            XCTAssertEqual(quad.clipHeight, Float(80 * scale))
            let pixels = GPUIRawSceneRasterizer.rasterize(
                fixture.scene, size: IntSize(width: Int32(120 * scale), height: Int32(80 * scale)))
            XCTAssertEqual(try XCTUnwrap(pixels.colorAt(x: Int(60 * scale), y: Int(40 * scale))).red, 1)
        }
    }

    func testFillFlagsAndChildPresentationOrderAreUnchanged() async throws {
        let content = ZStack {
            Rectangle().fill(Self.red)
            Rectangle().fill(Self.green).frame(width: 20, height: 20)
        }
        let plain = makeFixture(content)
        let clipped = makeFixture(
            content.clipShape(
                UnevenRoundedRectangle(topLeadingRadius: 24, style: .circular),
                style: FillStyle(eoFill: true, antialiased: false)))
        XCTAssertEqual(clipped.node.clipFillStyle, RetainedClipFillStyle(eoFill: true, antialiased: false))
        XCTAssertEqual(Array(clipped.scene.presentationOrder()), Array(plain.scene.presentationOrder()))
        let before = plain.scene.layers.flatMap(\.quads)
        let after = clipped.scene.layers.flatMap(\.quads)
        XCTAssertEqual(before.count, 2)
        XCTAssertEqual(after.count, before.count)
        for (a, b) in zip(before, after) {
            XCTAssertEqual(a.x, b.x)
            XCTAssertEqual(a.y, b.y)
            XCTAssertEqual(a.width, b.width)
            XCTAssertEqual(a.height, b.height)
            XCTAssertEqual(a.startR, b.startR)
            XCTAssertEqual(a.startG, b.startG)
        }
        XCTAssertEqual(try XCTUnwrap(raster(clipped.scene).colorAt(x: 60, y: 40)).green, 1)
    }

    func testClipDescriptorDoesNotRetainOrInvokeAnAuthoredPath() async {
        let counts = PathCounts()
        let weakProbe = WeakPathProbe()
        let view = callbackClipView(counts: counts, weakProbe: weakProbe)
        XCTAssertNil(weakProbe.value)
        XCTAssertEqual(counts.pathCalls, 0)
        let fixture = makeFixture(view)
        XCTAssertTrue(fixture.node.clipsToBounds)
        _ = fixture.runtime.renderScene()
        fixture.runtime.displayScale = 1.25
        _ = fixture.runtime.renderScene()
        XCTAssertEqual(counts.pathCalls, 0)
        XCTAssertNil(weakProbe.value)
    }

    func testUniformRuntimeExportKeepsOriginalRadiusAfterCornerRemoval() async throws {
        let anchor = Rect(x: 0, y: 0, width: 20, height: 20)
        let crop = Rect(x: 1, y: 1, width: 1, height: 1)
        let original = RuntimeClipShape(rect: anchor, uniformRadius: 5, space: .painted)
        let narrowed = try XCTUnwrap(original.intersecting(crop, radii: nil, uniformRadius: 0, space: .painted))
        XCTAssertEqual(narrowed.rect, crop)
        XCTAssertEqual(narrowed.shapeRect, anchor)
        XCTAssertNil(narrowed.radii)
        XCTAssertEqual(narrowed.uniformRadius, 5)
        XCTAssertEqual(narrowed.resolvedCornerRadius(forQuadRect: crop), 0)
        XCTAssertEqual(narrowed.sceneCornerRadii, RetainedCornerRadii(uniform: 5))
    }

    func testThinSquareCropPreservesEveryOriginalCornerValue() async throws {
        let anchor = Rect(x: 0, y: 0, width: 100, height: 100)
        let radii = RetainedCornerRadii(topLeft: 40, topRight: 4, bottomRight: 8, bottomLeft: 0)
        let original = RuntimeClipShape(rect: anchor, radii: radii, space: .painted)
        let crop = Rect(x: 0, y: 0, width: 100, height: 4)
        let narrowed = try XCTUnwrap(original.intersecting(crop, radii: nil, uniformRadius: 0, space: .painted))
        XCTAssertEqual(narrowed.rect, crop)
        XCTAssertEqual(narrowed.shapeRect, anchor)
        XCTAssertEqual(narrowed.sceneCornerRadii, radii)
        XCTAssertEqual(narrowed.rotation, 0)
        XCTAssertEqual(narrowed.space, .painted)
    }

    func testNestedRoundedSelectionAndRectangleContainsPolicyStayUnchanged() async throws {
        let outer = RuntimeClipShape(
            rect: Rect(x: 0, y: 0, width: 100, height: 100),
            radii: RetainedCornerRadii(topLeft: 40), space: .painted)
        let innerBounds = Rect(x: 10, y: 15, width: 50, height: 40)
        let innerRadii = RetainedCornerRadii(bottomRight: 7)
        let inner = try XCTUnwrap(
            outer.intersecting(innerBounds, radii: innerRadii, uniformRadius: 0, space: .painted))
        XCTAssertEqual(inner.rect, innerBounds)
        XCTAssertEqual(inner.shapeRect, innerBounds)
        XCTAssertEqual(inner.sceneCornerRadii, innerRadii)
        // contains remains rectangular at zero rotation; this visual transport
        // does not claim a rounded input predicate or two-mask intersection.
        XCTAssertTrue(inner.contains(Point(x: 59, y: 54)))
        XCTAssertFalse(inner.contains(Point(x: 61, y: 54)))
    }

    func testRuntimeRadiusFlooringPrecedesOriginalGeometryExport() async {
        let clip = RuntimeClipShape(
            rect: Self.bounds,
            radii: RetainedCornerRadii(topLeft: .nan, topRight: .infinity, bottomRight: -4, bottomLeft: 9),
            uniformRadius: 100, space: .painted)
        XCTAssertEqual(clip.sceneCornerRadii, RetainedCornerRadii(bottomLeft: 9))
        XCTAssertEqual(clip.uniformRadius, 9)
        let invalidUniform = RuntimeClipShape(rect: Self.bounds, uniformRadius: .infinity, space: .painted)
        XCTAssertEqual(invalidUniform.sceneCornerRadii, RetainedCornerRadii(uniform: 0))
        XCTAssertNil(invalidUniform.radii)
    }

    private struct Fixture {
        let runtime: RetainedViewRuntime
        let node: ViewNode
        let scene: GPUIScene
    }

    private func makeFixture<V: View>(_ view: V, scale: Double = 1) -> Fixture {
        let root = ViewNode(frame: Self.bounds, isHitTestVisible: false)
        let runtime = RetainedViewRuntime(clearColor: .clear, root: root)
        runtime.displayScale = scale
        let context = ViewBuildContext(canvasSizeProvider: { Self.size }, invalidateHandler: {})
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        node.frame = Self.bounds
        root.addChild(node)
        return Fixture(runtime: runtime, node: node, scene: runtime.renderScene())
    }

    private func redQuad(in scene: GPUIScene, file: StaticString = #filePath, line: UInt = #line) throws
        -> QuadPrimitive
    {
        try XCTUnwrap(
            scene.layers.flatMap(\.quads).first { $0.startR == 1 && $0.startG == 0 && $0.startA == 1 },
            file: file, line: line)
    }

    private func assertClip(
        _ quad: QuadPrimitive, radii: RetainedCornerRadii, anchor: Rect,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(quad.clipShapeBounds, anchor, file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusTopLeft, Float(radii.topLeft), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusTopRight, Float(radii.topRight), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusBottomRight, Float(radii.bottomRight), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusBottomLeft, Float(radii.bottomLeft), file: file, line: line)
    }

    private func raster(_ scene: GPUIScene) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 120, height: 80))
    }

    private func assertPixel(
        _ scene: GPUIScene, x: Int, y: Int, painted: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let color = try XCTUnwrap(raster(scene).colorAt(x: x, y: y), file: file, line: line)
        XCTAssertEqual(color.red, painted ? 1 : 0, accuracy: 1.0 / 255, file: file, line: line)
        XCTAssertEqual(color.green, 0, accuracy: 1.0 / 255, file: file, line: line)
        XCTAssertEqual(color.blue, 0, accuracy: 1.0 / 255, file: file, line: line)
        XCTAssertEqual(color.alpha, painted ? 1 : 0, accuracy: 1.0 / 255, file: file, line: line)
    }

    private func firstNode(in node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let result = firstNode(in: child, where: predicate) { return result }
        }
        return nil
    }

    private final class PathCounts { var pathCalls = 0 }
    private final class PathProbe {
        let counts: PathCounts
        init(counts: PathCounts) { self.counts = counts }
    }
    private final class WeakPathProbe { weak var value: PathProbe? }
    private struct CallbackShape: Shape {
        let probe: PathProbe
        func path(in rect: Rect) -> Path {
            probe.counts.pathCalls += 1
            return Path(rect)
        }
    }
    private func callbackClipView(counts: PathCounts, weakProbe: WeakPathProbe) -> AnyView {
        let probe = PathProbe(counts: counts)
        weakProbe.value = probe
        let shape = AnyShape(AnyShape(CallbackShape(probe: probe)))
        return AnyView(Rectangle().fill(Self.red).clipShape(shape))
    }
}
