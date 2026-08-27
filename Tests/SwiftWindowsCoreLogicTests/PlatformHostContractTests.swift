import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI

/// Proves that a complete window/event lifecycle can be supplied by a host
/// containing no Win32 window, native handle, or rendering backend.
///
/// Win32 adapter coverage separately pins backward-compatible forwarding to
/// the concrete delegate used by the current Windows application.
@MainActor
final class PlatformHostContractTests: XCTestCase {
    private final class EventRecorder: PlatformWindowHost {
        var events: [PlatformWindowEvent] = []
        var windowTitles: [String] = []
        var caretRect: Rect?
        var allowsClose = true
        private(set) var closeRequestCount = 0

        func platformWindowShouldClose(_ window: any PlatformWindow) -> Bool {
            closeRequestCount += 1
            return allowsClose
        }

        func platformWindow(_ window: any PlatformWindow, didReceive event: PlatformWindowEvent) {
            windowTitles.append(window.title)
            events.append(event)
        }

        func platformWindowTextInputCaretRect(_ window: any PlatformWindow) -> Rect? {
            caretRect
        }
    }

    private final class InMemoryPlatformWindow: PlatformWindow {
        let title: String
        var clientSize: IntSize
        var scaleFactor: Double = 1
        var monitorRefreshRate: UInt32 = 60
        var isMinimized = false
        weak var host: (any PlatformWindowHost)?

        private(set) var createCount = 0
        private(set) var showCount = 0
        private(set) var invalidateCount = 0
        private(set) var closeCount = 0
        private(set) var requestedTimerInterval: UInt32?

        init(configuration: PlatformWindowConfiguration) {
            title = configuration.title
            clientSize = configuration.clientSize
        }

        var nativeHandle: NativeWindowHandle? {
            nil
        }

        var effectiveScaleFactor: Double {
            guard scaleFactor.isFinite, scaleFactor > 0 else {
                return 1
            }
            return max(scaleFactor, 1)
        }

        func create() throws {
            createCount += 1
            emit(.created)
        }

        func show() {
            showCount += 1
            emit(.visibilityChanged(true))
        }

        func invalidate() {
            invalidateCount += 1
            emit(.needsDisplay)
        }

        func requestClose() {
            guard host?.platformWindowShouldClose(self) ?? true else { return }
            closeCount += 1
            emit(.willClose)
        }

        func currentClientSize() -> IntSize {
            clientSize
        }

        func setAnimationTimerEnabled(_ enabled: Bool, intervalMilliseconds: UInt32) {
            requestedTimerInterval = enabled ? intervalMilliseconds : nil
        }

        func clientRectToScreen(_ rect: Rect) -> Rect {
            Rect(
                x: rect.origin.x * effectiveScaleFactor,
                y: rect.origin.y * effectiveScaleFactor,
                width: rect.size.width * effectiveScaleFactor,
                height: rect.size.height * effectiveScaleFactor
            )
        }

        func setPlatformWindowHost(_ host: (any PlatformWindowHost)?) {
            self.host = host
        }

        func moveToDisplay(scaleFactor: Double, refreshRate: UInt32, clientSize: IntSize) {
            self.scaleFactor = scaleFactor
            monitorRefreshRate = refreshRate
            self.clientSize = clientSize
            emit(.displayChanged(scaleFactor: effectiveScaleFactor, refreshRate: refreshRate))
            emit(.resized(clientSize))
        }

        func emit(_ event: PlatformWindowEvent) {
            host?.platformWindow(self, didReceive: event)
        }
    }

    private final class InMemoryPlatformHostFactory: PlatformHostFactory {
        let platformName = "In-memory alternate platform"
        private(set) var windows: [InMemoryPlatformWindow] = []
        private(set) var eventLoopRunCount = 0
        private(set) var eventLoopTerminationCount = 0

        func makeWindow(configuration: PlatformWindowConfiguration) throws -> any PlatformWindow {
            let window = InMemoryPlatformWindow(configuration: configuration)
            windows.append(window)
            return window
        }

