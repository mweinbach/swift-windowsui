import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsLayout

import SwiftWindowsPlatform

import XCTest

@testable import SwiftWindowsUI

/// Lays out `root` with one render pass.
@MainActor
private func renderStackFloorProbe(_ root: ViewNode, displayScale: Double = 1) {
    let runtime = RetainedViewRuntime(root: root)
    runtime.displayScale = displayScale
    _ = runtime.renderFrame()
}

@MainActor
private func makeSingleLineCaptionNode() -> ViewNode {
    ViewNode(text: "CONTROL CENTER")
}

@MainActor
private func makeWrappingSubtitleNode() -> ViewNode {
    let node = ViewNode(text: "RESPONSIVE COMPOSITION AND PANEL STRUCTURE")
    node.textStyle.lineBreakMode = .wrap
    return node
}

@MainActor
private func makeNativeWrappingSubtitleNode() -> ViewNode {
    let node = makeWrappingSubtitleNode()
    node.textStyle.nativeFontSize = 13
    return node
}

@MainActor
private func wrappedSubtitleHeight(width: Double = 120, displayScale: Double = 1) -> Double {
    let text = makeNativeWrappingSubtitleNode()
    let root = ViewNode(
        frame: Rect(x: 0, y: 0, width: width, height: 500),
        layoutMode: .stack(.vertical(alignment: .leading)),
        children: [text]
    )
    renderStackFloorProbe(root, displayScale: displayScale)
    return text.resolvedFrame.height
}

/// Pins the stack shrink floor: text-bearing nodes keep their measured
/// main-axis size when a stack runs out of room, while padding, spacers,
/// and flexible siblings absorb the squeeze first (and content overflows
/// rather than crushing text below its measured size).
final class StackTextShrinkFloorTests: XCTestCase {

