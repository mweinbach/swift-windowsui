import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedOutlineGroupStateTests: XCTestCase {
    func testExplicitRootKeysPreserveStateAndNodesAcrossReorderDespiteMatchingDescriptions() async throws {
        let first = OutlineStateItem(1, "first", seed: 10, identifiableID: 0)
        let second = OutlineStateItem(2, "second", seed: 20, identifiableID: 0)
        let third = OutlineStateItem(3, "third", seed: 30, identifiableID: 0)
        let model = OutlineStateModel(items: [first, second, third])
        let capture = OutlineStateCapture()
        let fixture = OutlineStateWindow(
            OutlineStateParent(model: model) {
                OutlineGroup(model.items, id: \.key, children: \.children) { item in
                    OutlineStateRow(item: item, capture: capture)
                }
            })
        defer { fixture.close() }
        let firstNode = try fixture.node("first.value")
        let secondNode = try fixture.node("second.value")
        XCTAssertEqual(first.id, second.id, "The explicitly supplied key path must override Identifiable.id")
        XCTAssertEqual(first.key.description, second.key.description)
        XCTAssertNotEqual(
            try XCTUnwrap(firstNode.retainedViewIdentity), try XCTUnwrap(secondNode.retainedViewIdentity))

        try fixture.activate("first.increment")
        try fixture.activate("first.increment")
        try fixture.activate("second.increment")
        fixture.flush()
        model.items = [third, first, second]
        fixture.flush()

        XCTAssertEqual(fixture.valueIdentifiers, ["third.value", "first.value", "second.value"])
        try fixture.assertText("12", "first.value")
        try fixture.assertText("21", "second.value")
        try fixture.assertText("30", "third.value")
        XCTAssertTrue(try fixture.node("first.value") === firstNode)
        XCTAssertTrue(try fixture.node("second.value") === secondNode)
        XCTAssertEqual(try capture.binding("first").wrappedValue, 12)
        XCTAssertEqual(try capture.binding("second").wrappedValue, 21)
    }

    func testSameChildKeyUnderDifferentParentsHasIndependentMountedState() async throws {
        let north = OutlineStateItem(
            1, "north", children: [OutlineStateItem(7, "north.child", seed: 10)])
        let south = OutlineStateItem(
            2, "south", children: [OutlineStateItem(7, "south.child", seed: 20)])
        let root = OutlineStateItem(0, "root", children: [north, south])
        let model = OutlineStateModel(items: [root])
        let capture = OutlineStateCapture()
        let fixture = OutlineStateWindow(
            OutlineStateParent(model: model) {
                OutlineGroup(model.items[0], id: \.key, children: \.children) { item in
                    OutlineStateRow(item: item, capture: capture)
                }
            })
        defer { fixture.close() }
        // Nested bodies are eagerly built by the existing OutlineGroup even
        // when their nodes are collapsed. These bindings come from that host build.
        let northBinding = try capture.binding("north.child")
        let southBinding = try capture.binding("south.child")
        XCTAssertEqual(northBinding.wrappedValue, 10)
        XCTAssertEqual(southBinding.wrappedValue, 20)

        northBinding.wrappedValue = 41
        fixture.flush()
        XCTAssertEqual(southBinding.wrappedValue, 20)
        southBinding.wrappedValue = 82
        fixture.flush()
        model.items = [OutlineStateItem(0, "root", children: [south, north])]
        model.revision += 1
        fixture.flush()

        XCTAssertEqual(northBinding.wrappedValue, 41)
        XCTAssertEqual(southBinding.wrappedValue, 82)
        XCTAssertEqual(try capture.binding("north.child").wrappedValue, 41)
        XCTAssertEqual(try capture.binding("south.child").wrappedValue, 82)
        northBinding.wrappedValue = 42
        fixture.flush()
        XCTAssertEqual(try capture.binding("north.child").wrappedValue, 42)
        XCTAssertEqual(try capture.binding("south.child").wrappedValue, 82)
        XCTAssertEqual(try capture.binding("north").wrappedValue, 0)
        XCTAssertEqual(try capture.binding("south").wrappedValue, 0)
        XCTAssertEqual(try capture.binding("root").wrappedValue, 0)

        // Put the same branches at the root so their collapsed row containers
        // are visible, without relying on any expansion-state persistence.
        let branchModel = OutlineStateModel(items: [north, south])
        let branchCapture = OutlineStateCapture()
        let branchFixture = OutlineStateWindow(
            OutlineStateParent(model: branchModel) {
                OutlineGroup(branchModel.items, id: \.key, children: \.children) { item in
                    OutlineStateRow(item: item, capture: branchCapture)
                }
            })
        defer { branchFixture.close() }
        let northRow = try branchFixture.branchRow(containing: "north.increment")
        let southRow = try branchFixture.branchRow(containing: "south.increment")
        XCTAssertNotEqual(northRow.retainedViewIdentity, southRow.retainedViewIdentity)

        branchModel.items = [south, north]
        branchFixture.flush()

        XCTAssertEqual(branchFixture.valueIdentifiers, ["south.value", "north.value"])
        XCTAssertTrue(try branchFixture.branchRow(containing: "north.increment") === northRow)
        XCTAssertTrue(try branchFixture.branchRow(containing: "south.increment") === southRow)
    }

    func testDuplicateSiblingKeysUseIndependentOccurrencesRatherThanFlattenedPositions() async throws {
        let first = OutlineStateItem(7, "duplicate-a", seed: 10)
        let second = OutlineStateItem(7, "duplicate-b", seed: 20)
        let other = OutlineStateItem(9, "other", seed: 30)
        let model = OutlineStateModel(items: [first, second, other])
        let capture = OutlineStateCapture()
        let fixture = OutlineStateWindow(
            OutlineStateParent(model: model) {
                OutlineGroup(model.items, children: \.children) { item in
                    OutlineStateRow(item: item, capture: capture)
                }
            })
        defer { fixture.close() }
        let firstNode = try fixture.node("duplicate-a.value")
        let secondNode = try fixture.node("duplicate-b.value")
        XCTAssertNotEqual(
            try XCTUnwrap(firstNode.retainedViewIdentity), try XCTUnwrap(secondNode.retainedViewIdentity))
        try fixture.activate("duplicate-a.increment")
        try fixture.activate("duplicate-b.increment")
        try fixture.activate("duplicate-b.increment")
        fixture.flush()
        model.items = [other, first, second]
        fixture.flush()

        try fixture.assertText("11", "duplicate-a.value")
        try fixture.assertText("22", "duplicate-b.value")
        try fixture.assertText("30", "other.value")
        XCTAssertTrue(try fixture.node("duplicate-a.value") === firstNode)
        XCTAssertTrue(try fixture.node("duplicate-b.value") === secondNode)

        // Equal IDs have ordinal identity within their parent. Swapping only
        // their authored labels keeps State at the first and second occurrences.
        model.items = [other, second, first]
        fixture.flush()

        try fixture.assertText("11", "duplicate-b.value")
        try fixture.assertText("22", "duplicate-a.value")
        XCTAssertTrue(try fixture.node("duplicate-b.value") === firstNode)
        XCTAssertTrue(try fixture.node("duplicate-a.value") === secondNode)
    }

    func testFreshSingleRootAndRowValuesKeepPrivateStateAcrossParentRebuildsAndNewSeeds() async throws {
        let model = OutlineStateModel(items: [])
        let capture = OutlineStateCapture()
        let fixture = OutlineStateWindow(
            OutlineStateParent(model: model) {
                OutlineGroup(
                    OutlineStateItem(1, "fresh", seed: 100 + model.revision), children: \.children
                ) { item in
                    OutlineStateRow(item: item, capture: capture)
                }
            })
        defer { fixture.close() }
        let original = try fixture.node("fresh.value")
        let binding = try capture.binding("fresh")
        try fixture.activate("fresh.increment")
        fixture.flush()
        try fixture.assertText("101", "fresh.value")
        let previousBuilds = capture.bodyBuilds["fresh", default: 0]

        model.revision = 800
        fixture.flush()

        XCTAssertGreaterThan(capture.bodyBuilds["fresh", default: 0], previousBuilds)
        try fixture.assertText("101", "fresh.value")
        XCTAssertEqual(binding.wrappedValue, 101)
        XCTAssertTrue(try fixture.node("fresh.value") === original)
        try fixture.activate("fresh.increment")
        fixture.flush()
        try fixture.assertText("102", "fresh.value")
        XCTAssertEqual(binding.wrappedValue, 102)
    }
}

