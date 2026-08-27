import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class WindowGroupContentIdentityTests: XCTestCase {
    func testManagedWindowsOwnIndependentRootStateAndKeepItAcrossRebuilds() async throws {
        let recorder = WindowContentModelRecorder()
        let shared = WindowContentSharedModel()
        let scene = WindowGroup("Identity", id: "identity") {
            WindowContentIdentityProbe(recorder: recorder)
        }
        .environment(\.colorScheme, .light)
        .environmentObject(shared)
        .windowLevel(.floating)
        let configuration = scene.makeWindowConfiguration()
        XCTAssertEqual(configuration.content.count, 1, "Scene inspection keeps its existing content snapshot")
        recorder.models.removeAll()
        let clock = RuntimeTestClock()
        clock.now = 10
        let coordinator = makeIdentityCoordinator(configurations: [configuration], clock: clock)
        let first = try coordinator.bootPrimaryWindow()
        defer { closeIdentityWindows(coordinator) }
        XCTAssertTrue(coordinator.openWindow(payload: WindowActionPayload(id: "identity")))
        let second = try XCTUnwrap(coordinator.windows.last?.host)
        XCTAssertFalse(first === second)
        XCTAssertEqual(recorder.models.count, 2, "Materialized hosts must not evaluate their factory again")
        let firstModel = recorder.models[0]
        let secondModel = recorder.models[1]
        XCTAssertFalse(firstModel === secondModel)
        XCTAssertTrue(coordinator.windows.allSatisfy { $0.configuration.windowLevel == .floating })
        XCTAssertTrue(identityTexts(first).contains("Light shared"))
        XCTAssertTrue(identityTexts(second).contains("Light shared"))
        let firstRoot = first.hostedRuntime.root.children.first

        let increment = try XCTUnwrap(identityNode(in: first.hostedRuntime.root, identifier: "identity.increment"))
        let control = try XCTUnwrap(identityActivatableNode(in: increment))
        first.hostedRuntime.requestFocus(control)
        first.hostedRuntime.keyDown(KeyboardEvent(keyCode: 0x20))
        paintIdentityHosts([first, second], clock: clock)
        XCTAssertEqual(firstModel.value, 1)
        XCTAssertEqual(secondModel.value, 0)
        XCTAssertTrue(identityTexts(first).contains("Owned 1"))
        XCTAssertTrue(identityTexts(second).contains("Owned 0"))
        XCTAssertTrue(first.hostedRuntime.root.children.first === firstRoot)

        shared.label = "updated"
        paintIdentityHosts([first, second], clock: clock)
        XCTAssertTrue(identityTexts(first).contains("Light updated"))
        XCTAssertTrue(identityTexts(second).contains("Light updated"))
        XCTAssertEqual(recorder.models.count, 2, "A same-window body rebuild must keep the root-owned state")
        XCTAssertEqual(firstModel.value, 1)
        XCTAssertEqual(secondModel.value, 0)
    }

    func testDirectHostsAlsoMaterializeFreshUnidentifiedWindowGroupContent() async {
        let recorder = WindowContentModelRecorder()
        let shared = WindowContentSharedModel()
        let configuration = WindowGroup("Direct identity") {
            WindowContentIdentityProbe(recorder: recorder)
        }
        .environmentObject(shared)
        .makeWindowConfiguration()
        recorder.models.removeAll()
        let clock = RuntimeTestClock()
        clock.now = 20
        let first = makeIdentityHost(configuration: configuration, clock: clock)
        let second = makeIdentityHost(configuration: configuration, clock: clock)
        defer {
            first.windowWillClose(first.platformWindow)
            second.windowWillClose(second.platformWindow)
        }
        first.windowDidCreate(first.platformWindow)
        second.windowDidCreate(second.platformWindow)
        XCTAssertEqual(recorder.models.count, 2)
        guard recorder.models.count == 2 else { return }
        XCTAssertFalse(recorder.models[0] === recorder.models[1])
        recorder.models[0].value = 3
        paintIdentityHosts([first, second], clock: clock)
        XCTAssertTrue(identityTexts(first).contains("Owned 3"))
        XCTAssertTrue(identityTexts(second).contains("Owned 0"))
        XCTAssertEqual(recorder.models.count, 2)
    }

    func testOpeningSettingsAgainReusesItsSingletonWithoutRebuildingWindowGroupContent() async throws {
        let recorder = WindowContentModelRecorder()
        let shared = WindowContentSharedModel()
        let window = WindowGroup("Identity", id: "identity") {
            WindowContentIdentityProbe(recorder: recorder)
        }
        .environmentObject(shared)
        .makeWindowConfiguration()
        let settings = Settings { Text("Settings singleton") }.makeWindowConfiguration()
        XCTAssertNil(settings.windowContentFactory)
        recorder.models.removeAll()
        let clock = RuntimeTestClock()
        clock.now = 30
        let coordinator = makeIdentityCoordinator(configurations: [window, settings], clock: clock)
        _ = try coordinator.bootPrimaryWindow()
        defer { closeIdentityWindows(coordinator) }
        XCTAssertTrue(coordinator.openSettings())
        let settingsHost = try XCTUnwrap(coordinator.windows.first(where: { $0.configuration.isSettingsWindow })?.host)
        XCTAssertTrue(coordinator.openSettings())
        XCTAssertEqual(coordinator.windowCount, 2)
        XCTAssertTrue(coordinator.windows.first(where: { $0.configuration.isSettingsWindow })?.host === settingsHost)
        XCTAssertEqual(recorder.models.count, 1)
        XCTAssertTrue(identityTexts(settingsHost).contains("Settings singleton"))
    }

    func testExplicitPublicContentReplacementOverridesTheDeclarationFactory() async {
        var configuration = WindowGroup("Replaced") { Text("Original declaration") }.makeWindowConfiguration()
        configuration.content = [AnyView(Text("Explicit replacement"))]
        XCTAssertNil(configuration.windowContentFactory)
        let clock = RuntimeTestClock()
        clock.now = 40
        let host = makeIdentityHost(configuration: configuration, clock: clock)
        defer { host.windowWillClose(host.platformWindow) }
        host.windowDidCreate(host.platformWindow)
        XCTAssertTrue(identityTexts(host).contains("Explicit replacement"))
        XCTAssertFalse(identityTexts(host).contains("Original declaration"))
    }
}

