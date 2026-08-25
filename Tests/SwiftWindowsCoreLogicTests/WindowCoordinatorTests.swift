import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsRendererD3D11

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

// Multi-window lifecycle tests (Phase 5). Drives WinSwiftUIWindowCoordinator
// headlessly: the window-factory seam substitutes fake render backends and
// simulates WM_CLOSE/WM_DESTROY delivery by calling windowWillClose directly,
// so no real HWNDs are created.

@testable import WinSwiftUI

@MainActor
private final class CoordinatorHookLog {
    var startedHosts: [WinSwiftUIWindowHost] = []
    var terminateCallCount = 0
    var runMessageLoopCallCount = 0
}

/// Records the real application/coordinator platform-factory composition
/// without ever creating an HWND or entering a native message loop.
@MainActor
private final class CoordinatorPlatformFactoryLog: PlatformHostFactory {
    let platformName = "Recording application platform"
    var returnsIncompatibleWindow = false
    private(set) var configurations: [PlatformWindowConfiguration] = []
    private(set) var startedWindows: [any PlatformWindow] = []
    private(set) var runEventLoopCount = 0
    private(set) var terminateEventLoopCount = 0

    func makeWindow(configuration: PlatformWindowConfiguration) throws -> any PlatformWindow {
        configurations.append(configuration)
        if returnsIncompatibleWindow {
            return IncompatiblePlatformWindow(configuration: configuration)
        }
        return try Win32PlatformHostFactory().makeWindow(configuration: configuration)
    }

    func start(window: any PlatformWindow) throws {
        startedWindows.append(window)
    }

    func runEventLoop() throws -> Int32 {
        runEventLoopCount += 1
        return 23
    }

    func terminateEventLoop() {
        terminateEventLoopCount += 1
    }

    private final class IncompatiblePlatformWindow: PlatformWindow {
        let title: String
        let clientSize: IntSize
        let scaleFactor: Double = 1
        let effectiveScaleFactor: Double = 1
        let monitorRefreshRate: UInt32 = 60
        let isMinimized = false

        init(configuration: PlatformWindowConfiguration) {
            title = configuration.title
            clientSize = configuration.clientSize
        }

        var nativeHandle: NativeWindowHandle? { nil }

        func create() throws {}
        func show() {}
        func invalidate() {}
        func requestClose() {}
        func currentClientSize() -> IntSize { clientSize }
        func setAnimationTimerEnabled(_ enabled: Bool, intervalMilliseconds: UInt32) {}
        func clientRectToScreen(_ rect: Rect) -> Rect { rect }
        func setPlatformWindowHost(_ host: (any PlatformWindowHost)?) {}
    }
}

@MainActor
private struct SceneStorageProbe {
    @SceneStorage("coordinator-probe-key") var text: String = "default"
}

private func makeCoordinatorTestSurface() -> SurfaceDescriptor {
    SurfaceDescriptor(
        windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
        pixelSize: IntSize(width: 640, height: 480),
        scaleFactor: 1.0
    )
}

