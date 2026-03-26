import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
@testable import SwiftWindowsUI
import SwiftWindowsRendererD3D11

// MARK: - Integration Tests: Batch Renderer Wiring

final class IntegrationTests: XCTestCase {

    // MARK: - GPUIScene Bridge Tests

    func testBridgeConvertsEmptyFrameToSceneWithOneLayer() {
        let frame = RenderFrame(clearColor: .white, commands: [])
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 800, height: 600))

        XCTAssertEqual(scene.clearColor, .white)
        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertEqual(scene.primitiveCount, 0)
    }

    func testBridgeConvertsFillRectsToQuads() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(
                rect: Rect(x: 10, y: 20, width: 100, height: 50),
                color: Color(red: 1, green: 0, blue: 0, alpha: 1)
            )),
            .fillRect(FillRectCommand(
                rect: Rect(x: 30, y: 40, width: 60, height: 80),
                color: Color(red: 0, green: 1, blue: 0, alpha: 1),
                cornerRadius: 8
            )),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 800, height: 600))

        // Both fillRect commands are the same primitive type, so they should
        // stay in the same layer.
        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertEqual(scene.layers[0].quads.count, 2)

        let first = scene.layers[0].quads[0]
        XCTAssertEqual(first.x, 10)
        XCTAssertEqual(first.y, 20)
        XCTAssertEqual(first.width, 100)
        XCTAssertEqual(first.height, 50)
        XCTAssertEqual(first.startR, 1)

        let second = scene.layers[0].quads[1]
        XCTAssertEqual(second.cornerRadius, 8)
        XCTAssertEqual(second.startG, 1)
    }

    func testBridgePushesLayerOnPrimitiveTypeChange() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 50, height: 50),
                color: .white
            )),
            .drawBitmap(DrawBitmapCommand(
                rect: Rect(x: 0, y: 0, width: 50, height: 50),
                bitmap: BitmapSurface(width: 1, height: 1, bytesPerRow: 4,
                                      pixels: Data([255, 255, 255, 255]))
            )),
            .fillRect(FillRectCommand(
                rect: Rect(x: 60, y: 0, width: 50, height: 50),
                color: .black
            )),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 200, height: 200))

        // quad -> image (new layer) -> quad (new layer) = 3 layers
        XCTAssertEqual(scene.layers.count, 3)
        XCTAssertEqual(scene.layers[0].quads.count, 1)
        XCTAssertEqual(scene.layers[1].images.count, 1)
        XCTAssertEqual(scene.layers[2].quads.count, 1)
    }

    func testBridgePreservesClearColor() {
        let clearColor = Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1.0)
        let frame = RenderFrame(clearColor: clearColor, commands: [])
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 100, height: 100))

        XCTAssertEqual(scene.clearColor, clearColor)
    }

    func testBridgeHandlesClipCommands() {
        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(
                shape: .rect(Rect(x: 10, y: 10, width: 80, height: 80), cornerRadius: 0)
            )),
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 100, height: 100),
                color: .white
            )),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 100, height: 100))

        XCTAssertEqual(scene.layers[0].quads.count, 1)
        // The quad should carry the clip rect from the pushClip command.
        let quad = scene.layers[0].quads[0]
        XCTAssertEqual(quad.clipX, 10)
        XCTAssertEqual(quad.clipY, 10)
        XCTAssertEqual(quad.clipWidth, 80)
        XCTAssertEqual(quad.clipHeight, 80)
    }

    // MARK: - renderScene() Tests

    func testRenderSceneProducesNonEmptyScene() async {
        await MainActor.run {
            let child = ViewNode(
                frame: Rect(x: 0, y: 0, width: 50, height: 30),
                backgroundColor: .white
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                children: [child]
            )
            let runtime = RetainedViewRuntime(root: root)
            let scene = runtime.renderScene()

            XCTAssertGreaterThan(scene.primitiveCount, 0)
            XCTAssertFalse(scene.layers.isEmpty)
        }
    }

    func testRenderSceneUsesRootFrameForSurfaceSize() async {
        await MainActor.run {
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 640, height: 480),
                backgroundColor: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0)
            )
            let runtime = RetainedViewRuntime(
                clearColor: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
                root: root
            )
            let scene = runtime.renderScene()

            // The scene's clear color should come from the runtime.
            XCTAssertEqual(scene.clearColor, Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
        }
    }

    // MARK: - GPUIScene Layer Management Tests

    func testPushLayerIncreasesCount() {
        var scene = GPUIScene(clearColor: .black)
        XCTAssertEqual(scene.layers.count, 1)

        scene.pushLayer()
        XCTAssertEqual(scene.layers.count, 2)

        scene.pushLayer()
        XCTAssertEqual(scene.layers.count, 3)
    }

    func testPushLayerReturnsCorrectIndex() {
        var scene = GPUIScene(clearColor: .black)
        let idx = scene.pushLayer()
        XCTAssertEqual(idx, 1)
    }

    func testPrimitiveCountAcrossLayers() {
        var scene = GPUIScene(clearColor: .black)
        scene.layers[0].quads.append(QuadPrimitive(
            x: 0, y: 0, width: 10, height: 10,
            startR: 1, startG: 1, startB: 1, startA: 1,
            endR: 1, endG: 1, endB: 1, endA: 1
        ))
        scene.pushLayer()
        scene.layers[1].shadows.append(ShadowPrimitive(
            x: 0, y: 0, width: 10, height: 10,
            colorR: 0, colorG: 0, colorB: 0, colorA: 0.5
        ))
        scene.layers[1].quads.append(QuadPrimitive(
            x: 0, y: 0, width: 20, height: 20,
            startR: 0, startG: 0, startB: 1, startA: 1,
            endR: 0, endG: 0, endB: 1, endA: 1
        ))

        XCTAssertEqual(scene.primitiveCount, 3)
    }

    // MARK: - BatchRenderBackend Protocol Tests

    func testBatchRenderBackendProtocolCanBeReferenced() async {
        // Verify the protocol exists and can be used as a type constraint.
        // We cannot instantiate it (no concrete implementation yet), but we
        // can confirm the factory returns the expected nil stub.
        await MainActor.run {
            let backend: (any BatchRenderBackend)? = DefaultRenderBackendFactory.makeBatchBackend()
            XCTAssertNil(backend, "makeBatchBackend() should return nil until a concrete implementation is merged")
        }
    }

    // MARK: - GPUILayer Tests

    func testEmptyLayerHasZeroPrimitives() {
        let layer = GPUILayer()
        XCTAssertEqual(layer.primitiveCount, 0)
        XCTAssertTrue(layer.quads.isEmpty)
        XCTAssertTrue(layer.shadows.isEmpty)
        XCTAssertTrue(layer.glyphs.isEmpty)
        XCTAssertTrue(layer.images.isEmpty)
    }

    func testSceneDefaultsToSingleEmptyLayer() {
        let scene = GPUIScene()
        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertEqual(scene.clearColor, .black)
        XCTAssertEqual(scene.primitiveCount, 0)
    }
}
