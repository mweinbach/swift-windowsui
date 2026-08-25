import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsScene
import XCTest

final class PortableCoreGeometryTests: XCTestCase {
    func testRectangleIntersectionAndHalfOpenContainment() {
        let rectangle = Rect(x: 3, y: 4, width: 12, height: 8)

        XCTAssertEqual(
            rectangle.intersected(with: Rect(x: 10, y: 2, width: 8, height: 8)),
            Rect(x: 10, y: 4, width: 5, height: 6)
        )
        XCTAssertTrue(rectangle.contains(Point(x: 3, y: 4)))
        XCTAssertFalse(rectangle.contains(Point(x: 15, y: 12)))
        XCTAssertNil(rectangle.intersected(with: Rect(x: 15, y: 4, width: 1, height: 1)))
    }

    func testPremultipliedColorInterpolationPreservesTransparentEndpoints() {
        let start = Color(red: 1, green: 0, blue: 0, alpha: 0)
        let end = Color(red: 0, green: 0, blue: 1, alpha: 1)
        let midpoint = start.interpolated(to: end, progress: 0.5)

        XCTAssertEqual(midpoint.red, 0, accuracy: 0.0001)
        XCTAssertEqual(midpoint.green, 0, accuracy: 0.0001)
        XCTAssertEqual(midpoint.blue, 1, accuracy: 0.0001)
        XCTAssertEqual(midpoint.alpha, 0.5, accuracy: 0.0001)
    }

    func testAffineRotationUsesPortableMathImplementation() {
        let transform = Transform2D(rotation: .pi / 2)
        let point = Point(x: 4, y: 0).applying(transform)

        XCTAssertEqual(point.x, 0, accuracy: 0.0001)
        XCTAssertEqual(point.y, 4, accuracy: 0.0001)
    }
}

final class PortableLayoutTests: XCTestCase {
    func testFlexGrowDistributesAvailableSpaceProportionally() {
        let layout = FlexboxEngine.layout(
            FlexboxEngine.LayoutInput(
                containerWidth: 360,
                containerHeight: 80,
                style: FlexStyle(direction: .row),
                children: [
                    .init(itemStyle: FlexItemStyle(grow: 1), intrinsicHeight: 30),
                    .init(itemStyle: FlexItemStyle(grow: 2), intrinsicHeight: 30),
                ]
            )
        )

        XCTAssertEqual(layout.count, 2)
        XCTAssertEqual(layout[0].width, 120, accuracy: 0.0001)
        XCTAssertEqual(layout[1].width, 240, accuracy: 0.0001)
        XCTAssertEqual(layout[1].x, 120, accuracy: 0.0001)
        XCTAssertEqual(layout[0].height, 80, accuracy: 0.0001)
    }

    func testWrappingUsesPortableLayoutGeometry() {
        let layout = FlexboxEngine.layout(
            FlexboxEngine.LayoutInput(
                containerWidth: 100,
                containerHeight: 120,
                style: FlexStyle(direction: .row, wrap: .wrap, alignItems: .flexStart, gap: 10),
                children: [
                    .init(intrinsicWidth: 60, intrinsicHeight: 20),
                    .init(intrinsicWidth: 60, intrinsicHeight: 30),
                ]
            )
        )

        XCTAssertEqual(layout.count, 2)
        XCTAssertEqual(layout[0].y, 0, accuracy: 0.0001)
        XCTAssertEqual(layout[1].y, 30, accuracy: 0.0001)
    }
}

