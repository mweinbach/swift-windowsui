import SwiftWindowsCore

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

// The timer-resolution half of the smoothness work. Every timer the frame
// loop rides — the timer-queue frame timer, the `SetTimer` fallback, and the
// 1 ms deferral wake the self-paced gate arms — fires on the system interrupt
// period, which defaults to ~15.6 ms. `useHighResolutionTimer` promised a
// high-resolution cadence and delivered nothing: nothing in the process ever
// raised the resolution, so a "16 ms" timer quantized to the system tick and
// a millisecond wake could land a whole tick late. Measured on a 60 Hz
// display: a 13.8 ms median presented-frame gap and ~62 delivered frames a
// second instead of 60.
//
// The hold is power policy as much as timing policy: `timeBeginPeriod(1)`
// charges the whole machine, so it is held exactly while an animation timer
// is running and not a moment longer. These tests pin the transition rules
// against a recording controller, because the real one changes the machine's
// interrupt rate — the one side effect a unit test must not have.

/// Records raise/lower transitions instead of touching WinMM.
final class RecordingTimerResolutionController: TimerResolutionController {
    private(set) var raiseCount = 0
    private(set) var lowerCount = 0

    func raise() {
        raiseCount += 1
    }

    func lower() {
        lowerCount += 1
    }
}

@MainActor
final class TimerResolutionHoldTests: XCTestCase {
    private func makeWindow() -> (Win32Window, RecordingTimerResolutionController) {
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        let controller = RecordingTimerResolutionController()
        window.timerResolutionController = controller
        return (window, controller)
    }

    func testARunningAnimationTimerHoldsTheRaisedResolution() async {
        let (window, controller) = makeWindow()

        window.setAnimationTimerRunningForTesting(true)

        XCTAssertEqual(
            controller.raiseCount,
            1,
            "An animating window needs 1 ms timers, or its cadence is the 15.6 ms system tick."
        )
        XCTAssertEqual(controller.lowerCount, 0)
        XCTAssertTrue(window.holdsRaisedTimerResolutionForTesting)
    }

    func testStoppingTheTimerReleasesTheResolutionExactlyOnce() async {
        let (window, controller) = makeWindow()

        window.setAnimationTimerRunningForTesting(true)
        window.setAnimationTimerRunningForTesting(false)
        window.setAnimationTimerRunningForTesting(false)

        XCTAssertEqual(controller.raiseCount, 1)
        XCTAssertEqual(
            controller.lowerCount,
            1,
            "timeBeginPeriod/timeEndPeriod refcount per process; an unbalanced release would steal another window's hold."
        )
        XCTAssertFalse(window.holdsRaisedTimerResolutionForTesting)
    }

    func testIntervalChangesDoNotChurnTheHold() async {
        let (window, controller) = makeWindow()

        // The self-paced deferral re-arms the timer with a new interval as
        // often as every frame, and each re-arm is a stop/start of the OS
        // timer. The hold must ride across those, not cycle with them.
        window.setAnimationTimerRunningForTesting(true)
        window.setAnimationTimerRunningForTesting(true)
        window.setAnimationTimerRunningForTesting(true)

        XCTAssertEqual(controller.raiseCount, 1, "One hold per running timer, however many times the interval moves.")
        XCTAssertEqual(controller.lowerCount, 0)
    }

    func testStoppingATimerThatNeverRanReleasesNothing() async {
        let (window, controller) = makeWindow()

        window.setAnimationTimerRunningForTesting(false)

        XCTAssertEqual(controller.raiseCount, 0)
        XCTAssertEqual(controller.lowerCount, 0)
    }

    func testAWindowWithNoTimerNeverRaisesTheResolution() async {
        let (window, controller) = makeWindow()

        // No HWND: `setAnimationTimerEnabled` installs no timer, so there is
        // nothing whose accuracy the raised resolution would buy — holding it
        // would bill the whole machine for a timer that does not exist.
        window.setAnimationTimerEnabled(true, intervalMilliseconds: 16)

        XCTAssertEqual(controller.raiseCount, 0, "The hold follows a real timer, not the intent to have one.")
        XCTAssertFalse(window.holdsRaisedTimerResolutionForTesting)
    }

    func testStartStopStartHoldsAgain() async {
        let (window, controller) = makeWindow()

        window.setAnimationTimerRunningForTesting(true)
        window.setAnimationTimerRunningForTesting(false)
        window.setAnimationTimerRunningForTesting(true)

        XCTAssertEqual(
            controller.raiseCount, 2, "An idle window that starts animating again needs the resolution back.")
        XCTAssertEqual(controller.lowerCount, 1)
        XCTAssertTrue(window.holdsRaisedTimerResolutionForTesting)
    }
}
