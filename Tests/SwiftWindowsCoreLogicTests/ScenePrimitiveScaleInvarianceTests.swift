import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// What a HiDPI render may and may not cost.
///
/// The same app at the same *logical* size emits more scene primitives at
/// 2x than at 1x — 752 → 787 on the demo dashboard, 490 → 520 on the data
/// screen. That is a legitimate difference with exactly one source, and
/// these tests are what keeps it that way: chrome does not multiply with
/// device pixels, and the only thing that does is path fill, which is
/// lowered to one axis-aligned quad per *device pixel row* and so is
/// counted in pixels by construction.
///
/// See docs/GPURenderingPipeline.md, "Why 2x emits more primitives".
@MainActor
final class ScenePrimitiveScaleInvarianceTests: XCTestCase {

    private struct FamilyCounts: Equatable, CustomStringConvertible {
        var shadows = 0
        var quads = 0
        var glyphs = 0
        var pixelGlyphs = 0
        var images = 0
        var paths = 0

        var description: String {
            "shadow \(shadows), quad \(quads), glyph \(glyphs), pixelGlyph \(pixelGlyphs), "
                + "image \(images), path \(paths)"
        }
    }

    private func families(_ screen: DemoScreen, displayScale: Double) -> FamilyCounts {
        let model = DemoDashboardModel()
        model.selectedScreen = screen
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model),
            // The runtime's root size is LOGICAL points, so the same value at
            // both scales is the same layout rendered into more pixels.
            size: IntSize(width: 1280, height: 720),
            displayScale: displayScale
        )
        var counts = FamilyCounts()
        for layer in snapshot.scene.layers {
            counts.shadows += layer.shadows.count
            counts.quads += layer.quads.count
            counts.glyphs += layer.glyphs.count
            counts.pixelGlyphs += layer.pixelGlyphs.count
            counts.images += layer.images.count
            counts.paths += layer.paths.count
        }
        return counts
    }

    /// Nothing but quads may differ. A glyph, an image, a shadow, or a CPU
    /// path is one primitive per drawn thing at any scale; a second one at
    /// 2x would mean something is emitting per device pixel that should not.
    func testOnlyQuadsDifferAcrossDisplayScale() async {
        for screen in DemoScreen.allCases {
            let one = families(screen, displayScale: 1)
            let two = families(screen, displayScale: 2)
            XCTAssertEqual(one.shadows, two.shadows, "\(screen) shadows")
            XCTAssertEqual(one.glyphs, two.glyphs, "\(screen) glyphs")
            XCTAssertEqual(one.pixelGlyphs, two.pixelGlyphs, "\(screen) pixel glyphs")
            XCTAssertEqual(one.images, two.images, "\(screen) images")
            XCTAssertEqual(one.paths, two.paths, "\(screen) CPU paths")
        }
    }

    /// Control chrome — fills, borders, corner-arc segments, hairlines,
    /// scroll indicators — is resolved in points and scaled afterwards, so a
    /// screen with no tessellated path fill costs the same number of
    /// primitives at 2x as at 1x. The settings pane is that screen.
    func testChromeOnlyScreenIsPrimitiveCountInvariantAcrossDisplayScale() async {
        let one = families(.settings, displayScale: 1)
        let two = families(.settings, displayScale: 2)
        XCTAssertEqual(
            one, two,
            "A pane of borders, arcs and hairlines must not cost more primitives at 2x"
        )
    }

    /// The one thing that is counted in device pixels, and why. A filled
    /// path is lowered to axis-aligned quads one device-pixel row at a
    /// time, so the same logical shape at 2x is twice as many rows — the
    /// rows *are* the pixels, and emitting a scale-invariant number of them
    /// would leave gaps.
    func testPathFillEmitsOneQuadPerDevicePixelRow() {
        func triangle(scaledBy scale: Double) -> PathPrimitive {
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 0, y: 0)),
                    .lineTo(Point(x: 40 * scale, y: 0)),
                    .lineTo(Point(x: 0, y: 20 * scale)),
                    .close,
                ],
                bounds: Rect(x: 0, y: 0, width: 40 * scale, height: 20 * scale),
                fillColor: .white
            )
        }

        guard
            let atOneX = PathToQuadTessellator.tessellate(triangle(scaledBy: 1)),
            let atTwoX = PathToQuadTessellator.tessellate(triangle(scaledBy: 2))
        else {
            return XCTFail("a triangle fill is tessellatable at both scales")
        }

        XCTAssertEqual(atOneX.count, 20, "one quad per device-pixel row of a 20px-tall triangle")
        XCTAssertEqual(atTwoX.count, 40, "the same shape at 2x is 40 pixel rows, so 40 quads")
        for quad in atOneX + atTwoX {
            XCTAssertEqual(
                Double(quad.height), 1, accuracy: 0.001,
                "every strip is exactly one device pixel tall at every scale"
            )
        }
    }
}
