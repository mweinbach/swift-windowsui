import Foundation
import SwiftWindowsCore
import WinSDK
import XCTest

@testable import SwiftWindowsPlatform

// These fixtures own hidden HWNDs and use real DestroyWindow/CreateWindowExW
// delivery. They never synthesize WM_DESTROY/WM_NCDESTROY, show a window, or
// enter a message loop. The adapters observe the cleanup request; they do not
// claim to observe Windows releasing its internal UIA event-map references.
private struct UIACleanupGetObjectCall: Equatable {
    let handle: UInt?
    let wParam: WPARAM
    let lParam: LPARAM
}

@MainActor
private final class UIACleanupProvider: Win32WindowAccessibilityProvider {
    var result: LRESULT?
    var calls: [UIACleanupGetObjectCall] = []
    var onQuery: (@MainActor (UIACleanupGetObjectCall) -> LRESULT?)?

    init(result: LRESULT? = 901) { self.result = result }

    func handleAccessibilityGetObject(
        hwnd: UnsafeMutableRawPointer?, wParam: WPARAM, lParam: LPARAM
    ) -> LRESULT? {
        let call = UIACleanupGetObjectCall(
            handle: hwnd.map { UInt(bitPattern: $0) }, wParam: wParam, lParam: lParam)
        calls.append(call)
        let action = onQuery
        onQuery = nil
        if let action { return action(call) }
        return result
    }
}

@MainActor
private final class UIACleanupRecorder: WindowDelegate {
    var events: [String] = []
    var creations = 0
    var closes = 0
    var preflights = 0
    var allowsClose = true
    var cleanupHandles: [UInt] = []
    var cleanupBackPointers: [LONG_PTR] = []
    var defaults: [UIACleanupGetObjectCall] = []
    var defaultResult: LRESULT = 503
    var onWillClose: (@MainActor (Win32Window) -> Void)?
    var onCleanup: (@MainActor (HWND) -> Void)?
    var onDefault: (@MainActor (HWND?, WPARAM, LPARAM) -> LRESULT)?

    func windowDidCreate(_ window: Win32Window) {
        creations += 1
        events.append("created")
    }

    func windowShouldClose(_ window: Win32Window) -> Bool {
        preflights += 1
        return allowsClose
    }

    func windowWillClose(_ window: Win32Window) {
        closes += 1
        events.append("delegate.begin")
        let action = onWillClose
        onWillClose = nil
        action?(window)
        events.append("delegate.end")
    }

    func requestCleanup(_ handle: HWND) {
        cleanupHandles.append(UInt(bitPattern: handle))
        cleanupBackPointers.append(GetWindowLongPtrW(handle, GWLP_USERDATA))
        events.append("cleanup")
        // One-shot hooks bound test-induced reentry without hiding duplicate
        // adapter invocations, which are still recorded above.
        let action = onCleanup
        onCleanup = nil
        action?(handle)
    }

    func defaultGetObject(_ handle: HWND?, wParam: WPARAM, lParam: LPARAM) -> LRESULT {
        defaults.append(
            UIACleanupGetObjectCall(handle: handle.map { UInt(bitPattern: $0) }, wParam: wParam, lParam: lParam))
        let action = onDefault
        onDefault = nil
        return action?(handle, wParam, lParam) ?? defaultResult
    }
}

@MainActor
private func makeUIACleanupWindow(recorder: UIACleanupRecorder) -> Win32Window {
    let window = Win32Window(title: "UIA cleanup lifetime", clientSize: IntSize(width: 160, height: 100))
    window.postsQuitMessageOnDestroy = false
    window.delegate = recorder
    let cleanup: @MainActor (HWND) -> Void = { [recorder] handle in
        recorder.requestCleanup(handle)
    }
    let defaultGetObject: @MainActor (HWND?, WPARAM, LPARAM) -> LRESULT = { [recorder] handle, wParam, lParam in
        recorder.defaultGetObject(handle, wParam: wParam, lParam: lParam)
    }
    window.requestUIAEventMapCleanup = cleanup
    window.accessibilityDefaultGetObject = defaultGetObject
    return window
}

@MainActor
private func uiacCleanupHasQuit() -> Bool {
    var message = MSG()
    return PeekMessageW(&message, nil, UINT(WM_QUIT), UINT(WM_QUIT), UINT(PM_NOREMOVE))
}

@MainActor
private func uiacCleanupHandle(
    _ window: Win32Window, file: StaticString = #filePath, line: UInt = #line
) throws -> HWND {
    let raw = try XCTUnwrap(window.nativeHandle?.rawPointer, file: file, line: line)
    return try XCTUnwrap(HWND(bitPattern: Int(bitPattern: raw)), file: file, line: line)
}

