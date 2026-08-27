import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedStateDispatchTests: XCTestCase {
    func testReusedCustomModifierHasIndependentPrivateStateAndSurvivesParentRebuilds() async throws {
        let model = DispatchStateModel()
        let modifier = DispatchCounterModifier()
        let fixture = DispatchStateWindow(
            DispatchStateParent(model: model) {
                Text("Left content").modifier(modifier).accessibilityIdentifier("left")
                Text("Right content").modifier(modifier).accessibilityIdentifier("right")
            })
        defer { fixture.close() }
        let left = try fixture.node("modifier.value", within: "left")
        let right = try fixture.node("modifier.value", within: "right")
        XCTAssertNotEqual(try XCTUnwrap(left.retainedViewIdentity), try XCTUnwrap(right.retainedViewIdentity))

        try fixture.activate("modifier.increment", within: "left")
        fixture.flush()
        try fixture.assertText("1", "modifier.value", within: "left")
        try fixture.assertText("0", "modifier.value", within: "right")

        try fixture.activate("modifier.increment", within: "right")
        try fixture.activate("modifier.increment", within: "right")
        fixture.flush()
        model.revision += 1
        fixture.flush()

        try fixture.assertText("1", "modifier.value", within: "left")
        try fixture.assertText("2", "modifier.value", within: "right")
        XCTAssertTrue(try fixture.node("modifier.value", within: "left") === left)
        XCTAssertTrue(try fixture.node("modifier.value", within: "right") === right)
    }

    func testDefaultBodyUpdatesCustomDynamicPropertyOnceAfterEnvironmentTransforms() async throws {
        let model = DispatchStateModel()
        let events = DispatchEnvironmentEvents()
        let fixture = DispatchStateWindow(
            DispatchStateParent(model: model) {
                DispatchEnvironmentView(events: events)
                    .environment(\.colorScheme, model.scheme)
                    .padding(2)
                    .environment(\.colorScheme, .light)
            })
        defer { fixture.close() }

        events.assertOneUpdatePerBody(scheme: .dark)
        try fixture.assertText("dark:1", "probe.value")
        events.entries.removeAll()
        model.scheme = .light
        fixture.flush()

        events.assertOneUpdatePerBody(scheme: .light)
        try fixture.assertText("light:1", "probe.value")
        events.entries.removeAll()
        model.revision += 1
        fixture.flush()
        events.assertOneUpdatePerBody(scheme: .light)
    }

    func testModifierBodyUpdatesCustomDynamicPropertyOnceAfterEnvironmentTransforms() async throws {
        let model = DispatchStateModel()
        let events = DispatchEnvironmentEvents()
        let fixture = DispatchStateWindow(
            DispatchStateParent(model: model) {
                Text("Modified content")
                    .modifier(DispatchEnvironmentModifier(events: events))
                    .environment(\.colorScheme, model.scheme)
                    .padding(2)
                    .environment(\.colorScheme, .light)
            })
        defer { fixture.close() }

        events.assertOneUpdatePerBody(scheme: .dark)
        try fixture.assertText("dark:1", "probe.value")
        events.entries.removeAll()
        model.scheme = .light
        fixture.flush()

        events.assertOneUpdatePerBody(scheme: .light)
        try fixture.assertText("light:1", "probe.value")
        events.entries.removeAll()
        model.revision += 1
        fixture.flush()
        events.assertOneUpdatePerBody(scheme: .light)
    }

    func testCustomMakeComponentOverrideInstallsPrivateStateThroughMultipleModifiers() async throws {
        let model = DispatchStateModel()
        let fixture = DispatchStateWindow(
            DispatchStateParent(model: model) {
                DispatchComponentCounter(seed: model.revision)
                    .padding(3)
                    .opacity(0.8)
                    .environment(\.colorScheme, model.scheme)
                    .accessibilityIdentifier("override")
            })
        defer { fixture.close() }
        let original = try fixture.node("override.value")
        try fixture.assertText("0", "override.value")
        try fixture.assertText("dark", "override.scheme")

        try fixture.activate("override.increment")
        fixture.flush()
        try fixture.assertText("1", "override.value")
        model.revision = 40
        model.scheme = .light
        fixture.flush()

        try fixture.assertText("1", "override.value")
        try fixture.assertText("light", "override.scheme")
        XCTAssertTrue(try fixture.node("override.value") === original)
        try fixture.activate("override.increment")
        fixture.flush()
        try fixture.assertText("2", "override.value")
    }

    func testErasedOptionalKeepsIndependentSlotsAndRemountsOnlyTheRemovedOccurrence() async throws {
        let model = DispatchStateModel()
        let source = AnyView(DispatchStateCounter(name: "optional"))
        let fixture = DispatchStateWindow(
            DispatchStateParent(model: model) {
                AnyView(model.showsFirst ? Optional<AnyView>.some(source) : Optional<AnyView>.none)
                    .accessibilityIdentifier("left")
                AnyView(Optional<AnyView>.some(source))
                    .accessibilityIdentifier("right")
            })
        defer { fixture.close() }
        let left = try fixture.node("optional.value", within: "left")
        let right = try fixture.node("optional.value", within: "right")
        let leftIdentity = try XCTUnwrap(left.retainedViewIdentity)
        XCTAssertNotEqual(leftIdentity, try XCTUnwrap(right.retainedViewIdentity))

        try fixture.activate("optional.increment", within: "left")
        try fixture.activate("optional.increment", within: "left")
        try fixture.activate("optional.increment", within: "right")
        fixture.flush()
        model.revision += 1
        fixture.flush()
        try fixture.assertText("2", "optional.value", within: "left")
        try fixture.assertText("1", "optional.value", within: "right")
        XCTAssertTrue(try fixture.node("optional.value", within: "left") === left)

        model.showsFirst = false
        fixture.flush()
        XCTAssertEqual(fixture.nodes("optional.value").count, 1)
        XCTAssertTrue(try fixture.node("optional.value", within: "right") === right)
        model.showsFirst = true
        fixture.flush()

        try fixture.assertText("0", "optional.value", within: "left")
        try fixture.assertText("1", "optional.value", within: "right")
        let replacement = try fixture.node("optional.value", within: "left")
        XCTAssertFalse(replacement === left)
        XCTAssertEqual(replacement.retainedViewIdentity, leftIdentity)
        XCTAssertTrue(try fixture.node("optional.value", within: "right") === right)
    }

    func testInactiveTabDeclarationPreservesStateButRemovingItRetiresTheOldGeneration() async throws {
        let model = DispatchStateModel()
        let capture = DispatchStateBindingCapture()
        let first = DispatchStateCounter(name: "first", capture: capture)
        let selection = Binding(get: { model.selection }, set: { model.selection = $0 })
        let fixture = DispatchStateWindow(
            DispatchStateParent(model: model) {
                TabView(selection: selection) {
                    if model.showsFirst {
                        first.tag("first").tabItem { Text("First tab") }
                    }
                    DispatchStateCounter(name: "second")
                        .tag("second").tabItem { Text("Second tab") }
                }
            })
        defer { fixture.close() }
        try fixture.activate("first.increment")
        fixture.flush()
        try fixture.assertText("1", "first.value")
        let firstBinding = try XCTUnwrap(capture.binding)

        selection.wrappedValue = "second"
        fixture.settleTransitions()
        XCTAssertTrue(fixture.nodes("first.value").isEmpty)
        try fixture.assertText("0", "second.value")
        try fixture.activate("second.increment")
        fixture.flush()
        model.revision += 1
        fixture.flush()
        selection.wrappedValue = "first"
        fixture.settleTransitions()

        try fixture.assertText("1", "first.value")
        try fixture.activate("first.increment")
        fixture.flush()
        XCTAssertEqual(firstBinding.wrappedValue, 2)
        selection.wrappedValue = "second"
        fixture.settleTransitions()
        try fixture.assertText("1", "second.value")
        model.showsFirst = false
        fixture.settleTransitions()
        try fixture.assertText("1", "second.value")
        let reloadsAfterRemoval = fixture.host.executedReloadCount

        firstBinding.wrappedValue = 80
        XCTAssertEqual(firstBinding.wrappedValue, 2)
        XCTAssertEqual(fixture.host.executedReloadCount, reloadsAfterRemoval)
        await Task.yield()
        await Task.yield()
        fixture.flush()
        XCTAssertEqual(fixture.host.executedReloadCount, reloadsAfterRemoval)

        model.showsFirst = true
        fixture.settleTransitions()
        try fixture.assertText("1", "second.value")
        selection.wrappedValue = "first"
        fixture.settleTransitions()
        try fixture.assertText("0", "first.value")
        XCTAssertEqual(firstBinding.wrappedValue, 2)
    }
}

