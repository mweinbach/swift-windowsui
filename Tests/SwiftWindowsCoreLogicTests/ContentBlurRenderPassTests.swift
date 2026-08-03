import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// `.blur(radius:)` and `.background(.regularMaterial)` used to be the same
/// field on `ViewNode`, which made both of them wrong.
///
/// - As a *cost* bug, the radius was inherited by every descendant and
///   landed on every descendant background quad. Each such quad breaks the
///   quad batch and costs one backbuffer copy plus two blur passes, so a
///   blurred list of 50 rows issued 50 copies and 100 blur draws a frame.
/// - As a *fidelity* bug, only background quads carry the field, so the text,
///   images, borders and paths inside a `.blur()`ed subtree came out
///   perfectly sharp — a `.blur()` on a label did nothing at all.
///
/// The two meanings are now separate: `blurRadius` is the node's own
/// backdrop effect and does not inherit; `contentBlurRadius` is resolved as
/// an **isolated** render pass — the subtree painted into its own offscreen
/// buffer, blurred there, composited back — because a backdrop pass blurs
/// whatever is already painted under it, and a `.blur()` on one view is not
/// allowed to change the pixels of another.
@MainActor
final class ContentBlurRenderPassTests: XCTestCase {

    private func snapshot<V: View>(_ view: V, size: IntSize = IntSize(width: 320, height: 480))
        -> WinSwiftUIRenderSnapshot
    {
        WinSwiftUIRendererSnapshotter.snapshot(of: view, size: size, displayScale: 1)
    }

    private func blurredQuads(_ snapshot: WinSwiftUIRenderSnapshot) -> [QuadPrimitive] {
        snapshot.scene.layers.flatMap { $0.quads.filter { $0.blurRadius > 0 } }
    }

    private func images(_ snapshot: WinSwiftUIRenderSnapshot) -> [ImagePrimitive] {
        snapshot.scene.layers.flatMap { $0.images }
    }

