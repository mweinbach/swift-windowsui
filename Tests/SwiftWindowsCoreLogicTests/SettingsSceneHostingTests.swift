import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

// These app and custom-scene bodies intentionally omit @SceneBuilder. Ordinary
// SwiftUI-shaped declarations must infer it from the protocol requirement.
@MainActor
private struct SettingsHostingApp: App {
    var body: some Scene {
        WindowGroup("Main", id: "main") {
            Text("Main content")
        }
        WindowGroup("Inspector", id: "inspector") {
            Text("Inspector content")
        }
        Settings {
            Text("Preferences")
        }
    }
}

@MainActor
private struct AvailableSettingsHostingScenes: Scene {
    var body: some Scene {
        WindowGroup("Main", id: "main") {
            EmptyView()
        }
        if #available(macOS 13.0, *) {
            Settings {
                EmptyView()
            }
        }
        WindowGroup("Extra 0", id: "extra-0") {
            EmptyView()
        }
        WindowGroup("Extra 1", id: "extra-1") {
            EmptyView()
        }
    }
}

@MainActor
private struct NestedSettingsHostingScenes: Scene {
    var body: some Scene {
        AvailableSettingsHostingScenes()
    }
}

@MainActor
private struct SettingsHostingEnvironmentScenes: Scene {
    let primaryRecorder: HostEnvironmentRecorder
    let settingsRecorder: HostEnvironmentRecorder
    let valueRecorder: HostEnvironmentRecorder

    var body: some Scene {
        WindowGroup("Main", id: "main") {
            HostEnvironmentProbeView(recorder: primaryRecorder)
        }
        Settings {
            HostEnvironmentProbeView(recorder: settingsRecorder)
        }
        WindowGroup("Editor", id: "editor", for: String.self) { _ in
            HostEnvironmentProbeView(recorder: valueRecorder)
        }
    }
}

@MainActor
private final class SettingsHostingEnvironmentObject: ObservableObject {}

@MainActor
private struct SettingsHostingActionReader: View {
    @Environment(\.openSettings) var openSettings

    var body: some View {
        Button("Open preferences") {
            openSettings()
        }
    }
}

@MainActor
private struct SettingsHostingStorageProbe {
    @SceneStorage("settings-hosting-storage") var text = "default"
}

private enum SettingsHostingError: Error, Equatable {
    case startFailed
    case factoryFailed
}

@MainActor
private final class SettingsHostingHookLog {
    var createdHosts: [WinSwiftUIWindowHost] = []
    var renderers: [FakeRenderBackend] = []
    var startAttempts: [WinSwiftUIWindowHost] = []
    var startedHosts: [WinSwiftUIWindowHost] = []
    var closeRequests: [WinSwiftUIWindowHost] = []
    var activationRequests: [WinSwiftUIWindowHost] = []
    var startFailuresRemaining = 0
    var factoryFailuresRemaining = 0
    var activationSucceeds = true
    var runMessageLoopCount = 0
    var terminateMessageLoopCount = 0
}

