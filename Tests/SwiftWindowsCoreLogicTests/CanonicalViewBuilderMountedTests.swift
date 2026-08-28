import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class CanonicalViewBuilderMountedTests: XCTestCase {
    func testUnannotatedPairBodyProvidesVerticalStackChildren() async throws {
        let fixture = CanonicalMountedWindow(
            VStack(alignment: .leading, spacing: 7) {
                CanonicalMountedPair()
            }
            .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let stack = try fixture.node("stack")
        let first = try fixture.node("pair.first")
        let second = try fixture.node("pair.second")

        XCTAssertEqual(stack.children.count, 2)
        XCTAssertTrue(stack.children.first === first)
        XCTAssertTrue(stack.children.last === second)
        XCTAssertEqual(first.resolvedFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(second.resolvedFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(second.resolvedFrame.minY - first.resolvedFrame.minY, 17, accuracy: 0.000_001)
        XCTAssertEqual(second.resolvedFrame.minX, first.resolvedFrame.minX, accuracy: 0.000_001)
    }

    func testUnannotatedPairBodyProvidesHorizontalStackChildren() async throws {
        let fixture = CanonicalMountedWindow(
            HStack(alignment: .top, spacing: 7) {
                CanonicalMountedPair()
            }
            .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let stack = try fixture.node("stack")
        let first = try fixture.node("pair.first")
        let second = try fixture.node("pair.second")

        XCTAssertEqual(stack.children.count, 2)
        XCTAssertTrue(stack.children.first === first)
        XCTAssertTrue(stack.children.last === second)
        XCTAssertEqual(first.resolvedFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(second.resolvedFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(second.resolvedFrame.minX - first.resolvedFrame.minX, 17, accuracy: 0.000_001)
        XCTAssertEqual(second.resolvedFrame.minY, first.resolvedFrame.minY, accuracy: 0.000_001)
    }

    func testUnannotatedGeometryBodyUsesEachAssignedSlot() async throws {
        let fixture = CanonicalMountedWindow(
            VStack(alignment: .leading, spacing: 7) {
                CanonicalMountedGeometryPair()
            }
            .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let first = try fixture.node("geometry.first.slot")
        let second = try fixture.node("geometry.second.slot")
        let firstReader = try XCTUnwrap(first.children.first)
        let secondReader = try XCTUnwrap(second.children.first)

        XCTAssertEqual(try fixture.node("stack").children.count, 2)
        XCTAssertEqual(first.resolvedFrame.size, Size(width: 80, height: 24))
        XCTAssertEqual(second.resolvedFrame.size, Size(width: 120, height: 36))
        XCTAssertEqual(firstReader.geometryReaderBuiltSize, first.resolvedFrame.size)
        XCTAssertEqual(secondReader.geometryReaderBuiltSize, second.resolvedFrame.size)
        XCTAssertEqual(try fixture.node("geometry.first.value").text, "80 X 24")
        XCTAssertEqual(try fixture.node("geometry.second.value").text, "120 X 36")
        XCTAssertEqual(second.resolvedFrame.minY - first.resolvedFrame.minY, 31, accuracy: 0.000_001)
    }

    func testMutableTupleKeepsIndependentReusedStateAndFollowingOwner() async throws {
        let model = CanonicalMountedModel()
        let capture = CanonicalMountedCapture()
        let source = CanonicalMountedCounter(name: "shared", seed: 0)
        var tuple = TupleView(
            (
                source.accessibilityIdentifier("left"),
                source.accessibilityIdentifier("right")
            ))
        let fixture = CanonicalMountedWindow(
            CanonicalMountedParent(model: model) {
                tuple
                CanonicalMountedCounter(name: "following", seed: 30, capture: capture)
            })
        defer { fixture.close() }
        let left = try fixture.node("shared.value", within: "left")
        let right = try fixture.node("shared.value", within: "right")
        let following = try fixture.node("following.value")
        XCTAssertNotEqual(try XCTUnwrap(left.retainedViewIdentity), try XCTUnwrap(right.retainedViewIdentity))

        try fixture.activate("shared.increment", within: "left")
        fixture.flush()
        XCTAssertEqual(try fixture.node("shared.value", within: "left").text, "1")
        XCTAssertEqual(try fixture.node("shared.value", within: "right").text, "0")
        let followingBinding = try capture.binding("following")
        followingBinding.wrappedValue = 31
        fixture.flush()

        tuple.value.0 = CanonicalMountedCounter(name: "shared", seed: 999).accessibilityIdentifier("left")
        model.revision += 1
        fixture.flush()
        try fixture.activate("shared.increment", within: "right")
        try fixture.activate("shared.increment", within: "right")
        fixture.flush()

        XCTAssertTrue(try fixture.node("shared.value", within: "left") === left)
        XCTAssertTrue(try fixture.node("shared.value", within: "right") === right)
        XCTAssertEqual(left.text, "1")
        XCTAssertEqual(right.text, "2")
        XCTAssertTrue(try fixture.node("following.value") === following)
        XCTAssertEqual(following.text, "31")
        XCTAssertEqual(followingBinding.wrappedValue, 31)
    }

    func testNestedTupleMutationReadsCurrentValuesWithoutResettingState() async throws {
        let model = CanonicalMountedModel()
        let capture = CanonicalMountedCapture()
        var tuple = TupleView(
            (
                TupleView(
                    (
                        CanonicalMountedLabel(text: "A", name: "a"),
                        CanonicalMountedCounter(name: "nested", seed: 5, capture: capture)
                    )),
                CanonicalMountedLabel(text: "B", name: "b")
            ))
        let fixture = CanonicalMountedWindow(
            CanonicalMountedParent(model: model) {
                tuple
                CanonicalMountedCounter(name: "following", seed: 30, capture: capture)
            })
        defer { fixture.close() }
        let first = try fixture.node("a.label")
        let last = try fixture.node("b.label")
        let nested = try fixture.node("nested.value")
        let following = try fixture.node("following.value")
        let nestedBinding = try capture.binding("nested")
        let followingBinding = try capture.binding("following")
        nestedBinding.wrappedValue = 6
        followingBinding.wrappedValue = 35
        fixture.flush()

        tuple.value.0.value.0.text = "A2"
        tuple.value.0.value.1 = CanonicalMountedCounter(name: "nested", seed: 999, capture: capture)
        tuple.value.1.text = "B2"
        model.revision += 1
        fixture.flush()

        XCTAssertEqual(try fixture.node("a.label").text, "A2")
        XCTAssertEqual(try fixture.node("b.label").text, "B2")
        XCTAssertTrue(try fixture.node("a.label") === first)
        XCTAssertTrue(try fixture.node("b.label") === last)
        XCTAssertTrue(try fixture.node("nested.value") === nested)
        XCTAssertTrue(try fixture.node("following.value") === following)
        XCTAssertEqual(nested.text, "6")
        XCTAssertEqual(following.text, "35")
    }

    func testInheritedBodyAndCustomOverrideDispatchOncePerParentBuild() async throws {
        let model = CanonicalMountedModel()
        let events = CanonicalMountedEvents()
        let fixture = CanonicalMountedWindow(
            CanonicalMountedParent(model: model, events: events) {
                CanonicalMountedEnvironmentView(events: events)
                    .environment(\.colorScheme, model.scheme)
                CanonicalMountedOverride(events: events)
                    .environment(\.colorScheme, model.scheme)
            })
        defer { fixture.close() }
        events.assertPerParent(scheme: "dark")
        XCTAssertEqual(try fixture.node("probe.value").text, "dark:1")
        XCTAssertEqual(try fixture.node("override.value").text, "0:dark")

        events.reset()
        try fixture.activate("override.increment")
        fixture.flush()
        events.assertPerParent(scheme: "dark")
        XCTAssertEqual(try fixture.node("override.value").text, "1:dark")

        events.reset()
        model.scheme = .light
        fixture.flush()
        events.assertPerParent(scheme: "light")
        XCTAssertEqual(try fixture.node("probe.value").text, "light:1")
        XCTAssertEqual(try fixture.node("override.value").text, "1:light")
    }

    func testEmptyInheritedBodyKeepsOwnerWithoutPhantomSpacing() async throws {
        let model = CanonicalMountedModel()
        model.childPresent = false
        let capture = CanonicalMountedCapture()
        let fixture = CanonicalMountedWindow(
            CanonicalMountedParent(model: model) {
                Color.red.frame(width: 10, height: 10).accessibilityIdentifier("before")
                CanonicalMountedEmptyOwner(showsContent: model.childPresent, capture: capture)
                Color.blue.frame(width: 10, height: 10).accessibilityIdentifier("after")
            })
        defer { fixture.close() }
        let before = try fixture.node("before")
        let after = try fixture.node("after")
        let binding = try capture.binding("empty")
        XCTAssertEqual(try fixture.node("stack").children.count, 2)
        XCTAssertEqual(after.resolvedFrame.minY - before.resolvedFrame.minY, 17, accuracy: 0.000_001)
        XCTAssertTrue(fixture.nodes("empty.value").isEmpty)

        binding.wrappedValue = 7
        fixture.flush()
        XCTAssertEqual(try capture.binding("empty").wrappedValue, 7)
        XCTAssertEqual(try fixture.node("stack").children.count, 2)
        model.childPresent = true
        fixture.flush()

        XCTAssertEqual(try fixture.node("empty.value").text, "7")
        XCTAssertEqual(try fixture.node("stack").children.count, 3)
        XCTAssertTrue(try fixture.node("before") === before)
        XCTAssertTrue(try fixture.node("after") === after)
        XCTAssertEqual(after.resolvedFrame.minY - before.resolvedFrame.minY, 34, accuracy: 0.000_001)
    }

    func testReErasurePreservesOldCopiesAndFreshTupleValuesWithoutReadingBodies() async throws {
        let model = CanonicalMountedModel()
        let capture = CanonicalMountedCapture()
        var tuple = TupleView(
            (
                CanonicalMountedLabel(text: "A", name: "a", capture: capture),
                CanonicalMountedLabel(text: "B", name: "b", capture: capture)
            ))
        let copied = tuple
        let oldErasure = AnyView(AnyView(tuple))
        var freshErasure = AnyView(tuple)
        XCTAssertTrue(capture.bodyBuilds.isEmpty, "Tuple construction and erasure must not read custom bodies.")
        let fixture = CanonicalMountedWindow(
            CanonicalMountedParent(model: model) {
                let selected = model.copyMode == 0 ? freshErasure : (model.copyMode == 1 ? oldErasure : AnyView(copied))
                selected
            })
        defer { fixture.close() }
        XCTAssertEqual(try fixture.node("a.label").text, "A")
        let builds = capture.bodyBuilds

        tuple.value.0.text = "A2"
        tuple.value.1.text = "B2"
        freshErasure = AnyView(AnyView(tuple))
        XCTAssertEqual(capture.bodyBuilds, builds, "Fresh erasure only captures the current value.")
        model.revision += 1
        fixture.flush()
        XCTAssertEqual(try fixture.node("a.label").text, "A2")
        XCTAssertEqual(try fixture.node("b.label").text, "B2")

        for mode in [1, 2] {
            model.copyMode = mode
            fixture.flush()
            XCTAssertEqual(try fixture.node("a.label").text, "A")
            XCTAssertEqual(try fixture.node("b.label").text, "B")
        }
        model.copyMode = 0
        fixture.flush()
        XCTAssertEqual(try fixture.node("a.label").text, "A2")
        XCTAssertEqual(try fixture.node("b.label").text, "B2")
    }

    func testInactiveTypedOptionalRetiresRemovedChildWithoutReadingItsBody() async throws {
        let model = CanonicalMountedModel()
        let capture = CanonicalMountedCapture()
        let fixture = CanonicalMountedWindow(
            CanonicalMountedParent(model: model) {
                ViewThatFits(in: .horizontal) {
                    Color.clear.frame(width: model.primaryFits ? 10 : 1_200, height: 20)
                    canonicalMountedOptional(present: model.childPresent, capture: capture)
                        .frame(width: 180, height: 80)
                }
            })
        defer { fixture.close() }
        try fixture.activate("optional.increment")
        fixture.flush()
        let binding = try capture.binding("optional")
        XCTAssertEqual(binding.wrappedValue, 4)
        let builds = capture.buildCount("optional")

        model.primaryFits = true
        fixture.flush()
        XCTAssertTrue(fixture.nodes("optional.value").isEmpty)
        XCTAssertEqual(capture.buildCount("optional"), builds)
        binding.wrappedValue = 5
        fixture.flush()
        XCTAssertEqual(binding.wrappedValue, 5)
        XCTAssertEqual(capture.buildCount("optional"), builds)

        model.childPresent = false
        fixture.flush()
        XCTAssertEqual(capture.buildCount("optional"), builds)
        await fixture.assertRetired(binding, lastValue: 5)
        model.childPresent = true
        fixture.flush()
        XCTAssertEqual(capture.buildCount("optional"), builds)
        await fixture.assertRetired(binding, lastValue: 5)

        model.primaryFits = false
        fixture.flush()
        XCTAssertEqual(try fixture.node("optional.value").text, "3")
        await fixture.assertRetired(binding, lastValue: 5)
    }

    func testInactiveTypedConditionalRetiresOnlyItsPreviousBranchWithoutBodyReads() async throws {
        let model = CanonicalMountedModel()
        let capture = CanonicalMountedCapture()
        let fixture = CanonicalMountedWindow(
            CanonicalMountedParent(model: model) {
                ViewThatFits(in: .horizontal) {
                    Color.clear.frame(width: model.primaryFits ? 10 : 1_200, height: 20)
                    canonicalMountedConditional(first: model.firstBranch, capture: capture)
                        .frame(width: 180, height: 80)
                }
                CanonicalMountedCounter(name: "following", seed: 30, capture: capture)
            })
        defer { fixture.close() }
        try fixture.activate("branch.increment")
        fixture.flush()
        let old = try capture.binding("branch")
        let following = try capture.binding("following")
        following.wrappedValue = 31
        fixture.flush()
        let builds = capture.buildCount("branch")

        model.primaryFits = true
        fixture.flush()
        model.firstBranch = false
        fixture.flush()
        XCTAssertTrue(fixture.nodes("branch.value").isEmpty)
        XCTAssertEqual(capture.buildCount("branch"), builds)
        await fixture.assertRetired(old, lastValue: 9)
        XCTAssertEqual(following.wrappedValue, 31)
        XCTAssertEqual(try fixture.node("following.value").text, "31")

        model.primaryFits = false
        fixture.flush()
        XCTAssertEqual(try fixture.node("branch.value").text, "20")
        XCTAssertEqual(try fixture.node("following.value").text, "31")
        await fixture.assertRetired(old, lastValue: 9)
    }

    func testInactiveTypedIterationRetiresRemovedTailAndPreservesEarlierOwner() async throws {
        let model = CanonicalMountedModel()
        let capture = CanonicalMountedCapture()
        let fixture = CanonicalMountedWindow(
            CanonicalMountedParent(model: model) {
                ViewThatFits(in: .horizontal) {
                    Color.clear.frame(width: model.primaryFits ? 10 : 1_200, height: 20)
                    canonicalMountedIteration(model.items, capture: capture)
                        .frame(width: 180, height: 120)
                }
            })
        defer { fixture.close() }
        let first = try capture.binding("iteration.0")
        let last = try capture.binding("iteration.1")
        first.wrappedValue = 11
        last.wrappedValue = 21
        fixture.flush()
        let firstBuilds = capture.buildCount("iteration.0")
        let lastBuilds = capture.buildCount("iteration.1")

        model.primaryFits = true
        fixture.flush()
        model.items = [0]
        fixture.flush()
        XCTAssertEqual(capture.buildCount("iteration.0"), firstBuilds)
        XCTAssertEqual(capture.buildCount("iteration.1"), lastBuilds)
        await fixture.assertRetired(last, lastValue: 21)

        first.wrappedValue = 12
        fixture.flush()
        XCTAssertEqual(first.wrappedValue, 12)
        XCTAssertEqual(capture.buildCount("iteration.0"), firstBuilds)
        model.items = [0, 1]
        fixture.flush()
        XCTAssertEqual(capture.buildCount("iteration.0"), firstBuilds)
        XCTAssertEqual(capture.buildCount("iteration.1"), lastBuilds)
        await fixture.assertRetired(last, lastValue: 21)

        model.primaryFits = false
        fixture.flush()
        XCTAssertEqual(try fixture.node("iteration.0.value").text, "12")
        XCTAssertEqual(try fixture.node("iteration.1.value").text, "20")
        await fixture.assertRetired(last, lastValue: 21)
    }
}

// Ordinary custom bodies intentionally have no explicit @ViewBuilder.
private struct CanonicalMountedPair: View {
    var body: some View {
        Color.red.frame(width: 10, height: 10).accessibilityIdentifier("pair.first")
        Color.blue.frame(width: 10, height: 10).accessibilityIdentifier("pair.second")
    }
}

private struct CanonicalMountedGeometryPair: View {
    var body: some View {
        GeometryReader { proxy in
            Text("\(Int(proxy.size.width)) X \(Int(proxy.size.height))")
                .accessibilityIdentifier("geometry.first.value")
        }
        .frame(width: 80, height: 24)
        .accessibilityIdentifier("geometry.first.slot")
        GeometryReader { proxy in
            Text("\(Int(proxy.size.width)) X \(Int(proxy.size.height))")
                .accessibilityIdentifier("geometry.second.value")
        }
        .frame(width: 120, height: 36)
        .accessibilityIdentifier("geometry.second.slot")
    }
}

@MainActor
private final class CanonicalMountedModel: ObservableObject {
    @Published var revision = 0
    @Published var scheme = ColorScheme.dark
    @Published var childPresent = true
    @Published var firstBranch = true
    @Published var primaryFits = false
    @Published var items = [0, 1]
    @Published var copyMode = 0
}

private struct CanonicalMountedParent: View {
    @ObservedObject private var model: CanonicalMountedModel
    private let events: CanonicalMountedEvents?
    private let content: @MainActor () -> [AnyView]

    init(
        model: CanonicalMountedModel, events: CanonicalMountedEvents? = nil,
        @ViewBuilder content: @escaping @MainActor () -> [AnyView]
    ) {
        self.model = model
        self.events = events
        self.content = content
    }

    var body: some View {
        let _ = model.revision
        events?.parentBuilds += 1
        return VStack(alignment: .leading, spacing: 7) {
            content()
        }
        .accessibilityIdentifier("stack")
    }
}

@MainActor
private final class CanonicalMountedCapture {
    var bindings: [String: Binding<Int>] = [:]
    var bodyBuilds: [String: Int] = [:]

    func record(_ name: String, binding: Binding<Int>? = nil) {
        bodyBuilds[name, default: 0] += 1
        if let binding { bindings[name] = binding }
    }

    func buildCount(_ name: String) -> Int { bodyBuilds[name, default: 0] }

    func binding(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Binding<Int> {
        try XCTUnwrap(bindings[name], "Expected mounted binding for \(name)", file: file, line: line)
    }
}

private struct CanonicalMountedLabel: View {
    var text: String
    let name: String
    var capture: CanonicalMountedCapture? = nil

    var body: some View {
        let _ = capture?.record(name)
        Text(text).accessibilityIdentifier("\(name).label")
    }
}

private struct CanonicalMountedCounter: View {
    @State private var count: Int
    let name: String
    let capture: CanonicalMountedCapture?

    init(name: String, seed: Int, capture: CanonicalMountedCapture? = nil) {
        _count = State(initialValue: seed)
        self.name = name
        self.capture = capture
    }

    var body: some View {
        let value = count
        let _ = capture?.record(name, binding: $count)
        Text(String(value)).accessibilityIdentifier("\(name).value")
        Button("Increment \(name)") { count += 1 }
            .accessibilityIdentifier("\(name).increment")
    }
}

private struct CanonicalMountedEmptyOwner: View {
    @State private var count = 0
    let showsContent: Bool
    let capture: CanonicalMountedCapture

    var body: some View {
        let _ = capture.record("empty", binding: $count)
        if showsContent {
            Text(String(count)).accessibilityIdentifier("empty.value")
                .frame(width: 10, height: 10)
        }
    }
}

@MainActor
private final class CanonicalMountedEvents {
    var parentBuilds = 0
    var overrideBuilds = 0
    var entries: [String] = []

    func reset() {
        parentBuilds = 0
        overrideBuilds = 0
        entries.removeAll()
    }

    func assertPerParent(scheme: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(parentBuilds, 0, file: file, line: line)
        XCTAssertEqual(overrideBuilds, parentBuilds, file: file, line: line)
        XCTAssertEqual(entries.count, parentBuilds * 2, file: file, line: line)
        for index in stride(from: 0, to: entries.count, by: 2) {
            XCTAssertEqual(
                Array(entries[index..<min(index + 2, entries.count)]),
                ["update:\(scheme)", "body:\(scheme):1"], file: file, line: line)
        }
    }
}

@MainActor
private struct CanonicalMountedEnvironmentProperty: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    private let events: CanonicalMountedEvents
    private var updatedScheme: String?
    private var updates = 0

    init(events: CanonicalMountedEvents) { self.events = events }

    nonisolated mutating func update() {
        MainActor.assumeIsolated {
            updates += 1
            let name = scheme == .dark ? "dark" : "light"
            updatedScheme = name
            events.entries.append("update:\(name)")
        }
    }

    func recordBody() -> String {
        let label = "\(updatedScheme ?? "unset"):\(updates)"
        events.entries.append("body:\(label)")
        return label
    }
}

private struct CanonicalMountedEnvironmentView: View {
    private var probe: CanonicalMountedEnvironmentProperty

    init(events: CanonicalMountedEvents) { probe = CanonicalMountedEnvironmentProperty(events: events) }

    var body: some View {
        let label = probe.recordBody()
        Text(label).accessibilityIdentifier("probe.value")
        Text("Second inherited child").accessibilityIdentifier("probe.second")
    }
}

private struct CanonicalMountedOverride: View {
    typealias Body = Never
    @State private var count = 0
    @Environment(\.colorScheme) private var scheme
    let events: CanonicalMountedEvents

    var body: Never { fatalError("CanonicalMountedOverride uses makeComponent") }

    func makeComponent(context: ViewBuildContext) -> Component {
        events.overrideBuilds += 1
        let name = scheme == .dark ? "dark" : "light"
        return Group {
            Text("\(count):\(name)").accessibilityIdentifier("override.value")
            Button("Increment override") { count += 1 }
                .accessibilityIdentifier("override.increment")
        }
        .makeComponent(context: context)
    }
}

// These return known typed structures directly; no opaque custom body is opened
// to discover the declarations of an inactive ViewThatFits alternative.
@MainActor
@ViewBuilder
private func canonicalMountedOptional(present: Bool, capture: CanonicalMountedCapture) -> some View {
    if present {
        CanonicalMountedCounter(name: "optional", seed: 3, capture: capture)
    }
}

@MainActor
@ViewBuilder
private func canonicalMountedConditional(first: Bool, capture: CanonicalMountedCapture) -> some View {
    if first {
        CanonicalMountedCounter(name: "branch", seed: 8, capture: capture)
    } else {
        CanonicalMountedCounter(name: "branch", seed: 20, capture: capture)
    }
}

@MainActor
@ViewBuilder
private func canonicalMountedIteration(_ items: [Int], capture: CanonicalMountedCapture) -> some View {
    for index in items {
        CanonicalMountedCounter(name: "iteration.\(index)", seed: 10 + index * 10, capture: capture)
    }
}

@MainActor
private final class CanonicalMountedWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init<Content: View>(_ content: Content) {
        let configuration = WindowGroupConfiguration(
            title: "Canonical builder", size: IntSize(width: 640, height: 480), clearColor: .black,
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

    private func descendants(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(in: $0) }
    }
}
