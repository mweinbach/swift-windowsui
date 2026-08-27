import SwiftWindowsCore
import WinSDK

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@MainActor
private final class PointerMessageRecordingDelegate: WindowDelegate {
    private(set) var pointerDownPoints: [Point] = []
    private(set) var pointerUpPoints: [Point] = []
    private(set) var doubleClicks: [MouseEvent] = []
    private(set) var horizontalScrollDeltas: [Double] = []
    private(set) var verticalScrollDeltas: [Double] = []
    private(set) var scrollSources: [ScrollInputSource] = []
    private(set) var cancellationCount = 0

    func window(_ window: Win32Window, leftMouseDownAt point: Point) {
        pointerDownPoints.append(point)
    }

    func window(_ window: Win32Window, leftMouseUpAt point: Point) {
        pointerUpPoints.append(point)
    }

    func windowDidReceiveDoubleClick(_ window: Win32Window, event: MouseEvent) {
        doubleClicks.append(event)
    }

    func window(
        _ window: Win32Window, horizontalScrollAt point: Point, delta: Double, source: ScrollInputSource
    ) {
        horizontalScrollDeltas.append(delta)
        scrollSources.append(source)
    }

    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double, source: ScrollInputSource) {
        verticalScrollDeltas.append(delta)
        scrollSources.append(source)
    }

    func windowDidCancelPointerInteraction(_ window: Win32Window) {
        cancellationCount += 1
    }
}

@MainActor
final class Win32PointerMessageRoutingTests: XCTestCase {
    private func makeWindow() throws -> (Win32Window, HWND, PointerMessageRecordingDelegate) {
        let window = Win32Window(title: "Pointer message routing", clientSize: IntSize(width: 160, height: 100))
        window.postsQuitMessageOnDestroy = false
        let recorder = PointerMessageRecordingDelegate()
        window.delegate = recorder

        do {
            try window.create()
        } catch {
            throw XCTSkip("This environment cannot create a top-level window: \(error)")
        }

        let handle = try XCTUnwrap(window.nativeHandle?.rawPointer)
        let hwnd = try XCTUnwrap(HWND(bitPattern: Int(bitPattern: handle)))
        return (window, hwnd, recorder)
    }

    private func packedPoint(x: Int16, y: Int16) -> LPARAM {
        LPARAM(UInt32(UInt16(bitPattern: x)) | (UInt32(UInt16(bitPattern: y)) << 16))
    }

    private func wheelWParam(delta: Int16, keyState: UInt32 = 0) -> WPARAM {
        WPARAM((UInt32(UInt16(bitPattern: delta)) << 16) | keyState)
    }

    func testDoubleClickPreservesItsOrdinaryPointerPressAndMouseCapture() async throws {
        let (window, hwnd, recorder) = try makeWindow()
        defer {
            _ = window
            DestroyWindow(hwnd)
        }

        let point = packedPoint(x: 32, y: 24)
        SendMessageW(hwnd, UINT(WM_LBUTTONDOWN), WPARAM(MK_LBUTTON), point)
        SendMessageW(hwnd, UINT(WM_LBUTTONUP), 0, point)

        XCTAssertEqual(recorder.pointerDownPoints, [Point(x: 32, y: 24)])
        XCTAssertEqual(recorder.pointerUpPoints, [Point(x: 32, y: 24)])
        XCTAssertEqual(recorder.cancellationCount, 0, "A normal release is not an interrupted pointer interaction.")

        SendMessageW(hwnd, UINT(WM_LBUTTONDBLCLK), WPARAM(MK_LBUTTON), point)

        XCTAssertEqual(
            recorder.pointerDownPoints,
            [Point(x: 32, y: 24), Point(x: 32, y: 24)],
            "Windows replaces the second button-down with WM_LBUTTONDBLCLK; it must still reach SwiftUI."
        )
        XCTAssertEqual(recorder.doubleClicks.count, 1)
        XCTAssertEqual(recorder.doubleClicks.first?.clickCount, 2)
        XCTAssertEqual(GetCapture(), hwnd, "A double-click press must support dragging outside the client area.")

        SendMessageW(hwnd, UINT(WM_LBUTTONUP), 0, point)

        XCTAssertEqual(recorder.pointerUpPoints, [Point(x: 32, y: 24), Point(x: 32, y: 24)])
        XCTAssertEqual(recorder.cancellationCount, 0)
        XCTAssertNil(GetCapture())
    }

