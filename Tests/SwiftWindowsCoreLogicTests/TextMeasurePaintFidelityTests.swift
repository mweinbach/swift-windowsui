import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Measure-vs-paint fidelity for native (DirectWrite) text at fractional
/// display scales. A background pill sized to the measured text width must
/// contain the painted glyphs: measured and painted line widths must agree
/// within ~1 physical pixel at every supported scale, for regular and bold.
@MainActor
final class TextMeasurePaintFidelityTests: XCTestCase {

    override func setUp() async throws {
        NativeGlyphAtlas.shared.resetForTesting()
    }

    private func makeStyle(weight: TextWeight, size: Double) -> PixelTextStyle {
        PixelTextStyle(
            color: .white,
            scale: 2,
            alignment: .leading,
            verticalAlignment: .top,
            letterSpacing: 1,
            lineSpacing: 2,
            insets: .zero,
            fontFamily: "Segoe UI",
            nativeFontSize: size,
            weight: weight,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )
    }

    private struct FidelitySample {
        var measuredLogicalWidth: Double
        var layoutLineWidth: Double
        var glyphAdvanceSpan: Double
        var paintedMinX: Double
        var paintedMaxX: Double
        var glyphCount: Int

        var measuredPhysicalWidth: Double
        var paintedPhysicalWidth: Double { paintedMaxX - paintedMinX }
    }

