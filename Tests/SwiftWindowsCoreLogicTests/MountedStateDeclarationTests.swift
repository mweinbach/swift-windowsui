import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedStateDeclarationTests: XCTestCase {
    func testInactiveTabPreservesOverlayStateWithoutEvaluatingItsBodyAndRemovalRetiresIt() async throws {
        let model = DeclarationStateModel()
        let capture = DeclarationStateCapture()
        let selection = Binding(get: { model.selection }, set: { model.selection = $0 })
        let fixture = DeclarationStateWindow(
            DeclarationStateParent(model: model) {
                TabView(selection: selection) {
                    if model.hasPage {
                        Text("Overlay base")
                            .frame(width: 180, height: 120)
                            .padding(4)
                            .overlay {
                                DeclarationStateCounter(name: "overlay", seed: 10, capture: capture)
                            }
                            .tag("first").tabItem { Text("Overlay") }
                    }
                    Text("Second page").tag("second").tabItem { Text("Second") }
                }
            })
        defer { fixture.close() }
        try fixture.activate("overlay.increment")
        fixture.flush()
        try fixture.assertText("11", "overlay.value")
        let binding = try capture.binding("overlay")

        selection.wrappedValue = "second"
        fixture.settleTransitions()
        XCTAssertTrue(fixture.nodes("overlay.value").isEmpty)
        let inactiveBuilds = capture.buildCount("overlay")
        model.revision += 1
        fixture.flush()
        binding.wrappedValue = 12
        fixture.flush()
        XCTAssertEqual(binding.wrappedValue, 12)
        XCTAssertEqual(capture.buildCount("overlay"), inactiveBuilds)

        selection.wrappedValue = "first"
        fixture.settleTransitions()
        try fixture.assertText("12", "overlay.value")
        selection.wrappedValue = "second"
        fixture.settleTransitions()
        model.hasPage = false
        fixture.settleTransitions()
        await fixture.assertRetired(binding, lastValue: 12)

        model.hasPage = true
        fixture.settleTransitions()
        selection.wrappedValue = "first"
        fixture.settleTransitions()
        try fixture.assertText("10", "overlay.value")
        await fixture.assertRetired(binding, lastValue: 12)
        try fixture.assertText("10", "overlay.value")
    }

    func testViewThatFitsDiscardsNewRejectedOverlayButPreservesPreviouslySelectedDeclarations() async throws {
        let model = DeclarationStateModel()
        let capture = DeclarationStateCapture()
        let fixture = DeclarationStateWindow(
            DeclarationStateParent(model: model) {
                ViewThatFits(in: .horizontal) {
                    Text("Candidate base")
                        .frame(width: model.primaryFits ? 180 : 1_200, height: 120)
                        .padding(4)
                        .overlay {
                            DeclarationStateCounter(name: "candidate", seed: 10, capture: capture)
                        }
                    DeclarationStateCounter(name: "fallback", seed: 20, capture: capture)
                }
            })
        defer { fixture.close() }
        let rejected = try capture.binding("candidate")
        XCTAssertTrue(fixture.nodes("candidate.value").isEmpty)
        try fixture.assertText("20", "fallback.value")
        await fixture.assertRetired(rejected, lastValue: 10)

        try fixture.activate("fallback.increment")
        fixture.flush()
        try fixture.assertText("21", "fallback.value")
        let fallback = try capture.binding("fallback")
        model.primaryFits = true
        fixture.flush()
        XCTAssertTrue(fixture.nodes("fallback.value").isEmpty)
        try fixture.assertText("10", "candidate.value")
        try fixture.activate("candidate.increment")
        fixture.flush()
        try fixture.assertText("11", "candidate.value")
        let candidate = try capture.binding("candidate")

        let fallbackBuilds = capture.buildCount("fallback")
        fallback.wrappedValue = 22
        fixture.flush()
        XCTAssertEqual(fallback.wrappedValue, 22)
        XCTAssertEqual(capture.buildCount("fallback"), fallbackBuilds)
        try fixture.assertText("11", "candidate.value")
        model.primaryFits = false
        fixture.flush()
        XCTAssertTrue(fixture.nodes("candidate.value").isEmpty)
        try fixture.assertText("22", "fallback.value")

        candidate.wrappedValue = 12
        fixture.flush()
        XCTAssertEqual(try capture.binding("candidate").wrappedValue, 12)
        try fixture.assertText("22", "fallback.value")
        model.primaryFits = true
        fixture.flush()
        try fixture.assertText("12", "candidate.value")
        await fixture.assertRetired(rejected, lastValue: 10)
        try fixture.assertText("12", "candidate.value")
    }

    func testViewThatFitsRejectingAnUnstructuredCandidateDoesNotRetireAPrestructuredSibling() async throws {
        let model = DeclarationStateModel()
        let capture = DeclarationStateCapture()
        let fixture = DeclarationStateWindow(
            DeclarationStateParent(model: model) {
                ViewThatFits(in: .horizontal) {
                    // A raw entry's normalized path can prefix the builder
                    // fragment's path, but it must not own that sibling's State.
                    [
                        AnyView(
                            DeclarationStateCounter(name: "wide.fragment", seed: 10, capture: capture)
                                .frame(width: 1_200, height: 120)),
                        declarationSelectedFragment(seed: 20 + model.revision, capture: capture)[0],
                    ]
                }
            })
        defer { fixture.close() }
        let rejected = try capture.binding("wide.fragment")
        let selected = try capture.binding("selected.fragment")
        let selectedNode = try fixture.node("selected.fragment.value")
        XCTAssertTrue(fixture.nodes("wide.fragment.value").isEmpty)
        try fixture.assertText("20", "selected.fragment.value")
        await fixture.assertRetired(rejected, lastValue: 10)

        selected.wrappedValue = 21
        fixture.flush()
        try fixture.assertText("21", "selected.fragment.value")
        try fixture.activate("selected.fragment.increment")
        fixture.flush()
        try fixture.assertText("22", "selected.fragment.value")
        model.revision = 100
        fixture.flush()

        try fixture.assertText("22", "selected.fragment.value")
        XCTAssertTrue(try fixture.node("selected.fragment.value") === selectedNode)
        selected.wrappedValue = 23
        fixture.flush()
        try fixture.assertText("23", "selected.fragment.value")
        XCTAssertEqual(try capture.binding("selected.fragment").wrappedValue, 23)
        await fixture.assertRetired(try capture.binding("wide.fragment"), lastValue: 10)
        try fixture.assertText("23", "selected.fragment.value")
    }

    func testInactiveExternallyTaggedErasedOptionalRetiresItsRemovedChildBeforeSelection() async throws {
        let model = DeclarationStateModel()
        let capture = DeclarationStateCapture()
        let source = AnyView(DeclarationStateCounter(name: "optional", seed: 3, capture: capture))
        let selection = Binding(get: { model.selection }, set: { model.selection = $0 })
        let fixture = DeclarationStateWindow(
            DeclarationStateParent(model: model) {
                TabView(selection: selection) {
                    AnyView(model.childPresent ? Optional<AnyView>.some(source) : Optional<AnyView>.none)
                        .padding(2)
                        .tag("first").tabItem { Text("Optional") }
                    Text("Second page").tag("second").tabItem { Text("Second") }
                }
            })
        defer { fixture.close() }
        try fixture.activate("optional.increment")
        fixture.flush()
        let binding = try capture.binding("optional")
        XCTAssertEqual(binding.wrappedValue, 4)
        selection.wrappedValue = "second"
        fixture.settleTransitions()
        let inactiveBuilds = capture.buildCount("optional")

        model.childPresent = false
        fixture.settleTransitions()
        XCTAssertEqual(model.selection, "second")
        XCTAssertTrue(fixture.nodes("optional.value").isEmpty)
        XCTAssertEqual(capture.buildCount("optional"), inactiveBuilds)
        await fixture.assertRetired(binding, lastValue: 4)
        model.childPresent = true
        fixture.settleTransitions()
        XCTAssertEqual(capture.buildCount("optional"), inactiveBuilds)
        await fixture.assertRetired(binding, lastValue: 4)

        selection.wrappedValue = "first"
        fixture.settleTransitions()
        try fixture.assertText("3", "optional.value")
        await fixture.assertRetired(binding, lastValue: 4)
        try fixture.assertText("3", "optional.value")
    }

    func testChangingInactiveWrappedExplicitIdentityRetiresItWithoutEvaluatingThePage() async throws {
        let model = DeclarationStateModel()
        let capture = DeclarationStateCapture()
        let source = DeclarationStateCounter(name: "identified", seed: 5, capture: capture)
        let selection = Binding(get: { model.selection }, set: { model.selection = $0 })
        let fixture = DeclarationStateWindow(
            DeclarationStateParent(model: model) {
                TabView(selection: selection) {
                    AnyView(source.id(model.identifier).padding(2))
                        .tag("first").tabItem { Text("Identified") }
                    Text("Second page").tag("second").tabItem { Text("Second") }
                }
            })
        defer { fixture.close() }
        try fixture.activate("identified.increment")
        fixture.flush()
        let binding = try capture.binding("identified")
        XCTAssertEqual(binding.wrappedValue, 6)
        selection.wrappedValue = "second"
        fixture.settleTransitions()
        let inactiveBuilds = capture.buildCount("identified")

        model.identifier = 2
        fixture.settleTransitions()
        XCTAssertEqual(model.selection, "second")
        XCTAssertEqual(capture.buildCount("identified"), inactiveBuilds)
        await fixture.assertRetired(binding, lastValue: 6)
        model.identifier = 1
        fixture.settleTransitions()
        XCTAssertEqual(capture.buildCount("identified"), inactiveBuilds)
        await fixture.assertRetired(binding, lastValue: 6)

        selection.wrappedValue = "first"
        fixture.settleTransitions()
        try fixture.assertText("5", "identified.value")
        await fixture.assertRetired(binding, lastValue: 6)
        try fixture.assertText("5", "identified.value")
    }

    func testInactiveSameTypeConditionalStorageRetiresOnlyThePreviousBranch() async throws {
        let model = DeclarationStateModel()
        let capture = DeclarationStateCapture()
        let selection = Binding(get: { model.selection }, set: { model.selection = $0 })
        let fixture = DeclarationStateWindow(
            DeclarationStateParent(model: model) {
                TabView(selection: selection) {
                    declarationConditional(model: model, capture: capture)
                        .padding(2)
                        .tag("first").tabItem { Text("Conditional") }
                    Text("Second page").tag("second").tabItem { Text("Second") }
                }
            })
        defer { fixture.close() }
        try fixture.activate("branch.increment")
        fixture.flush()
        let first = try capture.binding("branch")
        XCTAssertEqual(first.wrappedValue, 9)
        selection.wrappedValue = "second"
        fixture.settleTransitions()
        let firstInactiveBuilds = capture.buildCount("branch")

        model.firstBranch = false
        fixture.settleTransitions()
        XCTAssertEqual(capture.buildCount("branch"), firstInactiveBuilds)
        await fixture.assertRetired(first, lastValue: 9)
        selection.wrappedValue = "first"
        fixture.settleTransitions()
        try fixture.assertText("20", "branch.value")
        try fixture.activate("branch.increment")
        fixture.flush()
        let second = try capture.binding("branch")
        XCTAssertEqual(second.wrappedValue, 21)

        selection.wrappedValue = "second"
        fixture.settleTransitions()
        let secondInactiveBuilds = capture.buildCount("branch")
        model.firstBranch = true
        fixture.settleTransitions()
        XCTAssertEqual(capture.buildCount("branch"), secondInactiveBuilds)
        await fixture.assertRetired(second, lastValue: 21)
        selection.wrappedValue = "first"
        fixture.settleTransitions()
        try fixture.assertText("8", "branch.value")
        await fixture.assertRetired(first, lastValue: 9)
        await fixture.assertRetired(second, lastValue: 21)
        try fixture.assertText("8", "branch.value")
    }
}

