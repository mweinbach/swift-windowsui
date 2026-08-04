import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// E6-TEXT. Text under a transform is laid out in the node's *local* space and
/// the finished glyph run is scaled — the way SwiftUI/CoreAnimation does it.
///
/// The painter used to hand the already-transformed rect to the text layout as
/// its `maxWidth` while leaving the font size alone, so a `scaleEffect`
/// re-broke and re-truncated the string: a 2x label wrapped at twice the
/// character count, and a button pressed to `ControlAnimationStyle.pressedScale`
/// (0.97) re-fitted its own title into a box 3% narrower and ellipsized it.
/// SwiftUI never re-flows under a transform; the run is a rendered thing that
/// gets scaled.
@MainActor
final class ScaledTextLayoutTests: XCTestCase {

    /// Large enough that a 2x label still lands inside it — a glyph outside the
    /// surface is culled, and a culled glyph would make every count in here
    /// agree for the wrong reason.
    private let surfaceSize = Size(width: 900, height: 700)

    override func setUp() async throws {
        NativeGlyphAtlas.shared.resetForTesting()
    }

    /// The width the string actually occupies, through the same measurement
    /// `ViewNode` lays out with. A label box exactly this wide is the case the
    /// press bug lived in: no tolerance at all, so 3% off the width truncates.
    private func measuredWidth(_ text: String, style: PixelTextStyle) throws -> Double {
        let system = WindowTextSystem()
        let size = try XCTUnwrap(
            system.measure(text, style: style, maxWidth: nil, scaleFactor: 1),
            "DirectWrite measured the string")
        return size.width
    }

    private func style(
        lines: Int?,
        alignment: TextHorizontalAlignment = .leading,
        breakMode: TextLineBreakMode = .truncateTail
    ) -> PixelTextStyle {
        PixelTextStyle(
            color: .white,
            scale: 2,
            alignment: alignment,
            verticalAlignment: .top,
            letterSpacing: 1,
            lineSpacing: 2,
            insets: .zero,
            fontFamily: "Segoe UI",
            nativeFontSize: 13,
            weight: .regular,
            lineBreakMode: breakMode,
            maximumNumberOfLines: lines
        )
    }

    private func glyphs(_ node: ViewNode, displayScale: Double = 1.0) -> [GlyphPrimitive] {
        let scene = ScenePainter.paint(
            root: node, clearColor: .black, surfaceSize: surfaceSize, displayScale: displayScale)
        return scene.layers[0].glyphs + scene.layers[0].pixelGlyphs
    }

    /// Glyph counts per painted line, top to bottom. Two runs with the same
    /// line breaks produce the same list whatever scale they are drawn at.
    private func lineGlyphCounts(_ glyphs: [GlyphPrimitive]) -> [Int] {
        var buckets: [(y: Double, count: Int)] = []
        for glyph in glyphs.sorted(by: { $0.screenY < $1.screenY }) {
            let y = Double(glyph.screenY)
            // A line's cells share a baseline but not an ink top; bucket on a
            // tolerance of half the cell height so ascenders and descenders
            // stay together.
            let tolerance = max(Double(glyph.screenH), 1)
            if let index = buckets.indices.last, abs(buckets[index].y - y) <= tolerance {
                buckets[index].count += 1
            } else {
                buckets.append((y: y, count: 1))
            }
        }
        return buckets.map(\.count)
    }