    func testExternalCaptureLossCancelsThePointerExactlyOnce() async throws {
        let (window, hwnd, recorder) = try makeWindow()
        defer {
            _ = window
            DestroyWindow(hwnd)
        }

        let point = packedPoint(x: 14, y: 18)
        SendMessageW(hwnd, UINT(WM_LBUTTONDOWN), WPARAM(MK_LBUTTON), point)
        XCTAssertEqual(GetCapture(), hwnd)

        ReleaseCapture()

        XCTAssertEqual(recorder.cancellationCount, 1)
        XCTAssertEqual(recorder.pointerDownPoints, [Point(x: 14, y: 18)])
        XCTAssertTrue(recorder.pointerUpPoints.isEmpty, "Capture loss is cancellation, not a control activation.")
    }

    func testCancelModeReleasesCaptureAndDeliversOnlyOneCancellation() async throws {
        let (window, hwnd, recorder) = try makeWindow()
        defer {
            _ = window
            DestroyWindow(hwnd)
        }

        SendMessageW(hwnd, UINT(WM_LBUTTONDOWN), WPARAM(MK_LBUTTON), packedPoint(x: 20, y: 25))
        XCTAssertEqual(GetCapture(), hwnd)

        SendMessageW(hwnd, UINT(WM_CANCELMODE), 0, 0)

        XCTAssertNil(GetCapture())
        XCTAssertEqual(
            recorder.cancellationCount,
            1,
            "WM_CANCELMODE's synchronous WM_CAPTURECHANGED must not cancel the same gesture twice."
        )
        XCTAssertTrue(recorder.pointerUpPoints.isEmpty)
    }

    func testMouseCaptureRemainsOwnedUntilAllPressedButtonsAreReleased() async throws {
        let (window, hwnd, recorder) = try makeWindow()
        defer {
            _ = window
            DestroyWindow(hwnd)
        }

        let point = packedPoint(x: 26, y: 19)
        SendMessageW(hwnd, UINT(WM_LBUTTONDOWN), WPARAM(MK_LBUTTON), point)
        SendMessageW(hwnd, UINT(WM_RBUTTONDOWN), WPARAM(MK_LBUTTON | MK_RBUTTON), point)

        SendMessageW(hwnd, UINT(WM_RBUTTONUP), WPARAM(MK_LBUTTON), point)
        XCTAssertEqual(GetCapture(), hwnd, "Releasing another button must not strand the active left-button drag.")
        XCTAssertEqual(recorder.cancellationCount, 0)

        SendMessageW(hwnd, UINT(WM_LBUTTONUP), 0, point)
        XCTAssertNil(GetCapture())
        XCTAssertEqual(recorder.pointerUpPoints, [Point(x: 26, y: 19)])
        XCTAssertEqual(recorder.cancellationCount, 0)
    }

    func testHorizontalWheelTranslatesRightwardWin32MotionIntoForwardScroll() async throws {
        let (window, hwnd, recorder) = try makeWindow()
        defer {
            _ = window
            DestroyWindow(hwnd)
        }

        SendMessageW(hwnd, UINT(WM_MOUSEHWHEEL), wheelWParam(delta: 120), 0)
        SendMessageW(hwnd, UINT(WM_MOUSEHWHEEL), wheelWParam(delta: -120), 0)

        XCTAssertEqual(recorder.horizontalScrollDeltas.count, 2)
        XCTAssertLessThan(
            recorder.horizontalScrollDeltas[0],
            0,
            "A positive WM_MOUSEHWHEEL delta means right; the retained runtime advances right on negative deltas."
        )
        XCTAssertGreaterThan(recorder.horizontalScrollDeltas[1], 0)
        XCTAssertEqual(recorder.horizontalScrollDeltas[0], -recorder.horizontalScrollDeltas[1], accuracy: 0.001)
    }

    func testWheelUsesTheShiftStateCapturedInItsMessage() async throws {
        let (window, hwnd, recorder) = try makeWindow()
        defer {
            _ = window
            DestroyWindow(hwnd)
        }

        SendMessageW(hwnd, UINT(WM_MOUSEWHEEL), wheelWParam(delta: -40, keyState: UInt32(MK_SHIFT)), 0)
        SendMessageW(hwnd, UINT(WM_MOUSEWHEEL), wheelWParam(delta: -40), 0)

        XCTAssertEqual(recorder.horizontalScrollDeltas.count, 1, "Shift-wheel is horizontal at message time.")
        XCTAssertEqual(recorder.verticalScrollDeltas.count, 1, "The next unmodified wheel message remains vertical.")
        XCTAssertEqual(recorder.scrollSources, [.systemManaged, .systemManaged])
    }
}
