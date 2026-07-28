import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsLayout

import SwiftWindowsPlatform

import XCTest

@testable import SwiftWindowsUI

/// Lays out `root` with one render pass.
@MainActor
private func renderStackFloorProbe(_ root: ViewNode) {
    _ = RetainedViewRuntime(root: root).renderFrame()
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

/// Pins the stack shrink floor: text-bearing nodes keep their measured
/// main-axis size when a stack runs out of room, while padding, spacers,
/// and flexible siblings absorb the squeeze first (and content overflows
/// rather than crushing text below its measured size).
final class StackTextShrinkFloorTests: XCTestCase {

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
}
