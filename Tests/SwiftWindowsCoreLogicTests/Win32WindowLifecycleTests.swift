import SwiftWindowsCore
import Synchronization
import WinSDK

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

// WS-10: window ownership and frame-timer lifecycle.
//
// The `GWLP_USERDATA` self reference used to be unretained, so a close that
// also dropped the delegate chain's last strong reference freed the window
// during `WM_DESTROY` and let the `WM_NCDESTROY` that Windows sends next
// resolve freed memory. The frame timer had two matching hazards: restarting
// it after a size/move read back the interval of the timer that had just been
// stopped (zero, i.e. a 1 ms 1000 Hz timer), and a `CreateTimerQueueTimer`
// failure left the window believing a timer was running that did not exist.
//
// The timer rules are pinned as pure values so they hold without an HWND. The
// ownership test needs a real window and skips itself where one cannot be
// created.

@MainActor
final class Win32WindowLifecycleTests: XCTestCase {

    // MARK: - Frame timer plan

    func testTimerPlanUsesRequestedIntervalOutsideModalLoops() async {
        let plan = Win32Window.animationTimerConfiguration(
            requestedInterval: 17,
            isInModalLoop: false,
            prefersHighResolution: true,
            isHighResolutionAvailable: true
        )
        XCTAssertEqual(plan.intervalMilliseconds, 17)
        XCTAssertTrue(plan.useHighResolution)
    }

    func testTimerPlanDropsToTheCoalescingPathInsideModalLoops() async {
        let plan = Win32Window.animationTimerConfiguration(
            requestedInterval: 17,
            isInModalLoop: true,
            prefersHighResolution: true,
            isHighResolutionAvailable: true
        )
        XCTAssertEqual(plan.intervalMilliseconds, UINT(max(1, USER_TIMER_MINIMUM)))
        XCTAssertFalse(
            plan.useHighResolution,
            "A modal size/move loop runs its own pump; only SetTimer messages are delivered there."
        )
    }

    func testTimerPlanFallsBackToSetTimerWhenTheTimerQueueIsUnavailable() async {
        let plan = Win32Window.animationTimerConfiguration(
            requestedInterval: 17,
            isInModalLoop: false,
            prefersHighResolution: true,
            isHighResolutionAvailable: false
        )
        XCTAssertEqual(plan.intervalMilliseconds, 17)
        XCTAssertFalse(
            plan.useHighResolution,
            "A window whose timer-queue timer could not be created must fall back to SetTimer, not stall."
        )
    }

    func testRequestedTimerIntervalSurvivesEnterAndExitSizeMove() async {
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        window.useHighResolutionTimer = true
        window.setAnimationTimerEnabled(true, intervalMilliseconds: 17)

        XCTAssertEqual(window.currentAnimationTimerConfiguration.intervalMilliseconds, 17)

        window.setModalLoopStateForTesting(isInSizeMove: true)
        XCTAssertEqual(
            window.currentAnimationTimerConfiguration.intervalMilliseconds,
            UINT(max(1, USER_TIMER_MINIMUM))
        )

        window.setModalLoopStateForTesting()
        XCTAssertEqual(
            window.currentAnimationTimerConfiguration.intervalMilliseconds,
            17,
            "Exiting a size/move must restore the requested cadence, not restart the frame timer at 1 ms."
        )
        XCTAssertTrue(window.currentAnimationTimerConfiguration.useHighResolution)

        window.setModalLoopStateForTesting(isInMenuLoop: true)
        window.setModalLoopStateForTesting()
        XCTAssertEqual(window.currentAnimationTimerConfiguration.intervalMilliseconds, 17)
    }

    func testMarkingTheHighResolutionTimerUnavailableSticksToTheCoalescingPath() async {
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        window.useHighResolutionTimer = true
        window.setAnimationTimerEnabled(true, intervalMilliseconds: 17)
        XCTAssertTrue(window.currentAnimationTimerConfiguration.useHighResolution)

        window.markHighResolutionTimerUnavailableForTesting()

        XCTAssertFalse(window.currentAnimationTimerConfiguration.useHighResolution)
        XCTAssertEqual(window.currentAnimationTimerConfiguration.intervalMilliseconds, 17)
    }

    // MARK: - Timer post gate

    func testTimerGateAdmitsOneOutstandingPostAtATime() async {
        let gate = Win32AnimationTimerGate(windowHandleValue: 0x1)

        let (firstClaim, _) = gate.isPostOutstanding.compareExchange(
            expected: false,
            desired: true,
            ordering: .acquiringAndReleasing
        )
        XCTAssertTrue(firstClaim)

        let (secondClaim, _) = gate.isPostOutstanding.compareExchange(
            expected: false,
            desired: true,
            ordering: .acquiringAndReleasing
        )
        XCTAssertFalse(
            secondClaim,
            "Posted WM_TIMER messages are not coalesced; a second post before the first is consumed grows the queue."
        )

        gate.consumePost()

        let (claimAfterConsume, _) = gate.isPostOutstanding.compareExchange(
            expected: false,
            desired: true,
            ordering: .acquiringAndReleasing
        )
        XCTAssertTrue(claimAfterConsume, "Consuming the queued tick must re-open the gate for the next one.")
    }