        func start(window: any PlatformWindow) throws {
            try window.create()
            window.show()
        }

        func runEventLoop() throws -> Int32 {
            eventLoopRunCount += 1
            return 17
        }

        func terminateEventLoop() {
            eventLoopTerminationCount += 1
        }
    }

    private final class LegacyDelegateRecorder: WindowDelegate {
        private(set) var createdCount = 0
        private(set) var pointerPositions: [Point] = []
        private(set) var keyboardEvents: [KeyboardEvent] = []
        private(set) var closeCount = 0

        var allowsClose = true
        private(set) var closeRequestCount = 0

        func windowShouldClose(_ window: Win32Window) -> Bool {
            closeRequestCount += 1
            return allowsClose
        }

        func windowDidCreate(_ window: Win32Window) {
            createdCount += 1
        }

        func window(_ window: Win32Window, pointerMovedTo point: Point) {
            pointerPositions.append(point)
        }

        func window(_ window: Win32Window, keyDown event: KeyboardEvent) {
            keyboardEvents.append(event)
        }

        func windowWillClose(_ window: Win32Window) {
            closeCount += 1
        }
    }

    func testAlternateHostCanRefuseCloseBeforeAnyTeardownEvent() async throws {
        let factory = InMemoryPlatformHostFactory()
        let recorder = EventRecorder()
        recorder.allowsClose = false
        let window = try factory.makeWindow(
            configuration: PlatformWindowConfiguration(
                title: "Refused close", clientSize: IntSize(width: 100, height: 80)))
        window.setPlatformWindowHost(recorder)

        window.requestClose()
        XCTAssertEqual(recorder.closeRequestCount, 1)
        XCTAssertTrue(recorder.events.isEmpty)

        recorder.allowsClose = true
        window.requestClose()
        XCTAssertEqual(recorder.closeRequestCount, 2)
        XCTAssertEqual(recorder.events.count, 1)
        guard case .willClose = recorder.events.first else {
            return XCTFail("Only approval should deliver teardown.")
        }
    }

    func testWin32AdapterPreservesBothConsumersCloseVetoes() async {
        let window = Win32Window(title: "Close forwarding", clientSize: IntSize(width: 100, height: 80))
        let legacy = LegacyDelegateRecorder()
        let neutral = EventRecorder()
        window.delegate = legacy
        window.setPlatformWindowHost(neutral)

        legacy.allowsClose = false
        XCTAssertEqual(window.delegate?.windowShouldClose(window), false)
        XCTAssertEqual(legacy.closeRequestCount, 1)
        XCTAssertEqual(neutral.closeRequestCount, 0)

        legacy.allowsClose = true
        neutral.allowsClose = false
        XCTAssertEqual(window.delegate?.windowShouldClose(window), false)
        XCTAssertEqual(legacy.closeRequestCount, 2)
        XCTAssertEqual(neutral.closeRequestCount, 1)

        neutral.allowsClose = true
        XCTAssertEqual(window.delegate?.windowShouldClose(window), true)
        XCTAssertEqual(legacy.closeCount, 0)
        XCTAssertTrue(neutral.events.isEmpty, "An approval query is not a teardown event.")

        window.delegate?.windowWillClose(window)
        XCTAssertEqual(legacy.closeCount, 1)
        XCTAssertEqual(neutral.events.count, 1)
    }

    func testWin32AdapterUsesLatestHostAndRestoresOriginalClosePolicy() async {
        let window = Win32Window(title: "Replaced close host", clientSize: IntSize(width: 100, height: 80))
        let legacy = LegacyDelegateRecorder()
        let first = EventRecorder()
        first.allowsClose = false
        let second = EventRecorder()
        window.delegate = legacy
        window.setPlatformWindowHost(first)
        XCTAssertEqual(window.delegate?.windowShouldClose(window), false)

        window.setPlatformWindowHost(second)
        XCTAssertEqual(window.delegate?.windowShouldClose(window), true)
        XCTAssertEqual(first.closeRequestCount, 1)
        XCTAssertEqual(second.closeRequestCount, 1)

        window.setPlatformWindowHost(nil)
        XCTAssertTrue(window.delegate === legacy)
        legacy.allowsClose = false
        XCTAssertEqual(window.delegate?.windowShouldClose(window), false)
        XCTAssertEqual(second.closeRequestCount, 1)
    }

