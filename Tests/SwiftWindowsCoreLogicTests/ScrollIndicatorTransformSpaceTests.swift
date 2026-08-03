import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// A scroll indicator lives in two spaces at once and they are not
/// interchangeable. Its *length* is the fraction of the content the viewport
/// shows — a ratio of `resolvedFrame` to `resolvedContentSize`, both layout
/// space. Its *position* is what the painter draws and what the pointer is
/// tested against — painted space, after every accumulated transform.
///
/// Moving the track to `paintFrame` put the position right and the length
/// wrong: under `.scaleEffect(2)` the viewport measured twice as tall while
/// the content size stayed as it was, so a ScrollView showing a third of its
/// content drew a thumb two thirds of the track long and dragged at twice the
/// rate.
@MainActor
final class ScrollIndicatorTransformSpaceTests: XCTestCase {

    /// Layout: a 100×200 viewport at (100, 100) over 600pt of content, scaled
    /// 2× about its own centre. Painted: a 200×400 viewport at (50, 0).
    private func makeScaledScrollFixture() -> (runtime: RetainedViewRuntime, scroll: ViewNode) {
        let content = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 600),
            backgroundColor: .white
        )
        let scroll = ViewNode(
            frame: Rect(x: 100, y: 100, width: 100, height: 200),
            transform: Transform2D(scaleX: 2, scaleY: 2),
            scrollAxis: .vertical,
            scrollOffset: 0,
            showsScrollIndicator: true,
            children: [content]
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 400, height: 400),
            isHitTestVisible: false,
            children: [scroll]
        )
        return (RetainedViewRuntime(root: root), scroll)
    }

    private func indicatorTrack(of runtime: RetainedViewRuntime) -> ScrollIndicatorTrack? {
        for deferredDraw in runtime.currentPrepaintState.deferredDraws {
            if case .scrollIndicator(let payload) = deferredDraw.payload {
                return payload.track
            }
        }
        return nil
    }

    /// The default 6pt indicator insets, scaled with everything else.
    private static let paintedTrackLength = (200.0 - 6.0 - 6.0) * 2.0
    /// 200pt of viewport over 600pt of content — a layout-space ratio that no
    /// transform may change.
    private static let visibleFraction = 200.0 / 600.0
    private static let paintedThumbLength = paintedTrackLength * visibleFraction
    private static let paintedTravel = paintedTrackLength - paintedThumbLength

    func testAScaledScrollViewDrawsAThumbProportionalToTheVisibleFraction() async {
        let (runtime, scroll) = makeScaledScrollFixture()
        _ = runtime.renderScene()

        XCTAssertEqual(scroll.resolvedContentSize.height, 600, "the fixture must actually overflow")

        guard let track = indicatorTrack(of: runtime) else {
            XCTFail("a scrollable overflowing viewport must emit an indicator")
            return
        }

        XCTAssertEqual(
            track.indicatorRect.size.height, Self.paintedThumbLength, accuracy: 0.001,
            "the thumb is the visible fraction of the track, and the fraction is a layout-space ratio")
        XCTAssertEqual(
            track.travel, Self.paintedTravel, accuracy: 0.001,
            "travel is what is left of the painted track once the thumb is placed in it")

        // Still painted space: the thumb sits on the *scaled* viewport's
        // trailing edge, not the layout one, and its thickness scaled with it.
        XCTAssertEqual(track.indicatorRect.maxX, 238, accuracy: 0.001)
        XCTAssertEqual(track.indicatorRect.size.width, 12, accuracy: 0.001)
        XCTAssertEqual(track.indicatorRect.origin.y, 12, accuracy: 0.001)
    }

    func testDraggingAScaledScrollIndicatorMovesContentAtTheTrackRate() async {
        let (runtime, scroll) = makeScaledScrollFixture()
        _ = runtime.renderScene()

        XCTAssertEqual(scroll.scrollOffset, 0)

        // Inside the painted thumb — (226, 12, 12, 125.33).
        runtime.pointerDown(at: Point(x: 232, y: 60))
        runtime.pointerMoved(to: Point(x: 232, y: 160))
        runtime.pointerUp(at: Point(x: 232, y: 160))

        // 100 painted points of painted travel, over the 400pt layout scroll
        // range (600pt of content in a 200pt viewport).
        XCTAssertEqual(
            scroll.scrollOffset, 400.0 * 100.0 / Self.paintedTravel, accuracy: 0.01,
            "a drag maps painted travel onto the layout scroll range; a mis-measured track mis-scales it")
    }

    /// The untransformed case is the one every other indicator test pins, and
    /// measuring in layout space must leave it byte-identical.
    func testAnUntransformedScrollIndicatorIsUnchanged() async {
        let content = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 200), backgroundColor: .white)
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 80, height: 100),
            scrollAxis: .vertical,
            scrollOffset: 0,
            showsScrollIndicator: true,
            children: [content]
        )
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 100), children: [scroll]))
        _ = runtime.renderScene()

        guard let track = indicatorTrack(of: runtime) else {
            XCTFail("a scrollable overflowing viewport must emit an indicator")
            return
        }
        XCTAssertEqual(track.indicatorRect, scroll.scrollIndicatorRect(in: Rect(x: 0, y: 0, width: 80, height: 100)))
        // 100pt viewport over 200pt of content, inside an 88pt track.
        XCTAssertEqual(track.travel, 88.0 - 44.0, accuracy: 0.001)
    }
}