@MainActor
final class SettingsSceneHostingTests: XCTestCase {
    private func makeCoordinator(
        configurations: [WindowGroupConfiguration],
        log: SettingsHostingHookLog,
        sceneStorageScopeProvider: (@MainActor () -> String)? = nil
    ) -> WinSwiftUIWindowCoordinator {
        let hooks = WindowCoordinatorHooks(
            startWindow: { host in
                log.startAttempts.append(host)
                host.windowDidCreate(host.platformWindow)
                if log.startFailuresRemaining > 0 {
                    log.startFailuresRemaining -= 1
                    throw SettingsHostingError.startFailed
                }
                log.startedHosts.append(host)
            },
            requestCloseWindow: { host in
                log.closeRequests.append(host)
                host.windowWillClose(host.platformWindow)
            },
            runMessageLoop: {
                log.runMessageLoopCount += 1
                return 0
            },
            terminateMessageLoop: {
                log.terminateMessageLoopCount += 1
            },
            activateWindow: { host in
                log.activationRequests.append(host)
                return log.activationSucceeds
            }
        )
        return WinSwiftUIWindowCoordinator(
            sceneConfigurations: configurations,
            hooks: hooks,
            hostFactory: { configuration, _ in
                if log.factoryFailuresRemaining > 0 {
                    log.factoryFailuresRemaining -= 1
                    throw SettingsHostingError.factoryFailed
                }
                let renderer = FakeRenderBackend()
                let host = WinSwiftUIWindowHost(
                    configuration: configuration,
                    renderer: renderer,
                    batchRenderer: nil,
                    surfaceDescriptorProvider: { _ in
                        SurfaceDescriptor(
                            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                            pixelSize: IntSize(width: 640, height: 480),
                            scaleFactor: 1
                        )
                    },
                    startupProbeConfiguration: nil
                )
                log.createdHosts.append(host)
                log.renderers.append(renderer)
                return host
            },
            sceneStorageScopeProvider: sceneStorageScopeProvider
        )
    }

    private func makePrimaryConfiguration(recorder: HostEnvironmentRecorder? = nil) -> WindowGroupConfiguration {
        WindowGroupConfiguration(
            title: "Main",
            size: IntSize(width: 640, height: 480),
            clearColor: .black,
            content: recorder.map { [AnyView(HostEnvironmentProbeView(recorder: $0))] } ?? [],
            windowID: "main"
        )
    }

    private func makeSettingsConfiguration(recorder: HostEnvironmentRecorder? = nil) -> WindowGroupConfiguration {
        WindowGroupConfiguration(
            title: "Settings",
            size: IntSize(width: 600, height: 400),
            clearColor: .black,
            content: recorder.map { [AnyView(HostEnvironmentProbeView(recorder: $0))] } ?? [],
            isSettingsWindow: true
        )
    }