    private func span(_ glyphs: [GlyphPrimitive]) -> Rect {
        guard let first = glyphs.first else { return .zero }
        var minX = Double(first.screenX)
        var minY = Double(first.screenY)
        var maxX = Double(first.screenX + first.screenW)
        var maxY = Double(first.screenY + first.screenH)
        for glyph in glyphs.dropFirst() {
            minX = min(minX, Double(glyph.screenX))
            minY = min(minY, Double(glyph.screenY))
            maxX = max(maxX, Double(glyph.screenX + glyph.screenW))
            maxY = max(maxY, Double(glyph.screenY + glyph.screenH))
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func label(
        _ text: String,
        frame: Rect,
        style: PixelTextStyle,
        transform: Transform2D = .identity
    ) -> ViewNode {
        ViewNode(frame: frame, text: text, textStyle: style, transform: transform)
    }

    // MARK: - Press

    /// The workaround this replaces: a segmented control's titles were given
    /// centring headroom because a pressed segment re-fitted its label to a
    /// box 3% narrower and ellipsized it. Every other control label had no
    /// such headroom. A press is a transform; it must not touch the run.
    func testAPressedLabelKeepsEveryGlyphOfItsUnpressedSelf() async throws {
        let text = "Continue Without Saving"
        let textStyle = style(lines: 1)
        // The segment cell is the width of its own title, so the press has
        // nothing to eat into.
        let frame = Rect(x: 20, y: 20, width: try measuredWidth(text, style: textStyle).rounded(.up), height: 22)

        let idle = glyphs(label(text, frame: frame, style: textStyle))
        XCTAssertFalse(idle.isEmpty, "the unpressed label paints glyphs")

        // The claim below is only worth making while a box 3% narrower really
        // does truncate this string — which is exactly what the painter used
        // to hand the layout. Pin it, or the test passes for the wrong reason
        // the day the metrics move.
        let narrowed = Rect(
            x: frame.origin.x, y: frame.origin.y,
            width: frame.size.width * ControlAnimationStyle.pressedScale, height: frame.size.height)
        let refitted = glyphs(label(text, frame: narrowed, style: textStyle))
        XCTAssertNotEqual(
            refitted.count, idle.count,
            "a box 3% narrower must ellipsize this string, or the press claim is vacuous")

        let pressed = glyphs(
            label(
                text, frame: frame, style: textStyle,
                transform: Transform2D(
                    scaleX: ControlAnimationStyle.pressedScale, scaleY: ControlAnimationStyle.pressedScale)
            ))

        XCTAssertEqual(
            pressed.count, idle.count,
            "a 0.97 press re-fitted the title into a narrower box and ellipsized it")
        XCTAssertEqual(
            lineGlyphCounts(pressed), lineGlyphCounts(idle),
            "the pressed run has the unpressed run's line breaks")
    }

    /// The same statement for a wrapping label: the break points are the
    /// unpressed ones, scaled.
    func testAPressedMultilineLabelKeepsItsUnpressedBreaks() async throws {
        let text = "Move the selected items to the Trash without asking again"
        let frame = Rect(x: 20, y: 20, width: 170, height: 120)
        let textStyle = style(lines: 6)

        let idle = glyphs(label(text, frame: frame, style: textStyle))
        let pressed = glyphs(
            label(
                text, frame: frame, style: textStyle,
                transform: Transform2D(
                    scaleX: ControlAnimationStyle.pressedScale, scaleY: ControlAnimationStyle.pressedScale)
            ))

        XCTAssertEqual(
            lineGlyphCounts(pressed), lineGlyphCounts(idle),
            "a pressed paragraph re-wrapped at 97% of its own width")
    }

    // MARK: - scaleEffect

    /// `scaleEffect(2)` scales the rendered run: same breaks, twice the cell
    /// geometry. Before the fix the run was re-laid-out into a box twice as
    /// wide at the same font size, so a wrapped label collapsed onto fewer,
    /// longer lines.
    func testAScaledLabelKeepsItsBreaksAndDoublesItsCells() async throws {
        let text = "Move the selected items to the Trash without asking again"
        let frame = Rect(x: 100, y: 100, width: 170, height: 120)
        let textStyle = style(lines: 6)

        let unscaled = glyphs(label(text, frame: frame, style: textStyle))
        let scaled = glyphs(
            label(text, frame: frame, style: textStyle, transform: Transform2D(scaleX: 2, scaleY: 2)))

        // Same vacuity guard: the doubled *box* at an undoubled font size —
        // what the painter used to lay out against — really does re-wrap.
        let widened = Rect(
            x: frame.origin.x, y: frame.origin.y,
            width: frame.size.width * 2, height: frame.size.height * 2)
        XCTAssertNotEqual(
            lineGlyphCounts(glyphs(label(text, frame: widened, style: textStyle))), lineGlyphCounts(unscaled),
            "a box twice as wide must re-wrap this string, or the scale claim is vacuous")

        XCTAssertEqual(
            lineGlyphCounts(scaled), lineGlyphCounts(unscaled),
            "a 2x label re-wrapped to the transformed width instead of scaling its run")

        let unscaledSpan = span(unscaled)
        let scaledSpan = span(scaled)
        XCTAssertEqual(
            scaledSpan.size.width, unscaledSpan.size.width * 2, accuracy: max(unscaledSpan.size.width * 0.04, 2),
            "the scaled run spans twice the width")
        XCTAssertEqual(
            scaledSpan.size.height, unscaledSpan.size.height * 2, accuracy: max(unscaledSpan.size.height * 0.04, 2),
            "the scaled run spans twice the height")
        // The run is not centred in its box — it is leading-aligned and
        // narrower — so the statement is that the *node's* centre is the fixed
        // point of the scale, which is where a `scaleEffect` anchors.
        XCTAssertEqual(
            scaledSpan.midX, frame.midX + (unscaledSpan.midX - frame.midX) * 2, accuracy: 2,
            "the scale is anchored on the node's centre")
        XCTAssertEqual(
            scaledSpan.midY, frame.midY + (unscaledSpan.midY - frame.midY) * 2, accuracy: 2,
            "the scale is anchored on the node's centre")
    }

    /// A scaled glyph cell is a scaled cell: the cells grow with the scale.
    /// This is the "2x cell geometry" half of the statement, independent of
    /// where the run lands.
    func testScaledGlyphCellsGrowWithTheScale() async throws {
        let text = "Handgloves"
        let frame = Rect(x: 300, y: 300, width: 200, height: 60)
        let textStyle = style(lines: 1)

        let unscaled = glyphs(label(text, frame: frame, style: textStyle))
        let scaled = glyphs(
            label(text, frame: frame, style: textStyle, transform: Transform2D(scaleX: 2, scaleY: 2)))

        XCTAssertEqual(scaled.count, unscaled.count, "same run, same glyph count")
        let unscaledHeight = unscaled.map { Double($0.screenH) }.reduce(0, +) / Double(max(unscaled.count, 1))
        let scaledHeight = scaled.map { Double($0.screenH) }.reduce(0, +) / Double(max(scaled.count, 1))
        XCTAssertEqual(
            scaledHeight, unscaledHeight * 2, accuracy: unscaledHeight * 0.15,
            "the 2x run's cells are 2x tall")
    }

    // MARK: - Composition with rotation

    /// Rotation was lowered in WS-19 and already turns the run about the
    /// node's centre. Scale composes with it exactly: the turned-and-scaled
    /// run is the scaled run with every cell's centre turned a quarter circle
    /// about the node's centre, cell for cell, and the angle on the primitive.
    ///
    /// Stated against the *purely scaled* run rather than the unscaled one so
    /// the claim is about composition and nothing else; that the scaled run
    /// keeps the unscaled run's breaks is the test above.
    func testARotatedAndScaledLabelComposesBoth() async throws {
        let text = "Move the selected items to the Trash without asking again"
        let frame = Rect(x: 320, y: 260, width: 170, height: 110)
        let textStyle = style(lines: 6)
        let pivot = Point(x: frame.midX, y: frame.midY)

        let plain = glyphs(label(text, frame: frame, style: textStyle))
        let scaled = glyphs(
            label(text, frame: frame, style: textStyle, transform: Transform2D(scaleX: 1.5, scaleY: 1.5)))
        let turned = glyphs(
            label(
                text, frame: frame, style: textStyle,
                transform: Transform2D(scaleX: 1.5, scaleY: 1.5, rotation: .pi / 2)
            ))

        XCTAssertFalse(scaled.isEmpty, "the scaled run paints glyphs")
        XCTAssertEqual(
            turned.count, scaled.count,
            "a turned-and-scaled label re-flowed instead of composing the two placements")

        // Anchored against the *untransformed* run as well, so the claim is
        // not just that the two transformed paths agree with each other —
        // they used to agree by being wrong together.
        XCTAssertEqual(turned.count, plain.count, "the turned run is the untransformed run, placed")
        let meanHeight: ([GlyphPrimitive]) -> Double = { run in
            run.map { Double($0.screenH) }.reduce(0, +) / Double(max(run.count, 1))
        }
        XCTAssertEqual(
            meanHeight(turned), meanHeight(plain) * 1.5, accuracy: meanHeight(plain) * 0.15,
            "the turned run's cells carry the 1.5 scale")

        for (index, cell) in turned.enumerated() {
            let source = scaled[index]
            XCTAssertEqual(
                Double(cell.rotationRadians), .pi / 2, accuracy: 1e-4, "cell \(index) carries the angle")
            XCTAssertEqual(
                Double(cell.screenW), Double(source.screenW), accuracy: 0.01,
                "cell \(index) keeps its scaled width — the angle is on the primitive")
            XCTAssertEqual(
                Double(cell.screenH), Double(source.screenH), accuracy: 0.01, "cell \(index) keeps its scaled height")
            // A quarter turn about the pivot: (x, y) -> (px - (y - py), py + (x - px)).
            let sourceCentre = Point(
                x: Double(source.screenX) + Double(source.screenW) / 2,
                y: Double(source.screenY) + Double(source.screenH) / 2)
            let expected = Point(
                x: pivot.x - (sourceCentre.y - pivot.y),
                y: pivot.y + (sourceCentre.x - pivot.x))
            let actual = Point(
                x: Double(cell.screenX) + Double(cell.screenW) / 2,
                y: Double(cell.screenY) + Double(cell.screenH) / 2)
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.01, "cell \(index) turned about the node's centre — x")
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.01, "cell \(index) turned about the node's centre — y")
        }
    }