    /// Measures `text` through the same API `ViewNode.textContentSize` uses
    /// (`WindowTextSystem.measure`), then paints it through the real scene
    /// paint path (`ScenePainter` -> native glyph emission) and returns both
    /// widths in physical pixels.
    private func sample(
        text: String,
        style: PixelTextStyle,
        scale: Double
    ) -> FidelitySample? {
        let textSystem = WindowTextSystem()
        guard let measured = textSystem.measure(text, style: style, maxWidth: nil, scaleFactor: scale),
            let layout = textSystem.layout(text, style: style, maxWidth: nil, scaleFactor: scale),
            let line = layout.lines.first
        else {
            return nil
        }

        var advanceSpan = 0.0
        for glyph in line.glyphs {
            advanceSpan = max(advanceSpan, glyph.origin.x + glyph.advance)
        }

        // Slack keeps truncation from kicking in; leading alignment keeps the
        // text origin at x = 0 regardless of the extra room.
        let frameWidth = measured.width + 8
        let frameHeight = measured.height + 4
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: frameWidth, height: frameHeight),
            text: text,
            textStyle: style
        )
        let scene = ScenePainter.paint(
            root: node,
            clearColor: .black,
            surfaceSize: Size(width: frameWidth + 40, height: frameHeight + 20),
            displayScale: scale
        )

        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var glyphCount = 0
        for sceneLayer in scene.layers {
            for glyph in sceneLayer.glyphs {
                minX = min(minX, Double(glyph.screenX))
                maxX = max(maxX, Double(glyph.screenX + glyph.screenW))
                glyphCount += 1
            }
        }
        guard glyphCount > 0 else {
            return nil
        }

        return FidelitySample(
            measuredLogicalWidth: measured.width,
            layoutLineWidth: line.width,
            glyphAdvanceSpan: advanceSpan,
            paintedMinX: minX,
            paintedMaxX: maxX,
            glyphCount: glyphCount,
            measuredPhysicalWidth: measured.width * scale
        )
    }

    private func assertFidelity(
        text: String,
        weight: TextWeight,
        size: Double,
        scale: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let style = makeStyle(weight: weight, size: size)
        guard let sample = sample(text: text, style: style, scale: scale) else {
            XCTFail(
                "\(text) \(weight) @\(scale)x: native layout or glyph emission unavailable",
                file: file, line: line)
            return
        }

        let overhang = sample.paintedMaxX - sample.measuredPhysicalWidth
        // Measured width is advance-based, so the apples-to-apples painted
        // width is the glyph advance span (ink bounds are legitimately
        // narrower — trailing side bearings are not inked).
        let advanceSpanPhysical = sample.glyphAdvanceSpan * scale
        let widthDelta = advanceSpanPhysical - sample.measuredPhysicalWidth
        let details = """
            \(text) weight=\(weight) size=\(size) @\(scale)x: \
            measuredLogical=\(sample.measuredLogicalWidth) \
            measuredPhysical=\(sample.measuredPhysicalWidth) \
            layoutLineWidth=\(sample.layoutLineWidth) \
            advanceSpan=\(sample.glyphAdvanceSpan) \
            painted=[\(sample.paintedMinX), \(sample.paintedMaxX)] \
            paintedWidth=\(sample.paintedPhysicalWidth) \
            overhang=\(overhang) widthDelta=\(widthDelta) glyphs=\(sample.glyphCount)
            """

        // The painted ink must not spill past the measured width by more
        // than ~1 physical pixel (pill containment).
        XCTAssertLessThanOrEqual(
            overhang, 1.0,
            "painted text overhangs its measured width — \(details)",
            file: file, line: line)
        // And the advance-based widths must agree within ~1 physical pixel.
        XCTAssertLessThanOrEqual(
            abs(widthDelta), 2.0,
            "measured and painted widths disagree — \(details)",
            file: file, line: line)
    }

    func testBoldCaptionCycleModeAtFractionalScale() async {
        await MainActor.run {
            for scale in [1.0, 1.5, 2.0] {
                assertFidelity(text: "CYCLE MODE", weight: .bold, size: 12, scale: scale)
            }
        }
    }

    func testRegularAndBoldBodyTextAcrossScales() async {
        await MainActor.run {
            for scale in [1.0, 1.5, 2.0] {
                assertFidelity(text: "Dashboard settings", weight: .regular, size: 13, scale: scale)
                assertFidelity(text: "Dashboard settings", weight: .bold, size: 13, scale: scale)
            }
        }
    }

    func testLargeTitleAcrossScales() async {
        await MainActor.run {
            for scale in [1.0, 1.5, 2.0] {
                assertFidelity(text: "Performance", weight: .regular, size: 22, scale: scale)
                assertFidelity(text: "Performance", weight: .bold, size: 22, scale: scale)
            }
        }
    }

    // MARK: - Full WinSwiftUI construction (pill containment)

    /// The demo's pill button shape: bold rounded 12pt caption on a
    /// background that hugs the measured text size. The painted glyphs must
    /// stay inside the pill background at every scale.
    func testPillBackgroundContainsBoldCaptionGlyphs() async {
        await MainActor.run {
            for scale in [1.0, 1.5, 2.0] {
                let view =
                    VStack(alignment: .leading, spacing: 0) {
                        Text("CYCLE MODE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .frame(height: 38)
                            .background(Color(red: 1, green: 0, blue: 0, alpha: 1))
                    }
                    .padding(8)

                let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                    of: view,
                    size: IntSize(width: 400, height: 120),
                    displayScale: scale,
                    clearColor: .black
                )

                var glyphMinX = Double.greatestFiniteMagnitude
                var glyphMaxX = -Double.greatestFiniteMagnitude
                var glyphCount = 0
                var pill: (left: Double, right: Double)?
                for sceneLayer in snapshot.scene.layers {
                    for glyph in sceneLayer.glyphs {
                        glyphMinX = min(glyphMinX, Double(glyph.screenX))
                        glyphMaxX = max(glyphMaxX, Double(glyph.screenX + glyph.screenW))
                        glyphCount += 1
                    }
                    // The red background pill sized from the measured text.
                    for quad in sceneLayer.quads
                    where quad.startR == 1 && quad.startG == 0 && quad.startB == 0 && quad.startA == 1 {
                        let left = Double(quad.x)
                        let right = Double(quad.x + quad.width)
                        if let current = pill {
                            pill = (min(current.left, left), max(current.right, right))
                        } else {
                            pill = (left, right)
                        }
                    }
                }
                XCTAssertGreaterThan(glyphCount, 0, "@\(scale)x: native glyphs must paint")
                guard let pill else {
                    XCTFail("@\(scale)x: red pill background quad not found")
                    continue
                }

                let pillOverhang = glyphMaxX - pill.right
                let pillLeadingOverhang = pill.left - glyphMinX
                XCTAssertLessThanOrEqual(
                    pillOverhang, 1.0,
                    """
                    @\(scale)x: glyphs overhang the pill on the right — \
                    pill=[\(pill.left), \(pill.right)] painted=[\(glyphMinX), \(glyphMaxX)] \
                    overhang=\(pillOverhang)
                    """)
                XCTAssertLessThanOrEqual(
                    pillLeadingOverhang, 1.0,
                    "@\(scale)x: glyphs overhang the pill on the left by \(pillLeadingOverhang)px")
            }
        }
    }

    // MARK: - Real demo pill button

    private struct PillContainment {
        var glyphCount: Int
        var pillFound: Bool
        var overhang: Double
        var leadingOverhang: Double
        var glyphMinX: Double
        var glyphMaxX: Double
        var pillLeft: Double
        var pillRight: Double
    }

    /// Locates the demo caption glyphs and the pill surface quad (identified
    /// by its 38pt frame height) in a scene and measures containment.
    private func pillContainment(scene: GPUIScene, scale: Double) -> PillContainment {
        var glyphMinX = Double.greatestFiniteMagnitude
        var glyphMaxX = -Double.greatestFiniteMagnitude
        var glyphMinY = Double.greatestFiniteMagnitude
        var glyphMaxY = -Double.greatestFiniteMagnitude
        var glyphCount = 0
        for sceneLayer in scene.layers {
            for glyph in sceneLayer.glyphs {
                glyphMinX = min(glyphMinX, Double(glyph.screenX))
                glyphMaxX = max(glyphMaxX, Double(glyph.screenX + glyph.screenW))
                glyphMinY = min(glyphMinY, Double(glyph.screenY))
                glyphMaxY = max(glyphMaxY, Double(glyph.screenY + glyph.screenH))
                glyphCount += 1
            }
        }
        guard glyphCount > 0 else {
            return PillContainment(
                glyphCount: 0, pillFound: false, overhang: 0, leadingOverhang: 0,
                glyphMinX: 0, glyphMaxX: 0, pillLeft: 0, pillRight: 0)
        }

        let glyphCenterY = (glyphMinY + glyphMaxY) / 2
        var pill: (left: Double, right: Double)?
        for sceneLayer in scene.layers {
            for quad in sceneLayer.quads {
                let top = Double(quad.y)
                let bottom = Double(quad.y + quad.height)
                let height = bottom - top
                guard top <= glyphCenterY, bottom >= glyphCenterY,
                    height >= 38 * scale - 4, height <= 38 * scale + 8
                else { continue }
                let left = Double(quad.x)
                let right = Double(quad.x + quad.width)
                if let current = pill {
                    pill = (min(current.left, left), max(current.right, right))
                } else {
                    pill = (left, right)
                }
            }
        }
        guard let pill else {
            return PillContainment(
                glyphCount: glyphCount, pillFound: false, overhang: 0, leadingOverhang: 0,
                glyphMinX: glyphMinX, glyphMaxX: glyphMaxX, pillLeft: 0, pillRight: 0)
        }
        return PillContainment(
            glyphCount: glyphCount,
            pillFound: true,
            overhang: glyphMaxX - pill.right,
            leadingOverhang: pill.left - glyphMinX,
            glyphMinX: glyphMinX,
            glyphMaxX: glyphMaxX,
            pillLeft: pill.left,
            pillRight: pill.right
        )
    }

    private func assertPillContainment(
        scene: GPUIScene,
        scale: Double,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = pillContainment(scene: scene, scale: scale)
        XCTAssertGreaterThan(
            result.glyphCount, 0, "@\(scale)x \(context): native glyphs must paint",
            file: file, line: line)
        XCTAssertTrue(result.pillFound, "@\(scale)x \(context): pill surface quad not found", file: file, line: line)
        guard result.pillFound else { return }
        XCTAssertLessThanOrEqual(
            result.overhang, 1.0,
            """
            @\(scale)x \(context): caption glyphs overhang the demo pill — \
            pill=[\(result.pillLeft), \(result.pillRight)] \
            painted=[\(result.glyphMinX), \(result.glyphMaxX)] \
            overhang=\(result.overhang)
            """,
            file: file, line: line)
        XCTAssertLessThanOrEqual(
            result.leadingOverhang, 1.0,
            "@\(scale)x \(context): glyphs overhang the pill on the left by \(result.leadingOverhang)px",
            file: file, line: line)
    }

    private func demoPillView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DemoPillButton(
                "CYCLE MODE",
                colors: [DemoTheme.fieldTop, DemoTheme.fieldBottom],
                textColor: DemoTheme.primaryText
            ) {}
        }
        .padding(8)
    }

    /// The exact demo construction (`DemoPillButton` from SwiftWindowsDemo):
    /// bold rounded 12pt caption inside a gradient surface hugging the
    /// measured text.
    func testDemoPillButtonContainsCaptionGlyphs() async {
        await MainActor.run {
            for scale in [1.0, 1.5, 2.0] {
                let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                    of: demoPillView(),
                    size: IntSize(width: 400, height: 120),
                    displayScale: scale,
                    clearColor: .black
                )
                assertPillContainment(scene: snapshot.scene, scale: scale, context: "fresh render")
            }
        }
    }

    /// Same runtime, mid-session scale change (monitor move / DPI change):
    /// render at one scale, then switch displayScale and re-render. The
    /// WindowTextSystem layout cache and the shared glyph atlas both survive
    /// the transition — measured and painted widths must still agree.
    func testDemoPillButtonContainmentAfterScaleChange() async {
        await MainActor.run {
            for (initial, target) in [(1.0, 1.5), (1.5, 1.0), (1.0, 2.0), (2.0, 1.5)] as [(Double, Double)] {
                let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                    of: demoPillView(),
                    size: IntSize(width: 400, height: 120),
                    displayScale: initial,
                    clearColor: .black
                )
                assertPillContainment(scene: snapshot.scene, scale: initial, context: "initial render")

                snapshot.runtime.displayScale = target
                let rescaled = snapshot.runtime.renderScene(at: 1.0)
                assertPillContainment(
                    scene: rescaled, scale: target,
                    context: "after \(initial)->\(target) scale change")
            }
        }
    }

    /// The hero row construction from the demo dashboard: both pill buttons
    /// share an HStack with layout priorities, inside a fixed-width panel.
    /// Sweeping panel widths covers the constrained-measure regime.
    func testHeroPillRowContainmentAcrossPanelWidths() async {
        await MainActor.run {
            for scale in [1.0, 1.5] {
                for width in [760.0, 700.0, 620.0, 540.0, 460.0, 400.0] {
                    let view =
                        HStack(alignment: .center, spacing: 12) {
                            DemoPillButton(
                                "OPEN LAYOUT",
                                colors: [
                                    DemoTheme.fieldTop.opacity(0.94),
                                    DemoTheme.fieldBottom.opacity(0.70),
                                ]
                            ) {}
                            .layoutPriority(1)
                            DemoPillButton(
                                "CYCLE MODE",
                                colors: [DemoTheme.fieldTop, DemoTheme.fieldBottom],
                                textColor: DemoTheme.primaryText
                            ) {}
                            .layoutPriority(1)
                        }
                        .padding(18)
                        .frame(width: width, alignment: .leading)

                    let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                        of: view,
                        size: IntSize(width: Int32(width), height: 120),
                        displayScale: scale,
                        clearColor: .black
                    )
                    assertGlyphClustersContained(
                        scene: snapshot.scene, scale: scale,
                        context: "hero row width=\(width)")
                }
            }
        }
    }

    /// Splits the scene's glyphs into x-separated caption clusters and checks
    /// each cluster against the pill-height quad that overlaps it most.
    private func assertGlyphClustersContained(
        scene: GPUIScene,
        scale: Double,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        struct GlyphBox {
            var minX: Double
            var maxX: Double
            var minY: Double
            var maxY: Double
        }
        var boxes: [GlyphBox] = []
        for sceneLayer in scene.layers {
            for glyph in sceneLayer.glyphs {
                boxes.append(
                    GlyphBox(
                        minX: Double(glyph.screenX),
                        maxX: Double(glyph.screenX + glyph.screenW),
                        minY: Double(glyph.screenY),
                        maxY: Double(glyph.screenY + glyph.screenH)
                    ))
            }
        }
        XCTAssertFalse(boxes.isEmpty, "@\(scale)x \(context): native glyphs must paint", file: file, line: line)
        guard !boxes.isEmpty else { return }
        boxes.sort { $0.minX < $1.minX }

        var clusters: [(minX: Double, maxX: Double, centerY: Double)] = []
        var current = (minX: boxes[0].minX, maxX: boxes[0].maxX, minY: boxes[0].minY, maxY: boxes[0].maxY)
        for box in boxes.dropFirst() {
            if box.minX - current.maxX > 16 * scale {
                clusters.append((current.minX, current.maxX, (current.minY + current.maxY) / 2))
                current = (box.minX, box.maxX, box.minY, box.maxY)
            } else {
                current = (
                    min(current.minX, box.minX), max(current.maxX, box.maxX),
                    min(current.minY, box.minY), max(current.maxY, box.maxY)
                )
            }
        }
        clusters.append((current.minX, current.maxX, (current.minY + current.maxY) / 2))

        for cluster in clusters {
            var best: (left: Double, right: Double, overlap: Double)?
            for sceneLayer in scene.layers {
                for quad in sceneLayer.quads {
                    let top = Double(quad.y)
                    let bottom = Double(quad.y + quad.height)
                    let height = bottom - top
                    guard top <= cluster.centerY, bottom >= cluster.centerY,
                        height >= 38 * scale - 4, height <= 38 * scale + 8
                    else { continue }
                    let left = Double(quad.x)
                    let right = Double(quad.x + quad.width)
                    let overlap = min(right, cluster.maxX) - max(left, cluster.minX)
                    guard overlap > 0 else { continue }
                    if let current = best {
                        if overlap > current.overlap {
                            best = (left, right, overlap)
                        }
                    } else {
                        best = (left, right, overlap)
                    }
                }
            }
            guard let pill = best else {
                XCTFail("@\(scale)x \(context): no pill quad for caption cluster \(cluster)", file: file, line: line)
                continue
            }
            let overhang = cluster.maxX - pill.right
            XCTAssertLessThanOrEqual(
                overhang, 1.0,
                """
                @\(scale)x \(context): caption cluster overhangs its pill — \
                pill=[\(pill.left), \(pill.right)] cluster=[\(cluster.minX), \(cluster.maxX)] \
                overhang=\(overhang)
                """,
                file: file, line: line)
        }
    }

    /// The full live wiring: `WinSwiftUIWindowHost` with a surface at the
    /// given scale factor, exactly as a 150%/200% display presents it. The
    /// host sets `runtime.displayScale` from the surface, rebuilds, and
    /// renders through the scene path — the scene it hands to the batch
    /// renderer must keep the caption inside its pill.
    func testWindowHostSceneKeepsCaptionInsidePillAtFractionalScale() async {
        await MainActor.run {
            for scale in [1.0, 1.5, 2.0] {
                let pixelSize = IntSize(width: Int32(400 * scale), height: Int32(120 * scale))
                let surface = SurfaceDescriptor(
                    windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                    pixelSize: pixelSize,
                    scaleFactor: scale
                )
                let batchRenderer = FakeBatchRenderBackend()
                let config = WindowGroupConfiguration(
                    title: "Fidelity",
                    size: pixelSize,
                    clearColor: .black,
                    content: [AnyView(demoPillView())]
                )
                let host = WinSwiftUIWindowHost(
                    configuration: config,
                    renderer: FakeRenderBackend(),
                    batchRenderer: batchRenderer,
                    surfaceDescriptorProvider: { _ in surface }
                )
                let window = Win32Window(title: "Fidelity", clientSize: pixelSize)
                host.windowDidCreate(window)

                guard let scene = batchRenderer.renderedScenes.first else {
                    XCTFail("@\(scale)x: window host did not render a scene")
                    continue
                }
                assertPillContainment(scene: scene, scale: scale, context: "window host")
            }
        }
    }
}
