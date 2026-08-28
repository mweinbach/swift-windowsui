import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Mounted Windows array-authoring regressions, not native SwiftUI qualification.
/// Nested layout and control closures continue using the canonical ViewBuilder.
@MainActor
final class WindowsArrayViewBuilderMountedTests: XCTestCase {
    func testOpaqueArrayRowsUseCanonicalVerticalSpacingWithoutAnEmptyRow() async throws {
        let showsMiddle = false
        let rows = windowsArrayMountedRows {
            Color.red.frame(width: 10, height: 10)
                .accessibilityIdentifier("first").opacity(0.8)
            if showsMiddle {
                Color.green.frame(width: 10, height: 10).accessibilityIdentifier("middle")
            }
            Color.blue.frame(width: 10, height: 10)
                .accessibilityIdentifier("second").opacity(0.6)
        }
        XCTAssertEqual(rows.count, 2)
        let fixture = try WindowsArrayMountedWindow(
            VStack(alignment: .leading, spacing: 7) { rows }
                .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let first = try fixture.node("first")
        let second = try fixture.node("second")
        let stack = try fixture.node("stack")

        XCTAssertEqual(stack.children.count, 2)
        XCTAssertTrue(stack.children.first === first)
        XCTAssertTrue(stack.children.last === second)
        XCTAssertTrue(fixture.nodes("middle").isEmpty)
        XCTAssertEqual(first.resolvedFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(second.resolvedFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(second.resolvedFrame.minY - first.resolvedFrame.minY, 17, accuracy: 0.000_001)
        XCTAssertEqual(second.resolvedFrame.minX, first.resolvedFrame.minX, accuracy: 0.000_001)
    }

    func testOpaqueLoopRowsExpandThroughReErasedGroupIntoCanonicalHStack() async throws {
        let rows = windowsArrayMountedRows {
            for index in 0..<2 {
                Color.red.frame(width: 10, height: 10).opacity(0.8)
                    .accessibilityIdentifier("loop.\(index)")
            }
        }
        let erased = AnyView(AnyView(Group { rows }))
        let fixture = try WindowsArrayMountedWindow(
            HStack(alignment: .top, spacing: 7) { erased }
                .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let first = try fixture.node("loop.0")
        let second = try fixture.node("loop.1")

        XCTAssertEqual(try fixture.node("stack").children.count, 2)
        XCTAssertEqual(first.resolvedFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(second.resolvedFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(second.resolvedFrame.minX - first.resolvedFrame.minX, 17, accuracy: 0.000_001)
        XCTAssertEqual(second.resolvedFrame.minY, first.resolvedFrame.minY, accuracy: 0.000_001)
        XCTAssertNotEqual(try XCTUnwrap(first.retainedViewIdentity), try XCTUnwrap(second.retainedViewIdentity))
    }

    func testKeyedForEachArrayRowsKeepMountedStateAndFollowingSiblingAcrossReorder() async throws {
        let model = WindowsArrayMountedModel()
        let capture = WindowsArrayMountedCapture()
        let fixture = try WindowsArrayMountedWindow(
            WindowsArrayMountedRoot(model: model) {
                ForEach(model.items, id: \.self) { item in
                    windowsArrayMountedRows {
                        WindowsArrayMountedCounter(name: "row.\(item)", seed: item * 10, capture: capture)
                            .frame(width: 80, height: 20).padding(1)
                    }
                }
                WindowsArrayMountedCounter(name: "following", seed: 90, capture: capture)
            })
        defer { fixture.close() }
        var originalNodes: [Int: ViewNode] = [:]
        var originalIdentities: [Int: RetainedViewIdentity] = [:]
        for item in [1, 2, 3] {
            let node = try fixture.node("row.\(item).value")
            originalNodes[item] = node
            originalIdentities[item] = try XCTUnwrap(node.retainedViewIdentity)
            let binding = try capture.binding("row.\(item)")
            binding.wrappedValue = item * 11
        }
        let following = try fixture.node("following.value")
        let followingIdentity = try XCTUnwrap(following.retainedViewIdentity)
        let followingBinding = try capture.binding("following")
        followingBinding.wrappedValue = 91
        fixture.flush()
        XCTAssertEqual(Set(originalIdentities.values).count, 3)

        model.items = [3, 1, 2]
        fixture.flush()

        XCTAssertEqual(try fixture.texts(in: "stack"), ["33", "11", "22", "91"])
        XCTAssertEqual(try fixture.node("stack").children.map(\.dynamicContentIndex), [0, 1, 2, nil])
        for item in [1, 2, 3] {
            let node = try fixture.node("row.\(item).value")
            XCTAssertTrue(node === originalNodes[item])
            XCTAssertEqual(node.retainedViewIdentity, originalIdentities[item])
            XCTAssertEqual(try capture.binding("row.\(item)").wrappedValue, item * 11)
        }
        XCTAssertTrue(try fixture.node("following.value") === following)
        XCTAssertEqual(following.retainedViewIdentity, followingIdentity)
        XCTAssertEqual(followingBinding.wrappedValue, 91)
    }

    func testRawArrayKeepsOriginalTailSlotWhenAnErasedOptionalBecomesEmpty() async throws {
        let model = WindowsArrayMountedModel()
        let capture = WindowsArrayMountedCapture()
        let fixture = try WindowsArrayMountedWindow(
            WindowsArrayMountedRoot(model: model) {
                let optional: WindowsArrayMountedCounter? =
                    model.showsOptional
                    ? WindowsArrayMountedCounter(name: "optional", seed: 3, capture: capture) : nil
                let raw = [
                    AnyView(optional),
                    AnyView(WindowsArrayMountedCounter(name: "tail", seed: 7, capture: capture)),
                ]
                raw
            })
        defer { fixture.close() }
        let tail = try fixture.node("tail.value")
        let identity = try XCTUnwrap(tail.retainedViewIdentity)
        let optionalBinding = try capture.binding("optional")
        let tailBinding = try capture.binding("tail")
        optionalBinding.wrappedValue = 4
        tailBinding.wrappedValue = 41
        fixture.flush()
        let optionalBodies = capture.buildCount("optional")

        model.showsOptional = false
        fixture.flush()

        XCTAssertTrue(fixture.nodes("optional.value").isEmpty)
        XCTAssertEqual(try fixture.node("stack").children.count, 1)
        XCTAssertTrue(try fixture.node("tail.value") === tail)
        XCTAssertEqual(tail.retainedViewIdentity, identity)
        XCTAssertTrue(identity.segments.contains(.slot(1)))
        XCTAssertEqual(tail.text, "41")
        XCTAssertEqual(capture.buildCount("optional"), optionalBodies)
        await fixture.assertRetired(optionalBinding, lastValue: 4)
        tailBinding.wrappedValue = 42
        fixture.flush()
        XCTAssertEqual(tail.text, "42")

        model.showsOptional = true
        fixture.flush()
        XCTAssertEqual(try fixture.node("optional.value").text, "3")
        XCTAssertTrue(try fixture.node("tail.value") === tail)
        XCTAssertEqual(tail.text, "42")
        await fixture.assertRetired(optionalBinding, lastValue: 4)
    }

    func testLoopConditionalAbsencePreservesOriginalIterationAndOuterState() async throws {
        let model = WindowsArrayMountedModel()
        let capture = WindowsArrayMountedCapture()
        let fixture = try WindowsArrayMountedWindow(
            WindowsArrayMountedRoot(model: model) {
                for index in 0..<3 {
                    if index != 1 || model.showsMiddle {
                        WindowsArrayMountedCounter(name: "loop.\(index)", seed: index * 10, capture: capture)
                            .frame(width: 80, height: 20).opacity(0.9)
                    }
                }
                WindowsArrayMountedCounter(name: "outside", seed: 90, capture: capture)
            })
        defer { fixture.close() }
        let last = try fixture.node("loop.2.value")
        let lastIdentity = try XCTUnwrap(last.retainedViewIdentity)
        let outside = try fixture.node("outside.value")
        let outsideIdentity = try XCTUnwrap(outside.retainedViewIdentity)
        let middleBinding = try capture.binding("loop.1")
        let lastBinding = try capture.binding("loop.2")
        let outsideBinding = try capture.binding("outside")
        middleBinding.wrappedValue = 11
        lastBinding.wrappedValue = 22
        outsideBinding.wrappedValue = 91
        fixture.flush()
        let middleBodies = capture.buildCount("loop.1")

        model.showsMiddle = false
        fixture.flush()

        XCTAssertEqual(try fixture.texts(in: "stack"), ["0", "22", "91"])
        XCTAssertTrue(fixture.nodes("loop.1.value").isEmpty)
        XCTAssertEqual(try fixture.node("stack").children.count, 3)
        XCTAssertTrue(try fixture.node("loop.2.value") === last)
        XCTAssertEqual(last.retainedViewIdentity, lastIdentity)
        XCTAssertEqual(lastBinding.wrappedValue, 22)
        XCTAssertTrue(lastIdentity.segments.contains(.iteration(2)))
        XCTAssertFalse(lastIdentity.segments.contains(.iteration(1)))
        XCTAssertTrue(try fixture.node("outside.value") === outside)
        XCTAssertEqual(outside.retainedViewIdentity, outsideIdentity)
        XCTAssertEqual(outsideBinding.wrappedValue, 91)
        XCTAssertEqual(capture.buildCount("loop.1"), middleBodies)
        await fixture.assertRetired(middleBinding, lastValue: 11)

        model.showsMiddle = true
        fixture.flush()
        XCTAssertEqual(try fixture.node("loop.1.value").text, "10")
        XCTAssertTrue(try fixture.node("loop.2.value") === last)
        XCTAssertEqual(last.text, "22")
        XCTAssertTrue(try fixture.node("outside.value") === outside)
        XCTAssertEqual(outside.text, "91")
        await fixture.assertRetired(middleBinding, lastValue: 11)
    }

    func testReErasedInactiveArrayRetiresOnlyRemovedDeclarationWithoutReadingBodies() async throws {
        let model = WindowsArrayMountedModel()
        let capture = WindowsArrayMountedCapture()
        let fixture = try WindowsArrayMountedWindow(
            WindowsArrayMountedRoot(model: model) {
                let secondary = windowsArrayMountedCandidate(present: model.showsOptional, capture: capture)
                ViewThatFits(in: .horizontal) {
                    Color.clear.frame(width: model.primaryFits ? 10 : 1_200, height: 20)
                    AnyView(AnyView(secondary)).frame(width: 180, height: 80)
                }
            })
        defer { fixture.close() }
        let optional = try fixture.node("optional.value")
        let tail = try fixture.node("tail.value")
        let optionalIdentity = try XCTUnwrap(optional.retainedViewIdentity)
        let tailIdentity = try XCTUnwrap(tail.retainedViewIdentity)
        let optionalBinding = try capture.binding("optional")
        let tailBinding = try capture.binding("tail")
        optionalBinding.wrappedValue = 4
        tailBinding.wrappedValue = 8
        fixture.flush()
        let optionalBodies = capture.buildCount("optional")
        let tailBodies = capture.buildCount("tail")

        model.primaryFits = true
        fixture.flush()
        XCTAssertTrue(fixture.nodes("optional.value").isEmpty)
        XCTAssertTrue(fixture.nodes("tail.value").isEmpty)
        XCTAssertEqual(capture.buildCount("optional"), optionalBodies)
        XCTAssertEqual(capture.buildCount("tail"), tailBodies)
        optionalBinding.wrappedValue = 5
        tailBinding.wrappedValue = 9
        fixture.flush()
        XCTAssertEqual(optionalBinding.wrappedValue, 5)
        XCTAssertEqual(tailBinding.wrappedValue, 9)

        model.showsOptional = false
        fixture.flush()
        XCTAssertEqual(capture.buildCount("optional"), optionalBodies)
        XCTAssertEqual(capture.buildCount("tail"), tailBodies)
        await fixture.assertRetired(optionalBinding, lastValue: 5)
        tailBinding.wrappedValue = 10
        fixture.flush()
        XCTAssertEqual(tailBinding.wrappedValue, 10)

        model.showsOptional = true
        fixture.flush()
        XCTAssertEqual(capture.buildCount("optional"), optionalBodies)
        XCTAssertEqual(capture.buildCount("tail"), tailBodies)
        await fixture.assertRetired(optionalBinding, lastValue: 5)
        model.primaryFits = false
        fixture.flush()

        let currentOptional = try fixture.node("optional.value")
        let currentTail = try fixture.node("tail.value")
        XCTAssertEqual(currentOptional.text, "3")
        XCTAssertEqual(currentTail.text, "10")
        XCTAssertEqual(currentOptional.retainedViewIdentity, optionalIdentity)
        XCTAssertEqual(currentTail.retainedViewIdentity, tailIdentity)
        XCTAssertEqual(tailBinding.wrappedValue, 10)
        await fixture.assertRetired(optionalBinding, lastValue: 5)
    }

    func testOpaqueArrayChildrenInstallAndDispatchOncePerMountedParentBuild() async throws {
        let model = WindowsArrayMountedModel()
        let events = WindowsArrayMountedEvents()
        let fixture = try WindowsArrayMountedWindow(
            WindowsArrayMountedRoot(model: model, events: events) {
                WindowsArrayMountedProbe(events: events)
                    .environment(\.colorScheme, model.scheme).frame(width: 120, height: 20)
                WindowsArrayMountedOverride(events: events)
                    .environment(\.colorScheme, model.scheme).frame(width: 180, height: 70)
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
}

@MainActor
private func windowsArrayMountedRows(@WindowsArrayViewBuilder _ content: () -> [AnyView]) -> [AnyView] {
    content()
}

// Keep the changing declaration directly visible through erasure and frame.
// No custom opaque body is evaluated to discover an inactive candidate's children.
@MainActor
@WindowsArrayViewBuilder
private func windowsArrayMountedCandidate(present: Bool, capture: WindowsArrayMountedCapture) -> [AnyView] {
    if present {
        WindowsArrayMountedCounter(name: "optional", seed: 3, capture: capture)
    }
    WindowsArrayMountedCounter(name: "tail", seed: 7, capture: capture).offset(y: 24)
}

@MainActor
private final class WindowsArrayMountedModel: ObservableObject {
    @Published var revision = 0
    @Published var items = [1, 2, 3]
    @Published var showsOptional = true
    @Published var showsMiddle = true
    @Published var primaryFits = false
    @Published var scheme = ColorScheme.dark
}

private struct WindowsArrayMountedRoot: View {
    @ObservedObject private var model: WindowsArrayMountedModel
    private let events: WindowsArrayMountedEvents?
    private let content: @MainActor () -> [AnyView]

    init(
        model: WindowsArrayMountedModel, events: WindowsArrayMountedEvents? = nil,
        @WindowsArrayViewBuilder content: @escaping @MainActor () -> [AnyView]
    ) {
        self.model = model
        self.events = events
        self.content = content
    }

    var body: some View {
        let _ = model.revision
        events?.parentBuilds += 1
        return VStack(alignment: .leading, spacing: 7) { content() }
            .accessibilityIdentifier("stack")
    }
}

@MainActor
private final class WindowsArrayMountedCapture {
    private var bindings: [String: Binding<Int>] = [:]
    private var bodyBuilds: [String: Int] = [:]

    func record(_ name: String, binding: Binding<Int>) {
        bindings[name] = binding
        bodyBuilds[name, default: 0] += 1
    }

    func buildCount(_ name: String) -> Int { bodyBuilds[name, default: 0] }

    func binding(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Binding<Int> {
        try XCTUnwrap(bindings[name], "Expected mounted binding for \(name)", file: file, line: line)
    }
}

private struct WindowsArrayMountedCounter: View {
    @State private var count: Int
    let name: String
    let capture: WindowsArrayMountedCapture

    init(name: String, seed: Int, capture: WindowsArrayMountedCapture) {
        _count = State(initialValue: seed)
        self.name = name
        self.capture = capture
    }

    var body: some View {
        let value = count
        capture.record(name, binding: $count)
        return Text(String(value)).accessibilityIdentifier("\(name).value")
    }
}

@MainActor
private final class WindowsArrayMountedEvents {
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
private struct WindowsArrayMountedProperty: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    private let events: WindowsArrayMountedEvents
    private var updatedScheme: String?
    private var updates = 0

    init(events: WindowsArrayMountedEvents) { self.events = events }

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

private struct WindowsArrayMountedProbe: View {
    private var property: WindowsArrayMountedProperty

    init(events: WindowsArrayMountedEvents) { property = WindowsArrayMountedProperty(events: events) }

    var body: some View {
        let label = property.recordBody()
        return Text(label).accessibilityIdentifier("probe.value")
    }
}

private struct WindowsArrayMountedOverride: View {
    typealias Body = Never
    @State private var count = 0
    @Environment(\.colorScheme) private var scheme
    let events: WindowsArrayMountedEvents

    var body: Never { fatalError("WindowsArrayMountedOverride uses makeComponent") }

    func makeComponent(context: ViewBuildContext) -> Component {
        events.overrideBuilds += 1
        let name = scheme == .dark ? "dark" : "light"
        return VStack(spacing: 0) {
            Text("\(count):\(name)").accessibilityIdentifier("override.value")
            Button("Increment override") { count += 1 }
                .accessibilityIdentifier("override.increment")
        }
        .makeComponent(context: context)
    }
}

@MainActor
private final class WindowsArrayMountedWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init<Content: View>(_ content: Content) throws {
        let configuration = WindowGroupConfiguration(
            title: "Windows array builder", size: IntSize(width: 640, height: 480), clearColor: .black,
            content: [AnyView(content)])
        let clock = RuntimeTestClock()
        clock.now = 8_000
        let handle = try XCTUnwrap(NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1)))
        let surface = SurfaceDescriptor(windowHandle: handle, pixelSize: configuration.size, scaleFactor: 1)
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

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes(identifier)
        XCTAssertEqual(matches.count, 1, "Expected one node identified as \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func texts(in identifier: String) throws -> [String] {
        descendants(in: try node(identifier)).compactMap(\.text)
    }

    func activate(_ identifier: String) throws {
        let identified = try node(identifier)
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
