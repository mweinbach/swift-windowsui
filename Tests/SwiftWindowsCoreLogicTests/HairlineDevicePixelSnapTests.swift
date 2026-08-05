import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Hairline rules land on whole device pixels, at every display scale.
///
/// Both backends rasterize a quad the same way: the pixel shader runs only
/// where a pixel *centre* falls inside the rect (`GPUIQuadCoverage`
/// `geometryCovers`, and the D3D11 vertex stage which emits the rect with no
/// antialiasing margin), and the signed-distance term inside can attenuate
/// that coverage but never extend it. A one-device-pixel rule sitting on a
/// half pixel therefore contains exactly one pixel centre, at distance zero
/// from its own edge, and draws at half weight — the other half is not
/// redistributed, it is lost.
///
/// At 100% that is rare, because whole points land on whole pixels. At 125%,
/// 150% and 175% it is the common case (10pt × 1.25 = 12.5), which is why
/// separator weight used to vary with DPI. See `docs/Typography.md`.
@MainActor
final class HairlineDevicePixelSnapTests: XCTestCase {

    // MARK: - The policy, as arithmetic

    func testSnapPinsTheThinAxisToWholeDevicePixels() async {
        // A 1-device-pixel rule at a half pixel: 10pt at 125% is device 12.5.
        let snapped = ScenePainter.devicePixelSnappedRule(
            Rect(x: 0, y: 10, width: 120, height: 0.8), displayScale: 1.25)
        XCTAssertEqual(snapped.origin.y * 1.25, (snapped.origin.y * 1.25).rounded(), accuracy: 1e-9)
        XCTAssertEqual(snapped.size.height * 1.25, 1, accuracy: 1e-9)
        XCTAssertEqual(snapped.origin.x, 0, "the long axis is untouched")
        XCTAssertEqual(snapped.size.width, 120, "the long axis is untouched")
    }

    func testSnapNeverThinsARuleBelowOneDevicePixel() async {
        for scale: Double in [1, 1.25, 1.5, 2, 3] {
            let snapped = ScenePainter.devicePixelSnappedRule(
                Rect(x: 0, y: 7.3, width: 100, height: 0.05), displayScale: scale)
            XCTAssertEqual(
                snapped.size.height * scale, 1, accuracy: 1e-9,
                "@\(scale)x: a rule rounds up to one device pixel rather than disappearing")
        }
    }

    func testSnapKeepsTheRuleWithinHalfADevicePixelOfWhereLayoutPutIt() async {
        for scale: Double in [1, 1.25, 1.5, 1.75, 2] {
            for y: Double in [10, 10.1, 10.3, 10.5, 10.7, 10.9] {
                let height = 1 / scale
                let snapped = ScenePainter.devicePixelSnappedRule(
                    Rect(x: 0, y: y, width: 100, height: height), displayScale: scale)
                let snappedCentre = snapped.origin.y + snapped.size.height / 2
                let centreShift = abs(snappedCentre - (y + height / 2)) * scale
                XCTAssertLessThanOrEqual(
                    centreShift, 0.5 + 1e-9,
                    "@\(scale)x y=\(y): a pinned rule may move by half a device pixel, no more")
            }
        }
    }

    func testSnapPicksTheThinAxisOfAVerticalRule() async {
        let snapped = ScenePainter.devicePixelSnappedRule(
            Rect(x: 10, y: 4, width: 0.8, height: 200), displayScale: 1.25)
        XCTAssertEqual(snapped.size.width * 1.25, 1, accuracy: 1e-9)
        XCTAssertEqual(snapped.origin.y, 4, "the long axis is untouched")
        XCTAssertEqual(snapped.size.height, 200, "the long axis is untouched")
    }

    func testSnapLeavesDegenerateGeometryAlone() async {
        let nan = Rect(x: 0, y: .nan, width: 10, height: 1)
        XCTAssertTrue(ScenePainter.devicePixelSnappedRule(nan, displayScale: 1.5).origin.y.isNaN)
        let rect = Rect(x: 0, y: 10, width: 10, height: 1)
        XCTAssertEqual(ScenePainter.devicePixelSnappedRule(rect, displayScale: 0).origin.y, 10)
        XCTAssertEqual(ScenePainter.devicePixelSnappedRule(rect, displayScale: .nan).origin.y, 10)
    }

    // MARK: - Which nodes it applies to

    func testOnlyAxisAlignedLeafRulesArePinned() async {
        let rule = ViewNode()
        rule.isSeparatorRule = true
        XCTAssertTrue(ScenePainter.snapsRuleToDevicePixels(rule, placement: .axisAligned(.zero)))

        let plain = ViewNode()
        XCTAssertFalse(
            ScenePainter.snapsRuleToDevicePixels(plain, placement: .axisAligned(.zero)),
            "ordinary content keeps the geometry the app asked for")

        let rotated = PaintPlacement(frame: .zero, rotation: 0.3, boundingBox: .zero)
        XCTAssertFalse(
            ScenePainter.snapsRuleToDevicePixels(rule, placement: rotated),
            "a rotated rule has no device axis to pin to")

        let scaled = PaintPlacement.axisAligned(.zero, scale: 2)
        XCTAssertFalse(
            ScenePainter.snapsRuleToDevicePixels(rule, placement: scaled),
            "a scaled rule is resampled by construction")

        let parentRule = ViewNode()
        parentRule.isSeparatorRule = true
        parentRule.addChild(ViewNode())
        XCTAssertFalse(
            ScenePainter.snapsRuleToDevicePixels(parentRule, placement: .axisAligned(.zero)),
            "pinning a node with children would move its paint off the frame they are placed against")
    }