@MainActor
private final class DeclarationStateModel: ObservableObject {
    @Published var selection = "first"
    @Published var revision = 0
    @Published var hasPage = true
    @Published var childPresent = true
    @Published var identifier = 1
    @Published var firstBranch = true
    @Published var primaryFits = false
}

private struct DeclarationStateParent: View {
    @ObservedObject private var model: DeclarationStateModel
    private let content: @MainActor () -> [AnyView]

    init(model: DeclarationStateModel, @ViewBuilder content: @escaping @MainActor () -> [AnyView]) {
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

@MainActor
private final class DeclarationStateCapture {
    var bindings: [String: Binding<Int>] = [:]
    var bodyBuilds: [String: Int] = [:]

    func binding(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Binding<Int> {
        try XCTUnwrap(bindings[name], "Expected an installed binding for \(name)", file: file, line: line)
    }

    func buildCount(_ name: String) -> Int { bodyBuilds[name, default: 0] }
}

private struct DeclarationStateCounter: View {
    @State private var count: Int
    let name: String
    let capture: DeclarationStateCapture

    init(name: String, seed: Int, capture: DeclarationStateCapture) {
        _count = State(initialValue: seed)
        self.name = name
        self.capture = capture
    }

    var body: some View {
        let value = count
        capture.bindings[name] = $count
        capture.bodyBuilds[name, default: 0] += 1
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(value)).accessibilityIdentifier("\(name).value")
            Button("Increment \(name)") { count += 1 }
                .accessibilityIdentifier("\(name).increment")
        }
    }
}

@MainActor
@ViewBuilder
private func declarationSelectedFragment(seed: Int, capture: DeclarationStateCapture) -> [AnyView] {
    DeclarationStateCounter(name: "selected.fragment", seed: seed, capture: capture)
}

@MainActor
private func declarationConditional(
    model: DeclarationStateModel, capture: DeclarationStateCapture
) -> _ConditionalContent<DeclarationStateCounter, DeclarationStateCounter> {
    _ConditionalContent(
        storage: model.firstBranch
            ? .trueContent(DeclarationStateCounter(name: "branch", seed: 8, capture: capture))
            : .falseContent(DeclarationStateCounter(name: "branch", seed: 20, capture: capture)))
}

@MainActor
private final class DeclarationStateWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init<Content: View>(_ content: Content) {
        let configuration = WindowGroupConfiguration(
            title: "Mounted declarations", size: IntSize(width: 640, height: 640), clearColor: .black,
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

    func assertRetired(
        _ binding: Binding<Int>, lastValue: Int, file: StaticString = #filePath, line: UInt = #line
    ) async {
        let reloads = host.executedReloadCount
        binding.wrappedValue = lastValue + 1_000
        XCTAssertEqual(binding.wrappedValue, lastValue, file: file, line: line)
        XCTAssertEqual(host.executedReloadCount, reloads, file: file, line: line)
        await Task.yield()
        await Task.yield()
        flush()
        XCTAssertEqual(host.executedReloadCount, reloads, file: file, line: line)
    }

    func nodes(_ identifier: String) -> [ViewNode] {
        descendants(in: runtime.root).filter { $0.accessibilityIdentifier == identifier }
    }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes(identifier)
        XCTAssertEqual(matches.count, 1, "Expected one node identified as \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func activate(_ identifier: String) throws {
        let identified = try node(identifier)
        let control = try XCTUnwrap(descendants(in: identified).first { $0.isFocusable && $0.onActivate != nil })
        runtime.requestFocus(control)
        XCTAssertTrue(runtime.focusedNode === control)
        host.window(window, keyDown: KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    func assertText(
        _ expected: String, _ identifier: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(try node(identifier, file: file, line: line).text, expected, file: file, line: line)
    }

    private func descendants(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(in: $0) }
    }
}