    func testAlternateFactoryOwnsWindowLifecycleWithoutNativeWindow() async throws {
        let factory = InMemoryPlatformHostFactory()
        let recorder = EventRecorder()
        let configuration = PlatformWindowConfiguration(
            title: "Portable window",
            clientSize: IntSize(width: 640, height: 480)
        )
        let window = try factory.makeWindow(configuration: configuration)
        window.setPlatformWindowHost(recorder)

        XCTAssertNil(window.nativeHandle)
        XCTAssertEqual(window.currentClientSize(), configuration.clientSize)

        try factory.start(window: window)
        window.invalidate()
        window.setAnimationTimerEnabled(true, intervalMilliseconds: 8)
        window.requestClose()

        guard let fakeWindow = window as? InMemoryPlatformWindow else {
            return XCTFail("Expected the alternate platform's own window type.")
        }

        XCTAssertEqual(fakeWindow.createCount, 1)
        XCTAssertEqual(fakeWindow.showCount, 1)
        XCTAssertEqual(fakeWindow.invalidateCount, 1)
        XCTAssertEqual(fakeWindow.closeCount, 1)
        XCTAssertEqual(fakeWindow.requestedTimerInterval, 8)
        XCTAssertEqual(recorder.windowTitles, Array(repeating: "Portable window", count: 4))
        XCTAssertEqual(try factory.runEventLoop(), 17)
        factory.terminateEventLoop()
        XCTAssertEqual(factory.eventLoopRunCount, 1)
        XCTAssertEqual(factory.eventLoopTerminationCount, 1)

        guard case .created = recorder.events[0],
            case .visibilityChanged(true) = recorder.events[1],
            case .needsDisplay = recorder.events[2],
            case .willClose = recorder.events[3]
        else {
            return XCTFail("Expected created, shown, invalidated, and closed lifecycle events.")
        }
    }

    func testAlternatePlatformRoutesKeyboardPointerImeAndTouchWithoutWin32() async throws {
        let factory = InMemoryPlatformHostFactory()
        let recorder = EventRecorder()
        let window = try factory.makeWindow(
            configuration: PlatformWindowConfiguration(
                title: "Input host",
                clientSize: IntSize(width: 300, height: 200)
            ))
        window.setPlatformWindowHost(recorder)

        guard let fakeWindow = window as? InMemoryPlatformWindow else {
            return XCTFail("Expected an in-memory alternate-platform window.")
        }

        let position = Point(x: 32, y: 18)
        fakeWindow.emit(.pointerMoved(position))
        fakeWindow.emit(.pointerButton(MouseEvent(button: .left, position: position), phase: .down))
        fakeWindow.emit(.keyDown(KeyboardEvent(keyCode: 0x41, modifiers: [.control, .shift])))
        fakeWindow.emit(.textInput("e\u{301} 🚀"))
        fakeWindow.emit(.imeComposition(IMECompositionEvent(phase: .committed("日本語"))))
        fakeWindow.emit(.touch(phase: .began, points: [position]))
        fakeWindow.emit(.scroll(position: position, delta: 0.5, axis: .vertical, source: .precise))

        XCTAssertEqual(recorder.events.count, 7)

        guard case .pointerMoved(let actualPosition) = recorder.events[0] else {
            return XCTFail("Expected a neutral pointer event.")
        }
        XCTAssertEqual(actualPosition, position)

        guard case .keyDown(let keyboard) = recorder.events[2] else {
            return XCTFail("Expected a neutral keyboard event.")
        }
        XCTAssertEqual(keyboard.keyCode, 0x41)
        XCTAssertTrue(keyboard.modifiers.contains(.control))
        XCTAssertTrue(keyboard.modifiers.contains(.shift))

        guard case .textInput(let text) = recorder.events[3] else {
            return XCTFail("Expected Unicode text input.")
        }
        XCTAssertEqual(text, "e\u{301} 🚀")

        guard case .imeComposition(let composition) = recorder.events[4] else {
            return XCTFail("Expected an IME composition event.")
        }
        XCTAssertEqual(composition.phase, .committed("日本語"))

        guard case .scroll(_, let delta, let axis, let source) = recorder.events[6] else {
            return XCTFail("Expected a scroll event with its gesture provenance.")
        }
        XCTAssertEqual(delta, 0.5)
        XCTAssertEqual(axis, .vertical)
        XCTAssertEqual(source, .precise)
    }