@MainActor
private func uiacCleanupDestroyRemaining(_ window: Win32Window) {
    if let raw = window.nativeHandle?.rawPointer {
        DestroyWindow(HWND(bitPattern: Int(bitPattern: raw)))
    }
}

@MainActor
private func uiacCleanupCreateInitial(_ window: Win32Window) throws {
    try XCTSkipUnless(!uiacCleanupHasQuit(), "Another test has a pending WM_QUIT on this thread.")
    do {
        try window.create()
    } catch {
        uiacCleanupDestroyRemaining(window)
        throw XCTSkip("This environment cannot create an owned hidden test window: \(error)")
    }
    do {
        let handle = try uiacCleanupHandle(window)
        XCTAssertFalse(IsWindowVisible(handle))
        XCTAssertNotEqual(GetWindowLongPtrW(handle, GWLP_USERDATA), 0)
    } catch {
        uiacCleanupDestroyRemaining(window)
        throw error
    }
}

@MainActor
private func uiacCleanupExpectRejectedCreation(
    _ window: Win32Window, file: StaticString = #filePath, line: UInt = #line
) {
    window.rejectNextNativeCreationForTesting = true
    do {
        try window.create()
        XCTFail("The admitted WM_NCCREATE rejection must make native creation fail", file: file, line: line)
    } catch let failure as Win32PlatformError {
        XCTAssertEqual(failure.operation, "CreateWindowExW", file: file, line: line)
    } catch {
        XCTFail("Unexpected creation error: \(error)", file: file, line: line)
    }
    XCTAssertFalse(window.rejectNextNativeCreationForTesting, file: file, line: line)
    XCTAssertNil(window.nativeHandle, file: file, line: line)
}

@MainActor
private final class UIACleanupFixture {
    let recorder: UIACleanupRecorder
    let window: Win32Window

    init() {
        let recorder = UIACleanupRecorder()
        self.recorder = recorder
        window = makeUIACleanupWindow(recorder: recorder)
    }

    func finish(file: StaticString = #filePath, line: UInt = #line) {
        uiacCleanupDestroyRemaining(window)
        XCTAssertFalse(uiacCleanupHasQuit(), "Owned hidden windows must not post WM_QUIT", file: file, line: line)
    }
}

@MainActor
private func makeLiveUIACleanupFixture() throws -> UIACleanupFixture {
    let fixture = UIACleanupFixture()
    try uiacCleanupCreateInitial(fixture.window)
    return fixture
}

@MainActor
private final class UIACleanupCloseAuthority: Win32CloseAuthority {
    var preparations = 0

    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation {
        preparations += 1
        return .busy(.buildsNotSettled)
    }
}

@MainActor
private final class UIACleanupWindowOwner {
    var window: Win32Window?
}

private enum UIACleanupFixtureError: Error {
    case nestedDestructionDidNotComplete
}

final class Win32UIAWindowCleanupTests: XCTestCase {
    func testOrdinaryDestroyRequestsCleanupAfterItsDelegateAndOnlyOnceAcrossNativeNCDestroy() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let handle = try uiacCleanupHandle(fixture.window)
            let backPointer = GetWindowLongPtrW(handle, GWLP_USERDATA)
            XCTAssertNil(fixture.window.accessibilityProvider)
            fixture.recorder.onCleanup = { [weak fixture] supplied in
                guard let fixture else { return XCTFail("Missing cleanup fixture") }
                XCTAssertEqual(supplied, handle)
                XCTAssertEqual(fixture.recorder.closes, 1)
                XCTAssertEqual(fixture.recorder.events, ["created", "delegate.begin", "delegate.end", "cleanup"])
                XCTAssertEqual(fixture.window.nativeHandle?.rawPointer, UnsafeMutableRawPointer(handle))
                XCTAssertEqual(GetWindowLongPtrW(supplied, GWLP_USERDATA), backPointer)
            }

            XCTAssertTrue(DestroyWindow(handle))