@MainActor
final class WindowCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        configurations: [WindowGroupConfiguration],
        log: CoordinatorHookLog,
        sceneStorageScopeProvider: (@MainActor () -> String)? = nil
    ) -> WinSwiftUIWindowCoordinator {
        let hooks = WindowCoordinatorHooks(
            startWindow: { host in
                log.startedHosts.append(host)
                host.windowDidCreate(host.platformWindow)
            },
            requestCloseWindow: { host in
                // Simulate WM_CLOSE → WM_DESTROY delivery headlessly.
                host.windowWillClose(host.platformWindow)
            },
            runMessageLoop: {
                log.runMessageLoopCallCount += 1
                return 0
            },
            terminateMessageLoop: {
                log.terminateCallCount += 1
            }
        )
        return WinSwiftUIWindowCoordinator(
            sceneConfigurations: configurations,
            hooks: hooks,
            hostFactory: { configuration, _ in
                WinSwiftUIWindowHost(
                    configuration: configuration,
                    renderer: FakeRenderBackend(),
                    batchRenderer: nil,
                    surfaceDescriptorProvider: { _ in makeCoordinatorTestSurface() },
                    startupProbeConfiguration: nil
                )
            },
            sceneStorageScopeProvider: sceneStorageScopeProvider
        )
    }

    private func makeConfiguration(
        title: String = "Test",
        windowID: String? = nil,
        envRecorder: HostEnvironmentRecorder? = nil,
        forType: Any.Type? = nil,
        dataBoundContent: ((AnyHashable) -> [AnyView])? = nil
    ) -> WindowGroupConfiguration {
        WindowGroupConfiguration(
            title: title,
            size: IntSize(width: 640, height: 480),
            clearColor: .black,
            content: envRecorder.map { [AnyView(HostEnvironmentProbeView(recorder: $0))] } ?? [],
            windowID: windowID,
            forType: forType,
            dataBoundContent: dataBoundContent
        )
    }

    private func makeBuildContext(scope: String) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { Size(width: 100, height: 100) },
            invalidateHandler: {},
            environmentValuesProvider: { EnvironmentValues(sceneStorageScope: scope) }
        )
    }

    func testPrimaryBootMatchesSingleWindowModel() async {
        await MainActor.run {
            let log = CoordinatorHookLog()
            let envRecorder = HostEnvironmentRecorder()
            let coordinator = makeCoordinator(
                configurations: [makeConfiguration(windowID: "main", envRecorder: envRecorder)],
                log: log
            )

            let exitCode = try? coordinator.run()

            XCTAssertEqual(exitCode, 0)
            XCTAssertEqual(log.runMessageLoopCallCount, 1)
            XCTAssertEqual(log.startedHosts.count, 1)
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertEqual(log.terminateCallCount, 0)

            // Coordinator-managed windows report multi-window support.
            XCTAssertEqual(envRecorder.snapshots.last?.supportsMultipleWindows, true)

            // The production path, unlike explicit legacy test hooks, now
            // delegates window creation, startup, and its process event loop
            // to the application's independently selected platform factory.
            let platformFactory = CoordinatorPlatformFactoryLog()
            var configuration = makeConfiguration(title: "Factory managed", windowID: "factory")
            configuration.idealSize = IntSize(width: 840, height: 620)
            configuration.minSize = IntSize(width: 400, height: 300)
            configuration.maxSize = IntSize(width: 1200, height: 900)
            configuration.defaultPosition = .coordinates(0.25, 0.75)
            configuration.resizability = .contentSize
            configuration.windowLevel = .floating
            configuration.titleBarVisibility = .hidden

            let platformCoordinator = WinSwiftUIWindowCoordinator(
                sceneConfigurations: [configuration],
                platformHostFactory: platformFactory
            )

            XCTAssertEqual(try? platformCoordinator.run(), 23)
            XCTAssertEqual(platformFactory.configurations.count, 1)
            XCTAssertEqual(platformFactory.startedWindows.count, 1)
            XCTAssertEqual(platformFactory.runEventLoopCount, 1)

            guard let created = platformFactory.configurations.first,
                let managedHost = platformCoordinator.windows.first?.host
            else {
                return XCTFail("The platform factory must create and start the managed application window.")
            }

            XCTAssertEqual(created.title, "Factory managed")
            XCTAssertEqual(created.clientSize, IntSize(width: 840, height: 620))
            XCTAssertEqual(created.minimumClientSize, configuration.minSize)
            XCTAssertEqual(created.maximumClientSize, configuration.maxSize)
            XCTAssertEqual(created.normalizedPosition, Point(x: 0.25, y: 0.75))
            XCTAssertFalse(created.isResizable)
            XCTAssertTrue(created.isAlwaysOnTop)
            XCTAssertEqual(created.titleBarVisibility, .hidden)
            XCTAssertTrue(platformFactory.startedWindows.first === managedHost.platformWindow)
            XCTAssertFalse(managedHost.platformWindow.postsQuitMessageOnDestroy)

            managedHost.windowWillClose(managedHost.platformWindow)
            XCTAssertEqual(platformFactory.terminateEventLoopCount, 1)
        }
    }

    func testHostWithoutCoordinatorKeepsSingleWindowDefaults() async {
        await MainActor.run {
            let envRecorder = HostEnvironmentRecorder()
            let host = WinSwiftUIWindowHost(
                configuration: makeConfiguration(envRecorder: envRecorder),
                renderer: FakeRenderBackend(),
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in makeCoordinatorTestSurface() },
                startupProbeConfiguration: nil
            )
            host.windowDidCreate(host.platformWindow)

            // Historical defaults: no multi-window support, shared
            // scene-storage scope, no-op window actions.
            let env = envRecorder.snapshots.last
            XCTAssertEqual(env?.supportsMultipleWindows, false)
            XCTAssertEqual(env?.sceneStorageScope, "shared")
        }
    }

    func testOpenWindowByIDOpensSecondWindowWithIndependentState() async {
        await MainActor.run {
            let log = CoordinatorHookLog()
            let envRecorder = HostEnvironmentRecorder()
            let coordinator = makeCoordinator(
                configurations: [makeConfiguration(windowID: "doc", envRecorder: envRecorder)],
                log: log
            )
            _ = try? coordinator.run()

            guard let primaryEnv = envRecorder.snapshots.last else {
                XCTFail("Primary window did not build its environment.")
                return
            }

            XCTAssertTrue(coordinator.openWindow(payload: WindowActionPayload(id: "doc")))
            XCTAssertEqual(coordinator.windowCount, 2)
            XCTAssertEqual(log.startedHosts.count, 2)

            let primaryHost = log.startedHosts[0]
            let secondaryHost = log.startedHosts[1]
            XCTAssertFalse(primaryHost === secondaryHost)
            XCTAssertFalse(primaryHost.platformWindow === secondaryHost.platformWindow)

            // The action routed through the injected environment matches the
            // direct coordinator call.
            primaryEnv.openWindow(id: "doc")
            XCTAssertEqual(coordinator.windowCount, 3)

            // Per-window retained state is independent: resizing one window
            // leaves the other window's runtime untouched.
            let primarySizeBefore = primaryHost.currentLogicalRootSize
            secondaryHost.window(secondaryHost.platformWindow, didResizeTo: IntSize(width: 800, height: 600))
            XCTAssertEqual(primaryHost.currentLogicalRootSize, primarySizeBefore)
            XCTAssertEqual(secondaryHost.currentLogicalRootSize, IntSize(width: 800, height: 600))
            XCTAssertEqual(log.terminateCallCount, 0)
        }
    }

    func testOpenWindowByValueBuildsDataBoundContentAndDedupesValue() async {
        await MainActor.run {
            let log = CoordinatorHookLog()
            let coordinator = makeCoordinator(
                configurations: [
                    makeConfiguration(
                        windowID: "editor",
                        forType: String.self,
                        dataBoundContent: { value in
                            [AnyView(Text(String(describing: value.base)))]
                        }
                    )
                ],
                log: log
            )
            _ = try? coordinator.run()

            XCTAssertTrue(coordinator.openWindow(payload: WindowActionPayload(value: AnyHashable("a"))))
            XCTAssertEqual(coordinator.windowCount, 2)

            // Re-presenting an already-open value does not duplicate.
            XCTAssertTrue(coordinator.openWindow(payload: WindowActionPayload(value: AnyHashable("a"))))
            XCTAssertEqual(coordinator.windowCount, 2)

            XCTAssertTrue(coordinator.openWindow(payload: WindowActionPayload(value: AnyHashable("b"))))
            XCTAssertEqual(coordinator.windowCount, 3)

            XCTAssertEqual(coordinator.windows[1].presentedValue, AnyHashable("a"))
            XCTAssertEqual(coordinator.windows[2].presentedValue, AnyHashable("b"))
            XCTAssertEqual(log.terminateCallCount, 0)
        }
    }

    func testOpenWindowWithUnknownIDOrMismatchedValueTypeIsNoop() async {
        await MainActor.run {
            let log = CoordinatorHookLog()
            let coordinator = makeCoordinator(
                configurations: [makeConfiguration(windowID: "doc")],
                log: log
            )
            _ = try? coordinator.run()

            XCTAssertFalse(coordinator.openWindow(payload: WindowActionPayload(id: "nope")))
            XCTAssertFalse(coordinator.openWindow(payload: WindowActionPayload(value: AnyHashable(42))))
            XCTAssertFalse(coordinator.openWindow(payload: WindowActionPayload()))
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertEqual(log.startedHosts.count, 1)

            // The app has a real factory composition seam, but its existing
            // retained host still owns Win32-specific appearance, accessibility,
            // and lifecycle behavior. Reject an alternate window explicitly.
            let incompatibleFactory = CoordinatorPlatformFactoryLog()
            incompatibleFactory.returnsIncompatibleWindow = true
            let incompatibleCoordinator = WinSwiftUIWindowCoordinator(
                sceneConfigurations: [makeConfiguration(windowID: "incompatible")],
                platformHostFactory: incompatibleFactory
            )

            do {
                _ = try incompatibleCoordinator.bootPrimaryWindow()
                XCTFail("A non-Win32 platform window must fail before the application host starts.")
            } catch {
                XCTAssertEqual(
                    error as? PlatformHostError,
                    .incompatibleWindow(expectedPlatform: "Windows / Win32")
                )
            }
            XCTAssertEqual(incompatibleFactory.configurations.count, 1)
            XCTAssertTrue(incompatibleFactory.startedWindows.isEmpty)
            XCTAssertEqual(incompatibleCoordinator.windowCount, 0)
        }
    }

    func testDismissWindowClosesCallingSceneOnly() async {
        await MainActor.run {
            let log = CoordinatorHookLog()
            let envRecorder = HostEnvironmentRecorder()
            let coordinator = makeCoordinator(
                configurations: [makeConfiguration(windowID: "doc", envRecorder: envRecorder)],
                log: log
            )
            _ = try? coordinator.run()
            coordinator.openWindow(payload: WindowActionPayload(id: "doc"))
            XCTAssertEqual(coordinator.windowCount, 2)

            // The last environment snapshot belongs to the second window;
            // its dismissWindow() must close its own scene only.
            guard let secondaryEnv = envRecorder.snapshots.last else {
                XCTFail("Secondary window did not build its environment.")
                return
            }
            secondaryEnv.dismissWindow()

            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertTrue(coordinator.windows[0].isPrimary)
            XCTAssertEqual(log.terminateCallCount, 0)
        }
    }

    func testDismissWindowByIDClosesAllMatchingWindows() async {
        await MainActor.run {
            let log = CoordinatorHookLog()
            let envRecorder = HostEnvironmentRecorder()
            let coordinator = makeCoordinator(
                configurations: [
                    makeConfiguration(windowID: "main", envRecorder: envRecorder),
                    makeConfiguration(windowID: "aux"),
                ],
                log: log
            )
            _ = try? coordinator.run()
            coordinator.openWindow(payload: WindowActionPayload(id: "aux"))
            coordinator.openWindow(payload: WindowActionPayload(id: "aux"))
            XCTAssertEqual(coordinator.windowCount, 3)

            guard let primaryEnv = envRecorder.snapshots.last else {
                XCTFail("Primary window did not build its environment.")
                return
            }
            primaryEnv.dismissWindow(id: "aux")

            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertTrue(coordinator.windows[0].isPrimary)
            XCTAssertEqual(log.terminateCallCount, 0)
        }
    }

    func testLastWindowClosedTerminatesMessageLoop() async {
        await MainActor.run {
            let log = CoordinatorHookLog()
            let coordinator = makeCoordinator(
                configurations: [makeConfiguration(windowID: "doc")],
                log: log
            )
            _ = try? coordinator.run()
            coordinator.openWindow(payload: WindowActionPayload(id: "doc"))

            let primaryHost = log.startedHosts[0]
            let secondaryHost = log.startedHosts[1]

            // Simulate OS destroy of the secondary window: only its own host
            // is torn down; the app keeps running.
            secondaryHost.windowWillClose(secondaryHost.platformWindow)
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertTrue(coordinator.windows[0].host === primaryHost)
            XCTAssertEqual(log.terminateCallCount, 0)

            // Last window closed: the coordinator quits the message loop,
            // matching single-window quit behavior.
            primaryHost.windowWillClose(primaryHost.platformWindow)
            XCTAssertEqual(coordinator.windowCount, 0)
            XCTAssertEqual(log.terminateCallCount, 1)
        }
    }

    func testClosingPrimaryFirstDoesNotTerminateUntilLastWindow() async {
        await MainActor.run {
            let log = CoordinatorHookLog()
            let coordinator = makeCoordinator(
                configurations: [makeConfiguration(windowID: "doc")],
                log: log
            )
            _ = try? coordinator.run()
            coordinator.openWindow(payload: WindowActionPayload(id: "doc"))

            let primaryHost = log.startedHosts[0]
            let secondaryHost = log.startedHosts[1]

            primaryHost.windowWillClose(primaryHost.platformWindow)
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertEqual(log.terminateCallCount, 0)

            secondaryHost.windowWillClose(secondaryHost.platformWindow)
            XCTAssertEqual(coordinator.windowCount, 0)
            XCTAssertEqual(log.terminateCallCount, 1)
        }
    }

    func testSceneStorageScopesAreUniquePerWindow() async {
        await MainActor.run {
            let log = CoordinatorHookLog()
            let envRecorder = HostEnvironmentRecorder()
            var scopeIndex = 0
            let coordinator = makeCoordinator(
                configurations: [makeConfiguration(windowID: "doc", envRecorder: envRecorder)],
                log: log,
                sceneStorageScopeProvider: {
                    scopeIndex += 1
                    return "scope-\(scopeIndex)"
                }
            )
            _ = try? coordinator.run()
            coordinator.openWindow(payload: WindowActionPayload(id: "doc"))

            // Each window also builds once eagerly at host init, before the
            // coordinator installs its environment; those snapshots carry the
            // shared default scope. The coordinator-assigned scopes are the
            // post-boot builds and must be unique per window.
            let coordinatorScopes = envRecorder.snapshots.map(\.sceneStorageScope).filter { $0 != "shared" }
            XCTAssertEqual(coordinatorScopes, ["scope-1", "scope-2"])
        }
    }

    func testSceneStorageValuesAreIsolatedPerWindowScope() async {
        await MainActor.run {
            let contextA = makeBuildContext(scope: "scope-a")
            let contextB = makeBuildContext(scope: "scope-b")

            var probeA = SceneStorageProbe()
            // First read under window A's build context binds the scope.
            _ = ViewBuildContextScope.withCurrent(contextA) { probeA.text }
            // Writes outside a build scope ride the captured scope.
            probeA.text = "A-value"

            var probeB = SceneStorageProbe()
            _ = ViewBuildContextScope.withCurrent(contextB) { probeB.text }
            // Window B does not observe window A's write.
            XCTAssertEqual(probeB.text, "default")

            // The shared default scope (uncoordinated hosts) is untouched.
            let sharedProbe = SceneStorageProbe()
            XCTAssertEqual(sharedProbe.text, "default")

            // Window A still reads its own value back.
            let rereadA = ViewBuildContextScope.withCurrent(contextA) { probeA.text }
            XCTAssertEqual(rereadA, "A-value")
        }
    }
}