    func testAlternatePlatformReportsDisplayScaleRefreshAndLogicalCoordinates() async throws {
        let factory = InMemoryPlatformHostFactory()
        let recorder = EventRecorder()
        let window = try factory.makeWindow(
            configuration: PlatformWindowConfiguration(
                title: "Display host",
                clientSize: IntSize(width: 400, height: 300)
            ))
        window.setPlatformWindowHost(recorder)

        guard let fakeWindow = window as? InMemoryPlatformWindow else {
            return XCTFail("Expected an in-memory alternate-platform window.")
        }

        fakeWindow.moveToDisplay(
            scaleFactor: 2,
            refreshRate: 144,
            clientSize: IntSize(width: 800, height: 600)
        )

        XCTAssertEqual(window.effectiveScaleFactor, 2)
        XCTAssertEqual(window.monitorRefreshRate, 144)
        XCTAssertEqual(window.clientSize, IntSize(width: 800, height: 600))
        XCTAssertEqual(
            window.clientRectToScreen(Rect(x: 10, y: 12, width: 30, height: 20)),
            Rect(x: 20, y: 24, width: 60, height: 40)
        )

        guard case .displayChanged(let scale, let rate) = recorder.events[0] else {
            return XCTFail("Expected a display event independent of the Win32 monitor API.")
        }
        XCTAssertEqual(scale, 2)
        XCTAssertEqual(rate, 144)

        fakeWindow.moveToDisplay(
            scaleFactor: 0.75,
            refreshRate: 60,
            clientSize: IntSize(width: 400, height: 300)
        )
        XCTAssertEqual(window.effectiveScaleFactor, 1, "All hosts must clamp invalid sub-point display scales.")
    }

    func testWin32FactoryPreservesNeutralWindowConfigurationWithoutCreatingAWindow() async throws {
        let configuration = PlatformWindowConfiguration(
            title: "Configured native window",
            clientSize: IntSize(width: 840, height: 620),
            titleBarVisibility: .hidden,
            minimumClientSize: IntSize(width: 400, height: 300),
            maximumClientSize: IntSize(width: 1200, height: 900),
            normalizedPosition: Point(x: 0.25, y: 0.75),
            isResizable: false,
            isAlwaysOnTop: true
        )
        let factory = Win32PlatformHostFactory()
        let window = try factory.makeWindow(configuration: configuration)

        guard let win32Window = window as? Win32Window else {
            return XCTFail("The Win32 platform factory must provide its native adapter.")
        }

        XCTAssertEqual(factory.platformName, "Windows / Win32")
        XCTAssertEqual(win32Window.title, configuration.title)
        XCTAssertEqual(win32Window.requestedLogicalClientSize, configuration.clientSize)
        XCTAssertEqual(win32Window.titleBarVisibility, .hidden)
        XCTAssertEqual(win32Window.configuration.minimumClientSize, configuration.minimumClientSize)
        XCTAssertEqual(win32Window.configuration.maximumClientSize, configuration.maximumClientSize)
        XCTAssertEqual(win32Window.configuration.normalizedPosition, configuration.normalizedPosition)
        XCTAssertEqual(win32Window.configuration.resizability, .fixedSize)
        XCTAssertTrue(win32Window.configuration.isAlwaysOnTop)
        XCTAssertNil(win32Window.nativeHandle, "Constructing a platform window must not create an OS window.")
    }