            XCTAssertNil(fixture.window.nativeHandle)
            XCTAssertFalse(IsWindow(handle))
            XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: handle)])
            XCTAssertEqual(fixture.recorder.cleanupBackPointers, [backPointer])
            XCTAssertEqual(fixture.recorder.closes, 1)
            XCTAssertTrue(fixture.recorder.defaults.isEmpty)
            XCTAssertFalse(uiacCleanupHasQuit())
        }
    }

    func testRemovingOrReplacingTheProviderDuringDelegateTeardownDoesNotSkipCleanup() async throws {
        try await MainActor.run {
            for replace in [false, true] {
                let fixture = try makeLiveUIACleanupFixture()
                defer { fixture.finish() }
                let handle = try uiacCleanupHandle(fixture.window)
                let original = UIACleanupProvider()
                let replacement = UIACleanupProvider(result: 902)
                fixture.window.accessibilityProvider = original
                XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 0, -25), LRESULT(901))
                fixture.recorder.onWillClose = { window in
                    window.accessibilityProvider = replace ? replacement : nil
                }

                XCTAssertTrue(DestroyWindow(handle))

                XCTAssertEqual(original.calls.count, 1)
                XCTAssertTrue(replacement.calls.isEmpty)
                XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: handle)])
                XCTAssertEqual(fixture.recorder.events, ["created", "delegate.begin", "delegate.end", "cleanup"])
                XCTAssertNil(fixture.window.nativeHandle)
                XCTAssertTrue(fixture.recorder.defaults.isEmpty)
            }
        }
    }

    func testRealNestedDestroyAndGetObjectReentryCannotRepeatCleanupOrPublishProviders() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let handle = try uiacCleanupHandle(fixture.window)
            let provider = UIACleanupProvider()
            fixture.window.accessibilityProvider = provider
            var delegateReentered = false
            var cleanupReentered = false
            fixture.recorder.onWillClose = { [weak fixture] _ in
                guard let fixture else { return XCTFail("Missing destroy fixture") }
                XCTAssertTrue(fixture.recorder.cleanupHandles.isEmpty, "Ordinary delegate teardown precedes the claim")
                XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 0, -25), LRESULT(0))
                delegateReentered = true
                // Windows decides whether an already-destroying HWND accepts
                // this nested request. No fabricated destroy message is sent.
                _ = DestroyWindow(handle)
            }
            fixture.recorder.onCleanup = { [weak fixture] supplied in
                guard let fixture else { return XCTFail("Missing cleanup fixture") }
                XCTAssertEqual(fixture.recorder.cleanupHandles.count, 1)
                XCTAssertEqual(SendMessageW(supplied, UINT(WM_GETOBJECT), 0, -25), LRESULT(0))
                cleanupReentered = true
                _ = DestroyWindow(supplied)
                XCTAssertEqual(fixture.recorder.cleanupHandles.count, 1)
            }

            XCTAssertTrue(DestroyWindow(handle))

            XCTAssertTrue(delegateReentered)
            XCTAssertTrue(cleanupReentered)
            XCTAssertEqual(fixture.recorder.closes, 1)
            XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: handle)])
            XCTAssertEqual(fixture.recorder.events.filter { $0 == "cleanup" }.count, 1)
            XCTAssertTrue(provider.calls.isEmpty)
            XCTAssertTrue(fixture.recorder.defaults.isEmpty)
            XCTAssertNil(fixture.window.nativeHandle)
        }
    }

    func testProviderReturningAValueOrNilAfterDestroyCannotReachDefaultOrPublishAResult() async throws {
        try await MainActor.run {
            let results: [LRESULT?] = [901, nil]
            for returned in results {
                let fixture = try makeLiveUIACleanupFixture()
                defer { fixture.finish() }
                let handle = try uiacCleanupHandle(fixture.window)
                let provider = UIACleanupProvider(result: returned)
                fixture.window.accessibilityProvider = provider
                provider.onQuery = { _ in
                    XCTAssertTrue(DestroyWindow(handle))
                    return returned
                }

                let result = SendMessageW(handle, UINT(WM_GETOBJECT), 7, -25)

                XCTAssertEqual(result, LRESULT(0))
                XCTAssertEqual(
                    provider.calls,
                    [UIACleanupGetObjectCall(handle: UInt(bitPattern: handle), wParam: 7, lParam: -25)])
                XCTAssertTrue(fixture.recorder.defaults.isEmpty, "A nil callback result still requires revalidation")
                XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: handle)])
                XCTAssertEqual(fixture.recorder.closes, 1)
                XCTAssertNil(fixture.window.nativeHandle)
            }
        }
    }

    func testDefaultGetObjectResultIsSuppressedWhenTheDefaultCallbackDestroysTheWindow() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let handle = try uiacCleanupHandle(fixture.window)
            XCTAssertNil(fixture.window.accessibilityProvider)
            XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 3, -4), LRESULT(503))
            fixture.recorder.onDefault = { supplied, wParam, lParam in
                XCTAssertEqual(supplied, handle)
                XCTAssertEqual(wParam, WPARAM(8))
                XCTAssertEqual(lParam, LPARAM(-25))
                XCTAssertTrue(DestroyWindow(handle))
                return 777
            }

            XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 8, -25), LRESULT(0))

            XCTAssertEqual(fixture.recorder.defaults.count, 2)
            XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: handle)])
            XCTAssertEqual(fixture.recorder.closes, 1)
            XCTAssertNil(fixture.window.nativeHandle)
        }
    }

    func testSameSwiftWindowRequestsFreshCleanupForEveryRecreatedNativeLifetime() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let provider = UIACleanupProvider()
            fixture.window.accessibilityProvider = provider
            let first = try uiacCleanupHandle(fixture.window)
            XCTAssertTrue(DestroyWindow(first))
            XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: first)])

            try fixture.window.create()
            let second = try uiacCleanupHandle(fixture.window)
            XCTAssertFalse(IsWindowVisible(second))
            XCTAssertEqual(SendMessageW(second, UINT(WM_GETOBJECT), 0, -25), LRESULT(901))
            XCTAssertEqual(fixture.recorder.cleanupHandles.count, 1)
            XCTAssertTrue(DestroyWindow(second))

            // The values may be equal if Windows reused an HWND. The second
            // native lifetime must still own an independent cleanup claim.
            XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: first), UInt(bitPattern: second)])
            XCTAssertEqual(fixture.recorder.creations, 2)
            XCTAssertEqual(fixture.recorder.closes, 2)
            XCTAssertNil(fixture.window.nativeHandle)
        }
    }

    func testCleanupOfOneWindowCanQueryAndDestroyAnIndependentWindow() async throws {
        try await MainActor.run {
            let first = try makeLiveUIACleanupFixture()
            defer { first.finish() }
            let second = try makeLiveUIACleanupFixture()
            defer { second.finish() }
            let firstHandle = try uiacCleanupHandle(first.window)
            let secondHandle = try uiacCleanupHandle(second.window)
            let provider = UIACleanupProvider(result: 944)
            second.window.accessibilityProvider = provider
            var nestedQuery: LRESULT?
            first.recorder.onCleanup = { [weak second] _ in
                guard let second else { return XCTFail("Missing second window fixture") }
                XCTAssertTrue(second.recorder.cleanupHandles.isEmpty)
                nestedQuery = SendMessageW(secondHandle, UINT(WM_GETOBJECT), 0, -25)
                XCTAssertTrue(DestroyWindow(secondHandle))
            }

            XCTAssertTrue(DestroyWindow(firstHandle))

            XCTAssertEqual(nestedQuery, LRESULT(944))
            XCTAssertEqual(provider.calls.count, 1)
            XCTAssertEqual(first.recorder.cleanupHandles, [UInt(bitPattern: firstHandle)])
            XCTAssertEqual(second.recorder.cleanupHandles, [UInt(bitPattern: secondHandle)])
            XCTAssertEqual(first.recorder.closes, 1)
            XCTAssertEqual(second.recorder.closes, 1)
            XCTAssertNil(first.window.nativeHandle)
            XCTAssertNil(second.window.nativeHandle)
        }
    }

    func testVetoAndBuildBusyCloseAttemptsDoNotRequestUIACleanup() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let handle = try uiacCleanupHandle(fixture.window)
            let authority = UIACleanupCloseAuthority()
            defer { withExtendedLifetime(authority) {} }
            let registration = try XCTUnwrap(fixture.window.installCloseAuthority(authority))
            let rejected = try XCTUnwrap(registration.makeTicket(intentID: Foundation.UUID()))
            fixture.recorder.allowsClose = false

            XCTAssertEqual(fixture.window.attemptClose(ticket: rejected), .vetoed)

            XCTAssertFalse(rejected.isCurrent)
            XCTAssertEqual(authority.preparations, 0)
            XCTAssertTrue(fixture.recorder.cleanupHandles.isEmpty)
            XCTAssertTrue(IsWindow(handle))
            fixture.recorder.allowsClose = true
            let busy = try XCTUnwrap(registration.makeTicket(intentID: Foundation.UUID()))

            XCTAssertEqual(fixture.window.attemptClose(ticket: busy), .busy(.buildsNotSettled))

            XCTAssertTrue(busy.isCurrent)
            XCTAssertEqual(authority.preparations, 1)
            XCTAssertEqual(fixture.recorder.preflights, 2)
            XCTAssertEqual(fixture.recorder.closes, 0)
            XCTAssertTrue(fixture.recorder.cleanupHandles.isEmpty)
            XCTAssertTrue(IsWindow(handle))
            XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 0, -25), LRESULT(503))
            XCTAssertTrue(DestroyWindow(handle))
            XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: handle)])
        }
    }

    func testFailedStartupDestructionRequestsCleanupEvenWhenOrdinaryCloseIsVetoed() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let handle = try uiacCleanupHandle(fixture.window)
            fixture.recorder.allowsClose = false
            SendMessageW(handle, UINT(WM_CLOSE), 0, 0)
            XCTAssertEqual(fixture.recorder.preflights, 1)
            XCTAssertTrue(fixture.recorder.cleanupHandles.isEmpty)
            XCTAssertTrue(IsWindow(handle))

            fixture.window.destroyForFailedStartup()
            fixture.window.destroyForFailedStartup()

            XCTAssertEqual(fixture.recorder.preflights, 1)
            XCTAssertEqual(fixture.recorder.closes, 1)
            XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: handle)])
            XCTAssertNil(fixture.window.nativeHandle)
        }
    }

    func testRejectedNativeCreationRequestsNCOnlyCleanupAndDoesNotPoisonTheNextCreation() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let first = try uiacCleanupHandle(fixture.window)
            XCTAssertTrue(DestroyWindow(first))
            var failedHandle: HWND?
            fixture.recorder.onCleanup = { [weak fixture] handle in
                guard let fixture else { return XCTFail("Missing rejected-creation fixture") }
                failedHandle = handle
                XCTAssertNil(fixture.window.nativeHandle, "Early failed creation has no published HWND")
                XCTAssertEqual(fixture.recorder.creations, 1)
                XCTAssertEqual(fixture.recorder.closes, 1, "The rejected WM_NCCREATE does not deliver WM_DESTROY")
                XCTAssertNotEqual(GetWindowLongPtrW(handle, GWLP_USERDATA), 0)
            }

            uiacCleanupExpectRejectedCreation(fixture.window)

            let rejected = try XCTUnwrap(failedHandle)
            XCTAssertFalse(IsWindow(rejected))
            XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: first), UInt(bitPattern: rejected)])
            XCTAssertEqual(Array(fixture.recorder.events.suffix(1)), ["cleanup"])
            try fixture.window.create()
            let replacement = try uiacCleanupHandle(fixture.window)
            XCTAssertFalse(IsWindowVisible(replacement))
            XCTAssertEqual(SendMessageW(replacement, UINT(WM_GETOBJECT), 0, -25), LRESULT(503))
            XCTAssertTrue(DestroyWindow(replacement))
            XCTAssertEqual(fixture.recorder.cleanupHandles.count, 3)
            XCTAssertEqual(fixture.recorder.cleanupHandles.last, UInt(bitPattern: replacement))
            XCTAssertEqual(fixture.recorder.creations, 2)
            XCTAssertEqual(fixture.recorder.closes, 2)
        }
    }

    func testNCOnlyCleanupDeniesGetObjectBeforeTheBackPointerIsCleared() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let first = try uiacCleanupHandle(fixture.window)
            XCTAssertTrue(DestroyWindow(first))
            let provider = UIACleanupProvider()
            let replacement = UIACleanupProvider(result: 955)
            fixture.window.accessibilityProvider = provider
            var entered = false
            fixture.recorder.onCleanup = { [weak fixture] handle in
                guard let fixture else { return XCTFail("Missing NC-only fixture") }
                entered = true
                XCTAssertNotEqual(GetWindowLongPtrW(handle, GWLP_USERDATA), 0)
                XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
                XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 0, -25), LRESULT(0))
                fixture.window.accessibilityProvider = replacement
                XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 0, -25), LRESULT(0))
                fixture.window.accessibilityProvider = nil
                XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 0, -4), LRESULT(0))
            }

            uiacCleanupExpectRejectedCreation(fixture.window)

            XCTAssertTrue(entered)
            XCTAssertEqual(fixture.recorder.closes, 1)
            XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
            XCTAssertTrue(provider.calls.isEmpty)
            XCTAssertTrue(replacement.calls.isEmpty)
            XCTAssertTrue(fixture.recorder.defaults.isEmpty)
        }
    }

    func testReentrantCreateDuringNCOnlyCleanupCannotPublishAnotherHandleOrCarryTheOneShotFlag() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let first = try uiacCleanupHandle(fixture.window)
            XCTAssertTrue(DestroyWindow(first))
            var reentered = false
            var reentryError: Error?
            fixture.recorder.onCleanup = { [weak fixture] handle in
                guard let fixture else { return XCTFail("Missing reentrant-creation fixture") }
                XCTAssertNil(fixture.window.nativeHandle)
                XCTAssertNotEqual(GetWindowLongPtrW(handle, GWLP_USERDATA), 0)
                fixture.window.rejectNextNativeCreationForTesting = true
                reentered = true
                do {
                    try fixture.window.create()
                } catch {
                    reentryError = error
                }
                XCTAssertNil(fixture.window.nativeHandle, "The old native backpointer still owns this object")
                XCTAssertFalse(
                    fixture.window.rejectNextNativeCreationForTesting, "Every create entry consumes the flag")
                XCTAssertEqual(fixture.recorder.creations, 1)
                XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
            }

            uiacCleanupExpectRejectedCreation(fixture.window)

            XCTAssertTrue(reentered)
            XCTAssertNil(reentryError, "The ownership guard refuses creation without entering CreateWindowExW")
            XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
            try fixture.window.create()
            let replacement = try uiacCleanupHandle(fixture.window)
            XCTAssertFalse(IsWindowVisible(replacement))
            XCTAssertEqual(fixture.recorder.creations, 2)
            XCTAssertTrue(DestroyWindow(replacement))
            XCTAssertEqual(fixture.recorder.cleanupHandles.count, 3)
        }
    }

    func testDestroyDelegateMayDropTheLastSwiftOwnerBeforeNativeCleanupFinishes() async throws {
        try await MainActor.run {
            let recorder = UIACleanupRecorder()
            let owner = UIACleanupWindowOwner()
            owner.window = makeUIACleanupWindow(recorder: recorder)
            weak var window = owner.window
            defer {
                if let remaining = owner.window { uiacCleanupDestroyRemaining(remaining) }
                XCTAssertFalse(uiacCleanupHasQuit())
            }
            try uiacCleanupCreateInitial(try XCTUnwrap(owner.window))
            let handle = try uiacCleanupHandle(try XCTUnwrap(owner.window))
            recorder.onWillClose = { [weak owner] _ in owner?.window = nil }
            var cleanupSawOwnedWindow = false
            recorder.onCleanup = { supplied in
                cleanupSawOwnedWindow = window != nil
                XCTAssertEqual(supplied, handle)
                XCTAssertNotEqual(GetWindowLongPtrW(supplied, GWLP_USERDATA), 0)
            }

            XCTAssertTrue(DestroyWindow(handle))

            XCTAssertTrue(cleanupSawOwnedWindow)
            XCTAssertNil(owner.window)
            XCTAssertNil(window, "WM_NCDESTROY must release the retained self reference exactly once")
            XCTAssertEqual(recorder.closes, 1)
            XCTAssertEqual(recorder.cleanupHandles, [UInt(bitPattern: handle)])
        }
    }

    func testNCOnlyFailureCanDropItsSwiftOwnerAndStillBalanceTheNativeSelfReference() async throws {
        try await MainActor.run {
            let recorder = UIACleanupRecorder()
            let owner = UIACleanupWindowOwner()
            owner.window = makeUIACleanupWindow(recorder: recorder)
            weak var window = owner.window
            defer {
                if let remaining = owner.window { uiacCleanupDestroyRemaining(remaining) }
                XCTAssertFalse(uiacCleanupHasQuit())
            }
            try uiacCleanupCreateInitial(try XCTUnwrap(owner.window))
            let first = try uiacCleanupHandle(try XCTUnwrap(owner.window))
            XCTAssertTrue(DestroyWindow(first))
            var cleanupSawOwnedWindow = false
            recorder.onCleanup = { [weak owner] handle in
                owner?.window = nil
                cleanupSawOwnedWindow = window != nil
                XCTAssertNotEqual(GetWindowLongPtrW(handle, GWLP_USERDATA), 0)
            }

            uiacCleanupExpectRejectedCreation(try XCTUnwrap(owner.window))

            XCTAssertTrue(cleanupSawOwnedWindow)
            XCTAssertNil(owner.window)
            XCTAssertNil(window, "Creation's catch path must neither leak nor release the NC-owned reference twice")
            XCTAssertEqual(recorder.creations, 1)
            XCTAssertEqual(recorder.closes, 1)
            XCTAssertEqual(recorder.cleanupHandles.count, 2)
        }
    }

    func testLiveGetObjectPreservesProviderAndDefaultRoutingAndMessageArguments() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let handle = try uiacCleanupHandle(fixture.window)
            let provider = UIACleanupProvider()
            fixture.window.accessibilityProvider = provider

            XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 41, -25), LRESULT(901))

            XCTAssertEqual(
                provider.calls,
                [UIACleanupGetObjectCall(handle: UInt(bitPattern: handle), wParam: 41, lParam: -25)])
            XCTAssertTrue(fixture.recorder.defaults.isEmpty)
            provider.result = nil

            XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 42, -4), LRESULT(503))

            XCTAssertEqual(provider.calls.count, 2)
            XCTAssertEqual(
                fixture.recorder.defaults,
                [UIACleanupGetObjectCall(handle: UInt(bitPattern: handle), wParam: 42, lParam: -4)])
            fixture.window.accessibilityProvider = nil
            XCTAssertEqual(SendMessageW(handle, UINT(WM_GETOBJECT), 43, -25), LRESULT(503))
            XCTAssertEqual(fixture.recorder.defaults.last?.wParam, WPARAM(43))
            XCTAssertEqual(fixture.recorder.defaults.last?.lParam, LPARAM(-25))
            SendMessageW(handle, UINT(WM_NULL), 0, 0)
            XCTAssertEqual(fixture.recorder.defaults.count, 2, "The injected default is exclusive to WM_GETOBJECT")
            XCTAssertTrue(fixture.recorder.cleanupHandles.isEmpty)
            XCTAssertTrue(IsWindow(handle))
            XCTAssertFalse(IsWindowVisible(handle))
        }
    }

    func testRecreationInsideProviderOrDefaultCannotPublishAnOldResultOrReuseItsCleanupClaim() async throws {
        try await MainActor.run {
            for useProvider in [false, true] {
                let fixture = try makeLiveUIACleanupFixture()
                defer { fixture.finish() }
                let oldHandle = try uiacCleanupHandle(fixture.window)
                let provider = UIACleanupProvider()
                var recreationError: Error?
                let recreate: @MainActor () -> Void = { [weak fixture] in
                    guard let fixture else { return XCTFail("Missing recreation fixture") }
                    XCTAssertTrue(DestroyWindow(oldHandle))
                    do {
                        try fixture.window.create()
                    } catch {
                        recreationError = error
                    }
                }
                if useProvider {
                    fixture.window.accessibilityProvider = provider
                    provider.onQuery = { _ in
                        recreate()
                        return 988
                    }
                } else {
                    fixture.recorder.onDefault = { _, _, _ in
                        recreate()
                        return 977
                    }
                }

                XCTAssertEqual(SendMessageW(oldHandle, UINT(WM_GETOBJECT), 0, -25), LRESULT(0))

                XCTAssertNil(recreationError)
                let current = try uiacCleanupHandle(fixture.window)
                XCTAssertTrue(IsWindow(current))
                XCTAssertFalse(IsWindowVisible(current))
                XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: oldHandle)])
                XCTAssertEqual(fixture.recorder.closes, 1)
                XCTAssertEqual(fixture.recorder.creations, 2)
                XCTAssertEqual(fixture.recorder.defaults.count, useProvider ? 0 : 1)
                XCTAssertEqual(
                    SendMessageW(current, UINT(WM_GETOBJECT), 0, -25),
                    useProvider ? LRESULT(901) : LRESULT(503))
                XCTAssertTrue(DestroyWindow(current))
                XCTAssertEqual(
                    fixture.recorder.cleanupHandles, [UInt(bitPattern: oldHandle), UInt(bitPattern: current)])
                XCTAssertEqual(fixture.recorder.closes, 2)
                XCTAssertNil(fixture.window.nativeHandle)
            }
        }
    }

    func testOuterNCDestroyScopeDeniesRecreationAfterNestedNativeDestructionReleasedTheOldHandle() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let first = try uiacCleanupHandle(fixture.window)
            XCTAssertTrue(DestroyWindow(first))
            var reachedReleasedHandle = false
            var callbackError: Error?
            fixture.recorder.onCleanup = { [weak fixture] handle in
                guard let fixture else { return XCTFail("Missing outer-NC fixture") }
                XCTAssertNil(fixture.window.nativeHandle)
                let nestedDestroyed = DestroyWindow(handle)
                let oldHandleIsGone = !IsWindow(handle)
                XCTAssertTrue(nestedDestroyed, "This fixture requires actual nested native destruction")
                XCTAssertTrue(oldHandleIsGone, "The old HWND must be gone before exercising the outer-NC guard")
                guard nestedDestroyed, oldHandleIsGone else {
                    callbackError = UIACleanupFixtureError.nestedDestructionDidNotComplete
                    return
                }
                reachedReleasedHandle = true
                XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
                do {
                    try fixture.window.create()
                } catch {
                    callbackError = error
                }
                XCTAssertNil(
                    fixture.window.nativeHandle,
                    "The outer NC frame still owns teardown even after nested NC consumed the retained self reference")
                XCTAssertEqual(fixture.recorder.creations, 1)
                XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
            }

            uiacCleanupExpectRejectedCreation(fixture.window)

            if let callbackError { throw callbackError }
            XCTAssertTrue(reachedReleasedHandle)
            XCTAssertNil(fixture.window.nativeHandle)
            XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
            try fixture.window.create()
            let replacement = try uiacCleanupHandle(fixture.window)
            XCTAssertFalse(IsWindowVisible(replacement))
            XCTAssertEqual(fixture.recorder.creations, 2)
            XCTAssertTrue(DestroyWindow(replacement))
            XCTAssertEqual(fixture.recorder.cleanupHandles.count, 3)
        }
    }
}