@MainActor
private final class DispatchStateModel: ObservableObject {
    @Published var revision = 0
    @Published var scheme = ColorScheme.dark
    @Published var showsFirst = true
    @Published var selection = "first"
}

private struct DispatchStateParent: View {
    @ObservedObject private var model: DispatchStateModel
    private let content: @MainActor () -> [AnyView]

    init(model: DispatchStateModel, @ViewBuilder content: @escaping @MainActor () -> [AnyView]) {
        self.model = model
        self.content = content
    }

    var body: some View {
        let revision = model.revision
        return VStack(alignment: .leading, spacing: 8) {
            Text("Parent \(revision)")
            content()
        }
    }
}

private struct DispatchCounterModifier: ViewModifier {
    @State private var count = 0

    func body(content: Content) -> some View {
        let value = count
        return VStack(alignment: .leading, spacing: 4) {
            content
            Text(String(value)).accessibilityIdentifier("modifier.value")
            Button("Increment modifier") { count += 1 }
                .accessibilityIdentifier("modifier.increment")
        }
    }
}

@MainActor
private final class DispatchEnvironmentEvents {
    var entries: [String] = []

    func assertOneUpdatePerBody(
        scheme: ColorScheme, file: StaticString = #filePath, line: UInt = #line
    ) {
        let name = dispatchSchemeName(scheme)
        XCTAssertFalse(entries.isEmpty, "Expected the host to build the probe", file: file, line: line)
        XCTAssertEqual(entries.count % 2, 0, file: file, line: line)
        for index in stride(from: 0, to: entries.count, by: 2) {
            XCTAssertEqual(
                Array(entries[index..<min(index + 2, entries.count)]),
                ["update:\(name)", "body:\(name):1"], file: file, line: line)
        }
    }
}