    private func makeContext(environment: EnvironmentValues) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { Size(width: 640, height: 480) },
            invalidateHandler: {},
            environmentValuesProvider: { environment }
        )
    }

    func testAppBodyCollectsEveryWindowAndSettingsSceneInDeclarationOrder() async {
        await MainActor.run {
            let body = SettingsHostingApp().body
            let configurations = body.makeWindowConfigurations()

            XCTAssertEqual(configurations.map(\.title), ["Main", "Inspector", "Settings"])
            XCTAssertEqual(configurations.map(\.windowID), ["main", "inspector", nil])
            XCTAssertEqual(configurations.map(\.isSettingsWindow), [false, false, true])
            XCTAssertTrue(configurations.allSatisfy { $0.content.count == 1 })
            XCTAssertEqual(body.makeWindowConfiguration().title, "Main")
        }
    }

    func testCustomSceneBodiesPreserveStaticAndAvailabilityGatedScenes() async {
        await MainActor.run {
            let nested = NestedSettingsHostingScenes().makeWindowConfigurations()
            XCTAssertEqual(nested.map(\.title), ["Main", "Settings", "Extra 0", "Extra 1"])
            XCTAssertEqual(nested.map(\.windowID), ["main", nil, "extra-0", "extra-1"])

            let window = WindowGroup("Expression", id: "expression") { EmptyView() }
            let expression: WindowGroup = SceneBuilder.buildExpression(window)
            XCTAssertEqual(expression.makeWindowConfiguration().windowID, "expression")

            // SwiftUI accepts an optional scene only after availability
            // erasure; runtime conditionals and loops are not scene syntax.
            let settings = Settings { EmptyView() }
            let available = SceneBuilder.buildLimitedAvailability(settings)
            let included = SceneBuilder.buildOptional(available).makeWindowConfigurations()
            XCTAssertEqual(included.map(\.title), ["Settings"])
            XCTAssertEqual(included.map(\.isSettingsWindow), [true])
            XCTAssertTrue(SceneBuilder.buildOptional(nil).makeWindowConfigurations().isEmpty)
        }
    }

    func testSceneModifiersApplyToEveryNestedConfiguration() async {
        await MainActor.run {
            let scene = NestedSettingsHostingScenes()
                .defaultSize(IntSize(width: 720, height: 520))
                .windowMinSize(IntSize(width: 320, height: 240))
                .windowResizability(.contentSize)
                .windowTitleBar(.hidden)
                .handlesExternalEvents(matching: ["preferences"])
                .commands {
                    CommandMenu("Application") {
                        SettingsLink()
                    }
                }
            let configurations = scene.makeWindowConfigurations()

            XCTAssertEqual(configurations.count, 4)
            XCTAssertEqual(configurations.map(\.title), ["Main", "Settings", "Extra 0", "Extra 1"])
            for configuration in configurations {
                XCTAssertEqual(configuration.size, IntSize(width: 720, height: 520))
                XCTAssertEqual(configuration.minSize, IntSize(width: 320, height: 240))
                XCTAssertEqual(configuration.resizability, .contentSize)
                XCTAssertEqual(configuration.titleBarVisibility, .hidden)
                XCTAssertEqual(configuration.handlesExternalEvents, Set(["preferences"]))
                XCTAssertEqual(configuration.commands?.menus.map(\.name), ["Application"])
            }
            XCTAssertEqual(scene.makeWindowConfiguration().size, configurations[0].size)
        }
    }

    func testSceneEnvironmentModifiersReachSettingsAndDataBoundContent() async throws {
        try await MainActor.run {
            let primaryRecorder = HostEnvironmentRecorder()
            let settingsRecorder = HostEnvironmentRecorder()
            let valueRecorder = HostEnvironmentRecorder()
            let model = SettingsHostingEnvironmentObject()
            let scene = SettingsHostingEnvironmentScenes(
                primaryRecorder: primaryRecorder,
                settingsRecorder: settingsRecorder,
                valueRecorder: valueRecorder
            )
            .environment(\.isEnabled, false)
            .environmentObject(model)
            let log = SettingsHostingHookLog()
            let coordinator = makeCoordinator(configurations: scene.makeWindowConfigurations(), log: log)

            try coordinator.bootPrimaryWindow()
            XCTAssertTrue(coordinator.openSettings())
            XCTAssertTrue(coordinator.openWindow(payload: WindowActionPayload(id: "editor", value: AnyHashable("a"))))

            for recorder in [primaryRecorder, settingsRecorder, valueRecorder] {
                let environment = try XCTUnwrap(recorder.snapshots.last)
                XCTAssertFalse(environment.isEnabled)
                XCTAssertTrue(environment.environmentObjects.object(SettingsHostingEnvironmentObject.self) === model)
                XCTAssertTrue(environment.supportsMultipleWindows)
            }
        }
    }

    func testSingleSceneEnvironmentModifiersPreserveDeferredValueContent() async throws {
        try await MainActor.run {
            let recorder = HostEnvironmentRecorder()
            let model = SettingsHostingEnvironmentObject()
            let scene = WindowGroup("Editor", id: "editor", for: String.self) { _ in
                HostEnvironmentProbeView(recorder: recorder)
            }
            .environment(\.isEnabled, false)
            .environmentObject(model)
            let configuration = scene.makeWindowConfiguration()
            let views = try XCTUnwrap(configuration.dataBoundContent?(AnyHashable("a")))
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = makeContext(environment: EnvironmentValues())

            for view in views {
                _ = view.makeComponent(context: context).makeNode(runtime: runtime)
            }

            let environment = try XCTUnwrap(recorder.snapshots.last)
            XCTAssertFalse(environment.isEnabled)
            XCTAssertTrue(environment.environmentObjects.object(SettingsHostingEnvironmentObject.self) === model)
        }
    }

    func testPrimaryBootSkipsSettingsAndMenuBarExtras() async throws {
        try await MainActor.run {
            let menu = MenuBarExtra("Menu") { EmptyView() }.makeWindowConfiguration()
            let log = SettingsHostingHookLog()
            let coordinator = makeCoordinator(
                configurations: [makeSettingsConfiguration(), menu]
                    + SettingsHostingApp().body.makeWindowConfigurations(),
                log: log
            )

            XCTAssertEqual(try coordinator.run(), 0)

            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertEqual(coordinator.windows.first?.configuration.windowID, "main")
            XCTAssertEqual(coordinator.windows.first?.isPrimary, true)
            XCTAssertEqual(log.startedHosts.count, 1)
            XCTAssertEqual(log.runMessageLoopCount, 1)
            XCTAssertTrue(log.activationRequests.isEmpty)
            XCTAssertEqual(log.terminateMessageLoopCount, 0)
        }
    }

    func testBootRejectsEmptyOrNonlaunchableSceneCollections() async throws {
        try await MainActor.run {
            let settings = makeSettingsConfiguration()
            let menu = MenuBarExtra("Menu") { EmptyView() }.makeWindowConfiguration()
            let collections: [[WindowGroupConfiguration]] = [[], [settings], [menu], [settings, menu]]

            for configurations in collections {
                let log = SettingsHostingHookLog()
                let coordinator = makeCoordinator(configurations: configurations, log: log)

                XCTAssertThrowsError(try coordinator.run()) { error in
                    XCTAssertEqual(error as? WindowCoordinatorError, .noLaunchableWindowScene)
                }
                XCTAssertEqual(coordinator.windowCount, 0)
                XCTAssertTrue(log.createdHosts.isEmpty)
                XCTAssertEqual(log.runMessageLoopCount, 0)
                XCTAssertEqual(log.terminateMessageLoopCount, 0)
            }
        }
    }

    func testOpenSettingsReusesFirstSettingsSceneAndRequestsActivationEveryTime() async throws {
        try await MainActor.run {
            let log = SettingsHostingHookLog()
            var otherSettings = makeSettingsConfiguration()
            otherSettings.title = "Other settings"
            let coordinator = makeCoordinator(
                configurations: [makePrimaryConfiguration(), makeSettingsConfiguration(), otherSettings],
                log: log
            )
            let primary = try coordinator.bootPrimaryWindow()

            // A successful route is independent of whether Windows grants the
            // foreground request. Neither first open nor reuse may duplicate.
            log.activationSucceeds = false
            XCTAssertTrue(coordinator.openSettings())
            let settings = try XCTUnwrap(coordinator.windows.first(where: { $0.configuration.isSettingsWindow }))
            XCTAssertEqual(settings.configuration.title, "Settings")
            XCTAssertFalse(settings.isPrimary)
            XCTAssertFalse(settings.host === primary)
            XCTAssertFalse(settings.host.platformWindow === primary.platformWindow)
            XCTAssertTrue(coordinator.openSettings())

            XCTAssertEqual(coordinator.windowCount, 2)
            XCTAssertEqual(log.startedHosts.count, 2)
            XCTAssertEqual(log.activationRequests.count, 2)
            XCTAssertTrue(log.activationRequests.allSatisfy { $0 === settings.host })
            XCTAssertEqual(log.terminateMessageLoopCount, 0)
        }
    }

    func testEnvironmentActionAndSettingsLinkRouteToTheManagedSettingsWindow() async throws {
        try await MainActor.run {
            let recorder = HostEnvironmentRecorder()
            let log = SettingsHostingHookLog()
            let coordinator = makeCoordinator(
                configurations: [makePrimaryConfiguration(recorder: recorder), makeSettingsConfiguration()],
                log: log
            )
            try coordinator.bootPrimaryWindow()
            let environment = try XCTUnwrap(recorder.snapshots.last)

            environment.openSettings()
            XCTAssertEqual(coordinator.windowCount, 2)

            let context = makeContext(environment: environment)
            let runtime = RetainedViewRuntime(root: ViewNode())
            let link = SettingsLink().makeComponent(context: context).makeNode(runtime: runtime)
            let reader = SettingsHostingActionReader().makeComponent(context: context).makeNode(runtime: runtime)
            XCTAssertNotNil(link.onActivate)
            XCTAssertNotNil(reader.onActivate)
            link.onActivate?()
            reader.onActivate?()

            XCTAssertEqual(coordinator.windowCount, 2)
            XCTAssertEqual(log.startedHosts.count, 2)
            XCTAssertEqual(log.activationRequests.count, 3)
            XCTAssertTrue(log.activationRequests.allSatisfy { $0 === coordinator.windows[1].host })
        }
    }

    func testSettingsDismissalAndReopeningUseIndependentHostsAndStorageScopes() async throws {
        try await MainActor.run {
            let primaryRecorder = HostEnvironmentRecorder()
            let settingsRecorder = HostEnvironmentRecorder()
            let log = SettingsHostingHookLog()
            let scopePrefix = UUID().uuidString
            var scopeIndex = 0
            let coordinator = makeCoordinator(
                configurations: [
                    makePrimaryConfiguration(recorder: primaryRecorder),
                    makeSettingsConfiguration(recorder: settingsRecorder),
                ],
                log: log,
                sceneStorageScopeProvider: {
                    scopeIndex += 1
                    return "\(scopePrefix):\(scopeIndex)"
                }
            )
            let primary = try coordinator.bootPrimaryWindow()
            let primaryEnvironment = try XCTUnwrap(primaryRecorder.snapshots.last)
            XCTAssertTrue(coordinator.openSettings())
            let firstSettings = try XCTUnwrap(coordinator.windows.first(where: { $0.configuration.isSettingsWindow }))
            let firstEnvironment = try XCTUnwrap(settingsRecorder.snapshots.last)
            XCTAssertNotEqual(firstEnvironment.sceneStorageScope, primaryEnvironment.sceneStorageScope)

            let settingsContext = makeContext(environment: firstEnvironment)
            let settingsStorage = SettingsHostingStorageProbe()
            XCTAssertEqual(ViewBuildContextScope.withCurrent(settingsContext) { settingsStorage.text }, "default")
            settingsStorage.text = "preferences-only"
            let primaryContext = makeContext(environment: primaryEnvironment)
            let primaryStorage = SettingsHostingStorageProbe()
            XCTAssertEqual(ViewBuildContextScope.withCurrent(primaryContext) { primaryStorage.text }, "default")

            firstEnvironment.dismissWindow()
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertTrue(coordinator.windows.first?.host === primary)
            XCTAssertTrue(log.closeRequests.first === firstSettings.host)
            XCTAssertEqual(log.terminateMessageLoopCount, 0)

            primaryEnvironment.openSettings()
            let reopened = try XCTUnwrap(coordinator.windows.first(where: { $0.configuration.isSettingsWindow }))
            let reopenedEnvironment = try XCTUnwrap(settingsRecorder.snapshots.last)
            XCTAssertFalse(reopened.host === firstSettings.host)
            XCTAssertNotEqual(reopenedEnvironment.sceneStorageScope, firstEnvironment.sceneStorageScope)
            XCTAssertNotEqual(reopenedEnvironment.sceneStorageScope, primaryEnvironment.sceneStorageScope)
            XCTAssertEqual(coordinator.windowCount, 2)
            XCTAssertEqual(log.startedHosts.count, 3)

            let reopenedContext = makeContext(environment: reopenedEnvironment)
            let reopenedStorage = SettingsHostingStorageProbe()
            XCTAssertEqual(ViewBuildContextScope.withCurrent(reopenedContext) { reopenedStorage.text }, "default")

            // The settings window receives the same action and re-presents
            // itself rather than creating another settings host.
            reopenedEnvironment.openSettings()
            XCTAssertEqual(coordinator.windowCount, 2)
            XCTAssertEqual(log.startedHosts.count, 3)
            XCTAssertTrue(log.activationRequests.last === reopened.host)
        }
    }

    func testSettingsKeepsApplicationAliveUntilItsOwnWindowCloses() async throws {
        try await MainActor.run {
            let recorder = HostEnvironmentRecorder()
            let log = SettingsHostingHookLog()
            let coordinator = makeCoordinator(
                configurations: [makePrimaryConfiguration(), makeSettingsConfiguration(recorder: recorder)],
                log: log
            )
            let primary = try coordinator.bootPrimaryWindow()
            XCTAssertTrue(coordinator.openSettings())
            let settingsEnvironment = try XCTUnwrap(recorder.snapshots.last)

            primary.windowWillClose(primary.platformWindow)
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertEqual(coordinator.windows.first?.configuration.isSettingsWindow, true)
            XCTAssertEqual(log.terminateMessageLoopCount, 0)

            settingsEnvironment.dismissWindow()
            XCTAssertEqual(coordinator.windowCount, 0)
            XCTAssertEqual(log.terminateMessageLoopCount, 1)
        }
    }

    func testOpenSettingsWithoutASettingsSceneIsANoop() async throws {
        try await MainActor.run {
            let recorder = HostEnvironmentRecorder()
            let log = SettingsHostingHookLog()
            let coordinator = makeCoordinator(
                configurations: [makePrimaryConfiguration(recorder: recorder)],
                log: log
            )
            try coordinator.bootPrimaryWindow()
            let environment = try XCTUnwrap(recorder.snapshots.last)

            XCTAssertFalse(coordinator.openSettings())
            environment.openSettings()

            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertEqual(log.startedHosts.count, 1)
            XCTAssertTrue(log.activationRequests.isEmpty)
            XCTAssertEqual(log.terminateMessageLoopCount, 0)
        }
    }

    func testWindowActionsDoNotPresentSettingsOrMenuBarExtrasAsOrdinaryWindows() async throws {
        try await MainActor.run {
            var settings = makeSettingsConfiguration()
            settings.windowID = "preferences"
            let menu = MenuBarExtra("Menu") { EmptyView() }.windowID("menu").makeWindowConfiguration()
            let log = SettingsHostingHookLog()
            let coordinator = makeCoordinator(
                configurations: [makePrimaryConfiguration(), settings, menu],
                log: log
            )
            try coordinator.bootPrimaryWindow()

            XCTAssertFalse(coordinator.openWindow(payload: WindowActionPayload(id: "preferences")))
            XCTAssertFalse(coordinator.openWindow(payload: WindowActionPayload(id: "menu")))
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertEqual(log.startedHosts.count, 1)

            XCTAssertTrue(coordinator.openSettings())
            XCTAssertEqual(coordinator.windowCount, 2)
            XCTAssertEqual(coordinator.windows.last?.configuration.windowID, "preferences")
        }
    }

    func testSettingsStartupFailureRollsBackRegistrationAndAllowsRetry() async throws {
        try await MainActor.run {
            let log = SettingsHostingHookLog()
            let coordinator = makeCoordinator(
                configurations: [makePrimaryConfiguration(), makeSettingsConfiguration()],
                log: log
            )
            let primary = try coordinator.bootPrimaryWindow()
            log.startFailuresRemaining = 1

            XCTAssertFalse(coordinator.openSettings())
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertTrue(coordinator.windows.first?.host === primary)
            XCTAssertEqual(log.createdHosts.count, 2)
            let failedHost = try XCTUnwrap(log.createdHosts.last)
            XCTAssertNil(failedHost.onWindowClosed)
            XCTAssertEqual(log.renderers.last?.attachedSurfaces.count, 1)
            XCTAssertEqual(log.renderers.last?.detachCount, 1)
            XCTAssertTrue(log.activationRequests.isEmpty)
            XCTAssertEqual(log.terminateMessageLoopCount, 0)

            XCTAssertTrue(coordinator.openSettings())
            XCTAssertEqual(coordinator.windowCount, 2)
            XCTAssertEqual(log.createdHosts.count, 3)
            XCTAssertEqual(log.startedHosts.count, 2)
            XCTAssertFalse(coordinator.windows.last?.host === failedHost)
            XCTAssertEqual(log.activationRequests.count, 1)
            XCTAssertEqual(log.terminateMessageLoopCount, 0)
        }
    }

    func testPrimaryStartupFailureDoesNotTerminateAndAllowsRetry() async throws {
        try await MainActor.run {
            let log = SettingsHostingHookLog()
            log.startFailuresRemaining = 1
            let coordinator = makeCoordinator(
                configurations: [makePrimaryConfiguration(), makeSettingsConfiguration()],
                log: log
            )

            XCTAssertThrowsError(try coordinator.run()) { error in
                XCTAssertEqual(error as? SettingsHostingError, .startFailed)
            }
            XCTAssertEqual(coordinator.windowCount, 0)
            XCTAssertEqual(log.runMessageLoopCount, 0)
            XCTAssertEqual(log.terminateMessageLoopCount, 0)
            XCTAssertEqual(log.renderers.first?.detachCount, 1)
            let failedHost = try XCTUnwrap(log.createdHosts.first)
            XCTAssertNil(failedHost.onWindowClosed)

            XCTAssertEqual(try coordinator.run(), 0)
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertEqual(coordinator.windows.first?.isPrimary, true)
            XCTAssertFalse(coordinator.windows.first?.host === failedHost)
            XCTAssertEqual(log.startedHosts.count, 1)
            XCTAssertEqual(log.runMessageLoopCount, 1)
            XCTAssertEqual(log.terminateMessageLoopCount, 0)
        }
    }

    func testSettingsFactoryFailureDoesNotLeaveAWindowToReuse() async throws {
        try await MainActor.run {
            let log = SettingsHostingHookLog()
            let coordinator = makeCoordinator(
                configurations: [makePrimaryConfiguration(), makeSettingsConfiguration()],
                log: log
            )
            try coordinator.bootPrimaryWindow()
            log.factoryFailuresRemaining = 1

            XCTAssertFalse(coordinator.openSettings())
            XCTAssertEqual(coordinator.windowCount, 1)
            XCTAssertEqual(log.createdHosts.count, 1)
            XCTAssertTrue(log.activationRequests.isEmpty)
            XCTAssertEqual(log.terminateMessageLoopCount, 0)

            XCTAssertTrue(coordinator.openSettings())
            XCTAssertEqual(coordinator.windowCount, 2)
            XCTAssertEqual(log.startedHosts.count, 2)
            XCTAssertEqual(log.activationRequests.count, 1)
        }
    }

    func testValueWindowReuseAlsoRequestsActivationWithoutDuplicating() async throws {
        try await MainActor.run {
            let editor = WindowGroup("Editor", id: "editor", for: String.self) { value in
                Text(value.wrappedValue)
            }
            .makeWindowConfiguration()
            let log = SettingsHostingHookLog()
            let coordinator = makeCoordinator(configurations: [makePrimaryConfiguration(), editor], log: log)
            try coordinator.bootPrimaryWindow()
            let payload = WindowActionPayload(id: "editor", value: AnyHashable("document"))
            XCTAssertTrue(coordinator.openWindow(payload: payload))
            let editorHost = try XCTUnwrap(coordinator.windows.last?.host)
            let activationCount = log.activationRequests.count

            log.activationSucceeds = false
            XCTAssertTrue(coordinator.openWindow(payload: payload))

            XCTAssertEqual(coordinator.windowCount, 2)
            XCTAssertEqual(log.startedHosts.count, 2)
            XCTAssertEqual(log.activationRequests.count, activationCount + 1)
            XCTAssertTrue(log.activationRequests.last === editorHost)
        }
    }

    func testUncreatedNativeWindowCannotBeActivated() async {
        await MainActor.run {
            let window = Win32Window(title: "Not created", clientSize: IntSize(width: 640, height: 480))

            XCTAssertNil(window.nativeHandle)
            XCTAssertFalse(window.activate())
        }
    }
}
