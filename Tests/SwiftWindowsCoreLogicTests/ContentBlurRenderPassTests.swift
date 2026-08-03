import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// WS-20: `.blur(radius:)` and `.background(.regularMaterial)` used to be the
/// same field on `ViewNode`, which made both of them wrong.
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
/// a single render pass over the subtree's painted bounds.
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
        let quads = blurredQuads(blurred)
        XCTAssertEqual(
            quads.count, 1,
            "a `.blur()` on a container is one render pass over the subtree, not one backdrop blur per "
                + "descendant background; got \(quads.count) blurred quads")

        // And the pass covers the subtree, so nothing inside it stays sharp.
        let plain = snapshot(RowList(count: 50))
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
    }

    /// The radius reaching the scene is the device-pixel radius, and it is
    /// the radius the app asked for — not something an ancestor merged in.
    func testContentBlurRadiusReachesTheSceneScaledByDisplayScale() async {
        let snapshotAt2x = WinSwiftUIRendererSnapshotter.snapshot(
            of: RowList(count: 4).blur(radius: 6),
            size: IntSize(width: 320, height: 240),
            displayScale: 2)
        let quads = snapshotAt2x.scene.layers.flatMap { $0.quads.filter { $0.blurRadius > 0 } }
        XCTAssertEqual(quads.count, 1)
        XCTAssertEqual(quads.first?.blurRadius ?? 0, 12, accuracy: 0.001)
    }

    func testNestedBlursEachEmitTheirOwnPass() async {
        let nested = snapshot(
            VStack(spacing: 0) {
                RowList(count: 5).blur(radius: 4)
                RowList(count: 5).blur(radius: 9)
            }
        )
        let radii = blurredQuads(nested).map { $0.blurRadius }.sorted()
        XCTAssertEqual(radii.count, 2, "two independent `.blur()` subtrees are two passes")
        XCTAssertEqual(radii, [4, 9])
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

    /// Largest horizontal channel step between neighbouring pixels — high
    /// for crisp glyph edges, low once a Gaussian has run over them.
    private static func maxNeighbourDelta(_ surface: BitmapSurface) -> Int {
        var worst = 0
        for y in 0..<Int(surface.height) {
            for x in 1..<Int(surface.width) {
                let offset = y * Int(surface.bytesPerRow) + x * 4
                let previous = offset - 4
                guard offset + 3 < surface.pixels.count else { continue }
                for channel in 0..<3 {
                    worst = max(
                        worst,
                        abs(Int(surface.pixels[offset + channel]) - Int(surface.pixels[previous + channel])))
                }
            }
        }
        return worst
    }
}
