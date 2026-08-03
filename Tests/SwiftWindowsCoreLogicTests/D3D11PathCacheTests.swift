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

    // MARK: - The raster is bounded by what can be seen

    /// A tall `Canvas` inside a short `ScrollView`.
    ///
    /// The renderer stripped the clip before rasterizing, so the bitmap, the
    /// coverage buffer and the GPU texture were all sized by the *unclipped*
    /// bounds — 8 megapixels and 32 MB for a chart showing 96 × 96 of itself,
    /// every frame it first appeared. The clip is still not part of the cache
    /// key; it now bounds the buffer instead.
    @MainActor
    func testAHugePathInsideASmallClipRasterizesBounded() async throws {
        let renderer = try makeIsolatedOffscreenRenderer()
        defer { renderer.detach() }

        var path = makeTallPath(height: 20_000)
        path.clipBounds = Rect(x: 0, y: 0, width: 96, height: 96)
        try render(path, through: renderer)

        let tile = Int(D3D11BatchRenderer.pathRasterWindowTile)
        let bound = (Int(Self.surface.width) + 2 * tile) * (Int(Self.surface.height) + 2 * tile)
        XCTAssertGreaterThan(renderer.largestPathRasterPixelsForTesting, 0, "something must have rasterized")
        XCTAssertLessThanOrEqual(
            renderer.largestPathRasterPixelsForTesting, bound,
            "the raster followed the path's extent rather than the clip and the surface")
        XCTAssertLessThan(renderer.largestPathRasterPixelsForTesting, 400 * 20_000 / 100)
    }

    /// Bounding the raster is only worth anything if it still draws the same
    /// pixels: the window is a *buffer* bound, not a second clip.
    @MainActor
    func testAWindowedPathDrawsWhatTheCPURasterizerDraws() async throws {
        let renderer = try makeIsolatedOffscreenRenderer()
        defer { renderer.detach() }

        var path = makeTallPath(height: 20_000)
        path.clipBounds = Rect(x: 8, y: 8, width: 96, height: 96)
        var scene = GPUIScene(clearColor: Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        scene.addPath(path, toLayer: 0)
        scene.finish()

        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        let gpu = try renderer.readOffscreenPixels()
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surface)

        let report = comparePixels(gpu, cpu, tolerance: 12)
        XCTAssertGreaterThan(
            report.matchRatio, 0.98,
            "the windowed raster must draw what the whole one did: "
                + "\(report.totalPixels - report.withinTolerance) pixels differ")
    }

    /// And the window is snapped to a grid, so scrolling inside it is still a
    /// hit rather than a re-rasterization per pixel of travel.
    @MainActor
    func testAWindowedPathStillHitsWhileScrollingInsideOneTile() async throws {
        let renderer = try makeIsolatedOffscreenRenderer()
        defer { renderer.detach() }

        for offset in 0..<8 {
            var path = makeTallPath(height: 20_000)
            path.clipBounds = Rect(x: 0, y: Double(offset), width: 96, height: 96)
            try render(path, through: renderer)
        }

        XCTAssertEqual(renderer.pathCacheMisses, 1, "eight pixels of scroll is one tile, so one raster")
        XCTAssertEqual(renderer.pathCacheHits, 7)
    }

    // MARK: - An outlier does not flush the cache

    /// One entry larger than the whole byte budget used to evict *every*
    /// other entry — the eviction loop cannot satisfy a condition that one
    /// entry alone violates — and then be inserted anyway. The next frame
    /// found an empty cache, re-rasterized everything, and did it again.
    @MainActor
    func testAnOversizedRasterIsDeniedRatherThanFlushingTheCache() async throws {
        let renderer = try makeIsolatedOffscreenRenderer()
        defer { renderer.detach() }
        D3D11BatchRenderer.pathCacheByteBudgetOverrideForTesting = 8_192
        defer { D3D11BatchRenderer.pathCacheByteBudgetOverrideForTesting = nil }

        // 30 × 20 × 4 = 2 400 bytes: comfortably inside the budget.
        try render(makePath(at: Point(x: 4, y: 4)), through: renderer)
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 1)
        let residentBytes = renderer.pathCacheByteCountForTesting

        // 100 × 100 × 4 = 40 000 bytes: past the budget on its own.
        var oversized = makePath(at: Point(x: 4, y: 4))
        oversized.elements = [
            .moveTo(Point(x: 4, y: 4)), .lineTo(Point(x: 104, y: 4)),
            .lineTo(Point(x: 104, y: 104)), .lineTo(Point(x: 4, y: 104)), .close,
        ]
        oversized.bounds = Rect(x: 4, y: 4, width: 100, height: 100)
        try render(oversized, through: renderer)

        XCTAssertEqual(renderer.pathCacheOversizedDenials, 1)
        XCTAssertEqual(
            renderer.pathCacheEntryCountForTesting, 1, "the outlier must not evict what it cannot replace")
        XCTAssertEqual(renderer.pathCacheByteCountForTesting, residentBytes)

        // …and the entry it did not evict is still there to hit.
        try render(makePath(at: Point(x: 4, y: 4)), through: renderer)
        XCTAssertEqual(renderer.pathCacheHits, 1)
    }

    // MARK: - The key is a digest, not a copy

    /// The key used to be a translated copy of the whole primitive: an
    /// element array allocated per path per frame purely to have something to
    /// hash. The digest is translation-invariant instead, so no copy is made
    /// and the exact comparison is only the tie-break behind it.
    func testShapeDigestIsTranslationInvariantAndMatchesWithoutCopying() {
        let a = makePath(at: Point(x: 12, y: 7))
        let b = makePath(at: Point(x: 200, y: 90))
        XCTAssertEqual(a.shapeHash, b.shapeHash)

        let normalized = a.translated(by: Point(x: -a.bounds.origin.x, y: -a.bounds.origin.y))
        XCTAssertEqual(normalized.shapeHash, a.shapeHash, "normalizing must not change the digest")
        XCTAssertTrue(
            normalized.matchesShapeAndPaint(
                of: b, translatedBy: Point(x: -b.bounds.origin.x, y: -b.bounds.origin.y)))

        var recoloured = a
        recoloured.fillColor = Color(red: 0, green: 1, blue: 0, alpha: 1)
        XCTAssertNotEqual(recoloured.shapeHash, a.shapeHash)
        XCTAssertFalse(normalized.matchesShapeAndPaint(of: recoloured, translatedBy: .zero))

        var restyled = a
        restyled.lineCap = .round
        XCTAssertNotEqual(restyled.shapeHash, a.shapeHash)
    }

    /// The old key sampled at most 32 elements, so two 200-segment charts
    /// differing at an unsampled vertex hashed the same and leaned entirely
    /// on a full-array `==` to tell them apart. The digest reads every
    /// element.
    func testDigestSeparatesPathsThatDifferAtAnUnsampledVertex() {
        func chart(bumpAt index: Int?) -> PathPrimitive {
            var elements: [PathElement] = [.moveTo(.zero)]
            for step in 1...200 {
                let y = step == index ? 10.0 : 0.0
                elements.append(.lineTo(Point(x: Double(step), y: y)))
            }
            return PathPrimitive(
                elements: elements,
                bounds: Rect(x: 0, y: 0, width: 200, height: 10),
                strokeColor: .white,
                lineWidth: 2)
        }
        // Index 101 is not on the old stride-of-6 sample grid.
        XCTAssertNotEqual(chart(bumpAt: 101).shapeHash, chart(bumpAt: nil).shapeHash)
        XCTAssertFalse(
            chart(bumpAt: 101).matchesShapeAndPaint(of: chart(bumpAt: nil), translatedBy: .zero))
    }

    /// Two different shapes with the same extent at the same place are two
    /// entries and two rasterizations — the digest must not merge them.
    @MainActor
    func testTwoShapesWithTheSameExtentStayTwoEntries() async throws {
        let renderer = try makeIsolatedOffscreenRenderer()
        defer { renderer.detach() }

        var triangle = makePath(at: Point(x: 8, y: 8))
        triangle.elements = [
            .moveTo(Point(x: 8, y: 8)), .lineTo(Point(x: 38, y: 8)), .lineTo(Point(x: 8, y: 28)), .close,
        ]
        try render(makePath(at: Point(x: 8, y: 8)), through: renderer)
        try render(triangle, through: renderer)

        XCTAssertEqual(renderer.pathCacheMisses, 2)
        XCTAssertEqual(renderer.pathCacheHits, 0)
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 2)
    }

    // MARK: - Helpers

    private func makeTallPath(height: Double) -> PathPrimitive {
        PathPrimitive(
            elements: [
                .moveTo(Point(x: 0, y: 0)),
                .lineTo(Point(x: 400, y: height)),
                .lineTo(Point(x: 0, y: height)),
                .close,
            ],
            bounds: Rect(x: 0, y: 0, width: 400, height: height),
            fillColor: Color(red: 0.2, green: 0.6, blue: 1, alpha: 1),
            strokeColor: .clear,
            lineWidth: 0)
    }

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
        try render(path, through: renderer)
    }

    @MainActor
    private func render(_ path: PathPrimitive, through renderer: D3D11BatchRenderer) throws {
        var scene = GPUIScene(clearColor: Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        scene.addPath(path, toLayer: 0)
        scene.finish()
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
    }
}
