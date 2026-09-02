import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class WinSwiftUIContentBlurReconciliationTests: XCTestCase {
    private static let size = Size(width: 96, height: 80)
    private static let pixelSize = IntSize(width: 96, height: 80)
    private static let ownerIdentifier = "content-blur-owner"

    func testPublicBlurRadiusChangesFromZeroToPositiveAndBackOnSameNode() async throws {
        let fixture = Fixture(radius: 0)
        let sharp = fixture.render()
        let owner = try fixture.owner()
        try assertOwner(fixture, remains: owner, radius: 0, opaque: false)
        XCTAssertEqual(sharp.paintMetrics.contentBlurPasses, 0)
        XCTAssertTrue(images(in: sharp).isEmpty)
        XCTAssertTrue(sharp.imageResources.isEmpty)
        let sharpPixels = pixels(of: sharp)
        XCTAssertEqual(try alpha(in: sharpPixels, x: 10, y: 24), 0)
        XCTAssertEqual(try alpha(in: sharpPixels, x: 28, y: 24), 1)

        fixture.update(radius: 6)
        let blurred = fixture.render()
        try assertOwner(fixture, remains: owner, radius: 6, opaque: false)
        try assertIsolatedBlur(blurred, owner: owner, radius: 6, opaque: false)
        let blurredPixels = pixels(of: blurred)
        XCTAssertNotEqual(blurredPixels.pixels, sharpPixels.pixels)
        // The badge begins at x=12. Its own blur contributes outside that
        // edge, while a center farther than the kernel radius stays opaque.
        XCTAssertGreaterThan(try alpha(in: blurredPixels, x: 10, y: 24), 0)
        XCTAssertLessThan(try alpha(in: blurredPixels, x: 10, y: 24), 1)
        XCTAssertEqual(try alpha(in: blurredPixels, x: 28, y: 24), 1, accuracy: 1.0 / 255.0)
        assertWarmBitmap(fixture, matching: blurredPixels)

        fixture.update(radius: 0)
        let restored = fixture.render()
        try assertOwner(fixture, remains: owner, radius: 0, opaque: false)
        XCTAssertEqual(restored.paintMetrics.contentBlurPasses, 0)
        XCTAssertTrue(images(in: restored).isEmpty)
        XCTAssertTrue(restored.imageResources.isEmpty)
        XCTAssertEqual(pixels(of: restored).pixels, sharpPixels.pixels)
    }

    func testPositiveRadiusRebuildReplacesTheOldCachedBlurAndRestoresItsPixels() async throws {
        let fixture = Fixture(radius: 2)
        let first = fixture.render()
        let owner = try fixture.owner()
        try assertOwner(fixture, remains: owner, radius: 2, opaque: false)
        try assertIsolatedBlur(first, owner: owner, radius: 2, opaque: false)
        let firstPixels = pixels(of: first)
        let firstKey = try XCTUnwrap(owner.cachedCompositingGroupKey)
        assertWarmBitmap(fixture, matching: firstPixels)

        fixture.update(radius: 6)
        let wider = fixture.render()
        try assertOwner(fixture, remains: owner, radius: 6, opaque: false)
        try assertIsolatedBlur(wider, owner: owner, radius: 6, opaque: false)
        let widerPixels = pixels(of: wider)
        let widerKey = try XCTUnwrap(owner.cachedCompositingGroupKey)
        XCTAssertNotEqual(widerKey, firstKey)
        XCTAssertNotEqual(widerPixels.pixels, firstPixels.pixels)
        assertWarmBitmap(fixture, matching: widerPixels)

        fixture.update(radius: 2)
        let restored = fixture.render()
        try assertOwner(fixture, remains: owner, radius: 2, opaque: false)
        try assertIsolatedBlur(restored, owner: owner, radius: 2, opaque: false)
        let restoredPixels = pixels(of: restored)
        XCTAssertEqual(restoredPixels.pixels, firstPixels.pixels)
        XCTAssertEqual(owner.cachedCompositingGroupKey, firstKey)
        assertWarmBitmap(fixture, matching: restoredPixels)
    }

    func testOpaqueHintReconcilesIndependentlyAtFixedRadiusWithoutInventingAPixelChange() async throws {
        let fixture = Fixture(radius: 6, opaque: false)
        let first = fixture.render()
        let owner = try fixture.owner()
        try assertOwner(fixture, remains: owner, radius: 6, opaque: false)
        try assertIsolatedBlur(first, owner: owner, radius: 6, opaque: false)
        let firstPixels = pixels(of: first)
        let firstKey = try XCTUnwrap(owner.cachedCompositingGroupKey)
        assertWarmBitmap(fixture, matching: firstPixels)

        fixture.update(opaque: true)
        let opaque = fixture.render()
        try assertOwner(fixture, remains: owner, radius: 6, opaque: true)
        try assertIsolatedBlur(opaque, owner: owner, radius: 6, opaque: true)
        let opaquePixels = pixels(of: opaque)
        let opaqueKey = try XCTUnwrap(owner.cachedCompositingGroupKey)
        XCTAssertNotEqual(opaqueKey, firstKey)
        // The isolated content-blur pass currently treats opaque as a hint.
        // It must refresh the authored value and cache key, not manufacture
        // an opaque margin or change the pixels to prove that it did so.
        XCTAssertEqual(opaquePixels.pixels, firstPixels.pixels)
        assertWarmBitmap(fixture, matching: opaquePixels)

        fixture.update(opaque: false)
        let restored = fixture.render()
        try assertOwner(fixture, remains: owner, radius: 6, opaque: false)
        try assertIsolatedBlur(restored, owner: owner, radius: 6, opaque: false)
        let restoredPixels = pixels(of: restored)
        XCTAssertEqual(restoredPixels.pixels, firstPixels.pixels)
        XCTAssertEqual(owner.cachedCompositingGroupKey, firstKey)
        assertWarmBitmap(fixture, matching: restoredPixels)
    }

    private func assertOwner(
        _ fixture: Fixture, remains original: ViewNode, radius: Double, opaque: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let owner = try fixture.owner(file: file, line: line)
        XCTAssertTrue(owner === original, "Reconciliation must reuse the blur owner", file: file, line: line)
        XCTAssertEqual(owner.resolvedFrame.size, Size(width: 32, height: 24), file: file, line: line)
        XCTAssertEqual(owner.contentBlurRadius, radius, file: file, line: line)
        XCTAssertEqual(owner.contentBlurOpaque, opaque, file: file, line: line)
        XCTAssertEqual(owner.blurRadius, 0, "Content blur must not become backdrop blur", file: file, line: line)
        XCTAssertFalse(owner.blurOpaque, file: file, line: line)
    }

    private func assertIsolatedBlur(
        _ scene: GPUIScene, owner: ViewNode, radius: Double, opaque: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(scene.paintMetrics.contentBlurPasses, 1, file: file, line: line)
        XCTAssertEqual(scene.paintMetrics.contentBlurPassesReused, 0, file: file, line: line)
        XCTAssertTrue(scene.imageRenderPasses.isEmpty, file: file, line: line)
        XCTAssertEqual(scene.imageResources.count, 1, file: file, line: line)
        let blurImages = images(in: scene)
        XCTAssertEqual(blurImages.count, 1, file: file, line: line)
        let image = try XCTUnwrap(blurImages.first, file: file, line: line)
        XCTAssertEqual(image.screenX, Float(12 - radius), accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(image.screenY, Float(12 - radius), accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(image.screenW, Float(32 + 2 * radius), accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(image.screenH, Float(24 + 2 * radius), accuracy: 0.0001, file: file, line: line)
        XCTAssertTrue(scene.layers.flatMap(\.quads).allSatisfy { $0.blurRadius == 0 }, file: file, line: line)
        let key = try XCTUnwrap(owner.cachedCompositingGroupKey, file: file, line: line)
        XCTAssertEqual(key.contentBlurRadius, radius, file: file, line: line)
        XCTAssertEqual(key.contentBlurOpaque, opaque, file: file, line: line)
        let bitmap = try XCTUnwrap(owner.cachedCompositingGroupBitmap, file: file, line: line)
        XCTAssertEqual(bitmap.width, Int32(32 + 2 * radius), file: file, line: line)
        XCTAssertEqual(bitmap.height, Int32(24 + 2 * radius), file: file, line: line)
    }

    private func assertWarmBitmap(
        _ fixture: Fixture, matching expected: BitmapSurface,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        // Repaint the already laid-out public tree without a previous scene.
        // This measures actual bitmap reuse, not the runtime returning its
        // entire cached scene with the previous frame's counters.
        let warm = fixture.repaintSettledTree()
        XCTAssertEqual(warm.paintMetrics.contentBlurPasses, 1, file: file, line: line)
        XCTAssertEqual(warm.paintMetrics.contentBlurPassesReused, 1, file: file, line: line)
        XCTAssertEqual(pixels(of: warm).pixels, expected.pixels, file: file, line: line)
    }

    private func images(in scene: GPUIScene) -> [ImagePrimitive] {
        scene.layers.flatMap(\.images)
    }

    private func pixels(of scene: GPUIScene) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(scene, size: Self.pixelSize)
    }

    private func alpha(
        in bitmap: BitmapSurface, x: Int, y: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> Double {
        let color = try XCTUnwrap(bitmap.pixelColor(atX: x, y: y), file: file, line: line)
        return Double(color.alpha)
    }

    @MainActor
    private final class Fixture {
        let runtime: RetainedViewRuntime
        let host: ComponentHost
        private let state: Values

        init(radius: Double, opaque: Bool = false) {
            let state = Values(radius: radius, opaque: opaque)
            self.state = state
            let size = WinSwiftUIContentBlurReconciliationTests.size
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: size.width, height: size.height), isHitTestVisible: false)
            let runtime = RetainedViewRuntime(clearColor: .clear, root: root)
            self.runtime = runtime
            let host = ComponentHost(runtime: runtime)
            self.host = host
            let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
            host.setComponents {
                [
                    Rectangle().fill(Color.red).frame(width: 32, height: 24)
                        .blur(radius: state.radius, opaque: state.opaque)
                        .accessibilityIdentifier(WinSwiftUIContentBlurReconciliationTests.ownerIdentifier)
                        .padding(12)
                        .makeComponent(context: context)
                ]
            }
        }

        func update(radius: Double? = nil, opaque: Bool? = nil) {
            if let radius { state.radius = radius }
            if let opaque { state.opaque = opaque }
            host.reload()
        }

        func render() -> GPUIScene {
            runtime.renderScene()
        }

        func repaintSettledTree() -> GPUIScene {
            ScenePainter.paint(
                root: runtime.root, clearColor: .clear,
                surfaceSize: WinSwiftUIContentBlurReconciliationTests.size, displayScale: 1)
        }

        func owner(file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
            try XCTUnwrap(findOwner(in: runtime.root), file: file, line: line)
        }

        private func findOwner(in node: ViewNode) -> ViewNode? {
            if node.accessibilityIdentifier == WinSwiftUIContentBlurReconciliationTests.ownerIdentifier {
                return node
            }
            for child in node.children {
                if let owner = findOwner(in: child) { return owner }
            }
            return nil
        }
    }

    @MainActor
    private final class Values {
        var radius: Double
        var opaque: Bool

        init(radius: Double, opaque: Bool) {
            self.radius = radius
            self.opaque = opaque
        }
    }
}
