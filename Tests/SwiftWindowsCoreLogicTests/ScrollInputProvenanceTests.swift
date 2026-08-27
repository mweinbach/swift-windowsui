import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI

/// A wheel notch is a bounded jump; a gesture glides.
///
/// Measured before this: one line of wheel input on a 200pt-tall scroll view
/// moved 117.7px — a 64px step plus 53.7px of momentum tail whose last motion
/// was at t = 0.667s. Two separate faults. `scrollStep` was 64 while the host
/// had *already* converted the physical notch into `SPI_GETWHEELSCROLLLINES`
/// lines (default 3), so a notch-sized value sat in a line-sized slot and one
/// notch travelled ~192px of step. And every wheel event seeded
/// `scrollMomenta` with the trackpad calibration, which AppKit reserves for
/// devices that report a momentum phase.
@MainActor
final class ScrollInputProvenanceTests: XCTestCase {

    private func makeScroller(scrollStep: Double? = nil) -> (RetainedViewRuntime, ViewNode) {
        let items = (0..<3).map { _ in
            ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 200))
        }
        let scrollPanel = ViewNode(
            frame: Rect(x: 10, y: 10, width: 80, height: 80),
            layoutMode: .stack(.vertical(spacing: 10)),
            scrollAxis: .vertical,
            scrollStep: scrollStep ?? ViewNode.defaultScrollLineHeight,
            isHitTestVisible: false,
            children: items
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
        let runtime = RetainedViewRuntime(root: root)
        _ = runtime.renderFrame()
        return (runtime, scrollPanel)
    }

    /// A detent stops when it stops.
    func testAWheelNotchScrollsALineStepAndDoesNotGlide() async {
        let (runtime, scroller) = makeScroller()
        XCTAssertFalse(runtime.hasActiveAnimations)

        runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
        let afterOneLine = scroller.scrollOffset
        XCTAssertEqual(
            afterOneLine, ViewNode.defaultScrollLineHeight, accuracy: 0.001,
            "delta is in lines, so one line moves one line")
        XCTAssertFalse(
            runtime.hasActiveAnimations,
            "a click-wheel detent seeds no momentum: AppKit's momentum phase is gesture-only")

        var clock = Win32Window.currentTimestampSeconds()
        for _ in 0..<60 {
            clock += 1.0 / 60.0
            _ = runtime.tickAnimations(at: clock)
        }
        XCTAssertEqual(
            scroller.scrollOffset, afterOneLine, accuracy: 0.001,
            "and it has not crept anywhere in the second after the notch")
    }

    /// The default per-line step is the body line box, so the default
    /// three-line notch lands at 48pt rather than 192.
    func testTheDefaultLineStepPutsAThreeLineNotchInTheMacOSBand() async {
        XCTAssertEqual(ViewNode.defaultScrollLineHeight, 16, accuracy: 0.001)
        let (runtime, scroller) = makeScroller()
        runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3)
        XCTAssertEqual(scroller.scrollOffset, 48, accuracy: 0.001)
    }

    /// A gesture device keeps the calibration that was tuned for it.
    func testAPreciseDeltaStillGlides() async {
        let (runtime, scroller) = makeScroller()
        runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3, source: .precise)
        let immediate = scroller.scrollOffset
        XCTAssertTrue(runtime.hasActiveAnimations, "a gesture glides")

        var clock = Win32Window.currentTimestampSeconds()
        clock += 1.0 / 60.0
        _ = runtime.tickAnimations(at: clock)
        clock += 1.0 / 60.0
        _ = runtime.tickAnimations(at: clock)
        XCTAssertGreaterThan(scroller.scrollOffset, immediate, "and the glide moves the offset")
    }

    /// Finer wheel resolution is not evidence that a caller wants inertia.
    func testTheHostPreservesSystemManagedTravelAtEveryWheelResolution() async {
        func wParam(delta: Int) -> UInt64 {
            UInt64(UInt16(bitPattern: Int16(delta))) << 16
        }
        for delta in [0, 120, -120, 240, 40, -17, Int(Int16.min)] {
            XCTAssertEqual(Win32Window.scrollInputSource(from: wParam(delta: delta)), .systemManaged)
        }
    }

    func testNativeFractionalWheelStreamStopsAtItsRequestedDistance() async {
        let (runtime, scroller) = makeScroller()
        var expectedOffset = 0.0
        for delta in [-40, -80, -17, -120, -31] as [Int16] {
            let parameter = UInt64(UInt16(bitPattern: delta)) << 16
            let lines = Win32Window.mouseWheelDelta(from: parameter, unitCount: 3)
            expectedOffset -= lines * ViewNode.defaultScrollLineHeight
            runtime.mouseWheel(
                at: Point(x: 30, y: 30), delta: lines,
                source: Win32Window.scrollInputSource(from: parameter))
        }
        XCTAssertEqual(scroller.scrollOffset, expectedOffset, accuracy: 0.001)

        let timestamp = runtime.clock()
        for frame in 1...60 {
            _ = runtime.tickAnimations(at: timestamp + Double(frame) / 60)
        }
        XCTAssertEqual(
            scroller.scrollOffset, expectedOffset, accuracy: 0.001,
            "Native input already describes its travel; fractional deltas must not create an extra glide.")
    }

    func testZeroSystemWheelPreferenceDisablesScrolling() async {
        let unitCount = Win32Window.resolvedWheelUnitCount(0, defaultCount: 3)
        XCTAssertEqual(unitCount, 0)
        let parameter = UInt64(UInt16(bitPattern: Int16(-120))) << 16
        XCTAssertEqual(Win32Window.mouseWheelDelta(from: parameter, unitCount: unitCount), 0)
    }
}