private struct OutlineStateKey: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "shared" }
}

private struct OutlineStateItem: Identifiable {
    let id: OutlineStateKey
    let key: OutlineStateKey
    let name: String
    let seed: Int
    let children: [OutlineStateItem]?
    init(
        _ key: Int, _ name: String, seed: Int = 0, identifiableID: Int? = nil,
        children: [OutlineStateItem]? = nil
    ) {
        self.id = OutlineStateKey(value: identifiableID ?? key)
        self.key = OutlineStateKey(value: key)
        self.name = name
        self.seed = seed
        self.children = children
    }
}

@MainActor
private final class OutlineStateModel: ObservableObject {
    @Published var items: [OutlineStateItem]
    @Published var revision = 0

    init(items: [OutlineStateItem]) {
        self.items = items
    }
}

private struct OutlineStateParent: View {
    @ObservedObject private var model: OutlineStateModel
    private let content: @MainActor () -> [AnyView]

    init(model: OutlineStateModel, @ViewBuilder content: @escaping @MainActor () -> [AnyView]) {
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
private final class OutlineStateCapture {
    var bindings: [String: Binding<Int>] = [:]
    var bodyBuilds: [String: Int] = [:]

    func binding(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Binding<Int> {
        try XCTUnwrap(bindings[name], "Expected an installed binding for \(name)", file: file, line: line)
    }
}

private struct OutlineStateRow: View {
    @State private var count: Int
    let name: String
    let capture: OutlineStateCapture

    init(item: OutlineStateItem, capture: OutlineStateCapture) {
        _count = State(initialValue: item.seed)
        self.name = item.name
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
private final class OutlineStateWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }
    var valueIdentifiers: [String] {
        descendants(in: runtime.root).compactMap(\.accessibilityIdentifier).filter { $0.hasSuffix(".value") }
    }

    init<Content: View>(_ content: Content) {
        let configuration = WindowGroupConfiguration(
            title: "Mounted outline", size: IntSize(width: 640, height: 640), clearColor: .black,
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

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = descendants(in: runtime.root).filter { $0.accessibilityIdentifier == identifier }
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

    func branchRow(
        containing identifier: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        var ancestor = try node(identifier, file: file, line: line).parent
        while let current = ancestor {
            if let identity = current.retainedViewIdentity,
                let last = identity.segments.last,
                case .occurrence(_) = last,
                identity.segments.contains(.role(.row))
            {
                return current
            }
            ancestor = current.parent
        }
        return try XCTUnwrap(
            nil as ViewNode?, "Expected a typed OutlineGroup branch row above \(identifier)", file: file, line: line)
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