    // MARK: - Window ownership

    func testDestroyingAWindowClearsItsBackPointerAndBalancesItsSelfReference() async throws {
        weak var probe: Win32Window?

        try autoreleasepoolCompatible {
            let window = Win32Window(title: "WS-10 Lifetime", clientSize: IntSize(width: 120, height: 80))
            // Never post WM_QUIT into the test process's message queue.
            window.postsQuitMessageOnDestroy = false

            do {
                try window.create()
            } catch {
                throw XCTSkip("This environment cannot create a top-level window: \(error)")
            }

            probe = window
            let handle = try XCTUnwrap(window.nativeHandle?.rawPointer)
            let hwnd = HWND(bitPattern: Int(bitPattern: handle))
            XCTAssertNotEqual(
                GetWindowLongPtrW(hwnd, GWLP_USERDATA),
                0,
                "The window installs a back pointer for the wndproc to resolve."
            )

            // DestroyWindow delivers WM_DESTROY and then WM_NCDESTROY
            // synchronously on this thread — exactly the sequence a user's
            // click on the close box produces.
            DestroyWindow(hwnd)

            XCTAssertNil(
                window.nativeHandle,
                "WM_NCDESTROY must forget the handle so nothing calls into a destroyed window."
            )
            XCTAssertNotNil(probe, "The window is still referenced by this scope.")
        }

        XCTAssertNil(
            probe,
            "The retained self reference must be released exactly once, in WM_NCDESTROY: any other count leaks or "
                + "double-frees."
        )
    }

    // MARK: - Minimize

    /// `WM_SIZE`/`SIZE_MINIMIZED` suppresses the delegate resize callback —
    /// rebuilding the component tree at 0×0 is pointless work — but it used to
    /// return before `updateCachedClientSize()` too, freezing `clientSize` at
    /// the pre-minimize rect. `currentClientSize()` feeds the host's surface
    /// descriptor, so a presenter attach that landed during a minimize built a
    /// swap chain for a size the window does not have. The cache now always
    /// mirrors the OS; only the callback is suppressed.
    func testMinimizeKeepsTheCachedClientSizeInSyncWithTheOS() async throws {
        let window = Win32Window(title: "WS-10 Minimize", clientSize: IntSize(width: 320, height: 200))
        window.postsQuitMessageOnDestroy = false

        do {
            try window.create()
        } catch {
            throw XCTSkip("This environment cannot create a top-level window: \(error)")
        }

        let handle = try XCTUnwrap(window.nativeHandle?.rawPointer)
        let hwnd = HWND(bitPattern: Int(bitPattern: handle))
        defer { DestroyWindow(hwnd) }

        let recorder = ResizeRecordingWindowDelegate()
        window.delegate = recorder

        ShowWindow(hwnd, SW_SHOWNOACTIVATE)
        let restoredSize = window.currentClientSize()
        try XCTSkipUnless(
            restoredSize.width > 0 && restoredSize.height > 0,
            "This environment did not give the window a client rect."
        )
        XCTAssertFalse(window.isMinimized)

        let resizesBeforeMinimize = recorder.sizes.count
        ShowWindow(hwnd, SW_MINIMIZE)

        XCTAssertTrue(window.isMinimized, "A minimized window must say so rather than look like a normal one.")
        XCTAssertEqual(
            window.currentClientSize(),
            IntSize(width: 0, height: 0),
            "The cached client size must mirror the OS, not the pre-minimize rect."
        )
        XCTAssertEqual(
            recorder.sizes.count,
            resizesBeforeMinimize,
            "Only the delegate resize callback is suppressed while minimized."
        )

        ShowWindow(hwnd, SW_RESTORE)
        XCTAssertFalse(window.isMinimized)
        XCTAssertEqual(window.currentClientSize(), restoredSize, "Restore delivers the real rect again.")
        XCTAssertGreaterThan(recorder.sizes.count, resizesBeforeMinimize, "Restore is a real resize.")
    }

    /// `autoreleasepool` is Darwin-only; this keeps the scoped-lifetime shape
    /// of the ownership test readable on Windows.
    private func autoreleasepoolCompatible(_ body: () throws -> Void) rethrows {
        try body()
    }
}

/// Records only what the minimize test asserts on: the sizes the window
/// forwarded to its delegate.
@MainActor
private final class ResizeRecordingWindowDelegate: WindowDelegate {
    private(set) var sizes: [IntSize] = []

    func window(_ window: Win32Window, didResizeTo size: IntSize) {
        sizes.append(size)
    }
}