@MainActor
private struct DispatchEnvironmentProperty: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    private let events: DispatchEnvironmentEvents
    private var updatedScheme: ColorScheme?
    private var updates = 0

    init(events: DispatchEnvironmentEvents) {
        self.events = events
    }

    nonisolated mutating func update() {
        MainActor.assumeIsolated {
            updates += 1
            updatedScheme = scheme
            events.entries.append("update:\(dispatchSchemeName(scheme))")
        }
    }

    func recordBody() -> String {
        let name = updatedScheme.map(dispatchSchemeName) ?? "unset"
        let label = "\(name):\(updates)"
        events.entries.append("body:\(label)")
        return label
    }
}

private struct DispatchEnvironmentView: View {
    private var probe: DispatchEnvironmentProperty

    init(events: DispatchEnvironmentEvents) {
        probe = DispatchEnvironmentProperty(events: events)
    }

    var body: some View {
        let label = probe.recordBody()
        return Text(label).accessibilityIdentifier("probe.value")
    }
}

private struct DispatchEnvironmentModifier: ViewModifier {
    private var probe: DispatchEnvironmentProperty

    init(events: DispatchEnvironmentEvents) {
        probe = DispatchEnvironmentProperty(events: events)
    }

    func body(content: Content) -> some View {
        let label = probe.recordBody()
        return VStack(alignment: .leading, spacing: 4) {
            content
            Text(label).accessibilityIdentifier("probe.value")
        }
    }
}

private struct DispatchComponentCounter: View {
    typealias Body = Never
    @State private var count: Int
    @Environment(\.colorScheme) private var scheme

    init(seed: Int) {
        _count = State(initialValue: seed)
    }

    var body: Never { fatalError("DispatchComponentCounter uses makeComponent") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let value = count
        let schemeName = dispatchSchemeName(scheme)
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(value)).accessibilityIdentifier("override.value")
            Text(schemeName).accessibilityIdentifier("override.scheme")
            Button("Increment override") { count += 1 }
                .accessibilityIdentifier("override.increment")
        }
        .makeComponent(context: context)
    }
}

@MainActor
private final class DispatchStateBindingCapture {
    var binding: Binding<Int>?
}

private struct DispatchStateCounter: View {
    @State private var count = 0
    let name: String
    var capture: DispatchStateBindingCapture? = nil

    var body: some View {
        let value = count
        capture?.binding = $count
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(value)).accessibilityIdentifier("\(name).value")
            Button("Increment \(name)") { count += 1 }
                .accessibilityIdentifier("\(name).increment")
        }
    }
}

private func dispatchSchemeName(_ scheme: ColorScheme) -> String {
    scheme == .dark ? "dark" : "light"
}

@MainActor
private final class DispatchStateWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init<Content: View>(_ content: Content) {
        let configuration = WindowGroupConfiguration(
            title: "Mounted dispatch", size: IntSize(width: 640, height: 640), clearColor: .black,
            content: [AnyView(content)])
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: configuration.size, scaleFactor: 1)
        let window = Win32Window(title: configuration.title, clientSize: configuration.size)
        let host = WinSwiftUIWindowHost(
            configuration: configuration, platformWindow: window,
            renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        self.clock = clock
        self.window = window
        self.host = host
        host.windowDidCreate(window)
        flush()
        host.resetObservabilityCounters()
    }

    func flush() {
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
        }
    }

    func settleTransitions() {
        flush()
        clock.now += 1
        host.windowNeedsDisplay(window)
        flush()
    }

    func close() { host.windowWillClose(window) }

    func nodes(_ identifier: String) -> [ViewNode] {
        descendants(in: runtime.root).filter { $0.accessibilityIdentifier == identifier }
    }

    func node(
        _ identifier: String, within scope: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        let root = try scope.map { try node($0, file: file, line: line) } ?? runtime.root
        let matches = descendants(in: root).filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one node identified as \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func activate(_ identifier: String, within scope: String? = nil) throws {
        let identified = try node(identifier, within: scope)
        let control = try XCTUnwrap(descendants(in: identified).first { $0.isFocusable && $0.onActivate != nil })
        runtime.requestFocus(control)
        XCTAssertTrue(runtime.focusedNode === control)
        host.window(window, keyDown: KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    func assertText(
        _ expected: String, _ identifier: String, within scope: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try node(identifier, within: scope, file: file, line: line).text, expected, file: file, line: line)
    }

    private func descendants(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(in: $0) }
    }
}