    // MARK: - Atlas cost

    /// The rung ladder that keeps scaled text crisp without one atlas
    /// rasterization per animation frame. The two facts that make the policy
    /// defensible, pinned: authored powers of two are exact, and the whole
    /// press range collapses onto the rung it started on.
    func testTheGlyphRasterLadderIsExactOnPowersOfTwoAndFlatUnderAPress() async throws {
        for scale in [0.25, 0.5, 1.0, 2.0, 4.0] {
            XCTAssertEqual(
                NativeGlyphAtlas.glyphRasterScale(for: scale), scale, accuracy: 1e-12,
                "an authored \(scale)x rasterizes at exactly \(scale)x")
        }

        // Everything a press spring visits stays on the 1x rung, so a pressed
        // control costs no atlas entries at all.
        for step in stride(from: ControlAnimationStyle.pressedScale, through: 1.0, by: 0.002) {
            XCTAssertEqual(
                NativeGlyphAtlas.glyphRasterScale(for: step), 1.0,
                "a press at \(step) rasterizes on the rung it already occupies")
        }

        // Neighbouring rungs are a 2^(1/8) ratio apart, so nothing is ever
        // resampled by more than ~4.4% in linear size.
        for step in stride(from: 0.2, through: 8.0, by: 0.01) {
            let rung = NativeGlyphAtlas.glyphRasterScale(for: step)
            XCTAssertLessThanOrEqual(
                abs(log2(step / rung)), 0.0626, "\(step) is within half a rung of \(rung)")
        }

        // Degenerate and out-of-range scales are clamped rather than trusted:
        // a 400px glyph is not worth rasterizing and a NaN is not a size.
        XCTAssertEqual(NativeGlyphAtlas.glyphRasterScale(for: 0), 1)
        XCTAssertEqual(NativeGlyphAtlas.glyphRasterScale(for: -2), 1)
        XCTAssertEqual(NativeGlyphAtlas.glyphRasterScale(for: .nan), 1)
        XCTAssertEqual(NativeGlyphAtlas.glyphRasterScale(for: 500), 8, accuracy: 1e-12)
        XCTAssertEqual(NativeGlyphAtlas.glyphRasterScale(for: 0.001), 0.125, accuracy: 1e-12)
    }

