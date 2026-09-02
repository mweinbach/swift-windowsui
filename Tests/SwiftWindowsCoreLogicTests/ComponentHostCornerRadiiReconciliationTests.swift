import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class ComponentHostCornerRadiiReconciliationTests: XCTestCase {
    private static let bounds = Rect(x: 0, y: 0, width: 80, height: 60)
    private static let pixelSize = IntSize(width: 80, height: 60)

    func testEqualMaximumRadiusStillCopiesEachCornerOnTheRetainedNode() async throws {
        let firstRadii = RetainedCornerRadii(topLeft: 20)
        let nextRadii = RetainedCornerRadii(topRight: 20)
        XCTAssertEqual(firstRadii.maxRadius, nextRadii.maxRadius)
        let fixture = makeFixture(radii: firstRadii, uniformRadius: 20)
        let first = fixture.runtime.renderScene()
        let owner = try XCTUnwrap(fixture.runtime.root.children.first)
        let leaf = try XCTUnwrap(owner.children.first)
        XCTAssertEqual(owner.cornerRadius, 20)
        XCTAssertEqual(owner.cornerRadii, firstRadii)
        try assertClip(first, radii: firstRadii)
        let firstPixels = raster(first)
        try assertPixel(firstPixels, x: 2, y: 2, painted: false)
        try assertPixel(firstPixels, x: 77, y: 2, painted: true)
        XCTAssertEqual(raster(fixture.runtime.renderScene()).pixels, firstPixels.pixels)

        fixture.radii.value = nextRadii
        fixture.host.reload()
        let changed = fixture.runtime.renderScene()

        XCTAssertTrue(fixture.runtime.root.children.first === owner)
        XCTAssertTrue(owner.children.first === leaf)
        XCTAssertEqual(owner.cornerRadius, 20, "The scalar radius did not change")
        XCTAssertEqual(owner.cornerRadii, nextRadii)
        try assertClip(changed, radii: nextRadii)
        let changedPixels = raster(changed)
        try assertPixel(changedPixels, x: 2, y: 2, painted: true)
        try assertPixel(changedPixels, x: 77, y: 2, painted: false)
        try assertPixel(changedPixels, x: 77, y: 57, painted: true)
    }

    func testClearingPerCornerRadiiRestoresTheUnchangedUniformRadius() async throws {
        let firstRadii = RetainedCornerRadii(topRight: 20)
        let fixture = makeFixture(radii: firstRadii, uniformRadius: 4)
        let first = fixture.runtime.renderScene()
        let owner = try XCTUnwrap(fixture.runtime.root.children.first)
        XCTAssertEqual(owner.cornerRadius, 4)
        XCTAssertEqual(owner.cornerRadii, firstRadii)
        try assertClip(first, radii: firstRadii)
        let firstPixels = raster(first)
        try assertPixel(firstPixels, x: 0, y: 0, painted: true)
        try assertPixel(firstPixels, x: 77, y: 2, painted: false)
        XCTAssertEqual(raster(fixture.runtime.renderScene()).pixels, firstPixels.pixels)

        fixture.radii.value = nil
        fixture.host.reload()
        let changed = fixture.runtime.renderScene()

        XCTAssertTrue(fixture.runtime.root.children.first === owner)
        XCTAssertEqual(owner.cornerRadius, 4, "Clearing C4 must preserve the scalar fallback")
        XCTAssertNil(owner.cornerRadii)
        try assertClip(changed, radii: RetainedCornerRadii(uniform: 4))
        let changedPixels = raster(changed)
        try assertPixel(changedPixels, x: 0, y: 0, painted: false)
        try assertPixel(changedPixels, x: 2, y: 2, painted: true)
        try assertPixel(changedPixels, x: 77, y: 2, painted: true)
    }

    private final class RadiiBox {
        var value: RetainedCornerRadii?

        init(_ value: RetainedCornerRadii?) {
            self.value = value
        }
    }

    private struct Fixture {
        let runtime: RetainedViewRuntime
        let host: ComponentHost
        let radii: RadiiBox
    }

    private func makeFixture(radii initialRadii: RetainedCornerRadii?, uniformRadius: Double) -> Fixture {
        let radii = RadiiBox(initialRadii)
        let runtime = RetainedViewRuntime(
            clearColor: .clear, root: ViewNode(frame: Self.bounds, isHitTestVisible: false))
        let host = ComponentHost(runtime: runtime)
        host.setComponents {
            [
                Component(key: "rounded-clip") { _ in
                    ViewNode(
                        frame: Self.bounds, cornerRadius: uniformRadius, cornerRadii: radii.value,
                        clipsToBounds: true, isHitTestVisible: false,
                        children: [ViewNode(frame: Self.bounds, backgroundColor: .white)])
                }
            ]
        }
        return Fixture(runtime: runtime, host: host, radii: radii)
    }

    private func assertClip(
        _ scene: GPUIScene, radii: RetainedCornerRadii,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let quad = try XCTUnwrap(
            scene.layers.flatMap(\.quads).first { $0.startR == 1 && $0.startG == 1 && $0.startA == 1 },
            file: file, line: line)
        XCTAssertEqual(quad.clipShapeBounds, Self.bounds, file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusTopLeft, Float(radii.topLeft), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusTopRight, Float(radii.topRight), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusBottomRight, Float(radii.bottomRight), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusBottomLeft, Float(radii.bottomLeft), file: file, line: line)
    }

    private func raster(_ scene: GPUIScene) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(scene, size: Self.pixelSize)
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, painted: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y), file: file, line: line)
        XCTAssertEqual(color.alpha, painted ? 1 : 0, accuracy: 1.0 / 255, file: file, line: line)
    }
}
