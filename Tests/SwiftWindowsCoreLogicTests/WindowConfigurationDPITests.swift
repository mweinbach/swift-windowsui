import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

@testable import WinSwiftUI

// WS-11: window creation, window configuration and the caches behind them.
//
// `CreateWindowExW` was handed `configuration.size` — logical points — as its
// *outer window rect in physical pixels*, so every app opened at a fraction of
// its intended area on a HiDPI display (≈26 % at 200 %, small enough to flip
// the app into the compact size class before it painted). The min/max/ideal
// size, default position, resizability and window level the scene modifiers
// parse never reached the HWND at all. Two host caches were equally literal:
// `WM_MOVE` re-enumerated the display mode at mouse-report rate, and every
// `WM_SETTINGCHANGE` broadcast — any process writing any system parameter —
// forced a full tree rebuild.

@MainActor
final class WindowConfigurationDPITests: XCTestCase {

    // MARK: - DPI-correct creation geometry

    func testCreationGeometryScalesTheRequestedClientSizeByMonitorDPI() async {
        let style = DWORD(UInt32(bitPattern: Int32(WS_OVERLAPPEDWINDOW)))
        let requested = IntSize(width: 1280, height: 720)

        let atStandardDPI = Win32Window.windowGeometry(forLogicalClientSize: requested, style: style, dpi: 96)
        let atDoubleDPI = Win32Window.windowGeometry(forLogicalClientSize: requested, style: style, dpi: 192)

        XCTAssertGreaterThan(
            atDoubleDPI.windowWidth,
            atStandardDPI.windowWidth,
            "A 200 % display needs twice the physical pixels for the same logical width."
        )

        // The frame inset is a property of the style and DPI, not of the
        // client size, so doubling the client size must add exactly the
        // physical client width — this is the property that was violated.
        let doubled = IntSize(width: requested.width * 2, height: requested.height * 2)
        for dpi in [UINT(96), UINT(144), UINT(192)] {
            let single = Win32Window.windowGeometry(forLogicalClientSize: requested, style: style, dpi: dpi)
            let double = Win32Window.windowGeometry(forLogicalClientSize: doubled, style: style, dpi: dpi)
            let expected = Win32Window.physicalClientSize(forLogicalClientSize: requested, dpi: dpi)
            XCTAssertEqual(
                double.windowWidth - single.windowWidth,
                expected.width,
                "At \(dpi) DPI the window rect must carry \(expected.width) physical pixels of client width."
            )
            XCTAssertEqual(double.windowHeight - single.windowHeight, expected.height)
        }
    }

    func testPhysicalClientSizeIsLinearInDPI() async {
        let requested = IntSize(width: 640, height: 480)
        let atStandard = Win32Window.physicalClientSize(forLogicalClientSize: requested, dpi: 96)
        let atDouble = Win32Window.physicalClientSize(forLogicalClientSize: requested, dpi: 192)

        XCTAssertEqual(atStandard, requested)
        XCTAssertEqual(atDouble, IntSize(width: 1280, height: 960))
    }