    /// The crispness half of the ladder: a 2x run is drawn from glyphs
    /// rasterized at 2x, not from the 1x atlas entries stretched. Observable
    /// without touching the atlas internals — a 2x raster is a different atlas
    /// cell, so painting a 2x run after a 1x one adds entries rather than
    /// reusing them.
    func testAScaledRunRasterizesAtItsOwnSize() async throws {
        let atlas = NativeGlyphAtlas(atlasWidth: 512, atlasHeight: 512)
        NativeGlyphAtlas.installForTesting(atlas)
        defer { NativeGlyphAtlas.restoreSharedForTesting() }

        let text = "Handgloves"
        let frame = Rect(x: 300, y: 300, width: 200, height: 60)
        let textStyle = style(lines: 1)

        _ = glyphs(label(text, frame: frame, style: textStyle))
        let afterUnscaled = atlas.cachedGlyphCount
        XCTAssertGreaterThan(afterUnscaled, 0, "the 1x run rasterized its glyphs")

        // Same string again at 1x: every glyph is already in the atlas.
        _ = glyphs(label(text, frame: frame, style: textStyle))
        XCTAssertEqual(atlas.cachedGlyphCount, afterUnscaled, "a repeated 1x run reuses its rasters")

        _ = glyphs(label(text, frame: frame, style: textStyle, transform: Transform2D(scaleX: 2, scaleY: 2)))
        XCTAssertGreaterThan(
            atlas.cachedGlyphCount, afterUnscaled,
            "the 2x run drew from stretched 1x rasters instead of rasterizing at 2x")

        // …and a press does not, because 0.97 is the 1x rung.
        let afterScaled = atlas.cachedGlyphCount
        _ = glyphs(
            label(
                text, frame: frame, style: textStyle,
                transform: Transform2D(
                    scaleX: ControlAnimationStyle.pressedScale, scaleY: ControlAnimationStyle.pressedScale)))
        XCTAssertEqual(
            atlas.cachedGlyphCount, afterScaled,
            "a pressed label rasterized a whole new size for a 3% change")
    }
}