@MainActor
private final class UIACleanupIdleCompletion: Win32DispatchWakeClient {
    private(set) var idleCalls = 0
    var completion: (@MainActor () -> Void)?

    func dispatchScopeDidBecomeIdle() -> (@MainActor () -> Void)? {
        idleCalls += 1
        let result = completion
        completion = nil
        return result
    }
}

extension Win32UIAWindowCleanupTests {
    func testNCDispatchExitCompletionCannotRecreateBeforeTheOuterCreationFailureUnwinds() async throws {
        try await MainActor.run {
            let fixture = try makeLiveUIACleanupFixture()
            defer { fixture.finish() }
            let first = try uiacCleanupHandle(fixture.window)
            XCTAssertTrue(DestroyWindow(first))
            let wake = UIACleanupIdleCompletion()
            defer { withExtendedLifetime(wake) {} }
            var events: [String] = []
            var failedHandle: HWND?
            var completionCalls = 0
            var callbackError: Error?
            var creationError: Win32PlatformError?
            wake.completion = { [weak fixture, weak wake] in
                events.append("completion.begin")
                completionCalls += 1
                guard let fixture, let wake, let failedHandle else {
                    XCTFail("Missing state for the native dispatch-exit completion")
                    return
                }
                XCTAssertEqual(wake.idleCalls, 1)
                XCTAssertEqual(
                    events, ["create.begin", "cleanup.begin", "cleanup.end", "completion.begin"])
                XCTAssertNil(fixture.window.nativeHandle)
                XCTAssertEqual(GetWindowLongPtrW(failedHandle, GWLP_USERDATA), 0)
                XCTAssertEqual(fixture.recorder.creations, 1)
                XCTAssertEqual(fixture.recorder.closes, 1)
                XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
                // NC handling and retained-self consumption have completed,
                // but the outer wndproc and CreateWindowExW have not returned.
                // IsWindow may still be true here; it is not the admission gate.
                do {
                    try fixture.window.create()
                } catch {
                    callbackError = error
                }
                XCTAssertNil(fixture.window.nativeHandle, "The outer NC scope must include dispatch-exit completions")
                XCTAssertEqual(fixture.recorder.creations, 1)
                XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
                events.append("completion.end")
            }
            fixture.recorder.onCleanup = { [weak fixture, weak wake] handle in
                events.append("cleanup.begin")
                guard let fixture, let wake else {
                    XCTFail("Missing state for the NC-only cleanup request")
                    return
                }
                failedHandle = handle
                XCTAssertNil(fixture.window.nativeHandle)
                XCTAssertNotEqual(GetWindowLongPtrW(handle, GWLP_USERDATA), 0)
                XCTAssertEqual(fixture.recorder.cleanupHandles.count, 2)
                Win32DispatchScope.requestWakeWhenIdle(wake)
                XCTAssertEqual(wake.idleCalls, 0, "The native window dispatch is still active")
                XCTAssertEqual(completionCalls, 0)
                events.append("cleanup.end")
            }
            fixture.window.rejectNextNativeCreationForTesting = true
            events.append("create.begin")

            do {
                try fixture.window.create()
                XCTFail("The admitted WM_NCCREATE rejection must fail the outer creation")
            } catch let failure as Win32PlatformError {
                creationError = failure
                events.append("create.catch")
            } catch {
                throw error
            }
            events.append("create.returned")

            if let callbackError { throw callbackError }
            let failure = try XCTUnwrap(creationError)
            XCTAssertEqual(failure.operation, "CreateWindowExW")
            XCTAssertEqual(
                events,
                [
                    "create.begin", "cleanup.begin", "cleanup.end",
                    "completion.begin", "completion.end", "create.catch", "create.returned",
                ])
            XCTAssertEqual(wake.idleCalls, 1)
            XCTAssertEqual(completionCalls, 1)
            XCTAssertNil(wake.completion)
            XCTAssertFalse(fixture.window.rejectNextNativeCreationForTesting)
            XCTAssertNil(fixture.window.nativeHandle)
            let rejected = try XCTUnwrap(failedHandle)
            XCTAssertFalse(IsWindow(rejected), "Only check OS handle destruction after CreateWindowExW has returned")
            XCTAssertEqual(fixture.recorder.cleanupHandles, [UInt(bitPattern: first), UInt(bitPattern: rejected)])

            try fixture.window.create()
            let replacement = try uiacCleanupHandle(fixture.window)
            XCTAssertFalse(IsWindowVisible(replacement))
            XCTAssertEqual(fixture.recorder.creations, 2)
            XCTAssertTrue(DestroyWindow(replacement))
            XCTAssertEqual(fixture.recorder.cleanupHandles.count, 3)
            XCTAssertEqual(fixture.recorder.closes, 2)
        }
    }
}