    /// The end-to-end promise: at 200 % the client area the OS reports is
    /// twice the requested logical size, and the host's logical root is the
    /// size the app asked for.
    func testLogicalRootMatchesRequestedSizeAtDoubleScale() async {
        let requested = IntSize(width: 1280, height: 720)
        let physical = Win32Window.physicalClientSize(forLogicalClientSize: requested, dpi: 192)
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: physical,
            scaleFactor: 2.0
        )
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Test",
                size: requested,
                clearColor: .black,
                content: []
            ),
            renderer: FakeRenderBackend(),
            batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface },
            startupProbeConfiguration: nil
        )

        host.windowDidCreate(Win32Window(title: "Test", clientSize: requested))

        XCTAssertEqual(host.currentLogicalRootSize, requested)
        XCTAssertEqual(host.currentDisplayScale, 2.0, accuracy: 0.0001)
    }

    // MARK: - One effective scale

    func testEffectiveScaleClampsSubUnitScalesForEveryConsumer() async {
        XCTAssertEqual(Win32Window.effectiveScaleFactor(for: 0.75), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Win32Window.effectiveScaleFactor(for: 0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Win32Window.effectiveScaleFactor(for: .nan), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Win32Window.effectiveScaleFactor(for: 1.5), 1.5, accuracy: 0.0001)

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 800, height: 600))
        window.testScaleFactorOverride = 0.75
        XCTAssertEqual(window.effectiveScaleFactor, 1.0, accuracy: 0.0001)
    }

    /// The coherence invariant: a click at the bottom-right physical pixel
    /// must land inside the logical root. Clamping the root size but not the
    /// point conversion put every hit test in a 0.75 session a third away
    /// from the element the user clicked.
    func testHitTestingRoundTripsAgainstTheLogicalRootAtSubUnitScale() async {
        let pixelSize = IntSize(width: 800, height: 600)
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: 0.75
        )
        let recorder = RoutedInputEventRecorder()
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Test",
                size: pixelSize,
                clearColor: .black,
                content: []
            ),
            renderer: FakeRenderBackend(),
            batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface },
            startupProbeConfiguration: nil
        )
        host.onInputEventRouted = { [recorder] event in recorder.record(event) }

        let window = Win32Window(title: "Test", clientSize: pixelSize)
        window.testScaleFactorOverride = 0.75
        host.windowDidCreate(window)

        let root = host.currentLogicalRootSize
        host.window(window, pointerMovedTo: Point(x: Double(pixelSize.width) - 1, y: Double(pixelSize.height) - 1))

        guard case .pointerMoved(let point, _)? = recorder.events.last else {
            XCTFail("The pointer event must reach the runtime.")
            return
        }
        XCTAssertLessThan(point.x, Double(root.width), "A click inside the window must be inside the logical root.")
        XCTAssertLessThan(point.y, Double(root.height))
        XCTAssertGreaterThan(point.x, Double(root.width) - 2, "…and at the far edge, not a third of the way in.")
    }

    // MARK: - Configuration reaches the HWND

    func testTrackSizeLimitsCarryTheConfiguredMinimumAndMaximum() async {
        let window = Win32Window(
            title: "Test",
            clientSize: IntSize(width: 800, height: 600),
            configuration: Win32WindowConfiguration(
                minimumClientSize: IntSize(width: 400, height: 300),
                maximumClientSize: IntSize(width: 1600, height: 1200)
            )
        )

        let limits = window.trackSizeLimits(dpi: 96)
        let style = DWORD(UInt32(bitPattern: Int32(WS_OVERLAPPEDWINDOW)))
        let expectedMinimum = Win32Window.windowGeometry(
            forLogicalClientSize: IntSize(width: 400, height: 300), style: style, dpi: 96)

        XCTAssertEqual(limits.minimum?.width, expectedMinimum.windowWidth)
        XCTAssertEqual(limits.minimum?.height, expectedMinimum.windowHeight)
        XCTAssertNotNil(limits.maximum)
        XCTAssertGreaterThan(limits.maximum?.width ?? 0, limits.minimum?.width ?? 0)

        // The limits are physical, so a 200 % display must report bigger ones.
        let atDoubleDPI = window.trackSizeLimits(dpi: 192)
        XCTAssertGreaterThan(atDoubleDPI.minimum?.width ?? 0, limits.minimum?.width ?? 0)
    }

    func testFixedSizeResizabilityPinsBothTrackSizesToTheRequestedSize() async {
        let window = Win32Window(
            title: "Test",
            clientSize: IntSize(width: 800, height: 600),
            configuration: Win32WindowConfiguration(resizability: .fixedSize)
        )

        let limits = window.trackSizeLimits(dpi: 96)
        XCTAssertNotNil(limits.minimum)
        XCTAssertEqual(limits.minimum, limits.maximum, ".windowResizability(.contentSize) is one size, not a range.")
    }

    func testResizableWindowsDeclareNoTrackSizeLimitsUnlessAsked() async {
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 800, height: 600))
        let limits = window.trackSizeLimits(dpi: 96)
        XCTAssertNil(limits.minimum)
        XCTAssertNil(limits.maximum)
    }

    func testDefaultPositionPlacesTheWindowInsideTheWorkArea() async {
        let workArea = RECT(left: 100, top: 50, right: 1_920, bottom: 1_130)
        let windowSize = IntSize(width: 800, height: 600)

        let centered = Win32Window.windowOrigin(
            normalizedPosition: Point(x: 0.5, y: 0.5), windowSize: windowSize, workArea: workArea)
        XCTAssertEqual(centered.x, 100 + (1_820 - 800) / 2)
        XCTAssertEqual(centered.y, 50 + (1_080 - 600) / 2)

        let topLeading = Win32Window.windowOrigin(
            normalizedPosition: Point(x: 0, y: 0), windowSize: windowSize, workArea: workArea)
        XCTAssertEqual(topLeading.x, 100)
        XCTAssertEqual(topLeading.y, 50)

        // Out-of-range and non-finite placements clamp instead of throwing the
        // window off the desktop.
        let clamped = Win32Window.windowOrigin(
            normalizedPosition: Point(x: 4, y: -3), windowSize: windowSize, workArea: workArea)
        XCTAssertEqual(clamped.x, 100 + 1_020)
        XCTAssertEqual(clamped.y, 50)

        let oversized = Win32Window.windowOrigin(
            normalizedPosition: Point(x: 1, y: 1),
            windowSize: IntSize(width: 4_000, height: 4_000),
            workArea: workArea
        )
        XCTAssertEqual(oversized.x, 100, "A window larger than the work area pins to its origin.")
        XCTAssertEqual(oversized.y, 50)
    }

    // MARK: - Scene configuration translation

    func testSceneModifiersTranslateIntoPlatformWindowConfiguration() async {
        var configuration = WindowGroupConfiguration(
            title: "Test",
            size: IntSize(width: 1280, height: 720),
            clearColor: .black,
            content: []
        )
        configuration.minSize = IntSize(width: 400, height: 300)
        configuration.maxSize = IntSize(width: 1600, height: 1200)
        configuration.idealSize = IntSize(width: 1024, height: 768)
        configuration.resizability = .contentSize
        configuration.windowLevel = .floating
        configuration.defaultPosition = WindowPlacement(UnitPoint(x: 0.25, y: 0.75))

        let platform = WinSwiftUIWindowHost.platformConfiguration(for: configuration)
        XCTAssertEqual(platform.minimumClientSize, IntSize(width: 400, height: 300))
        XCTAssertEqual(platform.maximumClientSize, IntSize(width: 1600, height: 1200))
        XCTAssertEqual(platform.resizability, .fixedSize)
        XCTAssertTrue(platform.isAlwaysOnTop)
        XCTAssertEqual(platform.normalizedPosition?.x ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(platform.normalizedPosition?.y ?? -1, 0.75, accuracy: 0.0001)

        XCTAssertEqual(
            WinSwiftUIWindowHost.initialClientSize(for: configuration),
            IntSize(width: 1024, height: 768),
            "`.windowIdealSize` is the size the window opens at."
        )

        configuration.idealSize = IntSize(width: 100, height: 100)
        XCTAssertEqual(
            WinSwiftUIWindowHost.initialClientSize(for: configuration),
            IntSize(width: 400, height: 300),
            "An ideal size below the declared minimum still opens at the minimum."
        )
    }

    func testNormalWindowLevelIsNotAlwaysOnTop() async {
        var configuration = WindowGroupConfiguration(
            title: "Test", size: IntSize(width: 320, height: 200), clearColor: .black, content: [])
        configuration.windowLevel = .normal
        XCTAssertFalse(WinSwiftUIWindowHost.platformConfiguration(for: configuration).isAlwaysOnTop)
        XCTAssertEqual(WinSwiftUIWindowHost.platformConfiguration(for: configuration).resizability, .resizable)
    }

    func testUnsupportedSceneModifiersAreReportedRatherThanDroppedSilently() async {
        var configuration = WindowGroupConfiguration(
            title: "Test", size: IntSize(width: 320, height: 200), clearColor: .black, content: [])
        let host = WinSwiftUIWindowHost(
            configuration: configuration,
            renderer: FakeRenderBackend(),
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in nil },
            startupProbeConfiguration: nil
        )
        XCTAssertTrue(host.unsupportedWindowConfigurationModifiers.isEmpty)

        configuration.toolbarStyle = .automatic
        configuration.subtitle = "Sub"
        let reporting = WinSwiftUIWindowHost(
            configuration: configuration,
            renderer: FakeRenderBackend(),
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in nil },
            startupProbeConfiguration: nil
        )
        XCTAssertEqual(
            Set(reporting.unsupportedWindowConfigurationModifiers),
            ["windowToolbarStyle", "navigationSubtitle"]
        )
    }

    // MARK: - Display and appearance caches

    func testDraggingOnOneMonitorDoesNotReQueryTheDisplayMode() async {
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 800, height: 600))
        let clock = FakeRecoveryClock(1_000)
        window.refreshRateQueryClock = { clock.now }
        window.testMonitorIdentityOverride = 1
        window.testMonitorRefreshRateOverride = 120

        _ = window.monitorRefreshRate
        let queriesAfterFirstRead = window.refreshRateQueryCount

        for _ in 0..<100 {
            window.noteWindowMayHaveChangedMonitor()
            _ = window.monitorRefreshRate
        }

        XCTAssertEqual(
            window.refreshRateQueryCount,
            queriesAfterFirstRead,
            "A drag delivers WM_MOVE at mouse-report rate; none of them changed monitor."
        )
        XCTAssertEqual(window.monitorRefreshRate, 120)
    }

    func testRepeatedMonitorChangesAreRateLimitedWithoutLosingTheInvalidation() async {
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 800, height: 600))
        let clock = FakeRecoveryClock(1_000)
        window.refreshRateQueryClock = { clock.now }
        window.testMonitorRefreshRateOverride = 60
        window.testMonitorIdentityOverride = 1
        _ = window.monitorRefreshRate
        let baseline = window.refreshRateQueryCount

        // A drag across a monitor boundary can alternate identities as fast as
        // WM_MOVE arrives; the rate limiter is the second belt behind the
        // identity check.
        for index in 0..<100 {
            window.testMonitorIdentityOverride = UInt(index % 2) + 1
            window.noteWindowMayHaveChangedMonitor()
            _ = window.monitorRefreshRate
        }
        XCTAssertEqual(window.refreshRateQueryCount, baseline, "At most one display-mode query per 250 ms.")

        // The invalidation is deferred, not dropped.
        clock.now += 1
        _ = window.monitorRefreshRate
        XCTAssertEqual(window.refreshRateQueryCount, baseline + 1)
    }

    func testDisplayModeChangeBypassesTheRateLimit() async {
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 800, height: 600))
        let clock = FakeRecoveryClock(1_000)
        window.refreshRateQueryClock = { clock.now }
        window.testMonitorRefreshRateOverride = 60
        XCTAssertEqual(window.monitorRefreshRate, 60)

        // WM_DISPLAYCHANGE is rare and real: the new mode must apply at once,
        // not up to 250 ms later.
        window.testMonitorRefreshRateOverride = 144
        XCTAssertEqual(window.monitorRefreshRate, 144)
    }

    func testUnchangedSystemAppearanceDoesNotTriggerAReload() async {
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        let provider = FakeSystemAppearanceProvider()
        window.systemAppearanceProvider = provider
        _ = window.systemAppearance

        XCTAssertFalse(
            window.refreshSystemAppearanceIfChanged(),
            "A WM_SETTINGCHANGE broadcast for something the app does not read must not rebuild the tree."
        )
        XCTAssertFalse(window.refreshSystemAppearanceIfChanged())

        provider.snapshot = SystemAppearanceSnapshot(colorSchemePreference: .dark)
        XCTAssertTrue(window.refreshSystemAppearanceIfChanged(), "A real theme change must still reload.")
        XCTAssertFalse(window.refreshSystemAppearanceIfChanged())
    }
}