final class PortableSceneContractTests: XCTestCase {
    func testMixedPrimitiveFamiliesPreserveAuthoredPresentationOrder() {
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 8, height: 8))
        scene.addShadow(ShadowPrimitive(x: 0, y: 0, width: 8, height: 8))
        scene.addQuad(QuadPrimitive(x: 2, y: 2, width: 4, height: 4))
        scene.finish()

        XCTAssertEqual(
            Array(scene.presentationOrder()),
            [
                GPUIPresentationRun(layerIndex: 0, kind: .quad, range: 0..<1),
                GPUIPresentationRun(layerIndex: 0, kind: .shadow, range: 0..<1),
                GPUIPresentationRun(layerIndex: 0, kind: .quad, range: 1..<2),
            ]
        )
        XCTAssertTrue(scene.validate().isEmpty)
    }

    func testLegacySceneProducesRendererNeutralFrame() {
        let rectangle = Rect(x: 2, y: 3, width: 7, height: 9)
        let node = SolidRectNode(rect: rectangle, color: .blue, cornerRadius: 2)
        let scene = Scene(clearColor: .white, nodes: [.solidRect(node)])

        XCTAssertEqual(scene.frame.clearColor, .white)
        XCTAssertEqual(
            scene.frame.commands,
            [
                .fillRect(
                    FillRectCommand(rect: rectangle, color: .blue, cornerRadius: 2)
                )
            ]
        )
    }

    func testFrameGradientBridgePreservesAuthoredStops() {
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: .red, position: 0),
                GradientStop(color: .green, position: 0.25),
                GradientStop(color: .blue, position: 1),
            ],
            axis: .horizontal
        )
        let frame = RenderFrame(
            clearColor: .clear,
            commands: [
                .fillRect(
                    FillRectCommand(
                        rect: Rect(x: 0, y: 0, width: 12, height: 4),
                        color: .white,
                        gradient: .linear(gradient)
                    )
                )
            ]
        )
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 12, height: 4))

        XCTAssertEqual(scene.layers[0].quads.count, 2)
        XCTAssertEqual(Array(scene.presentationOrder()).count, 1)
        XCTAssertEqual(scene.layers[0].quads[0].startR, 1, accuracy: 0.0001)
        XCTAssertEqual(scene.layers[0].quads[1].endB, 1, accuracy: 0.0001)
    }

    func testSoftwareRasterizerUsesPortableBGRAPixelContract() {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(
            QuadPrimitive(
                x: 1,
                y: 1,
                width: 2,
                height: 2,
                startR: 1,
                startG: 0,
                startB: 0,
                startA: 1,
                endR: 1,
                endG: 0,
                endB: 0,
                endA: 1
            )
        )

        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 4, height: 4))
        let center = (1 * Int(bitmap.bytesPerRow)) + (1 * 4)

        XCTAssertEqual(bitmap.width, 4)
        XCTAssertEqual(bitmap.height, 4)
        XCTAssertEqual(Array(bitmap.pixels[center..<center + 4]), [0, 0, 255, 255])
        XCTAssertEqual(Array(bitmap.pixels.prefix(4)), [0, 0, 0, 255])
    }

    func testPortablePNGWriterProducesValidSignature() throws {
        let bitmap = BitmapSurface(
            width: 1,
            height: 1,
            bytesPerRow: 4,
            pixels: Data([0, 0, 255, 255])
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-windowsui-portable-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }

        try bitmap.writePNG(to: output)

        let encoded = try Data(contentsOf: output)
        XCTAssertEqual(Array(encoded.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}

@MainActor
final class PortableSoftwareRendererTests: XCTestCase {
    func testCPUFactoryCreatesBothPortableBackendKinds() async {
        let factory = CPURenderBackendFactory()

        XCTAssertEqual(factory.factoryName, "CPU Reference")
        XCTAssertEqual(factory.probeAvailability(), .available)
        XCTAssertEqual(factory.makeRenderBackend().backendDisplayName, "CPU REFERENCE")
        XCTAssertEqual(factory.makeBatchRenderBackend()?.backendDisplayName, "CPU REFERENCE")
    }

    func testCPUBackendRendersARealOffscreenSurfaceWithoutAWindowHandle() async throws {
        let size = IntSize(width: 8, height: 6)
        let renderer = CPUBatchRenderer()
        try renderer.attach(to: SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1))

        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(
            QuadPrimitive(
                x: 2,
                y: 1,
                width: 4,
                height: 3,
                startR: 0,
                startG: 1,
                startB: 0,
                startA: 1,
                endR: 0,
                endG: 1,
                endB: 0,
                endA: 1
            )
        )

        try renderer.render(scene: scene)

        let rendered = try XCTUnwrap(renderer.lastRenderedBitmap)
        XCTAssertEqual(rendered, GPUIRawSceneRasterizer.rasterize(scene, size: size))
        XCTAssertEqual(rendered.width, size.width)
        XCTAssertEqual(rendered.height, size.height)
    }
}
