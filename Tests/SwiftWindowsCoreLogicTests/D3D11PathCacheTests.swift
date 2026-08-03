import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Tests for the D3D11 path render cache infrastructure. These cover the
/// translation-invariance of the cache key and structural invariants on a
/// fresh renderer. End-to-end cache-hit verification needs a real device, so
/// the live cache behaviour is exercised by integration tests when D3D11 is
/// available.
final class D3D11PathCacheTests: XCTestCase {
    private func makePath(at origin: Point) -> PathPrimitive {
        let elements: [PathElement] = [
            .moveTo(Point(x: origin.x + 0, y: origin.y + 0)),
            .lineTo(Point(x: origin.x + 30, y: origin.y + 0)),
            .lineTo(Point(x: origin.x + 30, y: origin.y + 20)),
            .lineTo(Point(x: origin.x + 0, y: origin.y + 20)),
            .close,
        ]
        return PathPrimitive(
            elements: elements,
            bounds: Rect(origin: origin, size: Size(width: 30, height: 20)),
            fillColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            strokeColor: .clear,
            lineWidth: 0
        )
    }

    func testTranslatedPathsNormalizeToIdenticalKeys() {
        let a = makePath(at: Point(x: 12, y: 7))
        let b = makePath(at: Point(x: 200, y: 90))
        let aNorm = a.translated(by: Point(x: -a.bounds.origin.x, y: -a.bounds.origin.y))
        let bNorm = b.translated(by: Point(x: -b.bounds.origin.x, y: -b.bounds.origin.y))
        XCTAssertEqual(
            aNorm,
            bNorm,
            "Path translation invariance: two paths with the same shape at different offsets must hash to the same normalized key"
        )
        XCTAssertEqual(aNorm.bounds.origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(aNorm.bounds.origin.y, 0, accuracy: 0.0001)
    }

    func testPathsDifferingInShapeStayDistinct() {
        var a = makePath(at: .zero)
        let b = makePath(at: .zero)
        // Modify one element so the shape genuinely changes.
        a.elements[1] = .lineTo(Point(x: 50, y: 0))
        XCTAssertNotEqual(a, b)
    }

    func testPathsDifferingInColorStayDistinct() {
        var a = makePath(at: .zero)
        let b = makePath(at: .zero)
        a.fillColor = Color(red: 0, green: 1, blue: 0, alpha: 1)
        XCTAssertNotEqual(a, b)
    }

    func testFreshRendererHasEmptyPathCache() async {
        await MainActor.run {
            let renderer = D3D11BatchRenderer()
            XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 0)
            XCTAssertEqual(renderer.pathCacheHits, 0)
            XCTAssertEqual(renderer.pathCacheMisses, 0)
        }
    }

    /// The clip is not part of the raster.
    ///
    /// The key used to be the whole `PathPrimitive`, clip included, so a chart
    /// inside a `ScrollView` produced a different key on every frame the clip
    /// moved: a miss, a CPU rasterization on the main actor and a texture
    /// upload, sixty times a second, for a shape that never changed. The clip
    /// now rides along as a draw parameter — a visible UV sub-rect plus the
    /// shader's clip rect — so it cannot reach the key at all.
    @MainActor
    func testOnePathUnderTwoClipsIsOneEntryOneMissOneHit() async throws {
        let renderer = try makeIsolatedOffscreenRenderer()
        defer { renderer.detach() }

        try render(pathClippedTo: Rect(x: 0, y: 0, width: 96, height: 96), through: renderer)
        XCTAssertEqual(renderer.pathCacheMisses, 1)
        XCTAssertEqual(renderer.pathCacheHits, 0)

        try render(pathClippedTo: Rect(x: 16, y: 16, width: 96, height: 96), through: renderer)

        XCTAssertEqual(renderer.pathCacheMisses, 1, "a moved clip is not a new path")
        XCTAssertEqual(renderer.pathCacheHits, 1)
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 1)
    }

    /// Sixty frames of the scroll case: the clip translates every frame and
    /// the path translates with it. One rasterization, fifty-nine hits.
    @MainActor
    func testATranslatingClippedPathStaysOneRasterizationAcrossSixtyFrames() async throws {
        let renderer = try makeIsolatedOffscreenRenderer()
        defer { renderer.detach() }

        for frame in 0..<60 {
            let offset = Double(frame % 24)
            try render(
                pathClippedTo: Rect(x: 8, y: offset, width: 96, height: 80),
                pathOrigin: Point(x: 16, y: offset),
                through: renderer)
        }

        XCTAssertEqual(renderer.pathCacheMisses, 1, "sixty frames of scrolling must rasterize once")
        XCTAssertEqual(renderer.pathCacheHits, 59)
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 1)
    }

    // MARK: - Helpers

    @MainActor
    private func makeIsolatedOffscreenRenderer() throws -> D3D11BatchRenderer {
        // Not `WARPBatchRenderer.shared`: that instance is reused across the
        // whole target, so its path-cache counters carry other tests' history.
        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: Self.surface, driver: .warpFirst)
        } catch {
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        return renderer
    }

    private static let surface = IntSize(width: 128, height: 128)

    @MainActor
    private func render(
        pathClippedTo clip: Rect,
        pathOrigin: Point = Point(x: 16, y: 16),
        through renderer: D3D11BatchRenderer
    ) throws {
        var path = makePath(at: pathOrigin)
        path.clipBounds = clip
        var scene = GPUIScene(clearColor: Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        scene.addPath(path, toLayer: 0)
        scene.finish()
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
    }
}