    func testWin32FactoryRejectsAWindowOwnedByAnotherPlatform() async throws {
        let alternateFactory = InMemoryPlatformHostFactory()
        let alternateWindow = try alternateFactory.makeWindow(
            configuration: PlatformWindowConfiguration(
                title: "Foreign window",
                clientSize: IntSize(width: 100, height: 100)
            ))

        XCTAssertThrowsError(try Win32PlatformHostFactory().start(window: alternateWindow)) { error in
            XCTAssertEqual(
                error as? PlatformHostError,
                .incompatibleWindow(expectedPlatform: "Windows / Win32")
            )
        }
    }

    func testWin32AdapterForwardsNeutralEventsAndPreservesExistingDelegate() async {
        let window = Win32Window(title: "Compatibility", clientSize: IntSize(width: 400, height: 300))
        let legacy = LegacyDelegateRecorder()
        let neutral = EventRecorder()
        window.delegate = legacy
        window.setPlatformWindowHost(neutral)

        window.delegate?.windowDidCreate(window)
        window.delegate?.window(window, pointerMovedTo: Point(x: 7, y: 9))
        window.delegate?.window(window, keyDown: KeyboardEvent(keyCode: 0x42, modifiers: .alt))
        window.delegate?.windowWillClose(window)

        XCTAssertEqual(legacy.createdCount, 1)
        XCTAssertEqual(legacy.pointerPositions, [Point(x: 7, y: 9)])
        XCTAssertEqual(legacy.keyboardEvents.count, 1)
        XCTAssertEqual(legacy.closeCount, 1)
        XCTAssertEqual(neutral.events.count, 4)

        guard case .pointerMoved(let point) = neutral.events[1],
            case .keyDown(let key) = neutral.events[2],
            case .willClose = neutral.events[3]
        else {
            return XCTFail("The adapter must preserve pointer, keyboard, and close events.")
        }
        XCTAssertEqual(point, Point(x: 7, y: 9))
        XCTAssertEqual(key.keyCode, 0x42)
        XCTAssertTrue(key.modifiers.contains(.alt))

        window.setPlatformWindowHost(nil)
        XCTAssertTrue(window.delegate === legacy, "Removing the neutral host must restore the original delegate.")
        window.delegate?.windowDidCreate(window)
        XCTAssertEqual(legacy.createdCount, 2)
        XCTAssertEqual(neutral.events.count, 4)
    }

    func testWin32AdapterPreservesWheelProvenanceTouchImeAndUnicode() async {
        let window = Win32Window(title: "Native input bridge", clientSize: IntSize(width: 320, height: 240))
        let recorder = EventRecorder()
        window.setPlatformWindowHost(recorder)
        let point = Point(x: 14, y: 28)

        window.delegate?.window(window, mouseWheelAt: point, delta: 0.25, source: .precise)
        window.delegate?.window(window, horizontalScrollAt: point, delta: -2)
        window.delegate?.window(window, didInputText: "🚀")
        window.delegate?.window(window, imeComposition: IMECompositionEvent(phase: .updated("日本")))
        window.delegate?.window(window, touchBegan: [point])
        window.delegate?.window(
            window,
            didReceiveFileDrop: FileDropPayload(
                fileURLs: [URL(fileURLWithPath: "C:\\Documents\\report.pdf")],
                clientPoint: point
            )
        )

        XCTAssertEqual(recorder.events.count, 6)

        guard case .scroll(_, let verticalDelta, .vertical, .precise) = recorder.events[0],
            case .scroll(_, let horizontalDelta, .horizontal, .wheelNotch) = recorder.events[1],
            case .textInput(let text) = recorder.events[2],
            case .imeComposition(let composition) = recorder.events[3],
            case .touch(.began, let touches) = recorder.events[4],
            case .filesDropped(let paths, let dropPoint) = recorder.events[5]
        else {
            return XCTFail("Every native callback must preserve its neutral input payload.")
        }

        XCTAssertEqual(verticalDelta, 0.25)
        XCTAssertEqual(horizontalDelta, -2)
        XCTAssertEqual(text, "🚀")
        XCTAssertEqual(composition.phase, .updated("日本"))
        XCTAssertEqual(touches, [point])
        XCTAssertEqual(paths, [URL(fileURLWithPath: "C:\\Documents\\report.pdf").path])
        XCTAssertEqual(dropPoint, point)
    }

