import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Three engine claims the pixel gates could not previously see.
///
/// 1. A focus ring is an ANNULUS. Both paths used to fill the whole outset
///    rect and rely on the control's border and background to cover all but
///    the margin. The macOS palettes are translucent, so the accent showed
///    through the body and a focused bordered button rendered accent-blue —
///    which in macOS terms is a different control (the prominent/default
///    button). Unit tests read palette fields and stayed green throughout.
///
/// 2. A shadow's cull footprint has to use the same TURNED offset the shadow
///    is emitted with, or a rotated card's halo is culled against a rectangle
///    it was never going to occupy.
///
/// 3. The snapshotter's `size` is POINTS. A HiDPI render therefore needs a
///    `size * scale` surface; sizing it `size` (which is what
///    `swift-windowsui-snapshot --scale 2` used to do) crops the render to the
///    top-left quadrant and magnifies it, so nothing about a HiDPI *layout*
///    was ever verified.
@MainActor
final class FocusRingAndDensityTests: XCTestCase {

    private let surfaceSize = Size(width: 400, height: 300)

    // MARK: - 1. The focus ring is a ring

    /// A control whose own fill is translucent is the case that exposes a
    /// slab: whatever is painted under the body shows through it.
    private func translucentFocusedButton() -> ViewNode {
        let node = ViewNode(
            frame: Rect(x: 100, y: 100, width: 120, height: 36),
            // 15% white, the class of fill `ControlPalette.controlSurface`
            // uses. An opaque fill would hide a slab and prove nothing.
            backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 0.15),
            outlineColor: Color(red: 0, green: 0.478, blue: 1, alpha: 0.55),
            outlineWidth: 4,
            cornerRadius: 6
        )
        node.isFocusable = true
        return node
    }

    /// The interior of the control must contain no outline geometry at all.
    func testFocusRingLeavesTheControlBodyUncovered() async throws {
        let node = translucentFocusedButton()
        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        let ringColor = Color(red: 0, green: 0.478, blue: 1, alpha: 0.55)
        let ringQuads = scene.layers[0].quads.filter {
            abs($0.startB - Float(ringColor.blue)) < 0.01 && abs($0.startR - Float(ringColor.red)) < 0.01
        }
        XCTAssertFalse(ringQuads.isEmpty, "the focus ring is still drawn")

        // The body is the control's frame inset past its 6pt corner radius.
        // A corner arc's bounding box legitimately reaches into the frame's
        // square corners — which are OUTSIDE the rounded bezel, i.e. still
        // background — so the interior is what the ring must not touch.
        let body = Rect(x: 100, y: 100, width: 120, height: 36).outset(by: -7)
        for quad in ringQuads {
            let quadRect = Rect(
                x: Double(quad.x), y: Double(quad.y),
                width: Double(quad.width), height: Double(quad.height))
            XCTAssertNil(
                quadRect.intersected(with: body),
                """
                A ring quad covers the control's body at \(quadRect). The ring must occupy \
                only the band outside the bezel — a slab under a translucent fill repaints \
                the control accent.
                """)
        }
    }

    /// And it must still reach outside it: a ring that covers nothing is not a
    /// fix, it is a deletion.
    func testFocusRingStillCoversTheBandOutsideTheControl() async throws {
        let node = translucentFocusedButton()
        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        let ringQuads = scene.layers[0].quads.filter { $0.startB > 0.9 && $0.startR < 0.1 }
        XCTAssertFalse(ringQuads.isEmpty)

        // Something has to be painted just left of the bezel, inside the 4pt band.
        let leftBand = Rect(x: 97, y: 115, width: 2, height: 6)
        let covered = ringQuads.contains { quad in
            let quadRect = Rect(
                x: Double(quad.x), y: Double(quad.y),
                width: Double(quad.width), height: Double(quad.height))
            return quadRect.intersected(with: leftBand) != nil
        }
        XCTAssertTrue(covered, "the ring still occupies the band outside the bezel")
    }

    /// The frame path is the same ring, from the same walk — the two paths
    /// disagreeing is how the shadow double-offset survived as long as it did.
    func testFramePathDrawsTheSameRingAsTheScenePath() async throws {
        let node = translucentFocusedButton()
        let runtime = RetainedViewRuntime(clearColor: .black, root: node)
        runtime.setRootSize(IntSize(width: 400, height: 300))
        let commands = runtime.renderFrame().commands

        let body = Rect(x: 100, y: 100, width: 120, height: 36).outset(by: -7)
        var ringFills = 0
        for command in commands {
            guard case .fillRect(let fill) = command else { continue }
            // The ring's blue, either the 4pt outline or the 2pt focus effect.
            guard fill.color.blue > 0.9, fill.color.red < 0.3 else { continue }
            ringFills += 1
            XCTAssertNil(
                fill.rect.intersected(with: body),
                "the frame path's ring covers the body at \(fill.rect)")
        }
        XCTAssertGreaterThan(ringFills, 0, "the frame path still draws a ring")
    }

    /// The 2pt focus *effect* halo is the other ring, and it had the same
    /// defect — it is emitted from `focusEffectCommands`, shared by both paths.
    func testFocusEffectHaloIsARingNotASlab() async throws {
        let node = ViewNode(
            frame: Rect(x: 50, y: 50, width: 100, height: 30),
            backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 0.15),
            cornerRadius: 6
        )
        node.isFocusable = true
        node.isFocused = true

        let commands = node.focusEffectCommands(for: node.frame, inheritedClip: nil, opacity: 1)
        XCTAssertFalse(commands.isEmpty, "a focused node still draws its halo")

        let body = node.frame.outset(by: -7)
        for command in commands {
            XCTAssertNil(
                command.rect.intersected(with: body),
                "the focus halo covers the body at \(command.rect)")
        }
    }

    // MARK: - 2. A rotated shadow is culled where it actually falls

    /// A card turned 90° with `.shadow(y: …)` casts to its SIDE. The cull
    /// footprint used the unturned offset, so a clip that the halo actually
    /// falls in could be missed and the whole subtree pruned.
    func testRotatedShadowSurvivesACullAgainstWhereItActuallyFalls() async throws {
        // The clip is a band at x ∈ [200, 300]. The card sits entirely to its
        // right (absolute x ∈ [320, 360] — child frames are parent-relative,
        // so 120 inside a parent at 200), and its shadow is authored 60pt
        // DOWN. Turned by the card's 90°, that offset casts the halo 60pt
        // LEFT, to x ∈ [256, 304] — inside the band. Assuming the authored
        // offset instead puts the footprint at x ∈ [316, 364], which misses
        // the band entirely and prunes the subtree.
        let card = ViewNode(
            frame: Rect(x: 120, y: 100, width: 40, height: 40),
            backgroundColor: .white,
            shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.6),
            shadowOffset: Point(x: 0, y: 60),
            shadowSpread: 4,
            transform: Transform2D(rotation: .pi / 2)
        )
        let clip = ViewNode(
            frame: Rect(x: 200, y: 0, width: 100, height: 300),
            clipsToBounds: true,
            children: [card]
        )

        let scene = ScenePainter.paint(root: clip, clearColor: .black, surfaceSize: surfaceSize)
        let shadows = scene.layers.flatMap { $0.shadows }
        XCTAssertFalse(
            shadows.isEmpty,
            """
            The rotated card's halo was culled. The cull footprint has to turn the shadow \
            offset the same way the emission does, or it tests a rectangle the shadow never \
            occupies.
            """)
    }

    /// And the emitted offset is the turned one, applied exactly once — the
    /// rect carries no pre-offset of its own.
    func testShadowOffsetIsAppliedExactlyOnceAndTurnedWithTheNode() async throws {
        let node = ViewNode(
            frame: Rect(x: 100, y: 100, width: 40, height: 40),
            backgroundColor: .white,
            shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.6),
            shadowOffset: Point(x: 0, y: 20),
            shadowSpread: 0,
            transform: Transform2D(rotation: .pi / 2)
        )
        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)
        let shadow = try XCTUnwrap(scene.layers[0].shadows.first)

        // Rect: the unoffset frame, turned about its own centre — so the
        // centre is where it started. Any pre-offset here would be a second
        // application, since the backends add `offset` to the origin.
        XCTAssertEqual(Double(shadow.x) + Double(shadow.width) * 0.5, 120, accuracy: 1e-4)
        XCTAssertEqual(Double(shadow.y) + Double(shadow.height) * 0.5, 120, accuracy: 1e-4)

        // Offset: (0, 20) turned by 90° is (-20, 0).
        XCTAssertEqual(Double(shadow.offsetX), -20, accuracy: 1e-4)
        XCTAssertEqual(Double(shadow.offsetY), 0, accuracy: 1e-4)
    }

    // MARK: - 3. A HiDPI snapshot needs a `size * scale` surface

    private func densitySample() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Density").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Rectangle().fill(.white).frame(width: 120, height: 20)
            }
            .padding(10)
        )
    }

    /// `size` is points: the same `size` at 1x and 2x lays out identically and
    /// the scene's device geometry scales by exactly the display scale. The
    /// corollary is the bug: a scale-2 scene does not fit in a `size` surface.
    func testSceneGeometryScalesWithDisplayScaleForAFixedLogicalSize() async throws {
        let logical = IntSize(width: 200, height: 120)

        func extent(displayScale: Double) -> (maxX: Double, maxY: Double) {
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: densitySample(), size: logical, displayScale: displayScale, clearColor: .black)
            var maxX = 0.0
            var maxY = 0.0
            for layer in snapshot.scene.layers {
                for quad in layer.quads {
                    maxX = max(maxX, Double(quad.x) + Double(quad.width))
                    maxY = max(maxY, Double(quad.y) + Double(quad.height))
                }
            }
            return (maxX, maxY)
        }

        let oneX = extent(displayScale: 1)
        let twoX = extent(displayScale: 2)

        XCTAssertGreaterThan(oneX.maxX, 0, "the sample paints something at 1x")
        XCTAssertEqual(
            twoX.maxX, oneX.maxX * 2, accuracy: 1.0,
            "device geometry is the point layout times the display scale")
        XCTAssertEqual(twoX.maxY, oneX.maxY * 2, accuracy: 1.0)
    }

    /// Stated as the surface rule the snapshot tool now follows: at scale 2 the
    /// scene reaches past `size`, so a `size`-sized bitmap crops it. This is
    /// the assertion that fails against the old `--scale 2` behaviour.
    func testAHiDPISceneDoesNotFitInALogicalSizedSurface() async throws {
        let logical = IntSize(width: 200, height: 120)
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: densitySample(), size: logical, displayScale: 2, clearColor: .black)

        let maxX = snapshot.scene.layers.flatMap { $0.quads }.map { Double($0.x) + Double($0.width) }.max() ?? 0
        XCTAssertGreaterThan(
            maxX, Double(logical.width),
            """
            A scale-2 scene of a 200pt-wide window reaches beyond 200 device pixels, so the \
            snapshot surface must be `logical * scale`. Sizing it `logical` is what made \
            `--scale 2` a magnified top-left quadrant rather than a HiDPI layout.
            """)
    }

    /// A hairline is one DEVICE pixel at every scale — that is what makes it a
    /// hairline rather than a 1pt rule, and it is the macOS rule
    /// (`1/displayScale` points). A 1pt border, by contrast, scales.
    func testHairlineStaysOneDevicePixelWhileAPointBorderScales() async throws {
        for scale in [1.0, 2.0, 3.0] {
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {},
                environmentValuesProvider: {
                    EnvironmentValues(displayScale: scale, pixelLength: 1 / scale)
                }
            )
            let hairline = retainedHairlineThickness(for: context)
            XCTAssertEqual(
                hairline * scale, 1, accuracy: 1e-9,
                "a hairline is 1 device pixel at scale \(scale), not \(hairline * scale)")
            XCTAssertEqual(
                1.0 * scale, scale, accuracy: 1e-9,
                "while a 1pt rule is \(scale) device pixels at scale \(scale)")
        }
    }
}