    private struct RowList: View {
        let count: Int
        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    Text("row \(index)")
                        .frame(width: 200, height: 8)
                        .background(Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
                }
            }
        }
    }

    // MARK: - One pass, not one per descendant

    func testBlurOverManyBackgroundedChildrenEmitsOnePass() async {
        let blurred = snapshot(RowList(count: 50).blur(radius: 8))
        XCTAssertEqual(
            blurred.scene.paintMetrics.contentBlurPasses, 1,
            "a `.blur()` on a container is one render pass over the subtree, not one backdrop blur per "
                + "descendant")
        XCTAssertTrue(
            blurredQuads(blurred).isEmpty,
            "an isolated content blur composites a bitmap; it must not also leave a backdrop-blur quad "
                + "behind, which would blur the scene under the panel a second time")

        // And the pass covers the subtree, so nothing inside it stays sharp.
        let plain = snapshot(RowList(count: 50))
        XCTAssertEqual(plain.scene.paintMetrics.contentBlurPasses, 0)
        XCTAssertTrue(
            blurredQuads(plain).isEmpty,
            "the same tree without `.blur()` must emit no blurred quads at all")
    }

    func testMaterialBackgroundDoesNotBlurItsDescendantsBackgrounds() async {
        let materialPanel = snapshot(
            RowList(count: 20)
                .background(.regularMaterial)
        )
        XCTAssertEqual(
            blurredQuads(materialPanel).count, 1,
            "a Material background is the panel's own backdrop effect; the cards inside it are not "
                + "each a frosted panel")
        XCTAssertEqual(
            materialPanel.scene.paintMetrics.contentBlurPasses, 0,
            "a Material is a backdrop pass, not a content-blur isolation")
    }

    /// The radius reaching the pass is the device-pixel radius, and it is the
    /// radius the app asked for. The isolation buffer is the subtree's frame
    /// outset by exactly that radius, so the blur fades out past the frame
    /// instead of ending at a hard edge — which is the observable the
    /// composited image's extent pins.
    func testContentBlurRadiusReachesTheSceneScaledByDisplayScale() async {
        let snapshotAt2x = WinSwiftUIRendererSnapshotter.snapshot(
            // Padded away from the surface edge: the buffer is clamped to the
            // clip, and a subtree at the origin would have its left and top
            // margin clipped away — correctly, but it would make the extent
            // below say less than it means to.
            of: RowList(count: 4).frame(width: 200, height: 32).blur(radius: 6).padding(20),
            size: IntSize(width: 320, height: 240),
            displayScale: 2)
        let blurImages = images(snapshotAt2x)
        XCTAssertEqual(blurImages.count, 1)
        XCTAssertEqual(
            blurImages.first?.screenW ?? 0, Float(200 * 2 + 2 * 12), accuracy: 1.5,
            "at 2x a radius-6 blur is 12 device pixels, and the pass is the frame outset by that much")
        XCTAssertEqual(blurImages.first?.screenH ?? 0, Float(32 * 2 + 2 * 12), accuracy: 1.5)
    }

    func testNestedBlursEachEmitTheirOwnPass() async {
        let nested = snapshot(
            VStack(spacing: 0) {
                RowList(count: 5).blur(radius: 4)
                RowList(count: 5).blur(radius: 9)
            }
            .padding(20)
        )
        XCTAssertEqual(
            nested.scene.paintMetrics.contentBlurPasses, 2,
            "two independent `.blur()` subtrees are two passes")
        let widths = images(nested).map { $0.screenW }.sorted()
        XCTAssertEqual(widths.count, 2)
        guard widths.count == 2 else { return }
        // Same subtree width, different margins: 2 * (9 - 4) = 10 points.
        XCTAssertEqual(widths[1] - widths[0], 10, accuracy: 1.5)
    }

    // MARK: - Isolation: a blur changes the view it is on, and nothing else

    /// The regression this pass exists to prevent. A backdrop blur over the
    /// subtree's outset bounds composites *the blurred backdrop* across that
    /// whole rectangle, so blurring the middle row of a stack replaced a band
    /// of the rows above and below with a smeared copy of themselves.
    ///
    /// Blurring a view that draws nothing is the sharpest statement of it:
    /// the render must be pixel-for-pixel what it was without the modifier.
    func testBlurringAnEmptyViewLeavesEverySiblingPixelIdentical() async {
        let size = IntSize(width: 160, height: 150)

        struct Stack: View {
            let radius: Double
            var body: some View {
                VStack(spacing: 0) {
                    Stripes()
                    Color.clear.frame(width: 120, height: 50).blur(radius: radius)
                    Stripes()
                }
            }
        }

        let sharp = GPUIRawSceneRasterizer.rasterize(
            WinSwiftUIRendererSnapshotter.snapshot(of: Stack(radius: 0), size: size, displayScale: 1).scene,
            size: size)
        let blurred = GPUIRawSceneRasterizer.rasterize(
            WinSwiftUIRendererSnapshotter.snapshot(of: Stack(radius: 10), size: size, displayScale: 1).scene,
            size: size)

        let report = comparePixels(blurred, sharp, tolerance: 0)
        XCTAssertEqual(
            report.matchRatio, 1.0,
            "blurring a view that paints nothing must change nothing; a blur that reaches its siblings "
                + "is a backdrop pass wearing a content blur's name (max channel delta "
                + "\(report.maxChannelDelta), first failure \(String(describing: report.firstFailure)))")
    }

    /// And with something to blur: the wallpaper behind a blurred badge stays
    /// sharp. Sampled just outside the badge, where the badge's own falloff
    /// has almost no alpha left — the backdrop lowering smeared the stripes
    /// there because it blurred everything already painted under its bounds.
    ///
    /// Built from retained nodes rather than views so the geometry is exact:
    /// the badge is at (50, 50) 40×40, and rows 42…47 under columns 45…95 are
    /// wallpaper inside the radius-10 ring.
    func testABlurredBadgeDoesNotBlurTheWallpaperAroundIt() async {
        let size = IntSize(width: 140, height: 140)

        func scene(radius: Double) -> GPUIScene {
            var children: [ViewNode] = []
            for stripe in 0..<35 {
                children.append(
                    ViewNode(
                        frame: Rect(x: 0, y: Double(stripe) * 4, width: 140, height: 2),
                        backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1)))
            }
            children.append(
                ViewNode(
                    frame: Rect(x: 50, y: 50, width: 40, height: 40),
                    backgroundColor: Color(red: 0.1, green: 0.8, blue: 0.3, alpha: 1),
                    contentBlurRadius: radius))
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 140, height: 140), children: children)
            return ScenePainter.paint(
                root: root, clearColor: .black, surfaceSize: Size(width: 140, height: 140))
        }

        let sharp = GPUIRawSceneRasterizer.rasterize(scene(radius: 0), size: size)
        let blurred = GPUIRawSceneRasterizer.rasterize(scene(radius: 10), size: size)

        let sharpContrast = Self.maxNeighbourDelta(sharp, rows: 42..<48, columns: 45..<95)
        let blurredContrast = Self.maxNeighbourDelta(blurred, rows: 42..<48, columns: 45..<95)
        XCTAssertGreaterThan(
            sharpContrast, 200,
            "the fixture must have high-contrast stripes there for the comparison to mean anything")
        XCTAssertGreaterThan(
            Double(blurredContrast), Double(sharpContrast) * 0.75,
            "the wallpaper around a blurred badge must stay sharp: the badge's own falloff is nearly "
                + "transparent this far out, so the stripes must survive it (measured \(blurredContrast) "
                + "against \(sharpContrast))")
    }

    // MARK: - Fidelity: the subtree's content is what gets blurred

    /// The regression that matters visually. A `.blur()` on a label used to
    /// change nothing whatsoever, because the label has no background quad
    /// for the inherited radius to land on.
    func testBlurredTextIsActuallyBlurred() async {
        let size = IntSize(width: 160, height: 80)
        let sharp = WinSwiftUIRendererSnapshotter.snapshot(
            of: Text("BLUR").font(.system(size: 32)).frame(width: 160, height: 80),
            size: size, displayScale: 1)
        let soft = WinSwiftUIRendererSnapshotter.snapshot(
            of: Text("BLUR").font(.system(size: 32)).frame(width: 160, height: 80).blur(radius: 5),
            size: size, displayScale: 1)

        let sharpPixels = GPUIRawSceneRasterizer.rasterize(sharp.scene, size: size)
        let softPixels = GPUIRawSceneRasterizer.rasterize(soft.scene, size: size)

        let report = comparePixels(softPixels, sharpPixels, tolerance: 8)
        XCTAssertLessThan(
            report.matchRatio, 0.98,
            "blurring a label must change its pixels; a `.blur()` that leaves text untouched is the bug "
                + "this pass exists to fix")

        // And the change is a blur, not an erase: the ink is still there.
        XCTAssertGreaterThan(
            Self.inkCoverage(softPixels), 0,
            "the blurred label must still draw ink")
        XCTAssertLessThan(
            Self.maxNeighbourDelta(softPixels), Self.maxNeighbourDelta(sharpPixels),
            "the blurred render must be locally smoother than the sharp one")
    }

    // MARK: - Deferred children are inside the blur, not on top of it

    /// A pinned section header is a *deferred* subtree: prepaint collects it
    /// and the painter drains it after every node has finished painting —
    /// which is after the blur. So a blurred pinned list used to render
    /// blurred rows with a perfectly sharp header sitting on top of them.
    /// There is no ordering of one pass that fixes that; the header has to be
    /// inside the thing being blurred.
    func testPinnedHeaderInsideABlurredSubtreeIsBlurredWithIt() async {
        let size = IntSize(width: 240, height: 200)

        struct PinnedList: View {
            let radius: Double
            var body: some View {
                ScrollView {
                    LazyVStack(pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(0..<6, id: \.self) { index in
                                Text("row \(index)").frame(width: 200, height: 20)
                            }
                        } header: {
                            Text("HEADER")
                                .frame(width: 200, height: 24)
                                .background(Color(red: 1, green: 0, blue: 0, alpha: 1))
                        }
                    }
                }
                .frame(width: 220, height: 160)
                .blur(radius: radius)
            }
        }

        func headerQuadCount(_ snapshot: WinSwiftUIRenderSnapshot) -> Int {
            snapshot.scene.layers.reduce(0) {
                $0 + $1.quads.filter { $0.startR > 0.9 && $0.startG < 0.1 && $0.startB < 0.1 }.count
            }
        }

        let sharp = WinSwiftUIRendererSnapshotter.snapshot(
            of: PinnedList(radius: 0), size: size, displayScale: 1)
        XCTAssertGreaterThan(
            headerQuadCount(sharp), 0,
            "the fixture must actually pin a header, or the blurred case proves nothing")

        let blurred = WinSwiftUIRendererSnapshotter.snapshot(
            of: PinnedList(radius: 6), size: size, displayScale: 1)
        XCTAssertEqual(blurred.scene.paintMetrics.contentBlurPasses, 1)
        XCTAssertEqual(
            headerQuadCount(blurred), 0,
            "the pinned header must be painted inside the blurred subtree's bitmap, not drawn sharp on "
                + "top of it by the deferred phase")
    }

    /// And it stays claimed when the pass reuses its bitmap. The deferred
    /// entry is already inside those pixels; drawing it again because this
    /// frame skipped the rasterization would put a sharp copy on top from the
    /// second frame onwards — a bug that only appears once the cache warms,
    /// which is exactly the kind a single-frame test misses.
    func testDeferredDescendantStaysClaimedWhenTheBlurBitmapIsReused() async {
        let header = ViewNode(
            frame: Rect(x: 0, y: 0, width: 60, height: 12),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1))
        header.paintsInDeferredPhase = true
        let body = ViewNode(
            frame: Rect(x: 0, y: 12, width: 60, height: 40),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
        let blurred = ViewNode(
            frame: Rect(x: 10, y: 10, width: 60, height: 52),
            contentBlurRadius: 4,
            children: [header, body])
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100), children: [blurred])

        // The deferred entry prepaint would have produced for the pinned
        // child, drained after every node has painted.
        var deferredDraws = [
            DeferredDrawState(
                priority: 0,
                parentDispatchIndex: 0,
                contentMask: nil,
                payload: .subtree(
                    DeferredSubtreePayload(
                        node: header,
                        parentOrigin: Point(x: 10, y: 10),
                        inheritedClip: nil,
                        inheritedOpacity: 1,
                        inheritedInverseTransform: nil,
                        inheritedColorEffects: []
                    )
                )
            )
        ]

        func paint() -> GPUIScene {
            var replay = 0
            var deferredReplay = 0
            return ScenePainter.paint(
                root: root,
                clearColor: .black,
                surfaceSize: Size(width: 120, height: 100),
                displayScale: 1,
                textSystem: WindowTextSystem(),
                previousScene: nil,
                deferredDraws: &deferredDraws,
                replayCount: &replay,
                deferredReplayCount: &deferredReplay)
        }

        func headerQuadCount(_ scene: GPUIScene) -> Int {
            scene.layers.reduce(0) {
                $0 + $1.quads.filter { $0.startR > 0.9 && $0.startG < 0.1 && $0.startB < 0.1 }.count
            }
        }

        let first = paint()
        XCTAssertEqual(first.paintMetrics.contentBlurPasses, 1)
        XCTAssertEqual(headerQuadCount(first), 0, "the deferred child belongs inside the blurred bitmap")

        let second = paint()
        XCTAssertEqual(
            second.paintMetrics.contentBlurPassesReused, 1,
            "the fixture must actually hit the bitmap cache, or it proves nothing")
        XCTAssertEqual(
            headerQuadCount(second), 0,
            "the reused bitmap already contains the deferred child; the deferred phase must still skip it")
    }

    /// The cache the test above cannot see: the *outer* scene replay. The
    /// paint above passes `previousScene: nil`, so it exercises only the
    /// bitmap cache. Through `renderScene()` a second frame has a real
    /// previous scene, and a clean blurred node used to replay its cached
    /// paint range — bitmap included — without ever reaching the isolation
    /// branch, so nothing claimed its deferred child and the deferred phase
    /// drew a second, sharp copy on top.
    func testACleanBlurredSubtreeDoesNotReplayASharpCopyOfItsDeferredChild() async {
        let header = ViewNode(
            frame: Rect(x: 0, y: 0, width: 60, height: 12),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1))
        header.paintsInDeferredPhase = true
        let body = ViewNode(
            frame: Rect(x: 0, y: 12, width: 60, height: 40),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
        let blurred = ViewNode(
            frame: Rect(x: 10, y: 10, width: 60, height: 52),
            contentBlurRadius: 4,
            children: [header, body])
        let sibling = ViewNode(
            frame: Rect(x: 80, y: 10, width: 30, height: 30),
            backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1))
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 100),
            children: [blurred, sibling])
        let runtime = RetainedViewRuntime(root: root)

        func headerQuadCount(_ scene: GPUIScene) -> Int {
            scene.layers.reduce(0) {
                $0 + $1.quads.filter { $0.startR > 0.9 && $0.startG < 0.1 && $0.startB < 0.1 }.count
            }
        }

        let first = runtime.renderScene()
        XCTAssertEqual(first.paintMetrics.contentBlurPasses, 1)
        XCTAssertEqual(headerQuadCount(first), 0, "the deferred child belongs inside the blurred bitmap")

        // Dirty the sibling, not the blurred subtree: the second frame must
        // repaint at all — a fully clean runtime returns its cached scene and
        // never reaches the deferred phase — while the blurred node itself
        // stays clean, which is the exact shape that used to take the outer
        // replay path.
        sibling.backgroundColor = Color(red: 1, green: 1, blue: 0, alpha: 1)
        let second = runtime.renderScene()
        XCTAssertEqual(
            second.paintMetrics.contentBlurPassesReused, 1,
            "the clean subtree must composite its cached bitmap, or the fixture proves nothing")
        XCTAssertEqual(
            headerQuadCount(second), 0,
            "a clean blurred node must keep its deferred child claimed; replaying the outer range "
                + "without claiming painted a second, sharp copy on top from frame 2 onwards")
    }

    /// A scroll view *nested inside* a blurred subtree defers its indicator
    /// exactly like a pinned header defers its subtree — and it used to stay
    /// unclaimed because the payload carried only a dispatch index, so the
    /// deferred phase painted the indicator sharp on top of the blurred
    /// bitmap. (The blurred node's *own* indicator is deliberately not
    /// claimed and stays sharp above its content, matching the subtree rule
    /// that excludes the node itself.)
    func testANestedScrollViewsIndicatorIsBlurredWithTheSubtree() async {
        let indicatorColor = Color(red: 1, green: 0, blue: 1, alpha: 1)

        func fixture(radius: Double) -> (root: ViewNode, deferredDraws: [DeferredDrawState]) {
            let scroller = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 52),
                backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
            let blurred = ViewNode(
                frame: Rect(x: 10, y: 10, width: 60, height: 52),
                contentBlurRadius: radius,
                children: [scroller])
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100), children: [blurred])
            // The deferred entry prepaint produces for the nested scroll
            // view's indicator, drained after every node has painted.
            let deferredDraws = [
                DeferredDrawState(
                    priority: 0,
                    parentDispatchIndex: 0,
                    contentMask: nil,
                    payload: .scrollIndicator(
                        ScrollIndicatorDeferredDrawPayload(
                            node: scroller,
                            dispatchIndex: 0,
                            track: ScrollIndicatorTrack(
                                axis: .vertical, origin: 12, travel: 30,
                                indicatorRect: Rect(x: 62, y: 12, width: 6, height: 20)),
                            color: indicatorColor,
                            cornerRadius: 3
                        ))
                )
            ]
            return (root, deferredDraws)
        }

        func paint(_ fixture: (root: ViewNode, deferredDraws: [DeferredDrawState])) -> GPUIScene {
            var deferredDraws = fixture.deferredDraws
            var replay = 0
            var deferredReplay = 0
            return ScenePainter.paint(
                root: fixture.root,
                clearColor: .black,
                surfaceSize: Size(width: 120, height: 100),
                displayScale: 1,
                textSystem: WindowTextSystem(),
                previousScene: nil,
                deferredDraws: &deferredDraws,
                replayCount: &replay,
                deferredReplayCount: &deferredReplay)
        }

        func indicatorQuadCount(_ scene: GPUIScene) -> Int {
            scene.layers.reduce(0) {
                $0 + $1.quads.filter { $0.startR > 0.9 && $0.startG < 0.1 && $0.startB > 0.9 }.count
            }
        }

        let sharp = paint(fixture(radius: 0))
        XCTAssertEqual(
            indicatorQuadCount(sharp), 1,
            "without a blur the deferred phase draws the indicator into the outer scene")

        let blurred = paint(fixture(radius: 4))
        XCTAssertEqual(blurred.paintMetrics.contentBlurPasses, 1)
        XCTAssertEqual(
            indicatorQuadCount(blurred), 0,
            "a nested scroll view's indicator belongs inside the blurred bitmap, not sharp on top of it")

        // And claimed means *drawn into the pass*, not dropped: the bitmap
        // with the indicator differs from one painted without the entry.
        var withoutEntry = fixture(radius: 4)
        withoutEntry.deferredDraws = []
        let without = paint(withoutEntry)
        XCTAssertNotEqual(
            blurred.imageResources.first?.bitmap, without.imageResources.first?.bitmap,
            "the claimed indicator must be painted into the isolation pass's bitmap")
    }

    // MARK: - Cost

    /// A blurred subtree costs a CPU rasterization plus a Gaussian when it
    /// changes and nothing when it does not.
    func testUnchangedBlurredSubtreeReusesItsBitmap() async {
        let child = ViewNode(
            frame: Rect(x: 0, y: 0, width: 60, height: 40),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
        let blurred = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 60),
            contentBlurRadius: 5,
            children: [child])
        func paint() -> GPUIScene {
            ScenePainter.paint(root: blurred, clearColor: .black, surfaceSize: Size(width: 200, height: 120))
        }

        let first = paint()
        XCTAssertEqual(first.paintMetrics.contentBlurPasses, 1)
        XCTAssertEqual(first.paintMetrics.contentBlurPassesReused, 0)

        let second = paint()
        XCTAssertEqual(
            second.paintMetrics.contentBlurPasses, 1,
            "an unchanged blurred subtree still composites its pass")
        XCTAssertEqual(
            second.paintMetrics.contentBlurPassesReused, 1,
            "…but it must not rasterize and blur the subtree again")
        XCTAssertEqual(
            second.imageResources.first?.bitmap, first.imageResources.first?.bitmap,
            "and the composited image must be the same pixels, not just the same count")

        child.backgroundColor = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let third = paint()
        XCTAssertEqual(
            third.paintMetrics.contentBlurPassesReused, 0,
            "a dirty descendant must invalidate the blurred bitmap")
        XCTAssertNotEqual(
            third.imageResources.first?.bitmap, first.imageResources.first?.bitmap,
            "the reblurred bitmap must carry the change")
    }

    // MARK: - Fixtures

    /// High-contrast 2-point stripes: a pattern a Gaussian destroys and a
    /// composite leaves alone.
    private struct Stripes: View {
        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<25, id: \.self) { index in
                    (index % 2 == 0
                        ? Color(red: 1, green: 1, blue: 1, alpha: 1)
                        : Color(red: 0, green: 0, blue: 0, alpha: 1))
                        .frame(width: 140, height: 2)
                }
            }
        }
    }

    /// Sum of non-background coverage, as a crude "is anything drawn" probe.
    private static func inkCoverage(_ surface: BitmapSurface) -> Int {
        var total = 0
        for y in 0..<Int(surface.height) {
            for x in 0..<Int(surface.width) {
                let offset = y * Int(surface.bytesPerRow) + x * 4
                guard offset + 3 < surface.pixels.count else { continue }
                let luminance =
                    Int(surface.pixels[offset]) + Int(surface.pixels[offset + 1]) + Int(surface.pixels[offset + 2])
                if luminance > 30 { total += 1 }
            }
        }
        return total
    }

    /// Largest channel step between neighbouring pixels, in either axis —
    /// high for crisp glyph edges or a stripe pattern, low once a Gaussian
    /// has run over them.
    private static func maxNeighbourDelta(
        _ surface: BitmapSurface, rows: Range<Int>? = nil, columns: Range<Int>? = nil
    ) -> Int {
        var worst = 0
        let stride = Int(surface.bytesPerRow)
        let range = rows ?? 1..<Int(surface.height)
        let columnRange = columns ?? 1..<Int(surface.width)
        for y in range where y >= 1 && y < Int(surface.height) {
            for x in columnRange where x >= 1 && x < Int(surface.width) {
                let offset = y * stride + x * 4
                guard offset + 3 < surface.pixels.count else { continue }
                for neighbour in [offset - 4, offset - stride] {
                    guard neighbour >= 0 else { continue }
                    for channel in 0..<3 {
                        worst = max(
                            worst,
                            abs(Int(surface.pixels[offset + channel]) - Int(surface.pixels[neighbour + channel])))
                    }
                }
            }
        }
        return worst
    }
}