@MainActor
private final class WindowContentOwnedModel: ObservableObject {
    @Published var value = 0
}

@MainActor
private final class WindowContentSharedModel: ObservableObject {
    @Published var label = "shared"
}

@MainActor
private final class WindowContentModelRecorder {
    var models: [WindowContentOwnedModel] = []

    func makeModel() -> WindowContentOwnedModel {
        let model = WindowContentOwnedModel()
        models.append(model)
        return model
    }
}

private struct WindowContentIdentityProbe: View {
    @StateObject private var owned: WindowContentOwnedModel
    @EnvironmentObject private var shared: WindowContentSharedModel
    @Environment(\.colorScheme) private var colorScheme

    init(recorder: WindowContentModelRecorder) {
        _owned = StateObject(wrappedValue: recorder.makeModel())
    }

    var body: some View {
        VStack {
            Text("Owned \(owned.value)")
            Text("\(colorScheme == .light ? "Light" : "Dark") \(shared.label)")
            Button("Increment") { owned.value += 1 }
                .accessibilityIdentifier("identity.increment")
        }
    }
}

@MainActor
private func makeIdentityHost(configuration: WindowGroupConfiguration, clock: RuntimeTestClock) -> WinSwiftUIWindowHost
{
    let size = IntSize(width: 640, height: 480)
    let window = Win32Window(title: configuration.title, clientSize: size)
    let surface = SurfaceDescriptor(
        windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
        pixelSize: size, scaleFactor: 1
    )
    let host = WinSwiftUIWindowHost(
        configuration: configuration,
        platformWindow: window,
        renderer: FakeRenderBackend(), batchRenderer: nil,
        surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil
    )
    host.frameClock = { clock.now }
    host.hostedRuntime.clock = { clock.now }
    return host
}

@MainActor
private func makeIdentityCoordinator(
    configurations: [WindowGroupConfiguration], clock: RuntimeTestClock
) -> WinSwiftUIWindowCoordinator {
    WinSwiftUIWindowCoordinator(
        sceneConfigurations: configurations,
        hooks: WindowCoordinatorHooks(
            startWindow: { host in host.windowDidCreate(host.platformWindow) },
            requestCloseWindow: { host in host.windowWillClose(host.platformWindow) },
            runMessageLoop: { 0 },
            terminateMessageLoop: {},
            activateWindow: { _ in true }
        ),
        hostFactory: { configuration, _ in
            XCTAssertNil(configuration.windowContentFactory, "The coordinator materializes content before its factory")
            return makeIdentityHost(configuration: configuration, clock: clock)
        }
    )
}

@MainActor
private func closeIdentityWindows(_ coordinator: WinSwiftUIWindowCoordinator) {
    for window in coordinator.windows { window.host.windowWillClose(window.host.platformWindow) }
}

@MainActor
private func paintIdentityHosts(_ hosts: [WinSwiftUIWindowHost], clock: RuntimeTestClock) {
    for _ in 0..<3 {
        clock.now += 0.02
        for host in hosts { host.windowNeedsDisplay(host.platformWindow) }
    }
}

@MainActor
private func identityTexts(_ host: WinSwiftUIWindowHost) -> [String] {
    func collect(_ node: ViewNode) -> [String] {
        (node.text.map { [$0] } ?? []) + node.children.flatMap(collect)
    }
    return collect(host.hostedRuntime.root)
}

@MainActor
private func identityNode(in node: ViewNode, identifier: String) -> ViewNode? {
    if node.accessibilityIdentifier == identifier { return node }
    for child in node.children {
        if let match = identityNode(in: child, identifier: identifier) { return match }
    }
    return nil
}

@MainActor
private func identityActivatableNode(in node: ViewNode) -> ViewNode? {
    if node.onActivate != nil, node.isFocusable { return node }
    for child in node.children {
        if let match = identityActivatableNode(in: child) { return match }
    }
    return nil
}