    // MARK: - End to end

    private func dividerScene(topPadding: Double, displayScale: Double) -> BitmapSurface {
        let size = IntSize(
            width: Int32((120 * displayScale).rounded()),
            height: Int32((80 * displayScale).rounded()))
        let scene = WinSwiftUIRendererSnapshotter.snapshot(
            of: AnyView(
                VStack(spacing: 0) {
                    Divider().padding(.top, topPadding)
                    Spacer()
                }
                .frame(width: 120, height: 80)),
            size: size,
            displayScale: displayScale,
            clearColor: .black
        ).scene
        return GPUIRawSceneRasterizer.rasterize(scene, size: size)
    }

    /// The peak luminance down the middle of the surface, and how many rows
    /// carry any ink at all.
    private func ruleProfile(_ bitmap: BitmapSurface) -> (peak: Double, inkedRows: Int) {
        let width = Int(bitmap.width)
        let height = Int(bitmap.height)
        let stride = Int(bitmap.bytesPerRow)
        let bytes = [UInt8](bitmap.pixels)
        let column = width / 2
        var peak = 0.0
        var inked = 0
        for y in 0..<height {
            let offset = y * stride + column * 4
            guard offset + 3 < bytes.count else { continue }
            let value = Double(max(bytes[offset], max(bytes[offset + 1], bytes[offset + 2]))) / 255.0
            if value > 0.005 { inked += 1 }
            peak = max(peak, value)
        }
        return (peak, inked)
    }

    /// The regression this exists for: a `Divider` used to render anywhere
    /// between 50% and 100% of its intended weight depending on where layout
    /// happened to land it in device space. Nine of the fifteen cases below
    /// were short before the pin; all fifteen are exact after it.
    func testEveryDividerDrawsOneFullWeightDevicePixelAtEveryScale() async {
        // The reference: an integer scale with an integer offset, where the
        // rule has always been exactly right.
        let reference = ruleProfile(dividerScene(topPadding: 10, displayScale: 1)).peak
        XCTAssertGreaterThan(reference, 0.02, "the separator must actually be visible on black")

        for topPadding: Double in [10, 10.3, 10.5] {
            for displayScale: Double in [1, 1.25, 1.5, 1.75, 2] {
                let profile = ruleProfile(dividerScene(topPadding: topPadding, displayScale: displayScale))
                XCTAssertEqual(
                    profile.peak, reference, accuracy: 0.005,
                    "pad \(topPadding) @\(displayScale)x: the rule must carry its full weight, not a "
                        + "fraction of it left over from straddling two device rows")
                XCTAssertEqual(
                    profile.inkedRows, 1,
                    "pad \(topPadding) @\(displayScale)x: a hairline is one device row, never a two-row smear")
            }
        }
    }

    /// A rule's own pin must not move anything else: it is a paint-time
    /// adjustment, and the layout tree it sits in is unchanged.
    func testPinningARuleDoesNotMoveItsSiblings() async {
        for displayScale: Double in [1.25, 1.5] {
            let size = IntSize(width: Int32(200 * displayScale), height: Int32(120 * displayScale))
            let view = AnyView(
                VStack(spacing: 0) {
                    Text("Above").font(.system(size: 13)).foregroundColor(.white)
                    Divider()
                    Text("Below").font(.system(size: 13)).foregroundColor(.white)
                }
                .frame(width: 200, height: 120))
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: view, size: size, displayScale: displayScale, clearColor: .black)
            let glyphYs = snapshot.scene.layers.flatMap { $0.glyphs.map(\.screenY) }.sorted()
            XCTAssertFalse(glyphYs.isEmpty)

            // The same tree with the rule removed places its text identically.
            let withoutRule = AnyView(
                VStack(spacing: 0) {
                    Text("Above").font(.system(size: 13)).foregroundColor(.white)
                    Color.clear.frame(height: 1 / displayScale)
                    Text("Below").font(.system(size: 13)).foregroundColor(.white)
                }
                .frame(width: 200, height: 120))
            let control = WinSwiftUIRendererSnapshotter.snapshot(
                of: withoutRule, size: size, displayScale: displayScale, clearColor: .black)
            let controlYs = control.scene.layers.flatMap { $0.glyphs.map(\.screenY) }.sorted()
            XCTAssertEqual(
                glyphYs, controlYs,
                "@\(displayScale)x: pinning the rule changed where the text around it landed")
        }
    }
}