    func testWin32AdapterReportsDpiChangesAndUsesNeutralCaretProvider() async {
        let window = Win32Window(title: "Display bridge", clientSize: IntSize(width: 400, height: 300))
        let recorder = EventRecorder()
        recorder.caretRect = Rect(x: 8, y: 11, width: 2, height: 18)
        window.setPlatformWindowHost(recorder)

        window.testScaleFactorOverride = 2
        window.testMonitorRefreshRateOverride = 120
        window.delegate?.window(window, didResizeTo: IntSize(width: 800, height: 600))

        XCTAssertEqual(recorder.events.count, 2)
        guard case .resized(let size) = recorder.events[0],
            case .displayChanged(let scale, let refreshRate) = recorder.events[1]
        else {
            return XCTFail("DPI-changing resizes must emit both a resize and neutral display update.")
        }
        XCTAssertEqual(size, IntSize(width: 800, height: 600))
        XCTAssertEqual(scale, 2)
        XCTAssertEqual(refreshRate, 120)
        XCTAssertEqual(window.delegate?.windowTextInputCaretRect(window), recorder.caretRect)
    }

    func testReplacingNeutralHostDoesNotStackAdaptersOrRetainPreviousHost() async {
        let window = Win32Window(title: "Host replacement", clientSize: IntSize(width: 200, height: 100))
        let original = EventRecorder()
        let replacement = EventRecorder()

        window.setPlatformWindowHost(original)
        window.delegate?.windowDidCreate(window)
        window.setPlatformWindowHost(replacement)
        window.delegate?.windowDidCreate(window)

        XCTAssertEqual(original.events.count, 1)
        XCTAssertEqual(replacement.events.count, 1)

        window.setPlatformWindowHost(nil)
        XCTAssertNil(window.delegate)
    }

    func testPortableClockIsMonotonicAndSharesTheWin32ClockOrigin() async {
        let samples = (0..<2048).map { _ in PlatformClock.now() }
        XCTAssertGreaterThan(samples[0], 0)

        for index in 1..<samples.count {
            XCTAssertGreaterThanOrEqual(samples[index], samples[index - 1])
        }

        XCTAssertGreaterThan(
            Set(samples.map { ($0 * 1_000_000).rounded() }).count,
            1,
            "Animation pacing requires resolution finer than a Windows system timer tick."
        )

        let before = PlatformClock.now()
        let win32Now = Win32Window.currentTimestampSeconds()
        let after = PlatformClock.now()
        XCTAssertGreaterThanOrEqual(win32Now, before)
        XCTAssertLessThanOrEqual(win32Now, after)
    }

    func testRetainedRuntimeKeepsAnInjectableNeutralAnimationClock() async {
        let root = ViewNode()
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 1234.5 }

        XCTAssertEqual(runtime.clock(), 1234.5)
        XCTAssertEqual(root.animationClockNow, 1234.5)

        let detached = ViewNode()
        let before = PlatformClock.now()
        let detachedTimestamp = detached.animationClockNow
        let after = PlatformClock.now()
        XCTAssertGreaterThanOrEqual(detachedTimestamp, before)
        XCTAssertLessThanOrEqual(detachedTimestamp, after)
    }
}
