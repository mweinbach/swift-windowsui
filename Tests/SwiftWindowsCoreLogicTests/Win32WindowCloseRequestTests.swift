import SwiftWindowsCore
import WinSDK
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@MainActor
private final class CloseRequestDelegate: WindowDelegate {
    var allowsClose = true
    var decision: ((Win32Window) -> Bool)?
    var didClose: ((Win32Window) -> Void)?
    private(set) var requests = 0
    private(set) var closes = 0

    func windowShouldClose(_ window: Win32Window) -> Bool {
        requests += 1
        return decision?(window) ?? allowsClose
    }

    func windowWillClose(_ window: Win32Window) {
        closes += 1
        didClose?(window)
    }
}

@MainActor
private final class DefaultCloseRequestDelegate: WindowDelegate {}

/// Owned hidden HWNDs only. Every test destroys its own remaining window;
/// none enters an unbounded message loop or posts WM_QUIT into XCTest.
@MainActor
final class Win32WindowCloseRequestTests: XCTestCase {
    private func makeWindow(delegate: any WindowDelegate) throws -> Win32Window {
        let window = Win32Window(title: "Close preflight test", clientSize: IntSize(width: 160, height: 100))
        window.postsQuitMessageOnDestroy = false
        window.delegate = delegate
        do {
            try window.create()
        } catch {
            throw XCTSkip("This environment cannot create an owned test window: \(error)")
        }
        return window
    }

    private func nativeHandle(_ window: Win32Window) throws -> HWND {
        let raw = try XCTUnwrap(window.nativeHandle?.rawPointer)
        return try XCTUnwrap(HWND(bitPattern: Int(bitPattern: raw)))
    }

    private func destroyRemainingWindow(_ window: Win32Window) {
        if let raw = window.nativeHandle?.rawPointer {
            DestroyWindow(HWND(bitPattern: Int(bitPattern: raw)))
        }
    }

    private func dispatchPostedCloses(to handle: HWND) {
        for _ in 0..<8 {
            var message = MSG()
            guard PeekMessageW(&message, handle, UINT(WM_CLOSE), UINT(WM_CLOSE), UINT(PM_REMOVE)) else { return }
            DispatchMessageW(&message)
        }
        XCTFail("Close requests did not settle within the bounded message drain.")
    }

