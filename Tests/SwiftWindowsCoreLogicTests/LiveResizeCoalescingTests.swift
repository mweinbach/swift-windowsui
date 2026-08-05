import SwiftWindowsCore
import SwiftWindowsGraphics

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

@testable import WinSwiftUI

// L7-ADAPT: what an interactive border drag costs.
//
// A modal size/move loop delivers `WM_SIZE` continuously — at mouse-report
// rate, which on a modern mouse is several times the display's refresh rate.
// The host's handler answered each one with a full `componentHost.reload()`
// (a complete SwiftUI-shaped body re-evaluation), a UIA
// `raiseStructureChanged()` (a complete accessibility structure invalidation),
// and a swap-chain `ResizeBuffers`. Nothing debounced, coalesced or deferred
// any of it, so a drag queued many frames' worth of work per frame it could
// actually present and fell further behind the pointer the longer it lasted.
//
// The contract these tests pin: inside a drag the work rate is a function of
// the *display*, not of the mouse. Size messages accumulate into one pending
// size; the frame the drag asks for applies it once.
@MainActor
final class LiveResizeCoalescingTests: XCTestCase {

    private func makeHost(
        pixelSize: IntSize = IntSize(width: 800, height: 600)
    ) -> (WinSwiftUIWindowHost, Win32Window, ResizeCountingBackend) {
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: 1.0
        )
        let renderer = ResizeCountingBackend()
        let config = WindowGroupConfiguration(
            title: "Test",
            size: pixelSize,
            clearColor: .black,
            content: []
        )
        let host = WinSwiftUIWindowHost(
            configuration: config,
            renderer: renderer,
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }
        )
        let window = Win32Window(title: "Test", clientSize: pixelSize)
        window.testScaleFactorOverride = 1.0
        host.windowDidCreate(window)
        return (host, window, renderer)
    }

    /// The window knows it is in a drag, which is the fact the whole
    /// coalescing decision hangs off. `WM_ENTERSIZEMOVE`/`WM_EXITSIZEMOVE`
    /// are the only two messages that move it.
    func testLiveResizeStateTracksTheModalSizeMoveLoop() async {
        await MainActor.run {
            let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
            XCTAssertFalse(window.isInLiveResize)

            window.setModalLoopStateForTesting(isInSizeMove: true)
            XCTAssertTrue(window.isInLiveResize)

            window.setModalLoopStateForTesting(isInSizeMove: false)
            XCTAssertFalse(window.isInLiveResize)

            // A menu loop is modal too, but it is not a resize: it must not make
            // the host start holding sizes back.
            window.setModalLoopStateForTesting(isInMenuLoop: true)
            XCTAssertFalse(window.isInLiveResize)
        }
    }

    /// The defect, stated as a count: a burst of size messages inside one
    /// drag must cost one rebuild, not one rebuild each.
    func testDragCoalescesEverySizeMessageIntoOneRebuildPerFrame() async {
        await MainActor.run {
            let (host, window, renderer) = makeHost()
            let rebuildsBeforeDrag = host.executedResizeRebuildCount
            let resizesBeforeDrag = renderer.resizeCallCount

            window.setModalLoopStateForTesting(isInSizeMove: true)
            for width in 800..<840 {
                host.window(window, didResizeTo: IntSize(width: Int32(width), height: 600))
            }

            XCTAssertEqual(
                host.executedResizeRebuildCount, rebuildsBeforeDrag,
                "40 size messages inside a drag must not have rebuilt the tree 40 times before a single frame ran."
            )
            XCTAssertEqual(
                renderer.resizeCallCount, resizesBeforeDrag,
                "The swap chain must not be rebuilt once per mouse report."
            )

            // The frame the drag asked for.
            host.windowNeedsDisplay(window)

            XCTAssertEqual(
                host.executedResizeRebuildCount, rebuildsBeforeDrag + 1,
                "The frame applies the newest size exactly once."
            )
            XCTAssertEqual(
                renderer.resizeCallCount, resizesBeforeDrag + 1,
                "One swap-chain resize per presented frame, not per message."
            )
            XCTAssertEqual(
                host.currentLogicalRootSize, IntSize(width: 839, height: 600),
                "The size that lands is the newest one, not the first or an average."
            )
        }
    }

    /// Coalescing must not turn into dropping: a second burst after the frame
    /// gets its own frame, and the drag's final size always lands.
    func testEachFrameDuringADragAppliesTheNewestSize() async {
        await MainActor.run {
            let (host, window, _) = makeHost()
            window.setModalLoopStateForTesting(isInSizeMove: true)

            for width in 800..<820 {
                host.window(window, didResizeTo: IntSize(width: Int32(width), height: 600))
            }
            host.windowNeedsDisplay(window)
            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 819, height: 600))

            for width in 820..<860 {
                host.window(window, didResizeTo: IntSize(width: Int32(width), height: 620))
            }
            host.windowNeedsDisplay(window)
            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 859, height: 620))

            XCTAssertEqual(
                host.executedResizeRebuildCount, 2,
                "60 messages across two frames cost two rebuilds."
            )
        }
    }

    /// `WM_EXITSIZEMOVE` re-delivers the final client size with the loop flag
    /// already cleared. That delivery applies immediately — a settled window
    /// must never wait for a frame to reach its final layout — and it must not
    /// leave a stale pending size behind for the next frame to redo.
    func testDragEndAppliesImmediatelyAndLeavesNothingPending() async {
        await MainActor.run {
            let (host, window, _) = makeHost()

            window.setModalLoopStateForTesting(isInSizeMove: true)
            for width in 800..<830 {
                host.window(window, didResizeTo: IntSize(width: Int32(width), height: 600))
            }
            XCTAssertEqual(host.executedResizeRebuildCount, 0)

            // WM_EXITSIZEMOVE: the flag clears, then the size is redelivered.
            window.setModalLoopStateForTesting(isInSizeMove: false)
            host.window(window, didResizeTo: IntSize(width: 829, height: 600))

            XCTAssertEqual(
                host.executedResizeRebuildCount, 1,
                "The settling delivery applies without waiting for a frame."
            )
            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 829, height: 600))

            host.windowNeedsDisplay(window)
            XCTAssertEqual(
                host.executedResizeRebuildCount, 1,
                "The frame after the drag must not rebuild again for a size the window already has."
            )
        }
    }

    /// A screen reader wants to hear that the window's structure changed once,
    /// when it settles — not on every mouse report of a drag.
    func testAccessibilityStructureChangeIsRaisedOncePerDragNotPerMessage() async {
        await MainActor.run {
            let (host, window, _) = makeHost()
            let notificationsBefore = host.executedResizeAccessibilityNotificationCount

            window.setModalLoopStateForTesting(isInSizeMove: true)
            for width in 800..<840 {
                host.window(window, didResizeTo: IntSize(width: Int32(width), height: 600))
                host.windowNeedsDisplay(window)
            }

            XCTAssertEqual(
                host.executedResizeAccessibilityNotificationCount, notificationsBefore,
                "40 frames of drag must raise no structure changes; the tree's shape is not what is moving."
            )

            window.setModalLoopStateForTesting(isInSizeMove: false)
            host.windowNeedsDisplay(window)

            XCTAssertEqual(
                host.executedResizeAccessibilityNotificationCount, notificationsBefore + 1,
                "Exactly one notification when the window settles."
            )
        }
    }

    /// Outside a drag — a programmatic resize, a maximize, a `WM_DPICHANGED`,
    /// a restore — nothing is deferred. These are discrete events, and one
    /// rebuild is the right answer for each.
    func testResizeOutsideADragStillAppliesSynchronously() async {
        await MainActor.run {
            let (host, window, renderer) = makeHost()

            host.window(window, didResizeTo: IntSize(width: 1280, height: 720))

            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 1280, height: 720))
            XCTAssertEqual(host.executedResizeRebuildCount, 1)
            XCTAssertEqual(host.executedResizeAccessibilityNotificationCount, 1)
            XCTAssertEqual(renderer.resizeCallCount, 1)
        }
    }

    /// A DPI change arriving mid-drag (dragging a window across a monitor
    /// boundary) still has to reach the runtime: the deferred path carries the
    /// scale, not just the pixel size, because every glyph's raster key is
    /// `displayScale * rasterScale`.
    func testDeferredResizeCarriesTheDisplayScale() async {
        await MainActor.run {
            let (host, window, _) = makeHost()
            window.setModalLoopStateForTesting(isInSizeMove: true)

            window.testScaleFactorOverride = 1.5
            host.window(window, didResizeTo: IntSize(width: 1920, height: 1080))
            host.windowNeedsDisplay(window)

            XCTAssertEqual(host.currentDisplayScale, 1.5)
            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 1280, height: 720))
        }
    }
}

/// Minimal frame backend that only counts what this suite asserts on.
@MainActor
private final class ResizeCountingBackend: RenderBackend {
    private(set) var resizeCallCount = 0
    private(set) var renderCallCount = 0

    var backendDisplayName: String { "COUNTING FRAME" }
    var backendStatusDescription: String { "Resize-counting frame backend" }
    var presentationState = PresentationState()

    func attach(to surface: SurfaceDescriptor) throws {}
    func resize(to size: IntSize) throws { resizeCallCount += 1 }
    func render(frame: RenderFrame) throws { renderCallCount += 1 }
    func detach() {}
}