    func testWrappingTextMeasuresAtItsPreferredWidthBeforePlacingTheNextRow() async {
        await MainActor.run {
            for scale in [1.0, 1.25, 1.5, 1.75, 2.0] {
                let wrappedHeight = wrappedSubtitleHeight(displayScale: scale)

                let text = makeNativeWrappingSubtitleNode()
                text.preferredSize = Size(width: 120, height: 0)
                let nextRow = makeSingleLineCaptionNode()
                let root = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 500, height: 500),
                    layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                    children: [text, nextRow]
                )
                renderStackFloorProbe(root, displayScale: scale)

                XCTAssertGreaterThan(wrappedHeight, 30, "The fixture must wrap at \(scale)x")
                XCTAssertEqual(text.resolvedFrame.width, 120, accuracy: 0.001)
                XCTAssertEqual(
                    text.resolvedFrame.height, wrappedHeight, accuracy: 0.001,
                    "A paragraph must measure at its own width, not its wider parent's proposal at \(scale)x")
                XCTAssertEqual(
                    nextRow.resolvedFrame.minY, wrappedHeight + 8, accuracy: 0.001,
                    "The following row must start after every wrapped line at \(scale)x")
            }
        }
    }

    func testFixedWidthPaddedContainerIncludesEveryWrappedLineInItsHeight() async {
        await MainActor.run {
            for scale in [1.0, 1.25, 1.5, 1.75, 2.0] {
                let wrappedHeight = wrappedSubtitleHeight(displayScale: scale)

                let text = makeNativeWrappingSubtitleNode()
                let container = ViewNode(
                    layoutMode: .stack(
                        .vertical(
                            padding: EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10),
                            alignment: .leading)),
                    preferredSize: Size(width: 140, height: 0),
                    children: [text]
                )
                let nextRow = makeSingleLineCaptionNode()
                let root = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 500, height: 500),
                    layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                    children: [container, nextRow]
                )
                renderStackFloorProbe(root, displayScale: scale)

                XCTAssertGreaterThan(wrappedHeight, 30, "The fixture must wrap at \(scale)x")
                XCTAssertEqual(container.resolvedFrame.width, 140, accuracy: 0.001)
                XCTAssertEqual(text.resolvedFrame.height, wrappedHeight, accuracy: 0.001)
                XCTAssertEqual(
                    container.resolvedFrame.height, wrappedHeight + 8, accuracy: 0.001,
                    "A fixed-width container must propagate its inner width during measurement at \(scale)x")
                XCTAssertEqual(nextRow.resolvedFrame.minY, wrappedHeight + 16, accuracy: 0.001)
            }
        }
    }

    func testHorizontalWrappingRowRemeasuresBeforePlacingTheNextRow() async {
        await MainActor.run {
            for scale in [1.0, 1.25, 1.5, 1.75, 2.0] {
                let wrappedHeight = wrappedSubtitleHeight(displayScale: scale)
                let text = makeNativeWrappingSubtitleNode()
                let row = ViewNode(
                    layoutMode: .stack(.horizontal(alignment: .leading)), children: [text])
                let nextRow = makeSingleLineCaptionNode()
                let root = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 120, height: 500),
                    layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                    children: [row, nextRow]
                )
                renderStackFloorProbe(root, displayScale: scale)

                XCTAssertGreaterThan(wrappedHeight, 30, "The fixture must wrap at \(scale)x")
                XCTAssertEqual(row.resolvedFrame.width, 120, accuracy: 0.001)
                XCTAssertEqual(row.resolvedFrame.height, wrappedHeight, accuracy: 0.001)
                XCTAssertEqual(text.resolvedFrame.height, wrappedHeight, accuracy: 0.001)
                XCTAssertEqual(
                    nextRow.resolvedFrame.minY, wrappedHeight + 8, accuracy: 0.001,
                    "A horizontal row must report its wrapped height to the parent at \(scale)x")
            }
        }
    }

    func testWrappingLabelsKeepTheirAllocatedWidthsAndHeightUnderVerticalPressure() async {
        await MainActor.run {
            let wrappedHeight = wrappedSubtitleHeight()
            let first = makeNativeWrappingSubtitleNode()
            let second = makeNativeWrappingSubtitleNode()
            let row = ViewNode(
                layoutMode: .stack(.horizontal(spacing: 8, alignment: .leading)), children: [first, second])
            let flexibleSibling = ViewNode(
                backgroundColor: .white, preferredSize: Size(width: 100, height: 300))
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 248, height: wrappedHeight + 20),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                children: [row, flexibleSibling]
            )
            renderStackFloorProbe(root)

            XCTAssertGreaterThan(wrappedHeight, 30)
            XCTAssertEqual(first.resolvedFrame.width, 120, accuracy: 0.001)
            XCTAssertEqual(second.resolvedFrame.width, 120, accuracy: 0.001)
            XCTAssertEqual(second.resolvedFrame.maxX, 248, accuracy: 0.001)
            XCTAssertEqual(first.resolvedFrame.height, wrappedHeight, accuracy: 0.001)
            XCTAssertEqual(second.resolvedFrame.height, wrappedHeight, accuracy: 0.001)
            XCTAssertEqual(
                row.resolvedFrame.height, wrappedHeight, accuracy: 0.001,
                "A row's vertical floor must use its allocated widths, not the unwrapped ideal widths")
            XCTAssertEqual(flexibleSibling.resolvedFrame.height, 12, accuracy: 0.001)
        }
    }

    func testEqualWidthColumnsIncludeTheirWrappedTextInTheRowHeight() async {
        await MainActor.run {
            let wrappedHeight = wrappedSubtitleHeight()
            let texts = [makeNativeWrappingSubtitleNode(), makeNativeWrappingSubtitleNode()]
            let columns = texts.map { text in
                ViewNode(
                    layoutMode: .stack(
                        .vertical(
                            padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8),
                            alignment: .leading)),
                    children: [text])
            }
            let row = ViewNode(
                layoutMode: .stack(.horizontal(spacing: 8, alignment: .leading, distribution: .fillEqually)),
                children: columns)
            let nextRow = makeSingleLineCaptionNode()
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 280, height: 500),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                children: [row, nextRow]
            )
            renderStackFloorProbe(root)

            for (column, text) in zip(columns, texts) {
                XCTAssertEqual(column.resolvedFrame.width, 136, accuracy: 0.001)
                XCTAssertEqual(column.resolvedFrame.height, wrappedHeight + 8, accuracy: 0.001)
                XCTAssertEqual(text.resolvedFrame.height, wrappedHeight, accuracy: 0.001)
            }
            XCTAssertEqual(row.resolvedFrame.height, wrappedHeight + 8, accuracy: 0.001)
            XCTAssertEqual(nextRow.resolvedFrame.minY, wrappedHeight + 16, accuracy: 0.001)
        }
    }

    func testHorizontalFixedSizeWrapperKeepsItsWidthBesideWrappingText() async {
        await MainActor.run {
            let fixedText = ViewNode(text: "FIXED")
            fixedText.textStyle.lineBreakMode = .wrap
            let fixed = ViewNode(
                layoutMode: .stack(
                    .vertical(padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))),
                fixedSizeAxes: FixedSizeAxes(horizontal: true, vertical: false),
                children: [fixedText])
            let idealWidth = fixed.intrinsicContentSize().width
            let wrappingText = makeNativeWrappingSubtitleNode()
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: idealWidth + 88, height: 200),
                layoutMode: .stack(.horizontal(spacing: 8, alignment: .leading)),
                children: [fixed, wrappingText])
            renderStackFloorProbe(root)

            XCTAssertEqual(
                fixed.resolvedFrame.width, idealWidth, accuracy: 0.001,
                "fixedSize on a wrapper protects the subtree even when its text can wrap")
            XCTAssertEqual(wrappingText.resolvedFrame.width, 80, accuracy: 0.001)
            XCTAssertEqual(wrappingText.resolvedFrame.maxX, root.resolvedFrame.width, accuracy: 0.001)
        }
    }

    func testGreedyPreferredWidthMeasuresAtTheAcceptedProposal() async {
        await MainActor.run {
            let expectedHeight = wrappedSubtitleHeight(width: 500)
            let text = makeNativeWrappingSubtitleNode()
            text.preferredSize = Size(width: 120, height: 0)
            text.layoutFillAxes = LayoutFillAxes(horizontal: true, vertical: false)
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 500, height: 500),
                layoutMode: .stack(.vertical(alignment: .leading)),
                children: [text])
            renderStackFloorProbe(root)

            XCTAssertEqual(text.resolvedFrame.width, 500, accuracy: 0.001)
            XCTAssertEqual(
                text.resolvedFrame.height, expectedHeight, accuracy: 0.001,
                "A greedy node's preferred width is an ideal; content measures at its accepted wider proposal")
        }
    }

    /// A squeezed vertical stack must leave a single-line text child at
    /// exactly the height it measures in an unsqueezed stack, taking the
    /// whole deficit out of the flexible (non-text) sibling.
    func testVerticalStackSqueezeKeepsSingleLineTextAtMeasuredHeight() async {
        await MainActor.run {
            let referenceText = makeSingleLineCaptionNode()
            let referenceRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: 400),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                isHitTestVisible: false,
                children: [
                    referenceText,
                    ViewNode(backgroundColor: .white, preferredSize: Size(width: 100, height: 200)),
                ]
            )
            renderStackFloorProbe(referenceRoot)
            let naturalTextHeight = referenceText.resolvedFrame.size.height
            XCTAssertGreaterThan(naturalTextHeight, 0)

            let squeezedText = makeSingleLineCaptionNode()
            let flexibleSibling = ViewNode(
                backgroundColor: .white, preferredSize: Size(width: 100, height: 200))
            let squeezedRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: naturalTextHeight + 20),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                isHitTestVisible: false,
                children: [squeezedText, flexibleSibling]
            )
            renderStackFloorProbe(squeezedRoot)

            XCTAssertEqual(
                squeezedText.resolvedFrame.size.height, naturalTextHeight, accuracy: 0.001,
                "Text must not shrink below its measured height in a squeezed stack")
            XCTAssertEqual(
                flexibleSibling.resolvedFrame.size.height, 12, accuracy: 0.001,
                "The flexible sibling should absorb the entire deficit")
        }
    }

    /// A wrapped multi-line text keeps every line: its squeezed height
    /// matches the height it measures with room to spare at the same
    /// width.
    func testVerticalStackSqueezeKeepsMultiLineTextFullyVisible() async {
        await MainActor.run {
            let referenceText = makeWrappingSubtitleNode()
            let referenceRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 600),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                isHitTestVisible: false,
                children: [referenceText]
            )
            renderStackFloorProbe(referenceRoot)
            let wrappedHeight = referenceText.resolvedFrame.size.height

            let singleLineText = makeSingleLineCaptionNode()
            let singleLineRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 600),
                layoutMode: .stack(.vertical(alignment: .leading)),
                isHitTestVisible: false,
                children: [singleLineText]
            )
            renderStackFloorProbe(singleLineRoot)
            let singleLineHeight = singleLineText.resolvedFrame.size.height
            XCTAssertGreaterThan(
                wrappedHeight, singleLineHeight + 1,
                "The long subtitle must wrap to multiple lines at width 120 for this test to be meaningful")

            let squeezedText = makeWrappingSubtitleNode()
            let flexibleSibling = ViewNode(
                backgroundColor: .white, preferredSize: Size(width: 100, height: 300))
            let squeezedRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: wrappedHeight + 16),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                isHitTestVisible: false,
                children: [squeezedText, flexibleSibling]
            )
            renderStackFloorProbe(squeezedRoot)

            XCTAssertEqual(
                squeezedText.resolvedFrame.size.height, wrappedHeight, accuracy: 0.001,
                "Multi-line text must keep all of its wrapped lines under a squeeze")
        }
    }

    /// Sacrifice order: a priority -1 track gives up its extent first, and
    /// the text child still stops at its floor once the track is gone.
    func testShrinkSacrificesNegativePriorityTrackBeforeTextFloor() async {
        await MainActor.run {
            let referenceText = makeSingleLineCaptionNode()
            let referenceRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: 400),
                layoutMode: .stack(.vertical(alignment: .leading)),
                isHitTestVisible: false,
                children: [referenceText]
            )
            renderStackFloorProbe(referenceRoot)
            let naturalTextHeight = referenceText.resolvedFrame.size.height

            let track = ViewNode(
                backgroundColor: .white,
                preferredSize: Size(width: 100, height: 40),
                layoutPriority: -1
            )
            let text = makeSingleLineCaptionNode()
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: naturalTextHeight + 10),
                layoutMode: .stack(.vertical(alignment: .leading)),
                isHitTestVisible: false,
                children: [track, text]
            )
            renderStackFloorProbe(root)

            XCTAssertEqual(
                track.resolvedFrame.size.height, 10, accuracy: 0.001,
                "The negative-priority track should be sacrificed down to the remaining space")
            XCTAssertEqual(
                text.resolvedFrame.size.height, naturalTextHeight, accuracy: 0.001,
                "Text keeps its measured height once the track has absorbed the deficit")
        }
    }

    /// When even the floors do not fit, the stack overflows instead of
    /// crushing text: both labels keep their measured height and the
    /// second one is laid out past the stack's bounds.
    func testSqueezeBeyondFloorsOverflowsInsteadOfCrushingText() async {
        await MainActor.run {
            let referenceText = makeSingleLineCaptionNode()
            let referenceRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: 400),
                layoutMode: .stack(.vertical(alignment: .leading)),
                isHitTestVisible: false,
                children: [referenceText]
            )
            renderStackFloorProbe(referenceRoot)
            let naturalTextHeight = referenceText.resolvedFrame.size.height

            let first = makeSingleLineCaptionNode()
            let second = makeSingleLineCaptionNode()
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: naturalTextHeight + 4),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                isHitTestVisible: false,
                children: [first, second]
            )
            renderStackFloorProbe(root)

            XCTAssertEqual(first.resolvedFrame.size.height, naturalTextHeight, accuracy: 0.001)
            XCTAssertEqual(second.resolvedFrame.size.height, naturalTextHeight, accuracy: 0.001)
            XCTAssertEqual(
                second.resolvedFrame.origin.y, naturalTextHeight + 8, accuracy: 0.001,
                "The overflowing label keeps its layout position instead of being crushed")
        }
    }

    /// A labeled container (text wrapped in padding, capsule-style) stops
    /// shrinking at the sum that keeps its text readable: the padding is
    /// compressed away before the text itself loses a single point.
    func testSqueezedLabeledContainerCompressesPaddingBeforeText() async {
        await MainActor.run {
            let referenceText = makeSingleLineCaptionNode()
            let referenceRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: 400),
                layoutMode: .stack(.vertical(alignment: .stretch)),
                isHitTestVisible: false,
                children: [referenceText]
            )
            renderStackFloorProbe(referenceRoot)
            let naturalTextHeight = referenceText.resolvedFrame.size.height

            let capsuleText = makeSingleLineCaptionNode()
            let capsule = ViewNode(
                layoutMode: .stack(
                    .vertical(
                        padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10),
                        alignment: .stretch)),
                isHitTestVisible: false,
                children: [capsuleText]
            )
            let flexibleSibling = ViewNode(
                backgroundColor: .white, preferredSize: Size(width: 100, height: 200))
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: naturalTextHeight + 8),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                isHitTestVisible: false,
                children: [capsule, flexibleSibling]
            )
            renderStackFloorProbe(root)

            XCTAssertEqual(
                capsuleText.resolvedFrame.size.height, naturalTextHeight, accuracy: 0.001,
                "The capsule's text must keep its measured height")
            XCTAssertEqual(
                capsule.resolvedFrame.size.height, naturalTextHeight, accuracy: 0.001,
                "The capsule compresses its padding down to the text instead of crushing it")
        }
    }

    /// Cross axis: a squeezed horizontal stack leaves a text child at its
    /// measured (single-line) width and takes the deficit out of the
    /// flexible sibling.
    func testHorizontalStackSqueezeKeepsTextMeasuredWidth() async {
        await MainActor.run {
            let referenceText = makeSingleLineCaptionNode()
            let referenceRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 600, height: 40),
                layoutMode: .stack(.horizontal(spacing: 8, alignment: .center)),
                isHitTestVisible: false,
                children: [referenceText]
            )
            renderStackFloorProbe(referenceRoot)
            let naturalTextWidth = referenceText.resolvedFrame.size.width
            XCTAssertGreaterThan(naturalTextWidth, 0)

            let squeezedText = makeSingleLineCaptionNode()
            let flexibleSibling = ViewNode(
                backgroundColor: .white, preferredSize: Size(width: 300, height: 20))
            let squeezedRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: naturalTextWidth + 20, height: 40),
                layoutMode: .stack(.horizontal(spacing: 8, alignment: .center)),
                isHitTestVisible: false,
                children: [squeezedText, flexibleSibling]
            )
            renderStackFloorProbe(squeezedRoot)

            XCTAssertEqual(
                squeezedText.resolvedFrame.size.width, naturalTextWidth, accuracy: 0.001,
                "Text must not shrink below its measured width in a squeezed horizontal stack")
            XCTAssertEqual(
                flexibleSibling.resolvedFrame.size.width, 12, accuracy: 0.001,
                "The flexible sibling should absorb the entire deficit")
        }
    }

    /// Non-text children keep the historical behavior: no floor, so a
    /// squeeze is still distributed proportionally across them.
    func testNonTextChildrenShrinkProportionallyAsBefore() async {
        await MainActor.run {
            let first = ViewNode(backgroundColor: .white, preferredSize: Size(width: 100, height: 50))
            let second = ViewNode(backgroundColor: .black, preferredSize: Size(width: 100, height: 50))
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: 60),
                layoutMode: .stack(.vertical(alignment: .leading)),
                isHitTestVisible: false,
                children: [first, second]
            )
            renderStackFloorProbe(root)

            XCTAssertEqual(first.resolvedFrame.size.height, 30, accuracy: 0.001)
            XCTAssertEqual(second.resolvedFrame.size.height, 30, accuracy: 0.001)
        }
    }

    /// A floor protects text from sibling pressure, never from a
    /// container that is smaller than the child alone: a lone oversized
    /// text in an undersized box fills the box instead of poking out.
    func testFloorIsCappedByTheContainersOwnExtent() async {
        await MainActor.run {
            let text = makeSingleLineCaptionNode()
            let referenceRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: 400),
                layoutMode: .stack(.vertical(alignment: .leading)),
                isHitTestVisible: false,
                children: [text]
            )
            renderStackFloorProbe(referenceRoot)
            let naturalTextHeight = text.resolvedFrame.size.height
            XCTAssertGreaterThan(naturalTextHeight, 8)

            let squeezedText = makeSingleLineCaptionNode()
            let sibling = ViewNode(
                backgroundColor: .white, preferredSize: Size(width: 100, height: 100))
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: 8),
                layoutMode: .stack(.vertical(alignment: .leading)),
                isHitTestVisible: false,
                children: [squeezedText, sibling]
            )
            renderStackFloorProbe(root)

            XCTAssertLessThanOrEqual(
                squeezedText.resolvedFrame.size.height, 8.001,
                "A floor never exceeds the extent the container itself can offer")
        }
    }

    /// A `clipsToBounds` container absorbs squeeze instead of propagating
    /// its content's floor: clipping is the declared cut boundary, so a
    /// pinned frame stays contained and the interior clips.
    func testClippingContainerAbsorbsSqueezeWithoutPropagatingFloor() async {
        await MainActor.run {
            let clippedText = makeSingleLineCaptionNode()
            let clippingCard = ViewNode(
                layoutMode: .stack(
                    .vertical(
                        padding: EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4),
                        alignment: .stretch)),
                isHitTestVisible: false,
                children: [clippedText]
            )
            clippingCard.clipsToBounds = true
            let protectedText = makeSingleLineCaptionNode()
            let referenceRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: 400),
                layoutMode: .stack(.vertical(alignment: .leading)),
                isHitTestVisible: false,
                children: [makeSingleLineCaptionNode()]
            )
            renderStackFloorProbe(referenceRoot)
            let naturalTextHeight = referenceRoot.children[0].resolvedFrame.size.height

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 400, height: naturalTextHeight + 12),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .leading)),
                isHitTestVisible: false,
                children: [protectedText, clippingCard]
            )
            renderStackFloorProbe(root)

            XCTAssertEqual(
                protectedText.resolvedFrame.size.height, naturalTextHeight, accuracy: 0.001,
                "The unclipped text keeps its floor")
            XCTAssertEqual(
                clippingCard.resolvedFrame.size.height, 4, accuracy: 0.001,
                "The clipping card absorbs the whole deficit instead of overflowing")
            XCTAssertLessThanOrEqual(
                clippingCard.resolvedFrame.maxY, root.resolvedFrame.size.height + 0.001,
                "The squeezed stack stays contained")
        }
    }

    /// Explicit single-line text opted into truncation: it takes no width
    /// floor, so a squeezed row shrinks it (showing an ellipsis) instead
    /// of overflowing the trailing edge.
    func testSingleLineTextTakesNoWidthFloor() async {
        await MainActor.run {
            let label = makeSingleLineCaptionNode()
            label.textStyle.maximumNumberOfLines = 1
            let value = ViewNode(text: "A VERY LONG TRAILING VALUE STRING")
            value.textStyle.maximumNumberOfLines = 1
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 160, height: 40),
                layoutMode: .stack(.horizontal(spacing: 8, alignment: .center)),
                isHitTestVisible: false,
                children: [label, value]
            )
            renderStackFloorProbe(root)

            XCTAssertLessThanOrEqual(
                value.resolvedFrame.maxX, 160.001,
                "Single-line text shrinks (truncating) instead of overflowing the row")
        }
    }

    /// `.fillEqually` overrides the text shrink floor: equality is the
    /// distribution's contract (macOS segmented controls), so an over-long
    /// label truncates instead of stealing width from its siblings.
    func testFillEquallyDistributionOverridesTextShrinkFloors() async {
        await MainActor.run {
            let short = ViewNode(text: "A")
            let long = ViewNode(text: "AN EXTREMELY LONG SEGMENT LABEL THAT CANNOT FIT")
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 240, height: 40),
                layoutMode: .stack(
                    .horizontal(spacing: 4, alignment: .stretch, distribution: .fillEqually)),
                isHitTestVisible: false,
                children: [short, long]
            )
            renderStackFloorProbe(root)

            XCTAssertEqual(
                short.resolvedFrame.size.width,
                long.resolvedFrame.size.width,
                accuracy: 0.001,
                "fillEqually must keep children equal even when one label cannot fit its share"
            )
            XCTAssertEqual(
                short.resolvedFrame.size.width + long.resolvedFrame.size.width + 4,
                240,
                accuracy: 0.001,
                "equal shares plus spacing must exactly consume the track"
            )
        }
    }
}