    func testRejectedNativeRequestsKeepWindowAliveUntilALaterApproval() async throws {
        let recorder = CloseRequestDelegate()
        recorder.allowsClose = false
        let window = try makeWindow(delegate: recorder)
        defer { destroyRemainingWindow(window) }
        let handle = try nativeHandle(window)
        let backPointer = GetWindowLongPtrW(handle, GWLP_USERDATA)

        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)
        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)

        XCTAssertEqual(recorder.requests, 2)
        XCTAssertEqual(recorder.closes, 0)
        XCTAssertTrue(IsWindow(handle))
        XCTAssertEqual(GetWindowLongPtrW(handle, GWLP_USERDATA), backPointer)
        XCTAssertEqual(try nativeHandle(window), handle)

        recorder.allowsClose = true
        window.requestClose()
        XCTAssertTrue(IsWindow(handle), "requestClose must wait for native message delivery.")
        dispatchPostedCloses(to: handle)

        XCTAssertEqual(recorder.requests, 3)
        XCTAssertEqual(recorder.closes, 1)
        XCTAssertNil(window.nativeHandle)
    }

    func testDefaultDelegateApprovesOrdinaryClose() async throws {
        let recorder = DefaultCloseRequestDelegate()
        let window = try makeWindow(delegate: recorder)
        defer { destroyRemainingWindow(window) }

        SendMessageW(try nativeHandle(window), UINT(WM_CLOSE), 0, 0)

        XCTAssertNil(window.nativeHandle)
    }

    func testSystemCloseCommandUsesTheSamePreflight() async throws {
        let recorder = CloseRequestDelegate()
        recorder.allowsClose = false
        let window = try makeWindow(delegate: recorder)
        defer { destroyRemainingWindow(window) }
        let handle = try nativeHandle(window)

        SendMessageW(handle, UINT(WM_SYSCOMMAND), WPARAM(SC_CLOSE), 0)
        XCTAssertEqual(recorder.requests, 1)
        XCTAssertEqual(recorder.closes, 0)
        XCTAssertTrue(IsWindow(handle))

        recorder.allowsClose = true
        SendMessageW(handle, UINT(WM_SYSCOMMAND), WPARAM(SC_CLOSE), 0)
        XCTAssertEqual(recorder.requests, 2)
        XCTAssertEqual(recorder.closes, 1)
        XCTAssertNil(window.nativeHandle)
    }

    func testSynchronousAndPostedReentrantRequestsDoNotReenterTheDecision() async throws {
        let recorder = CloseRequestDelegate()
        let window = try makeWindow(delegate: recorder)
        defer { destroyRemainingWindow(window) }
        let handle = try nativeHandle(window)
        recorder.decision = { window in
            SendMessageW(handle, UINT(WM_CLOSE), 0, 0)
            window.requestClose()
            return false
        }

        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)
        dispatchPostedCloses(to: handle)
        XCTAssertEqual(recorder.requests, 1)
        XCTAssertEqual(recorder.closes, 0)
        XCTAssertTrue(IsWindow(handle))

        recorder.decision = nil
        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)
        XCTAssertEqual(recorder.requests, 2)
        XCTAssertEqual(recorder.closes, 1)
    }

    func testDecisionMayDestroyTheWindowWithoutASecondDestruction() async throws {
        let recorder = CloseRequestDelegate()
        let window = try makeWindow(delegate: recorder)
        defer { destroyRemainingWindow(window) }
        let handle = try nativeHandle(window)
        recorder.decision = { _ in
            DestroyWindow(handle)
            return true
        }
        recorder.didClose = { $0.requestClose() }

        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)

        XCTAssertEqual(recorder.requests, 1)
        XCTAssertEqual(recorder.closes, 1)
        XCTAssertNil(window.nativeHandle)
    }

    func testCloseKeepsWindowAliveWhileDelegateDropsItsLastOwner() async throws {
        let recorder = CloseRequestDelegate()
        var owner: Win32Window? = try makeWindow(delegate: recorder)
        weak var probe = owner
        let handle = try nativeHandle(try XCTUnwrap(owner))
        defer {
            if let owner { destroyRemainingWindow(owner) }
        }
        recorder.didClose = { _ in owner = nil }

        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)

        XCTAssertEqual(recorder.requests, 1)
        XCTAssertEqual(recorder.closes, 1)
        XCTAssertNil(owner)
        XCTAssertNil(probe, "All nested wndproc frames must return before the final strong reference is released.")
    }

    func testDisabledCloseAffordanceIsRememberedBeforeNativeCreation() async throws {
        let recorder = CloseRequestDelegate()
        let window = Win32Window(title: "Disabled close test", clientSize: IntSize(width: 160, height: 100))
        window.postsQuitMessageOnDestroy = false
        window.delegate = recorder
        window.setCloseButtonEnabled(false)
        do {
            try window.create()
        } catch {
            throw XCTSkip("This environment cannot create an owned test window: \(error)")
        }
        defer { destroyRemainingWindow(window) }
        let handle = try nativeHandle(window)
        let menu = try XCTUnwrap(GetSystemMenu(handle, false))

        XCTAssertNotEqual(GetMenuState(menu, UINT(SC_CLOSE), UINT(MF_BYCOMMAND)) & UINT(MF_GRAYED), 0)
        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)
        XCTAssertEqual(recorder.requests, 1, "A delivered request still consults the current delegate.")
        XCTAssertEqual(recorder.closes, 0)

        window.setCloseButtonEnabled(true)
        XCTAssertEqual(GetMenuState(menu, UINT(SC_CLOSE), UINT(MF_BYCOMMAND)) & UINT(MF_GRAYED), 0)
        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)
        XCTAssertEqual(recorder.closes, 1)
    }

    func testMissingSystemMenuDoesNotRemoveTheCloseVeto() async throws {
        let recorder = CloseRequestDelegate()
        let window = Win32Window(
            title: "Hidden titlebar close test", clientSize: IntSize(width: 160, height: 100),
            titleBarVisibility: .hidden)
        window.postsQuitMessageOnDestroy = false
        window.delegate = recorder
        window.setCloseButtonEnabled(false)
        do {
            try window.create()
        } catch {
            throw XCTSkip("This environment cannot create an owned test window: \(error)")
        }
        defer { destroyRemainingWindow(window) }
        let handle = try nativeHandle(window)
        XCTAssertNil(GetSystemMenu(handle, false))

        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)
        XCTAssertTrue(IsWindow(handle))
        XCTAssertEqual(recorder.closes, 0)

        window.setCloseButtonEnabled(true)
        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)
        XCTAssertNil(window.nativeHandle)
        XCTAssertEqual(recorder.closes, 1)
    }

    func testHiddenTitleBarStylePreservesPopupBitWithoutCreatingAWindow() async {
        let window = Win32Window(
            title: "Popup style mask", clientSize: IntSize(width: 160, height: 100), titleBarVisibility: .hidden)
        let style = window.windowStyle
        XCTAssertEqual(style & DWORD(WS_POPUP), DWORD(WS_POPUP))
        XCTAssertNotEqual(style & DWORD(WS_THICKFRAME), 0)
        XCTAssertNotEqual(style & DWORD(WS_MAXIMIZEBOX), 0)
        XCTAssertEqual(style & DWORD(WS_SYSMENU), 0)
        XCTAssertNil(window.nativeHandle)
    }

    func testFixedHiddenTitleBarStyleKeepsPopupAndRemovesResizeBits() async {
        let window = Win32Window(
            title: "Fixed popup style mask", clientSize: IntSize(width: 160, height: 100),
            titleBarVisibility: .hidden, configuration: Win32WindowConfiguration(resizability: .fixedSize))
        let style = window.windowStyle
        XCTAssertEqual(style & DWORD(WS_POPUP), DWORD(WS_POPUP))
        XCTAssertEqual(style & DWORD(WS_THICKFRAME), 0)
        XCTAssertEqual(style & DWORD(WS_MAXIMIZEBOX), 0)
        XCTAssertNotEqual(style & DWORD(WS_MINIMIZEBOX), 0)
        XCTAssertNil(window.nativeHandle)
    }

    func testApprovalForAnOldLifetimeCannotDestroyARecreatedWindow() async throws {
        let recorder = CloseRequestDelegate()
        let window = try makeWindow(delegate: recorder)
        defer { destroyRemainingWindow(window) }
        let oldHandle = try nativeHandle(window)
        var recreationError: Error?
        recorder.decision = { window in
            DestroyWindow(oldHandle)
            do {
                try window.create()
            } catch {
                recreationError = error
            }
            return true
        }

        SendMessageW(oldHandle, UINT(WM_CLOSE), 0, 0)

        XCTAssertNil(recreationError)
        XCTAssertEqual(recorder.requests, 1)
        XCTAssertEqual(recorder.closes, 1)
        let newHandle = try nativeHandle(window)
        XCTAssertTrue(IsWindow(newHandle), "Even a reused HWND value must not inherit the old request's approval.")
        recorder.decision = nil
        SendMessageW(newHandle, UINT(WM_CLOSE), 0, 0)
        XCTAssertEqual(recorder.closes, 2)
    }

    func testRequestsWithoutAnOwnedHandleDoNotPostProcessQuit() async throws {
        var quitMessage = MSG()
        try XCTSkipUnless(
            !PeekMessageW(&quitMessage, nil, UINT(WM_QUIT), UINT(WM_QUIT), UINT(PM_NOREMOVE)),
            "Another test already has a quit message pending on this thread.")
        let uncreated = Win32Window(title: "No native window", clientSize: IntSize(width: 100, height: 80))
        uncreated.requestClose()
        XCTAssertFalse(PeekMessageW(&quitMessage, nil, UINT(WM_QUIT), UINT(WM_QUIT), UINT(PM_NOREMOVE)))

        let recorder = CloseRequestDelegate()
        let window = try makeWindow(delegate: recorder)
        defer { destroyRemainingWindow(window) }
        SendMessageW(try nativeHandle(window), UINT(WM_CLOSE), 0, 0)
        window.requestClose()
        window.requestClose()
        XCTAssertEqual(recorder.closes, 1)
        XCTAssertFalse(PeekMessageW(&quitMessage, nil, UINT(WM_QUIT), UINT(WM_QUIT), UINT(PM_NOREMOVE)))
    }
}
