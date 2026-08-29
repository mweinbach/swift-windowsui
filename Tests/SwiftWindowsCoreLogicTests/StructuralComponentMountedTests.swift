import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class StructuralComponentMountedTests: XCTestCase {
    func testPairBodyProvidesTwoDirectVerticalStackChildren() async throws {
        let fixture = StructuralComponentWindow(
            VStack(alignment: .leading, spacing: 7) {
                StructuralComponentPairBody()
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

    func testPairBodyProvidesTwoDirectHorizontalStackChildren() async throws {
        let fixture = StructuralComponentWindow(
            HStack(alignment: .top, spacing: 7) {
                StructuralComponentPairBody()
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

    func testStructuralBodyKeepsStateIdentityAndOneEnvironmentUpdatePerParentBuild() async throws {
        let model = StructuralComponentModel()
        let events = StructuralComponentEvents()
        let fixture = StructuralComponentWindow(
            StructuralComponentParent(model: model, events: events) {
                StructuralComponentStatePair(seed: model.revision + 10, events: events)
                    .environment(\.colorScheme, model.scheme)
            })
        defer { fixture.close() }
        let original = try fixture.node("state.value")
        let identity = try XCTUnwrap(original.retainedViewIdentity)

        XCTAssertEqual(try fixture.node("stack").children.count, 2)
        XCTAssertEqual(original.text, "10:dark:1")
        events.assertOneUpdateAndBodyPerParentBuild(scheme: "dark")

        events.reset()
        try fixture.activate("state.increment")
        fixture.flush()
        XCTAssertEqual(try fixture.node("state.value").text, "11:dark:1")
        events.assertOneUpdateAndBodyPerParentBuild(scheme: "dark")

        events.reset()
        model.scheme = .light
        fixture.flush()
        XCTAssertEqual(try fixture.node("state.value").text, "11:light:1")
        events.assertOneUpdateAndBodyPerParentBuild(scheme: "light")

        events.reset()
        model.revision = 100
        fixture.flush()
        let updated = try fixture.node("state.value")
        XCTAssertTrue(updated === original)
        XCTAssertEqual(updated.retainedViewIdentity, identity)
        XCTAssertEqual(updated.text, "11:light:1", "A fresh authored seed cannot replace the mounted count.")
        events.assertOneUpdateAndBodyPerParentBuild(scheme: "light")
    }

    func testCustomComponentOverrideCanReturnStructuralChildrenWithInstalledState() async throws {
        let model = StructuralComponentModel()
        let events = StructuralComponentEvents()
        let fixture = StructuralComponentWindow(
            StructuralComponentParent(model: model, events: events) {
                StructuralComponentOverride(seed: model.revision, events: events)
                    .environment(\.colorScheme, model.scheme)
            })
        defer { fixture.close() }
        let original = try fixture.node("override.value")
        XCTAssertEqual(try fixture.node("stack").children.count, 2)
        XCTAssertEqual(original.text, "0:dark")
        XCTAssertGreaterThan(events.parentBuilds, 0)
        XCTAssertEqual(events.overrideBuilds, events.parentBuilds)

        events.reset()
        try fixture.activate("override.increment")
        fixture.flush()
        XCTAssertEqual(try fixture.node("override.value").text, "1:dark")
        XCTAssertEqual(events.overrideBuilds, events.parentBuilds)

        events.reset()
        model.revision = 99
        model.scheme = .light
        fixture.flush()

        XCTAssertTrue(try fixture.node("override.value") === original)
        XCTAssertEqual(original.text, "1:light")
        XCTAssertGreaterThan(events.parentBuilds, 0)
        XCTAssertEqual(events.overrideBuilds, events.parentBuilds)
    }

    func testEmptyBodyAddsNoSpacingAndKeepsItsMountedStateOwner() async throws {
        let model = StructuralComponentModel()
        let capture = StructuralComponentBindingCapture()
        let fixture = StructuralComponentWindow(
            StructuralComponentParent(model: model) {
                Color.red.frame(width: 10, height: 10).accessibilityIdentifier("before")
                StructuralComponentEmptyOwner(showsContent: model.showsContent, capture: capture)
                Color.blue.frame(width: 10, height: 10).accessibilityIdentifier("after")
            })
        defer { fixture.close() }
        let before = try fixture.node("before")
        let after = try fixture.node("after")
        let binding = try XCTUnwrap(capture.binding)

        XCTAssertEqual(try fixture.node("stack").children.count, 2)
        XCTAssertEqual(after.resolvedFrame.minY - before.resolvedFrame.minY, 17, accuracy: 0.000_001)
        XCTAssertTrue(fixture.nodes("empty.value").isEmpty)

        binding.wrappedValue = 7
        fixture.flush()
        XCTAssertEqual(capture.lastValue, 7, "An owner with zero emitted nodes must remain mounted.")
        XCTAssertEqual(try fixture.node("stack").children.count, 2)
        XCTAssertEqual(after.resolvedFrame.minY - before.resolvedFrame.minY, 17, accuracy: 0.000_001)

        model.showsContent = true
        fixture.flush()

        XCTAssertEqual(try fixture.node("empty.value").text, "7")
        XCTAssertEqual(try fixture.node("stack").children.count, 3)
        XCTAssertTrue(try fixture.node("before") === before)
        XCTAssertTrue(try fixture.node("after") === after)
        XCTAssertEqual(after.resolvedFrame.minY - before.resolvedFrame.minY, 34, accuracy: 0.000_001)
    }

    func testOptionalAndConditionalForwardChildrenWithoutResettingFollowingState() async throws {
        let model = StructuralComponentModel()
        let capture = StructuralComponentBindingCapture()
        let fixture = StructuralComponentWindow(
            StructuralComponentParent(model: model) {
                let optional: StructuralComponentPairBody? =
                    model.showsContent ? StructuralComponentPairBody(prefix: "optional") : nil
                let conditional = _ConditionalContent<StructuralComponentPairBody, StructuralComponentPairBody>(
                    storage: model.usesFirst
                        ? .trueContent(StructuralComponentPairBody(prefix: "conditional"))
                        : .falseContent(StructuralComponentPairBody(prefix: "conditional")))
                optional
                conditional
                StructuralComponentEmptyOwner(showsContent: true, capture: capture)
            })
        defer { fixture.close() }
        let following = try fixture.node("empty.value")
        let followingIdentity = try XCTUnwrap(following.retainedViewIdentity)
        let branch = try fixture.node("conditional.first")
        let branchIdentity = try XCTUnwrap(branch.retainedViewIdentity)
        XCTAssertEqual(try fixture.node("stack").children.count, 3)

        let binding = try XCTUnwrap(capture.binding)
        binding.wrappedValue = 9
        fixture.flush()
        model.showsContent = true
        fixture.flush()

        XCTAssertEqual(try fixture.node("stack").children.count, 5)
        XCTAssertTrue(try fixture.node("conditional.first") === branch)
        XCTAssertTrue(try fixture.node("empty.value") === following)
        XCTAssertEqual(following.text, "9")

        model.usesFirst = false
        fixture.flush()

        let otherBranch = try fixture.node("conditional.first")
        XCTAssertFalse(otherBranch === branch)
        XCTAssertNotEqual(otherBranch.retainedViewIdentity, branchIdentity)
        XCTAssertTrue(try fixture.node("empty.value") === following)
        XCTAssertEqual(following.retainedViewIdentity, followingIdentity)
        XCTAssertEqual(following.text, "9")

        model.showsContent = false
        fixture.flush()

        XCTAssertTrue(fixture.nodes("optional.first").isEmpty)
        XCTAssertEqual(try fixture.node("stack").children.count, 3)
        XCTAssertTrue(try fixture.node("empty.value") === following)
        XCTAssertEqual(following.text, "9")
    }

    func testReErasedReusedBodyHasSeparateFlatOccurrences() async throws {
        let source = AnyView(StructuralComponentPairBody())
        let fixture = StructuralComponentWindow(
            VStack(alignment: .leading, spacing: 7) {
                source
                AnyView(AnyView(source))
            }
            .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let children = try fixture.node("stack").children

        XCTAssertEqual(children.count, 4)
        XCTAssertEqual(
            children.compactMap(\.accessibilityIdentifier), ["pair.first", "pair.second", "pair.first", "pair.second"])
        let identities = try children.map { try XCTUnwrap($0.retainedViewIdentity) }
        XCTAssertEqual(Set(identities).count, 4)
        for (first, second) in zip(children, children.dropFirst()) {
            XCTAssertEqual(second.resolvedFrame.minY - first.resolvedFrame.minY, 17, accuracy: 0.000_001)
        }
    }

    func testGroupAndErasedForEachRowsRemainDirectStackChildren() async throws {
        var deletedIndices: [Int] = []
        let fixture = StructuralComponentWindow(
            VStack(alignment: .leading, spacing: 7) {
                Group { StructuralComponentPairBody() }
                AnyView(
                    ForEach([1, 2], id: \.self) { index in
                        Text("Row \(index)").frame(width: 10, height: 10)
                            .accessibilityIdentifier("row.\(index)")
                    }
                    .onDelete { deletedIndices = Array($0) })
            }
            .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let children = try fixture.node("stack").children

        XCTAssertEqual(children.count, 4)
        XCTAssertEqual(children.compactMap(\.accessibilityIdentifier), ["pair.first", "pair.second", "row.1", "row.2"])
        XCTAssertEqual(try fixture.node("row.1").nodeTag, "1#0")
        XCTAssertEqual(try fixture.node("row.2").nodeTag, "2#0")
        let secondRow = try fixture.node("row.2")
        XCTAssertEqual(secondRow.dynamicContentIndex, 1)
        XCTAssertNotNil(secondRow.onDeleteRows)
        secondRow.onDeleteRows?(IndexSet(integer: 1))
        XCTAssertEqual(deletedIndices, [1])
        for (first, second) in zip(children, children.dropFirst()) {
            XCTAssertEqual(second.resolvedFrame.minY - first.resolvedFrame.minY, 17, accuracy: 0.000_001)
        }
    }

    func testFrameMaterializesOneChildAtTheExplicitBoundary() async throws {
        let fixture = StructuralComponentWindow(
            VStack(alignment: .leading, spacing: 7) {
                StructuralComponentPairBody()
                    .frame(width: 40, height: 30)
                    .accessibilityIdentifier("boundary")
                Color.green.frame(width: 10, height: 10)
                    .accessibilityIdentifier("after")
            }
            .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let stack = try fixture.node("stack")
        let boundary = try fixture.node("boundary")
        let after = try fixture.node("after")
        let first = try fixture.node("pair.first")
        let second = try fixture.node("pair.second")

        XCTAssertEqual(stack.children.count, 2)
        XCTAssertTrue(stack.children.first === boundary)
        XCTAssertTrue(stack.children.last === after)
        XCTAssertEqual(boundary.resolvedFrame.size, Size(width: 40, height: 30))
        XCTAssertEqual(after.resolvedFrame.minY - boundary.resolvedFrame.minY, 37, accuracy: 0.000_001)
        XCTAssertTrue(fixture.contains(first, within: boundary))
        XCTAssertTrue(fixture.contains(second, within: boundary))
        XCTAssertFalse(stack.children.contains { $0 === first || $0 === second })
    }

    func testIdentityAndAccessibilityDecorationRemainOneNodeBoundary() async throws {
        let fixture = StructuralComponentWindow(
            VStack(alignment: .leading, spacing: 7) {
                StructuralComponentPairBody()
                    .id("aggregate")
                    .accessibilityIdentifier("aggregate")
                Color.green.frame(width: 10, height: 10)
                    .accessibilityIdentifier("after")
            }
            .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let stack = try fixture.node("stack")
        let aggregate = try fixture.node("aggregate")

        XCTAssertEqual(stack.children.count, 2)
        XCTAssertTrue(stack.children.first === aggregate)
        XCTAssertEqual(aggregate.nodeTag, "aggregate")
        XCTAssertTrue(fixture.contains(try fixture.node("pair.first"), within: aggregate))
        XCTAssertTrue(fixture.contains(try fixture.node("pair.second"), within: aggregate))
        XCTAssertNotEqual(try fixture.node("pair.first").nodeTag, "aggregate")
        XCTAssertNotEqual(try fixture.node("pair.second").nodeTag, "aggregate")
    }

    func testListSelectionAndForEachEditWrappersRemainSingleRows() async throws {
        var selected: String? = "pair"
        var deletedIndices: [Int] = []
        let selection = Binding<String?>(get: { selected }, set: { selected = $0 })
        let fixture = StructuralComponentWindow(
            List(selection: selection) {
                StructuralComponentPairBody().id("pair").tag("pair")
                ForEach([1, 2], id: \.self) { index in
                    Text("Row \(index)").tag(String(index))
                }
                .onDelete { deletedIndices = Array($0) }
            }
            .accessibilityIdentifier("list"))
        defer { fixture.close() }
        let list = try fixture.node("list")
        let content = try XCTUnwrap(list.children.first { $0.retainedLazyListAdapter != nil })
        let rows = content.children.filter { $0.nodeTag != nil }

        XCTAssertEqual(rows.compactMap(\.nodeTag), ["pair", "1#0", "2#0"])
        let second = try XCTUnwrap(rows.first { $0.nodeTag == "2#0" })
        XCTAssertEqual(second.children.count, 1)
        let editableContent = try XCTUnwrap(second.children.first)
        XCTAssertEqual(editableContent.dynamicContentIndex, 1)
        XCTAssertNotNil(second.onActivate)
        XCTAssertNotNil(editableContent.onDeleteRows)
        second.onActivate?()
        XCTAssertEqual(selected, "2")
        editableContent.onDeleteRows?(IndexSet(integer: 1))
        XCTAssertEqual(deletedIndices, [1])
    }

    func testGeometryReadersInStructuralBodyUseTheirAssignedStackSlots() async throws {
        let fixture = StructuralComponentWindow(
            VStack(alignment: .leading, spacing: 7) {
                StructuralComponentGeometryPairBody()
            }
            .accessibilityIdentifier("stack"))
        defer { fixture.close() }
        let stack = try fixture.node("stack")
        let first = try fixture.node("geometry.first.slot")
        let second = try fixture.node("geometry.second.slot")
        let firstReader = try XCTUnwrap(first.children.first)
        let secondReader = try XCTUnwrap(second.children.first)

        XCTAssertEqual(stack.children.count, 2)
        XCTAssertTrue(stack.children.first === first)
        XCTAssertTrue(stack.children.last === second)
        XCTAssertEqual(first.resolvedFrame.size, Size(width: 80, height: 24))
        XCTAssertEqual(second.resolvedFrame.size, Size(width: 120, height: 36))
        XCTAssertEqual(firstReader.resolvedFrame.size, first.resolvedFrame.size)
        XCTAssertEqual(secondReader.resolvedFrame.size, second.resolvedFrame.size)
        XCTAssertEqual(firstReader.geometryReaderBuiltSize, first.resolvedFrame.size)
        XCTAssertEqual(secondReader.geometryReaderBuiltSize, second.resolvedFrame.size)
        XCTAssertEqual(try fixture.node("geometry.first.value").text, "80 X 24")
        XCTAssertEqual(try fixture.node("geometry.second.value").text, "120 X 36")
        XCTAssertEqual(second.resolvedFrame.minY - first.resolvedFrame.minY, 31, accuracy: 0.000_001)
        XCTAssertEqual(second.resolvedFrame.minX, first.resolvedFrame.minX, accuracy: 0.000_001)
    }
}

private struct StructuralComponentGeometryPairBody: View {
    @ViewBuilder
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

private struct StructuralComponentPairBody: View {
    let prefix: String

    init(prefix: String = "pair") { self.prefix = prefix }

    @ViewBuilder
    var body: some View {
        Color.red.frame(width: 10, height: 10)
            .accessibilityIdentifier("\(prefix).first")
        Color.blue.frame(width: 10, height: 10)
            .accessibilityIdentifier("\(prefix).second")
    }
}

@MainActor
private final class StructuralComponentModel: ObservableObject {
    @Published var revision = 0
    @Published var scheme = ColorScheme.dark
    @Published var showsContent = false
    @Published var usesFirst = true
}

private struct StructuralComponentParent: View {
    @ObservedObject private var model: StructuralComponentModel
    private let events: StructuralComponentEvents?
    private let content: @MainActor () -> [AnyView]

    init(
        model: StructuralComponentModel, events: StructuralComponentEvents? = nil,
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
private final class StructuralComponentEvents {
    var parentBuilds = 0
    var overrideBuilds = 0
    var entries: [String] = []

    func reset() {
        parentBuilds = 0
        overrideBuilds = 0
        entries.removeAll()
    }

    func assertOneUpdateAndBodyPerParentBuild(
        scheme: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThan(parentBuilds, 0, file: file, line: line)
        XCTAssertEqual(entries.count, parentBuilds * 2, file: file, line: line)
        for index in stride(from: 0, to: entries.count, by: 2) {
            XCTAssertEqual(
                Array(entries[index..<min(index + 2, entries.count)]),
                ["update:\(scheme)", "body:\(scheme):1"], file: file, line: line)
        }
    }
}

@MainActor
private struct StructuralComponentEnvironmentProperty: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    private let events: StructuralComponentEvents
    private var updatedScheme: String?
    private var updates = 0

    init(events: StructuralComponentEvents) { self.events = events }

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

private struct StructuralComponentStatePair: View {
    @State private var count: Int
    private var probe: StructuralComponentEnvironmentProperty

    init(seed: Int, events: StructuralComponentEvents) {
        _count = State(initialValue: seed)
        probe = StructuralComponentEnvironmentProperty(events: events)
    }

    @ViewBuilder
    var body: some View {
        let label = probe.recordBody()
        Text("\(count):\(label)").accessibilityIdentifier("state.value")
        Button("Increment") { count += 1 }
            .accessibilityIdentifier("state.increment")
    }
}

private struct StructuralComponentOverride: View {
    typealias Body = Never
    @State private var count: Int
    @Environment(\.colorScheme) private var scheme
    private let events: StructuralComponentEvents

    init(seed: Int, events: StructuralComponentEvents) {
        _count = State(initialValue: seed)
        self.events = events
    }

    var body: Never { fatalError("StructuralComponentOverride uses makeComponent") }

    func makeComponent(context: ViewBuildContext) -> Component {
        events.overrideBuilds += 1
        let schemeName = scheme == .dark ? "dark" : "light"
        return Group {
            Text("\(count):\(schemeName)").accessibilityIdentifier("override.value")
            Button("Increment override") { count += 1 }
                .accessibilityIdentifier("override.increment")
        }
        .makeComponent(context: context)
    }
}

@MainActor
private final class StructuralComponentBindingCapture {
    var binding: Binding<Int>?
    var lastValue = -1

    func store(_ binding: Binding<Int>, value: Int) {
        self.binding = binding
        lastValue = value
    }
}

private struct StructuralComponentEmptyOwner: View {
    @State private var count = 0
    let showsContent: Bool
    let capture: StructuralComponentBindingCapture

    @ViewBuilder
    var body: some View {
        let _ = capture.store($count, value: count)
        if showsContent {
            Text(String(count)).accessibilityIdentifier("empty.value")
                .frame(width: 10, height: 10)
        }
    }
}

@MainActor
private final class StructuralComponentWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init<Content: View>(_ content: Content) {
        let configuration = WindowGroupConfiguration(
            title: "Structural components", size: IntSize(width: 320, height: 240), clearColor: .black,
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

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes(identifier)
        XCTAssertEqual(matches.count, 1, "Expected one node identified as \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func contains(_ node: ViewNode, within ancestor: ViewNode) -> Bool {
        descendants(in: ancestor).contains { $0 === node }
    }

    func activate(_ identifier: String) throws {
        let identified = try node(identifier)
        let control = try XCTUnwrap(descendants(in: identified).first { $0.isFocusable && $0.onActivate != nil })
        runtime.requestFocus(control)
        XCTAssertTrue(runtime.focusedNode === control)
        host.window(window, keyDown: KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    private func descendants(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(in: $0) }
    }
}
